-- MinidoracatWatch_Panel.lua：手錶面板。資訊架構照設計稿 panel.mjs（標題列、橫幅、錶面＋槽位、槽位檢視、功能清單、
-- 電量列），七款皮膚照 MinidoracatWatch_Skins.lua。元件一律用家族 UI 框架（規劃書 §0）：UI.Window（標題＝錶名、
-- icon＝錶的貼圖、內建關閉鈕、ISLayoutManager 存讀位置）、UI.Button、UI.Icons、UI.Toast、UI.Focus（Window 自動接手鍵盤
-- 與手把）。地圖錶專用的繪製：錶面與槽位外形（media/ui/MinidoracatWatch 的貼圖）、等級／狀態膠囊、功能清單、資訊框、
-- 橫幅底、各款裝飾——框架沒有對應元件，用 theme token＋Skin＋Icons 組出來。
-- 面板只讀錶的 modData 與解鎖狀態、送請求（MinidoracatWatch_Client.lua 的 request*）；所有突變在伺服器（單機在本機）。
-- 安裝入口：選空槽後按檢視區裡的模組按鈕（圖示＝模組物品貼圖）、把背包裡的模組拖到槽位（ISMouseDrag.dragging，照
-- ISHotbar.lua:18-41、:631-638：放開時 onMouseUp 讀拖曳清單，背包面板在自己的 update 才清掉，ISInventoryPane.lua:1880-1956）。
-- 槽位區是一個 Focus 目標（_focusKind="button"）：方向鍵／手把方向在槽位間移動游標、Enter／A 選取（focusRect 只框游標那格）。
require "ISUI/ISUIElement"
require "ISUI/ISLayoutManager"
require "MinidoracatWatch_Client"
require "MinidoracatWatch_PayClient"
require "MinidoracatWatch_Skins"
local W, C = MinidoracatWatchCore, MinidoracatWatchClient
local S = C.Skins

local panel -- 單例
local lastX, lastY -- 這次遊戲關掉面板時的位置（ISLayoutManager 只在存檔時寫 ini，重開沿用這個）
local LAYOUT_NAME = "MinidoracatWatchPanel"
local PAD, GAP = 14, 10
local PANEL_W, LEFT_W = 740, 290
local INSP_X = PAD + LEFT_W + 18
local INSP_MIN_H = 300
local SOCK, ADDON, ADDON_GAP = 56, 40, 8
local DIAL = 64
local SCAN_MS = 250
local MAX_ACTIONS = 12
local BUSY_TYPE = "ISMinidoracatWatchAction"
local FEATURES = { "minimap", "arrow", "poi", "nav", "share", "scan", "zombie", "light" }
local TIER_TOKEN = { std = "tierStd", ext = "tierExt", adv = "tierAdv", core = "tierCore", addon = "tierAddon",
    orphan = "tierOrphan" }
-- 付費按鈕的圖示（C.Pay.ui 的 id → UI.Icons key）
local PAY_ICON = { rent = "clock", renew = "clock", buy = "infinity", pay = "check", agree = "check", autoOn = "clock",
    autoOff = "pause", check = "reload", remove = "screwdriver" }
local STATUS_ICON = { active = "check", rent = "clock", paused = "pause", dead = "pause", locked = "lock", empty = "plus",
    lapsed = "clock", off = "close", Installing = "screwdriver", Removing = "screwdriver" }
local PAUSE_REASONS = { [W.REASON_PAUSED] = true, [W.REASON_DEAD] = true, [W.REASON_NO_BATTERY] = true }
local TEX_DIR = "media/ui/MinidoracatWatch/"

local function fontH(f) return getTextManager():getFontHeight(f or UIFont.Small) end
local function measure(s, f) return getTextManager():MeasureStringX(f or UIFont.Small, s) end

-- ===== 文字換行（依實際字寬；CJK 沒有空格也能斷）=====
-- Kahlua 的字串是 Java String，sub／#／byte 以字元計。結果依 (寬度, 文字) 快取，逐幀不重量測。
-- 斷點落在兩個 ASCII 字元中間（英文單字、數字）才退回前一個空格；中日文兩字之間直接斷，不為了空格留下大段空白。
-- 框架的 TextWrap 是內部模組（不在 facade 上），所以面板自己保留這一份。
local wrapCache, wrapCount = {}, 0
local function wrap(text, width)
    local byW = wrapCache[width]
    local hit = byW and byW[text]
    if hit then return hit end
    if wrapCount > 200 then wrapCache, wrapCount = {}, 0 end
    local tm, f = getTextManager(), UIFont.Small
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
    if def.id == "light" then return getText("IGUI_MinidoracatWatch_DrainLight", tostring(W.lightDrain())) end
    if d <= 0 then return getText("IGUI_MinidoracatWatch_DrainNone") end
    return getText("IGUI_MinidoracatWatch_DrainPlus", tostring(d))
end

-- 槽位狀態：empty／locked（未開啟）／lapsed（經濟系統的租約到期、槽位空著）／off（不開放）／active／paused（槽位失效）／
-- dead（錶沒電或沒電池）
function C.slotStatus(player, watch, slot)
    local rec = W.slotRecord(watch, slot.id)
    local valid = W.slotValid(player, slot)
    if not rec then
        if valid then return "empty", nil end
        if W.slotMode(slot) == "off" then return "off", nil end
        return C.Pay.lapsed(slot) and "lapsed" or "locked", nil
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
    if st == "lapsed" then return false, getText("IGUI_MinidoracatWatch_Drop_Lapsed", name) end
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

-- 槽位外形貼圖（scripts/gen_watch_ui_textures.py 產生；缺圖＝false，只少外形、不出錯）
local texCache = {}
local function shapeTex(name)
    local t = texCache[name]
    if t == nil then
        local ok, tex = pcall(getTexture, TEX_DIR .. name .. ".png")
        t = ok and tex or false
        texCache[name] = t
    end
    return t or nil
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

-- ===== 繪製小工具（顏色一律是 theme token 解出來的 {r,g,b,a}）=====
local function text(el, s, x, y, c, f)
    el:drawText(s, x, y, c.r, c.g, c.b, c.a or 1, f or UIFont.Small)
end
local function para(el, s, x, y, width, c)
    local fh = fontH()
    for _, line in ipairs(wrap(s, width)) do
        text(el, line, x, y, c)
        y = y + fh
    end
    return y
end
local function rect(el, x, y, w, h, c, a)
    el:drawRect(x, y, w, h, (a or 1) * (c.a or 1), c.r, c.g, c.b)
end
local function tint(el, tex, x, y, w, h, c, a)
    if tex then el:drawTextureScaled(tex, x, y, w, h, (a or 1) * (c.a or 1), c.r, c.g, c.b) end
end
local function shapeOf(UI, theme, part)
    if UI.Skin.shapeOf then return UI.Skin.shapeOf(theme, part) end
    return part == "title" and "roundTop" or nil
end

-- 電池圖示（Dock 與標題列共用；不配置 table）：Icons battery 外框＋內框填電量（32px 座標 x 6..23、y 12..20）
function C.drawBattery(el, x, y, size, watch, theme)
    local UI, colors = C.ui(), theme.colors
    local c = watch and W.charge(watch)
    UI.Icons.draw(el, "battery", x, y, size, colors.text, watch and 1 or 0.4)
    local k = size / 32
    local ix, iy, iw, ih = x + math.floor(6 * k), y + math.floor(12 * k), math.floor(17 * k), math.max(1, math.floor(8 * k))
    if c and c > 0 then
        rect(el, ix, iy, math.max(1, math.floor(iw * c)), ih, c <= W.LOW_CHARGE and colors.warnStrong or colors.accent)
    elseif watch then
        rect(el, ix, iy, iw, ih, colors.errorText, 0.5)
    end
end

-- ===== 槽位區（Focus 目標＋拖放）=====
local Sockets = ISUIElement:derive("MinidoracatWatchSockets")

-- 槽位外框（i＝panel:slots() 的索引；Sockets 的元素座標）：內建 6 格依皮膚版面，其他 MOD 的槽位在錶面下方一列一列排
local RING = {}
for i, deg in ipairs({ -150, -90, -30, 30, 90, 150 }) do
    RING[i] = { math.cos(deg * math.pi / 180), math.sin(deg * math.pi / 180) }
end
local HEX = { { 1, 0 }, { 3, 0 }, { 5, 0 }, { 2, 1 }, { 4, 1 }, { 6, 1 } }
local FACE_H = { ring = 280, hex = 218, plates = 232, row = 146 }

function Sockets:faceH() return FACE_H[self.layout] or FACE_H.plates end

function Sockets:socketRect(i)
    local L = self.layout
    if i > 6 then
        local j = i - 7
        local per = math.floor((LEFT_W + ADDON_GAP) / (ADDON + ADDON_GAP))
        local col, row = j % per, math.floor(j / per)
        return col * (ADDON + ADDON_GAP), self:faceH() + fontH() + 10 + row * (ADDON + ADDON_GAP + 4), ADDON
    end
    if L == "ring" then
        local r, cx, cy = 104, LEFT_W / 2, 130
        return math.floor(cx + RING[i][1] * r - SOCK / 2), math.floor(cy + RING[i][2] * r - SOCK / 2), SOCK
    elseif L == "hex" then
        local colW = LEFT_W / 7
        return math.floor(HEX[i][1] * colW - SOCK / 2 + colW / 2), 78 + HEX[i][2] * 66, SOCK
    elseif L == "row" then
        local s = 44
        return math.floor((i - 0.5) * LEFT_W / 6 - s / 2), 80, s
    end
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    return math.floor((col + 0.5) * LEFT_W / 3 - SOCK / 2), 78 + row * 78, SOCK
end

function Sockets:socketAt(x, y)
    for i = 1, #panel:slots() do
        local sx, sy, s = self:socketRect(i)
        if x >= sx and x < sx + s and y >= sy and y < sy + s then return i end
    end
    return nil
end

function Sockets:areaH()
    local n = #panel:slots()
    if n <= 6 then return self:faceH() end
    local _, y, s = self:socketRect(n)
    return y + s + 20
end

function Sockets:drawSocket(i, player, watch, colors, drop)
    local p = panel
    local slot = p:slots()[i]
    local x, y, s = self:socketRect(i)
    local k = s / SOCK
    local st, rec = C.slotStatus(player, watch, slot)
    local closed = st == "locked" or st == "off" or st == "lapsed"
    local tier = colors[TIER_TOKEN[slot.tier]] or colors.tierStd
    local a = drop == false and 0.35 or 1
    local tex = p.tex
    if i == p.sel or drop == true then
        local pulse = drop == true and (0.55 + 0.45 * math.abs(math.sin(getTimestampMs() / 250))) or 1
        tint(self, tex.sel, x, y, s, s, colors.ring, pulse * a)
    end
    if tex.deco and colors.sticker then tint(self, tex.deco, x, y, s, s, colors.sticker, a) end
    tint(self, tex.ring, x, y, s, s, tier, (closed and 0.45 or 1) * a)
    tint(self, tex.fill, x, y, s, s, closed and colors.socketLocked or colors.socket, a)
    local UI = C.ui()
    -- 四角的鉚釘（遊騎兵）／寶石爪（盧瑟斯）：設計稿座標 12／44、直徑 3.2／6.4（56px 槽）
    local dotC = p.skin == "ranger" and colors.rivet or (p.skin == "luthex" and colors.ring)
    if dotC then
        local at, d = p.skin == "ranger" and 12 or 12.1, p.skin == "ranger" and 3.2 or 6.4
        local ds = math.max(2, math.floor(d * k))
        for cx = 0, 1 do
            for cy = 0, 1 do
                UI.Skin.dot(self, x + math.floor((cx == 0 and at or SOCK - at) * k - ds / 2),
                    y + math.floor((cy == 0 and at or SOCK - at) * k - ds / 2), ds, dotC)
            end
        end
    end
    local icon = rec and moduleIcon(rec.item)
    local g = math.floor(22 * k)
    local gx, gy = x + math.floor((s - g) / 2), y + math.floor((s - g) / 2)
    if icon and icon.tex then
        local is = math.floor(s * 0.55)
        self:drawTextureScaled(icon.tex, x + (s - is) / 2, y + (s - is) / 2, is, is, (st == "active" and 1 or 0.45) * a,
            icon.r, icon.g, icon.b)
    elseif closed then
        UI.Icons.draw(self, st == "lapsed" and "clock" or "lock", gx, gy, g, colors.textMuted, a)
    elseif st == "empty" then
        UI.Icons.draw(self, "plus", gx, gy, g, colors.glyph, a)
    end
    -- 狀態徽章（右下角）：停用／沒電＝暫停、租約到期＝時鐘
    if st == "paused" or st == "dead" then
        local b = math.floor(20 * k)
        UI.Skin.dot(self, x + s - b + 1, y + s - b + 1, b, colors.surface, colors.textMuted)
        UI.Icons.draw(self, "pause", x + s - b + 1 + math.floor(b / 5), y + s - b + 1 + math.floor(b / 5), b - 2 * math.floor(b / 5),
            colors.textMuted)
    end
    -- 計時動作中：底部進度條
    local busy = p:busyAction(player, watch, slot)
    if busy then
        local delta = busy.action and busy:getJobDelta() or 0.5
        rect(self, x + 8 * k, y + s - 9 * k, math.max(1, (s - 16 * k) * delta), math.max(2, 4 * k), colors.accent)
    end
    -- 等級標籤（非標準槽，大格才畫）
    if slot.tier ~= "std" and s >= 44 then
        local label = getText("IGUI_MinidoracatWatch_Tag_" .. slot.tier)
        local tw = measure(label) + 12
        local ty = y + s + 1
        p.theme:fill(self, x + math.floor((s - tw) / 2), ty, tw, fontH() + 2, tier, "pill")
        text(self, label, x + math.floor((s - tw) / 2) + 6, ty + 1, colors.tagText)
    end
end

function Sockets:prerender()
    local p = panel
    if not p then return end
    local player, watch = p:target()
    if not (player and watch) then return end
    local colors = p.theme.colors
    local UI = C.ui()
    -- 錶面：圓底（槽位的圓形貼圖，圓在 56 格裡的直徑是 40）＋錶的物品圖示（環狀版面在正中央，其他版面在槽位上方）
    local cx, cy = LEFT_W / 2, self.layout == "ring" and 130 or 36
    local face = self.layout == "ring" and 120 or 70
    local disc = shapeTex("sock_circle_fill")
    local outer, inner = (face + 3) * 56 / 40, face * 56 / 40
    tint(self, disc, cx - outer / 2, cy - outer / 2, outer, outer, colors.border)
    tint(self, disc, cx - inner / 2, cy - inner / 2, inner, inner, colors.well)
    local tex = watch:getTex() -- InventoryItem.java:678
    if tex then self:drawTextureScaled(tex, cx - DIAL / 2, cy - DIAL / 2, DIAL, DIAL, 1, 1, 1, 1) end
    local item, def = draggedModule()
    local over = item and self:isMouseOver() and self:socketAt(self:getMouseX(), self:getMouseY())
    local why
    local list = p:slots()
    for i = 1, #list do
        local drop = nil
        if item then
            local ok, reason = C.dropCheck(player, watch, list[i], def)
            drop = ok
            if i == over then why = reason end
        end
        self:drawSocket(i, player, watch, colors, drop)
    end
    if #list > 6 then
        local y = self:faceH() + 4
        rect(self, 0, y, LEFT_W, 1, colors.border)
        text(self, getText("IGUI_MinidoracatWatch_OtherMods"), 0, y + 4, colors.textMuted)
    end
    -- 拖曳中滑過不能裝的槽位：原因寫在錶面底部（放開時另以 Toast 提示）
    if why then
        local lines = wrap(why, LEFT_W - 16)
        local h = #lines * fontH() + 10
        local y = self:faceH() - h
        p.theme:fill(self, 0, y, LEFT_W, h, "warnSurface", shapeOf(UI, p.theme, "control"))
        para(self, why, 8, y + 5, LEFT_W - 16, colors.warnText)
    end
end

function Sockets:onMouseDown(x, y)
    local i = self:socketAt(x, y)
    if i then panel:select(i) end
    return true
end

function Sockets:onMouseUp(x, y)
    local item, def = draggedModule()
    if not item then return true end
    local i = self:socketAt(x, y)
    local player, w = panel:target()
    if i and player and w then
        panel:select(i)
        panel:dropOn(player, w, panel:slots()[i], item, def)
    end
    return true
end

-- Focus：游標框目前那格；方向鍵往該方向最近的一格（主軸距離＋2×側向偏移最小）；Enter／Space／A 選取
function Sockets:focusRect()
    local x, y, s = self:socketRect(self.cur or panel.sel)
    return x, y, s, s
end

local DIRS -- 方向鍵 → { dx, dy }（Keyboard 常數在遊戲裡才有，第一次用到才建）
function Sockets:move(dx, dy)
    local cur = self.cur or panel.sel
    local x0, y0, s0 = self:socketRect(cur)
    x0, y0 = x0 + s0 / 2, y0 + s0 / 2
    local best, bestScore = nil, 1e9
    for i = 1, #panel:slots() do
        if i ~= cur then
            local x, y, s = self:socketRect(i)
            local ddx, ddy = x + s / 2 - x0, y + s / 2 - y0
            local main, side = ddx * dx + ddy * dy, math.abs(ddx * dy) + math.abs(ddy * dx)
            if main > 4 and main + 2 * side < bestScore then best, bestScore = i, main + 2 * side end
        end
    end
    if not best then return false end
    self.cur = best
    panel:refreshFocusLabel()
    return true
end

function Sockets:onFocusKey(key)
    if not DIRS then
        DIRS = { [Keyboard.KEY_LEFT] = { -1, 0 }, [Keyboard.KEY_RIGHT] = { 1, 0 }, [Keyboard.KEY_UP] = { 0, -1 },
            [Keyboard.KEY_DOWN] = { 0, 1 } }
    end
    local d = DIRS[key]
    if d then return self:move(d[1], d[2]) end
    if key == Keyboard.KEY_RETURN or key == Keyboard.KEY_NUMPADENTER or key == Keyboard.KEY_SPACE then
        self:forceClick()
        return true
    end
    return false
end

function Sockets:forceClick() panel:select(self.cur or panel.sel) end

-- ===== 面板（UI.Window 子類別；類別在第一次開面板時才建：框架可能比本檔晚載入）=====
local M = {}
local Panel

-- 面板對象：從右鍵選單開的那支（還在玩家身上時），否則是戴著的那支
function M:target()
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
function M:slots() return self.slotView or W.slotList end

function M:selectedSlot()
    local list = self:slots()
    return list[self.sel] or list[1]
end

function M:select(i)
    self.sel = i
    self.sockets.cur = i
    self.scanAt = nil
    self:refreshFocusLabel()
end

function M:refreshFocusLabel()
    local player, w = self:target()
    local slot = self:slots()[self.sockets.cur or self.sel]
    if not (slot and player and w) then return end
    local st = C.slotStatus(player, w, slot)
    -- 焦點說明：Focus 在聚焦那一刻記下描述的 label，之後游標換格不會更新；captionOf 每幀讀控制項的 tooltip
    -- （Focus.lua captionOf：沒有 title 時用 tooltip），所以游標那格的名稱與狀態放在 tooltip
    local label = getText("IGUI_MinidoracatWatch_SlotAndModule", C.slotName(slot), getText("IGUI_MinidoracatWatch_St_" .. st))
    self.sockets._focusLabel, self.sockets.tooltip = label, label
end

-- 正在對這支錶的這個槽位跑的計時動作（佇列第一個；ISTimedActionQueue.getTimedActionQueue）
function M:busyAction(player, watch, slot)
    local q = ISTimedActionQueue.getTimedActionQueue(player)
    local a = q and q.queue and q.queue[1]
    if a and a.Type == BUSY_TYPE and a.kind == "module" and a.watch == watch and a.slotId == slot.id then return a end
    return nil
end

function M:build()
    local UI = C.ui()
    local function button(title, icon, style, fn, insp)
        local b = UI.Button.new({ x = 0, y = 0, title = title, icon = icon, style = style, theme = insp and self.inspTheme or self.theme,
            target = self, onClick = fn })
        b._watchInsp = insp
        b:setVisible(false)
        self:addChild(b)
        return b
    end
    self.sockets = Sockets:new(PAD, 0, LEFT_W, 10)
    self.sockets._focusKind = "button"
    self.sockets:initialise()
    self:addChild(self.sockets)
    self.btnBanner = button("", "battery", "normal", M.onInsert)
    -- 檢視區的動作按鈕池：模組清單、解鎖卡、拆下模組、付費按鈕（標題、圖示、樣式由 scan 的 actions 決定）
    self.actBtns = {}
    for i = 1, MAX_ACTIONS do self.actBtns[i] = button("", nil, "normal", M.onAction, true) end
    self.btnInsert = button(getText("IGUI_MinidoracatWatch_InsertBattery"), "battery", "normal", M.onInsert)
    self.btnRemove = button(getText("IGUI_MinidoracatWatch_RemoveBattery"), "eject", "normal", M.onRemove)
    self.btnScreen = button(getText("IGUI_MinidoracatWatch_ScreenAmber"), nil, "normal", M.onScreen)
    -- 照明模組的開關（MinidoracatWatch_LightClient.lua）：戴著的錶裝了照明模組才出現；chip（§3.7：active＝燈開著）
    self.btnLight = button(getText("IGUI_MinidoracatWatch_LightOn"), "lightbulb", "chip", M.onLight)
    self.footBtns = { self.btnLight, self.btnScreen, self.btnRemove, self.btnInsert } -- 由右而左
end

-- 皮膚：依錶款（嗶嗶腕機另看螢幕色）換 theme、版面與槽位外形；所有框架元件一起換
function M:applySkin(key)
    local UI = C.ui()
    local spec = S.spec(key)
    self.skinKey, self.skin = key, key == "crt-amber" and "crt" or key
    self.theme, self.inspTheme, self.footTheme = S.themes(UI, key)
    self.shape, self.mono = spec.shape, spec.mono == true
    self.tex = { sel = shapeTex("sock_" .. spec.shape .. "_sel"), ring = shapeTex("sock_" .. spec.shape .. "_ring"),
        fill = shapeTex("sock_" .. spec.shape .. "_fill"), deco = spec.shape == "circle" and shapeTex("sock_circle_deco") or nil }
    self.sockets.layout = spec.layout
    for _, b in ipairs(self.actBtns) do b.theme = self.inspTheme end
    for _, b in ipairs(self.footBtns) do b.theme = self.footTheme end
    self.btnBanner.theme = self.theme
end

-- 背包與錶的掃描（解鎖卡、電池、孤立槽位、付費檢視、動作按鈕、功能清單）每 250ms 一次，不在每幀翻背包
function M:scan(player, watch, slot)
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
    self.payUi = C.Pay.ui(player, watch, slot)
    self.actions = self:buildActions(player, watch, slot)
    self.feats = self:buildFeatures()
    self:refreshFocusLabel()
end

-- 檢視區的動作：{ id, 標題, 可按, 樣式, 圖示, def＝要裝的模組 }
function M:buildActions(player, watch, slot)
    local out = {}
    self.noModule = false
    if not watch or self:busyAction(player, watch, slot) then return out end
    local function add(id, title, enabled, style, icon, def)
        out[#out + 1] = { id = id, title = title, enabled = enabled, style = style or "normal", icon = icon, def = def }
    end
    local function modules()
        local inv = player:getInventory()
        for _, def in ipairs(W.moduleList) do
            if slot.accepts[def.class] and inv:getAllTypeRecurse(def.item):size() > 0 then
                local m = moduleIcon(def.item)
                add("module", C.moduleName(def.id), true, "normal", m and m.tex, def)
            end
        end
        self.noModule = #out == 0
    end
    local st = C.slotStatus(player, watch, slot)
    local ui = self.payUi
    if ui and not ui.keep then
        for _, b in ipairs(ui.buttons) do
            if b[1] == "install" then modules() else add(b[1], b[2], b[3], b[4], PAY_ICON[b[1]]) end
        end
    elseif st == "empty" then
        modules()
    elseif st == "locked" then
        add("card", getText("IGUI_MinidoracatWatch_UseSlotCard", C.cardName(slot)), self.cardCount > 0, "primary", "card")
    elseif st ~= "off" then
        add("remove", getText("IGUI_MinidoracatWatch_RemoveModule"), true, "normal", "screwdriver")
    end
    return out
end

-- 功能清單：{ 標籤, 說明, 圖示 }（可用＝勾、停用＝暫停、缺模組／沒開放＝叉）
function M:buildFeatures()
    local out = {}
    for _, f in ipairs(FEATURES) do
        local ok, reason = C.gate(self.playerNum, f, "mini")
        local icon = ok and "check" or (PAUSE_REASONS[reason] and "pause" or "close")
        local label, note = getText("IGUI_MinidoracatWatch_Feature_" .. f), (not ok and reason) and getText(reason) or nil
        local w = 10 + 16 + 5 + measure(label) + (note and 6 + measure(note) or 0) + 10
        out[#out + 1] = { label = label, note = note, icon = icon, ok = ok, w = w }
    end
    return out
end

-- 標題列下的橫幅：{ 文字, 底色 token, 字色 token, 框 token, 圖示, 電池按鈕樣式（nil＝不放按鈕）}
function M:banner(player, watch)
    if watch ~= C.watchOf(self.playerNum) then
        return getText("IGUI_MinidoracatWatch_Banner_NotWorn"), "warnSurface", "warnText", "warnLine", "warning", nil
    end
    local c = W.charge(watch)
    if c == nil then
        return getText("IGUI_MinidoracatWatch_Banner_NoBattery"), "errorSurface", "errorText", "errorLine", "battery", "primary"
    end
    if c <= 0 then
        return getText("IGUI_MinidoracatWatch_Banner_Dead"), "errorSurface", "errorText", "errorLine", "battery", "primary"
    end
    if c <= W.LOW_CHARGE then
        return getText("IGUI_MinidoracatWatch_Banner_Low", tostring(C.percent(c)), C.timeText(c, C.fullRuntime(player, watch))),
            "warnSurface", "warnText", "warnLine", "warning", "normal"
    end
    -- 經濟系統的租約到期、自動續租還在重試（設計稿 banner grace）
    local retry = C.Pay.bannerText(player, watch)
    if retry then return retry, "warnSurface", "warnText", "warnLine", "clock", nil end
    return nil
end

-- 底部電量列的文字（充電中：MinidoracatWatch.lua 的 W.chargeState／W.chargeHoursToFull，有才顯示）
function M:composeFoot(player, watch)
    local c = watch and W.charge(watch)
    if not watch then return getText("IGUI_MinidoracatWatch_Status_NoWatch") end
    if c == nil then return getText("IGUI_MinidoracatWatch_Foot_NoBattery") end
    if c <= 0 then return getText("IGUI_MinidoracatWatch_Foot_Dead") end
    local hours = C.fullRuntime(player, watch)
    local d, h = W.timeLeft(c, hours)
    local full = C.timeText(1, hours)
    local s
    if d == 0 and h == 0 then
        s = getText("IGUI_MinidoracatWatch_Foot_ChargeUnderHour", tostring(C.percent(c)), full)
    else
        s = getText("IGUI_MinidoracatWatch_Foot_Charge", tostring(C.percent(c)), C.timeText(c, hours), full)
    end
    if W.lightLit(player, watch) then s = getText("IGUI_MinidoracatWatch_Foot_LightOn", s) end
    local where = type(W.chargeState) == "function" and W.chargeState(player)
    local toFull = where and type(W.chargeHoursToFull) == "function" and W.chargeHoursToFull(player, watch)
    if (where == "car" or where == "house") and toFull then
        s = getText(where == "car" and "IGUI_MinidoracatWatch_Foot_ChargingCar" or "IGUI_MinidoracatWatch_Foot_ChargingHouse",
            s, C.timeText(1, toFull))
    end
    return s
end

-- 由左到右排一列按鈕、放不下換行；最後一列底緣貼在 bottom，多的列往上長。回第一列的 y
local function flow(btns, n, left, right, bottom, gap)
    local rowH, rows, x = 0, 1, left
    for i = 1, n do
        local b = btns[i]
        rowH = math.max(rowH, b.height)
        if i > 1 and x + b.width > right then rows, x = rows + 1, left end
        x = x + b.width + gap
    end
    local y = bottom - rows * rowH - (rows - 1) * 6
    local top = y
    x = left
    for i = 1, n do
        local b = btns[i]
        if i > 1 and x + b.width > right then x, y = left, y + rowH + 6 end
        b:setX(x)
        b:setY(y)
        b:setVisible(true)
        x = x + b.width + gap
    end
    return top
end

function M:update()
    C.ui().Window.update(self)
    local player, w = self:target()
    local key = S.keyOf(w)
    if key ~= self.skinKey then self:applySkin(key) end
    local slot = self:selectedSlot()
    if player then self:scan(player, w, slot) end
    if w then
        self:setTitle(w:getDisplayName())
        self.icon = w:getTex()
    else
        self:setTitle(getText("IGUI_MinidoracatWatch_DockLabel"))
        self.icon = nil
    end
    self:arrange(player, w)
end

-- 版面：橫幅、槽位區、檢視區按鈕、功能清單、電量列依內容排位；視窗高度跟著內容
function M:arrange(player, w)
    local th, fh, width = self:contentTop(), fontH(), self.width
    local y = th + GAP
    -- 橫幅
    local msg, bstyle
    if player and w then
        local m, _, _, _, _, s = self:banner(player, w)
        msg, bstyle = m, s
    end
    local bb = self.btnBanner
    local showBtn = msg ~= nil and bstyle ~= nil and self.hasBattery == true
    bb:setVisible(showBtn)
    self.bannerY, self.bannerH, self.bannerMsg = y, 0, msg
    if msg then
        local c = W.charge(w)
        bb:setTitle(getText(c ~= nil and "IGUI_MinidoracatWatch_ReplaceBattery" or "IGUI_MinidoracatWatch_InsertBattery"))
        bb:setStyle(bstyle or "normal")
        self.bannerTextW = width - 2 * PAD - 44 - (showBtn and bb.width + 10 or 0)
        local h = math.max(bb.height + 12, #wrap(msg, self.bannerTextW) * fh + 16)
        self.bannerH = h
        bb:setX(width - PAD - 10 - bb.width)
        bb:setY(y + math.floor((h - bb.height) / 2))
        y = y + h + GAP
    end
    -- 槽位區與檢視區
    self.bodyY = y
    local sk = self.sockets
    sk:setY(y)
    sk:setVisible(player ~= nil and w ~= nil)
    local leftH = sk:areaH()
    if sk.height ~= leftH then sk:setHeight(leftH) end
    self.bodyH = math.max(leftH, INSP_MIN_H)
    local acts = self.actions or {}
    local n = (player and w) and math.min(#acts, MAX_ACTIONS) or 0
    local inspW = width - INSP_X - PAD
    for i = 1, n do
        local b, a = self.actBtns[i], acts[i]
        b:setTitle(a.title)
        b:setIcon(a.icon)
        b:setStyle(a.style)
        b:setEnabled(a.enabled)
        b.internal, b.def = a.id, a.def
        if b.width > inspW then b:setWidth(inspW) end
    end
    for i = n + 1, MAX_ACTIONS do self.actBtns[i]:setVisible(false) end
    self.actTop = flow(self.actBtns, n, INSP_X, width - PAD, y + self.bodyH, 8)
    y = y + self.bodyH + GAP
    -- 功能清單（膠囊，放不下換行）
    self.featY = y
    local x, rows = PAD, 1
    for i, f in ipairs(self.feats or {}) do
        if i > 1 and x + f.w > width - PAD then x, rows = PAD, rows + 1 end
        f.x, f.y = x, y + (rows - 1) * (fh + 12)
        x = x + f.w + 6
    end
    y = y + rows * (fh + 12) + GAP
    -- 底部電量列：右側按鈕（由右而左），左側文字換行
    local c = w and W.charge(w)
    self.btnInsert:setTitle(getText(c ~= nil and "IGUI_MinidoracatWatch_ReplaceBattery" or "IGUI_MinidoracatWatch_InsertBattery"))
    self.btnInsert:setEnabled(w ~= nil and self.hasBattery == true)
    self.btnInsert:setStyle((w and (c == nil or c <= 0)) and "primary" or "normal")
    self.btnRemove:setEnabled(w ~= nil and c ~= nil)
    local screen = W.hasScreen(w)
    if screen then self.btnScreen:setTitle(C.screenLabel(w)) end
    local e = player and w and w == C.watchOf(self.playerNum) and W.status(player)
    local hasLight = e and W.modState(e, "light") ~= nil
    if hasLight then
        local on = W.lightOn(player)
        self.btnLight:setTitle(getText(on and "IGUI_MinidoracatWatch_LightOff" or "IGUI_MinidoracatWatch_LightOn"))
        self.btnLight:setActive(on == true)
        self.btnLight:setEnabled(on or W.lightAllowed(player) == true)
    end
    local show = { hasLight == true, screen == true, true, true }
    local right, maxH = width - PAD, 0
    for i, b in ipairs(self.footBtns) do
        b:setVisible(show[i])
        if show[i] then
            right = right - b.width
            b:setX(right)
            right = right - 8
            maxH = math.max(maxH, b.height)
        end
    end
    self.footText = self:composeFoot(player, w)
    self.footTextW = right - PAD - 4
    local footH = math.max(maxH + 16, #wrap(self.footText, self.footTextW) * fh + 16)
    self.footY, self.footH = y, footH
    for _, b in ipairs(self.footBtns) do b:setY(y + math.floor((footH - b.height) / 2)) end
    local h = y + footH
    if h ~= self.height then self:setHeight(h) end
end

-- ===== 繪製 =====
function M:drawHeader(UI, colors, w)
    local th = self:contentTop()
    rect(self, 0, th - (self.skin == "crt" and 2 or 1), self.width, self.skin == "crt" and 2 or 1, colors.headLine)
    if self.skin == "spiffo" then
        for x = 0, self.width - 1, 32 do
            rect(self, x, th, math.min(16, self.width - x), 6, colors.stripeA)
            rect(self, x + 16, th, math.max(0, math.min(16, self.width - x - 16)), 6, colors.stripeB)
        end
    elseif self.skin == "ranger" then
        UI.Skin.dot(self, 5, 5, 5, colors.rivet)
        UI.Skin.dot(self, self.width - th - 10, 5, 5, colors.rivet)
    end
    -- 電量膠囊（關閉鈕左邊）：低電量＝警示色、沒電＝錯誤色；嗶嗶腕機的數字用等寬字
    local c = w and W.charge(w)
    if c == nil then return end
    local f = self.mono and UIFont.Code or UIFont.Small
    local pct = C.percent(c) .. "%"
    local pw = 6 + 20 + 4 + measure(pct, f) + 8
    local px, ph = self.width - th - 6 - pw, th - 8
    local bg, fg = colors.battSurface or colors.well, colors.battText or colors.text
    if c <= 0 then bg, fg = colors.errorSurface, colors.errorText
    elseif c <= W.LOW_CHARGE then bg, fg = colors.warnSurface, colors.warnText end
    self.theme:fill(self, px, 4, pw, ph, bg, "pill")
    C.drawBattery(self, px + 6, 4 + math.floor((ph - 20) / 2), 20, w, self.theme)
    text(self, pct, px + 30, 4 + math.floor((ph - fontH(f)) / 2), fg, f)
end

function M:drawBanner(UI, colors, player, w)
    local msg, bg, fg, line, icon = self:banner(player, w)
    if not msg then return end
    local x, y, bw, h = PAD, self.bannerY, self.width - 2 * PAD, self.bannerH
    local shape = shapeOf(UI, self.theme, "control")
    self.theme:fill(self, x, y, bw, h, bg, shape)
    self.theme:border(self, x, y, bw, h, line, shape)
    UI.Icons.draw(self, icon, x + 12, y + math.floor((h - 18) / 2), 18, colors[fg])
    local lines = wrap(msg, self.bannerTextW)
    para(self, msg, x + 38, y + math.floor((h - #lines * fontH()) / 2), self.bannerTextW, colors[fg])
end

-- 膠囊：底色 token、圖示、文字（＋說明）。回寬度
local function chip(el, theme, x, y, h, bgTok, fgTok, icon, label, outline)
    local colors = theme.colors
    local w = 8 + (icon and 18 or 0) + measure(label) + 8
    if outline then theme:border(el, x, y, w, h, "border", "pill") else theme:fill(el, x, y, w, h, bgTok, "pill") end
    local tx = x + 8
    if icon then
        C.ui().Icons.draw(el, icon, tx, y + math.floor((h - 14) / 2), 14, colors[fgTok])
        tx = tx + 18
    end
    text(el, label, tx, y + math.floor((h - fontH()) / 2), colors[fgTok])
    return w
end

-- 資訊格（類別、耗電、槽位）：well 底＋換行文字。回下一格的 x
local function kvBox(el, theme, x, y, w, h, s, shape)
    theme:fill(el, x, y, w, h, "well", shape)
    para(el, s, x + 6, y + 5, w - 12, theme.colors.text)
    return x + w + 6
end

-- 資訊框：底色＋圖示＋換行文字。回下一個 y
local function box(el, theme, x, y, width, s, icon, kind)
    local UI, colors = C.ui(), theme.colors
    local lines = wrap(s, width - 40)
    local h = #lines * fontH() + 16
    local bg, fg = "well", "text"
    if kind == "warn" then bg, fg = "warnSurface", "warnText" end
    local shape = shapeOf(UI, theme, "control")
    if kind == "paused" then theme:border(el, x, y, width, h, "border", shape) else theme:fill(el, x, y, width, h, bg, shape) end
    UI.Icons.draw(el, icon, x + 10, y + 9, 18, colors[fg])
    para(el, s, x + 34, y + 8, width - 40, colors[fg])
    return y + h + 8
end

function M:drawInspector(UI, player, watch, slot)
    local theme = self.inspTheme
    local colors = theme.colors
    local x, y, width = INSP_X, self.bodyY, self.width - INSP_X - PAD
    if self.skin == "valutech" then
        -- 液晶檢視區（styles.mjs:325）：綠灰底＋2px 內框
        theme:fill(self, x - 10, y - 6, width + 20, self.bodyH + 12, "surface", shapeOf(UI, theme, "control"))
        for i = 0, 1 do self:drawRectBorder(x - 10 + i, y - 6 + i, width + 20 - 2 * i, self.bodyH + 12 - 2 * i, 1,
            colors.border.r, colors.border.g, colors.border.b) end
    end
    local fh = fontH()
    local st, rec = C.slotStatus(player, watch, slot)
    local name = C.slotName(slot)
    local busy = self:busyAction(player, watch, slot)
    local ui = self.payUi
    local stKey = busy and (busy.install and "Installing" or "Removing") or (ui and ui.chip) or st
    -- 等級膠囊＋狀態膠囊
    local tier = TIER_TOKEN[slot.tier] or "tierStd"
    local cx = x + chip(self, theme, x, y, fh + 6, tier, "tagText", nil, getText("IGUI_MinidoracatWatch_Tag_" .. slot.tier)) + 6
    local muted = st == "paused" or st == "dead" or st == "locked" or st == "empty" or st == "off"
    chip(self, theme, cx, y, fh + 6, (stKey == "lapsed") and "warnSurface" or "well",
        stKey == "lapsed" and "warnText" or (muted and "textMuted" or "text"), STATUS_ICON[stKey], getText("IGUI_MinidoracatWatch_St_" .. stKey))
    y = y + fh + 14
    local mh = fontH(UIFont.Medium)
    if busy then
        local mod = busy.install and C.moduleName(W.moduleByItem[busy.item:getFullType()].id) or C.moduleName(rec and rec.id or "")
        para(self, getText(busy.install and "IGUI_MinidoracatWatch_BusyInstall" or "IGUI_MinidoracatWatch_BusyRemove",
            mod, name), x, y, width, colors.text)
        return
    end
    local function payLines(yy)
        for _, l in ipairs(ui.lines) do yy = para(self, l[1], x, yy, width, colors[l[2]] or colors.text) + 4 end
        return yy
    end
    local cardNote = W.slotMode(slot) == "card" and st ~= "locked"
    if not rec then
        text(self, getText("IGUI_MinidoracatWatch_SlotTitle_" .. st, name), x, y, colors.text, UIFont.Medium)
        y = y + mh + 6
        if st == "off" then
            para(self, getText("IGUI_MinidoracatWatch_Desc_Off", name), x, y, width, colors.text)
            return
        end
        y = para(self, getText("IGUI_MinidoracatWatch_Desc_Accepts", acceptsText(slot)), x, y, width, colors.text) + 4
        if slot.tier == "core" then y = para(self, getText("IGUI_MinidoracatWatch_Desc_Core"), x, y, width, colors.text) + 4 end
        if slot.tier == "addon" then y = para(self, getText("IGUI_MinidoracatWatch_Desc_Addon"), x, y, width, colors.text) + 4 end
        if ui and not ui.keep then
            y = payLines(y)
        elseif st == "locked" then
            y = box(self, theme, x, y, width, getText("IGUI_MinidoracatWatch_Desc_Card", C.cardName(slot), name), "card")
            local note = self.cardCount > 0 and getText("IGUI_MinidoracatWatch_CardCount", tostring(self.cardCount))
                or getText("IGUI_MinidoracatWatch_CardNone", C.cardName(slot))
            y = para(self, note, x, y, width, colors.textMuted) + 4
            if ui then payLines(y) end
            return
        else
            y = para(self, getText("IGUI_MinidoracatWatch_Desc_Empty"), x, y, width, colors.textMuted) + 4
            if ui then y = payLines(y) end
        end
        if self.noModule then para(self, getText("IGUI_MinidoracatWatch_NoModuleToInstall"), x, y, width, colors.textMuted) end
        return
    end
    local def = W.modules[rec.id]
    text(self, def and C.moduleName(def.id) or rec.item, x, y, colors.text, UIFont.Medium)
    y = y + mh + 6
    if def and W.BUILTIN[def.id] then y = para(self, C.moduleDesc(def.id), x, y, width, colors.text) + 6 end
    -- 類別／耗電／槽位：三格資訊（未知模組只有槽位一格）
    local kw = math.floor((width - 12) / 3)
    local kSlot = getText("IGUI_MinidoracatWatch_KV_Slot", name)
    local kh = #wrap(kSlot, kw - 12) * fh + 10
    local kx, shape = x, shapeOf(UI, theme, "control")
    if def then
        local kClass = getText("IGUI_MinidoracatWatch_KV_Class", className(def.class))
        local kDrain = getText("IGUI_MinidoracatWatch_KV_Drain", drainText(def))
        kh = math.max(kh, #wrap(kClass, kw - 12) * fh + 10, #wrap(kDrain, kw - 12) * fh + 10)
        kx = kvBox(self, theme, kx, y, kw, kh, kClass, shape)
        kx = kvBox(self, theme, kx, y, kw, kh, kDrain, shape)
    end
    kvBox(self, theme, kx, y, kw, kh, kSlot, shape)
    y = y + kh + 8
    if slot.orphan then
        y = box(self, theme, x, y, width, getText("IGUI_MinidoracatWatch_Desc_Orphan"), "warning", "warn")
    elseif st == "dead" then
        y = box(self, theme, x, y, width, getText("IGUI_MinidoracatWatch_Desc_Dead"), "pause", "paused")
    elseif st == "paused" and not (ui and not ui.keep) then
        y = box(self, theme, x, y, width, getText("IGUI_MinidoracatWatch_Desc_Paused", name), "pause", "paused")
    end
    if ui then y = payLines(y) end
    if cardNote then box(self, theme, x, y, width, getText("IGUI_MinidoracatWatch_Desc_CardOpened"), "card") end
end

function M:drawFeatures(colors)
    local h = fontH() + 8
    for _, f in ipairs(self.feats or {}) do
        local fg = f.ok and "text" or "textMuted"
        chip(self, self.theme, f.x, f.y, h, "well", fg, f.icon, f.note and (f.label .. "  " .. f.note) or f.label, not f.ok)
    end
end

function M:drawFooter(UI, colors)
    local y, h, r = self.footY, self.footH, 24
    local foot = colors.footSurface or colors.surfaceTitle
    -- 底色往上多畫 r 再用 surface 蓋回：下緣跟著視窗圓角、上緣是直的
    self.theme:fill(self, 0, y - r, self.width, h + r, foot, shapeOf(UI, self.theme, "panel"))
    rect(self, 0, y - r, self.width, r, colors.surface)
    rect(self, 0, y, self.width, self.skin == "crt" and 2 or 1, self.skin == "crt" and colors.headLine or colors.border)
    if self.skin == "ranger" then
        UI.Skin.dot(self, 5, y + 5, 5, colors.rivet)
        UI.Skin.dot(self, self.width - 10, y + 5, 5, colors.rivet)
    end
    local lines = wrap(self.footText, self.footTextW)
    para(self, self.footText, PAD, y + math.floor((h - #lines * fontH()) / 2), self.footTextW, colors.titleText)
end

local SCAN_LINE = { r = 0, g = 0, b = 0, a = 0.2 }

function M:prerender()
    C.ui().Window.prerender(self)
    local UI = C.ui()
    local colors = self.theme.colors
    local player, w = self:target()
    if self.skin == "paws" then
        local ear = shapeTex("ear")
        tint(self, ear, 24, -15, 30, 22, colors.deco)
        tint(self, ear, 66, -15, 30, 22, colors.deco)
    end
    self:drawFooter(UI, colors)
    self:drawHeader(UI, colors, w)
    if not (player and w) then
        para(self, C.statusText(nil), PAD, self.bodyY or 40, self.width - 2 * PAD, colors.text)
        return
    end
    if self.skin == "crt" then
        -- 掃描線（styles.mjs:340）：畫在內容底下
        for y = self.bodyY, self.bodyY + self.bodyH, 3 do rect(self, PAD, y, self.width - 2 * PAD, 1, SCAN_LINE) end
    end
    self:drawBanner(UI, colors, player, w)
    self:drawInspector(UI, player, w, self:selectedSlot())
    self:drawFeatures(colors)
end

function M:render()
    C.ui().Window.render(self)
    local colors = self.theme.colors
    if self.skin == "nexus" then
        -- 角括號外框（styles.mjs:296-298）
        local a, n, wd, ht = colors.ring, 18, self.width, self.height
        rect(self, -4, -4, n, 2, a); rect(self, -4, -4, 2, n, a)
        rect(self, wd + 4 - n, ht + 2, n, 2, a); rect(self, wd + 2, ht + 4 - n, 2, n, a)
    elseif self.skin == "luthex" then
        local g = colors.gold
        self:drawRectBorder(3, 3, self.width - 6, self.height - 6, 1, g.r, g.g, g.b)
    end
end

-- ===== 拖放與按鈕 =====
function M:dropOn(player, watch, slot, item, def)
    local ok, why = C.dropCheck(player, watch, slot, def)
    if not ok then
        C.toast(player, why)
        return false
    end
    C.requestModule(player, watch, slot.id, item)
    return true
end

function M:onAction(b)
    local id = b and b.internal
    local player, w = self:target()
    if not (player and id) then return end
    local slot = self:selectedSlot()
    if id == "remove" then
        C.requestModule(player, w, slot.id, nil)
    elseif id == "module" then
        local list = b.def and player:getInventory():getAllTypeRecurse(b.def.item)
        if list and list:size() > 0 then C.requestModule(player, w, slot.id, list:get(0)) end
    elseif id == "card" then
        C.requestUnlock(player, slot.id)
    else
        C.Pay.press(id, player, slot)
    end
    self.scanAt = nil -- 下一幀重算檢視區
end

function M:onInsert()
    local player, w = self:target()
    C.requestBattery(player, w, true)
end

function M:onRemove()
    local player, w = self:target()
    C.requestBattery(player, w, false)
end

function M:onScreen()
    local player, w = self:target()
    C.requestScreen(player, w)
end

function M:onLight()
    local player = self:target()
    C.toggleLight(player)
end

-- ===== 開關 =====
local warned = false
local function toastAvoid()
    if not (panel and panel:getIsVisible()) then return nil end
    return panel:getAbsoluteX(), panel:getAbsoluteY(), panel.width, panel.height
end

function C.closePanel()
    local p = panel
    if not p then return end
    panel = nil
    lastX, lastY = p:getX(), p:getY()
    p:setVisible(false) -- Window：放掉手把焦點與焦點框
    p:removeFromUIManager()
end

function C.openPanel(pn, watchItem)
    C.closePanel()
    local UI = C.ui()
    if not UI then
        if not warned then
            warned = true
            W.log("MinidoracatUI API rev 14 (controls + window) not found: the watch panel is unavailable")
        end
        C.toast(getSpecificPlayer(pn), getText("IGUI_MinidoracatWatch_UiTooOld"))
        return
    end
    if not Panel then
        Panel = UI.Window:derive("MinidoracatWatchPanel")
        for k, v in pairs(M) do Panel[k] = v end
        Panel.__index = Panel
        if UI.CAPABILITIES.toastAvoid and UI.Toast and UI.Toast.setAvoid then UI.Toast.setAvoid(LAYOUT_NAME, toastAvoid) end
    end
    local o = UI.Window.new({ x = math.floor((getCore():getScreenWidth() - PANEL_W) / 2), y = 120, width = PANEL_W,
        height = 560, title = "", closable = true, onClose = function() C.closePanel() end })
    setmetatable(o, Panel)
    o.playerNum = pn
    o.watchItem = watchItem
    o.sel = 1
    o.cardCount = 0
    o:build()
    o:applySkin(S.keyOf(watchItem or C.watchOf(pn)))
    o:select(1)
    ISLayoutManager.RegisterWindow(LAYOUT_NAME, UI.Window, o)
    if lastX then
        o:setX(lastX)
        o:setY(lastY)
    end
    panel = o
    o:update()
    o:addToUIManager()
end

function C.togglePanel(pn)
    if panel then C.closePanel() else C.openPanel(pn, nil) end
end

function C.isPanelOpen() return panel ~= nil end
function C.panel() return panel end
C.wrapText = wrap -- 測試用
