-- MinidoracatWatch_PayClient.lua：Economy 付費槽位的客戶端（Phase 6）——伺服器推來的有效槽位、面板的檢視區文字與按鈕、
-- 付款流程。付款照車輛管理 BillingWindow：全走 Economy 客戶端 facade（MinidoracatEconomy.v1.Client.Entitlements，
-- late bind、不 require）；先報價，報價金額與幣別等於確認頁才用同一張報價付款，不同（方案剛改）就不付款、確認頁換新價；
-- 付款逾時＝結果未知：鎖住這個產品的購買，只能「查詢購買結果」讀同一筆訂單，絕不重送、不換新報價。
-- 畫面只顯示伺服器回來的狀態（不樂觀更新）；槽位有不有效只看伺服器推來的 W.clientPay（Phase 6 規格 3.6）。
-- 時間是伺服器的 epoch ms，和本機時鐘的落差只影響顯示。
require "MinidoracatWatch_Client"
require "MinidoracatWatch_Pay"
local W, C = MinidoracatWatchCore, MinidoracatWatchClient
local SRC = W.ECON_SOURCE

local P = { orders = {}, busy = {}, msg = {}, sheet = nil, requested = {} }
C.Pay = P
local VIEW_MS = 250
local REQUEST_MS = 30000
P.MSG_MS = 15000 -- 結果訊息（付款完成、錯誤）在檢視區留多久

local function tbl(t) return type(t) == "table" and t or {} end
local function T(key, ...) return getText("IGUI_MinidoracatWatch_" .. key, ...) end

-- Economy 客戶端權益 facade；沒裝、舊版（rev < 2）或還是單一租約（沒有 rentals 能力）回 nil
function P.api()
    local EC = MinidoracatEconomy
    local CL = EC and EC.v1 and EC.v1.Client
    local caps = CL and CL.CAPABILITIES
    if CL and CL.API_MAJOR == 1 and (CL.API_REVISION or 0) >= 2 and type(caps) == "table"
        and caps.entitlements == true and caps.rentals == true and type(CL.Entitlements) == "table" then
        return CL.Entitlements
    end
    return nil
end

-- ===== 文字 =====
function P.reasonText(code)
    local key = "IGUI_MinidoracatWatch_PayReason_" .. tostring(code)
    local t = getText(key)
    if t ~= key then return t end
    local E = P.api()
    if E and E.errorText then return E.errorText(code) end
    return T("PayFailed")
end

function P.currencyName(id)
    local E = P.api()
    if E and E.currencyName then return E.currencyName(id) end
    return tostring(id)
end
function P.money(amount, cur) return T("Money", tostring(amount or 0), P.currencyName(cur)) end

-- 剩餘時間：不到一小時寫分鐘，整天只寫天數
function P.leftText(ms)
    if type(ms) ~= "number" or ms <= 0 then return T("PayMinutes", "0") end
    if ms < 3600000 then return T("PayMinutes", tostring(math.ceil(ms / 60000))) end
    local hours = math.ceil(ms / 3600000)
    local d = math.floor(hours / 24)
    local h = hours - d * 24
    if d > 0 and h == 0 then return T("PayDays", tostring(d)) end
    if d > 0 then return T("PayDaysHours", tostring(d), tostring(h)) end
    return T("PayHours", tostring(h))
end

-- ===== 伺服器推來的有效槽位與 Economy 狀態 =====
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= W.MODULE or type(args) ~= "table" then return end
    if command == W.CMD_PAY then
        if type(args.to) ~= "string" or type(args.slots) ~= "table" then return end
        local slots = {}
        for k, v in pairs(args.slots) do
            if type(k) == "string" and v == true then slots[k] = true end
        end
        W.clientPay[args.to] = slots
        if type(args.econ) == "string" then W.econStatus = args.econ end
        P.views = {}
        W.invalidate()
    elseif command == W.CMD_PLAN_WARN then
        -- 管理員改了租金、幣別或天數（D3）：提醒在線管理員，已同意自動續租的玩家要重新同意
        local slot = type(args.slot) == "string" and W.slotById[args.slot]
        local p = getSpecificPlayer(0)
        if slot and p and isAdmin() then C.toast(p, T("PlanTermsChanged", C.slotName(slot))) end
    end
end)

-- 客戶端第一個 tick 補要一次（伺服器第一次推的時候客戶端可能還在載入）
local asked, lastPoll = {}, nil
function P.poll()
    if not isClient() then return end
    local now = getTimestampMs()
    if lastPoll and now >= lastPoll and now - lastPoll < 1000 then return end
    lastPoll = now
    for pn = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(pn)
        if p and not asked[pn] then
            asked[pn] = true
            sendClientCommand(p, W.MODULE, W.CMD_PAY_REQ, {})
        end
    end
end
Events.OnTick.Add(P.poll)

-- ===== 一個槽位的權益檢視（Economy facade 的快取；250ms 重算一次）=====
-- 自動續租開著（取消送出中顯示關）
local function autoOn(r)
    if r.autoRenewState == "pending_off" then return false end
    return r.autoRenew == true or r.autoRenewState == "on" or r.autoRenewState == "pending_on"
end
local function termsDiffer(plan, t)
    return type(t) == "table" and (t.price ~= plan.rentalPrice or t.currency ~= plan.rentalCurrency or t.days ~= plan.rentalDays)
end
local function balance(env, cur)
    local b = type(env.balances) == "table" and env.balances[cur]
    return type(b) == "table" and tonumber(b.available) or 0
end

P.views = {}
function P.request(pid, now)
    local E = P.api()
    local at = P.requested[pid]
    if not E or (at and now >= at and now - at < REQUEST_MS) then return end
    P.requested[pid] = now
    E.requestState(SRC, pid)
end

function P.view(slot, now)
    now = now or getTimestampMs()
    local pid = W.productOf(slot.id)
    local v = P.views[pid]
    if v and now >= v.at and now - v.at < VIEW_MS then return v end
    v = { at = now, pid = pid }
    P.views[pid] = v
    local E = P.api()
    v.api = E ~= nil
    local env = E and E.getState(SRC, pid)
    if type(env) ~= "table" or env.ok == false then
        P.request(pid, now)
        return v
    end
    local plan, ent = tbl(env.plan), tbl(env.entitlement)
    v.ready, v.env, v.plan, v.ent = true, env, plan, ent
    v.available = env.available ~= false
    v.perm = (tonumber(ent.permanent) or 0) >= 1
    v.cur, v.days = plan.rentalCurrency, plan.rentalDays
    v.rentPrice = plan.rentalEnabled == true and plan.rentalPrice or nil
    v.buyPrice = plan.permanentEnabled == true and plan.permanentPrice or nil
    v.buyCur = plan.permanentCurrency
    v.autoAllowed = plan.rentalEnabled == true and plan.autoRenewAllowed == true
    v.bal, v.buyBal = balance(env, v.cur), balance(env, v.buyCur)
    local r = nil
    for _, x in ipairs(tbl(ent.rentals)) do
        if type(x) == "table" then r = x end -- rentalLimit 1：最多一張有效；取最新的
    end
    if r then
        v.rental, v.state = r, r.state
        v.left = type(r.paidUntil) == "number" and r.paidUntil - now or nil
        v.graceLeft = type(r.graceUntil) == "number" and r.graceUntil - now or nil
        v.autoOn = autoOn(r)
        v.consent = v.autoOn and termsDiffer(plan, r.autoTerms) and v.autoAllowed
        v.autoPaused = v.autoOn and (r.autoRenewState == "paused_terms" or r.autoRenewState == "paused_system" or v.consent)
        local n = ent.notice
        if type(n) == "table" and n.code == "renewal_failed" and (n.rental == nil or n.rental == r.id) then v.fail = n.error end
        v.short = math.max(0, (tonumber(r.quantity) or 1) * (tonumber(plan.rentalPrice) or 0) - v.bal)
    end
    return v
end

-- 付款鎖：處理中、或有結果未知的訂單時不能再買
function P.canPay(v)
    return v.api and v.ready and v.available and not P.busy[v.pid] and P.orders[v.pid] == nil
end

-- 「經濟系統」槽位的租約到期而且槽位空著（面板 lapsed）
function P.lapsed(slot)
    if W.slotMode(slot) ~= "econ" then return false end
    local v = P.view(slot)
    return v.rental ~= nil and not v.perm
end

-- ===== 檢視區：文字與按鈕（面板每 250ms 重算一次）=====
-- 回 nil＝不是付費相關的槽位；否則 { lines = { { 文字, 顏色 token }... }, buttons = { { id, 標題, 可按 }... },
-- chip＝狀態字鍵（St_<chip>）, keep＝保留面板原本的按鈕（解鎖卡）}
-- 顏色是面板 theme 的 token（MinidoracatWatch_Skins.lua）：警示、錯誤、次要、內文
local GOLD, RED, DIM, WHITE = "warnText", "errorText", "textMuted", "text"
local function line(ui, text, col)
    ui.lines[#ui.lines + 1] = { text, col or WHITE }
end
-- 按鈕 { id, 標題, 可按, 樣式 }；樣式是 UI 框架 Button 的 style（設計稿：租用、付款、同意、到期後的續租是主要按鈕）
local PRIMARY = { pay = true, rent = true, agree = true }
local function button(ui, id, title, enabled, style)
    ui.buttons[#ui.buttons + 1] = { id, title, enabled ~= false, style or (PRIMARY[id] and "primary" or "normal") }
end

local SHEET_TITLE = { permanent = "PaySheet_permanent", rental = "PaySheet_rental", renew = "PaySheet_renew",
    auto = "PaySheet_auto" }
function P.sheetMoney(v, s)
    if s.kind == "permanent" then return v.buyPrice or v.plan.permanentPrice, v.buyCur, v.buyBal end
    local q = s.kind == "renew" and v.rental and tonumber(v.rental.quantity) or 1
    return (tonumber(v.plan.rentalPrice) or 0) * q, v.cur, v.bal
end

local function sheetUi(ui, v, slot, s)
    local name = C.slotName(slot)
    line(ui, T(SHEET_TITLE[s.kind], name, tostring(v.days)))
    local amount, cur, bal = P.sheetMoney(v, s)
    if s.kind == "auto" then
        line(ui, T("PaySheetAuto", P.money(amount, cur), tostring(v.days), tostring(v.plan.graceHours or 0)), DIM)
        button(ui, "pay", T("PayBtnAgreeConfirm"), not P.busy[v.pid])
    else
        line(ui, T("PaySheetAmount", P.money(amount, cur)))
        line(ui, T("PaySheetBalance", P.money(bal, cur)), DIM)
        local short = amount - bal
        if short > 0 then line(ui, T("PaySheetShort", P.money(short, cur)), RED) end
        if s.notice then line(ui, T("PayPriceChanged"), GOLD) end
        button(ui, "pay", T("PayBtnPay"), P.canPay(v) and short <= 0)
        if s.kind == "rental" and v.autoAllowed then
            button(ui, "sheetAuto", T("PayBtnSheetAuto", T(s.auto and "PayOn" or "PayOff")), not P.busy[v.pid])
        end
    end
    button(ui, "cancel", T("PayBtnCancel"), P.busy[v.pid] ~= "quote" and P.busy[v.pid] ~= "purchase")
end

-- 有效、或租約到期的槽位：租用中（剩餘、自動續租）、買斷、到期與重試
local function leaseUi(ui, v, slot, valid, rec)
    local r = v.rental
    if v.perm then
        ui.chip = "active"
        line(ui, T("PayBought"))
        return
    end
    local renewTitle = v.rentPrice and (valid and T("PayBtnRenewShort", tostring(v.days))
        or T("PayBtnRenew", tostring(v.days), P.money(v.rentPrice, v.cur))) or nil
    if valid then
        ui.chip = "rent"
        line(ui, T("PayRenting", P.leftText(v.left), P.money(v.rentPrice or v.plan.rentalPrice, v.cur)))
        line(ui, T(v.autoOn and "PayAutoOn" or "PayAutoOff"), DIM)
    else
        ui.chip = rec and "paused" or "lapsed"
        line(ui, rec and T("PayLapsedModule", C.moduleName(rec.id)) or T("PayLapsed"), GOLD)
        if v.state == "grace" and v.autoOn and not v.autoPaused then
            local why = v.fail == "insufficient_funds" and T("PayFailFunds", P.currencyName(v.cur), tostring(v.short))
                or (v.fail and T("PayFailOther") or "")
            line(ui, why .. T("PayRetryWindow", P.leftText(v.graceLeft)), GOLD)
        elseif not v.consent then
            line(ui, T("PayRenewToRestore"), DIM)
        end
    end
    if v.consent then
        line(ui, T("PayNeedConsent"), GOLD)
    elseif v.autoPaused then
        line(ui, T("PayAutoPaused"), DIM)
    end
    if renewTitle and v.state ~= "frozen" then
        button(ui, "renew", renewTitle, P.canPay(v), valid and "normal" or "primary")
    end
    if v.consent then
        button(ui, "agree", T("PayBtnAgree"), not P.busy[v.pid])
    elseif v.autoOn then
        button(ui, "autoOff", T("PayBtnAutoOff"), not P.busy[v.pid])
    elseif v.autoAllowed and r.state ~= "expired" then
        button(ui, "autoOn", T("PayBtnAutoOn"), not P.busy[v.pid])
    end
    -- D5：租用中可以買斷，但租約開著自動續租時要先關閉（伺服器 validatePurchase 也擋）；到期後先續租，這裡不賣買斷
    if valid and v.buyPrice then
        button(ui, "buy", T("PayBtnBuy", P.money(v.buyPrice, v.buyCur)), P.canPay(v) and not v.autoOn)
        if v.autoOn then line(ui, T("PayBuyAutoOn"), DIM) end
    end
end

-- 還沒買過：租用／買斷
local function offerUi(ui, v, slot, rec)
    if rec then line(ui, T("Desc_Paused", C.slotName(slot)), GOLD) end
    if not v.rentPrice and not v.buyPrice then
        line(ui, T("PayNotSold", C.slotName(slot)), DIM)
        return
    end
    line(ui, T("PayAccountBound"), DIM)
    if v.rentPrice then
        button(ui, "rent", T("PayBtnRent", tostring(v.days), P.money(v.rentPrice, v.cur)), P.canPay(v))
    end
    if v.buyPrice then
        button(ui, "buy", T("PayBtnBuy", P.money(v.buyPrice, v.buyCur)), P.canPay(v))
    else
        button(ui, "buy", T("PayBtnBuyOff"), false)
        line(ui, T("PayNoBuy"), DIM)
    end
end

function P.ui(player, watch, slot)
    if slot.orphan then
        local v = P.view(slot)
        if v.state ~= "frozen" then return nil end
        local ui = { lines = {}, buttons = {} }
        line(ui, T("PayFrozen", P.leftText(v.left)), DIM)
        if watch and W.slotRecord(watch, slot.id) then button(ui, "remove", T("RemoveModule"), true) end
        return ui
    end
    if W.slotModeValue(slot) ~= 3 then return nil end
    local ui = { lines = {}, buttons = {} }
    if W.slotMode(slot) ~= "econ" then
        ui.keep = true
        line(ui, T("PayNoEcon"), DIM)
        return ui
    end
    local rec = watch and W.slotRecord(watch, slot.id)
    local valid = W.slotValid(player, slot)
    local v = P.view(slot)
    if not v.api then
        line(ui, T("PayNoClient"), DIM)
    elseif not v.ready then
        line(ui, T("PayLoading"), DIM)
    elseif P.sheet and P.sheet.pid == v.pid then
        sheetUi(ui, v, slot, P.sheet)
    elseif P.orders[v.pid] then
        line(ui, T("PayNoAnswer"), GOLD)
        button(ui, "check", T("PayBtnCheck"), not P.busy[v.pid])
    elseif v.perm or v.rental then
        leaseUi(ui, v, slot, valid, rec)
    elseif valid then
        ui.chip = "active"
    else
        offerUi(ui, v, slot, rec)
    end
    if P.busy[v.pid] then line(ui, T("PayBusy"), DIM) end
    local m = P.msg[v.pid]
    if m and getTimestampMs() - m[3] < P.MSG_MS then line(ui, m[1], m[2] and RED or WHITE) end
    if rec then
        button(ui, "remove", T("RemoveModule"), true)
    elseif valid then
        button(ui, "install", T("InstallModule"), true)
    end
    return ui
end

-- 錶面上方的橫幅：有模組的「經濟系統」槽位租約到期、自動續租還在重試（設計稿 banner grace）
function P.bannerText(player, watch)
    for _, slot in ipairs(W.slotList) do
        local rec = W.slotRecord(watch, slot.id)
        if rec and W.slotMode(slot) == "econ" and not W.slotValid(player, slot) then
            local v = P.view(slot)
            if v.state == "grace" and v.autoOn and not v.autoPaused then
                return T("BannerRetry", C.slotName(slot), C.moduleName(rec.id), P.leftText(v.graceLeft))
            end
        end
    end
    return nil
end

-- ===== 付款流程 =====
local function say(pid, text, bad)
    P.msg[pid] = text and { text, bad == true, getTimestampMs() } or nil
    P.views[pid] = nil
end
local function refuse(pid, why)
    P.busy[pid] = nil
    say(pid, P.reasonText(why or "invalid_args"), true)
end

function P.openSheet(slot, kind, rental)
    local pid = W.productOf(slot.id)
    P.sheet = { pid = pid, slot = slot, kind = kind, rental = rental, auto = false }
    say(pid, nil)
end

function P.closeSheet()
    local s = P.sheet
    if not s or P.busy[s.pid] == "quote" or P.busy[s.pid] == "purchase" then return end
    P.sheet = nil
    say(s.pid, nil)
end

-- 自動續租的同意或取消（rental 必填）；paidKey＝付款後替新租約送同意（同意失敗時一併說明付款已完成）
function P.sendAuto(pid, enabled, revision, termsRevision, rental, paidKey)
    local E = P.api()
    if E == nil or P.busy[pid] then return end
    P.busy[pid] = "auto"
    say(pid, nil)
    local function failed(text) say(pid, paidKey and T("PayPaidAutoFailed", text) or text, true) end
    local rid, why = E.setAutoRenew(SRC, pid, enabled, revision, termsRevision, function(res)
        P.busy[pid] = nil
        if res.unknown then
            E.requestState(SRC, pid)
            return failed(T("PayAutoUnknown"))
        end
        if not res.ok then return failed(P.reasonText(res.error)) end
        if P.sheet and P.sheet.pid == pid and P.sheet.kind == "auto" then P.sheet = nil end
        say(pid, paidKey and T(paidKey) or T(enabled and "PayAutoOnDone" or "PayAutoOffDone"))
    end, rental)
    if rid == nil then
        P.busy[pid] = nil
        failed(P.reasonText(why or "invalid_args"))
    end
end

-- 付款鈕：先報價（確認頁金額記成 expect）；同意自動續租直接送
function P.confirm()
    local s, E = P.sheet, P.api()
    if not s or not E then return end
    local pid = s.pid
    P.views[pid] = nil
    local v = P.view(s.slot)
    if not v.ready then return end
    if s.kind == "auto" then return P.sendAuto(pid, true, v.ent.revision, v.plan.revision, s.rental) end
    if not P.canPay(v) then return end
    local amount, cur = P.sheetMoney(v, s)
    s.expect, s.notice = { amount = amount, currency = cur }, nil
    P.busy[pid] = "quote"
    say(pid, nil)
    local rid, why
    if s.kind == "renew" then
        rid, why = E.quote(SRC, pid, "rental", nil, function(res) P.onQuote(pid, res) end, s.rental)
    else
        rid, why = E.quote(SRC, pid, s.kind, 1, function(res) P.onQuote(pid, res) end)
    end
    if rid == nil then refuse(pid, why) end
end

-- 報價回來：金額、幣別等於確認頁的才付款；不同（方案剛改）不付款，確認頁換成新價格並提示
function P.onQuote(pid, res)
    P.busy[pid] = nil
    if res.unknown then return say(pid, T("PayQuoteNoAnswer"), true) end
    if not res.ok or type(res.quote) ~= "table" then return say(pid, P.reasonText(res.error), true) end
    local s = P.sheet
    if not s or s.pid ~= pid then return end
    local q = res.quote
    if not (type(s.expect) == "table" and q.amount == s.expect.amount and q.currency == s.expect.currency) then
        s.notice = true
        P.views[pid] = nil
        return
    end
    P.purchase(pid, q)
end

function P.purchase(pid, q)
    local E = P.api()
    if E == nil or P.busy[pid] or P.orders[pid] then return end
    local s = P.sheet
    P.busy[pid] = "purchase"
    -- 付款前保留伺服器指定的訂單 id：查詢只讀同一筆。新租約勾了自動續租：意圖跟著這筆訂單直到它有最終結果
    P.orders[pid] = { quoteId = q.id, orderId = q.orderId,
        auto = s and s.kind == "rental" and s.auto and { terms = q.termsRevision } or nil }
    local rid, why = E.purchase(SRC, q.id, function(res) P.onPurchase(pid, res) end)
    if rid == nil then
        P.orders[pid] = nil
        refuse(pid, why)
    end
end

-- 訂單有了最終結果：付款完成而且勾了自動續租，就替這張新租約（id＝訂單 id）送同意，條款＝報價的方案版本
function P.finish(pid, o, res, key)
    P.orders[pid] = nil
    local auto = o and o.auto
    if auto and o.orderId ~= nil and key == "PayPaidDone" then
        local snap = tbl(res.snapshot)
        return P.sendAuto(pid, true, tbl(snap.entitlement).revision, tonumber(auto.terms) or tbl(snap.plan).revision,
            o.orderId, key)
    end
    say(pid, T(key))
end

function P.onPurchase(pid, res)
    P.busy[pid] = nil
    local o = P.orders[pid]
    if res.unknown or res.error == "timeout" then
        if P.sheet and P.sheet.pid == pid then P.sheet = nil end
        if o and res.orderId and not o.orderId then o.orderId = res.orderId end
        return say(pid, nil)
    end
    if not res.ok then
        P.orders[pid] = nil
        return say(pid, P.reasonText(res.error), true)
    end
    if P.sheet and P.sheet.pid == pid then P.sheet = nil end
    P.finish(pid, o, res, res.duplicate and "PayDuplicate" or "PayPaidDone")
end

-- 查詢購買結果：只讀伺服器在報價指定的 orderId（缺就查原 quoteId），絕不重送購買
function P.check(pid)
    local E, o = P.api(), P.orders[pid]
    if E == nil or o == nil or P.busy[pid] then return end
    local id = o.orderId or o.quoteId
    P.busy[pid] = "order"
    say(pid, nil)
    local rid, why = E.getOrder(SRC, pid, id, function(res) P.onOrder(pid, res, id) end)
    if rid == nil then refuse(pid, why) end
end

local OUTCOME = { paid = "PayPaidDone", refunded = "PayRefunded", not_paid = "PayNoOrder" }
-- 只有查回同一筆、而且伺服器給了最終結果才解除付款鎖；其他一律維持「查詢購買結果」
function P.onOrder(pid, res, requestedId)
    P.busy[pid] = nil
    if res.unknown then return say(pid, nil) end
    if not res.ok then return say(pid, P.reasonText(res.error), true) end
    local o = P.orders[pid]
    local order = tbl(res.order)
    if o and o.orderId == nil and requestedId == o.quoteId and res.known == true then o.orderId = order.orderId end
    local same = o and order.orderId ~= nil and order.orderId == o.orderId
    local E = P.api()
    local key = same and res.known == true and E and E.orderOutcome and OUTCOME[E.orderOutcome(res)]
    if not key then return say(pid, nil) end
    P.finish(pid, o, res, key)
end

-- 面板按鈕（id 由 P.ui 給）
function P.press(id, player, slot)
    local v = P.view(slot)
    local pid = v.pid
    if id == "rent" or id == "buy" then
        if P.canPay(v) then P.openSheet(slot, id == "buy" and "permanent" or "rental") end
    elseif id == "renew" then
        if P.canPay(v) and v.rental then P.openSheet(slot, "renew", v.rental.id) end
    elseif id == "autoOn" or id == "agree" then
        if v.rental and v.autoAllowed then P.openSheet(slot, "auto", v.rental.id) end
    elseif id == "autoOff" then
        if v.rental then P.sendAuto(pid, false, v.ent.revision, v.plan.revision, v.rental.id) end
    elseif id == "sheetAuto" then
        if P.sheet then P.sheet.auto = not P.sheet.auto end
    elseif id == "pay" then
        P.confirm()
    elseif id == "cancel" then
        P.closeSheet()
    elseif id == "check" then
        P.check(pid)
    end
    P.views[pid] = nil
end
