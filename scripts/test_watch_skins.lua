-- 手錶面板七款皮膚：WCAG 對比（文字 4.5:1、圖示與大字 3:1，逐款逐對算）、皮膚選擇（含嗶嗶腕機琥珀）、
-- 框架 rev 15 套皮膚與圓角、rev 14 退回預設 theme（仍帶自有 token）。
-- 用法（repo 根目錄）：lua scripts/test_watch_skins.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check = F.check
F.mode = "client"
require "MinidoracatWatch"
require "MinidoracatWatch_Client"
F.load("client/MinidoracatWatch_Skins.lua")
local W, C = MinidoracatWatchCore, MinidoracatWatchClient
local S = C.Skins

-- ===== 對比（WCAG 2.x 相對亮度）=====
local function lin(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
local function lum(hex)
    local c = S.rgb(hex)
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
end
local function ratio(a, b)
    local la, lb = lum(a), lum(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

-- { 前景, 背景, 門檻, 用途 }：面板實際畫出的配對
local PAIRS = {
    { "text", "surface", 4.5, "內文" }, { "textMuted", "surface", 4.5, "次要文字" },
    { "warnText", "surface", 4.5, "付費說明的警示字" }, { "errorText", "surface", 4.5, "錯誤字" },
    { "text", "well", 4.5, "按鈕、狀態膠囊、資訊框" }, { "textMuted", "well", 4.5, "資訊框標籤" },
    { "titleText", "surfaceTitle", 4.5, "標題列與底部電量列" }, { "titleMuted", "surfaceTitle", 3, "關閉鈕" },
    { "onAccent", "accent", 4.5, "主要按鈕" }, { "accent", "surface", 3, "主要按鈕外形、功能勾" },
    { "ring", "surface", 3, "選取外框" }, { "warnText", "warnSurface", 4.5, "橫幅、警示框" },
    { "errorText", "errorSurface", 4.5, "沒電橫幅" }, { "warnStrong", "surface", 3, "槽位徽章（寬限）" },
    { "glyph", "socket", 3, "槽位裡的加號" }, { "textMuted", "socketLocked", 3, "鎖住槽位的鎖" },
    { "tagText", "tierStd", 4.5, "等級標籤" }, { "tagText", "tierExt", 4.5, "等級標籤" },
    { "tagText", "tierAdv", 4.5, "等級標籤" }, { "tagText", "tierCore", 4.5, "等級標籤" },
    { "tagText", "tierAddon", 4.5, "等級標籤" }, { "tagText", "tierOrphan", 4.5, "等級標籤" },
}
-- 電量列（底色＝footSurface 或標題列色）上的按鈕：用 foot theme
local FOOT_PAIRS = {
    { "textMuted", "footBg", 4.5, "照明 chip（未啟用）的字" }, { "accent", "footBg", 4.5, "照明 chip（啟用）的字與框" },
    { "text", "well", 4.5, "電量列按鈕" }, { "onAccent", "accent", 4.5, "電量列主要按鈕" },
}
-- 檢視區（ValuTech 的液晶）另算一次：字、按鈕、警示框都在液晶上
local INSP_PAIRS = {
    { "text", "surface", 4.5, "檢視區內文" }, { "textMuted", "surface", 4.5, "檢視區次要文字" },
    { "warnText", "surface", 4.5, "檢視區警示字" }, { "errorText", "surface", 4.5, "檢視區錯誤字" },
    { "text", "well", 4.5, "檢視區按鈕" }, { "onAccent", "accent", 4.5, "檢視區主要按鈕" },
    { "warnText", "warnSurface", 4.5, "檢視區警示框" },
}

local keys = {}
for k in pairs(S.SKINS) do keys[#keys + 1] = k end
table.sort(keys)
local worst, report = math.huge, {}
local function run(key, colors, pairs, tag)
    for _, p in ipairs(pairs) do
        local fg, bg = colors[p[1]], colors[p[2]]
        if p[1] == "titleText" and p[2] == "surfaceTitle" and colors.footSurface then
            check(ratio(fg, colors.footSurface) >= 4.5, key .. "：底部電量列的字（footSurface）")
        end
        if not (fg and bg) then
            check(false, key .. tag .. "：缺 token " .. p[1] .. "／" .. p[2])
        else
            local r = ratio(fg, bg)
            if r / p[3] < worst then worst = r / p[3] end
            report[#report + 1] = string.format("%s%s %s/%s %.2f", key, tag, p[1], p[2], r)
            check(r >= p[3], string.format("%s%s：%s（%s 對 %s）%.2f ≥ %.1f", key, tag, p[4], p[1], p[2], r, p[3]))
        end
    end
end
for _, key in ipairs(keys) do
    local spec = S.spec(key)
    run(key, spec.colors, PAIRS, "")
    if spec.colors.battSurface then
        check(ratio(spec.colors.battText, spec.colors.battSurface) >= 4.5, key .. "：標題列電量膠囊")
    end
    local function merged(over)
        local m = {}
        for k, v in pairs(spec.colors) do m[k] = v end
        for k, v in pairs(over or {}) do m[k] = v end
        return m
    end
    if spec.insp then run(key, merged(spec.insp), INSP_PAIRS, "（檢視區）") end
    -- 電量列：底色是 footSurface（沒有就是標題列色），上面的按鈕用 foot theme（chip 未啟用＝textMuted、啟用＝accent）
    local foot = merged(spec.foot)
    foot.footBg = spec.colors.footSurface or spec.colors.surfaceTitle
    run(key, foot, FOOT_PAIRS, "（電量列）")
end
check(#keys == 8, "七款皮膚＋嗶嗶腕機琥珀＝8 套（" .. #keys .. "）")
-- 預設 theme（管理員視窗與確認框、Dock、框架太舊時的面板）：框架 DARK 的色＋共用色，底色不透明
local DEFAULT_PAIRS = {
    { "text", "surface", 4.5, "內文" }, { "textMuted", "surface", 4.5, "說明文字、欄位單位" },
    { "accent", "surface", 4.5, "頁尾訊息、經濟系統狀態" }, { "errorText", "surface", 4.5, "錯誤說明" },
    { "text", "well", 4.5, "輸入框、下拉選單" }, { "textMuted", "well", 4.5, "輸入框提示字" },
    { "titleText", "surfaceTitle", 4.5, "標題列" }, { "titleMuted", "surfaceTitle", 3, "關閉鈕" },
    { "onAccent", "accent", 4.5, "主要按鈕" }, { "border", "surface", 3, "控制項外框" },
    { "textDisabled", "surface", 3, "停用控制項" }, { "errorText", "errorSurface", 4.5, "欄位錯誤框" },
    { "warnText", "warnSurface", 4.5, "警示框" },
}
local defaultColors = {}
for _, map in ipairs({ S.DEFAULT, S.COMMON, S.FALLBACK }) do for k, v in pairs(map) do defaultColors[k] = v end end
run("預設", defaultColors, DEFAULT_PAIRS, "")
local made0 = {}
local dt = S.defaultTheme({ Theme = { create = function(o) made0[#made0 + 1] = o; return { colors = o.colors } end } })
local opaque = true
for _, tok in ipairs({ "surface", "surfaceTitle", "well", "errorSurface", "warnSurface" }) do
    local c = dt.colors[tok]
    if not (c and c.a == 1) then opaque = false end
end
check(opaque and dt.colors.hover == nil and dt.colors.selected == nil,
    "預設 theme：底色（surface／surfaceTitle／well／錯誤與警示框）不透明，hover／selected 留給框架的半透明疊色")
if os.getenv("SKIN_REPORT") then for _, l in ipairs(report) do F.print(l) end end

-- ===== 皮膚選擇 =====
local function watch(style) return F.item("MinidoracatWatch.MapWatch_" .. style .. "_Left") end
local want = { ValuTech = "valutech", Paws = "paws", Nexus = "nexus", Spiffo = "spiffo", Ranger = "ranger",
    Luthex = "luthex", BB3000 = "crt" }
local all = true
for style, key in pairs(want) do if S.keyOf(watch(style)) ~= key then all = false end end
check(all, "七款錶各對到自己的皮膚")
local bb = watch("BB3000")
bb:getModData()[W.SCREEN_KEY] = 1
check(S.keyOf(bb) == "crt-amber", "嗶嗶腕機琥珀螢幕：crt-amber")
check(S.keyOf(nil) == "valutech", "沒有錶：預設 ValuTech")
check(S.spec("crt-amber").layout == "plates" and S.spec("crt-amber").mono == true
    and S.spec("crt-amber").colors.text == "#FFC266", "琥珀沿用嗶嗶腕機的版面與等寬讀數、換成琥珀色")

-- ===== 套用：rev 15 帶圓角；rev 14 退回預設 theme（仍有自有 token）=====
local made = {}
local UI = { API_REVISION = 15, Skin = { shapeOf = function() end },
    Theme = { create = function(o) made[#made + 1] = o; return { colors = o.colors, radius = o.radius, opts = o } end } }
local t, insp = S.themes(UI, "paws")
check(t.opts.variant == "light" and t.radius == 20 and t.opts.controlRadius == 10 and t.opts.buttonShape == "pill"
    and insp == t, "rev 15 貓爪：淺色、圓角 20／10、膠囊按鈕；檢視區沿用同一個 theme")
check(math.abs(t.colors.accent.r - 0xB0 / 255) < 1e-9 and t.colors.socket and t.colors.tierAdv, "theme 帶框架 token 與自有 token")
local n = #made
check(S.themes(UI, "paws") == t and #made == n, "同一款只建一次")
local vt, vinsp = S.themes(UI, "valutech")
check(vinsp ~= vt and math.abs(vinsp.colors.surface.r - 0xB9 / 255) < 1e-9 and math.abs(vt.colors.surface.r - 0x1C / 255) < 1e-9,
    "ValuTech：檢視區另一個 theme（液晶色）")
local old = { API_REVISION = 14, Skin = {}, Theme = UI.Theme }
local ft, finsp = S.themes(old, "paws")
check(ft.opts.variant == nil and ft.radius == nil and ft.colors.socket and ft.colors.ring and ft.colors.warnText
    and finsp == ft, "rev 14：退回預設 theme（深色、沒有圓角），自有 token 照樣在")
check(S.themes(UI, "paws") ~= ft, "換回 rev 15 的框架：重建皮膚 theme")

F.print(string.format("  最低餘裕：實際對比／門檻＝%.2f", worst))
F.finish("test_watch_skins")
