-- MinidoracatWatch_AdminUI.lua（client）：管理員設定視窗（Phase 4）與齒輪設定的「地圖錶管理」分類，以及伺服器清單的同步。
-- 版面照設計稿 admin.mjs：總覽、功能、槽位與價格、電池、取得方式、殭屍掉落六個分類＋快速方案＋「檢查並套用」。
-- 控制項一律用 UI 框架（規劃書 §0）：UI.Window／Tabs／Checkbox／Dropdown／TextField／Button／Dialog／Table／Toast；
-- 框架缺席或版本不足時分類照樣出現，按「開啟地圖錶設定」只提示，不退回原版外觀。
-- 資料與文字在 MinidoracatWatch_AdminModel.lua；伺服器端（權限、版本、設定檔、審計）在 server/MinidoracatWatch_Admin.lua。
require "MinidoracatWatch"
require "MinidoracatWatch_AdminModel"
local W = MinidoracatWatchCore
local M = MinidoracatWatchAdminModel
local T = M.T
local AU = {}
MinidoracatWatchAdminUI = AU -- 內部表（測試與 E2E 用），不是公開 API

-- ===== 伺服器清單的同步（MP 客戶端；不需要 UI 框架）=====
-- 伺服器每次變更廣播一次；客戶端第一個 tick 補要一次（伺服器送的時候客戶端可能還在載入）。只收認得的形狀。
function AU.onLists(args)
    local drains, slots = {}, {}
    for id, v in pairs(type(args.moduleDrains) == "table" and args.moduleDrains or {}) do
        if type(id) == "string" and type(v) == "number" then drains[id] = v end
    end
    for id, e in pairs(type(args.addonSlots) == "table" and args.addonSlots or {}) do
        if type(id) == "string" and type(e) == "table" and W.MODE_VALUE[e.mode] then
            slots[id] = {
                mode = e.mode,
                buy = type(e.buy) == "boolean" and e.buy or nil,
                buyPrice = type(e.buyPrice) == "number" and e.buyPrice or nil,
                rent = type(e.rent) == "boolean" and e.rent or nil,
                rentPrice = type(e.rentPrice) == "number" and e.rentPrice or nil,
            }
        end
    end
    W.clientLists.moduleDrains, W.clientLists.addonSlots = drains, slots
    W.invalidate()
end

local function askLists()
    if not isClient() then return Events.OnTick.Remove(askLists) end
    local p = getSpecificPlayer(0)
    if not p then return end
    Events.OnTick.Remove(askLists)
    sendClientCommand(p, W.MODULE, W.CMD_LISTS_REQ, {})
end
Events.OnTick.Add(askLists)

-- 本機玩家（分割畫面依 to 找）
local function localPlayer(name)
    for pn = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(pn)
        if p and p:getUsername() == name then return p, pn end
    end
    return nil
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= W.MODULE or type(args) ~= "table" then return end
    if command == W.CMD_LISTS then return AU.onLists(args) end
    if command == W.CMD_ADMIN_STATE then return AU.onState(args) end
    if command == W.CMD_ADMIN_RESULT and AU.onResult then return AU.onResult(args) end
end)

-- ===== 齒輪設定的分類（主 MOD settingsApiVersion >= 3 的 visible(pn)）=====
-- v2 以下會忽略 visible、所有人都看得到（主 MOD docs/addon-api.md 3.12）：不足就不註冊、log 一次。
AU.SECTION = {
    label = "IGUI_MinidoracatWatch_Admin_Section",
    actions = { { label = "IGUI_MinidoracatWatch_Admin_Open", tooltip = "IGUI_MinidoracatWatch_Admin_Open_tooltip",
        run = function(pn) AU.open(pn) end } },
    visible = function(pn) return W.isSettingsAdmin(getSpecificPlayer(pn)) end,
}
AU.registered = false
function AU.register()
    local api = MinidoracatMiniMapAPI
    if type(api) == "table" and type(api.settingsApiVersion) == "number" and api.settingsApiVersion >= 3
            and type(api.registerSettingsSection) == "function" then
        local ok, res = pcall(api.registerSettingsSection, W.MOD_ID, AU.SECTION)
        AU.registered = ok and res == true
    end
    if not AU.registered then
        W.log("MinidoracatMiniMapAPI.settingsApiVersion >= 3 not found: no admin settings category in the minimap settings")
    end
end
Events.OnGameStart.Add(AU.register)

local function notify(player, text)
    if player and HaloTextHelper then HaloTextHelper.addBadText(player, text) end
end

-- ===== UI 框架 =====
-- 需要 rev 14（Dropdown）＋window／controls／dialog／dropdown／table；Toast 選用。widget 檔不保證排在本檔之前，自己 pcall require。
if not (MinidoracatUI and MinidoracatUI.v1) then pcall(require, "MinidoracatUI/V1") end
pcall(require, "MinidoracatUI/VirtualList")
pcall(require, "MinidoracatUI/Widgets/Controls")
pcall(require, "MinidoracatUI/Widgets/Window")
pcall(require, "MinidoracatUI/Widgets/Dropdown")
pcall(require, "MinidoracatUI/Widgets/Table")
pcall(require, "MinidoracatUI/Widgets/Toast")
local UI = MinidoracatUI and MinidoracatUI.v1
local CAPS = UI and UI.CAPABILITIES
AU.uiReady = UI ~= nil and UI.API_MAJOR == 1 and type(UI.API_REVISION) == "number" and UI.API_REVISION >= 14
    and type(CAPS) == "table" and CAPS.window == true and CAPS.controls == true and CAPS.dialog == true
    and CAPS.dropdown == true and CAPS.table == true
local okWrap, TextWrap = pcall(require, "MinidoracatUI/TextWrap")
if not (okWrap and type(TextWrap) == "table" and type(TextWrap.cut) == "function") then TextWrap = nil end

AU.state = nil -- 開著的視窗：{ pn, player, win, base, draft, rev, … }
AU.pending = {} -- MP：[帳號] = playerNum（等 adminState）

function AU.open(pn)
    local player = getSpecificPlayer(pn or 0)
    if not player then return end
    if not AU.uiReady then
        W.log("admin settings window needs MinidoracatUIFor42 API rev 14 (window, controls, dialog, dropdown, table)")
        return notify(player, T("UiMissing"))
    end
    if not W.isSettingsAdmin(player) then return notify(player, T("Denied")) end
    if AU.state and AU.state.win then
        AU.state.win:setVisible(true)
        AU.state.win:bringToTop()
        return
    end
    if isClient() then
        AU.pending[player:getUsername()] = pn or 0
        sendClientCommand(player, W.MODULE, W.CMD_ADMIN_GET, {})
    else
        AU.build(pn or 0, player, W.Admin.state())
    end
end

function AU.onState(args)
    if type(args.to) ~= "string" then return end
    local player = localPlayer(args.to)
    if not player then return end
    if AU.state and AU.state.player == player and AU.state.reloading then
        AU.state.reloading = false
        return AU.reload(args)
    end
    local pn = AU.pending[args.to]
    if pn == nil then return end
    AU.pending[args.to] = nil
    if AU.uiReady and not (AU.state and AU.state.win) then AU.build(pn, player, args) end
end

-- ============================================================
-- 視窗
-- ============================================================
if not AU.uiReady then return end

local THEME = UI.Theme.create()
local COL = THEME.colors
local FONT = UIFont.Small
local FH = getTextManager():getFontHeight(FONT)
local CH = FH + 10 -- 控制項高
local ROW = CH + 6
local PAD = 14
local GAP = 8
local WIN_W, WIN_H = 880, 680
local FOOT_H = CH + 16
AU.TABS = { "overview", "features", "slots", "battery", "acquire", "zombies" }

local function measure(s) return getTextManager():MeasureStringX(FONT, s) end

-- 斷行（框架內部的 TextWrap；缺席時一行一段）
local function wrap(text, width)
    local out = {}
    for para in string.gmatch(tostring(text) .. "\n", "([^\n]*)\n") do
        if TextWrap then
            local rest = para
            while rest ~= "" do
                local line
                line, rest = TextWrap.cut(rest, width, FONT)
                out[#out + 1] = line
            end
        else
            out[#out + 1] = para
        end
    end
    return out
end

-- ===== 分頁容器：畫自己的文字列與不合法欄位的紅框（不畫底，ISPanel 的 background 關掉）=====
local Pane = ISPanel:derive("MinidoracatWatchAdminPane")
function Pane:prerender() end
function Pane:render()
    for i = 1, #self.texts do
        local t = self.texts[i]
        local c = COL[t.token] or COL.text
        self:drawText(t.text, t.x, t.y, c.r, c.g, c.b, c.a, FONT)
    end
    local bad = self.S and self.S.bad
    if bad then
        local c = COL.errorText
        for ctrl in pairs(bad) do
            if ctrl.parent == self and ctrl:getIsVisible() then
                self:drawRectBorder(ctrl:getX() - 2, ctrl:getY() - 2, ctrl:getWidth() + 4, ctrl:getHeight() + 4, c.a, c.r, c.g, c.b)
            end
        end
    end
end
local function newPane(S, x, y, w, h)
    local p = ISPanel.new(Pane, x, y, w, h)
    p:initialise()
    p.background = false
    p.texts, p.S = {}, S
    return p
end
local function text(p, s, x, y, token)
    local t = { text = s, x = x, y = y, token = token or "text" }
    p.texts[#p.texts + 1] = t
    return t
end
-- 換行文字，回下一行的 y
local function para(p, s, x, y, width, token)
    for _, line in ipairs(wrap(s, width)) do
        text(p, line, x, y, token or "textMuted")
        y = y + FH + 2
    end
    return y
end

-- ===== 控制項綁定：每個控制項登記一個 sync，重新載入或套用方案時照 draft 寫回（不觸發回呼）=====
local function changed(S) AU.refresh(S) end

local function check(S, p, x, y, label, get, set, width)
    local cb = UI.Checkbox.new({ x = x, y = y, width = width, label = label, checked = get(), theme = THEME,
        onChange = function(_, v) set(v); changed(S) end })
    p:addChild(cb)
    S.binds[#S.binds + 1] = function() cb:setChecked(get() == true, true) end
    return cb
end
-- sb* 的控制項依沙盒鍵記在 S.ctrl（E2E 直接操作同一個控制項）
local function sbCheck(S, p, x, y, key, label, width)
    local c = check(S, p, x, y, label or M.sbLabel(key), function() return S.draft.sb[key] end,
        function(v) S.draft.sb[key] = v end, width)
    S.ctrl[key] = c
    return c
end

local function dropdown(S, p, x, y, w, options, get, set)
    local dd = UI.Dropdown.new({ x = x, y = y, width = w, height = CH, options = options, selected = get(), theme = THEME,
        maxRows = 10, onChange = function(_, id) set(id); changed(S) end })
    p:addChild(dd)
    S.binds[#S.binds + 1] = function() dd:setSelected(get(), true) end
    return dd
end
local function enumOptions(key, labels)
    local f, out = M.FIELD[key], {}
    for v = f.min, f.max do
        out[#out + 1] = { id = v, label = labels and labels[v] or getText("Sandbox_MinidoracatWatch_" .. key .. "_option" .. v) }
    end
    return out
end
local function sbDropdown(S, p, x, y, w, key, labels)
    local c = dropdown(S, p, x, y, w, enumOptions(key, labels), function() return S.draft.sb[key] end,
        function(v) S.draft.sb[key] = v end)
    S.ctrl[key] = c
    return c
end

-- 數字欄：文字合法就寫進 draft，不合法記進 S.bad（紅框、擋住套用）；parse(text) → 值或 nil
local function field(S, p, x, y, w, get, set, parse, fmt)
    fmt = fmt or tostring
    local tf
    tf = UI.TextField.new({ x = x, y = y, width = w, height = CH, text = fmt(get()), theme = THEME,
        onChange = function(_, s)
            local v = parse(s)
            if v == nil then
                S.bad[tf] = true
            else
                S.bad[tf] = nil
                set(v)
            end
            changed(S)
        end })
    p:addChild(tf)
    S.binds[#S.binds + 1] = function()
        S.bad[tf] = nil
        tf:setText(fmt(get()))
    end
    return tf
end
local function intParser(min, max)
    return function(s)
        local v = tonumber(s)
        if v and v == math.floor(v) and v >= min and v <= max then return v end
        return nil
    end
end
local function sbField(S, p, x, y, w, key)
    local f = M.FIELD[key]
    local c = field(S, p, x, y, w, function() return S.draft.sb[key] end, function(v) S.draft.sb[key] = v end,
        intParser(f.min, f.max))
    S.ctrl[key] = c
    return c
end

local function button(p, x, y, title, onClick, style, width, icon)
    local b = UI.Button.new({ x = x, y = y, width = width, height = CH, title = title, style = style, icon = icon,
        theme = THEME, onClick = onClick })
    p:addChild(b)
    return b
end

-- 標籤＋控制項同一列：標籤在左（寬 lw），回控制項的 x
local function labeled(p, s, x, y, lw)
    text(p, UI.Text and UI.Text.fit and UI.Text.fit(s, lw - 6, FONT) or s, x, y + (CH - FH) / 2, "text")
    return x + lw
end

-- ===== 分類：總覽 =====
local function buildOverview(S, p)
    local w = p.width
    local y = 0
    sbCheck(S, p, 0, y, "Enabled", T("Enable"))
    y = para(p, T("Enable_desc"), 0, y + CH + 2, w) + GAP
    text(p, T("Presets"), 0, y, "text")
    y = para(p, T("Presets_desc"), 0, y + FH + 4, w) + 4
    local cw = math.floor((w - 2 * GAP) / 3)
    local maxY = y
    for i, id in ipairs(M.PRESETS) do
        local x = (i - 1) * (cw + GAP)
        button(p, x, y, T("Preset_" .. id), function()
            M.applyPreset(S.draft, id)
            AU.syncAll(S)
            S.msg = T("PresetApplied", T("Preset_" .. id))
            changed(S)
        end, id == "standard" and "primary" or "normal", cw)
        maxY = math.max(maxY, para(p, T("Preset_" .. id .. "_desc"), x, y + CH + 4, cw))
    end
    y = maxY + GAP
    text(p, T("Summary"), 0, y, "text")
    S.summaryTop, S.summaryPane = y + FH + 4, p
end

-- ===== 分類：功能 =====
local function buildFeatures(S, p)
    local w = p.width
    local y = para(p, T("Features_desc"), 0, 0, w) + 4
    local cw = math.floor((w - GAP * 2) / 2)
    for i, f in ipairs(M.FEATURES) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x = col * (cw + GAP * 2)
        local labels = {}
        for v = 1, #f.values do labels[v] = M.ruleText(f, v) end
        local dx = labeled(p, M.featureName(f.id), x, y + row * ROW, 120)
        sbDropdown(S, p, dx, y + row * ROW, cw - 120, f.key, labels)
    end
    y = y + math.ceil(#M.FEATURES / 2) * ROW + 4
    y = para(p, T("ScanNote"), 0, y, w) + GAP
    text(p, T("Ranges"), 0, y, "text")
    y = y + FH + 6
    local keys = { "ScanRadius", "DetectRadius", "MilDetectRadius", "CommRange", "LongCommRange", "LightRadius" }
    for i, k in ipairs(keys) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x = col * (cw + GAP * 2)
        local dx = labeled(p, M.sbLabel(k), x, y + row * ROW, cw - 110)
        sbField(S, p, dx, y + row * ROW, 100, k)
    end
    y = y + 3 * ROW + 2
    para(p, T("Ranges_desc"), 0, y, w)
end

-- ===== 分類：槽位與價格 =====
local function buildSlots(S, p)
    local w = p.width
    local y = para(p, T("Slots_desc"), 0, 0, w) + 2
    S.noEconY = y
    if W.econStatus ~= "READY" then y = para(p, T("NoEcon_hint"), 0, y, w, "errorText") + 2 end
    -- 欄：槽位｜開啟方式｜買斷｜買斷價格｜租用｜每期租金｜（第三方：用預設）
    local cx = { 0, 180, 392, 446, 566, 620, 740 }
    local heads = { "Col_slot", "Col_mode", "Col_buy", "Col_buyPrice", "Col_rent", "Col_rentPrice" }
    for i, k in ipairs(heads) do text(p, T(k), cx[i], y, "textMuted") end
    y = y + FH + 6
    local modeOpts = {}
    for i, m in ipairs(M.MODES) do modeOpts[i] = { id = i, label = T("ModeOpt_" .. m) } end
    local price = intParser(1, 1000000000)
    local function sbRow(name, key)
        text(p, name, cx[1], y + (CH - FH) / 2, "text")
        dropdown(S, p, cx[2], y, 200, modeOpts, function() return S.draft.sb[key] end, function(v) S.draft.sb[key] = v end)
        sbCheck(S, p, cx[3], y, key .. "Buy", "", 40)
        sbField(S, p, cx[4], y, 110, key .. "BuyPrice")
        sbCheck(S, p, cx[5], y, key .. "Rent", "", 40)
        sbField(S, p, cx[6], y, 110, key .. "RentPrice")
        y = y + ROW
    end
    for _, t in ipairs(M.TIERS) do sbRow(getText("IGUI_MinidoracatWatch_Slot_" .. t.id), t.key) end
    sbRow(T("AddonDefault"), "SlotAddon")
    -- 第三方槽位逐槽設定：改任何一欄就建立這個槽位的設定（存設定檔）；「用預設」刪掉它
    for _, slot in ipairs(M.addonSlots()) do
        local id = slot.id
        local function entry()
            if not S.draft.addon[id] then
                local e = M.slotEntry(S.draft, id)
                S.draft.addon[id] = { mode = e.mode, buy = e.buy, buyPrice = e.buyPrice, rent = e.rent, rentPrice = e.rentPrice }
            end
            return S.draft.addon[id]
        end
        local function cur(f) return M.slotEntry(S.draft, id)[f] end
        text(p, M.slotName(slot), cx[1], y + (CH - FH) / 2, "text")
        dropdown(S, p, cx[2], y, 200, modeOpts, function() return W.MODE_VALUE[cur("mode")] end,
            function(v) entry().mode = M.MODES[v] end)
        check(S, p, cx[3], y, "", function() return cur("buy") end, function(v) entry().buy = v end, 40)
        field(S, p, cx[4], y, 110, function() return cur("buyPrice") end, function(v) entry().buyPrice = v end, price)
        check(S, p, cx[5], y, "", function() return cur("rent") end, function(v) entry().rent = v end, 40)
        field(S, p, cx[6], y, 110, function() return cur("rentPrice") end, function(v) entry().rentPrice = v end, price)
        button(p, cx[7], y, T("UseDefault"), function()
            S.draft.addon[id] = nil
            AU.syncAll(S)
            changed(S)
        end, "ghost", w - cx[7])
        y = y + ROW
    end
    y = y + 4
    text(p, T("Renewal"), 0, y, "text")
    y = para(p, T("Renewal_desc"), 0, y + FH + 4, w) + 4
    local cw = math.floor((w - GAP * 2) / 2)
    local dx = labeled(p, M.sbLabel("PayCurrency"), 0, y, cw - 160)
    sbDropdown(S, p, dx, y, 150, "PayCurrency")
    dx = labeled(p, M.sbLabel("PayRentDays"), cw + GAP * 2, y, cw - 110)
    sbField(S, p, dx, y, 100, "PayRentDays")
    y = y + ROW
    dx = labeled(p, M.sbLabel("PayRetryHours"), 0, y, cw - 110)
    sbField(S, p, dx, y, 100, "PayRetryHours")
    dx = labeled(p, M.sbLabel("PayReminderHours"), cw + GAP * 2, y, cw - 110)
    sbField(S, p, dx, y, 100, "PayReminderHours")
    y = y + ROW
    sbCheck(S, p, 0, y, "PayAutoRenew")
end

-- ===== 分類：電池 =====
local function buildBattery(S, p)
    local w = p.width
    local dx = labeled(p, M.sbLabel("FullHours"), 0, 0, 260)
    sbField(S, p, dx, 0, 90, "FullHours")
    text(p, T("Unit_hours"), dx + 98, (CH - FH) / 2, "textMuted")
    local y = para(p, T("FullHours_desc"), 0, CH + 4, w) + 2
    sbCheck(S, p, 0, y, "DrainOffline")
    sbCheck(S, p, math.floor(w / 2), y, "DrainPaused")
    y = y + ROW + 2
    -- 充電（沙盒有充電選項的版本才有這一列）：開關＋「從沒電到充滿約 N 小時」
    if S.base.sb.ChargeCar ~= nil and S.base.sb.ChargeHouse ~= nil then
        local half = math.floor(w / 2)
        local cb = sbCheck(S, p, 0, y, "ChargeCar")
        sbField(S, p, cb:getRight() + GAP, y, 56, "CarHours")
        text(p, T("Unit_hours"), cb:getRight() + GAP + 62, y + (CH - FH) / 2, "textMuted")
        cb = sbCheck(S, p, half, y, "ChargeHouse")
        sbField(S, p, cb:getRight() + GAP, y, 56, "HouseHours")
        text(p, T("Unit_hours"), cb:getRight() + GAP + 62, y + (CH - FH) / 2, "textMuted")
        y = y + ROW + 2
    end
    text(p, T("Drains"), 0, y, "text")
    y = para(p, T("Drains_desc"), 0, y + FH + 4, w) + 4
    local cw = math.floor((w - GAP * 4) / 3)
    local function cell(i, top, label, get, set)
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local x = col * (cw + GAP * 2)
        local fx = labeled(p, label, x, top + row * ROW, cw - 96)
        text(p, "+", fx - 10, top + row * ROW + (CH - FH) / 2, "textMuted")
        field(S, p, fx, top + row * ROW, 64, get, set, intParser(0, 1000))
        text(p, "%", fx + 70, top + row * ROW + (CH - FH) / 2, "textMuted")
    end
    for i, d in ipairs(M.DRAINS) do
        cell(i, y, M.moduleName(d[1]), function() return S.draft.sb[d[2]] end, function(v) S.draft.sb[d[2]] = v end)
    end
    cell(#M.DRAINS + 1, y, T("DrainLight"), function() return S.draft.sb.LightDrain end,
        function(v) S.draft.sb.LightDrain = v end)
    y = y + math.ceil((#M.DRAINS + 1) / 3) * ROW + 2
    text(p, T("DrainsAddon"), 0, y, "text")
    y = y + FH + 6
    local mods = M.addonModules()
    if #mods == 0 then
        text(p, T("DrainsNone"), 0, y, "textMuted")
        y = y + FH + 6
    else
        -- ponytail: 第三方模組最多列 6 個（兩列），更多的用設定檔調；框架沒有捲動容器（回報框架缺件）
        for i = 1, math.min(6, #mods) do
            local def = mods[i]
            cell(i, y, M.moduleName(def.id), function() return M.addonDrain(S.draft, def) end,
                function(v) S.draft.drains[def.id] = v end)
        end
        y = y + math.ceil(math.min(6, #mods) / 3) * ROW
        if #mods > 6 then
            text(p, T("DrainsMore", tostring(#mods - 6)), 0, y, "textMuted")
            y = y + FH + 6
        end
    end
    button(p, 0, y, T("DrainReset"), function()
        for _, d in ipairs(M.DRAINS) do S.draft.sb[d[2]] = M.FIELD[d[2]].default end
        S.draft.sb.LightDrain = M.FIELD.LightDrain.default
        S.draft.drains = {}
        AU.syncAll(S)
        changed(S)
    end)
    y = y + ROW + 4
    text(p, T("Calc"), 0, y, "text")
    S.calcTop, S.calcPane = y + FH + 4, p
end

-- ===== 分類：取得方式 =====
local function buildAcquire(S, p)
    local w = p.width
    text(p, T("LootStyles"), 0, 0, "text")
    local y = para(p, T("LootStyles_desc"), 0, FH + 4, w) + 4
    local cw = math.floor(w / 4)
    for i, st in ipairs(M.LOOT_STYLES) do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        sbCheck(S, p, col * cw, y + row * ROW, "Loot" .. st, getItemNameFromFullType(W.watchType(st)), cw - 8)
    end
    y = y + 2 * ROW
    local amount = {}
    for v = 1, 4 do amount[v] = T("Amount_" .. v) end
    local dx = labeled(p, T("LootWatchAmount"), 0, y, 260)
    sbDropdown(S, p, dx, y, 140, "LootWatchAmount", amount)
    y = y + ROW + 4
    local function row(key, label, desc, amountKey)
        sbCheck(S, p, 0, y, key, label)
        if amountKey then
            local ax = labeled(p, T("Amount"), w - 230, y, 80)
            sbDropdown(S, p, ax, y, 140, amountKey, amount)
        end
        y = para(p, desc, 0, y + CH + 2, w - 240) + GAP
    end
    row("LootModules", T("LootModules"), T("LootModules_desc"), "LootModuleAmount")
    row("LootCards", T("LootCards"), T("LootCards_desc"), "LootCardAmount")
    row("AllowCraft", T("Craft"), T("Craft_desc"))
    row("NeedScrewdriver", T("Tool"), T("Tool_desc"))
end

-- ===== 分類：殭屍掉落 =====
local RuleCell = ISPanel:derive("MinidoracatWatchAdminRuleCell")
function RuleCell:onBind() self.label = M.ruleSentence(self.entry) end
function RuleCell:render()
    local lit = UI.Table.rowBackground(self)
    local S = self.list.S
    local box = FH
    local by = math.floor((self.height - box) / 2)
    local picked = S and S.picked[self.entry]
    if picked then self:drawRect(6, by, box, box, 1, COL.accent.r, COL.accent.g, COL.accent.b) end
    self:drawRectBorder(6, by, box, box, 1, COL.textMuted.r, COL.textMuted.g, COL.textMuted.b)
    if picked and UI.Icons and UI.Icons.draw then UI.Icons.draw(self, "check", 6, by, box, COL.onAccent or COL.text) end
    local c = lit and COL.text or COL.textMuted
    self:drawText(self.label or "", 12 + box, (self.height - FH) / 2, c.r, c.g, c.b, 1, FONT)
end
AU.PICK_W = FH + 14 -- 列首勾選框的點擊範圍

local function buildZombies(S, p)
    local w = p.width
    sbCheck(S, p, 0, 0, "ZombieDrops", T("DropsOn"))
    local y = para(p, T("DropsOn_desc"), 0, CH + 2, w) + 4
    local dx = labeled(p, T("DropCap"), 0, y, 200)
    sbField(S, p, dx, y, 60, "ZombieDropCap")
    text(p, T("Unit_items"), dx + 68, y + (CH - FH) / 2, "textMuted")
    text(p, T("DropCap_desc"), dx + 110, y + (CH - FH) / 2, "textMuted")
    y = y + ROW + 2
    text(p, T("Rules"), 0, y, "text")
    y = y + FH + 6
    -- 批量列：全選｜已選幾條｜機率設為／乘以｜數值｜套用｜刪除選取
    S.pickAll = UI.Checkbox.new({ x = 0, y = y, label = T("PickAll"), theme = THEME, onChange = function(_, v)
        S.picked = {}
        if v then for _, r in ipairs(S.draft.drops) do S.picked[r] = true end end
        AU.refreshRules(S)
    end })
    p:addChild(S.pickAll)
    S.pickText = text(p, "", S.pickAll.width + 12, y + (CH - FH) / 2, "textMuted")
    local bx = w - 470
    S.batchOp = UI.Dropdown.new({ x = bx, y = y, width = 120, height = CH, theme = THEME, selected = "set",
        options = { { id = "set", label = T("BatchSet") }, { id = "mul", label = T("BatchMul") } } })
    p:addChild(S.batchOp)
    S.batchValue = UI.TextField.new({ x = bx + 126, y = y, width = 70, height = CH, text = "2", theme = THEME })
    p:addChild(S.batchValue)
    S.batchApply = button(p, bx + 202, y, T("BatchApply"), function() AU.batch(S, false) end, "normal", 150)
    S.batchDel = button(p, bx + 358, y, T("BatchDel"), function() AU.batch(S, true) end, "danger", w - bx - 358)
    y = y + ROW
    -- 規則清單（UI.Table＝VirtualList）：點列首方框＝勾選，點其他地方＝在下方編輯這條
    local editorH = ROW * 2 + FH + 12
    local listH = math.max(ROW * 3, p.height - y - editorH)
    S.rules = UI.Table.new({ x = 0, y = y, width = w, height = listH, rowHeight = FH + 10, cell = RuleCell, theme = THEME,
        onSelect = function(list, item, index)
            if list:getMouseX() < AU.PICK_W then
                S.picked[item] = not S.picked[item] or nil
                AU.refreshRules(S)
            else
                AU.selectRule(S, index)
            end
        end })
    S.rules.S = S
    p:addChild(S.rules)
    S.emptyText = text(p, "", 12, y + 8, "textMuted")
    y = y + listH + 6
    -- 編輯列：殭屍類型｜（自訂服裝）｜每隻有｜機率｜% 機率掉落｜掉落物｜刪除
    local function cur() return S.draft.drops[S.ruleIndex or 0] end
    S.edGroup = UI.Dropdown.new({ x = 0, y = y, width = 180, height = CH, theme = THEME, options = M.groupOptions(),
        maxRows = 10, onChange = function(_, id)
            local r = cur()
            if not r then return end
            r.group = id
            if id == "custom" then r.outfits = r.outfits or M.parseOutfits(S.edOutfits:getText()) else r.outfits = nil end
            AU.refreshRules(S)
            AU.syncEditor(S)
        end })
    p:addChild(S.edGroup)
    local ex = 186
    text(p, T("Every"), ex, y + (CH - FH) / 2, "text")
    ex = ex + measure(T("Every")) + 6
    S.edChance = UI.TextField.new({ x = ex, y = y, width = 64, height = CH, theme = THEME, onChange = function(_, s)
        local r, v = cur(), tonumber(s)
        if not r then return end
        if v and M.validChance(v) then
            S.bad[S.edChance] = nil
            r.chance = v
        else
            S.bad[S.edChance] = true
        end
        AU.refreshRules(S)
    end })
    p:addChild(S.edChance)
    ex = ex + 70
    text(p, T("ChanceDrop"), ex, y + (CH - FH) / 2, "text")
    ex = ex + measure(T("ChanceDrop")) + 6
    S.edItem = UI.Dropdown.new({ x = ex, y = y, width = w - ex - 90, height = CH, theme = THEME, options = M.itemOptions(),
        maxRows = 12, onChange = function(_, id)
            local r = cur()
            if not r then return end
            r.item = id
            AU.refreshRules(S)
        end })
    p:addChild(S.edItem)
    S.edDel = button(p, w - 84, y, T("RuleDel"), function()
        if S.ruleIndex then
            S.picked[S.draft.drops[S.ruleIndex]] = nil
            table.remove(S.draft.drops, S.ruleIndex)
            S.ruleIndex = nil
            AU.refreshRules(S)
            AU.syncEditor(S)
        end
    end, "danger", 84)
    y = y + ROW
    S.edOutfits = UI.TextField.new({ x = 0, y = y, width = 360, height = CH, theme = THEME, placeholder = T("Outfits_ph"),
        onChange = function(_, s)
            local r = cur()
            if not (r and r.group == "custom") then return end
            local list = M.parseOutfits(s)
            S.bad[S.edOutfits] = list == nil or nil
            if list then r.outfits = list end
            AU.refreshRules(S)
        end })
    p:addChild(S.edOutfits)
    S.edHint = text(p, "", 0, y + (CH - FH) / 2, "textMuted")
    button(p, w - 300, y, T("RuleAdd"), function() AU.addRule(S) end, "normal", 140, "plus")
    button(p, w - 154, y, T("RuleReset"), function()
        S.draft.drops = M.copyDrops(W.defaultDrops())
        S.picked, S.ruleIndex = {}, nil
        AU.refreshRules(S)
        AU.syncEditor(S)
    end, "normal", 154)
end

-- 新增一條（所有殭屍、隨機一款地圖錶、1%），選取它在下方編輯
function AU.addRule(S)
    S.draft.drops[#S.draft.drops + 1] = { group = "all", item = "watch:any", chance = 1 }
    AU.refreshRules(S)
    AU.selectRule(S, #S.draft.drops)
    S.rules:scrollToIndex(#S.draft.drops)
end

-- 規則清單、勾選數、空清單提示（清單變了就呼叫）
function AU.refreshRules(S)
    local drops = S.draft.drops
    local keep = {}
    for _, r in ipairs(drops) do if S.picked[r] then keep[r] = true end end
    S.picked = keep
    local n = 0
    for _ in pairs(keep) do n = n + 1 end
    S.rules:setItems(drops)
    S.pickText.text = n == 0 and T("PickNone") or T("PickN", tostring(n))
    S.pickAll:setChecked(n > 0 and n == #drops, true)
    S.batchApply:setEnabled(n > 0)
    S.batchDel:setEnabled(n > 0)
    S.emptyText.text = #drops == 0 and T("RulesEmpty") or ""
    changed(S)
end

function AU.selectRule(S, index)
    S.ruleIndex = index
    S.rules:setSelectedIndex(index)
    AU.syncEditor(S)
end

-- 編輯列照目前選的規則（沒有選＝停用）；自訂服裝欄只在「自訂服裝」時出現，其他類型顯示包含哪些服裝
function AU.syncEditor(S)
    local r = S.draft.drops[S.ruleIndex or 0]
    if not r then S.ruleIndex = nil end
    for _, c in ipairs({ S.edGroup, S.edChance, S.edItem, S.edDel }) do c:setEnabled(r ~= nil) end
    S.bad[S.edChance], S.bad[S.edOutfits] = nil, nil
    if r then
        S.edGroup:setSelected(r.group, true)
        S.edItem:setSelected(r.item, true)
        S.edChance:setText(M.chanceText(r.chance))
    end
    local custom = r ~= nil and r.group == "custom"
    S.edOutfits:setVisible(custom)
    if custom then S.edOutfits:setText(type(r.outfits) == "table" and table.concat(r.outfits, ", ") or "") end
    local outfits = r and W.DROP_GROUPS[r.group]
    if not r then
        S.edHint.text = T("EditHint")
    else
        S.edHint.text = (not custom and outfits and #outfits > 0) and T("GroupOutfits", table.concat(outfits, ", ")) or ""
    end
    if UI.Text and UI.Text.fit then S.edHint.text = UI.Text.fit(S.edHint.text, S.rules.width - 320, FONT) end
end

-- 批量：機率設為／乘以（夾在 0..100），或刪除選取
function AU.batch(S, delete)
    local out = {}
    local v = tonumber(S.batchValue:getText())
    if not delete and not (v and v == v and v >= 0) then
        S.msg = T("BatchBad")
        return changed(S)
    end
    for _, r in ipairs(S.draft.drops) do
        if S.picked[r] then
            if not delete then
                local c = S.batchOp:getSelected() == "mul" and r.chance * v or v
                r.chance = math.floor(math.max(0, math.min(100, c)) * 1000 + 0.5) / 1000
                out[#out + 1] = r
            end
        else
            out[#out + 1] = r
        end
    end
    S.draft.drops = out
    if delete then S.picked, S.ruleIndex = {}, nil end
    AU.refreshRules(S)
    AU.syncEditor(S)
end

-- ===== 頁首／頁尾 =====
local Footer = ISPanel:derive("MinidoracatWatchAdminFooter")
Footer.prerender = Pane.prerender
Footer.render = Pane.render

-- 動態文字（總覽一覽、續航試算、頁尾修改數與訊息）；每次修改後重算
function AU.refresh(S)
    if not S.footer then return end
    local p = S.summaryPane
    local keep = {}
    for _, t in ipairs(p.texts) do if not t.summary then keep[#keep + 1] = t end end
    p.texts = keep
    local y = S.summaryTop
    for _, line in ipairs(M.summary(S.draft, W.econStatus == "READY")) do
        for _, l in ipairs(wrap(T("Bullet", line), p.width)) do
            text(p, l, 0, y, "textMuted").summary = true
            y = y + FH + 2
        end
    end
    local c = S.calcPane
    keep = {}
    for _, t in ipairs(c.texts) do if not t.calc then keep[#keep + 1] = t end end
    c.texts = keep
    local half = math.floor(c.width / 2)
    local rows = { { "Calc_base", {}, false }, { "Calc_three", M.SAMPLE_THREE, false }, { "Calc_full", M.SAMPLE_FULL, false },
        { "Calc_lit", M.SAMPLE_FULL, true } }
    for i, r in ipairs(rows) do
        local x, yy = ((i - 1) % 2) * half, S.calcTop + math.floor((i - 1) / 2) * (FH + 4)
        local s = M.validInt("FullHours", S.draft.sb.FullHours) and M.hoursText(M.runtime(S.draft, r[2], r[3])) or "-"
        text(c, T("Sum_Line", T(r[1]), s), x, yy, "textMuted").calc = true
    end
    local _, _, n = M.diff(S.base, S.draft)
    S.dirty = n
    S.dirtyText.text = n == 0 and T("Clean") or T("Dirty", tostring(n))
    S.msgText.text = S.msg and (UI.Text and UI.Text.fit and UI.Text.fit(S.msg, S.footer.width - 420, FONT) or S.msg) or ""
    S.discard:setEnabled(n > 0)
    S.apply:setEnabled(n > 0 and not S.busy)
end

function AU.syncAll(S)
    for _, f in ipairs(S.binds) do f() end
    S.picked, S.ruleIndex = {}, nil
    AU.refreshRules(S)
    AU.syncEditor(S)
end

-- 伺服器的最新狀態（開窗、衝突後重讀、套用後）：base＝伺服器，draft＝base 的複本
function AU.reload(st)
    local S = AU.state
    if not S then return end
    S.base = M.readBase(st)
    S.draft = M.copy(S.base)
    S.rev = st.rev
    S.bad = {}
    AU.syncAll(S)
end

function AU.showTab(S, id)
    UI.Dropdown.close(S.win)
    for k, p in pairs(S.panes) do p:setVisible(k == id) end
    S.tab = id
    S.tabs:setSelected(id, true) -- 程式切換（E2E）也要讓頁籤跟上
end

function AU.close()
    local S = AU.state
    AU.state = nil
    if not S then return end
    UI.Dropdown.close(S.win)
    if UI.Dialog and S.dialog then UI.Dialog.close(S.dialog, false) end
    S.win:removeFromUIManager()
end

local function watchIcon()
    local item = getScriptManager():FindItem(W.watchType("ValuTech"))
    return item and item:getNormalTexture() or nil
end

function AU.build(pn, player, st)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h = math.min(WIN_W, sw - 40), math.min(WIN_H, sh - 40)
    local S = { pn = pn, player = player, binds = {}, bad = {}, picked = {}, panes = {}, ctrl = {} }
    AU.state = S
    local win = UI.Window.new({ x = math.floor((sw - w) / 2), y = math.floor((sh - h) / 2), width = w, height = h,
        title = T("Title"), icon = watchIcon(), theme = THEME, onClose = function() AU.close() end })
    S.win = win
    win:addToUIManager()
    local top = win:contentTop() + 8
    local items = {}
    for i, id in ipairs(AU.TABS) do items[i] = { id = id, label = T("Tab_" .. id) } end
    S.tabs = UI.Tabs.new({ x = PAD, y = top, items = items, selected = "overview", theme = THEME,
        onSelect = function(_, id) AU.showTab(S, id) end })
    win:addChild(S.tabs)
    local econ = W.econStatus == "READY" and T("EconOn") or T("EconOff")
    local head = newPane(S, S.tabs:getRight() + GAP, top, w - S.tabs:getRight() - GAP - PAD, S.tabs.height)
    text(head, econ, head.width - measure(econ), (S.tabs.height - FH) / 2, W.econStatus == "READY" and "accent" or "textMuted")
    win:addChild(head)
    local py = top + S.tabs.height + 12
    local ph = h - py - FOOT_H - 6
    -- 先建頁尾（refresh 要用到），再建分類
    local foot = ISPanel.new(Footer, 0, h - FOOT_H, w, FOOT_H)
    foot:initialise()
    foot.background, foot.texts, foot.S = false, {}, S
    win:addChild(foot)
    S.footer = foot
    S.msgText = text(foot, "", PAD, (FOOT_H - FH) / 2, "accent")
    S.apply = button(foot, w - PAD - 170, 8, T("Apply"), function() AU.check(S) end, "primary", 170)
    S.discard = button(foot, w - PAD - 170 - GAP - 120, 8, T("Discard"), function()
        S.draft = M.copy(S.base)
        S.msg = nil
        AU.syncAll(S)
    end, "normal", 120)
    S.dirtyText = text(foot, "", S.discard:getX() - 150, (FOOT_H - FH) / 2, "textMuted")
    local builders = { overview = buildOverview, features = buildFeatures, slots = buildSlots, battery = buildBattery,
        acquire = buildAcquire, zombies = buildZombies }
    S.base = M.readBase(st)
    S.draft = M.copy(S.base)
    S.rev = st.rev
    for _, id in ipairs(AU.TABS) do
        local p = newPane(S, PAD, py, w - PAD * 2, ph)
        win:addChild(p)
        S.panes[id] = p
        builders[id](S, p)
    end
    AU.showTab(S, "overview")
    AU.syncAll(S)
    return S
end

-- ===== 檢查並套用 =====
-- 先擋不合法欄位與沒修改；再列出「這次會改變」（原本 → 改成，含改價要玩家重新同意的警告），要求填原因。
AU.MAX_LINES = 14
function AU.check(S, err)
    local nbad = 0
    for _ in pairs(S.bad) do nbad = nbad + 1 end
    if nbad > 0 or M.problems(S.draft) > 0 then
        S.msg = T("Invalid")
        return changed(S)
    end
    local lines, _, n = M.diff(S.base, S.draft)
    if n == 0 then
        S.msg = T("NoChanges")
        return changed(S)
    end
    local shown = {}
    if err then shown[#shown + 1] = err end
    shown[#shown + 1] = T("WillChange")
    for i = 1, math.min(#lines, AU.MAX_LINES) do shown[#shown + 1] = T("Bullet", lines[i]) end
    if #lines > AU.MAX_LINES then shown[#shown + 1] = T("More", tostring(#lines - AU.MAX_LINES)) end
    S.dialog = UI.Dialog.show({ title = T("ApplyTitle"), text = table.concat(shown, "\n"), width = 560, theme = THEME,
        confirmText = T("Confirm"), cancelText = T("Back"), input = { placeholder = T("Reason_ph") },
        onResult = function(ok, reason)
            S.dialog = nil
            if not ok then return end
            reason = string.gsub(tostring(reason or ""), "^%s+", "")
            reason = string.gsub(reason, "%s+$", "")
            if reason == "" then return AU.check(S, T("NeedReason")) end
            AU.send(S, reason, lines)
        end })
end

function AU.send(S, reason, lines)
    local args = M.payload(S.base, S.draft, S.rev, reason, lines)
    S.sent = { draft = M.copy(S.draft), sandbox = M.sandboxChanges(S.base, S.draft) }
    S.busy, S.msg = true, T("Sending")
    changed(S)
    if isClient() then
        sendClientCommand(S.player, W.MODULE, W.CMD_ADMIN_SET, args)
    else
        local res = W.Admin.apply(S.player, args)
        res.to = S.player:getUsername()
        AU.onResult(res)
    end
end

-- 伺服器回覆：成功＝送沙盒（MP sendToServer／單機 set＋toLua），以送出的那份當新的 base；衝突＝重讀；其他＝顯示原因
function AU.onResult(args)
    local S = AU.state
    if not S or type(args.to) ~= "string" or localPlayer(args.to) ~= S.player then
        -- 沒開視窗（例如開窗請求被拒）：提示本人
        local p = type(args.to) == "string" and localPlayer(args.to)
        if p and args.code == "denied" then notify(p, T("Denied")) end
        return
    end
    S.busy = false
    if args.ok == true then
        M.applySandbox(S.sent and S.sent.sandbox or {})
        S.base = S.sent and S.sent.draft or M.copy(S.draft)
        S.rev = args.rev
        S.msg = T("Applied", tostring(args.rev))
        if UI.Toast and CAPS.toast then UI.Toast.show({ title = T("Title"), message = S.msg }) end
    elseif args.code == "conflict" then
        S.msg = T("Conflict")
        if isClient() then
            S.reloading = true
            sendClientCommand(S.player, W.MODULE, W.CMD_ADMIN_GET, {})
        else
            AU.reload(W.Admin.state())
        end
    elseif args.code == "denied" then
        S.msg = T("Denied")
    elseif args.code == "write_failed" then
        S.msg = T("WriteFailed")
    elseif args.code == "reason" then
        S.msg = T("NeedReason")
    else
        local first = type(args.problems) == "table" and args.problems[1]
        S.msg = T("Rejected", type(first) == "string" and first or tostring(args.code))
    end
    S.sent = nil
    changed(S)
end
