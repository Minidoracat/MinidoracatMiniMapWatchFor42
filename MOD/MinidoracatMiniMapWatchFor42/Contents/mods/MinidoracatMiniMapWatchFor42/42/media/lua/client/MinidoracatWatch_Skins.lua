-- MinidoracatWatch_Skins.lua：手錶面板的七款皮膚（設計稿 styles.mjs／panel.mjs）＝每款一個 UI 框架 theme
-- （UI.Theme.create：框架 16 個 token＋地圖錶自有 token）、錶面版面與槽位外形。
-- 框架 API rev 15 起才有圓角與 theme 字型（Skin.shapeOf）；更舊的框架一律退回預設 theme（只帶自有 token），
-- 版面與槽位外形是地圖錶自己的貼圖，不受影響。配色的對比由 scripts/test_watch_skins.lua 逐對檢查。
require "MinidoracatWatch_Client"
local W, C = MinidoracatWatchCore, MinidoracatWatchClient

local S = {}
C.Skins = S

-- 各款共用：警告／危險色（styles.mjs:292）、槽位等級色與等級標籤上的字（styles.mjs:6、:92）
S.COMMON = {
    warnSurface = "#3D3112", warnText = "#FFD88A", warnLine = "#7E6322", warnStrong = "#FFC24D",
    errorSurface = "#46191A", errorText = "#FFBDB7", errorLine = "#8A3330",
    tierStd = "#A7B0BA", tierExt = "#3FB27F", tierAdv = "#4C8DF6", tierCore = "#A970F0", tierAddon = "#E39A3B",
    tierOrphan = "#8A8F96", tagText = "#111111",
}

-- 每款：variant、圓角（設計稿 --r／--r-sm 換算到框架支援值）、版面（ring／hex／plates／row）、槽位外形（貼圖）、colors。
-- 框架 token：surface＝--wp-surface、surfaceTitle＝--wp-head、well＝--wp-raised、border、text、textMuted＝--wp-muted、
-- accent＝--wp-primary（主要按鈕）、onAccent＝--wp-on-primary、titleText／titleMuted＝--wp-head-text／-muted。
-- 自有 token：ring＝選取外框（--wp-accent）、socket／socketLocked、glyph＝槽位裡的圖示色、headLine＝標題列下緣線，
-- 以及各款裝飾色（sticker、deco、rivet、gold）。
S.SKINS = {
    nexus = { layout = "hex", shape = "hex", radius = 3, controlRadius = 3, colors = {
        surface = "#0D1116", surfaceTitle = "#131920", well = "#19212A", border = "#2A3540", text = "#E6F1F5",
        textMuted = "#97ABB6", accent = "#3EE6E0", onAccent = "#04181A", titleText = "#E6F1F5", titleMuted = "#97ABB6",
        ring = "#3EE6E0", socket = "#111820", socketLocked = "#0B0F13", glyph = "#E6F1F5", headLine = "#1F6E6B" } },
    paws = { variant = "light", layout = "ring", shape = "cat", radius = 20, controlRadius = 10, buttonShape = "pill",
        colors = {
        surface = "#FFF7F0", surfaceTitle = "#FFE4EE", well = "#FFEDF3", border = "#E6A9BE", text = "#3A2630",
        textMuted = "#74505D", accent = "#B03A6A", onAccent = "#FFFFFF", titleText = "#3A2630", titleMuted = "#74505D",
        ring = "#B03A6A", socket = "#FFFFFF", socketLocked = "#F2E2E8", glyph = "#3A2630", headLine = "#E6A9BE",
        deco = "#F59BBE", warnSurface = "#FFF0C7", warnText = "#5E3B00", warnLine = "#D9B04D", warnStrong = "#8F5500",
        errorSurface = "#FFE1E1", errorText = "#82191C", errorLine = "#E3A0A0" } },
    spiffo = { layout = "ring", shape = "circle", radius = 10, controlRadius = 6, colors = {
        surface = "#2A2C31", surfaceTitle = "#B8342C", well = "#363940", border = "#4B4F58", text = "#F2F2F2",
        textMuted = "#B9BEC7", accent = "#4FD1C5", onAccent = "#062B27", titleText = "#FFFFFF", titleMuted = "#FFE3E0",
        ring = "#4FD1C5", socket = "#3A3D44", socketLocked = "#2F3136", glyph = "#F2F2F2", headLine = "#4B4F58",
        sticker = "#F3F0E8", stripeA = "#8C8F96", stripeB = "#3A3C41" },
        -- 電量列是招牌紅：上面的 chip 用標題列的淺色字、啟用時白框白字；主要按鈕白底紅字
        foot = { textMuted = "#FFE3E0", accent = "#FFFFFF", onAccent = "#8C2620" } },
    ranger = { layout = "plates", shape = "oct", radius = 3, controlRadius = 3, colors = {
        surface = "#2B3020", surfaceTitle = "#3A4030", well = "#3D4432", border = "#5E6648", text = "#ECE6D2",
        textMuted = "#C0B89E", accent = "#A6D96A", onAccent = "#16200A", titleText = "#ECE6D2", titleMuted = "#C0B89E",
        ring = "#A6D96A", socket = "#333A27", socketLocked = "#272B1E", glyph = "#ECE6D2", headLine = "#1A1E12",
        rivet = "#1A1E12" } },
    valutech = { layout = "row", shape = "lcd", radius = 6, controlRadius = 3, colors = {
        surface = "#1C1D20", surfaceTitle = "#C9CDD3", well = "#2E3035", border = "#4A4D52", text = "#EDEDED",
        textMuted = "#AEB2B8", accent = "#E8E8E8", onAccent = "#1E1F22", titleText = "#1E1F22", titleMuted = "#3D4046",
        ring = "#F2F2F2", socket = "#B9C6A3", socketLocked = "#45493F", glyph = "#1E2A1A", headLine = "#4A4D52",
        battSurface = "#1E1F22", battText = "#C8D4B2" },
        -- 檢視區是綠灰液晶（styles.mjs:325）：裡面的字、按鈕換一套色
        insp = { surface = "#B9C6A3", text = "#1E2A1A", textMuted = "#3A4632", well = "#A9B794", border = "#6F7A63",
            accent = "#1E2A1A", onAccent = "#D4DEC0", warnSurface = "#E4D08A", warnText = "#3A2A00", errorText = "#7A1712" },
        -- 電量列是銀色面板：chip 用深色字與框，主要按鈕深底淺字
        foot = { textMuted = "#3D4046", accent = "#1E1F22", onAccent = "#E8E8E8" } },
    luthex = { layout = "ring", shape = "circle", radius = 10, controlRadius = 6, colors = {
        surface = "#121010", surfaceTitle = "#1A1716", well = "#231E1B", border = "#4A3E2C", text = "#F3EBDD",
        textMuted = "#C2B398", accent = "#D9B45A", onAccent = "#1A1408", titleText = "#F3EBDD", titleMuted = "#C2B398",
        ring = "#D9B45A", socket = "#1B1715", socketLocked = "#141110", glyph = "#F3EBDD", headLine = "#6B5A3A",
        gold = "#6B5A3A", warnSurface = "#3E2016", warnText = "#FFC0A3", warnLine = "#8A4A30", warnStrong = "#FF9E7A",
        errorSurface = "#43162A", errorText = "#FFB3CC", errorLine = "#8A2E55" } },
    -- 嗶嗶腕機：單色終端機；等寬字（UIFont.Code）只用在 ASCII 讀數（框架 ARCHITECTURE §3.2：Code 字型沒有中日韓字形）
    crt = { layout = "plates", shape = "crt", radius = 3, controlRadius = 3, mono = true, colors = {
        surface = "#061108", surfaceTitle = "#061108", well = "#0D2611", border = "#2C7A33", text = "#8DFF7A",
        textMuted = "#6BD85C", accent = "#7CFF6B", onAccent = "#04160A", titleText = "#7CFF6B", titleMuted = "#5FD150",
        ring = "#B6FF9E", socket = "#0B2210", socketLocked = "#061408", glyph = "#8DFF7A", headLine = "#5FD150",
        footSurface = "#0D2611", warnSurface = "#2C2A0A", warnText = "#FFE27A", warnLine = "#6B6420", warnStrong = "#FFD23F",
        errorSurface = "#2E0F0C", errorText = "#FF9F8F", errorLine = "#7A2A22" } },
}
-- 嗶嗶腕機琥珀螢幕（styles.mjs:524）：同一款，換一套色
S.SKINS["crt-amber"] = { base = "crt", colors = {
    surface = "#130B02", surfaceTitle = "#130B02", well = "#2A1A06", border = "#7A4A10", text = "#FFC266",
    textMuted = "#E0A040", accent = "#FFB642", onAccent = "#1A0F00", titleText = "#FFB642", titleMuted = "#E09A2E",
    ring = "#FFDCA0", socket = "#241505", socketLocked = "#140B02", glyph = "#FFC266", headLine = "#E09A2E",
    footSurface = "#2A1A06" } }

-- 框架太舊時的預設 theme 仍要有自有 token（未知 token 的繪製是靜默不畫）：深色家族外觀
S.FALLBACK = { ring = "#FFD966", socket = "#1A1C21", socketLocked = "#111214", glyph = "#E6E6E6", headLine = "#666666" }

local STYLE_SKIN = { ValuTech = "valutech", Paws = "paws", Nexus = "nexus", Spiffo = "spiffo", Ranger = "ranger",
    Luthex = "luthex", BB3000 = "crt" }

-- 這支錶的皮膚鍵（嗶嗶腕機琥珀螢幕＝crt-amber）；不是地圖錶或沒有錶＝valutech（入門款）
function S.keyOf(watch)
    local style = watch and watch:getFullType():match("^MinidoracatWatch%.MapWatch_(%w+)_")
    local id = STYLE_SKIN[style] or "valutech"
    if id == "crt" and W.screenOf(watch) == 1 then return "crt-amber" end
    return id
end

-- 一款皮膚的完整規格：base 鏈＋共用色合併成 { 欄位..., colors = {token=hex} }（測試與 theme 共用）
function S.spec(key)
    local own = S.SKINS[key]
    local base = own.base and S.spec(own.base) or { colors = {} }
    local out = { colors = {} }
    for k, v in pairs(base) do if k ~= "colors" then out[k] = v end end
    for k, v in pairs(own) do if k ~= "colors" and k ~= "base" then out[k] = v end end
    for k, v in pairs(S.COMMON) do out.colors[k] = v end
    for k, v in pairs(base.colors) do out.colors[k] = v end
    for k, v in pairs(own.colors) do out.colors[k] = v end
    return out
end

function S.rgb(hex)
    return { r = tonumber(hex:sub(2, 3), 16) / 255, g = tonumber(hex:sub(4, 5), 16) / 255,
        b = tonumber(hex:sub(6, 7), 16) / 255, a = 1 }
end

local function colorsOf(map, over)
    local out = {}
    for k, v in pairs(map) do out[k] = S.rgb(v) end
    for k, v in pairs(over or {}) do out[k] = S.rgb(v) end
    return out
end

-- 框架有圓角 API（rev 15）才套皮膚；否則預設 theme＋自有 token
function S.canSkin(UI)
    return UI.API_REVISION >= 15 and UI.Skin ~= nil and type(UI.Skin.shapeOf) == "function"
end

local cache = {}
-- 預設 theme：框架預設配色＋自有 token（面板外的 Dock、框架太舊時的面板）
function S.defaultTheme(UI)
    local hit = cache["@default"]
    if hit and hit.ui == UI then return hit.theme end
    local theme = UI.Theme.create({ colors = colorsOf(S.COMMON, S.FALLBACK) })
    cache["@default"] = { ui = UI, theme = theme }
    return theme
end

-- 回 theme, inspTheme（檢視區）, footTheme（電量列）：只有 ValuTech／Spiffo 不同。同一個框架、同一款只建一次
function S.themes(UI, key)
    if not S.canSkin(UI) then
        local theme = S.defaultTheme(UI)
        return theme, theme, theme
    end
    local hit = cache[key]
    if hit and hit.ui == UI then return hit.theme, hit.insp, hit.foot end
    local spec = S.spec(key)
    local function make(over)
        return UI.Theme.create({ variant = spec.variant, colors = colorsOf(spec.colors, over), radius = spec.radius,
            controlRadius = spec.controlRadius, buttonShape = spec.buttonShape })
    end
    local theme = make(nil)
    local insp = spec.insp and make(spec.insp) or theme
    local foot = spec.foot and make(spec.foot) or theme
    cache[key] = { ui = UI, theme = theme, insp = insp, foot = foot }
    return theme, insp, foot
end
