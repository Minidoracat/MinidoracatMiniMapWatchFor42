-- MinidoracatWatch_Panel.lua：手錶面板（單一皮膚；資訊架構照設計稿 panel.mjs：標題列、錶面＋槽位、槽位檢視、
-- 功能清單、電池區）。只用原版 ISPanel／ISButton／ISContextMenu，UI 框架缺席也能開。
-- 面板只讀錶的 modData 與解鎖狀態、送請求（MinidoracatWatch_Client.lua 的 request*）；所有突變在伺服器（單機在本機）。
-- 安裝入口：選空槽按「安裝模組」從清單挑、把背包裡的模組拖到槽位（ISMouseDrag.dragging，照 ISHotbar.lua:18-41、
-- :631-638：放開時 onMouseUp 讀拖曳清單，背包面板在自己的 update 才清掉，ISInventoryPane.lua:1880-1956）。
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISContextMenu"
require "MinidoracatWatch_Client"
local W, C = MinidoracatWatchCore, MinidoracatWatchClient

local Panel = ISPanel:derive("MinidoracatWatchPanel")
local panel -- 單例
local PAD, BTN_H = 10, 24
local PANEL_W, PANEL_H = 620, 510
local SOCK, GAP = 56, 10
local SOCK_Y = 124
local ADDON, ADDON_GAP, ADDON_PER_ROW = 40, 8, 4
local ADDON_Y = SOCK_Y + 2 * SOCK + GAP + 26
local LEFT_W = 3 * SOCK + 2 * GAP
local INSP_X = PAD + LEFT_W + 22
local FEAT_Y = 368
local SCAN_MS = 250
local BUSY_TYPE = "ISMinidoracatWatchAction"
local TIER_COLOR = {
    std = { 0.65, 0.69, 0.73 }, ext = { 0.25, 0.70, 0.50 }, adv = { 0.30, 0.55, 0.96 },
    core = { 0.66, 0.44, 0.94 }, addon = { 0.89, 0.60, 0.23 }, orphan = { 0.5, 0.5, 0.5 },
}
local FEATURES = { "minimap", "arrow", "poi", "nav", "share", "scan", "zombie" }

local function font() return UIFont.Small end
local function fontH() return getTextManager():getFontHeight(UIFont.Small) end

-- ===== 文字換行（依實際字寬；CJK 沒有空格也能斷）=====
-- Kahlua 的字串是 Java String，sub／#／byte 以字元計。結果依 (寬度, 文字) 快取，逐幀不重量測。
-- 斷點落在兩個 ASCII 字元中間（英文單字、數字）才退回前一個空格；中日文兩字之間直接斷，不為了空格留下大段空白。
local wrapCache, wrapCount = {}, 0
local function wrap(text, width)
    local byW = wrapCache[width]
    local hit = byW and byW[text]
    if hit then return hit end
    if wrapCount > 200 then wrapCache, wrapCount = {}, 0 end
    local tm, f = getTextManager(), font()
    local lines, n, start = {}, #text, 1
    while start <= n do
        if tm:MeasureStringX(f, text:sub(start, n)) <= width then
            lines[#lines + 1] = text:sub(start, n)
            break
        end
        local lo, hi = start, n
        while lo < hi do
            local mid = math.floor((lo + hi + 1) / 2)
            if tm:MeasureStringX(f, text:sub(start, mid)) <= width then lo = mid else hi = mid - 1 end
        end
        local stop = lo
        local a, b = text:byte(stop), text:byte(stop + 1)
        if a and b and a < 128 and b < 128 and a ~= 32 and b ~= 32 then
            for k = stop, start + 1, -1 do
                if text:sub(k, k) == " " then stop = k; break end
            end
        end
        lines[#lines + 1] = text:sub(start, stop)
        start = stop + 1
        while text:sub(start, start) == " " do start = start + 1 end
    end
    wrapCache[width] = wrapCache[width] or {}
    wrapCache[width][text] = lines
    wrapCount = wrapCount + 1
    return lines
end

-- ===== 槽位與模組的文字 =====
local function className(c) return getText("IGUI_MinidoracatWatch_Class_" .. c) end
local function acceptsText(slot)
    local parts = {}
    for i, c in ipairs(slot.acceptsList) do parts[i] = className(c) end
    return table.concat(parts, getText("IGUI_MinidoracatWatch_ListSep"))
end
local function drainText(def)
    local d = W.moduleDrain(def)
    if def.id == "eco" then return getText("IGUI_MinidoracatWatch_DrainHalf") end
    if d <= 0 then return getText("IGUI_MinidoracatWatch_DrainNone") end
    return getText("IGUI_MinidoracatWatch_DrainPlus", tostring(d))
end

-- 槽位狀態：empty／locked（解鎖卡未用）／off（不開放）／active／paused（槽位失效）／dead（錶沒電或沒電池）
function C.slotStatus(player, watch, slot)
    local rec = W.slotRecord(watch, slot.id)
    local valid = W.slotValid(player, slot)
    if not rec then
        if valid then return "empty", nil end
        return W.slotMode(slot) == "off" and "off" or "locked", nil
    end
    local c = W.charge(watch)
    if c == nil or c <= 0 then return "dead", rec end
    if not valid or not W.modules[rec.id] then return "paused", rec end
    return "active", rec
end

-- 拖到槽位上能不能裝：只看槽位有沒有效、空不空、類別合不合（設計稿 dropCheck）
function C.dropCheck(player, watch, slot, def)
    local st, rec = C.slotStatus(player, watch, slot)
    local name = C.slotName(slot)
    if st == "locked" then return false, getText("IGUI_MinidoracatWatch_Drop_Locked", name) end
    if st == "off" then return false, getText("IGUI_MinidoracatWatch_Drop_Off", name) end
    if rec then return false, getText("IGUI_MinidoracatWatch_Drop_Full", name, C.moduleName(rec.id)) end
    if not slot.accepts[def.class] then
        return false, getText("IGUI_MinidoracatWatch_Drop_Class", C.moduleName(def.id), className(def.class), name,
            acceptsText(slot))
    end
    return true, nil
end

-- 模組圖示：物品腳本的貼圖與色調（Item.getNormalTexture＝Item.java:525、getR/G/B＝:3230）
local iconCache = {}
local function moduleIcon(fullType)
    local e = iconCache[fullType]
    if e == nil then
        local s = getScriptManager():FindItem(fullType) -- ScriptManager.java:1414
        e = s and { tex = s:getNormalTexture(), r = s:getR(), g = s:getG(), b = s:getB() } or false
        iconCache[fullType] = e
    end
    return e or nil
end

-- ===== 面板 =====
function Panel:createChildren()
    local function button(x, y, w, title, fn)
        local b = ISButton:new(x, y, w, BTN_H, title, self, fn)
        b:initialise()
        self:addChild(b)
        return b
    end
    self.btnClose = button(self.width - 22 - PAD / 2, PAD / 2, 22, "X", Panel.onClose)
    local iy = FEAT_Y - BTN_H - 12
    self.btnInstall = button(INSP_X, iy, 140, getText("IGUI_MinidoracatWatch_InstallModule"), Panel.onInstall)
    self.btnRemoveModule = button(INSP_X, iy, 140, getText("IGUI_MinidoracatWatch_RemoveModule"), Panel.onRemoveModule)
    self.btnCard = button(INSP_X, iy, 220, getText("IGUI_MinidoracatWatch_UseCard"), Panel.onCard)
    local by = self.height - BTN_H - PAD
    self.btnInsert = button(PAD, by, 150, getText("IGUI_MinidoracatWatch_InsertBattery"), Panel.onInsert)
    self.btnRemove = button(PAD + 160, by, 150, getText("IGUI_MinidoracatWatch_RemoveBattery"), Panel.onRemove)
end

-- 面板對象：從右鍵選單開的那支（還在玩家身上時），否則是戴著的那支
function Panel:target()
    local player = getSpecificPlayer(self.playerNum)
    if not player then return nil, nil end
    local w = self.watchItem
    if w and player:getInventory():getItemWithIDRecursiv(w:getID()) ~= w then
        w = nil
        self.watchItem = nil
    end
    return player, w or C.watchOf(self.playerNum)
end

-- 面板上的槽位：登記的槽位，後面接這支錶的孤立槽位（提供槽位的 MOD 被移除、模組還在錶上；只能拆）。
-- 清單在 scan（250ms）重建，繪製與點擊只讀。
function Panel:slots() return self.slotView or W.slotList end

function Panel:selectedSlot()
    local list = self:slots()
    return list[self.sel] or list[1]
end

-- 正在對這支錶的這個槽位跑的計時動作（佇列第一個；ISTimedActionQueue.getTimedActionQueue）
function Panel:busyAction(player, watch, slot)
    local q = ISTimedActionQueue.getTimedActionQueue(player)
    local a = q and q.queue and q.queue[1]
    if a and a.Type == BUSY_TYPE and a.kind == "module" and a.watch == watch and a.slotId == slot.id then return a end
    return nil
end

-- 槽位外框（i＝self:slots() 的索引）：內建 6 格排 3×2，其他 MOD 的槽位在下面一列一列排
function Panel:socketRect(i)
    if i <= 6 then
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        return PAD + col * (SOCK + GAP), SOCK_Y + row * (SOCK + GAP), SOCK
    end
    local j = i - 7
    local col, row = j % ADDON_PER_ROW, math.floor(j / ADDON_PER_ROW)
    return PAD + col * (ADDON + ADDON_GAP), ADDON_Y + row * (ADDON + ADDON_GAP), ADDON
end

function Panel:socketAt(x, y)
    for i = 1, #self:slots() do
        local sx, sy, s = self:socketRect(i)
        if x >= sx and x < sx + s and y >= sy and y < sy + s then return i end
    end
    return nil
end

-- 背包與錶的掃描（解鎖卡、電池、孤立槽位）每 250ms 一次，不在每幀翻背包
function Panel:scan(player, watch, slot)
    local now = getTimestampMs()
    if self.scanAt and now >= self.scanAt and now - self.scanAt < SCAN_MS and self.scanSlot == slot then return end
    self.scanAt, self.scanSlot = now, slot
    local orphans = watch and W.orphanSlots(watch)
    if orphans and #orphans > 0 then
        local view = {}
        for i, s in ipairs(W.slotList) do view[i] = s end
        for _, s in ipairs(orphans) do view[#view + 1] = s end
        self.slotView = view
    else
        self.slotView = W.slotList
    end
    local list = C.cards(player, slot)
    self.cardCount = list and list:size() or 0
    self.hasBattery = C.bestBattery(player) ~= nil
end

function Panel:update()
    ISPanel.update(self)
    local player, w = self:target()
    local slot = self:selectedSlot()
    self.btnInstall:setVisible(false)
    self.btnRemoveModule:setVisible(false)
    self.btnCard:setVisible(false)
    if player then self:scan(player, w, slot) end
    local c = w and W.charge(w)
    self.btnInsert:setTitle(getText(c ~= nil and "IGUI_MinidoracatWatch_ReplaceBattery" or "IGUI_MinidoracatWatch_InsertBattery"))
    self.btnInsert:setEnable(w ~= nil and self.hasBattery == true)
    self.btnRemove:setEnable(w ~= nil and c ~= nil)
    if not w or self:busyAction(player, w, slot) then return end
    local st = C.slotStatus(player, w, slot)
    if st == "empty" then
        self.btnInstall:setVisible(true)
    elseif st == "locked" then
        self.btnCard:setVisible(true)
        self.btnCard:setTitle(getText("IGUI_MinidoracatWatch_UseSlotCard", C.cardName(slot)))
        self.btnCard:setEnable(self.cardCount > 0)
    elseif st ~= "off" then
        self.btnRemoveModule:setVisible(true)
    end
end

-- ===== 繪製 =====
local function text(el, s, x, y, r, g, b) el:drawText(s, x, y, r or 0.9, g or 0.9, b or 0.9, 1, font()) end

-- 換行繪製，回下一行的 y
local function para(el, s, x, y, width, r, g, b)
    local fh = fontH()
    for _, line in ipairs(wrap(s, width)) do
        text(el, line, x, y, r, g, b)
        y = y + fh
    end
    return y
end

local function drawLock(el, x, y)
    el:drawRectBorder(x + 3, y, 8, 8, 0.9, 0.75, 0.75, 0.75)
    el:drawRect(x, y + 6, 14, 10, 0.9, 0.75, 0.75, 0.75)
end

function Panel:drawSocket(i, player, watch, hover)
    local slot = self:slots()[i]
    local x, y, s = self:socketRect(i)
    local col = TIER_COLOR[slot.tier] or TIER_COLOR.std
    local st, rec = C.slotStatus(player, watch, slot)
    local dim = (st == "locked" or st == "off") and 0.45 or 1
    self:drawRect(x, y, s, s, 0.9, 0.10, 0.11, 0.13)
    self:drawRectBorder(x, y, s, s, dim, col[1], col[2], col[3])
    self:drawRectBorder(x + 1, y + 1, s - 2, s - 2, dim, col[1], col[2], col[3])
    if i == self.sel then self:drawRectBorder(x - 3, y - 3, s + 6, s + 6, 1, 1, 1, 1) end
    local icon = rec and moduleIcon(rec.item)
    if icon and icon.tex then
        local is = math.floor(s * 0.6)
        local a = st == "active" and 1 or 0.4
        self:drawTextureScaled(icon.tex, x + (s - is) / 2, y + (s - is) / 2 - 3, is, is, a, icon.r, icon.g, icon.b)
    elseif st == "locked" or st == "off" then
        drawLock(self, x + s / 2 - 7, y + s / 2 - 10)
    elseif st == "empty" then
        self:drawTextCentre("+", x + s / 2, y + s / 2 - fontH() / 2 - 3, 0.7, 0.7, 0.7, 1, UIFont.Medium)
    end
    if st == "paused" or st == "dead" then self:drawRect(x + s - 10, y + 3, 7, 7, 1, 1, 0.65, 0.2) end
    if slot.tier ~= "std" and s >= SOCK then
        self:drawTextCentre(getText("IGUI_MinidoracatWatch_Tag_" .. slot.tier), x + s / 2, y + s - fontH() - 1,
            col[1], col[2], col[3], 1, font())
    end
    if hover ~= nil then
        if hover then self:drawRect(x, y, s, s, 0.25, 0.3, 1, 0.4) else self:drawRect(x, y, s, s, 0.25, 1, 0.3, 0.3) end
    end
end

-- 正在拖的物品裡第一個模組（ISInventoryPane.getActualItems＝ISInventoryPane.lua:912）
local function draggedModule()
    if not ISMouseDrag or not ISMouseDrag.dragging then return nil, nil end
    for _, it in ipairs(ISInventoryPane.getActualItems(ISMouseDrag.dragging)) do
        local def = W.moduleByItem[it:getFullType()]
        if def then return it, def end
    end
    return nil, nil
end

function Panel:drawFace(player, watch)
    local cx = PAD + LEFT_W / 2
    local tex = watch:getTex() -- InventoryItem.java:678
    if tex then self:drawTextureScaled(tex, cx - 24, 66, 48, 48, 1, 1, 1, 1) end
    local item, def = draggedModule()
    local over = item and self:socketAt(self:getMouseX(), self:getMouseY())
    local why = nil
    local list = self:slots()
    for i = 1, #list do
        local hover = nil
        if i == over then
            local ok, reason = C.dropCheck(player, watch, list[i], def)
            hover, why = ok, reason
        end
        self:drawSocket(i, player, watch, hover)
    end
    if #list > 6 then
        text(self, getText("IGUI_MinidoracatWatch_OtherMods"), PAD, ADDON_Y - fontH() - 4, 0.6, 0.6, 0.6)
    end
    if why then para(self, why, PAD, FEAT_Y - 3 * fontH() - 8, LEFT_W, 1, 0.55, 0.45) end
end

function Panel:drawInspector(player, watch, slot)
    local x, y, width = INSP_X, 66, self.width - INSP_X - PAD
    local fh = fontH()
    local st, rec = C.slotStatus(player, watch, slot)
    local col = TIER_COLOR[slot.tier] or TIER_COLOR.std
    local name = C.slotName(slot)
    text(self, getText("IGUI_MinidoracatWatch_Tag_" .. slot.tier), x, y, col[1], col[2], col[3])
    local tagW = getTextManager():MeasureStringX(font(), getText("IGUI_MinidoracatWatch_Tag_" .. slot.tier))
    local busy = self:busyAction(player, watch, slot)
    local stKey = busy and (busy.install and "Installing" or "Removing") or st
    text(self, getText("IGUI_MinidoracatWatch_St_" .. stKey), x + tagW + 12, y, 0.75, 0.75, 0.75)
    y = y + fh + 6
    if busy then
        local mod = busy.install and C.moduleName(W.moduleByItem[busy.item:getFullType()].id) or C.moduleName(rec and rec.id or "")
        para(self, getText(busy.install and "IGUI_MinidoracatWatch_BusyInstall" or "IGUI_MinidoracatWatch_BusyRemove",
            mod, name), x, y, width)
        return
    end
    local cardNote = W.slotMode(slot) == "card" and st ~= "locked"
    if not rec then
        self:drawText(getText("IGUI_MinidoracatWatch_SlotTitle_" .. st, name), x, y, 1, 1, 1, 1, UIFont.Medium)
        y = y + getTextManager():getFontHeight(UIFont.Medium) + 6
        if st == "off" then
            para(self, getText("IGUI_MinidoracatWatch_Desc_Off", name), x, y, width)
            return
        end
        y = para(self, getText("IGUI_MinidoracatWatch_Desc_Accepts", acceptsText(slot)), x, y, width) + 4
        if slot.tier == "core" then y = para(self, getText("IGUI_MinidoracatWatch_Desc_Core"), x, y, width) + 4 end
        if slot.tier == "addon" then y = para(self, getText("IGUI_MinidoracatWatch_Desc_Addon"), x, y, width) + 4 end
        if st == "locked" then
            y = para(self, getText("IGUI_MinidoracatWatch_Desc_Card", C.cardName(slot), name), x, y, width, 0.85, 0.8, 0.6) + 4
            local note = self.cardCount > 0 and getText("IGUI_MinidoracatWatch_CardCount", tostring(self.cardCount))
                or getText("IGUI_MinidoracatWatch_CardNone", C.cardName(slot))
            para(self, note, x, y, width, 0.6, 0.6, 0.6)
            return
        end
        y = para(self, getText("IGUI_MinidoracatWatch_Desc_Empty"), x, y, width) + 4
    else
        local def = W.modules[rec.id]
        self:drawText(def and C.moduleName(def.id) or rec.item, x, y, 1, 1, 1, 1, UIFont.Medium)
        y = y + getTextManager():getFontHeight(UIFont.Medium) + 6
        if def and W.BUILTIN[def.id] then
            y = para(self, C.moduleDesc(def.id), x, y, width) + 4
        end
        if def then
            text(self, getText("IGUI_MinidoracatWatch_KV_Class", className(def.class)), x, y, 0.75, 0.75, 0.75)
            y = y + fh
            text(self, getText("IGUI_MinidoracatWatch_KV_Drain", drainText(def)), x, y, 0.75, 0.75, 0.75)
            y = y + fh
        end
        text(self, getText("IGUI_MinidoracatWatch_KV_Slot", name), x, y, 0.75, 0.75, 0.75)
        y = y + fh + 4
        if slot.orphan then
            y = para(self, getText("IGUI_MinidoracatWatch_Desc_Orphan"), x, y, width, 1, 0.65, 0.2) + 4
        elseif st == "paused" then
            y = para(self, getText("IGUI_MinidoracatWatch_Desc_Paused", name), x, y, width, 1, 0.65, 0.2) + 4
        elseif st == "dead" then
            y = para(self, getText("IGUI_MinidoracatWatch_Desc_Dead"), x, y, width, 1, 0.65, 0.2) + 4
        end
    end
    if cardNote then para(self, getText("IGUI_MinidoracatWatch_Desc_CardOpened"), x, y, width, 0.6, 0.6, 0.6) end
end

function Panel:drawFeatures()
    local fh = fontH()
    local colW = (self.width - 2 * PAD) / 2
    self:drawRect(PAD, FEAT_Y - 6, self.width - 2 * PAD, 1, 0.5, 0.5, 0.5, 0.5)
    for i, f in ipairs(FEATURES) do
        local x = PAD + ((i - 1) % 2) * colW
        local y = FEAT_Y + math.floor((i - 1) / 2) * (fh + 4)
        local ok, reason = C.gate(self.playerNum, f, "mini")
        if ok then self:drawRect(x, y + fh / 2 - 4, 8, 8, 1, 0.45, 0.85, 0.5)
        else self:drawRectBorder(x, y + fh / 2 - 4, 8, 8, 1, 0.6, 0.6, 0.6) end
        local label = getText("IGUI_MinidoracatWatch_Feature_" .. f)
        text(self, label, x + 14, y, ok and 0.9 or 0.6, ok and 0.9 or 0.6, ok and 0.9 or 0.6)
        if not ok and reason then
            local lw = getTextManager():MeasureStringX(font(), label)
            text(self, getText(reason), x + 24 + lw, y, 1, 0.65, 0.2)
        end
    end
end

function Panel:drawFooter(player, watch)
    local c = watch and W.charge(watch)
    local s
    if not watch then
        s = getText("IGUI_MinidoracatWatch_Status_NoWatch")
    elseif c == nil then
        s = getText("IGUI_MinidoracatWatch_Foot_NoBattery")
    elseif c <= 0 then
        s = getText("IGUI_MinidoracatWatch_Foot_Dead")
    else
        local hours = C.fullRuntime(player, watch)
        local d, h = W.timeLeft(c, hours)
        local full = C.timeText(1, hours)
        if d == 0 and h == 0 then
            s = getText("IGUI_MinidoracatWatch_Foot_ChargeUnderHour", tostring(C.percent(c)), full)
        else
            s = getText("IGUI_MinidoracatWatch_Foot_Charge", tostring(C.percent(c)), C.timeText(c, hours), full)
        end
    end
    para(self, s, PAD, self.height - BTN_H - PAD - fontH() - 6, self.width - 2 * PAD)
end

-- 標題列下的橫幅：沒戴這支錶、沒電池、沒電、電量低
function Panel:banner(player, watch)
    if watch ~= C.watchOf(self.playerNum) then return getText("IGUI_MinidoracatWatch_Banner_NotWorn"), 1, 0.8, 0.4 end
    local c = W.charge(watch)
    if c == nil then return getText("IGUI_MinidoracatWatch_Banner_NoBattery"), 1, 0.45, 0.4 end
    if c <= 0 then return getText("IGUI_MinidoracatWatch_Banner_Dead"), 1, 0.45, 0.4 end
    if c <= W.LOW_CHARGE then
        return getText("IGUI_MinidoracatWatch_Banner_Low", tostring(C.percent(c)), C.timeText(c, C.fullRuntime(player, watch))),
            1, 0.75, 0.3
    end
    return nil
end

function Panel:prerender()
    ISPanel.prerender(self)
    local player, w = self:target()
    local title = w and w:getDisplayName() or getText("IGUI_MinidoracatWatch_DockLabel")
    self:drawText(title, PAD, PAD, 1, 1, 1, 1, UIFont.Medium)
    local c = w and W.charge(w)
    local right = self.width - 22 - PAD
    if c ~= nil then
        local pct = C.percent(c) .. "%"
        local tw = getTextManager():MeasureStringX(font(), pct)
        text(self, pct, right - tw - 6, PAD + 2, 1, 1, 1)
        right = right - tw - 6
    end
    C.drawBattery(self, right - 30, PAD - 4, 28, w)
    if not (player and w) then
        para(self, C.statusText(nil), PAD, 44, self.width - 2 * PAD)
        self:drawFooter(player, nil)
        return
    end
    local msg, r, g, b = self:banner(player, w)
    if msg then para(self, msg, PAD, 40, self.width - 2 * PAD, r, g, b) end
    self:drawFace(player, w)
    self:drawInspector(player, w, self:selectedSlot())
    self:drawFeatures()
    self:drawFooter(player, w)
end

-- ===== 滑鼠：點槽位選取、放開拖曳的模組就安裝 =====
function Panel:onMouseDown(x, y)
    local i = self:socketAt(x, y)
    if i then
        self.sel = i
        return true
    end
    return ISPanel.onMouseDown(self, x, y)
end

function Panel:onMouseUp(x, y)
    local item, def = draggedModule()
    if item then
        local i = self:socketAt(x, y)
        local player, w = self:target()
        if i and player and w then
            self.sel = i
            self:dropOn(player, w, self:slots()[i], item, def)
        end
        return true
    end
    return ISPanel.onMouseUp(self, x, y)
end

function Panel:dropOn(player, watch, slot, item, def)
    local ok, why = C.dropCheck(player, watch, slot, def)
    if not ok then
        if HaloTextHelper then HaloTextHelper.addBadText(player, why) end
        return false
    end
    C.requestModule(player, watch, slot.id, item)
    return true
end

-- ===== 按鈕 =====
local function onPick(watch, player, slotId, item) C.requestModule(player, watch, slotId, item) end

-- 「安裝模組」：列出背包裡這個槽位裝得下的模組（每種一個）；沒有就列一行停用的說明
function Panel:onInstall()
    local player, w = self:target()
    if not (player and w) then return end
    local slot = self:selectedSlot()
    local menu = ISContextMenu.get(self.playerNum, getMouseX(), getMouseY())
    local any = false
    for _, def in ipairs(W.moduleList) do
        if slot.accepts[def.class] then
            local list = player:getInventory():getAllTypeRecurse(def.item)
            if list:size() > 0 then
                any = true
                menu:addOption(C.moduleName(def.id), w, onPick, player, slot.id, list:get(0))
            end
        end
    end
    if not any then
        local opt = menu:addOption(getText("IGUI_MinidoracatWatch_NoModuleToInstall"))
        opt.notAvailable = true
    end
    return menu
end

function Panel:onRemoveModule()
    local player, w = self:target()
    C.requestModule(player, w, self:selectedSlot().id, nil)
end

function Panel:onCard()
    local player = self:target()
    C.requestUnlock(player, self:selectedSlot().id)
end

function Panel:onInsert()
    local player, w = self:target()
    C.requestBattery(player, w, true)
end

function Panel:onRemove()
    local player, w = self:target()
    C.requestBattery(player, w, false)
end

function Panel:onClose() C.closePanel() end

function C.closePanel()
    if panel then panel:removeFromUIManager() end
    panel = nil
end

function C.openPanel(pn, watchItem)
    C.closePanel()
    local o = ISPanel.new(Panel, math.floor((getCore():getScreenWidth() - PANEL_W) / 2),
        math.floor((getCore():getScreenHeight() - PANEL_H) / 3), PANEL_W, PANEL_H)
    o.moveWithMouse = true
    o.backgroundColor = { r = 0.06, g = 0.07, b = 0.08, a = 0.95 }
    o.borderColor = { r = 0.45, g = 0.47, b = 0.5, a = 1 }
    o.playerNum = pn
    o.watchItem = watchItem
    o.sel = 1
    o.cardCount = 0
    o:initialise()
    o:addToUIManager()
    panel = o
end

function C.togglePanel(pn)
    if panel then C.closePanel() else C.openPanel(pn, nil) end
end

function C.isPanelOpen() return panel ~= nil end
function C.panel() return panel end
C.wrapText = wrap -- 測試用
