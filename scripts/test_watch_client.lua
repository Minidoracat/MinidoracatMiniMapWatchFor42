-- 地圖錶客戶端：主 MOD 版本守衛、功能閘門矩陣（模組 × 狀態 × 規則 × surface、nav 的 AutoDrive OR）、快取零配置、
-- Dock、計時動作請求（換電池／裝卸模組）、解鎖卡請求、伺服器回報、面板（槽位、拖曳、按鈕）、右鍵選單。
-- 用法（repo 根目錄）：lua scripts/test_watch_client.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check = F.check
F.mode = "client"

-- ===== 客戶端 UI 假物件 =====
UIFont = { Small = "S", Medium = "M" }
function getCore() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
function getTextManager()
    return { MeasureStringX = function(_, _, s) return #s * 7 end, getFontHeight = function() return 16 end }
end
function getMouseX() return 100 end
function getMouseY() return 100 end
F.draws = 0
local Element = {}
function Element:drawText() F.draws = F.draws + 1 end
function Element:drawTextCentre() F.draws = F.draws + 1 end
function Element:drawRect() F.draws = F.draws + 1 end
function Element:drawRectBorder() F.draws = F.draws + 1 end
function Element:drawTextureScaled() F.draws = F.draws + 1 end
function Element:getMouseX() return self.mx or 0 end
function Element:getMouseY() return self.my or 0 end
ISPanel = setmetatable({}, { __index = Element })
function ISPanel.new(cls, x, y, w, h)
    local o = { x = x, y = y, width = w, height = h }
    setmetatable(o, cls)
    cls.__index = cls
    return o
end
function ISPanel:derive(name) local c = setmetatable({ Type = name }, { __index = self }); c.__index = c; return c end
function ISPanel:initialise() end
function ISPanel:prerender() end
function ISPanel:update() end
function ISPanel:onMouseDown() F.panelMoved = true; return true end
function ISPanel:onMouseUp() return true end
function ISPanel:addChild(c) self.children = self.children or {}; table.insert(self.children, c) end
function ISPanel:addToUIManager() self.inUI = true; F.lastPanel = self; if self.createChildren then self:createChildren() end end
function ISPanel:removeFromUIManager() self.inUI = false end
ISButton = {}
function ISButton:new(x, y, w, h, title, target, onclick)
    return { title = title, target = target, onclick = onclick, enabled = true, visible = true, initialise = function() end,
        setTitle = function(b, t) b.title = t end, setEnable = function(b, e) b.enabled = e end,
        setVisible = function(b, v) b.visible = v end }
end
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

local dockSpec
MinidoracatUI = { v1 = { API_MAJOR = 1, API_REVISION = 13, CAPABILITIES = { dock = true },
    Dock = { register = function(spec) dockSpec = spec; return true end } } }

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
F.fire("OnGameStart")
check(C.gateActive == false, "主 MOD 沒有 API：不設閘")
check(#F.logs == 1 and F.logs[1]:find("featureApiVersion", 1, true) ~= nil, "log 一次")
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
check(C.docked == true and dockSpec and dockSpec.id == "minimapwatch", "UI 框架 rev 13 有 dock：登記")
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
F.draws = 0
dockSpec.drawIcon(setmetatable({}, { __index = Element }), 0, 0, 28)
check(F.draws >= 3, "drawIcon 畫出電池")
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
    item = "MyWeather.WeatherModule", onStateChanged = function(pl, s, old) seen[#seen + 1] = s end })
tick(); C.poll()
check(#seen == 1 and seen[1] == "missing", "第一次比對通知目前狀態")
tick(); C.poll()
check(#seen == 1, "沒變不通知")

-- ===== 面板 =====
SB.SlotExt, SB.SlotAdv, SB.SlotCore = 2, 4, 1
W.clientUnlocks.alice = {}
sp(W.applyModuleChange, p, watch:getID(), "std1", true, compass:getID())
C.openPanel(0, nil)
local panel = F.lastPanel
check(C.isPanelOpen() and panel.inUI, "開啟面板")
local function slotIndex(id) for i, s in ipairs(W.slotList) do if s.id == id then return i end end end
local function selectSlot(id)
    local x, y, s = panel:socketRect(slotIndex(id))
    panel:onMouseDown(x + s / 2, y + s / 2)
    tick()
    panel:update()
end
F.panelMoved = false
selectSlot("std1")
check(panel.sel == 1 and not F.panelMoved, "點槽位＝選取，不拖動面板")
check(panel.btnRemoveModule.visible and not panel.btnInstall.visible and not panel.btnCard.visible,
    "有模組的槽位：只有「拆下模組」")
F.draws = 0
panel:prerender()
check(F.draws >= 40, "面板畫出錶面、槽位、檢視區、功能清單與電池區（" .. F.draws .. " 次繪製）")
F.reset()
panel.btnRemoveModule.onclick(panel)
check(F.queues[p][1] and F.queues[p][1].kind == "module" and F.queues[p][1].install == false
    and F.queues[p][1].slotId == "std1", "拆下模組按鈕：排拆卸動作")
F.queues[p] = {}
selectSlot("std3")
check(panel.btnInstall.visible and not panel.btnRemoveModule.visible, "空槽：只有「安裝模組」")
local menu = panel:onInstall()
local names = {}
for _, o in ipairs(menu.options) do names[#names + 1] = o.name end
check(#menu.options >= 2 and not menu.options[1].notAvailable, "安裝模組：列出背包裡裝得下的模組（" .. table.concat(names, ",") .. "）")
local noAdv = true
for _, o in ipairs(menu.options) do if o.name == "IGUI_MinidoracatWatch_Module_mildetect" then noAdv = false end end
check(noAdv, "標準槽不列進階模組")
pick(menu.options[1])
check(F.queues[p][1] and F.queues[p][1].slotId == "std3" and F.queues[p][1].install, "從清單選模組：排安裝動作")
F.queues[p] = {}
selectSlot("ext")
check(panel.btnCard.visible and panel.btnCard.enabled and panel.btnCard.title == "IGUI_MinidoracatWatch_UseSlotCard|IGUI_MinidoracatWatch_Slot_ext",
    "解鎖卡模式、未開啟：「使用擴充槽解鎖卡」可按（背包有卡）")
F.reset()
panel.btnCard.onclick(panel)
check(F.clientCmds[1] and F.clientCmds[1].command == W.CMD_UNLOCK and F.clientCmds[1].args.slotId == "ext", "按鈕送解鎖")
selectSlot("adv")
check(not panel.btnCard.visible and not panel.btnInstall.visible and not panel.btnRemoveModule.visible, "不開放的槽位：沒有按鈕")
-- 拖曳：放到可以裝的槽位排動作；放到不能裝的槽位提示原因
local scan = give(MOD("Scan"))
ISMouseDrag.dragging = { scan }
F.reset()
local x, y = panel:socketRect(slotIndex("std3"))
panel:onMouseUp(x + 5, y + 5)
check(F.queues[p][1] and F.queues[p][1].slotId == "std3" and F.queues[p][1].item == scan, "拖到空的標準槽：排安裝動作")
F.queues[p] = {}
x, y = panel:socketRect(slotIndex("std1"))
panel:onMouseUp(x + 5, y + 5)
check(not F.queues[p][1] and F.halos[1] and F.halos[1].text:find("Drop_Full", 1, true), "拖到已經有模組的槽位：提示、不排")
F.reset()
x, y = panel:socketRect(slotIndex("ext"))
panel:onMouseUp(x + 5, y + 5)
check(not F.queues[p][1] and F.halos[1] and F.halos[1].text:find("Drop_Locked", 1, true), "拖到未開啟的槽位：提示")
F.reset()
mil = p.inv:getAllTypeRecurse(MOD("MilDetect")):get(0)
ISMouseDrag.dragging = { mil }
x, y = panel:socketRect(slotIndex("std3"))
panel:onMouseUp(x + 5, y + 5)
check(not F.queues[p][1] and F.halos[1] and F.halos[1].text:find("Drop_Class", 1, true), "類別不符：提示")
F.reset()
ISMouseDrag.dragging = { watch }
panel:onMouseUp(x + 5, y + 5)
check(not F.queues[p][1] and #F.halos == 0, "拖的不是模組：照一般面板處理")
panel.mx, panel.my = x + 5, y + 5
ISMouseDrag.dragging = { scan }
F.draws = 0
panel:prerender()
check(F.draws > 0, "拖曳中滑過槽位：畫可否安裝的提示")
ISMouseDrag.dragging = nil
-- 槽位失效：模組留著、標示停用
SB.SlotCore = 4
local eco = give(MOD("Eco"))
SB.SlotCore = 1
sp(W.applyModuleChange, p, watch:getID(), "core", true, eco:getID())
SB.SlotCore = 4
check(C.slotStatus(p, watch, W.slotById.core) == "paused", "核心槽改成不開放：模組 paused")
selectSlot("core")
check(panel.btnRemoveModule.visible, "失效槽位裡的模組隨時能拆")
W.setCharge(watch, 0)
check(C.slotStatus(p, watch, W.slotById.std1) == "dead", "沒電：模組 dead")
W.setCharge(watch, 0.5)
panel:update()
panel:prerender()
p.inv:DoRemoveItem(watch)
F.unwear(p, watch)
F.fire("OnClothingUpdated", p)
tick()
panel:update()
panel:prerender()
check(not panel.btnInsert.enabled and not panel.btnRemove.enabled, "錶離開身上：按鈕停用、不出錯")
p.inv:AddItem(watch)
F.wear(p, watch)
F.fire("OnClothingUpdated", p)
C.closePanel()
check(not C.isPanelOpen() and not panel.inUI, "關閉面板")

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

-- ===== UI 框架版本不足：不登記、不出錯 =====
MinidoracatUI.v1.API_REVISION = 12
dockSpec = nil
F.reset()
F.load("client/MinidoracatWatch_Client.lua")
check(MinidoracatWatchClient.docked == false and dockSpec == nil, "rev 12：不登記 Dock")
MinidoracatUI = nil
F.load("client/MinidoracatWatch_Client.lua")
check(MinidoracatWatchClient.docked == false, "沒有 UI 框架：照樣載入")

F.finish("test_watch_client")
