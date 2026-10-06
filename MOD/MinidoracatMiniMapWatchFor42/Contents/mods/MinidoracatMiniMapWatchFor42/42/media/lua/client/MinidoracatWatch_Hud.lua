-- MinidoracatWatch_Hud.lua：畫面上的地圖錶狀態（Phase 9，規劃書 §0「畫面狀態」、設計稿「遊戲裡的入口」「畫面上的手錶狀態」）——
-- 小地圖標題列的電量（主 MOD registerTitleStatus）、物品停留說明、重要事件的 Toast（每件事提示一次）。
-- 只讀狀態：電量、槽位、租約都是伺服器推來的（MinidoracatWatch_Client／_PayClient），這裡不送任何指令。
-- 用到的面板與付款函式（C.slotStatus、C.className、C.drainText、C.Pay）在呼叫時才取：那些檔可能排在本檔之後載入。
require "ISUI/ISToolTipInv"
require "MinidoracatWatch_Client"
local W, C = MinidoracatWatchCore, MinidoracatWatchClient
local H = {}
C.Hud = H

local function T(key, ...) return getText("IGUI_MinidoracatWatch_" .. key, ...) end

-- 「經濟系統」槽位的租約到期、槽位裡還有模組（面板 lapsed／paused）
local function lapsedWithModule(player, watch)
    for _, slot in ipairs(W.slotList) do
        if W.slotMode(slot) == "econ" and W.slotRecord(watch, slot.id) and not W.slotValid(player, slot)
                and C.Pay.lapsed(slot) then
            return true
        end
    end
    return false
end

-- ===== 小地圖標題列（主 MOD addon-api §3.17：fn(playerNum) → 已翻譯的短字[, "warn"]；主 MOD 每 250ms 問一次）=====
-- 電量％＋低電量、沒電、沒電池或租約到期的警示；不需要電池時不畫電量（只剩到期警示）。沒戴錶、系統關閉＝不顯示。
function H.titleStatus(pn)
    if not W.enabled() then return nil end
    local player = getSpecificPlayer(pn)
    local watch = player and C.watchOf(pn)
    if not watch then return nil end
    local lapsed = lapsedWithModule(player, watch)
    if not W.needBattery() then
        if lapsed then return T("TitleLapsedOnly"), "warn" end
        return nil
    end
    local c = W.charge(watch)
    local text, warn
    if c == nil then
        text, warn = T("TitleNoBattery"), true
    elseif c <= 0 then
        text, warn = T("TitleDead"), true
    else
        text, warn = T("TitleBattery", tostring(C.percent(c))), c <= W.LOW_CHARGE
    end
    if lapsed then text, warn = T("TitleLapsed", text), true end
    if warn then return text, "warn" end
    return text
end

-- 守衛先於註冊（addon-api §2）：主 MOD 太舊＝標題列不顯示，其他功能照常；log 一次
function H.registerTitle()
    local api = MinidoracatMiniMapAPI
    if type(api) == "table" and type(api.titleStatusApiVersion) == "number" and api.titleStatusApiVersion >= 1
            and type(api.registerTitleStatus) == "function" then
        local ok, res = pcall(api.registerTitleStatus, W.MOD_ID, H.titleStatus)
        H.titleActive = ok and res == true
    end
    if not H.titleActive then
        W.log("MinidoracatMiniMapAPI.titleStatusApiVersion >= 1 not found: the battery stays in the watch panel and the Dock")
    end
end
Events.OnGameStart.Add(H.registerTitle)

-- ===== 物品停留說明 =====
-- 清單每列最多 3 項（說明框不換行；七個模組寫成一列會比原版說明寬很多），第一列帶標題、之後縮排
local PER_ROW = 3
local function listLines(out, key, items, sep)
    for i = 1, #items, PER_ROW do
        local row = table.concat(items, sep, i, math.min(#items, i + PER_ROW - 1))
        if i + PER_ROW <= #items then row = row .. sep end
        out[#out + 1] = { i == 1 and T(key, row) or ("    " .. row), false }
    end
end

-- 回 { { 文字, 警示 }... } 或 nil（不是地圖錶或模組、系統關閉）。player＝看說明的玩家（槽位有效、租約都是他的帳號）。
local function watchLines(player, watch)
    local out = {}
    local c = W.charge(watch)
    local kind = W.needBattery() and c ~= nil and c > 0 and C.watchOf(player:getPlayerNum()) == watch
        and W.chargeState(player)
    if kind then
        out[1] = { T(kind == W.CHARGE_CAR and "Tip_ChargingCar" or "Tip_ChargingHouse", tostring(C.percent(c)),
            C.timeText(1 - c, W.chargeHours(kind))), false }
    else
        out[1] = { C.statusText(watch, player), W.needBattery() and (c == nil or c <= W.LOW_CHARGE) }
    end
    local sep, mods, paid = getText("IGUI_MinidoracatWatch_ListSep"), {}, {}
    for _, slot in ipairs(W.slotList) do
        local st, rec = C.slotStatus(player, watch, slot)
        local mode = W.slotMode(slot)
        local v = mode == "econ" and C.Pay.view(slot) or nil
        local rented = v and v.rental and not v.perm and W.slotValid(player, slot)
        if rec then
            local name = C.moduleName(rec.id)
            if st == "paused" then name = T("Tip_ModulePaused", name)
            elseif rented then name = T("Tip_ModuleRent", name) end
            mods[#mods + 1] = name
        end
        if mode == "card" or mode == "econ" then
            local word
            if W.slotValid(player, slot) then
                word = rented and T("St_rent") or (v and v.perm and T("Tip_Bought")) or T("Tip_Opened")
            else
                word = T(C.Pay.lapsed(slot) and "St_lapsed" or "St_locked")
            end
            paid[#paid + 1] = T("Tip_PaidSlot", C.slotName(slot), word)
        end
    end
    for _, slot in ipairs(W.orphanSlots(watch)) do
        mods[#mods + 1] = T("Tip_ModulePaused", C.moduleName(W.slotRecord(watch, slot.id).id))
    end
    if #mods == 0 then out[#out + 1] = { T("Tip_ModulesNone"), false } else listLines(out, "Tip_Modules", mods, sep) end
    if #paid > 0 then listLines(out, "Tip_Paid", paid, sep) end
    return out
end

local function moduleLines(def)
    local out = {
        { getText("IGUI_MinidoracatWatch_KV_Class", C.className(def.class)), false },
        { getText("IGUI_MinidoracatWatch_KV_Drain", C.drainText(def)), false },
    }
    local b = W.BUILTIN[def.id]
    if b and b.feature then out[3] = { T("Tip_Feature", T("Feature_" .. b.feature)), false } end
    return out
end

-- 說明每幀量測＋繪製兩次：同一件物品 250ms 內沿用同一份文字
local TIP_MS = 250
local tip = { item = nil, player = nil, at = nil, lines = nil }
function H.tipLines(player, item)
    if not W.enabled() or not player or not item or not item.getFullType then return nil end
    local now = getTimestampMs()
    if tip.item == item and tip.player == player and now >= tip.at and now - tip.at < TIP_MS then return tip.lines end
    local lines = nil
    if W.isWatch(item) then
        lines = watchLines(player, item)
    else
        local def = W.moduleByItem[item:getFullType()]
        if def then lines = moduleLines(def) end
    end
    tip.item, tip.player, tip.at, tip.lines = item, player, now, lines
    return lines
end

-- 疊法照家族 pitfalls「覆寫 vanilla UI render」與 Cleaner MinidoracatCleaner_Tooltip.lua：先讓下游（原版與其他 MOD 的
-- 覆寫）畫完，暫時攔 self 實例的 drawRect／drawRectBorder 量它畫到哪，再把自己的框貼在最底下。self.item 不一定是物品
-- （ISEnergyBar／ISFluidBar 也用 ISToolTipInv）：只認有 getFullType 的。實例欄位要用 pairs 找（rawget 會查 metatable）。
local PAD = 5
local function ownSlots(self)
    local rect, border
    for k, v in pairs(self) do
        if k == "drawRect" then rect = v elseif k == "drawRectBorder" then border = v end
    end
    return rect, border
end

local function renderMeasured(self, original)
    local ownRect, ownBorder = ownSlots(self)
    local fwdRect, fwdBorder = self.drawRect, self.drawRectBorder
    local bottom
    local function track(y, w, h)
        if w > 0 and h > 0 and (not bottom or y + h > bottom) then bottom = y + h end
    end
    rawset(self, "drawRect", function(ui, x, y, w, h, a, r, g, b)
        track(y, w, h)
        return fwdRect(ui, x, y, w, h, a, r, g, b)
    end)
    rawset(self, "drawRectBorder", function(ui, x, y, w, h, a, r, g, b)
        track(y, w, h)
        return fwdBorder(ui, x, y, w, h, a, r, g, b)
    end)
    local ok, err, trace = pcall(original, self)
    rawset(self, "drawRect", ownRect)
    rawset(self, "drawRectBorder", ownBorder)
    if not ok then error(err, trace) end -- Kahlua：第二參數是 stacktrace（BaseLib.java:250-256）
    return bottom -- nil＝下游這一幀沒畫（右鍵選單開著時原版整段跳過，ISToolTipInv.lua:45）
end

-- 框貼在下游最底下；超出螢幕底改貼上方，上方也放不下就不畫（貼的框不參與原版的螢幕夾取）
local function appendBox(self, lines, bottom)
    local tm = getTextManager()
    local font = self.tooltip:getFont()
    local lineH = tm:getFontHeight(font)
    local h = PAD * 2 + lineH * #lines
    local w = self.width
    for _, line in ipairs(lines) do w = math.max(w, PAD * 2 + tm:MeasureStringX(font, line[1])) end
    local y = bottom - 1
    if self.y + y + h > getCore():getScreenHeight() then
        if self.y - h < 0 then return end
        y = -h + 1
    end
    local bg, bd = self.backgroundColor, self.borderColor
    self:drawRect(0, y, w, h, math.min(1, bg.a + 0.4), bg.r, bg.g, bg.b)
    self:drawRectBorder(0, y, w, h, bd.a, bd.r, bd.g, bd.b)
    for i, line in ipairs(lines) do
        if line[2] then
            self:drawText(line[1], PAD, y + PAD + (i - 1) * lineH, 1, 0.65, 0.3, 1, font)
        else
            self:drawText(line[1], PAD, y + PAD + (i - 1) * lineH, 0.8, 0.8, 0.8, 1, font)
        end
    end
end

local function tipPlayer(self)
    local tt = self.tooltip
    local chr = tt and tt.getCharacter and tt:getCharacter()
    if chr and chr.getPlayerNum then return chr end
    return getSpecificPlayer(0)
end

-- 掛在 OnGameStart：晚於所有 MOD 的檔案頂層（GameLoadingState.java:307 在 :149 之後），所以本 MOD 在最外層、下游全畫得到
function H.installTooltip()
    if H.tooltipInstalled or not ISToolTipInv then return end
    H.tooltipInstalled = true
    local original = ISToolTipInv.render
    function ISToolTipInv:render()
        local lines = H.tipLines(tipPlayer(self), self.item)
        if not lines then return original(self) end
        local bottom = renderMeasured(self, original)
        if bottom then appendBox(self, lines, bottom) end
    end
end
Events.OnGameStart.Add(H.installTooltip)

-- ===== 重要事件的 Toast（每件事提示一次）=====
-- 每秒比對每位本機玩家的上一次狀態：戴的錶換了（或剛上線）只記基準、不提示。玩家看到的清單在 README「功能」的狀態顯示：
-- 低電量（往下跨過 W.LOW_CHARGE 一次，回到門檻＋5% 以上才重新武裝）、沒電（燈同時被熄就併成一則）、開始充電／充飽、
-- 經濟系統槽位的租約到期／自動續租沒扣到款／自動續租成功（面板自己付的不報：檢視區已經說了）、其他原因的槽位失效讓模組停用。
-- 同一件事 60 秒內不重報（車子反覆熄火發動、門檻上下跳）。低電量、沒電、租約到期另播音效（MinidoracatWatch_Sound.lua），跟著 Toast 一起不重報。
local POLL_MS, REPEAT_MS, LIGHT_MS, REARM, PAID_MS = 1000, 60000, 5000, 0.05, 10000
H.state = {}
local lastPoll = nil
local Snd = MinidoracatWatchSound

local function say(s, player, id, now, title, msg, sound)
    local last = s.said[id]
    if last and now >= last and now - last < REPEAT_MS then return end
    s.said[id] = now
    C.toast(player, msg, title)
    if sound then Snd.play(player, sound) end
end

local function failText(v)
    local why = v.fail == "insufficient_funds" and T("PayFailFunds", C.Pay.currencyName(v.cur), tostring(v.short))
        or T("PayFailOther")
    if v.state == "grace" then why = why .. T("PayRetryWindow", C.Pay.leftText(v.graceLeft)) end
    return why
end

-- 經濟系統槽位：回 true＝這次失效已由租約到期報過（不再報一般的「模組停用」）。
-- 租約以 id 追：同一張租約 paidUntil 往後延＝續租（自動續租在到期那一步或寬限內扣到款）；第一次看到只記基準。
local function leaseEvents(s, player, watch, slot, now, valid)
    local prevValid = s.valid[slot.id]
    local rec = W.slotRecord(watch, slot.id)
    local e = s.rent[slot.id]
    if not (rec or valid or prevValid or e) then return false end
    local v = C.Pay.view(slot)
    local r = v.rental
    if not r or v.perm then
        s.rent[slot.id] = nil
        return false
    end
    local untilMs = type(r.paidUntil) == "number" and r.paidUntil or 0
    if not e or e.id ~= r.id then
        s.rent[slot.id] = { id = r.id, untilMs = untilMs, fail = v.fail }
        return false
    end
    local name, lapsed = C.slotName(slot), prevValid and not valid
    if lapsed then
        -- 到期那一步自動續租就沒扣到款：併成一則（原因＋重試期限）
        local msg = v.fail and failText(v) or (rec and T("Toast_Lapsed_msg", C.moduleName(rec.id)) or T("Toast_Lapsed_empty"))
        say(s, player, "lapse:" .. slot.id, now, T("Toast_Lapsed", name), msg, Snd.LAPSED)
    elseif v.fail and not e.fail then
        say(s, player, "fail:" .. slot.id, now, T("Toast_RenewFailed", name), failText(v))
    end
    e.fail = v.fail
    if untilMs > e.untilMs + 1000 then e.untilMs, e.renewed = untilMs, true
    elseif untilMs < e.untilMs then e.untilMs = untilMs end -- 管理員縮短租期：之後的延長從這裡算
    -- 等槽位恢復有效再報（伺服器的有效槽位與 Economy 的租約是兩個推送，先後不定）；面板正在付或剛付完的不報
    if e.renewed and valid and C.Pay.busy[v.pid] == nil then
        e.renewed = nil
        -- 續租成功＝這段到期結束：之後再到期、再扣不到款是新的一件事，不受 60 秒不重報擋住
        s.said["lapse:" .. slot.id], s.said["fail:" .. slot.id] = nil, nil
        local paid = C.Pay.paidAt[v.pid]
        if not (paid and now >= paid and now - paid < PAID_MS) then
            say(s, player, "renew:" .. slot.id, now, T("Toast_Renewed", name), T("Toast_Renewed_msg", C.Pay.leftText(v.left)))
        end
    end
    return lapsed
end

function H.check(pn, player, now)
    local watch = C.watchOf(pn)
    local s = H.state[pn]
    if not s or s.obj ~= player or s.watch ~= watch then
        s = { obj = player, watch = watch, said = s and s.obj == player and s.said or {}, valid = {}, rent = {} }
        H.state[pn] = s
    end
    if not watch or not W.enabled() then return end
    local c = 1 -- 不需要電池＝永遠滿電（W.power）；需要時 nil＝沒有電池
    if W.needBattery() then c = W.charge(watch) end
    local kind = W.chargeState(player)
    if W.lightOn(player) then s.litAt = now end
    if c and s.c and s.c > W.LOW_CHARGE and c > 0 and c <= W.LOW_CHARGE and not s.lowSaid then
        s.lowSaid = true
        say(s, player, "low", now, T("Toast_Low", tostring(C.percent(c))),
            T("Toast_Low_msg", C.timeText(c, C.fullRuntime(player, watch))), Snd.LOW)
    end
    if c == 0 and s.c and s.c > 0 then
        -- 伺服器沒電當下就同步電量、同一秒熄燈（MinidoracatWatch.lua accrue、_Light.lua lightCheck）：5 秒內亮過燈就併成一則
        local msg = T(W.deadKeepsMinimap() and "Toast_Dead_map" or "Toast_Dead_msg")
        if s.litAt and now - s.litAt <= LIGHT_MS then msg = T("Toast_Dead_light", msg) end
        say(s, player, "dead", now, T("Toast_Dead"), msg, Snd.DEAD)
    end
    if kind and not s.kind then
        say(s, player, "charge:" .. kind, now, T("Toast_Charging"),
            T(kind == W.CHARGE_CAR and "Toast_Charging_car" or "Toast_Charging_house"))
    elseif s.kind and not kind and c and c >= 1 then
        say(s, player, "full", now, T("Toast_Full"), T("Toast_Full_msg"))
    end
    if c and c > W.LOW_CHARGE + REARM then s.lowSaid = false end
    s.c, s.kind = c, kind
    for _, slot in ipairs(W.slotList) do
        local valid = W.slotValid(player, slot)
        local handled = W.slotMode(slot) == "econ" and leaseEvents(s, player, watch, slot, now, valid)
        if not handled and s.valid[slot.id] and not valid then
            local rec = W.slotRecord(watch, slot.id)
            if rec then
                say(s, player, "paused:" .. slot.id, now, T("Toast_Paused", C.moduleName(rec.id)),
                    T("Toast_Paused_msg", C.slotName(slot)))
            end
        end
        s.valid[slot.id] = valid
    end
end

function H.poll()
    local now = getTimestampMs()
    if lastPoll and now >= lastPoll and now - lastPoll < POLL_MS then return end
    lastPoll = now
    for pn = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(pn)
        if p and not p:isDead() then H.check(pn, p, now) end
    end
end
Events.OnTick.Add(H.poll)
