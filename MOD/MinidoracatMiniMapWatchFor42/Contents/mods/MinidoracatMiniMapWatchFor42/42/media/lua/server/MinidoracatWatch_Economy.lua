-- MinidoracatWatch_Economy.lua：Economy 付費槽位的伺服器端（Phase 6；Economy 選用整合，不 require=、不 require Economy）。
-- 規格：主 MOD docs/plan-minimap-watch-economy.md；範本：車輛管理 MinidoracatVehicleManager_Economy.lua／_PaidSlots.lua。
--   - 開服偵測一次（OnServerStarted）：OFF（單機）／ABSENT（沒裝）／UNSUPPORTED（缺 API rev 2 的 entitlements、rentals、
--     setPlan 能力）／FAILED（註冊失敗）／READY。不是 READY 時「經濟系統」的槽位改用解鎖卡（W.slotMode）。
--   - 一個付費槽位一個 instant 產品（W.productOf）。第三方槽位帶 freezeWhenAbsent（Economy API rev 4＋CAPABILITIES.freeze）：
--     提供槽位的 MOD 被移除時租約凍結、不扣租金，裝回來接著算。舊版 Economy 沒有凍結：開服時把「認得、這次沒人登記」
--     的第三方產品照樣註冊，方案全關（不賣、不允許自動續租＝不扣款）；租約照絕對時間走（已知界線）。
--   - 方案只來自沙盒（使用者裁定）：開服與每 5 秒比對，變了才 setPlan（內容相同 Economy 回 updated=false，冪等）。
--   - 有效＝買斷，或租約 active／paused_* 且還沒到期（W.payEval；寬限＝自動續租重試時間，視為停用）。
--     權益快取到「最早的到期時間」或 60 秒；Economy 變更通知時以通知帶的快照更新。到期不等 Economy 的排程通知。
--   - 每秒比對每位在線玩家的有效槽位，變了才推 pay（本人、小型摘要）；客戶端第一個 tick 送 payReq 補要一次。
--   - 不自己扣款（自動續租只走 Economy 排程，否則會重複扣）；權益以 W.account 的帳號名查（綁帳號，分割畫面副座位＝無）。
-- MP 客戶端也會載入 media/lua/server（GameLoadingState.java:148），所以先以 isClient() 早退。
if isClient() then return end
require "MinidoracatWatch"
require "MinidoracatWatch_Pay"
local W = MinidoracatWatchCore

local Econ = { status = "OFF", src = nil, freeze = false, error = nil, slotByProduct = {}, productBySlot = {}, absent = {} }
W.Econ = Econ
Econ.KNOWN = "MinidoracatWatchPaid" -- 全域 ModData：[productId] = slotId（看過的第三方槽位，只增不改；舊版 Economy 的缺席偵測）
Econ.TTL_MS = 60000
Econ.RETRY_MS = 10000
Econ.TICK_MS = 1000
Econ.PLAN_MS = 5000
Econ.REASON_CODES = { "entitlement_purchase", "entitlement_renewal", "entitlement_refund" }
Econ.CURRENCIES = { "survivor", "cat" } -- 沙盒 PayCurrency 1／2（Economy EC.CURRENCY_ORDER）
-- 沙盒預設價（照設計稿 data.mjs PRICES）；只在沙盒讀不到時用
Econ.PRICE = { ext = { 60, 400 }, adv = { 150, 1200 }, core = { 300, 2400 }, addon = { 80, 600 } }
-- Economy 第一次看到產品時用的方案：兩種販售都關，開服立刻用沙盒覆蓋
Econ.DEFAULTS = {
    permanentEnabled = false, permanentCurrency = "survivor", permanentPrice = 400, permanentLimit = 1,
    rentalEnabled = false, rentalCurrency = "survivor", rentalPrice = 60, rentalLimit = 1, rentalDays = 7,
    graceHours = 24, reminderHours = 24, autoRenewAllowed = false,
}

-- Economy server facade；回 api, 能不能凍結。舊版、缺能力回 nil
function Econ.api()
    local api = MinidoracatEconomy and MinidoracatEconomy.v1
    local caps = api and api.CAPABILITIES
    if api and api.API_MAJOR == 1 and (api.API_REVISION or 0) >= 2 and type(caps) == "table"
        and caps.entitlements == true and caps.rentals == true and caps.setPlan == true
        and type(api.registerSource) == "function" then
        return api, (api.API_REVISION or 0) >= 4 and caps.freeze == true
    end
    return nil
end

local cache = {}     -- [帳號] = { [productId] = { v, untilMs, exp } }
local pushed = {}    -- [productId] = 上次成功 setPlan 的方案簽名
local planErr = {}   -- [productId] = 上次 log 過的錯誤
local lastSig = {}   -- [IsoPlayer] = 上次推給他的摘要簽名
local lastTick, lastPlan = nil, nil
local readErrAt = {}

local function setStatus(s)
    Econ.status = s
    W.econStatus = s
    W.invalidate()
end

local function failed(err)
    Econ.src, Econ.error = nil, tostring(err)
    setStatus("FAILED")
    W.log("Economy paid slots unavailable: " .. Econ.error .. ". Economy slots use unlock cards.")
end

local function intIn(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    return math.max(lo, math.min(hi, math.floor(v)))
end

-- 沙盒 → 12 欄方案。該級不是經濟系統（或第三方產品缺席）：兩種販售與自動續租全關（Economy 就不賣、不扣款，
-- 已付期間照舊）；不刪產品或權益，改回經濟系統就恢復。價格至少 1（Economy 範圍）。
-- 第三方槽位：設定檔 addonSlots 有這個槽位時，買斷／租用開關與價格以它為準（沒寫的欄位照沙盒 SlotAddon*）。
function Econ.planValues(slot, absent)
    local key = W.SLOT_MODE_KEY[slot.tier] or W.SLOT_MODE_KEY.addon -- 缺席的第三方產品是孤立假槽位
    local econ = not absent and W.slotModeValue(slot) == 3
    local d = Econ.PRICE[slot.tier] or Econ.PRICE.addon
    local cur = Econ.CURRENCIES[W.sandbox("PayCurrency", 1)] or "survivor"
    local e = slot.tier == "addon" and W.addonSlotCfg(slot.id) or nil
    local function pick(field, suffix, default)
        if e and e[field] ~= nil then return e[field] end
        return W.sandbox(key .. suffix, default)
    end
    return {
        permanentEnabled = econ and pick("buy", "Buy", true) ~= false,
        permanentCurrency = cur, permanentPrice = intIn(pick("buyPrice", "BuyPrice", d[2]), 1, 1e9, d[2]), permanentLimit = 1,
        rentalEnabled = econ and pick("rent", "Rent", true) ~= false,
        rentalCurrency = cur, rentalPrice = intIn(pick("rentPrice", "RentPrice", d[1]), 1, 1e9, d[1]), rentalLimit = 1,
        rentalDays = intIn(W.sandbox("PayRentDays", 7), 1, 365, 7),
        graceHours = intIn(W.sandbox("PayRetryHours", 24), 0, 168, 24),
        reminderHours = intIn(W.sandbox("PayReminderHours", 24), 0, 168, 24),
        autoRenewAllowed = econ and W.sandbox("PayAutoRenew", true) ~= false,
    }
end

local PLAN_ORDER = { "permanentEnabled", "permanentCurrency", "permanentPrice", "permanentLimit", "rentalEnabled",
    "rentalCurrency", "rentalPrice", "rentalLimit", "rentalDays", "graceHours", "reminderHours", "autoRenewAllowed" }
local function planSig(v)
    local parts = {}
    for i, k in ipairs(PLAN_ORDER) do parts[i] = tostring(v[k]) end
    return table.concat(parts, "|")
end
local TERMS = { rentalPrice = true, rentalCurrency = true, rentalDays = true }

-- 方案推送（開服與每 5 秒）：簽名變了才 setPlan。not_ready＝Economy 的世界資料還沒載入，下輪再試；
-- 其他錯誤 log 一次、下輪照樣重試。改了租金、幣別或天數：已同意的自動續租暫停、要玩家重新同意（Economy 的設計，D3），
-- log 並提醒在線管理員（開服後第一次推送不提醒：那時沒有管理員在線上改設定）；世界第一次從 defaults 換成沙盒值不算。
function Econ.pushPlans()
    if Econ.status ~= "READY" then return end
    for pid, slot in pairs(Econ.slotByProduct) do
        local values = Econ.planValues(slot, Econ.absent[pid])
        local sig = planSig(values)
        if pushed[pid] ~= sig then
            local okP, cur = pcall(Econ.src.getPlan, pid)
            local first = okP and type(cur) == "table" and type(cur.lastChange) == "table" and cur.lastChange.origin == "defaults"
            local ok, res = pcall(Econ.src.setPlan, pid, values, { actor = "watch", origin = "source", reason = "sandbox" })
            if ok and type(res) == "table" and res.ok == true then
                local terms = false
                for _, f in ipairs(type(res.changed) == "table" and res.changed or {}) do
                    if TERMS[f] then terms = true end
                end
                if res.updated and terms and not first then
                    W.log("Economy plan " .. pid .. ": rental price, currency or days changed; auto-renew consents pause until players agree again")
                    if pushed[pid] ~= nil then sendServerCommand(W.MODULE, W.CMD_PLAN_WARN, { slot = slot.id }) end
                end
                pushed[pid], planErr[pid] = sig, nil
            else
                local err = ok and type(res) == "table" and (tostring(res.error) .. (res.field and ("/" .. tostring(res.field)) or ""))
                    or tostring(res)
                if err ~= "not_ready" and planErr[pid] ~= err then
                    planErr[pid] = err
                    W.log("Economy setPlan " .. pid .. " failed: " .. err)
                end
            end
        end
    end
end

-- 權益快取的一筆：讀取失敗時沿用上次的有效值到它原本的到期時間，沒有就無效；10 秒後再讀
local function entryOf(env, now, old, name, pid)
    local v, untilMs = nil, nil
    if type(env) == "table" and env.ok == true then v, untilMs = W.payEval(env.entitlement, now) end
    if v == nil then
        if readErrAt[pid] == nil or now < readErrAt[pid] or now - readErrAt[pid] >= 60000 then
            readErrAt[pid] = now
            W.log("Economy getEntitlement failed product=" .. pid .. " owner=" .. tostring(name) .. ": "
                .. tostring(type(env) == "table" and env.error or env))
        end
        if old and old.v and old.untilMs and old.untilMs > now then
            return { v = true, untilMs = old.untilMs, exp = math.min(old.untilMs, now + Econ.RETRY_MS) }
        end
        return { v = false, exp = now + Econ.RETRY_MS }
    end
    return { v = v, untilMs = untilMs, exp = v and math.min(untilMs, now + Econ.TTL_MS) or (now + Econ.TTL_MS) }
end

local function byAccount(name)
    local t = cache[name]
    if not t then
        t = {}
        cache[name] = t
    end
    return t
end

-- W.payValid 的伺服器端：這位玩家（帳號）的這個槽位現在有沒有效
function Econ.valid(player, slot)
    if Econ.status ~= "READY" then return false end
    local pid = Econ.productBySlot[slot.id]
    local name = pid and W.account(player)
    if not name then return false end
    local now = getTimestampMs()
    local t = byAccount(name)
    local e = t[pid]
    if not e or now >= e.exp then
        local ok, env = pcall(Econ.src.getEntitlement, name, pid)
        e = entryOf(ok and env or tostring(env), now, e, name, pid)
        t[pid] = e
    end
    return e.v
end

-- Economy 的變更通知（同一來源所有產品共用一個監聽）：帶的快照就是提交後的權益
function Econ.onChanged(username, productId, env)
    if type(username) ~= "string" or not Econ.slotByProduct[productId] then return end
    local t = byAccount(username)
    t[productId] = entryOf(env, getTimestampMs(), t[productId], username, productId)
    W.invalidate()
end

-- 這個帳號用解鎖卡開過這個槽位（任一驗證鍵；Economy 只給登入名，W.account 要玩家物件）
-- ponytail: 不分驗證鍵，同名的 no-steam／Steam 紀錄都算；要分時改由 validatePurchase 帶玩家物件
local function cardUnlocked(username, slotId)
    local byKey = ModData.getOrCreate(W.UNLOCK_TABLE)[username]
    if type(byKey) ~= "table" then return false end
    for _, slots in pairs(byKey) do
        if type(slots) == "table" and slots[slotId] == true then return true end
    end
    return false
end

-- 購買驗證（Economy 付款與自動續租扣款前呼叫）：回 true 或 false, 原因碼（客戶端 IGUI_MinidoracatWatch_PayReason_<碼>）。
-- D5：已買斷不能租；租約開著自動續租時不能買斷（請先關閉，免得買斷後還被續租扣款）。不以「已經有效」拒絕（續租本來就要能付）。
-- 已經用解鎖卡開過（也接受解鎖卡）：永久有效，任何付款（含自動續租）都拒絕，免得付了沒有用的錢。
function Econ.validatePurchase(username, productId, kind, quantity, projected)
    local slot = Econ.slotByProduct[productId]
    if not slot or Econ.absent[productId] then return false, "UNKNOWN_SLOT" end
    if W.slotModeValue(slot) ~= 3 then return false, "MODE_NOT_ECONOMY" end
    if W.slotCardAlso(slot) and cardUnlocked(username, slot.id) then return false, "CARD_UNLOCKED" end
    if kind == "rental" and type(projected) == "table" and (tonumber(projected.permanent) or 0) >= 1 then
        return false, "HAVE_PERMANENT"
    end
    if kind == "permanent" then
        local ok, env = pcall(Econ.src.getEntitlement, username, productId)
        local ent = ok and type(env) == "table" and env.entitlement
        if type(ent) ~= "table" or type(ent.rentals) ~= "table" then return false, "READ_FAILED" end
        for _, r in ipairs(ent.rentals) do
            if type(r) == "table" and r.autoRenew == true then return false, "RENTING_AUTO_ON" end
        end
    end
    return true
end

-- 註冊一個產品；標準槽失敗＝整個整合 FAILED，第三方槽位失敗只 log、那個槽位不賣
local function register(src, pid, slot, nameKey, freeze)
    local spec = { id = pid, nameKey = nameKey, instant = true, defaults = Econ.DEFAULTS,
        validatePurchase = Econ.validatePurchase, freezeWhenAbsent = freeze or nil }
    local ok, res = pcall(src.registerProduct, spec)
    if ok and type(res) == "table" and res.ok == true then
        Econ.slotByProduct[pid] = slot
        Econ.productBySlot[slot.id] = pid
        return true
    end
    local err = ok and type(res) == "table" and (tostring(res.error) .. "/" .. tostring(res.field)) or tostring(res)
    if slot.tier ~= "addon" then failed(err); return false end
    W.log("Economy product " .. pid .. " (slot " .. slot.id .. ") not registered: " .. err)
    return true
end

local function addonNameKey(slot)
    local k = slot.name
    if type(k) == "string" and #k <= 96 and not k:find("%c") then return k end
    return "IGUI_MinidoracatWatch_Product_addon"
end

-- 開服偵測一次（Economy 允許在它的 ModData 載入前註冊；setPlan 另外重試）。第三方槽位要在檔案載入時登記才有產品。
function Econ.init()
    Econ.src, Econ.error, Econ.freeze = nil, nil, false
    Econ.slotByProduct, Econ.productBySlot, Econ.absent = {}, {}, {}
    cache, pushed, planErr, lastSig = {}, {}, {}, {}
    if not isServer() then return setStatus("OFF") end
    if MinidoracatEconomy == nil then return setStatus("ABSENT") end
    local api, freeze = Econ.api()
    if api == nil then
        W.log("Economy found without entitlement API rev 2 (rentals, setPlan): Economy slots use unlock cards")
        return setStatus("UNSUPPORTED")
    end
    Econ.freeze = freeze
    local currencies = {}
    for id in pairs(MinidoracatEconomy.CURRENCIES or {}) do currencies[#currencies + 1] = id end
    local ok, src, err = pcall(api.registerSource, { modId = W.ECON_SOURCE, nameKey = "IGUI_MinidoracatWatch_SourceName",
        displayName = { EN = "Minimap Watch" }, currencies = currencies, reasonCodes = Econ.REASON_CODES })
    if not ok then return failed(src) end
    if type(src) ~= "table" or type(src.registerProduct) ~= "function" or type(src.getEntitlement) ~= "function"
        or type(src.setPlan) ~= "function" then
        return failed(err or "no_entitlement_methods")
    end
    local known = ModData.getOrCreate(Econ.KNOWN)
    for _, slot in ipairs(W.slotList) do
        if slot.tier ~= "std" then
            local pid = W.productOf(slot.id)
            local owner = Econ.slotByProduct[pid] and Econ.slotByProduct[pid].id
            if owner == nil and slot.tier == "addon" and type(known[pid]) == "string" and known[pid] ~= slot.id then
                owner = known[pid]
            end
            if owner then
                W.log("Economy product " .. pid .. " of slot " .. slot.id .. " is already slot " .. owner .. ": not sold")
            elseif slot.tier == "addon" then
                register(src, pid, slot, addonNameKey(slot), freeze)
                known[pid] = slot.id
            elseif not register(src, pid, slot, "IGUI_MinidoracatWatch_Product_" .. slot.tier) then
                return
            end
        end
    end
    -- 舊版 Economy（沒有凍結）：認得、這次沒人登記的第三方產品照樣註冊並把方案全關（不賣、不扣自動續租）
    if not freeze then
        for pid, sid in pairs(known) do
            if type(sid) == "string" and not W.slotById[sid] and not Econ.slotByProduct[pid] then
                local fake = W.orphanSlot(sid)
                if register(src, pid, fake, "IGUI_MinidoracatWatch_Product_addon") and Econ.slotByProduct[pid] then
                    Econ.absent[pid] = true
                end
            end
        end
    end
    if type(src.onEntitlementChanged) == "function" then
        local okC, errC = pcall(src.onEntitlementChanged, Econ.onChanged)
        if not okC then return failed(errC) end
    end
    Econ.src = src
    setStatus("READY")
    W.log("Economy paid slots registered (" .. W.ECON_SOURCE .. ", freeze=" .. tostring(freeze) .. ")")
    Econ.pushPlans()
end

-- 推給這位玩家的摘要：Economy 狀態＋目前有效的「經濟系統」槽位
local function summary(player)
    local slots, parts = {}, { Econ.status }
    for _, slot in ipairs(W.slotList) do
        if W.slotMode(slot) == "econ" and Econ.valid(player, slot) then
            slots[slot.id] = true
            parts[#parts + 1] = slot.id
        end
    end
    return slots, table.concat(parts, ",")
end

-- 每秒：方案（每 5 秒）＋每位在線玩家的有效槽位，變了才推並讓狀態快取失效（到期在 1 秒內停用，不等 Economy 的排程）。
-- 掛 OnTickEvenPaused：沒人在線時伺服器暫停、OnTick 不跑，Economy 的自動續租照跑。
function Econ.tick()
    local now = getTimestampMs()
    if lastTick and now >= lastTick and now - lastTick < Econ.TICK_MS then return end
    lastTick = now
    if not lastPlan or now < lastPlan or now - lastPlan >= Econ.PLAN_MS then
        lastPlan = now
        Econ.pushPlans()
    end
    local players = getOnlinePlayers()
    local nextSig = {}
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local slots, sig = summary(p)
        nextSig[p] = sig
        if lastSig[p] ~= sig then
            W.invalidate()
            sendServerCommand(p, W.MODULE, W.CMD_PAY, { to = p:getUsername(), econ = Econ.status, slots = slots })
        end
    end
    lastSig = nextSig
end

-- 客戶端載入完成後補要一次（伺服器第一次送的時候客戶端可能還在載入）：清掉簽名，下一秒重送
Events.OnClientCommand.Add(function(module, command, player)
    if module == W.MODULE and command == W.CMD_PAY_REQ and player then lastSig[player] = nil end
end)
Events.OnServerStarted.Add(Econ.init)
Events.OnTickEvenPaused.Add(Econ.tick)
