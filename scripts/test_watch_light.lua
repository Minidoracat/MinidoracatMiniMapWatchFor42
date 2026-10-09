-- 照明模組（Phase 8）：登記與規則、開關的伺服器驗證（指令、單機）、耗電（+LightDrain%、節能核心、沒戴的錶不加）、
-- 自動熄燈各路徑（沒電、沒電池、拿下錶、拆模組、槽位失效、規則關閉、系統關閉、原版切燈鍵）、存檔後狀態（讀檔後還開著／
-- 讀檔時已不合規／伺服器掛載遺失）、客戶端（本機判斷、擁有者自己掛上／拿下、所有玩家的半徑、伺服器提醒、右鍵、快捷鍵、面板）。
-- 用法（repo 根目錄）：lua scripts/test_watch_light.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check, near = F.check, F.near
local baseReset = F.reset
function F.reset() baseReset(); F.attachSent, F.attachPackets = {}, {} end
F.mode = "server"
require "MinidoracatWatch"
F.load("server/MinidoracatWatch_Server.lua")
local W = MinidoracatWatchCore
local SB = SandboxVars.MinidoracatWatch
local H = 3600000
local LIGHT, LOC = W.LIGHT_TYPE, W.LIGHT_LOC

local function tick(ms, step)
    local t = 0
    while t < ms do F.now = F.now + step; t = t + step; F.fire("OnTickEvenPaused") end
end
local function give(p, t) return p.inv:AddItem(t) end
local function setup(name)
    local p = F.player(name)
    local w = give(p, F.LEFT)
    F.wear(p, w)
    give(p, "Base.Screwdriver")
    return p, w
end
local function installLight(p, w, slot)
    local m = give(p, "MinidoracatWatch.Module_Light")
    return W.applyModuleChange(p, w:getID(), slot or "std1", true, m:getID())
end
local function emitters(p)
    local n = 0
    for _, it in ipairs(p.inv.items) do if it.fullType == LIGHT then n = n + 1 end end
    return n
end
local function lit(p)
    local it = W.lightItem(p)
    return it ~= nil and it:isActivated() and p:getAttachedItem(LOC) == it
end
local function cmd(p, on)
    F.now = F.now + 300 -- 伺服器指令節流 250ms
    F.fire("OnClientCommand", W.MODULE, W.CMD_LIGHT, p, { on = on })
end
local function nudged(p)
    for _, c in ipairs(F.serverCmds) do
        if c.player == p and c.command == W.CMD_LIGHT and c.args.to == p:getUsername() then return true end
    end
    return false
end
local function lastAttach(p)
    local last = nil
    for _, a in ipairs(F.attachSent) do if a.player == p and a.loc == LOC then last = a end end
    return last
end

-- ===== 登記與規則 =====
local def = W.modules.light
check(def and def.class == "standard" and def.drain == 0 and def.item == "MinidoracatWatch.Module_Light",
    "照明模組登記成內建一般模組、裝著不耗電")
check(W.BUILTIN.light.feature == "light" and W.PROVIDERS.light[1] == "light" and W.moduleDrain(def) == 0,
    "功能 light 由照明模組提供；moduleDrain 是 0（開燈的耗電另算）")
check(F.attachedLocs[LOC] == true, "shared 載入時定義了自訂 AttachedLocation")
check(W.featureRule("light") == W.RULE_MODULE, "規則預設：需要模組")
SB.RuleLight = 2
check(W.featureRule("light") == W.RULE_OFF, "RuleLight=2：關閉")
SB.RuleLight = nil
check(W.lightRadius() == 4 and W.lightDrain() == 100, "預設半徑 4 格、開燈 +100%")
SB.LightRadius, SB.LightDrain = 7.9, -5
check(W.lightRadius() == 7 and W.lightDrain() == 100, "半徑取整數（setLightDistance 收 int）；負的耗電退回預設")
SB.LightRadius, SB.LightDrain = nil, nil

-- ===== 開燈的驗證 =====
local a, aw = setup("alice")
tick(2000, 500) -- 扣電迴圈第一次看到玩家
F.reset()
check(W.applyLight(a, true) == false and emitters(a) == 0, "沒裝照明模組：拒絕、不建光源")
local ok, why = W.lightAllowed(a)
check(ok == false and why == "IGUI_MinidoracatWatch_Reason_Need_light", "原因：需要照明模組")
for _, bad in ipairs({ "true", 1, 0 / 0 }) do
    check(W.applyLight(a, bad) == false and emitters(a) == 0, "on 不是布林：拒絕（" .. tostring(bad) .. "）")
end
check(W.applyLight(a, nil) == false, "on 是 nil：拒絕")
check(installLight(a, aw) == true and W.slotRecord(aw, "std1").id == "light", "照明模組裝進標準槽")
check(W.lightOn(a) == false and near(W.drainFactor(a, aw), 1), "裝著、燈關著：不耗電")
F.mode = "client"
check(W.applyLight(a, true) == false and emitters(a) == 0, "MP 客戶端不能直接開燈")
F.mode = "server"

-- ===== 經伺服器指令開燈 =====
F.reset()
cmd(a, true)
local item = W.lightItem(a)
check(lit(a) and emitters(a) == 1 and item:isActivated(), "指令開燈：主背包一個啟動的光源、掛在自訂位置")
check(F.added[1] == item and #F.added == 1, "伺服器 sendAddItemToContainer 送出光源")
check(lastAttach(a) and lastAttach(a).item == item, "伺服器 sendAttachedItem 送給範圍內客戶端")
check(nudged(a), "提醒擁有者客戶端自己掛上")
check(near(W.drainFactor(a, aw), 2), "開燈：耗電倍率 2（+100%）")
cmd(a, true)
check(emitters(a) == 1 and W.lightItem(a) == item, "再開一次：還是同一個，不重複")

-- 耗電：開燈 10 分鐘扣 2 倍、關燈 10 分鐘扣 1 倍；切換時先入帳
W.setCharge(aw, 1)
tick(600000, 500)
local onDrop = 1 - W.charge(aw)
cmd(a, false)
local mid = W.charge(aw)
tick(600000, 500)
local offDrop = mid - W.charge(aw)
local base = 600000 / (72 * H)
check(near(onDrop, 2 * base, base * 0.01), "開燈 10 分鐘：扣 2 倍（" .. onDrop .. "）")
check(near(offDrop, base, base * 0.01), "關燈 10 分鐘：扣 1 倍（" .. offDrop .. "）")
-- 切換前先入帳：入帳每秒一次，切換點之前還沒入帳的時間照舊倍率算（FullHours=1 讓 800ms 看得出來）
SB.FullHours = 1
W.setCharge(aw, 1)
tick(1000, 1000) -- 剛入帳
local c0 = W.charge(aw)
F.now = F.now + 800
F.fire("OnTickEvenPaused") -- 有效時間 +800ms，還沒到入帳
cmd(a, true)
check(near(c0 - W.charge(aw), 800 / H, 1e-9), "開燈前先入帳：之前的 800ms 照關燈的倍率（1 倍）")
tick(1000, 1000)
local c1 = W.charge(aw)
F.now = F.now + 800
F.fire("OnTickEvenPaused")
cmd(a, false)
check(near(c1 - W.charge(aw), 2 * 800 / H, 1e-9), "關燈前先入帳：開燈期間的 800ms 照 2 倍")
SB.FullHours = nil
W.setCharge(aw, 1)
SB.LightDrain = 50
cmd(a, true)
check(near(W.drainFactor(a, aw), 1.5), "LightDrain=50：倍率 1.5")
SB.LightDrain = nil

-- ===== 經伺服器指令關燈 =====
F.reset()
item = W.lightItem(a)
cmd(a, false)
check(emitters(a) == 0 and a:getAttachedItem(LOC) == nil, "指令關燈：光源刪除、拿下")
check(F.removed[1] == item, "伺服器 sendRemoveItemFromContainer")
check(lastAttach(a) and lastAttach(a).item == nil and nudged(a), "伺服器送出拿下、提醒擁有者")
cmd(a, false)
check(emitters(a) == 0, "已經關著再關：沒事")

-- ===== 自動熄燈 =====
local function autoOff(label, cause, restore)
    cmd(a, true)
    check(lit(a), label .. "：先開燈")
    F.reset()
    cause()
    tick(1500, 500)
    check(emitters(a) == 0 and a:getAttachedItem(LOC) == nil and lastAttach(a) and lastAttach(a).item == nil
        and nudged(a), label .. "：一秒內自動熄燈、通知其他人")
    local again = W.applyLight(a, true)
    check(again == false and emitters(a) == 0, label .. "：開不回來")
    restore()
    W.invalidate()
end
autoOff("沒電", function() W.setCharge(aw, 0) end, function() W.setCharge(aw, 1) end)
autoOff("沒電池", function() W.setCharge(aw, W.NO_BATTERY) end, function() W.setCharge(aw, 1) end)
autoOff("拿下錶", function() F.unwear(a, aw); W.invalidate() end, function() F.wear(a, aw) end)
autoOff("規則改成關閉", function() SB.RuleLight = 2 end, function() SB.RuleLight = nil end)
autoOff("地圖錶系統關閉", function() SB.Enabled = false end, function() SB.Enabled = true end)
-- 拆模組：拆下會 invalidate，下一秒的校正就熄燈
cmd(a, true)
F.reset()
check(W.applyModuleChange(a, aw:getID(), "std1", false) == true, "拆下照明模組")
tick(1500, 500)
check(emitters(a) == 0 and a:getAttachedItem(LOC) == nil, "拆模組：自動熄燈")
-- 槽位失效：裝在擴充槽（免費開放），之後擴充槽改成不開放
SB.SlotExt = 1
W.invalidate()
check(installLight(a, aw, "ext") == true, "照明模組裝進擴充槽（免費開放）")
cmd(a, true)
check(lit(a), "擴充槽的照明模組能開燈")
SB.SlotExt = 4
W.invalidate()
tick(1500, 500)
check(emitters(a) == 0 and W.moduleState(a, "light") == "paused", "槽位失效（不開放）：模組 paused、自動熄燈")
SB.SlotExt = 1
W.invalidate()
-- 原版切燈鍵（ItemBindingHandler.lua:50-61）：把 attached 的發光物 setActivated(false)
cmd(a, true)
W.lightItem(a):setActivated(false)
check(near(W.drainFactor(a, aw), 1), "被原版切燈鍵關掉：馬上不算開燈耗電")
tick(1500, 500)
check(emitters(a) == 0 and a:getAttachedItem(LOC) == nil, "被原版切燈鍵關掉的光源：校正時刪掉")
cmd(a, true)
check(lit(a) and emitters(a) == 1, "之後照常能再開")

-- 死亡：OnCharacterDeath（IsoGameCharacter.java:4873-4875，在 becomeCorpse 把背包交給屍體之前）由伺服器刪光源，
-- 屍體與掉落的背包裡不留隱形光源；之後的校正跳過死亡玩家
check(lit(a), "（死亡前燈開著）")
a.dead = true
F.reset()
F.fire("OnCharacterDeath", a)
check(emitters(a) == 0 and a:getAttachedItem(LOC) == nil, "死亡後背包沒有光源物品、也沒掛著")
check(lastAttach(a) and lastAttach(a).item == nil and F.removed[1] ~= nil, "死亡：伺服器送出移除與拿下")
F.fire("OnCharacterDeath", { _class = "IsoZombie" })
check(true, "殭屍死亡：不出錯")
check(W.applyLight(a, false) == false, "死亡：指令拒絕")
a.dead = false
cmd(a, true)
check(lit(a), "（重生後再開燈）")

-- 沒戴著的錶算續航時不加開燈的耗電
local w2 = give(a, F.RIGHT)
check(installLight(a, w2, "std2") == true, "背包裡另一支錶也裝照明模組")
check(near(W.drainFactor(a, w2), 1) and near(W.drainFactor(a, aw), 2), "開燈的耗電只算在戴著的那支")
-- 節能核心：整支錶（含開燈）減半
SB.SlotCore = 1
W.invalidate()
local eco = give(a, "MinidoracatWatch.Module_Eco")
check(W.applyModuleChange(a, aw:getID(), "core", true, eco:getID()) == true, "核心槽裝節能核心")
check(near(W.drainFactor(a, aw), 1), "節能核心＋開燈：(1+1)/2＝1")
cmd(a, false)
check(near(W.drainFactor(a, aw), 0.5), "節能核心＋關燈：0.5")

-- ===== 存檔後狀態（讀檔：activated 與 attached 都隨背包存，InventoryItem.java:2032、IsoGameCharacter.java:14579-14586）=====
local function reloaded(name, charge, attached, activated)
    local p, w = setup(name)
    installLight(p, w)
    W.setCharge(w, charge)
    local it = give(p, LIGHT)
    it:setActivated(activated)
    if attached then p:setAttachedItem(LOC, it) end
    W.invalidate()
    F.reset()
    tick(1500, 500)
    return p, it
end
local p1, it1 = reloaded("bob", 0.5, true, true)
check(lit(p1) and W.lightItem(p1) == it1 and emitters(p1) == 1 and lastAttach(p1) == nil,
    "讀檔後燈還開著且合規：保留，不重送")
local p2 = reloaded("carol", 0, true, true)
check(emitters(p2) == 0 and p2:getAttachedItem(LOC) == nil, "讀檔時錶已沒電（離線耗電）：第一次校正就熄燈")
local p3, it3 = reloaded("dave", 0.5, false, true)
check(lit(p3) and lastAttach(p3) and lastAttach(p3).item == it3 and nudged(p3), "伺服器掛載遺失：補掛並通知")
local p4 = reloaded("erin", 0.5, true, false)
check(emitters(p4) == 0 and p4:getAttachedItem(LOC) == nil, "存的是關著的光源：刪掉")

-- ===== 單機：直接套用、不送封包 =====
F.mode = "sp"
local s, sw = setup("sam")
installLight(s, sw)
F.reset()
check(W.applyLight(s, true) == true and lit(s), "單機開燈：本機直接掛上")
check(#F.added == 0 and #F.attachSent == 0 and #F.serverCmds == 0, "單機不送任何封包")
check(W.applyLight(s, false) == true and emitters(s) == 0 and s:getAttachedItem(LOC) == nil, "單機關燈")

-- ===== 客戶端 =====
F.mode = "client"
F.players = {}
F.keys = {}
F.keyIs = {} -- KeybindId → 綁的鍵（getCore():isKey）
function getCore()
    return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end,
        getKey = function(_, name) return F.keys[name] end, isKey = function(_, id, k) return F.keyIs[id] == k end }
end
KeybindId = { LIGHT_SOURCE = "LIGHT_SOURCE", TOGGLE_VEHICLE_HEADLIGHTS = "TOGGLE_VEHICLE_HEADLIGHTS" }
keyBinding = {}
Keyboard.KEY_SCROLL, Keyboard.KEY_COMMA = 70, 51 -- LWJGL 鍵碼（org/lwjglx/input/KeyCodes.java）
function getTextManager()
    return { MeasureStringX = function(_, _, s2) return #s2 * 7 end, getFontHeight = function() return 16 end }
end
local Menu = {}
Menu.__index = Menu
local function newMenu() return setmetatable({ options = {} }, Menu) end
function Menu:addOption(name, target, fn, x1, x2, x3, x4)
    local o = { name = name, target = target, fn = fn, a = x1, b = x2, c = x3, d = x4 }
    self.options[#self.options + 1] = o
    return o
end
function Menu:addSubMenu(opt, sub) opt.sub = sub end
ISContextMenu = { getNew = function() return newMenu() end, get = function() return newMenu() end }
function getScriptManager()
    return { FindItem = function() return { getNormalTexture = function() return "tex" end, getR = function() return 1 end,
        getG = function() return 1 end, getB = function() return 1 end } end }
end
ISMouseDrag = {}
ISInventoryPane = { getActualItems = function(items) return items end }
-- 家族 UI 框架的替身（lib_watch_fakes 的 F.installUI）：面板與照明按鈕只用框架元件
F.installUI(14)
local function lightButtons()
    local n = 0
    for _, b in ipairs(F.uiButtons) do if b.icon == "lightbulb" then n = n + 1 end end
    return n
end

local c, cw = setup("cid")
F.load("client/MinidoracatWatch_LightClient.lua")
F.load("client/MinidoracatWatch_Panel.lua")
local C = MinidoracatWatchClient
F.reset()
F.now = F.now + 2000
C.requestLight(c, true)
check(#F.clientCmds == 0 and #F.halos == 1 and F.halos[1].text == "IGUI_MinidoracatWatch_Reason_Need_light",
    "客戶端：沒裝模組先在本機擋下並提示，不送指令")
local function spInstall() F.mode = "sp"; local r = installLight(c, cw); F.mode = "client"; return r end
check(spInstall() == true, "（客戶端玩家的錶裝上照明模組）")
F.reset()
C.requestLight(c, true)
check(#F.clientCmds == 1 and F.clientCmds[1].command == W.CMD_LIGHT and F.clientCmds[1].args.on == true,
    "客戶端開燈：只送純量 on=true")
C.toggleLight(c)
check(#F.clientCmds == 2 and F.clientCmds[2].args.on == true, "燈還沒開（伺服器還沒回）：切換＝開")

-- 擁有者自己掛：伺服器加進背包的光源（SyncItem 帶 activated）
local em = give(c, LIGHT)
em:setActivated(true)
F.reset()
F.fire("OnServerCommand", W.MODULE, W.CMD_LIGHT, { to = "cid" })
check(c:getAttachedItem(LOC) == em and #F.attachPackets == 1 and F.attachPackets[1].item == em,
    "伺服器提醒：擁有者掛上光源（本機掛載會送封包給其他人）")
C.syncLight(c)
check(#F.attachPackets == 1, "已經掛著：不重送")
check(C.toggleLight(c) == nil and F.clientCmds[#F.clientCmds].args.on == false, "燈開著：切換＝關")
em:setActivated(false)
C.syncLight(c)
check(c:getAttachedItem(LOC) == nil and F.attachPackets[2].item == nil, "光源被關掉：擁有者拿下（送出拿下）")
em:setActivated(true)
C.syncLight(c)
c.inv:DoRemoveItem(em)
C.syncLight(c)
check(c:getAttachedItem(LOC) == nil, "伺服器刪掉光源：擁有者拿下")
F.fire("OnServerCommand", W.MODULE, W.CMD_LIGHT, { to = "someone-else" })
F.fire("OnServerCommand", "OtherMod", W.CMD_LIGHT, { to = "cid" })
check(true, "別人的提醒、別的 MOD：不出錯")

-- 外觀 MOD（Mirage Wardrobe）從 OnTick 到畫完，把身上衣物與掛著的物品都換成重建的複製品：這時不動掛載（改到的是
-- 複製品、換回來就被蓋掉，還白送封包）；開著的燈照樣算在戴著的那支
do
    local lamp = give(c, LIGHT)
    lamp:setActivated(true)
    C.syncLight(c)
    check(c:getAttachedItem(LOC) == lamp, "（燈開著、掛著）")
    local realWorn, realAttached = c.worn, c.attached
    c.worn = { { loc = "leftwrist", item = F.item(F.LEFT) } }
    c.attached = { [LOC] = F.item(LIGHT) }
    F.reset()
    F.now = F.now + 2000
    C.syncLight(c)
    check(#F.attachPackets == 0, "外觀複製品換上時：不改掛載、不送封包")
    check(W.lightLit(c, cw), "外觀複製品換上時：開著的燈照樣算在戴著的那支")
    c.worn, c.attached = realWorn, realAttached
    C.syncLight(c)
    check(c:getAttachedItem(LOC) == lamp and #F.attachPackets == 0, "換回來：還是那個光源，不必重掛")
    c.inv:DoRemoveItem(lamp)
    C.syncLight(c)
end

-- 半徑：每台客戶端改每位玩家那份（本機與遠端）
local remote = F.player("rem", 1)
table.remove(F.players) -- 遠端玩家：不是本機座位（getSpecificPlayer／getNumActivePlayers 看不到）
local rem = F.item(LIGHT)
remote.attached = { [LOC] = rem }
local mine = give(c, LIGHT)
mine:setActivated(true)
SB.LightRadius = 7
local realOnline = getOnlinePlayers
function getOnlinePlayers() return F.javaList({ c, remote }) end
F.now = F.now + 2000
C.lightPoll()
check(rem:getLightDistance() == 7 and mine:getLightDistance() == 7, "沙盒半徑 7：遠端玩家與自己的光源都改成 7")
SB.LightRadius = nil
F.now = F.now + 2000
C.lightPoll()
check(rem:getLightDistance() == 4, "改回預設：跟著變回 4")
getOnlinePlayers = realOnline

-- 右鍵：戴著、裝了照明模組的錶才有
W.invalidate()
local ctx = newMenu()
F.fire("OnFillInventoryObjectContextMenu", 0, ctx, { cw })
local opt = nil
for _, o in ipairs(ctx.options) do
    if o.name == "IGUI_MinidoracatWatch_LightOff" or o.name == "IGUI_MinidoracatWatch_LightOn" then opt = o end
end
check(opt and opt.name == "IGUI_MinidoracatWatch_LightOff" and not opt.notAvailable, "燈開著：錶的右鍵有「關燈」")
F.reset()
opt.fn(opt.target, opt.a)
check(F.clientCmds[1] and F.clientCmds[1].args.on == false, "右鍵關燈：送 on=false")
c.inv:DoRemoveItem(mine)
C.syncLight(c)
W.setCharge(cw, 0)
ctx = newMenu()
F.fire("OnFillInventoryObjectContextMenu", 0, ctx, { cw })
opt = nil
for _, o in ipairs(ctx.options) do if o.name == "IGUI_MinidoracatWatch_LightOn" then opt = o end end
check(opt and opt.notAvailable == true, "沒電：右鍵「開燈」停用")
W.setCharge(cw, 1)
local ctx2 = newMenu()
local plain = give(c, "Base.Battery")
F.fire("OnFillInventoryObjectContextMenu", 0, ctx2, { plain })
local any = false
for _, o in ipairs(ctx2.options) do if o.name == "IGUI_MinidoracatWatch_LightOn" then any = true end end
check(not any, "其他物品的右鍵沒有開燈")

-- 快捷鍵：開機時登記可綁定的鍵，按下＝切換玩家 0 的燈
F.fire("OnGameBoot")
local bound = nil
for _, b in ipairs(keyBinding) do
    if b.value == "MinidoracatWatch_Light" then bound = b.key end
end
check(keyBinding[1] and keyBinding[1].value == "[MinidoracatWatch]" and bound == 70, "按鍵綁定：分類標題＋預設 Scroll Lock")
F.keys.MinidoracatWatch_Light = bound -- 玩家沒改鍵：Core 回登記的預設
F.reset()
F.now = F.now + 2000
F.fire("OnKeyPressed", 70)
check(F.clientCmds[1] and F.clientCmds[1].args.on == true, "按下 Scroll Lock：開燈")
F.reset()
F.fire("OnKeyPressed", 51)
F.fire("OnKeyPressed", 0)
check(#F.clientCmds == 0, "逗號（裝備視窗 MOD 的預設鍵）、未綁定（0）：不動作")

-- 原版「裝備或開／關光源」鍵（F）：手上沒拿燈時開關錶燈；駕駛時的車頭燈、手上的燈、錶燈開不了、我們的判斷拋錯時照原版
local vanilla = {}
ItemBindingHandler = { toggleLight = function(key) vanilla[#vanilla + 1] = key end }
C.hookLightKey()
local function pressF()
    F.reset()
    vanilla = {}
    F.now = F.now + 2000
    ItemBindingHandler.toggleLight(33)
end
pressF()
check(F.clientCmds[1] and F.clientCmds[1].args.on == true and #vanilla == 0, "F：手上沒拿燈、錶燈關著＝開錶燈，不交給原版")
local lamp = give(c, LIGHT)
lamp:setActivated(true)
pressF()
check(F.clientCmds[1] and F.clientCmds[1].args.on == false and #vanilla == 0, "F：錶燈開著＝關錶燈")
c.inv:DoRemoveItem(lamp)
c.secondary = { canEmitLight = function() return true end, getType = function() return "HandTorch" end }
pressF()
check(#F.clientCmds == 0 and #vanilla == 1, "F：手上拿著手電筒＝照原版切手電筒")
c.secondary = { canEmitLight = function() return true end, getType = function() return "CandleLit" end }
pressF()
check(F.clientCmds[1] and F.clientCmds[1].args.on == true and #vanilla == 0, "F：手上的點燃蠟燭原版不切（照抄原版）＝開錶燈")
c.secondary = nil
c.vehicle = { isDriver = function(_, pl) return pl == c end }
F.keyIs.TOGGLE_VEHICLE_HEADLIGHTS = 33
pressF()
check(#F.clientCmds == 0 and #vanilla == 1, "F：駕駛中且 F 也是車頭燈鍵＝照原版切車頭燈")
c.vehicle = { isDriver = function() return false end }
pressF()
check(F.clientCmds[1] and F.clientCmds[1].args.on == true and #vanilla == 0, "F：坐在乘客座＝開錶燈")
c.vehicle, F.keyIs.TOGGLE_VEHICLE_HEADLIGHTS = nil, nil
W.setCharge(cw, 0)
pressF()
check(#F.clientCmds == 0 and #vanilla == 1 and #F.halos == 0, "F：錶燈開不了（沒電）＝照原版（裝備背包裡的燈），不提示")
W.setCharge(cw, 1)
local realAllowed = W.lightAllowed
W.lightAllowed = function() error("boom") end
pressF()
W.lightAllowed = realAllowed
local keyLog = false
for _, l in ipairs(F.logs) do keyLog = keyLog or l:find("light key failed", 1, true) ~= nil end
check(#vanilla == 1 and keyLog, "F：我們的判斷拋錯＝照原版並記一次 log")

-- 面板：按鈕只在戴著的錶裝了照明模組時出現；開著時寫「關燈」、底部註明燈開著
C.openPanel(0, nil)
local panel = C.panel()
check(lightButtons() == 1 and panel.btnLight.icon == "lightbulb" and panel.btnLight.style == "chip",
    "照明按鈕是 UI 框架的 chip Button（燈泡圖示）")
panel:update()
check(panel.btnLight.visible and panel.btnLight.title == "IGUI_MinidoracatWatch_LightOn" and panel.btnLight.enable
    and panel.btnLight.active == false, "面板：照明按鈕「開燈」、未啟用")
local on2 = give(c, LIGHT)
on2:setActivated(true)
panel:update()
check(panel.btnLight.title == "IGUI_MinidoracatWatch_LightOff" and panel.btnLight.enable and panel.btnLight.active == true,
    "燈開著：按鈕「關燈」、chip 啟用")
F.draws = 0
panel:prerender()
check(F.draws > 20 and panel.footText:find("Foot_LightOn", 1, true) ~= nil, "燈開著：電量列註明「燈開著」")
F.reset()
panel.btnLight:forceClick()
check(F.clientCmds[1] and F.clientCmds[1].args.on == false, "面板按鈕：關燈")
c.inv:DoRemoveItem(on2)
W.setCharge(cw, 0)
W.invalidate()
panel:update()
check(panel.btnLight.visible and not panel.btnLight.enable, "沒電：按鈕停用")
F.mode = "sp"
W.applyModuleChange(c, cw:getID(), "std1", false)
F.mode = "client"
panel:update()
check(not panel.btnLight.visible, "拆掉照明模組：按鈕消失")
C.closePanel()
F.installUI(13)
C.openPanel(0, nil)
check(C.panel() == nil and lightButtons() == 0, "框架 rev 13：面板不開（照明照樣能用右鍵與快捷鍵開關）")
F.installUI(14)
MinidoracatUI.v1.CAPABILITIES.controls = false
C.openPanel(0, nil)
check(C.panel() == nil, "框架沒有 controls：面板不開、不出錯")

F.finish("test_watch_light")
