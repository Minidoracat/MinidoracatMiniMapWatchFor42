-- 地圖錶客戶端：主 MOD 版本守衛、功能閘門矩陣（模組 × 狀態 × 規則 × surface、nav 的 AutoDrive OR）、快取零配置、
-- Dock、計時動作請求（換電池／裝卸模組）、解鎖卡請求、伺服器回報、面板（UI 框架元件、槽位 Focus 導覽、拖曳、按鈕、
-- Toast、皮膚套用）、右鍵選單、沒有原版按鈕殘留。
-- 用法（repo 根目錄）：lua scripts/test_watch_client.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check = F.check
F.mode = "client"

-- ===== 客戶端 UI 假物件（家族 UI 框架的替身在 lib_watch_fakes 的 F.installUI）=====
function getCore() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
function getTextManager()
    return { MeasureStringX = function(_, _, s) return #s * 7 end, getFontHeight = function() return 16 end }
end
function getMouseX() return 100 end
function getMouseY() return 100 end
local Element = F.Element
-- ISContextMenu：addOption 回選項；getNew＋addSubMenu 建子選單；ISContextMenu.get 建面板用的浮動選單
local Menu = {}
Menu.__index = Menu
local function newMenu() return setmetatable({ options = {} }, Menu) end
function Menu:addOption(name, target, fn, a, b, c, d)
    local o = { name = name, target = target, fn = fn, a = a, b = b, c = c, d = d }
    self.options[#self.options + 1] = o
    return o
end
function Menu:addSubMenu(opt, sub) opt.sub = sub; opt.subOption = 1 end
ISContextMenu = { getNew = function(_, parent) return newMenu() end,
    get = function() F.lastMenu = newMenu(); return F.lastMenu end }
local function pick(o) o.fn(o.target, o.a, o.b, o.c, o.d) end
local scripts = {}
function getScriptManager()
    return { FindItem = function(_, t)
        scripts[t] = scripts[t] or { getNormalTexture = function() return "tex" end, getR = function() return 1 end,
            getG = function() return 1 end, getB = function() return 1 end }
        return scripts[t]
    end }
end
ISMouseDrag = {}
ISInventoryPane = { getActualItems = function(items) return items end }

F.installUI(15)

require "MinidoracatWatch"
local W = MinidoracatWatchCore
local SB = SandboxVars.MinidoracatWatch
local p = F.player("alice", 0)
require "MinidoracatWatch_Client"
F.load("client/MinidoracatWatch_Panel.lua")
local C = MinidoracatWatchClient
local MOD = function(name) return "MinidoracatWatch.Module_" .. name end
local function give(t) local it = F.item(t); p.inv:AddItem(it); return it end
-- 單機視角下裝模組（直接呼叫 shared 突變點；閘門測試只讀結果）
local function sp(fn, ...)
    F.mode = "sp"
    local r = fn(...)
    F.mode = "client"
    return r
end

-- ===== 版本守衛 =====
F.reset()
MinidoracatMiniMapAPI = nil
MinidoracatMiniMapServerAPI = { shareApiVersion = 1, registerShareFilter = function() return true end }
F.fire("OnGameStart")
check(C.gateActive == false, "主 MOD 沒有 API：不設閘")
local gateLogs = 0 -- 同一個 OnGameStart 還有音效的守衛 log（test_watch_sound.lua）
for _, l in ipairs(F.logs) do if l:find("featureApiVersion", 1, true) then gateLogs = gateLogs + 1 end end
check(gateLogs == 1, "log 一次")
F.admin = false
F.fire("OnTick")
check(#F.halos == 0, "一般玩家不提示")
local req = 0
for _, c in ipairs(F.clientCmds) do if c.command == W.CMD_UNLOCKS_REQ and c.player == p then req = req + 1 end end
check(req == 1, "MP：每位本機玩家在第一個客戶端 tick 補要一次解鎖狀態")

F.reset()
F.admin = true
MinidoracatMiniMapAPI = { featureApiVersion = 0, registerFeatureGate = function() error("should not be called") end }
C.registerGate()
F.fire("OnTick")
local apiHalo = false
for _, h in ipairs(F.halos) do if h.text == "IGUI_MinidoracatWatch_ApiMissing" then apiHalo = true end end
check(C.gateActive == false and apiHalo, "版本太舊：不呼叫、管理員收到提示")

F.reset()
MinidoracatMiniMapAPI = { featureApiVersion = 1, registerFeatureGate = function() error("boom") end }
C.registerGate()
check(C.gateActive == false, "主 MOD 註冊拋錯也不 crash")

local registered = {}
MinidoracatMiniMapAPI = { featureApiVersion = 2, registerFeatureGate = function(owner, fn)
    registered.owner, registered.fn = owner, fn; return true end }
F.reset()
C.registerGate()
check(C.gateActive == true and registered.owner == W.MOD_ID and registered.fn == C.gate, "featureApiVersion >= 1 才註冊")
check(#F.logs == 0, "註冊成功不 log")

-- 主 MOD 的伺服器分享過濾 API 太舊：通訊距離沒生效，MP 管理員收到提示（伺服器自己 log）。
-- 先清掉上面「註冊拋錯」那次排進來的提示。
F.fire("OnTick")
local function shareHalo()
    for _, h in ipairs(F.halos) do if h.text == "IGUI_MinidoracatWatch_ShareApiMissing" then return true end end
    return false
end
MinidoracatMiniMapServerAPI = { shareApiVersion = 0, registerShareFilter = function() return true end }
F.reset()
C.registerGate()
F.fire("OnTick")
check(shareHalo() and #F.halos == 1, "分享 API 太舊：管理員只收到通訊距離的提示（閘門已註冊）")
F.reset()
SB.RuleShare = 1
C.registerGate()
F.fire("OnTick")
check(not shareHalo(), "陣營分享是「不需要錶」：本來就不限制，不提示")
SB.RuleShare = nil
F.admin = false
F.reset()
C.registerGate()
F.fire("OnTick")
check(#F.halos == 0, "一般玩家不提示")
F.admin = true
MinidoracatMiniMapServerAPI = { shareApiVersion = 1, registerShareFilter = function() return true end }
F.reset()
C.registerGate()
F.fire("OnTick")
check(#F.halos == 0, "分享 API 足夠：不提示")

-- 通訊類模組說明的分享距離從沙盒讀（不寫死 2000／8000）
check(C.moduleDesc("comm") == "IGUI_MinidoracatWatch_ShareRange|IGUI_MinidoracatWatch_ModuleDesc_comm|2000"
    and C.moduleDesc("longcomm") == "IGUI_MinidoracatWatch_ShareRange|IGUI_MinidoracatWatch_ModuleDesc_longcomm|8000",
    "預設：通訊 2000、長距 8000")
SB.CommRange, SB.LongCommRange = 1234, 30000
check(C.moduleDesc("comm"):find("|1234", 1, true) and C.moduleDesc("longcomm"):find("|30000", 1, true), "說明的距離跟著沙盒改")
SB.CommRange, SB.LongCommRange = nil, nil
check(C.moduleDesc("relay") == "IGUI_MinidoracatWatch_ShareRangeUnlimited|IGUI_MinidoracatWatch_ModuleDesc_relay",
    "中繼核心：不限距離")
check(C.moduleDesc("gps") == "IGUI_MinidoracatWatch_ModuleDesc_gps", "其他模組沒有距離")
SB.RuleShare = 2
check(C.moduleDesc("comm") == "IGUI_MinidoracatWatch_ModuleDesc_comm", "陣營分享不是「需要模組」：不量距離，不寫")
SB.RuleShare = nil

-- ===== 小地圖閘門 =====
local gate = registered.fn
local ok, reason, dist = gate(0, "minimap", nil)
check(ok == false and reason == W.REASON_NO_WATCH, "沒戴錶：擋小地圖")
local watch = give(F.RIGHT)
F.wear(p, watch)
F.fire("OnClothingUpdated", p)
check(gate(0, "minimap", "mini") == true, "穿戴事件後立刻生效：全新的錶放行")
W.setCharge(watch, W.NO_BATTERY)
ok, reason = gate(0, "minimap")
check(ok == false and reason == W.REASON_NO_BATTERY, "沒有電池：擋")
W.setCharge(watch, 0)
ok, reason = gate(0, "minimap")
check(ok == false and reason == W.REASON_DEAD, "沒電：擋")
SB.DeadMode = 2
check(gate(0, "minimap") == true and select(1, gate(0, "arrow")) == false, "沒電時保留小地圖：小地圖放行、其他功能照擋")
W.setCharge(watch, W.NO_BATTERY)
check(gate(0, "minimap") == true, "沒電時保留小地圖：沒電池也放行")
SB.DeadMode, SB.NeedBattery = nil, false
check(gate(0, "minimap") == true, "不需要電池：沒電池也放行")
SB.NeedBattery = nil
W.setCharge(watch, 0)
SB.Enabled = false
check(gate(0, "minimap") == true, "總開關關閉：放行")
SB.Enabled = true
SB.MinimapRule = 1
check(gate(0, "minimap") == true, "規則 free：放行")
SB.MinimapRule = 3
ok, reason = gate(0, "minimap")
check(ok == false and reason == W.REASON_OFF, "規則 off：擋")
SB.MinimapRule = 2
W.setCharge(watch, 0.5)

-- ===== 功能閘門矩陣 =====
-- 每個功能 × 規則（1 免／2 錶／3 模組／4 關）× 錶的狀態 × 模組（沒有／有效槽位／失效槽位）× surface
give("Base.Screwdriver")
local FEATS = {
    arrow = { key = "RuleArrow", mods = { "Compass" }, need = "compass" },
    poi = { key = "RulePoi", mods = { "Ledger" }, need = "ledger" },
    nav = { key = "RuleNav", mods = { "GPS" }, need = "gps" },
    share = { key = "RuleShare", mods = { "Comm", "LongComm", "Relay" }, need = "comm" },
    scan = { key = "RuleScan", mods = { "Scan" }, need = "scan", dist = 60 },
    zombie = { key = "RuleZombie", mods = { "Detect" }, need = "detect", dist = 40 },
}
local CLASS_SLOT = { standard = "ext", advanced = "adv", core = "core" }
SB.SlotExt, SB.SlotAdv, SB.SlotCore = 1, 1, 1
local function tick() F.now = F.now + 1000 end -- 讓狀態快取過期（期限 1 秒）
local matrix = true
local function expect(label, f, surface, wantOk, wantReason, wantDist)
    tick()
    local o, r, d = gate(0, f, surface)
    if o ~= wantOk or r ~= wantReason or d ~= wantDist then
        matrix = false
        check(false, label .. "：得到 " .. tostring(o) .. "," .. tostring(r) .. "," .. tostring(d))
    end
end
for f, spec in pairs(FEATS) do
    for _, m in ipairs(spec.mods) do
        local def = W.moduleByItem[MOD(m)]
        local slotId = CLASS_SLOT[def.class]
        local item = give(MOD(m))
        local L = f .. "/" .. m
        SB[spec.key] = 1
        expect(L .. " 免：沒裝也放行", f, "mini", true, nil, nil)
        SB[spec.key] = 4
        expect(L .. " 關：一律擋", f, "mini", false, W.REASON_FEATURE_OFF, nil)
        SB[spec.key] = 2
        expect(L .. " 錶：戴著有電就放行", f, "mini", true, nil, nil)
        SB[spec.key] = 3
        expect(L .. " 模組：沒裝擋", f, "mini", false, "IGUI_MinidoracatWatch_Reason_Need_" .. spec.need, nil)
        sp(W.applyModuleChange, p, watch:getID(), slotId, true, item:getID())
        expect(L .. " 模組：裝上放行", f, "mini", true, nil, spec.dist)
        SB[spec.key] = 4
        expect(L .. " 關：裝了也擋", f, "mini", false, W.REASON_FEATURE_OFF, nil)
        SB[spec.key] = 3
        local modeKey = ({ ext = "SlotExt", adv = "SlotAdv", core = "SlotCore" })[slotId]
        SB[modeKey] = 4
        expect(L .. " 槽位失效：paused", f, "mini", false, W.REASON_PAUSED, nil)
        SB[modeKey] = 1
        W.setCharge(watch, 0)
        expect(L .. " 沒電", f, "mini", false, W.REASON_DEAD, nil)
        W.setCharge(watch, W.NO_BATTERY)
        expect(L .. " 沒電池", f, "mini", false, W.REASON_NO_BATTERY, nil)
        W.setCharge(watch, 0.5)
        F.unwear(p, watch)
        F.fire("OnClothingUpdated", p)
        expect(L .. " 沒戴錶", f, "mini", false, W.REASON_NEED_WATCH, nil)
        F.wear(p, watch)
        F.fire("OnClothingUpdated", p)
        sp(W.applyModuleChange, p, watch:getID(), slotId, false)
        SB[spec.key] = nil
    end
end
check(matrix, "功能閘門矩陣（6 功能 × 規則 × 狀態）")
-- 殭屍：偵測模組只放行小地圖，軍規偵測兩種地圖、半徑 80
SB.RuleZombie = 3
local det = give(MOD("Detect"))
sp(W.applyModuleChange, p, watch:getID(), "std1", true, det:getID())
expect("偵測：小地圖", "zombie", "mini", true, nil, 40)
expect("偵測：surface nil 視同小地圖", "zombie", nil, true, nil, 40)
expect("偵測：世界地圖擋", "zombie", "world", false, "IGUI_MinidoracatWatch_Reason_Need_mildetect", nil)
local mil = give(MOD("MilDetect"))
sp(W.applyModuleChange, p, watch:getID(), "adv", true, mil:getID())
expect("軍規偵測：世界地圖", "zombie", "world", true, nil, 80)
expect("軍規偵測：小地圖用 80", "zombie", "mini", true, nil, 80)
SB.MilDetectRadius = 120
expect("半徑是沙盒選項", "zombie", "world", true, nil, 120)
SB.MilDetectRadius = nil
SB.SlotAdv = 4
expect("軍規偵測槽位失效：世界地圖 paused", "zombie", "world", false, W.REASON_PAUSED, nil)
expect("軍規偵測槽位失效：小地圖退回偵測模組", "zombie", "mini", true, nil, 40)
SB.SlotAdv = 1
SB.RuleZombie = 2
expect("戴錶就能用：世界地圖也放行、不套半徑", "zombie", "world", true, nil, nil)
SB.RuleZombie = nil
sp(W.applyModuleChange, p, watch:getID(), "std1", false)
sp(W.applyModuleChange, p, watch:getID(), "adv", false)
check(matrix, "殭屍 surface 規則")

-- nav：定位模組 active OR AutoDrive hasNavDevice；規則關閉時一律擋
local hasDevice, adCalls = true, 0
MinidoracatAutoDriveAPI = { navDeviceApiVersion = 1, hasNavDevice = function(pn) adCalls = adCalls + 1; return hasDevice end }
expect("nav：沒模組、有 GPS 導航儀＝放行", "nav", nil, true, nil, nil)
hasDevice = false
expect("nav：沒模組、沒裝置＝擋", "nav", nil, false, "IGUI_MinidoracatWatch_Reason_Need_gps", nil)
hasDevice = true
SB.RuleNav = 4
expect("nav 關閉：有裝置也擋", "nav", nil, false, W.REASON_FEATURE_OFF, nil)
SB.RuleNav = nil
F.unwear(p, watch)
F.fire("OnClothingUpdated", p)
expect("nav：沒戴錶、有裝置＝放行", "nav", nil, true, nil, nil)
F.wear(p, watch)
F.fire("OnClothingUpdated", p)
MinidoracatAutoDriveAPI.navDeviceApiVersion = 0
expect("AutoDrive 版本太舊：不問", "nav", nil, false, "IGUI_MinidoracatWatch_Reason_Need_gps", nil)
MinidoracatAutoDriveAPI = { navDeviceApiVersion = 1 }
expect("AutoDrive 沒有 hasNavDevice：不問", "nav", nil, false, "IGUI_MinidoracatWatch_Reason_Need_gps", nil)
MinidoracatAutoDriveAPI = nil
expect("AutoDrive 不存在", "nav", nil, false, "IGUI_MinidoracatWatch_Reason_Need_gps", nil)
MinidoracatAutoDriveAPI = { navDeviceApiVersion = 2, hasNavDevice = function() error("ad boom") end }
F.reset()
expect("hasNavDevice 拋錯：當沒有", "nav", nil, false, "IGUI_MinidoracatWatch_Reason_Need_gps", nil)
expect("hasNavDevice 再拋錯", "nav", nil, false, "IGUI_MinidoracatWatch_Reason_Need_gps", nil)
check(#F.logs == 1 and F.logs[1]:find("hasNavDevice", 1, true), "AutoDrive 拋錯只 log 一次")
MinidoracatAutoDriveAPI = { navDeviceApiVersion = 1, hasNavDevice = function() adCalls = adCalls + 1; return true end }
local gpsItem = give(MOD("GPS"))
sp(W.applyModuleChange, p, watch:getID(), "std1", true, gpsItem:getID())
adCalls = 0
expect("定位模組 active：不必問 AutoDrive", "nav", nil, true, nil, nil)
check(adCalls == 0, "模組 active 時不呼叫 hasNavDevice")
check(matrix, "nav 的 OR 與 AutoDrive 守衛")
MinidoracatAutoDriveAPI = nil

-- 熱路徑：快取期內不翻穿戴清單、不配置 table
local scans = 0
local realWorn = p.getWornItems
p.getWornItems = function(self) scans = scans + 1; return realWorn(self) end
gate(0, "scan", "mini")
scans = 0
collectgarbage("collect")
collectgarbage("stop")
local kb = collectgarbage("count")
for _ = 1, 20000 do
    gate(0, "minimap", "mini")
    gate(0, "nav", nil)
    gate(0, "zombie", "world")
end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
check(scans == 0, "快取期內不翻穿戴清單")
check(grew < 1, "60000 次呼叫不配置記憶體（增加 " .. string.format("%.2f", grew) .. " KB）")
p.getWornItems = nil

-- 沒收到事件時，1 秒保險期限後也會看到變化
F.unwear(p, watch)
check(gate(0, "minimap") == true, "期限內沿用快取")
F.now = F.now + 1000
check(gate(0, "minimap") == false, "期限到重新讀取")

-- 兩支都戴：每秒的客戶端迴圈提示一次、左腕那支生效
local left = give(F.LEFT)
F.wear(p, watch)
F.wear(p, left)
W.setCharge(left, 0)
F.reset()
F.fire("OnClothingUpdated", p)
ok, reason = gate(0, "minimap")
check(ok == false and reason == W.REASON_DEAD, "兩支都戴：看左腕那支（沒電）")
tick(); C.poll()
tick(); C.poll()
local two = 0
for _, h in ipairs(F.halos) do if h.text == "IGUI_MinidoracatWatch_TwoWorn" then two = two + 1 end end
check(two == 1, "兩支都戴只提示一次")
F.unwear(p, left)
F.fire("OnClothingUpdated", p)
check(gate(0, "minimap") == true, "拿下一支後恢復")

-- SyncClothing 先到時身上掛的是同 ID 的臨時物品：改讀背包那件
local phantom = F.item(F.RIGHT)
phantom.id = watch.id
F.unwear(p, watch)
p.worn[#p.worn + 1] = { loc = "rightwrist", item = phantom }
F.fire("OnClothingUpdated", p)
check(C.watchOf(0) == watch, "臨時物品解析回背包裡的那件")
F.unwear(p, phantom)
F.wear(p, watch)
F.fire("OnClothingUpdated", p)

-- ===== Dock =====
local dockSpec = F.dockSpec
check(C.docked == true and dockSpec and dockSpec.id == "minimapwatch", "UI 框架 rev 14＋dock：登記")
W.setCharge(watch, 0.5)
check(dockSpec.getState() == nil and dockSpec.getBadge() == 0, "電量足夠：無警示")
W.setCharge(watch, 0.1)
check(dockSpec.getState() == "warn" and dockSpec.getBadge() == 0, "低電量：warn")
W.setCharge(watch, 0)
check(dockSpec.getState() == "warn" and dockSpec.getBadge() == -1, "沒電：warn＋紅點")
W.setCharge(watch, 0.5)
check(dockSpec.getStatus() == "IGUI_MinidoracatWatch_Status_Charge|50|IGUI_MinidoracatWatch_TimeDaysHours|1|4",
    "停留說明：電量與剩餘時間（定位模組 +25%：72÷1.25×0.5＝28.8 小時）")
W.setCharge(watch, 0.005)
check(dockSpec.getStatus() == "IGUI_MinidoracatWatch_Status_ChargeUnderHour|1", "不到 1 小時用整句（不拼「大約還能用 不到 1 小時」）")
W.setCharge(watch, 0.5)
-- 不需要電池：Dock 不警示、停留說明寫不需要電池、圖示畫滿格
SB.NeedBattery = false
W.setCharge(watch, 0)
check(dockSpec.getState() == nil and dockSpec.getBadge() == 0
    and dockSpec.getStatus() == "IGUI_MinidoracatWatch_Status_NoBatteryNeeded", "不需要電池：Dock 不警示、說明不需要電池")
SB.NeedBattery = nil
W.setCharge(watch, 0.5)
F.draws, F.icons, F.fills = 0, {}, {}
dockSpec.drawIcon(setmetatable({}, Element), 0, 0, 28)
check(F.icons[1] == "battery" and F.draws >= 2, "drawIcon：框架 Icons 的電池＋內框電量（不自己畫外框）")
check(dockSpec.isActive() == false, "面板未開")
dockSpec.onClick()
check(dockSpec.isActive() == true, "點按鈕開面板")
dockSpec.onClick()
check(dockSpec.isActive() == false, "再點關閉")

-- ===== 換電池：計時動作，MP 完成時只送純量 =====
local weak, strong = F.item("Base.Battery"), F.item("Base.Battery")
weak:setCurrentUsesFloat(0.2)
strong:setCurrentUsesFloat(0.9)
p.inv:AddItem(weak)
F.bag(p.inv):AddItem(strong)
F.reset()
C.requestBattery(p, watch, true)
check(#F.clientCmds == 0 and F.queues[p][1] and F.queues[p][1].Type == "ISMinidoracatWatchAction"
    and F.queues[p][1].maxTime == 50, "換電池排進計時動作（約 1 秒），還沒送指令")
F.runActions(p)
local cmd = F.clientCmds[1]
check(cmd and cmd.module == W.MODULE and cmd.command == W.CMD_BATTERY, "動作完成時送換電池指令")
check(cmd.args.watchId == watch.id and cmd.args.install == true and cmd.args.batteryId == strong.id, "挑電量最高的電池")
local function scalars(args)
    for _, v in pairs(args) do if type(v) ~= "number" and type(v) ~= "boolean" and type(v) ~= "string" then return false end end
    return true
end
check(scalars(cmd.args), "payload 只有純量")
check(W.charge(watch) == 0.5, "客戶端不自己改電量")
F.reset()
C.requestBattery(p, watch, true)
p.inv:DoRemoveItem(watch)
F.runActions(p)
check(#F.clientCmds == 0, "錶離開身上：動作取消、不送指令")
p.inv:AddItem(watch)

-- ===== 裝卸模組：計時動作（約 3 秒），螺絲起子 =====
local compass = give(MOD("Compass"))
F.reset()
C.requestModule(p, watch, "std2", compass)
local act = F.queues[p][1]
check(act and act.kind == "module" and act.maxTime == 150 and act.install == true, "安裝排進計時動作（約 3 秒）")
F.runActions(p)
cmd = F.clientCmds[1]
check(cmd and cmd.command == W.CMD_MODULE and cmd.args.watchId == watch.id and cmd.args.slotId == "std2"
    and cmd.args.install == true and cmd.args.itemId == compass.id and scalars(cmd.args), "完成時送純量安裝指令")
F.reset()
C.requestModule(p, watch, "std2", compass)
p.inv:DoRemoveItem(compass)
F.runActions(p)
check(#F.clientCmds == 0, "模組在動作途中離開背包：取消")
p.inv:AddItem(compass)
local sd = p.inv:getAllTypeRecurse("Base.Screwdriver"):get(0)
p.inv:DoRemoveItem(sd)
F.reset()
C.requestModule(p, watch, "std2", compass)
check(not (F.queues[p] and F.queues[p][1]) and F.halos[1] and F.halos[1].text == W.FAIL_SCREWDRIVER,
    "沒有螺絲起子：不排動作、提示")
SB.NeedScrewdriver = false
C.requestModule(p, watch, "std2", compass)
check(F.queues[p][1] ~= nil, "沙盒關掉螺絲起子：可以排")
F.queues[p] = {}
SB.NeedScrewdriver = true
p.inv:AddItem(sd)
-- 單機：完成時直接套用 shared 突變點
F.mode = "sp"
local compassBefore = p.inv:getAllTypeRecurse(MOD("Compass")):size() - 1
C.requestModule(p, watch, "std2", compass)
F.runActions(p)
check(W.slotRecord(watch, "std2") and W.slotRecord(watch, "std2").id == "compass" and compass.container == nil,
    "單機：動作完成就裝好")
C.requestModule(p, watch, "std2", nil)
F.runActions(p)
check(W.slotRecord(watch, "std2") == nil and compass.container == nil and p.inv:getAllTypeRecurse(MOD("Compass")):size() == compassBefore + 1, "單機：拆下")
compass = p.inv:getAllTypeRecurse(MOD("Compass")):get(compassBefore)
F.mode = "client"

-- ===== 解鎖卡請求與伺服器送來的解鎖狀態 =====
SB.SlotExt = 2
local card = give("MinidoracatWatch.UnlockCard_Ext")
F.reset()
C.requestUnlock(p, "ext")
cmd = F.clientCmds[1]
check(cmd and cmd.command == W.CMD_UNLOCK and cmd.args.slotId == "ext" and cmd.args.cardId == card.id
    and scalars(cmd.args), "使用解鎖卡：MP 只送純量（槽位 id、卡 id）")
F.reset()
C.requestUnlock(p, "core")
check(#F.clientCmds == 0, "身上沒有對應的卡：不送")
tick()
check(W.slotValid(p, W.slotById.ext) == false, "還沒收到伺服器回覆：擴充槽無效")
F.fire("OnServerCommand", W.MODULE, W.CMD_UNLOCKS, { to = "alice", slots = { ext = true, adv = "yes", [1] = true } })
check(W.slotValid(p, W.slotById.ext) == true and W.clientUnlocks.alice.adv == nil and W.clientUnlocks.alice[1] == nil,
    "收到解鎖狀態：只收「槽位 id＝true」，快取立刻失效")
F.fire("OnServerCommand", W.MODULE, W.CMD_UNLOCKS, { to = "alice", slots = "junk" })
check(W.slotValid(p, W.slotById.ext) == true, "壞掉的回覆忽略")
-- 每位本機玩家在第一個客戶端 tick 補要一次解鎖狀態
F.reset()
tick(); C.poll()
local asked = 0
for _, c in ipairs(F.clientCmds) do if c.command == W.CMD_UNLOCKS_REQ then asked = asked + 1 end end
tick(); C.poll()
check(asked == 0, "MP：補要解鎖狀態只一次")

-- ===== 伺服器失敗回報 =====
F.reset()
F.now = F.now + 2000
F.fire("OnServerCommand", W.MODULE, W.CMD_FAILED, { reason = W.FAIL_SLOT_FULL, to = "alice" })
check(#F.halos == 1 and F.halos[1].player == p and F.halos[1].text == W.FAIL_SLOT_FULL, "白名單原因：提示對的玩家")
F.now = F.now + 2000
F.fire("OnServerCommand", W.MODULE, W.CMD_FAILED, { reason = "IGUI_Anything_Else", to = "alice" })
F.fire("OnServerCommand", W.MODULE, W.CMD_FAILED, { reason = W.FAIL_GENERIC, to = "bob" })
check(#F.halos == 1, "未知原因與別人的回報都忽略")

-- ===== onStateChanged：客戶端每秒比對（MP 客戶端與單機）=====
local seen = {}
MinidoracatWatchAPI.registerWatchModule({ id = "weather", name = "IGUI_X", class = "standard", drain = 15,
    item = "MyWeather.WeatherModule", onStateChanged = function(pl, s, old) seen[#seen + 1] = { p = pl, s = s, old = old } end })
tick(); C.poll()
check(#seen == 1 and seen[1].s == "missing" and seen[1].old == nil, "第一次比對通知目前狀態")
tick(); C.poll()
check(#seen == 1, "沒變不通知")
-- 同一座位換成新的 IsoPlayer（重生、分割畫面換人，AddCoopPlayer.java:153-162）、狀態相同：照樣通知一次、oldState＝nil
local reborn = setmetatable({}, getmetatable(p))
for k, v in pairs(p) do reborn[k] = v end
F.players[1] = reborn
tick(); C.poll()
check(#seen == 2 and seen[2].p == reborn and seen[2].s == "missing" and seen[2].old == nil,
    "同座位換新玩家物件：重新通知、oldState＝nil")
F.players[1] = p
tick(); C.poll()
seen = {}

-- ===== 面板（UI 框架元件）=====
SB.SlotExt, SB.SlotAdv, SB.SlotCore = 2, 4, 1
W.clientUnlocks.alice = {}
sp(W.applyModuleChange, p, watch:getID(), "std1", true, compass:getID())
C.openPanel(0, nil)
local panel = F.lastPanel
local UIv = MinidoracatUI.v1
check(C.isPanelOpen() and panel.inUI and getmetatable(getmetatable(panel)).__index == UIv.Window,
    "開啟面板：UI.Window 的子類別")
check(F.layouts.MinidoracatWatchPanel and F.layouts.MinidoracatWatchPanel.target == panel
    and F.layouts.MinidoracatWatchPanel.funcs == UIv.Window, "位置交給 ISLayoutManager（RegisterWindow(name, UI.Window, win)）")
check(panel.title == watch:getDisplayName() and panel.icon == watch:getTex() and panel.closable, "標題＝錶名、圖示＝錶的貼圖、內建關閉鈕")
local function slotIndex(id) for i, s in ipairs(panel:slots()) do if s.id == id then return i end end end
local function center(id)
    local x, y, s = panel.sockets:socketRect(slotIndex(id))
    return x + s / 2, y + s / 2
end
local function selectSlot(id)
    panel.sockets:onMouseDown(center(id))
    tick()
    panel:update()
end
local function acts()
    local ids = {}
    for _, b in ipairs(panel.actBtns) do if b.visible then ids[#ids + 1] = b.internal end end
    return table.concat(ids, ",")
end
local function act(id) for _, b in ipairs(panel.actBtns) do if b.visible and b.internal == id then return b end end end
selectSlot("std1")
check(panel.sel == 1, "點槽位＝選取")
check(acts() == "remove" and act("remove").icon == "screwdriver", "有模組的槽位：只有「拆下模組」（螺絲起子圖示）")
F.draws, F.icons = 0, {}
panel:prerender()
panel.sockets:prerender()
check(F.draws >= 40, "面板畫出錶面、槽位、檢視區、功能清單與電量列（" .. F.draws .. " 次繪製）")
local iconSet = {}
for _, k in ipairs(F.icons) do iconSet[k] = true end
check(iconSet.lock and iconSet.check and iconSet.battery, "鎖、功能勾、電池都用 UI.Icons，不自己畫")
F.reset()
act("remove"):forceClick()
check(F.queues[p][1] and F.queues[p][1].kind == "module" and F.queues[p][1].install == false
    and F.queues[p][1].slotId == "std1", "拆下模組按鈕：排拆卸動作")
F.queues[p] = {}
selectSlot("std3")
local mods = {}
for _, b in ipairs(panel.actBtns) do if b.visible then mods[#mods + 1] = b end end
check(#mods >= 2 and mods[1].internal == "module" and mods[1].icon == "tex", "空槽：檢視區列出裝得下的模組按鈕（圖示＝模組物品貼圖）")
local noAdv = true
for _, b in ipairs(mods) do if b.title == "IGUI_MinidoracatWatch_Module_mildetect" then noAdv = false end end
check(noAdv, "標準槽不列進階模組")
local picked = mods[1].def.item
mods[1]:forceClick()
check(F.queues[p][1] and F.queues[p][1].slotId == "std3" and F.queues[p][1].install
    and F.queues[p][1].item:getFullType() == picked, "按模組按鈕：排安裝動作")
F.queues[p] = {}
-- Focus 導覽：閱讀順序＝槽位區 → 檢視區按鈕 → 電量列按鈕；方向鍵在槽位間移動游標、Enter 選取
local targets = panel:keyboardTargets()
local function indexOf(c) for i, t in ipairs(targets) do if t == c then return i end end end
check(targets[1] == panel.sockets and targets[2] == mods[1] and indexOf(panel.btnInsert) > indexOf(mods[#mods])
    and indexOf(panel.btnRemove) > indexOf(mods[#mods]), "焦點順序：槽位區、模組按鈕、電量列按鈕")
local sk = panel.sockets
sk.cur = slotIndex("std1")
check(sk:onFocusKey(Keyboard.KEY_RIGHT) and sk.cur == slotIndex("std2") and panel.sel == slotIndex("std3"),
    "→：游標移到右邊那格，選取不變")
local fx, fy, fw = sk:focusRect()
local rx, ry, rs = sk:socketRect(sk.cur)
check(fx == rx and fy == ry and fw == rs, "焦點框只框游標那格")
check(sk.layout == "row" and sk:onFocusKey(Keyboard.KEY_DOWN) == false, "ValuTech 一列排開：↓ 不處理（交給 Focus 移到下一個目標）")
sk.cur = slotIndex("std1")
check(sk:onFocusKey(Keyboard.KEY_LEFT) == false and sk.cur == slotIndex("std1"), "最左邊再 ←：不處理、游標不動")
sk.cur = slotIndex("std2")
check(sk:onFocusKey(Keyboard.KEY_RETURN) and panel.sel == slotIndex("std2"), "Enter：選取游標那格")
local std2Label = "IGUI_MinidoracatWatch_SlotAndModule|IGUI_MinidoracatWatch_Slot_std2|IGUI_MinidoracatWatch_St_empty"
check(sk._focusLabel == std2Label and sk:focusLabel() == std2Label, "焦點說明：槽位名＋狀態")
check(sk.tooltip == std2Label, "框架 rev 15（不讀 focusLabel）：說明退回每幀讀的 tooltip")
local ui = C.ui()
ui.API_REVISION, ui.CAPABILITIES.focusLabel = 16, true
sk.cur = slotIndex("std1")
check(sk:onFocusKey(Keyboard.KEY_RIGHT) and sk:focusLabel() == std2Label and sk.tooltip == nil,
    "框架 rev 16＋focusLabel：游標換格就換說明，不再借 tooltip")
ui.API_REVISION, ui.CAPABILITIES.focusLabel = 15, nil
sk.cur = slotIndex("std3")
sk:forceClick()
check(panel.sel == slotIndex("std3"), "forceClick（手把 A）：選取")
selectSlot("ext")
local cardBtn = act("card")
check(cardBtn and cardBtn.enable and cardBtn.style == "primary" and cardBtn.icon == "card"
    and cardBtn.title == "IGUI_MinidoracatWatch_UseSlotCard|item:MinidoracatWatch.UnlockCard_Ext",
    "解鎖卡模式、未開啟：「使用擴充槽解鎖卡」（卡的物品名）主要按鈕可按（背包有卡）")
F.reset()
cardBtn:forceClick()
check(F.clientCmds[1] and F.clientCmds[1].command == W.CMD_UNLOCK and F.clientCmds[1].args.slotId == "ext", "按鈕送解鎖")
-- 其他 MOD 的槽位（解鎖卡模式）：要的是擴充槽解鎖卡，文案用卡的物品名、不是「槽位名＋解鎖卡」
MinidoracatWatchAPI.registerWatchSlot({ id = "forecast", name = "IGUI_X_Forecast", accepts = { "standard" },
    price = { rent = 80, days = 7, buy = 600 } })
SB.SlotAddon = 2
local function hasText(want) return table.concat(F.texts):find(want, 1, true) ~= nil end
local savedCards = {}
for _, c in ipairs(p.inv:getAllTypeRecurse("MinidoracatWatch.UnlockCard_Ext")._items) do
    savedCards[#savedCards + 1] = c
    c.container:DoRemoveItem(c)
end
tick()
panel:update()
selectSlot("forecast")
F.texts = {}
panel:prerender()
check(act("card") and act("card").title == "IGUI_MinidoracatWatch_UseSlotCard|item:MinidoracatWatch.UnlockCard_Ext"
    and not act("card").enable, "其他 MOD 的槽位：按鈕寫擴充槽解鎖卡、背包沒卡時停用")
check(hasText("IGUI_MinidoracatWatch_Desc_Card|item:MinidoracatWatch.UnlockCard_Ext|IGUI_X_Forecast")
    and hasText("IGUI_MinidoracatWatch_CardNone|item:MinidoracatWatch.UnlockCard_Ext"),
    "其他 MOD 的槽位：說明與「背包裡沒有…」用卡的物品名，槽位名另外傳")
local fsx, fsy, fss = panel.sockets:socketRect(slotIndex("forecast"))
check(fss == 40 and fsy > panel.sockets:faceH() and panel.sockets.height >= fsy + fss, "其他 MOD 的槽位排在錶面下方（40px），槽位區跟著長高")
for _, c in ipairs(savedCards) do p.inv:AddItem(c) end
SB.SlotAddon = 1
for i = #W.slotList, 1, -1 do if W.slotList[i].id == "forecast" then table.remove(W.slotList, i) end end
W.slotById.forecast = nil
W.invalidate()
selectSlot("adv")
check(acts() == "", "不開放的槽位：沒有按鈕")
-- 拖曳：放到可以裝的槽位排動作；放到不能裝的槽位以 Toast 提示原因（面板開著時 Toast 避開面板）
local scan = give(MOD("Scan"))
ISMouseDrag.dragging = { scan }
F.reset()
F.toasts = {}
sk:onMouseUp(center("std3"))
check(F.queues[p][1] and F.queues[p][1].slotId == "std3" and F.queues[p][1].item == scan, "拖到空的標準槽：排安裝動作")
F.queues[p] = {}
sk:onMouseUp(center("std1"))
check(not F.queues[p][1] and F.toasts[1] and F.toasts[1]:find("Drop_Full", 1, true) and #F.halos == 0,
    "拖到已經有模組的槽位：Toast 提示、不排")
F.toasts = {}
sk:onMouseUp(center("ext"))
check(not F.queues[p][1] and F.toasts[1] and F.toasts[1]:find("Drop_Locked", 1, true), "拖到未開啟的槽位：提示")
F.toasts = {}
mil = p.inv:getAllTypeRecurse(MOD("MilDetect")):get(0)
ISMouseDrag.dragging = { mil }
sk:onMouseUp(center("std3"))
check(not F.queues[p][1] and F.toasts[1] and F.toasts[1]:find("Drop_Class", 1, true), "類別不符：提示")
F.toasts = {}
ISMouseDrag.dragging = { watch }
sk:onMouseUp(center("std3"))
check(not F.queues[p][1] and #F.toasts == 0, "拖的不是模組：不處理")
local ax, ay, aw, ah = F.avoid.MinidoracatWatchPanel()
check(ax == panel.x and ay == panel.y and aw == panel.width and ah == panel.height, "Toast 避開區＝面板矩形")
sk.mouseOver, sk.mx, sk.my = true, center("std1")
ISMouseDrag.dragging = { scan }
F.texts = {}
sk:prerender()
check(hasText("Drop_Full"), "拖曳中滑過不能裝的槽位：錶面底部寫原因")
sk.mouseOver = false
ISMouseDrag.dragging = nil
-- 槽位失效：模組留著、標示停用
SB.SlotCore = 4
local eco = give(MOD("Eco"))
SB.SlotCore = 1
sp(W.applyModuleChange, p, watch:getID(), "core", true, eco:getID())
SB.SlotCore = 4
check(C.slotStatus(p, watch, W.slotById.core) == "paused", "核心槽改成不開放：模組 paused")
selectSlot("core")
check(acts() == "remove", "失效槽位裡的模組隨時能拆")
W.setCharge(watch, 0)
check(C.slotStatus(p, watch, W.slotById.std1) == "dead", "沒電：模組 dead")
-- 橫幅狀態在 update 與 prerender 之間變了（伺服器推送剛到）：這一幀不畫，不拿還沒算過的寬度折行
-- （1006s watch-econ-mp：第一次出現橫幅時寬度還是 nil，prerender 連續拋錯）
panel.bannerTextW, panel.bannerMsg = nil, nil
check(pcall(panel.prerender, panel), "沒電的狀態剛到、還沒 update：prerender 不出錯")
tick()
panel:update()
check(panel.bannerMsg and panel.bannerMsg:find("Banner_Dead", 1, true) and panel.btnBanner.visible
    and panel.btnBanner.style == "primary" and panel.btnBanner.icon == "battery", "沒電：橫幅＋主要的「更換電池」鈕")
check(panel.btnInsert.style == "primary", "沒電：電量列的電池按鈕也是主要按鈕")
W.setCharge(watch, 0.5)
tick()
panel:update()
panel:prerender()
check(not panel.btnBanner.visible and panel.btnInsert.style == "normal", "電量正常：沒有橫幅按鈕")
-- 沒電時保留小地圖：橫幅不寫「無訊號」；不需要電池：沒有電池橫幅、電量列寫不需要電池
W.setCharge(watch, 0)
SB.DeadMode = 2
tick()
panel:update()
check(panel.bannerMsg and panel.bannerMsg:find("Banner_Dead_Map", 1, true), "沒電時保留小地圖：橫幅改寫小地圖照常顯示")
SB.DeadMode, SB.NeedBattery = nil, false
tick()
panel:update()
check(panel.bannerMsg == nil and panel.footText == "IGUI_MinidoracatWatch_Foot_NoBatteryNeeded"
    and panel.btnInsert.style == "normal" and C.slotStatus(p, watch, W.slotById.std1) ~= "dead",
    "不需要電池：沒有電池橫幅、電量列寫不需要電池、模組不算沒電")
SB.NeedBattery = nil
W.setCharge(watch, 0.5)
tick()
panel:update()
-- 充電（W.chargeState／W.chargeHoursToFull 換成固定值，看電量列怎麼寫）
local realState, realToFull = W.chargeState, W.chargeHoursToFull
W.chargeState = function() return "car" end
W.chargeHoursToFull = function() return 5 end
panel:update()
check(panel.footText:find("Foot_ChargingCar", 1, true) and panel.footText:find("TimeHours|5", 1, true), "車上充電：電量列寫充電中與充滿時間")
W.chargeState, W.chargeHoursToFull = realState, realToFull
panel:update()
check(not panel.footText:find("Charging", 1, true), "沒在充電：照舊")
p.inv:DoRemoveItem(watch)
F.unwear(p, watch)
F.fire("OnClothingUpdated", p)
tick()
panel:update()
panel:prerender()
check(not panel.btnInsert.enable and not panel.btnRemove.enable and acts() == "", "錶離開身上：按鈕停用、不出錯")
p.inv:AddItem(watch)
F.wear(p, watch)
F.fire("OnClothingUpdated", p)
tick()
panel:update()
local px, py = 333, 222
panel.x, panel.y = px, py
panel:close()
check(not C.isPanelOpen() and not panel.inUI, "關閉鈕：關閉面板")
check(F.avoid.MinidoracatWatchPanel() == nil, "關閉後 Toast 不再避開")
C.openPanel(0, nil)
check(F.lastPanel.x == px and F.lastPanel.y == py, "重開沿用這次的位置")
C.closePanel()

-- ===== 七款皮膚：面板依戴著的款式換 theme、版面與槽位外形；框架 rev 14 退回預設 theme =====
local function openStyle(style, amber)
    local w = F.item("MinidoracatWatch.MapWatch_" .. style .. "_Left")
    if amber then w:getModData()[W.SCREEN_KEY] = 1 end
    p.inv:AddItem(w)
    C.openPanel(0, w)
    return F.lastPanel, w
end
local pp, pw = openStyle("Paws")
check(pp.skinKey == "paws" and pp.sockets.layout == "ring" and pp.shape == "cat" and pp.theme.radius == 20
    and pp.btnInsert.theme == pp.theme, "貓爪：環狀版面、貓頭槽、圓角 20，按鈕跟著換 theme")
pp:update()
F.draws = 0
pp:prerender()
pp.sockets:prerender()
check(F.draws > 40, "貓爪面板畫得出來")
pp, pw = openStyle("BB3000", true)
check(pp.skinKey == "crt-amber" and pp.mono and pp.sockets.layout == "plates", "嗶嗶腕機琥珀：琥珀 theme、等寬讀數")
pp:update()
local AMBER = "media/textures/Item_MinidoracatWatch_BB3000_Amber.png"
local amberFile = io.open(F.MEDIA .. "/../textures/Item_MinidoracatWatch_BB3000_Amber.png", "rb")
if amberFile then amberFile:close() end
check(pp.icon == "tex:" .. AMBER and pp.faceTex == pp.icon and amberFile ~= nil,
    "嗶嗶腕機琥珀：標題列與錶面用琥珀版錶圖示（圖檔存在）")
pw:getModData()[W.SCREEN_KEY] = 0
pp:update()
check(pp.skinKey == "crt" and pp.icon == pw:getTex() and pp.faceTex == nil, "螢幕切回綠色：面板跟著換 theme 與錶圖示")
pp.sockets.cur = 1
check(pp.sockets:onFocusKey(Keyboard.KEY_DOWN) and pp.sockets.cur == 4 and pp.sockets:onFocusKey(Keyboard.KEY_RIGHT)
    and pp.sockets.cur == 5 and pp.sockets:onFocusKey(Keyboard.KEY_UP) and pp.sockets.cur == 2, "3×2 版面：↓ → ↑ 依位置走")
pp, pw = openStyle("ValuTech")
check(pp.actBtns[1].theme == pp.inspTheme and pp.inspTheme ~= pp.theme, "ValuTech：檢視區按鈕用液晶 theme")
C.closePanel()
F.installUI(14)
C.openPanel(0, pw)
check(F.lastPanel.theme.radius == nil and F.lastPanel.theme.colors.socket ~= nil, "框架 rev 14：預設 theme（沒有圓角）、自有 token 照樣在")
C.closePanel()
F.installUI(13)
F.toasts, F.halos = {}, {}
F.reset()
C.openPanel(0, pw)
check(not C.isPanelOpen() and #F.halos == 1 and F.halos[1].text == "IGUI_MinidoracatWatch_UiTooOld"
    and F.logs[1]:find("rev 14", 1, true), "框架 rev 13：面板不開、提示並 log 一次")
F.installUI(15)

-- ===== 面板文字換行：英文在空格斷、中日文兩字之間直接斷（量字寬假物件：每字元 7px）=====
local en = C.wrapText("open the expansion slot now", 90)
check(en[1] == "open the " and en[2] == "expansion " and en[3] == "slot now", "英文在空格斷（" .. table.concat(en, "|") .. "）")
local cjk = "\228\184\128\228\184\128 3 \231\167\146\228\184\128\228\184\128"
local cl = C.wrapText(cjk, 70)
check(table.concat(cl) == cjk and #cl[1] == 10, "非 ASCII 之間直接斷、不退回前面的空格（" .. #cl[1] .. "）")
local fit = true
for _, l in ipairs(C.wrapText(string.rep("word ", 30), 70)) do if #l * 7 > 70 + 7 then fit = false end end
check(fit, "每行不超過寬度（行尾空格除外）")

-- ===== 右鍵選單 =====
local function context(items)
    local ctx = newMenu()
    F.fire("OnFillInventoryObjectContextMenu", 0, ctx, items)
    return ctx.options
end
local opts = context({ { items = { watch, watch } } })
check(opts[1].name == "IGUI_MinidoracatWatch_Open" and opts[2].name == "IGUI_MinidoracatWatch_ReplaceBattery"
    and opts[3].name == "IGUI_MinidoracatWatch_RemoveBattery", "錶的右鍵：開啟／更換／取出電池")
local rm = opts[4]
check(rm and rm.name == "IGUI_MinidoracatWatch_RemoveModule" and rm.sub and #rm.sub.options == 2, "錶的右鍵：拆下模組 ▸ 列出裝著的模組")
F.reset()
pick(rm.sub.options[1])
check(F.queues[p][1] and F.queues[p][1].install == false and F.queues[p][1].slotId == "std1", "選單拆下：排動作")
F.queues[p] = {}
SB.SlotCore = 1
opts = context({ scan })
local inst = opts[1]
local targets = {}
for _, o in ipairs(inst.sub and inst.sub.options or {}) do if o.target == watch then targets[#targets + 1] = o.b end end
check(inst.name == "IGUI_MinidoracatWatch_InstallToWatch" and table.concat(targets, ",") == "std2,std3",
    "模組右鍵：只列有效空槽（" .. table.concat(targets, ",") .. "）")
pick(inst.sub.options[1])
check(F.queues[p][1] and F.queues[p][1].slotId == "std2" and F.queues[p][1].item == scan, "選單安裝：排動作")
F.queues[p] = {}
SB.SlotCore = 4
mil = p.inv:getAllTypeRecurse(MOD("MilDetect")):get(0)
opts = context({ mil })
targets = {}
for _, o in ipairs(opts[1].sub and opts[1].sub.options or {}) do targets[#targets + 1] = o.b end
check(#targets == 0 and opts[1].notAvailable, "進階模組沒有能裝的槽位（進階、核心槽都不開放）：選項停用")
SB.SlotCore = 1
opts = context({ card })
check(opts[1].name == "IGUI_MinidoracatWatch_UseCard" and opts[1].sub and #opts[1].sub.options == 1
    and opts[1].sub.options[1].name == "IGUI_MinidoracatWatch_OpenSlot|IGUI_MinidoracatWatch_Slot_ext", "解鎖卡右鍵：開啟擴充槽")
W.clientUnlocks.alice = { ext = true }
W.invalidate()
opts = context({ card })
check(opts[1].notAvailable, "已開啟：選項停用")
check(#context({ F.item(F.LEFT) }) == 0, "不在身上的錶不加選項")
check(#context({ F.item("Base.Battery") }) == 0, "其他物品不加選項")

-- ===== 孤立槽位（提供槽位的 MOD 被移除）：面板與右鍵選單照樣列出、能拆下 =====
F.queues[p] = {}
watch:getModData()[W.SLOTS_KEY].gone = { id = "scan", item = MOD("Scan") }
W.invalidate()
tick()
check(MinidoracatWatchAPI.getWatchModuleState(p, "scan") == "paused", "孤立槽位裡的模組 paused")
check(C.slotStatus(p, watch, W.orphanSlot("gone")) == "paused", "面板把孤立槽位標成已停用（不是運作中）")
opts = context({ watch })
local orphanOpt
for _, o in ipairs(opts) do
    if o.name == "IGUI_MinidoracatWatch_RemoveModule" then
        for _, so in ipairs(o.sub.options) do if so.b == "gone" then orphanOpt = so end end
    end
end
check(orphanOpt and orphanOpt.name == "IGUI_MinidoracatWatch_SlotAndModule|IGUI_MinidoracatWatch_Slot_orphan|IGUI_MinidoracatWatch_Module_scan",
    "錶的右鍵「拆下模組 ▸」列出孤立槽位")
if orphanOpt then pick(orphanOpt) end
check(F.queues[p] and F.queues[p][1] and F.queues[p][1].slotId == "gone" and F.queues[p][1].install == false,
    "選單拆下孤立槽位：排動作")
F.queues[p] = {}
C.openPanel(0, nil)
panel = F.lastPanel
panel:update()
local orphanIdx
for i, s in ipairs(panel.slots and panel:slots() or W.slotList) do if s.id == "gone" then orphanIdx = i end end
check(orphanIdx ~= nil, "面板列出孤立槽位")
if orphanIdx then
    selectSlot("gone")
    F.draws = 0
    panel:prerender()
    panel.sockets:prerender()
    check(panel:selectedSlot().id == "gone" and acts() == "remove" and F.draws > 0,
        "選孤立槽位：檢視區畫得出來、有「拆下模組」")
    act("remove"):forceClick()
    check(F.queues[p][1] and F.queues[p][1].slotId == "gone", "面板拆下孤立槽位：排動作")
end
F.queues[p] = {}
F.mode = "sp"
local scansBefore = p.inv:getAllTypeRecurse(MOD("Scan")):size()
C.requestModule(p, watch, "gone", nil)
F.runActions(p)
F.mode = "client"
check(W.slotRecord(watch, "gone") == nil and p.inv:getAllTypeRecurse(MOD("Scan")):size() == scansBefore + 1,
    "單機：孤立槽位的模組拆下回背包")
C.requestModule(p, watch, "nope", nil)
check(not F.queues[p][1], "沒有紀錄的未知槽位：不排動作")
C.closePanel()

-- ===== 嗶嗶腕機的螢幕顏色：右鍵、面板按鈕、MP 送純量、伺服器廣播 =====
local BB = "MinidoracatWatch.MapWatch_BB3000_Left"
local bb = F.item(BB)
p.inv:AddItem(bb)
local function screenOpt(list)
    for _, o in ipairs(list) do if o.name:find("IGUI_MinidoracatWatch_Screen", 1, true) then return o end end
end
local scr = screenOpt(context({ bb }))
check(scr and scr.name == "IGUI_MinidoracatWatch_ScreenAmber", "嗶嗶腕機的右鍵：螢幕改成琥珀色")
check(screenOpt(context({ watch })) == nil, "其他款沒有螢幕選項")
F.reset()
if scr then pick(scr) end
local sc = F.clientCmds[1]
check(#F.clientCmds == 1 and sc.command == W.CMD_SCREEN and sc.args.choice == 1 and sc.args.watchId == bb:getID(),
    "MP：送純量指令（watchId、choice 1）")
bb:getModData()[W.SCREEN_KEY] = 1
scr = screenOpt(context({ bb }))
check(scr and scr.name == "IGUI_MinidoracatWatch_ScreenGreen", "琥珀色時：選項改成「螢幕改成綠色」")
C.openPanel(0, bb)
panel = F.lastPanel
panel:update()
check(panel.btnScreen.visible and panel.btnScreen.title == "IGUI_MinidoracatWatch_ScreenGreen", "面板：嗶嗶腕機有螢幕按鈕")
F.reset()
panel.btnScreen:forceClick()
check(F.clientCmds[1] and F.clientCmds[1].args.choice == 0, "面板按鈕：送 choice 0（改回綠色）")
C.openPanel(0, watch)
panel = F.lastPanel
panel:update()
check(not panel.btnScreen.visible, "面板：其他款沒有螢幕按鈕")
C.closePanel()
-- 伺服器廣播：本機玩家改 WornItems 的 visual、遠端玩家改 remotePlayerItemVisuals，有改才 resetModelNextFrame
p.onlineId = 7
F.wear(p, bb)
local remoteVis = F.visual(BB, 0)
local hat = F.visual("Base.Hat_Beret", 0)
p.remoteVisuals = { remoteVis, hat }
p.resets = 0
bb:getVisual():setTextureChoice(0)
F.fire("OnServerCommand", W.MODULE, W.CMD_SCREEN, { pid = 7, id = bb:getID(), choice = 1 })
check(bb:getVisual():getTextureChoice() == 1 and remoteVis.choice == 1 and hat.choice == 0 and p.resets == 1,
    "廣播：穿著的錶與遠端 visual 都改成琥珀、其他衣物不動、模型重建一次")
F.fire("OnServerCommand", W.MODULE, W.CMD_SCREEN, { pid = 7, id = bb:getID(), choice = 1 })
check(p.resets == 1, "同樣的值再來一次：不重建模型")
for _, args in ipairs({ { pid = 99, choice = 0 }, { pid = 7, choice = 2 }, { pid = 7, choice = "0" }, { pid = 7.5, choice = 0 } }) do
    F.fire("OnServerCommand", W.MODULE, W.CMD_SCREEN, args)
end
check(bb:getVisual():getTextureChoice() == 1 and p.resets == 1, "找不到玩家、choice 不合法、pid 不是整數：忽略")
F.unwear(p, bb)
F.wear(p, watch)

-- ===== 付費槽位（Economy，Phase 6）：面板按鈕走 C.Pay.ui，不是解鎖卡 =====
local oldExt = SB.SlotExt
SB.SlotExt = 3
W.econStatus = "READY"
W.clientPay.alice = {}
local econEnv = { ok = true, available = true, entitlement = { permanent = 0, rentals = {}, revision = 1 },
    balances = { survivor = { available = 1000 } },
    plan = { permanentEnabled = true, permanentPrice = 400, permanentCurrency = "survivor", rentalEnabled = true,
        rentalPrice = 60, rentalCurrency = "survivor", rentalDays = 7, graceHours = 24, autoRenewAllowed = true, revision = 2 } }
local econQuote = nil
MinidoracatEconomy = { v1 = { Client = { API_MAJOR = 1, API_REVISION = 2, CAPABILITIES = { entitlements = true, rentals = true },
    Entitlements = { getState = function() return econEnv end, requestState = function() return 1 end,
        quote = function(_, pid, kind) econQuote = { pid = pid, kind = kind }; return 1 end,
        currencyName = function(id) return id end, errorText = function(c) return c end } } } }
C.Pay.views = {}
C.openPanel(0, watch)
panel = F.lastPanel
selectSlot("ext")
check(acts() == "rent,buy" and act("rent").style == "primary" and act("rent").icon == "clock"
    and act("buy").style == "normal" and act("buy").icon == "infinity", "經濟系統、未開啟：租用（主要、時鐘）與買斷（無限）按鈕，不是解鎖卡")
check(act("rent").x == act("buy").x and act("buy").y > act("rent").y,
    "付費按鈕放不下一列：第二顆換到下一列（測試的假字寬很寬）")
act("buy"):forceClick()
panel:update()
check(acts() == "pay,cancel", "按買斷：確認頁（付款、取消）")
F.texts = {}
panel:prerender()
local sheetShown = false
for _, t in ipairs(F.texts) do if t:find("PaySheet_permanent", 1, true) then sheetShown = true end end
check(sheetShown, "檢視區畫出買斷確認頁")
act("pay"):forceClick()
check(econQuote and econQuote.pid == "watch_ext" and econQuote.kind == "permanent", "付款鈕：先向 Economy 報價")
C.closePanel()
-- 管理員收到改價提醒：Toast（付款相關通知）
F.toasts = {}
F.admin = true
F.fire("OnServerCommand", W.MODULE, W.CMD_PLAN_WARN, { slot = "ext" })
check(F.toasts[1] and F.toasts[1]:find("PlanTermsChanged", 1, true), "改價提醒：Toast")
MinidoracatEconomy, W.econStatus, C.Pay.sheet, C.Pay.busy, SB.SlotExt = nil, nil, nil, {}, oldExt

-- ===== UI 框架版本不足：不登記、不出錯 =====
F.installUI(13)
F.dockSpec = nil
F.reset()
F.load("client/MinidoracatWatch_Client.lua")
check(MinidoracatWatchClient.docked == false and F.dockSpec == nil, "rev 13（沒有 battery 圖示）：不登記 Dock")
MinidoracatUI = nil
F.load("client/MinidoracatWatch_Client.lua")
check(MinidoracatWatchClient.docked == false, "沒有 UI 框架：照樣載入")

F.finish("test_watch_client")
