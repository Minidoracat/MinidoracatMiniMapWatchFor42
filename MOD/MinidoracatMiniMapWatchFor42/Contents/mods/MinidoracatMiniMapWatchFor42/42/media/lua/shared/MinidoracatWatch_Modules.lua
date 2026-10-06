-- MinidoracatWatch_Modules.lua（shared）：模組與槽位登記、對外 API、模組狀態快取、功能閘門決策、
-- 安裝／拆下與解鎖卡（伺服器／單機的唯一突變點）。
--
-- 資料模型
--   錶的 modData[SLOTS_KEY] = { [slotId] = { id = 模組 id, item = 模組物品完整類型, md = 模組物品 modData 的複本或 nil } }
--     模組跟著錶走（交易、換手時 ISClothingExtraAction 整份複製 modData）；安裝＝物品離開背包、紀錄進錶，
--     拆下＝紀錄離開錶、以同類型建回物品並還原 modData（物品數量守恆）。
--   解鎖紀錄：伺服器全域 ModData[UNLOCK_TABLE][W.seenKey(player)] = { [slotId] = true }。
--     綁帳號（username, playerNum），換戴別支錶也能用；玩家 modData 會被客戶端整表覆蓋
--     （ObjectModDataPacket.java:50-71），全域 ModData 客戶端改不到（GlobalModDataPacket.java:45-56）。
--     MP 客戶端只拿到自己的那份（登入與變更時由伺服器送，W.clientUnlocks）。
-- 由 MinidoracatWatch.lua 結尾 require（shared 依檔名順序先載入核心）；這裡不反向 require，免得 Kahlua 警告 recursive require。
local W = MinidoracatWatchCore

W.SLOTS_KEY = "MinidoracatWatchSlots"
W.UNLOCK_TABLE = "MinidoracatWatchUnlocks"
W.CMD_MODULE = "module"
W.CMD_UNLOCK = "unlock"
W.CMD_UNLOCKS_REQ = "unlocksReq"
W.CMD_UNLOCKS = "unlocks"

W.RULE_MODULE = "module"
W.CLASSES = { standard = true, advanced = true, core = true }
W.MAX_ADDON_SLOTS = 6 -- 面板「其他 MOD」那一列放得下的數量

W.FAIL_MODULE = "IGUI_MinidoracatWatch_ModuleFailed"
W.FAIL_SCREWDRIVER = "IGUI_MinidoracatWatch_NeedScrewdriver"
W.FAIL_SLOT_INVALID = "IGUI_MinidoracatWatch_SlotNotOpen"
W.FAIL_SLOT_FULL = "IGUI_MinidoracatWatch_SlotFull"
W.FAIL_SLOT_EMPTY = "IGUI_MinidoracatWatch_SlotEmpty"
W.FAIL_CLASS = "IGUI_MinidoracatWatch_SlotWrongClass"
W.FAIL_UNLOCK = "IGUI_MinidoracatWatch_UnlockFailed"
W.FAIL_UNLOCKED = "IGUI_MinidoracatWatch_AlreadyUnlocked"
for _, k in ipairs({ W.FAIL_MODULE, W.FAIL_SCREWDRIVER, W.FAIL_SLOT_INVALID, W.FAIL_SLOT_FULL, W.FAIL_SLOT_EMPTY,
        W.FAIL_CLASS, W.FAIL_UNLOCK, W.FAIL_UNLOCKED }) do
    W.FAIL_KEYS[k] = true
end

W.REASON_FEATURE_OFF = "IGUI_MinidoracatWatch_Reason_FeatureOff"
W.REASON_NEED_WATCH = "IGUI_MinidoracatWatch_Reason_NeedWatch"
W.REASON_PAUSED = "IGUI_MinidoracatWatch_Reason_Paused"

-- ===== 沙盒 =====
-- 功能規則：1 不需要錶、2 戴錶就能用、3 需要模組（預設，照設計稿 FEATURE_RULES）、4 關閉
local RULE_BY_VALUE = { W.RULE_FREE, W.RULE_WATCH, W.RULE_MODULE, W.RULE_OFF }
W.FEATURE_RULE_KEY = { arrow = "RuleArrow", poi = "RulePoi", nav = "RuleNav", share = "RuleShare",
    scan = "RuleScan", zombie = "RuleZombie" }
function W.featureRule(feature)
    local key = W.FEATURE_RULE_KEY[feature]
    if not key then return W.RULE_FREE end
    return RULE_BY_VALUE[W.sandbox(key, 3)] or W.RULE_MODULE
end

-- 槽位開啟方式：1 免費開放、2 解鎖卡、3 經濟系統、4 不開放。經濟系統在 Phase 6 之前一律當解鎖卡。
-- 預設照設計稿 DEFAULT_ADMIN：擴充／進階／核心＝經濟系統，其他 MOD 的槽位＝免費。
local SLOT_MODE_KEY = { ext = "SlotExt", adv = "SlotAdv", core = "SlotCore", addon = "SlotAddon" }
function W.slotMode(slot)
    local key = SLOT_MODE_KEY[slot.tier]
    if not key then return "free" end
    local v = W.sandbox(key, slot.tier == "addon" and 1 or 3)
    if v == 1 then return "free" end
    if v == 4 then return "off" end
    return "card"
end

function W.needScrewdriver() return W.sandbox("NeedScrewdriver", true) ~= false end

function W.radius(key, default)
    local r = tonumber(W.sandbox(key, default))
    if not r or r ~= r or r < 1 then return default end
    return r
end

-- ===== 登記 =====
W.modules, W.moduleList, W.moduleByItem, W.watchers = {}, {}, {}, {}
W.slotList, W.slotById = {}, {}

local function validId(id)
    return type(id) == "string" and #id <= 32 and id:match("^[%a][%w_]*$") ~= nil
end
local function finite(n, lo, hi) return type(n) == "number" and n == n and n >= lo and n <= hi end

local function reject(what, def, why)
    local id = type(def) == "table" and def.id or nil
    W.log(what .. " rejected (" .. tostring(id) .. "): " .. why)
    return false
end

-- 驗證失敗整筆拒收（fail closed）、記 log 一次；欄位複製進內部表，不留呼叫端的 table
local function registerModule(def)
    if type(def) ~= "table" then return reject("registerWatchModule", def, "def is not a table") end
    if not validId(def.id) then return reject("registerWatchModule", def, "bad id") end
    if W.modules[def.id] then return reject("registerWatchModule", def, "duplicate id") end
    if type(def.name) ~= "string" or def.name == "" then return reject("registerWatchModule", def, "bad name") end
    if not W.CLASSES[def.class] then return reject("registerWatchModule", def, "bad class") end
    if not finite(def.drain, 0, 1000) then return reject("registerWatchModule", def, "bad drain") end
    if type(def.item) ~= "string" or not def.item:match("^[%w_]+%.[%w_]+$") then
        return reject("registerWatchModule", def, "bad item")
    end
    if W.moduleByItem[def.item] then return reject("registerWatchModule", def, "item already used") end
    if def.onStateChanged ~= nil and type(def.onStateChanged) ~= "function" then
        return reject("registerWatchModule", def, "bad onStateChanged")
    end
    local m = { id = def.id, name = def.name, class = def.class, drain = def.drain, item = def.item,
        onStateChanged = def.onStateChanged }
    W.modules[m.id] = m
    W.moduleList[#W.moduleList + 1] = m
    W.moduleByItem[m.item] = m
    if m.onStateChanged then W.watchers[#W.watchers + 1] = m end
    return true
end

local function addSlot(id, name, tier, accepts, price)
    local set = {}
    for _, c in ipairs(accepts) do set[c] = true end
    local s = { id = id, name = name, tier = tier, accepts = set, acceptsList = accepts, price = price }
    W.slotList[#W.slotList + 1] = s
    W.slotById[id] = s
    return s
end

local addonSlots = 0
local function registerSlot(def)
    if type(def) ~= "table" then return reject("registerWatchSlot", def, "def is not a table") end
    if not validId(def.id) then return reject("registerWatchSlot", def, "bad id") end
    if W.slotById[def.id] then return reject("registerWatchSlot", def, "duplicate id") end
    if type(def.name) ~= "string" or def.name == "" then return reject("registerWatchSlot", def, "bad name") end
    if type(def.accepts) ~= "table" or #def.accepts == 0 then return reject("registerWatchSlot", def, "bad accepts") end
    local accepts = {}
    for i, c in ipairs(def.accepts) do
        if not W.CLASSES[c] then return reject("registerWatchSlot", def, "bad accepts") end
        accepts[i] = c
    end
    local p = def.price
    if type(p) ~= "table" or not finite(p.rent, 0, 1e9) or not finite(p.days, 1, 3650) or not finite(p.buy, 0, 1e9) then
        return reject("registerWatchSlot", def, "bad price")
    end
    if addonSlots >= W.MAX_ADDON_SLOTS then return reject("registerWatchSlot", def, "too many slots") end
    addonSlots = addonSlots + 1
    addSlot(def.id, def.name, "addon", accepts, { rent = p.rent, days = p.days, buy = p.buy })
    W.invalidate()
    return true
end

-- ===== 內建：槽位與模組（名稱／類別／耗電照設計稿 data.mjs MODULES；照明是 Phase 8）=====
local STD = { "standard" }
addSlot("std1", "IGUI_MinidoracatWatch_Slot_std1", "std", STD)
addSlot("std2", "IGUI_MinidoracatWatch_Slot_std2", "std", STD)
addSlot("std3", "IGUI_MinidoracatWatch_Slot_std3", "std", STD)
addSlot("ext", "IGUI_MinidoracatWatch_Slot_ext", "ext", STD, { rent = 60, days = 7, buy = 400 })
addSlot("adv", "IGUI_MinidoracatWatch_Slot_adv", "adv", { "standard", "advanced" }, { rent = 150, days = 7, buy = 1200 })
addSlot("core", "IGUI_MinidoracatWatch_Slot_core", "core", { "standard", "advanced", "core" },
    { rent = 300, days = 7, buy = 2400 })

-- feature＝這個模組開放的功能（沒有＝不對應功能，例如節能核心）；drainKey＝耗電的沙盒選項
W.BUILTIN = {}
local BUILTIN = {
    { "compass", "Compass", "standard", 10, "arrow" },
    { "ledger", "Ledger", "standard", 10, "poi" },
    { "gps", "GPS", "standard", 25, "nav" },
    { "comm", "Comm", "standard", 25, "share" },
    { "scan", "Scan", "standard", 25, "scan" },
    { "detect", "Detect", "standard", 50, "zombie" },
    { "mildetect", "MilDetect", "advanced", 50, "zombie" },
    { "longcomm", "LongComm", "advanced", 25, "share" },
    { "relay", "Relay", "core", 25, "share" },
    { "eco", "Eco", "core", 0, nil },
}
for _, b in ipairs(BUILTIN) do
    registerModule({ id = b[1], name = "IGUI_MinidoracatWatch_Module_" .. b[1], class = b[3], drain = b[4],
        item = "MinidoracatWatch.Module_" .. b[2] })
    W.BUILTIN[b[1]] = { feature = b[5], drainKey = "Drain" .. b[2] }
end
-- 每個功能由哪些模組提供（順序＝缺模組時提示哪一個）
W.PROVIDERS = { arrow = { "compass" }, poi = { "ledger" }, nav = { "gps" }, share = { "comm", "longcomm", "relay" },
    scan = { "scan" }, zombie = { "detect", "mildetect" } }

W.CARD_TYPES = { ext = "MinidoracatWatch.UnlockCard_Ext", adv = "MinidoracatWatch.UnlockCard_Adv",
    core = "MinidoracatWatch.UnlockCard_Core", addon = "MinidoracatWatch.UnlockCard_Ext" }
function W.cardType(slot) return W.CARD_TYPES[slot.tier] end

-- 模組耗電（%）：內建模組讀沙盒，第三方用它自己的建議值（管理員調整是 Phase 4 的伺服器設定檔）
function W.moduleDrain(def)
    local b = W.BUILTIN[def.id]
    if not b then return def.drain end
    local v = tonumber(W.sandbox(b.drainKey, def.drain))
    if not v or v ~= v or v < 0 then return def.drain end
    return v
end

-- ===== 解鎖紀錄 =====
W.clientUnlocks = {} -- MP 客戶端：[username] = { [slotId] = true }（伺服器送來的）

-- 鍵沿用 W.seenKey＝username .. "|" .. playerNum：playerNum 只有數字，最後一個 | 就是分隔，
-- 不同 (帳號, playerNum) 不會撞成同一鍵；帳號原樣存（無損），不消毒不截斷。
function W.unlocksOf(player)
    if isClient() then return W.clientUnlocks[player:getUsername()] end
    return ModData.getOrCreate(W.UNLOCK_TABLE)[W.seenKey(player)] -- ModData.java:20
end

function W.isUnlocked(player, slotId)
    local t = W.unlocksOf(player)
    return type(t) == "table" and t[slotId] == true
end

function W.slotValid(player, slot)
    if slot.orphan then return false end
    local mode = W.slotMode(slot)
    if mode == "free" then return true end
    if mode == "off" then return false end
    return W.isUnlocked(player, slot.id)
end

-- ===== 錶上的模組 =====
function W.slotsOf(watch)
    if not watch or not watch:hasModData() then return nil end
    local t = watch:getModData()[W.SLOTS_KEY]
    if type(t) ~= "table" then return nil end
    return t
end

-- 槽位紀錄（只認得出形狀的；壞資料當空槽）
function W.slotRecord(watch, slotId)
    local slots = W.slotsOf(watch)
    local rec = slots and slots[slotId]
    if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.item) ~= "string" then return nil end
    return rec
end

-- ===== 孤立槽位：提供槽位的 MOD 被移除（這次啟動沒有人登記這個 slotId），錶上還留著模組紀錄 =====
-- 使用者裁定：模組隨時能拆；槽位與付費權益凍結保留（紀錄與解鎖都不刪，MOD 裝回來就恢復）。
-- 孤立槽位一律無效：裡面的模組 paused、不耗電、不能再裝。模組類型也沒登記（提供模組的 MOD 也被移除）時
-- 拆不出物品（applyModuleChange 只建回已登記的類型），這種紀錄不列出、留在錶上。
-- 假槽位依 id 快取（不每次配置）；錶的 modData 是 KahluaTableImpl（LinkedHashMap），pairs 順序＝寫入順序。
local orphanById = {}
function W.orphanSlot(id)
    local s = orphanById[id]
    if not s then
        s = { id = id, name = "IGUI_MinidoracatWatch_Slot_orphan", tier = "orphan", orphan = true,
            accepts = {}, acceptsList = {} }
        orphanById[id] = s
    end
    return s
end

-- 這支錶上拆得下來的孤立槽位（使用者操作與面板掃描時呼叫，不在閘門熱路徑）
function W.orphanSlots(watch)
    local out = {}
    local slots = W.slotsOf(watch)
    if not slots then return out end
    for id in pairs(slots) do
        if type(id) == "string" and not W.slotById[id] then
            local rec = W.slotRecord(watch, id)
            if rec and W.moduleByItem[rec.item] then out[#out + 1] = W.orphanSlot(id) end
        end
    end
    return out
end

-- 錶的耗電倍率：Σ（有效槽位裡、功能沒被關閉的模組耗電%）；節能核心運作時整支錶減半（設計稿 fullRuntime）
function W.drainFactor(player, watch)
    local slots = W.slotsOf(watch)
    if not slots then return 1 end
    local pct, eco = 0, false
    for _, slot in ipairs(W.slotList) do
        local rec = slots[slot.id]
        local def = type(rec) == "table" and W.modules[rec.id]
        if def and W.slotValid(player, slot) then
            local b = W.BUILTIN[def.id]
            if not (b and b.feature and W.featureRule(b.feature) == W.RULE_OFF) then
                pct = pct + W.moduleDrain(def)
                if def.id == "eco" then eco = true end
            end
        end
    end
    local f = 1 + pct / 100
    if eco then f = f / 2 end
    return f
end

-- ===== 狀態快取（閘門與 getWatchModuleState 共用；熱路徑零配置）=====
-- 每位玩家一筆：生效的錶、錶上已知模組與其所在槽位是否有效。期限 1 秒；W.invalidate() 讓所有快取失效
-- （穿脫衣物、安裝／拆下、解鎖、登記槽位）。電量不快取：每次直接讀錶的 modData。
-- 模組清單用平行陣列（ids／states＋n）原地覆寫：不清表、不配置。
local STATUS_TTL_MS = 1000
local statusGen = 0
local statusCache = {}
function W.invalidate() statusGen = statusGen + 1 end
function W.clearStatus() statusCache = {} end

-- SyncClothing 先於物品封包到時，客戶端掛在身上的是臨時建的同 ID 物品（SyncClothingPacket.java:192-199），
-- 它沒有 modData；改讀背包裡同 ID 那件（穿著的物品仍在主背包，IsoGameCharacter.java:3427-3490）。
local function effectiveWatch(player)
    local item, count = W.wornWatch(player)
    if item then
        local real = player:getInventory():getItemWithID(item:getID()) -- ItemContainer.java:3112
        if real then item = real end
    end
    return item, count
end

function W.status(player)
    local now = getTimestampMs()
    local e = statusCache[player]
    if e and e.gen == statusGen and now >= e.at and now - e.at < STATUS_TTL_MS then return e end
    if not e then
        e = { ids = {}, states = {}, n = 0 }
        statusCache[player] = e
    end
    e.gen, e.at = statusGen, now
    local watch, count = effectiveWatch(player)
    e.watch, e.count = watch or false, count
    local n = 0
    local slots = W.slotsOf(watch)
    if slots then
        for _, slot in ipairs(W.slotList) do
            local rec = slots[slot.id]
            if type(rec) == "table" and W.modules[rec.id] then
                n = n + 1
                e.ids[n] = rec.id
                e.states[n] = W.slotValid(player, slot) and "active" or "paused"
            end
        end
        -- 孤立槽位裡的模組一律 paused（槽位凍結）
        for id, rec in pairs(slots) do
            if not W.slotById[id] and type(rec) == "table" and W.modules[rec.id] then
                n = n + 1
                e.ids[n] = rec.id
                e.states[n] = "paused"
            end
        end
    end
    e.n = n
    return e
end

-- 模組在這筆狀態裡：任一份 active＝"active"，否則有 paused＝"paused"，沒裝＝nil
function W.modState(e, id)
    local found = nil
    for i = 1, e.n do
        if e.ids[i] == id then
            if e.states[i] == "active" then return "active" end
            found = "paused"
        end
    end
    return found
end

local function powered(e)
    local c = e.watch and W.charge(e.watch) or nil
    return c ~= nil and c > 0
end

-- 優先序照規劃書 §1：disabled＞active＞notRequired＞unpowered＞paused＞missing。
-- 地圖錶系統關閉（Enabled=false）等同沒裝本 MOD：一律 notRequired（和小地圖規則一致，也不套功能規則）。
function W.moduleState(player, id)
    if type(id) ~= "string" or not W.modules[id] or player == nil then return "missing" end
    if not W.enabled() then return "notRequired" end
    local b = W.BUILTIN[id]
    local rule = b and b.feature and W.featureRule(b.feature) or W.RULE_MODULE
    if rule == W.RULE_OFF then return "disabled" end
    local e = W.status(player)
    local on = powered(e)
    local m = on and W.modState(e, id)
    if m == "active" then return "active" end
    if rule == W.RULE_FREE or (rule == W.RULE_WATCH and on) then return "notRequired" end
    if e.watch and not on then return "unpowered" end
    if m == "paused" then return "paused" end
    return "missing"
end

-- 功能閘門的決策（客戶端 gate 與面板功能清單共用）：回 allowed, reasonKey, maxDist。
-- 只有「需要模組」規則套用模組半徑；不需要錶／戴錶就能用時沿用主 MOD 自己的顯示距離。
-- 偵測模組只放行小地圖（surface ~= "world"）；軍規偵測兩種地圖都放行。
function W.featureDecision(player, feature, surface)
    local rule = W.featureRule(feature)
    if not W.enabled() or rule == W.RULE_FREE then return true end
    if rule == W.RULE_OFF then return false, W.REASON_FEATURE_OFF end
    local e = player and W.status(player)
    if not (e and e.watch) then return false, W.REASON_NEED_WATCH end
    local c = W.charge(e.watch)
    if c == nil then return false, W.REASON_NO_BATTERY end
    if c <= 0 then return false, W.REASON_DEAD end
    if rule == W.RULE_WATCH then return true end
    if feature == "zombie" then
        if W.modState(e, "mildetect") == "active" then return true, nil, W.radius("MilDetectRadius", 80) end
        if surface == "world" then
            if W.modState(e, "mildetect") == "paused" then return false, W.REASON_PAUSED end
            return false, "IGUI_MinidoracatWatch_Reason_Need_mildetect"
        end
        if W.modState(e, "detect") == "active" then return true, nil, W.radius("DetectRadius", 40) end
    else
        local list = W.PROVIDERS[feature]
        for i = 1, #list do
            if W.modState(e, list[i]) == "active" then
                if feature == "scan" then return true, nil, W.radius("ScanRadius", 60) end
                return true
            end
        end
    end
    local list = W.PROVIDERS[feature]
    for i = 1, #list do
        if W.modState(e, list[i]) == "paused" then return false, W.REASON_PAUSED end
    end
    return false, "IGUI_MinidoracatWatch_Reason_Need_" .. list[1]
end

-- onStateChanged：每秒比對一次（MP 伺服器在扣電迴圈、客戶端與單機在客戶端迴圈），只在狀態改變時呼叫
-- def.onStateChanged(player, newState, oldState)。第一次看到這位玩家時 oldState＝nil。拋錯只 log 一次。
local lastStates = {}
function W.pollStateCallbacks(player, key)
    if #W.watchers == 0 then return end
    local t = lastStates[key]
    if not t then
        t = {}
        lastStates[key] = t
    end
    for _, def in ipairs(W.watchers) do
        local s = W.moduleState(player, def.id)
        local old = t[def.id]
        if s ~= old then
            t[def.id] = s
            local ok, err = pcall(def.onStateChanged, player, s, old)
            if not ok and not def.errLogged then
                def.errLogged = true
                W.log("onStateChanged of module " .. def.id .. " failed: " .. tostring(err))
            end
        end
    end
end
function W.pruneStateCallbacks(keep) -- keep[key]=true 以外的玩家掉出去
    for k in pairs(lastStates) do if not keep[k] then lastStates[k] = nil end end
end

-- ===== 對外 API（shared；契約見 README「給其他 MOD 的 API」）=====
MinidoracatWatchAPI = MinidoracatWatchAPI or {}
local API = MinidoracatWatchAPI
API.watchApiVersion = 1
API.registerWatchModule = registerModule
API.registerWatchSlot = registerSlot
API.getWatchModuleState = W.moduleState

-- ===== 安裝／拆下（伺服器／單機的唯一突變點）=====
-- MP 由 server/MinidoracatWatch_Server.lua 在 OnClientCommand 內呼叫（player 是連線身分）；單機由計時動作直接呼叫。
-- 只收純量 watchId、slotId、install、itemId；錶與模組只從「這位玩家自己的背包樹」依 ID 重新解析
-- （getItemWithIDRecursiv＝ItemContainer.java:3094）。所有驗證都在第一個突變之前：失敗不留半套。
-- 拆下時只建回「已登記的模組物品類型」：錶的紀錄就算被改，也變不出其他物品；提供模組的 MOD 被移除時
-- （instanceItem 回 nil、或類型不再登記）拆不下來，模組留在錶上，不會被吃掉。
-- 孤立槽位（提供槽位的 MOD 被移除）只能拆、不能裝：slotId 沒登記時只接受格式合法的 id 與拆下。
-- 只複製純資料（字串／數字／布林／巢狀表），深度上限擋住循環參照。
function W.copyTable(t, depth)
    depth = depth or 0
    local out = {}
    for k, v in pairs(t) do
        local tk, tv = type(k), type(v)
        if tk == "string" or tk == "number" then
            if tv == "string" or tv == "number" or tv == "boolean" then
                out[k] = v
            elseif tv == "table" and depth < 8 then
                out[k] = W.copyTable(v, depth + 1)
            end
        end
    end
    return out
end

local function notBroken(item) return not item:isBroken() end
-- containsTagEvalRecurse(ItemTag, LuaClosure)＝ItemContainer.java:1166；ItemTag.SCREWDRIVER＝ItemTag.java:370
-- （原版用例 ISInventoryPaneContextMenu.lua:3791 的 getFirstTagEvalRecurse）
function W.hasScrewdriver(player)
    return player:getInventory():containsTagEvalRecurse(ItemTag.SCREWDRIVER, notBroken)
end

local function takeItem(player, item, container)
    player:removeFromHands(item)
    container:DoRemoveItem(item)
    -- 伺服器的 send* 只送封包、不動容器，所以先 DoRemoveItem（GameServer.java:2405-2421）
    if isServer() then sendRemoveItemFromContainer(container, item) end
end

function W.applyModuleChange(player, watchId, slotId, install, itemId)
    if isClient() then return false, W.FAIL_MODULE end
    if not W.isFiniteInt(watchId) or type(slotId) ~= "string" or type(install) ~= "boolean" then
        return false, W.FAIL_MODULE
    end
    if install and not W.isFiniteInt(itemId) then return false, W.FAIL_MODULE end
    local slot = W.slotById[slotId]
    if not slot and (install or not validId(slotId)) then return false, W.FAIL_MODULE end
    if not player or player:isDead() then return false, W.FAIL_MODULE end
    local inv = player:getInventory()
    if not inv then return false, W.FAIL_MODULE end
    local watch = inv:getItemWithIDRecursiv(watchId)
    if not W.isWatch(watch) then return false, W.FAIL_MODULE end
    if W.needScrewdriver() and not W.hasScrewdriver(player) then return false, W.FAIL_SCREWDRIVER end
    local rec = W.slotRecord(watch, slotId)

    if install then
        if not W.slotValid(player, slot) then return false, W.FAIL_SLOT_INVALID end
        local slots = W.slotsOf(watch)
        if slots and slots[slotId] ~= nil then return false, W.FAIL_SLOT_FULL end
        local item = inv:getItemWithIDRecursiv(itemId)
        local def = item and W.moduleByItem[item:getFullType()]
        if not def then return false, W.FAIL_MODULE end
        if not slot.accepts[def.class] then return false, W.FAIL_CLASS end
        local container = item:getContainer() -- InventoryItem.java:3840：實際所在的袋子
        if not container then return false, W.FAIL_MODULE end
        local md = item:hasModData() and W.copyTable(item:getModData()) or nil
        W.settleNow(player) -- 耗電倍率要變了：先把舊倍率下的耗電入帳
        -- 以下不再有失敗點
        takeItem(player, item, container)
        local wmd = watch:getModData()
        if type(wmd[W.SLOTS_KEY]) ~= "table" then wmd[W.SLOTS_KEY] = {} end
        wmd[W.SLOTS_KEY][slotId] = { id = def.id, item = def.item, md = md }
    else
        if not rec then return false, W.FAIL_SLOT_EMPTY end
        local def = W.moduleByItem[rec.item]
        if not def then return false, W.FAIL_MODULE end
        local item = instanceItem(def.item) -- LuaManager.java:5605
        if not item then return false, W.FAIL_MODULE end
        if type(rec.md) == "table" then
            local md = item:getModData()
            for k, v in pairs(W.copyTable(rec.md)) do md[k] = v end
        end
        W.settleNow(player)
        -- 以下不再有失敗點
        W.slotsOf(watch)[slotId] = nil
        inv:AddItem(item)
        if isServer() then sendAddItemToContainer(inv, item) end
    end
    W.invalidate()
    -- 只有伺服器能同步 modData（LuaManager.java:12326-12334；單機是 no-op）
    if isServer() then syncItemModData(player, watch) end
    return true
end

-- ===== 解鎖卡（伺服器／單機）=====
-- 只在開啟方式是「解鎖卡」（含 Phase 6 前的經濟系統）、而且還沒開啟時收卡：免費、不開放、已開啟一律拒絕，卡不會被吃。
function W.pushUnlocks(player)
    if not isServer() then return end
    sendServerCommand(player, W.MODULE, W.CMD_UNLOCKS, { to = player:getUsername(), slots = W.unlocksOf(player) or {} })
end

function W.applyUnlock(player, slotId, cardId)
    if isClient() then return false, W.FAIL_UNLOCK end
    if type(slotId) ~= "string" or not W.isFiniteInt(cardId) then return false, W.FAIL_UNLOCK end
    local slot = W.slotById[slotId]
    local want = slot and W.cardType(slot)
    if not want or not player or player:isDead() then return false, W.FAIL_UNLOCK end
    if W.slotMode(slot) ~= "card" then return false, W.FAIL_UNLOCK end
    if W.isUnlocked(player, slotId) then return false, W.FAIL_UNLOCKED end
    local inv = player:getInventory()
    local card = inv and inv:getItemWithIDRecursiv(cardId)
    if not card or card:getFullType() ~= want then return false, W.FAIL_UNLOCK end
    local container = card:getContainer()
    if not container then return false, W.FAIL_UNLOCK end
    -- 以下不再有失敗點
    takeItem(player, card, container)
    local all = ModData.getOrCreate(W.UNLOCK_TABLE)
    local key = W.seenKey(player)
    if type(all[key]) ~= "table" then all[key] = {} end
    all[key][slotId] = true
    W.invalidate()
    W.pushUnlocks(player)
    return true
end
