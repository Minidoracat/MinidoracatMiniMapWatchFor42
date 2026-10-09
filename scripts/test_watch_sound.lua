-- 地圖錶音效（client/MinidoracatWatch_Sound.lua）：sound script 與 WAV 對得上、播放（本機 emitter、不送封包、音量乘數、
-- 音量 0 不播、沒登記只 log 一次、分割畫面各自玩家）、調音量試聽（停下來才播一次、值沒變不試聽、先停掉上一個、音量 0）、
-- 裝卸模組（單機、MP 伺服器確認、依戴著的錶款、失敗不響）、開關燈（狀態真的變了才響、基準不響、單機立即）、
-- 定時掃描提示音（預設關、對應功能判斷、1 秒合併、分割畫面）、
-- 設定（ModOptions 保存與讀回、齒輪分類 settingsApiVersion 4 的滑桿、v3 與缺 API 不註冊不出錯、scanApiVersion 守衛）。
-- 用法（repo 根目錄）：lua scripts/test_watch_sound.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check = F.check

-- PZAPI.ModOptions 替身：形狀照原版 media/lua/client/PZAPI/ModOptions.lua（create／addSlider／addTickBox／getOption、
-- save 把每個選項寫成「type|modId|id|value」一行進 ModOptions.ini；load 由 MainOptions 叫，下次啟動才讀回）
local ini = {}
local function installModOptions()
    local MO = { Data = {}, Dict = {}, saves = 0 }
    local Options = {}
    Options.__index = Options
    local function add(self, o)
        o.getValue = function(x) return x.value end
        o.setValue = function(x, v) x.value = v end
        self.data[#self.data + 1], self.dict[o.id] = o, o
        return o
    end
    function Options:addSlider(id, name, min, max, step, value, tip)
        return add(self, { type = "slider", id = id, name = name, min = min, max = max, step = step, value = value, tooltip = tip })
    end
    function Options:addTickBox(id, name, value, tip)
        return add(self, { type = "tickbox", id = id, name = name, value = value, tooltip = tip })
    end
    function Options:getOption(id) return self.dict[id] end
    function Options:apply() end -- 原版預設空函式（ModOptions.lua:21-22），MainOptions 按套用時逐頁呼叫
    function MO:create(id, name)
        local o = setmetatable({ modOptionsID = id, name = name, data = {}, dict = {} }, Options)
        self.Data[#self.Data + 1], self.Dict[id] = o, o
        return o
    end
    function MO:save()
        self.saves = self.saves + 1
        ini = {}
        for _, o in ipairs(self.Data) do
            for _, x in ipairs(o.data) do ini[#ini + 1] = x.type .. "|" .. o.modOptionsID .. "|" .. x.id .. "|" .. tostring(x.value) end
        end
    end
    function MO:load()
        for _, line in ipairs(ini) do
            local t, mid, id, v = line:match("^(%w+)|([^|]+)|([^|]+)|(.*)$")
            local x = self.Dict[mid] and self.Dict[mid].dict[id]
            if x and t == "slider" then x.value = tonumber(v) elseif x and t == "tickbox" then x.value = v == "true" end
        end
    end
    PZAPI = { ModOptions = MO }
    return MO
end
local MO = installModOptions()

F.mode = "client"
require "MinidoracatWatch"
local W = MinidoracatWatchCore
local alice = F.player("alice", 0)
local bob = F.player("bob", 1)
require "MinidoracatWatch_Client"
F.load("client/MinidoracatWatch_LightClient.lua")
local C = MinidoracatWatchClient
local Snd = MinidoracatWatchSound
local MOD = function(name) return "MinidoracatWatch.Module_" .. name end
local function last() return F.sounds[#F.sounds] end
local function sp(fn, ...)
    F.mode = "sp"
    local a, b = fn(...)
    F.mode = "client"
    return a, b
end
local function wear(p, ft)
    local w = p.inv:AddItem(ft)
    w:getModData()[W.KEY] = 1
    F.wear(p, w)
    W.invalidate()
    return w
end

-- ===== sound script 與音檔 =====
local names = { Snd.REMOVE, Snd.LIGHT, Snd.LOW, Snd.DEAD, Snd.LAPSED, Snd.SCAN }
for _, s in ipairs(W.STYLES) do names[#names + 1] = Snd.INSTALL[s] end
local registered = 0
for _ in pairs(F.soundNames) do registered = registered + 1 end
check(#names == 13 and registered == 13, "13 個音效：7 款裝好＋拆下、開關燈、電量不足、沒電、到期、掃描")
local f = assert(io.open(F.MEDIA .. "/../scripts/MinidoracatWatch_sounds.txt", "r"))
local script = f:read("*a")
f:close()
for _, name in ipairs(names) do
    local line = "sound " .. name .. " { category = UI, is3D = false, master = Primary, clip { file = media/sound/MinidoracatWatch/"
        .. name .. ".wav, } }"
    check(script:find(line, 1, true) ~= nil, "sound script：" .. name .. " 是 UI、非空間音、跟主音量")
    local wav = io.open(F.MEDIA .. "/../sound/MinidoracatWatch/" .. name .. ".wav", "rb")
    local head = wav and wav:read(12)
    if wav then wav:close() end
    check(head and head:sub(1, 4) == "RIFF" and head:sub(9, 12) == "WAVE", "音檔存在且是 WAV：" .. name)
end

-- ===== 播放 =====
F.reset()
check(Snd.volume() == 70 and Snd.scanPing() == false, "預設：音量 70%、掃描提示音關")
local ref = Snd.play(alice, Snd.LIGHT)
check(ref ~= nil and #F.sounds == 1 and F.sounds[1].player == alice and F.sounds[1].volume == 0.7,
    "本機玩家的 emitter 播放，音量 70% → 0.7")
check(#F.clientCmds == 0 and #F.serverCmds == 0, "播放不送任何指令（只有自己聽得到）")
Snd.setVolume(35)
check(MO.saves == 1 and Snd.volume() == 35, "改音量：寫進 ModOptions 並保存")
Snd.play(bob, Snd.LIGHT)
check(#F.sounds == 2 and F.sounds[2].player == bob and F.sounds[2].volume == 0.35, "分割畫面：第二位玩家用自己的 emitter，音量 35% → 0.35")
Snd.setVolume(0)
check(Snd.play(alice, Snd.LIGHT) == nil and #F.sounds == 2, "音量 0：不播")
Snd.setVolume(150)
check(Snd.volume() == 100, "超過 100 夾回 100")
Snd.setVolume(0 / 0)
check(Snd.volume() == 100, "NaN 不收")
Snd.setVolume(70)
F.reset()
check(Snd.play(alice, "MinidoracatWatch_Nope") == nil and Snd.play(alice, "MinidoracatWatch_Nope") == nil
    and #F.logs == 1 and F.logs[1]:find("sound not registered", 1, true) ~= nil, "名稱沒登記：不播、log 一次")

-- ===== 調音量試聽（照公告板：拖動中不播，停下來 PREVIEW_MS 才播一次；下一次先停掉上一個）=====
local function settle(ms)
    F.now = F.now + ms
    F.fire("OnTickEvenPaused")
end
F.reset()
Snd.setVolume(50)
settle(Snd.PREVIEW_MS - 1)
Snd.setVolume(55)
settle(Snd.PREVIEW_MS - 1)
check(#F.sounds == 0, "試聽：拖動中（每次變動都往後排）不播")
settle(1)
settle(1000)
check(#F.sounds == 1 and last().player == alice and last().name == Snd.INSTALL.ValuTech and last().volume == 0.55,
    "試聽：停下來才用新音量播一次，沒戴錶播 ValuTech")
local saves = MO.saves
Snd.setVolume(55)
settle(1000)
check(MO.saves == saves and #F.sounds == 1, "值沒變（面板每幀同步滑桿）：不存檔、不試聽")
local pw = wear(alice, "MinidoracatWatch.MapWatch_Paws_Left")
Snd.setVolume(60)
settle(Snd.PREVIEW_MS)
check(#F.sounds == 2 and F.sounds[1].stopped and not last().stopped and last().name == "MinidoracatWatch_Install_Paws"
    and last().volume == 0.6, "再試聽：先停掉上一個，播戴著那款的裝好音效")
Snd.setVolume(0)
settle(Snd.PREVIEW_MS)
check(#F.sounds == 2 and last().stopped, "調到 0：停掉上一個、不播")
F.unwear(alice, pw)
alice.inv:DoRemoveItem(pw)
W.invalidate()
Snd.setVolume(70)
settle(Snd.PREVIEW_MS)
F.reset()

-- ===== 錶款對應 =====
for _, s in ipairs(W.STYLES) do
    for _, hand in ipairs({ "_Left", "_Right" }) do
        local w = wear(alice, "MinidoracatWatch.MapWatch_" .. s .. hand)
        F.reset()
        Snd.moduleDone(alice, true, nil)
        check(#F.sounds == 1 and last().name == "MinidoracatWatch_Install_" .. s, "裝好：戴著" .. s .. hand .. " 播自己的音效")
        F.unwear(alice, w)
        alice.inv:DoRemoveItem(w)
    end
end
W.invalidate()
F.reset()
Snd.moduleDone(alice, true, F.item("MinidoracatWatch.MapWatch_Luthex_Left"))
check(last().name == "MinidoracatWatch_Install_Luthex", "沒戴錶：依裝模組的那支錶")
Snd.moduleDone(alice, false, nil)
check(last().name == Snd.REMOVE, "拆下：拆下音效")

-- ===== 裝卸模組：單機 =====
local paws = wear(alice, "MinidoracatWatch.MapWatch_Paws_Left")
alice.inv:AddItem("Base.Screwdriver")
local spiffo = alice.inv:AddItem("MinidoracatWatch.MapWatch_Spiffo_Left")
spiffo:getModData()[W.KEY] = 1
F.reset()
local m = alice.inv:AddItem(MOD("GPS"))
sp(C.requestModule, alice, paws, "std1", m)
sp(F.runActions, alice)
check(#F.sounds == 1 and last().name == "MinidoracatWatch_Install_Paws" and last().player == alice, "單機裝好：戴著貓爪")
local m2 = alice.inv:AddItem(MOD("Ledger"))
sp(C.requestModule, alice, paws, "std1", m2)
sp(F.runActions, alice)
check(#F.sounds == 1, "裝到已經有模組的槽位（失敗）：不響")
local m3 = alice.inv:AddItem(MOD("Scan"))
sp(C.requestModule, alice, spiffo, "std1", m3)
sp(F.runActions, alice)
check(#F.sounds == 2 and last().name == "MinidoracatWatch_Install_Paws", "替背包裡的 Spiffo 裝：仍依戴著的貓爪")
sp(C.requestModule, alice, paws, "std1", nil)
sp(F.runActions, alice)
check(#F.sounds == 3 and last().name == Snd.REMOVE, "單機拆下")
F.mode = "client"
F.reset()
local m4 = alice.inv:AddItem(MOD("GPS"))
C.requestModule(alice, paws, "std1", m4)
F.runActions(alice)
check(#F.sounds == 0 and #F.clientCmds == 1, "MP：送出指令時不響（等伺服器確認）")

-- ===== 裝卸模組：MP 伺服器確認 =====
F.mode = "server"
F.load("server/MinidoracatWatch_Server.lua")
local carol = F.player("carol", 2)
local cw = wear(carol, "MinidoracatWatch.MapWatch_Nexus_Left")
carol.inv:AddItem("Base.Screwdriver")
local cm = carol.inv:AddItem(MOD("GPS"))
F.reset()
F.now = F.now + 1000
F.fire("OnClientCommand", W.MODULE, W.CMD_MODULE, carol, { watchId = cw:getID(), slotId = "std1", install = true, itemId = cm:getID() })
local ack = F.serverCmds[1]
check(#F.serverCmds == 1 and ack.player == carol and ack.command == W.CMD_MODULE and ack.args.to == "carol"
    and ack.args.install == true and ack.args.watchId == cw:getID(), "伺服器：裝好後回本人（帶帳號、裝或拆、錶 id）")
F.reset()
F.now = F.now + 1000
F.fire("OnClientCommand", W.MODULE, W.CMD_MODULE, carol, { watchId = cw:getID(), slotId = "std2", install = true, itemId = 999999 })
check(#F.serverCmds == 1 and F.serverCmds[1].command == W.CMD_FAILED, "伺服器：失敗只回失敗、不回確認")
F.reset()
F.now = F.now + 1000
F.fire("OnClientCommand", W.MODULE, W.CMD_MODULE, carol, { watchId = cw:getID(), slotId = "std1", install = false })
check(#F.serverCmds == 1 and F.serverCmds[1].command == W.CMD_MODULE and F.serverCmds[1].args.install == false, "伺服器：拆下也回確認")
F.mode = "client"
local bw = wear(bob, "MinidoracatWatch.MapWatch_Ranger_Left")
F.reset()
F.fire("OnServerCommand", W.MODULE, W.CMD_MODULE, { to = "bob", install = true, watchId = bw:getID() })
check(#F.sounds == 1 and last().player == bob and last().name == "MinidoracatWatch_Install_Ranger", "客戶端：分割畫面第二位收到確認，播他戴的遊騎兵")
F.fire("OnServerCommand", W.MODULE, W.CMD_MODULE, { to = "bob", install = false, watchId = bw:getID() })
check(#F.sounds == 2 and last().name == Snd.REMOVE, "客戶端：拆下確認")
F.fire("OnServerCommand", W.MODULE, W.CMD_MODULE, { to = "zed", install = true, watchId = 1 })
F.fire("OnServerCommand", W.MODULE, W.CMD_MODULE, { install = true })
check(#F.sounds == 2, "不是本機玩家、沒有帳號：不響")

-- ===== 開關燈 =====
F.reset()
C.syncLight(alice)
check(#F.sounds == 0, "燈：第一次看到只記基準")
local li = alice.inv:AddItem(W.LIGHT_TYPE)
li:setActivated(true)
C.syncLight(alice)
C.syncLight(alice)
check(#F.sounds == 1 and last().name == Snd.LIGHT, "開燈：響一次")
li:setActivated(false)
C.syncLight(alice)
check(#F.sounds == 2 and last().name == Snd.LIGHT, "關燈（原版切燈鍵）：響")
alice.inv:DoRemoveItem(li)
C.syncLight(alice)
check(#F.sounds == 2, "關著的光源被刪：狀態沒變、不響")
local alice2 = F.player("alice", 0)
table.remove(F.players) -- F.player 把新角色接在尾端：改成替換 0 號
F.players[1] = alice2 -- 重生：同一個 playerNum 的新角色
local li2 = alice2.inv:AddItem(W.LIGHT_TYPE)
li2:setActivated(true)
C.syncLight(alice2)
check(#F.sounds == 2, "重生的新角色：只記基準")
F.players[1] = alice
C.syncLight(alice) -- 換回原角色：重新記基準（燈關著）
-- 單機：開燈指令套用後立刻響（不等每秒校正）
F.reset()
local lm = alice.inv:AddItem(MOD("Light"))
sp(W.applyModuleChange, alice, paws:getID(), "std2", true, lm:getID())
sp(C.requestLight, alice, true)
check(W.lightOn(alice) and #F.sounds == 1 and last().name == Snd.LIGHT, "單機開燈：當下就響")
sp(C.requestLight, alice, false)
check(not W.lightOn(alice) and #F.sounds == 2, "單機關燈：當下就響")

-- ===== 定時掃描提示音 =====
-- 貓爪：std1 空、std2 照明；替它裝偵測（殭屍點位）。掃描模組在背包裡的 Spiffo 上，不算
sp(W.applyModuleChange, alice, paws:getID(), "std1", true, alice.inv:AddItem(MOD("Detect")):getID())
F.mode = "client"
F.reset()
F.now = F.now + 10000
Snd.onScan(0, "zombie")
check(#F.sounds == 0, "預設關：不響")
Snd.setScanPing(true)
check(Snd.scanPing() == true, "開啟")
Snd.onScan(0, "vehicleAnimal")
check(#F.sounds == 0, "載具與動物功能不能用（戴著的錶沒有掃描模組）：不響")
Snd.onScan(0, "zombie")
check(#F.sounds == 1 and last().name == Snd.SCAN and last().player == alice and last().volume == 0.7, "殭屍點位功能能用：響")
sp(W.applyModuleChange, alice, paws:getID(), "std3", true, alice.inv:AddItem(MOD("Scan")):getID())
W.invalidate()
F.mode = "client"
Snd.onScan(0, "vehicleAnimal")
F.now = F.now + 999
Snd.onScan(0, "vehicleAnimal")
Snd.onScan(0, "zombie")
check(#F.sounds == 1, "1 秒內另一種、同一種再更新：合併成一次")
F.now = F.now + 1
Snd.onScan(0, "vehicleAnimal")
check(#F.sounds == 2 and last().name == Snd.SCAN, "滿 1 秒：再響（裝了掃描模組，載具與動物也算）")
sp(W.applyModuleChange, bob, bw:getID(), "std1", true, (function()
    bob.inv:AddItem("Base.Screwdriver")
    return bob.inv:AddItem(MOD("Detect")):getID()
end)())
W.invalidate()
F.mode = "client"
Snd.onScan(1, "zombie")
check(#F.sounds == 3 and last().player == bob, "分割畫面：第二位玩家自己算 1 秒，用自己的 emitter")
F.now = F.now + 5000
Snd.onScan(0, "teammates")
Snd.onScan(3, "zombie")
bob.dead = true
Snd.onScan(1, "zombie")
bob.dead = false
check(#F.sounds == 3, "不認得的種類、沒有這位玩家、死了：不響")
Snd.setVolume(0)
Snd.onScan(0, "zombie")
check(#F.sounds == 3, "音量 0：不響")
Snd.setVolume(70)
F.now = F.now + 5000
Snd.setScanPing(false)
Snd.onScan(0, "zombie")
check(#F.sounds == 3, "關掉：不響")

-- ===== 註冊：齒輪設定的分類、掃描事件 =====
local function logged(s)
    for _, l in ipairs(F.logs) do if l:find(s, 1, true) then return true end end
    return false
end
F.reset()
MinidoracatMiniMapAPI = nil
Snd.register()
check(not Snd.scanActive and not Snd.sectionActive and logged("scanApiVersion >= 1") and logged("settingsApiVersion >= 4"),
    "主 MOD 沒有 API：不出錯、各 log 一次")
local v3calls = 0
MinidoracatMiniMapAPI = { settingsApiVersion = 3, registerSettingsSection = function() v3calls = v3calls + 1; return true end }
Snd.register()
check(v3calls == 0 and not Snd.sectionActive, "settingsApiVersion 3（會丟掉滑桿）：不註冊")
local regs, scans = {}, {}
MinidoracatMiniMapAPI = { settingsApiVersion = 4,
    registerSettingsSection = function(owner, spec) regs[#regs + 1] = { owner = owner, spec = spec }; return true end }
Snd.register()
local sec = regs[1] and regs[1].spec
local sl = sec and sec.sliders[1]
local tk = sec and sec.ticks[1]
check(Snd.sectionActive and regs[1].owner == Snd.OWNER and Snd.OWNER ~= W.MOD_ID and sec.visible == nil
    and sec.label == "IGUI_MinidoracatWatch_Sound_Section", "v4：註冊所有玩家看得到的「地圖錶」分類，和「地圖錶管理」不同 owner")
check(sec.icon == "watch" and sec.group == "addon" and sec.order == 12, "分類帶 v5 的圖標／群組／排序（擴充功能群組、order 12）")
check(MO.Dict.MinidoracatWatch.name == "IGUI_MinidoracatWatch_Options" and sec.label ~= MO.Dict.MinidoracatWatch.name,
    "ESC 選項頁名用自己的鍵（Minidoracat 地圖錶），齒輪分類名仍是「地圖錶」")
check(sl and sl.min == 0 and sl.max == 100 and sl.step == 5 and sl.default == 70 and sl.fmt == "%d%%"
    and sl.label == "IGUI_MinidoracatWatch_Sound_Volume", "音量滑桿 0–100%、step 5、預設 70")
check(tk and tk.default == false and tk.label == "IGUI_MinidoracatWatch_Sound_ScanPing"
    and tk.tooltip == "IGUI_MinidoracatWatch_Sound_ScanPing_old", "掃描提示音勾選預設關；主 MOD 沒有掃描事件：說明改成要更新")
sl.set(45)
tk.set(true)
check(sl.get() == 45 and Snd.volume() == 45 and tk.get() == true and Snd.scanPing() == true, "分類的 get／set 讀寫同一份設定")
MinidoracatMiniMapAPI.scanApiVersion = 0
MinidoracatMiniMapAPI.registerScanListener = function(owner, fn) scans[#scans + 1] = { owner = owner, fn = fn }; return true end
Snd.register()
check(#scans == 0 and not Snd.scanActive, "scanApiVersion 0：不註冊")
MinidoracatMiniMapAPI.scanApiVersion = 1
Snd.register()
check(Snd.scanActive and scans[1].owner == W.MOD_ID and scans[1].fn == Snd.onScan
    and regs[#regs].spec.ticks[1].tooltip == "IGUI_MinidoracatWatch_Sound_ScanPing_tooltip", "scanApiVersion 1：註冊掃描事件，說明照常")
MinidoracatMiniMapAPI.registerScanListener = function() error("boom") end
F.reset()
Snd.register()
check(not Snd.scanActive and logged("scanApiVersion >= 1"), "registerScanListener 拋錯：不出錯、當沒有")

-- ===== 設定保存與讀回（本機 ModOptions.ini，不跟存檔）=====
local saved = table.concat(ini, "\n")
check(saved:find("slider|MinidoracatWatch|Volume|45", 1, true) and saved:find("tickbox|MinidoracatWatch|ScanPing|true", 1, true),
    "保存：ModOptions.ini 寫進音量 45 與掃描提示音開")
local MO2 = installModOptions() -- 下次啟動：ModOptions 先以預設建立，MainOptions 再讀檔
F.load("client/MinidoracatWatch_Sound.lua")
local Snd2 = MinidoracatWatchSound
check(Snd2.volume() == 70 and Snd2.scanPing() == false, "讀檔前是預設")
MO2:load()
check(Snd2.volume() == 45 and Snd2.scanPing() == true, "讀回：音量 45、掃描提示音開")

-- ===== 工具列按鈕顯示（ShowButton，同一頁，預設顯示）=====
F.installUI(15)
F.load("client/MinidoracatWatch_Client.lua")
local spec = F.dockSpec
local page = MO2.Dict.MinidoracatWatch
local showOpt = page:getOption("ShowButton")
check(showOpt and showOpt.type == "tickbox" and showOpt.value == true and spec.isAvailable() == true,
    "預設：勾選顯示，工具列有地圖錶入口")
F.dockRefreshes = 0
showOpt:setValue(false)
check(spec.isAvailable() == true, "勾掉但還沒按套用：照舊顯示")
page:apply()
check(spec.isAvailable() == false and F.dockRefreshes == 1, "按套用：入口立刻消失、通知工具列重算")
showOpt:setValue(true)
page:apply()
check(spec.isAvailable() == true and F.dockRefreshes == 2, "勾回來按套用：立刻恢復")
SandboxVars.MinidoracatWatch.Enabled = false
check(spec.isAvailable() == false, "地圖錶停用：勾著也不顯示（原本的條件照舊）")
SandboxVars.MinidoracatWatch.Enabled = true
showOpt:setValue("garbage")
page:apply()
check(spec.isAvailable() == true, "設定值不是布林（讀壞）：當顯示")
showOpt:setValue(false)
PZAPI.ModOptions:save()
check(table.concat(ini, "\n"):find("tickbox|MinidoracatWatch|ShowButton|false", 1, true) ~= nil, "隱藏寫進 ModOptions.ini")
local MO4 = installModOptions() -- 下次啟動
F.load("client/MinidoracatWatch_Sound.lua")
F.load("client/MinidoracatWatch_Client.lua")
local spec4 = F.dockSpec
check(spec4.isAvailable() == true, "讀檔前：預設顯示")
MO4:load()
F.fire("OnGameStart")
check(spec4.isAvailable() == false, "進遊戲（OnGameStart 在原版讀檔之後）：讀回隱藏")
MO4.Dict.MinidoracatWatch:getOption("ShowButton"):setValue(true)
MO4.Dict.MinidoracatWatch:apply()
check(spec4.isAvailable() == true, "再勾回來：恢復")
-- 齒輪分類的同一個勾選：存檔後走同一個 apply（快取、ini、Dock 入口和 MODS 頁套用一致）
local gearTick = MinidoracatWatchSound.SECTION.ticks[2]
local function iniHas(s) return table.concat(ini, "\n"):find(s, 1, true) ~= nil end
check(gearTick and gearTick.label == "IGUI_MinidoracatWatch_ShowButton" and gearTick.tooltip == "IGUI_MinidoracatWatch_ShowButton_tooltip"
    and gearTick.default == true and gearTick.get() == true, "齒輪分類也有「顯示地圖錶按鈕」，預設勾、讀同一份設定")
F.dockRefreshes = 0
gearTick.set(false)
check(spec4.isAvailable() == false and gearTick.get() == false and F.dockRefreshes == 1
    and iniHas("tickbox|MinidoracatWatch|ShowButton|false"), "齒輪取消勾選：入口立刻消失、工具列重算、寫回 ModOptions.ini")
gearTick.set(true)
check(spec4.isAvailable() == true and gearTick.get() == true and F.dockRefreshes == 2
    and iniHas("tickbox|MinidoracatWatch|ShowButton|true"), "齒輪勾回來：立刻恢復、寫回 ModOptions.ini")

-- ===== 面板的音效音量列（框架 rev 17 SliderRow；和齒輪分類、ESC 頁同一份 ModOptions）=====
function getCore() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
function getTextManager() return { MeasureStringX = function(_, _, s) return #s * 7 end, getFontHeight = function() return 16 end } end
function getScriptManager() return { FindItem = function() return nil end } end
ISMouseDrag, ISInventoryPane = {}, { getActualItems = function(items) return items end }
F.installUI(17)
F.load("client/MinidoracatWatch_Panel.lua")
local PC = MinidoracatWatchClient -- 上面為了工具列按鈕重新載入過 _Client：面板掛在新的那張表上
PC.openPanel(0, nil)
local pv = PC.panel()
pv:update()
local row = pv.volRow
local gearVol = MinidoracatWatchSound.SECTION.sliders[1]
check(row and row.label == "IGUI_MinidoracatWatch_Sound_Volume" and row:getValue() == MinidoracatWatchSound.volume()
    and row.format(35) == "35%" and row.y + row.height <= pv.footY, "框架 rev 17：電量列上方有音效音量列，顯示目前設定")
row:setValue(35)
check(MinidoracatWatchSound.volume() == 35 and gearVol.get() == 35 and iniHas("slider|MinidoracatWatch|Volume|35"),
    "拖面板的滑桿：齒輪分類讀到同一個值、寫回 ModOptions.ini")
gearVol.set(60)
pv:update()
check(row:getValue() == 60, "齒輪改了音量：面板的滑桿跟著變")
-- 換戴另一款錶：滑桿的填色與圓鈕在建構時取色，換皮膚要用新皮膚重建（只留一列）
F.unwear(alice, paws)
F.wear(alice, spiffo)
F.fire("OnClothingUpdated", alice)
F.now = F.now + 1500
pv:update()
local rows = 0
for _, ch in ipairs(pv.children) do if ch.label == "IGUI_MinidoracatWatch_Sound_Volume" then rows = rows + 1 end end
check(pv.skinKey == "spiffo" and pv.volRow ~= row and pv.volRow.theme == pv.theme and rows == 1 and pv.volRow:getValue() == 60,
    "換成 Spiffo 的皮膚：音量列用新皮膚重建、只有一列、值不變")
F.unwear(alice, spiffo)
F.wear(alice, paws)
F.fire("OnClothingUpdated", alice)
PC.closePanel()
F.installUI(16)
PC.openPanel(0, nil)
local p16 = PC.panel()
p16:update()
check(p16.volRow == nil and p16.footY ~= nil, "框架 rev 16（沒有 SliderRow）：沒有音量列，面板照常")
PC.closePanel()
PZAPI = nil
F.load("client/MinidoracatWatch_Sound.lua")
local Snd3 = MinidoracatWatchSound
Snd3.setVolume(10)
F.reset()
check(Snd3.volume() == 70 and Snd3.play(alice, Snd3.LIGHT) and last().volume == 0.7, "沒有 ModOptions：用預設、不出錯")
F.fire("OnGameStart")
check(spec4.isAvailable() == true, "沒有 ModOptions：工具列按鈕照常顯示")

F.finish("test_watch_sound")
