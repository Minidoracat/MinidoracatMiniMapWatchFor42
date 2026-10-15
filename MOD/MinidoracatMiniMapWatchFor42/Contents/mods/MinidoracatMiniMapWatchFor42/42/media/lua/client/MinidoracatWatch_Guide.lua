-- MinidoracatWatch_Guide.lua（client）：「取得方式」視窗（2026-10-15 使用者裁定）。左欄 NavList 分六組列 24 樣物品
-- （地圖手錶、模組、核心、負重核心、解鎖卡、電池），右欄寫選到那一樣怎麼拿到：容器、殭屍、製作三段（C.acquireInfo）。
-- 寫多少照開放程度（沙盒 AcquireGuide，W.guideLevel）：1 不開放＝入口都不出現、開著的視窗自己關掉；2 只列取得方式；
-- 3 再加容器的稀有度與殭屍每隻的機率。殭屍規則與逐項倍率只來自伺服器裁切過的清單，伺服器沒送的這裡也寫不出來。
-- 入口：面板功能清單後面的「取得方式」按鈕、點「需要 X 模組」的膠囊（選到那個模組）、齒輪設定「地圖錶」分類的按鈕。
-- 需要 UI 框架 rev 17（NavList）＋ScrollPanel＋Text.wrap；不足時 G.available() 回 false（log 一次），入口都不出現。
-- 右欄是 UI.ScrollPanel、裡面沒有焦點目標：框架把整欄當成一個可捲動的焦點（方向鍵、PgUp／PgDn、手把右搖桿），
-- 內容比視窗高時鍵盤與手把也捲得到。內容每秒重算一次，管理員改設定、伺服器重送清單時跟著變。
require "ISUI/ISUIElement"
require "MinidoracatWatch_Client"
require "MinidoracatWatch_Skins"
local W, C = MinidoracatWatchCore, MinidoracatWatchClient
local G = {}
MinidoracatWatchGuide = G -- 內部表（面板、齒輪設定與 E2E 用），不是公開 API

if not (MinidoracatUI and MinidoracatUI.v1) then pcall(require, "MinidoracatUI/V1") end
pcall(require, "MinidoracatUI/TextWrap")
pcall(require, "MinidoracatUI/Widgets/Controls")
pcall(require, "MinidoracatUI/Widgets/Window")
pcall(require, "MinidoracatUI/Widgets/ScrollPanel")
pcall(require, "MinidoracatUI/Widgets/NavList")

G.UI_REV = 17
G.W, G.H = 640, 480
G.REFRESH_MS = 1000
local PAD, GAP, ICON, SMALL_ICON, INDENT = 12, 12, 24, 16, 20
local FONT = UIFont.Small

local function T(key, ...) return getText("IGUI_MinidoracatWatch_" .. key, ...) end
local function fontH(f) return getTextManager():getFontHeight(f or FONT) end
local function measure(s, f) return getTextManager():MeasureStringX(f or FONT, s) end

local function ui()
    local UI = C.ui()
    local caps = UI and UI.CAPABILITIES
    if UI and UI.API_REVISION >= G.UI_REV and caps.navList == true and caps.scrollPanel == true and caps.textWrap == true
            and UI.NavList and UI.ScrollPanel and UI.Text and type(UI.Text.wrap) == "function" then
        return UI
    end
    return nil
end

local warned = false
-- 入口要不要出現：框架夠新、地圖錶系統開著、開放程度 2 以上
function G.available()
    if not ui() then
        if not warned then
            warned = true
            W.log("MinidoracatUI API rev 17 (navList, scrollPanel, textWrap) not found: no acquisition guide window")
        end
        return false
    end
    return W.enabled() and W.guideLevel() ~= W.GUIDE_OFF
end

-- ===== 物品清單：六組 =====
local function itemTexture(fullType)
    local item = getScriptManager():FindItem(fullType)
    return item and item:getNormalTexture() or nil
end
-- 回 { { key, types = { 物品完整類型… } } … }；模組先一般、再進階（各自照登記順序）
function G.groupTypes()
    local watch, module, core, weight, card = {}, {}, {}, {}, {}
    for _, st in ipairs(W.STYLES) do watch[#watch + 1] = W.watchType(st) end
    for _, cls in ipairs({ "standard", "advanced" }) do
        for _, def in ipairs(W.moduleList) do
            if W.BUILTIN[def.id] and def.class == cls then module[#module + 1] = def.item end
        end
    end
    for _, def in ipairs(W.moduleList) do
        if W.BUILTIN[def.id] then
            if def.class == "core" then core[#core + 1] = def.item end
            if W.WEIGHT_CLASSES[def.class] then weight[#weight + 1] = def.item end
        end
    end
    for _, t in ipairs(W.CARD_TIERS) do card[#card + 1] = W.CARD_TYPES[t] end
    return { { key = "watch", types = watch }, { key = "module", types = module }, { key = "core", types = core },
        { key = "weight", types = weight }, { key = "card", types = card }, { key = "battery", types = { W.BATTERY_TYPE } } }
end

local function navGroups()
    local out = {}
    for i, g in ipairs(G.groupTypes()) do
        local items = {}
        for j, t in ipairs(g.types) do
            items[j] = { id = t, label = getItemNameFromFullType(t), icon = itemTexture(t) }
        end
        out[i] = { title = T("Guide_Group_" .. g.key), items = items }
    end
    return out
end

-- ===== 右欄：一樣物品的取得方式（繪製指令在 G.show 算好，render 只畫）=====
local Detail = ISUIElement:derive("MinidoracatWatchGuideDetail")
function Detail:render()
    local UI = ui()
    local colors = self.colors
    for i = 1, #self.ops do
        local o = self.ops[i]
        if o.tex then
            self:drawTextureScaled(o.tex, o.x, o.y, o.size, o.size, 1, 1, 1, 1)
        elseif o.icon then
            if UI then UI.Icons.draw(self, o.icon, o.x, o.y, o.size, colors.text) end
        else
            local c = colors[o.token] or colors.text
            self:drawText(o.text, o.x, o.y, c.r, c.g, c.b, c.a, o.font or FONT)
        end
    end
end

-- 版面工具：ops 加一段字（換行），回下一列的 y
local function para(UI, ops, s, x, y, width, token)
    for _, line in ipairs(UI.Text.wrap(s, width, FONT)) do
        ops[#ops + 1] = { text = line, x = x, y = y, token = token }
        y = y + fontH() + 2
    end
    return y
end
local function heading(ops, icon, s, y)
    y = y + 10
    ops[#ops + 1] = { icon = icon, x = 0, y = y + math.floor((fontH() - SMALL_ICON) / 2), size = SMALL_ICON }
    ops[#ops + 1] = { text = s, x = INDENT, y = y, token = "text" }
    return y + fontH() + 4
end
-- 左邊名稱（太長就換行）、右邊值（靠右，可以沒有）
local function row(UI, ops, left, right, y, width)
    local rw = right and measure(right) or 0
    if right then ops[#ops + 1] = { text = right, x = width - rw, y = y, token = "textMuted" } end
    return para(UI, ops, left, INDENT, y, width - INDENT - (right and rw + 8 or 0), "text")
end

-- 地點名在說明句裡是小寫（英文「Where to find: electronics stores.」），單獨一列時首字大寫；中日文沒有大小寫，不變
local function cap(s) return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2) end

local function zombieValue(d)
    if d.pct then
        return d.random and T("Guide_PctRandom", C.pctText(d.pct)) or T("Guide_Pct", C.pctText(d.pct))
    end
    return d.random and T("Guide_Random") or nil
end

-- 回 ops, 內容高度
function G.layout(fullType, width)
    local UI = ui()
    local ops, y = {}, 0
    local tex = itemTexture(fullType)
    if tex then ops[1] = { tex = tex, x = 0, y = 0, size = ICON } end
    local mf = UIFont.Medium
    ops[#ops + 1] = { text = getItemNameFromFullType(fullType), x = ICON + 8, y = math.floor((ICON - fontH(mf)) / 2),
        token = "text", font = mf }
    y = ICON + 4
    local info = C.acquireInfo(fullType)
    if not info then return ops, y end
    y = heading(ops, "house", T("Guide_Loot"), y)
    if info.vanilla then
        y = para(UI, ops, T("Guide_LootVanilla"), INDENT, y, width - INDENT, "textMuted")
    elseif #info.loot == 0 then
        y = para(UI, ops, T("Guide_LootNone"), INDENT, y, width - INDENT, "textMuted")
    else
        for _, l in ipairs(info.loot) do
            y = row(UI, ops, cap(l.place), l.tier and T("Tier_" .. l.tier) or nil, y, width)
        end
    end
    y = heading(ops, "skull", T("Guide_Zombie"), y)
    if #info.drops == 0 then
        y = para(UI, ops, T("Guide_ZombieNone"), INDENT, y, width - INDENT, "textMuted")
    else
        for _, d in ipairs(info.drops) do y = row(UI, ops, C.groupName(d.group), zombieValue(d), y, width) end
    end
    y = heading(ops, "screwdriver", T("Guide_Craft"), y)
    local craft = info.craft and (info.craft > 0 and T("Acquire_Craft", tostring(info.craft)) or T("Acquire_CraftAny"))
        or T("Guide_CraftNone")
    y = para(UI, ops, craft, INDENT, y, width - INDENT, info.craft and "text" or "textMuted")
    -- 說明：開放程度 3 寫稀有度怎麼看、每隻殭屍最多帶幾件；2 寫這台伺服器不公開機率
    y = y + 12
    if info.level == W.GUIDE_RATES then
        if info.dropCap then y = para(UI, ops, T("Guide_NoteCap", tostring(info.dropCap)), 0, y, width, "textMuted") end
        y = para(UI, ops, T("Guide_NoteTier"), 0, y, width, "textMuted")
    else
        y = para(UI, ops, T("Guide_NoteMethods"), 0, y, width, "textMuted")
    end
    return ops, y
end

-- ===== 視窗 =====
local GuideWindow = nil
local refreshAt = 0

function G.show(fullType)
    local d = G.detail
    if not (d and fullType) then return end
    G.current = fullType
    local ops, h = G.layout(fullType, d.width)
    d.ops = ops
    d:setHeight(math.max(h, 1))
    G.detailScroll._focusLabel = getItemNameFromFullType(fullType)
    refreshAt = getTimestampMs()
end

function G.select(fullType)
    if not (G.nav and fullType) then return end
    G.nav:setSelected(fullType, true)
    G.navScroll:scrollTo(G.nav)
    G.detailScroll:setYScroll(0)
    G.show(fullType)
end

function G.close()
    local win = G.win
    if not win then return end
    G.win, G.nav, G.navScroll, G.detail, G.detailScroll = nil, nil, nil, nil, nil
    win:setVisible(false)
    win:removeFromUIManager()
end

-- fullType＝要選的物品（nil＝上次看的那樣，第一次是第一款錶）
function G.open(pn, fullType)
    local UI = ui()
    if not (UI and G.available()) then return end
    fullType = fullType or G.current or W.watchType(W.STYLES[1])
    if G.win then
        G.select(fullType)
        G.win:setVisible(true)
        G.win:bringToTop()
        return
    end
    if not GuideWindow then
        GuideWindow = UI.Window:derive("MinidoracatWatchGuideWindow")
        GuideWindow.__index = GuideWindow
        -- 每秒重算右欄：開放程度降到 1、系統關掉就關視窗
        function GuideWindow:update()
            UI.Window.update(self)
            local now = getTimestampMs()
            if now >= refreshAt and now - refreshAt < G.REFRESH_MS then return end
            if not G.available() then return G.close() end
            G.show(G.current)
        end
    end
    local theme = C.Skins.defaultTheme(UI)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h = math.min(G.W, sw - 40), math.min(G.H, sh - 40)
    local win = UI.Window.new({ x = math.floor((sw - w) / 2), y = math.floor((sh - h) / 2), width = w, height = h,
        title = T("Guide_Title"), icon = "search", theme = theme, opaque = true, onClose = function() G.close() end })
    setmetatable(win, GuideWindow)
    local top = win:contentTop() + 8
    local bodyH = h - top - PAD
    -- 左欄寬：最長的物品名（圖示 16＋間距＋左右留白＋捲軸槽），最多視窗寬的四成五
    local groups = navGroups()
    local longest = 0
    for _, g in ipairs(groups) do
        for _, it in ipairs(g.items) do longest = math.max(longest, measure(it.label)) end
    end
    local navW = math.min(math.max(180, longest + 8 + 16 + 6 + 8 + 12), math.floor(w * 0.45))
    local navScroll = UI.ScrollPanel.new({ x = PAD, y = top, width = navW, height = bodyH, theme = theme })
    win:addChild(navScroll)
    local nav = UI.NavList.new({ x = 0, y = 0, width = navScroll:contentWidth(), theme = theme, groups = groups,
        selected = fullType, onSelect = function(_, id)
            G.detailScroll:setYScroll(0)
            G.show(id)
        end })
    navScroll:addChild(nav)
    local dx = PAD + navW + GAP
    local detailScroll = UI.ScrollPanel.new({ x = dx, y = top, width = w - dx - PAD, height = bodyH, theme = theme })
    win:addChild(detailScroll)
    local detail = ISUIElement.new(Detail, 0, 0, detailScroll:contentWidth(), 1)
    detail:initialise()
    detail.ops, detail.colors = {}, theme.colors
    detailScroll:addChild(detail)
    G.win, G.pn, G.nav, G.navScroll, G.detail, G.detailScroll = win, pn, nav, navScroll, detail, detailScroll
    G.show(fullType)
    win:addToUIManager()
    navScroll:scrollTo(nav)
end
