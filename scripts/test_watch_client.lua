-- 地圖錶客戶端：主 MOD 版本守衛、小地圖閘門（快取、零配置、事件失效）、Dock、換電池請求、伺服器失敗回報、右鍵選單。
-- 用法（repo 根目錄）：lua scripts/test_watch_client.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check = F.check
F.mode = "client"

-- ===== 客戶端 UI 假物件 =====
UIFont = { Small = "S", Medium = "M" }
function getCore() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
function getTextManager() return { MeasureStringX = function(_, _, s) return #s * 7 end, getFontHeight = function() return 16 end } end
F.draws = 0
local Element = {}
function Element:drawText() F.draws = F.draws + 1 end
function Element:drawRect() F.draws = F.draws + 1 end
function Element:drawRectBorder() F.draws = F.draws + 1 end
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
function ISPanel:addChild(c) self.children = self.children or {}; table.insert(self.children, c) end
function ISPanel:addToUIManager() self.inUI = true; F.lastPanel = self; if self.createChildren then self:createChildren() end end
function ISPanel:removeFromUIManager() self.inUI = false end
ISButton = {}
function ISButton:new(x, y, w, h, title, target, onclick)
    return { title = title, target = target, onclick = onclick, enabled = true, initialise = function() end,
        setTitle = function(b, t) b.title = t end, setEnable = function(b, e) b.enabled = e end }
end

local dockSpec
MinidoracatUI = { v1 = { API_MAJOR = 1, API_REVISION = 13, CAPABILITIES = { dock = true },
    Dock = { register = function(spec) dockSpec = spec; return true end } } }

require "MinidoracatWatch"
local W = MinidoracatWatchCore
local p = F.player("alice", 0)
F.load("client/MinidoracatWatch_Client.lua")
local C = MinidoracatWatchClient

-- ===== 版本守衛 =====
F.reset()
MinidoracatMiniMapAPI = nil
F.fire("OnGameStart")
check(C.gateActive == false, "主 MOD 沒有 API：不設閘")
check(#F.logs == 1 and F.logs[1]:find("featureApiVersion", 1, true) ~= nil, "log 一次")
F.admin = false
F.fire("OnTick")
check(#F.halos == 0, "一般玩家不提示")
F.fire("OnTick")
check(#F.halos == 0, "提示只排一次（第一個 tick 後移除）")

F.reset()
F.admin = true
MinidoracatMiniMapAPI = { featureApiVersion = 0, registerFeatureGate = function() error("should not be called") end }
C.registerGate()
F.fire("OnTick")
check(C.gateActive == false and #F.halos == 1 and F.halos[1].text == "IGUI_MinidoracatWatch_ApiMissing",
    "版本太舊：不呼叫、管理員收到提示")

F.reset()
MinidoracatMiniMapAPI = { featureApiVersion = 1, registerFeatureGate = function() error("boom") end }
C.registerGate()
F.fire("OnTick")
check(C.gateActive == false and #F.halos == 1, "主 MOD 註冊拋錯也不 crash，照樣提示管理員")

local registered = {}
MinidoracatMiniMapAPI = { featureApiVersion = 2, registerFeatureGate = function(owner, fn)
    registered.owner, registered.fn = owner, fn; return true end }
F.reset()
C.registerGate()
F.fire("OnTick")
check(C.gateActive == true and registered.owner == W.MOD_ID and registered.fn == C.gate, "featureApiVersion >= 1 才註冊")
check(#F.halos == 0 and #F.logs == 0, "註冊成功不提示")

-- ===== 閘門 =====
local gate = registered.fn
local ok, reason = gate(0, "minimap", nil)
check(ok == false and reason == W.REASON_NO_WATCH, "沒戴錶：擋，原因＝沒戴錶")
for _, feat in ipairs({ "arrow", "poi", "nav", "share", "scan", "zombie" }) do
    check(gate(0, feat, "mini") == true, "其他 feature 放行：" .. feat)
end
local watch = F.item(F.RIGHT)
p.inv:AddItem(watch)
F.wear(p, watch)
F.fire("OnClothingUpdated", p)
check(gate(0, "minimap", "mini") == true, "穿戴事件後立刻生效：全新的錶放行")
W.setCharge(watch, W.NO_BATTERY)
ok, reason = gate(0, "minimap")
check(ok == false and reason == W.REASON_NO_BATTERY, "沒有電池：擋")
W.setCharge(watch, 0)
ok, reason = gate(0, "minimap")
check(ok == false and reason == W.REASON_DEAD, "沒電：擋")
SandboxVars.MinidoracatWatch.Enabled = false
check(gate(0, "minimap") == true, "總開關關閉：放行")
SandboxVars.MinidoracatWatch.Enabled = true
SandboxVars.MinidoracatWatch.MinimapRule = 1
check(gate(0, "minimap") == true, "規則 free：放行")
SandboxVars.MinidoracatWatch.MinimapRule = 3
ok, reason = gate(0, "minimap")
check(ok == false and reason == W.REASON_OFF, "規則 off：擋")
SandboxVars.MinidoracatWatch.MinimapRule = 2
W.setCharge(watch, 0.5)

-- 熱路徑：快取期內不翻穿戴清單、不配置 table
local scans = 0
local realWorn = p.getWornItems
p.getWornItems = function(self) scans = scans + 1; return realWorn(self) end
gate(0, "minimap")
scans = 0
collectgarbage("collect")
collectgarbage("stop")
local kb = collectgarbage("count")
for _ = 1, 20000 do gate(0, "minimap", "mini") end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
check(scans == 0, "快取期內不翻穿戴清單")
check(grew < 1, "20000 次呼叫不配置記憶體（增加 " .. string.format("%.2f", grew) .. " KB）")
p.getWornItems = nil

-- 沒收到事件時，1 秒保險期限後也會看到變化
F.unwear(p, watch)
check(gate(0, "minimap") == true, "期限內沿用快取")
F.now = F.now + 1000
check(gate(0, "minimap") == false, "期限到重新讀取")

-- 兩支都戴：提示一次、左腕那支生效
local left = F.item(F.LEFT)
p.inv:AddItem(left)
F.wear(p, watch)
F.wear(p, left)
W.setCharge(left, 0)
F.reset()
F.fire("OnClothingUpdated", p)
ok, reason = gate(0, "minimap")
check(ok == false and reason == W.REASON_DEAD, "兩支都戴：看左腕那支（沒電）")
F.fire("OnClothingUpdated", p)
gate(0, "minimap")
check(#F.halos == 1 and F.halos[1].text == "IGUI_MinidoracatWatch_TwoWorn", "兩支都戴只提示一次")
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
W.setCharge(watch, W.NO_BATTERY)
check(dockSpec.getBadge() == -1, "沒電池：紅點")
W.setCharge(watch, 0.5)
check(dockSpec.getStatus() == "IGUI_MinidoracatWatch_Status_Charge|50|IGUI_MinidoracatWatch_TimeDaysHours|1|12",
    "停留說明：電量與剩餘時間")
F.draws = 0
dockSpec.drawIcon(setmetatable({}, { __index = Element }), 0, 0, 28)
check(F.draws >= 3, "drawIcon 畫出電池")
check(dockSpec.isActive() == false, "面板未開")
dockSpec.onClick()
check(dockSpec.isActive() == true, "點按鈕開面板")
dockSpec.onClick()
check(dockSpec.isActive() == false, "再點關閉")

-- ===== 換電池請求（MP 客戶端只送純量）=====
local weak, strong = F.item("Base.Battery"), F.item("Base.Battery")
weak:setCurrentUsesFloat(0.2)
strong:setCurrentUsesFloat(0.9)
p.inv:AddItem(weak)
F.bag(p.inv):AddItem(strong)
F.reset()
C.requestBattery(p, watch, true)
local cmd = F.clientCmds[1]
check(cmd and cmd.module == W.MODULE and cmd.command == W.CMD_BATTERY, "送出換電池指令")
check(cmd.args.watchId == watch.id and cmd.args.install == true and cmd.args.batteryId == strong.id, "挑電量最高的電池")
local scalars = true
for _, v in pairs(cmd.args) do if type(v) ~= "number" and type(v) ~= "boolean" then scalars = false end end
check(scalars, "payload 只有純量")
check(W.charge(watch) == 0.5, "客戶端不自己改電量")

-- 面板：按鈕狀態、繪製、按下
C.openPanel(0, watch)
local panel = F.lastPanel
check(C.isPanelOpen() and panel.inUI, "右鍵開啟面板")
panel:update()
F.draws = 0
panel:prerender()
check(F.draws >= 4, "面板畫出標題、電量與狀態")
check(panel.btnInsert.enabled and panel.btnRemove.enabled and panel.btnInsert.title == "IGUI_MinidoracatWatch_ReplaceBattery",
    "有電池、背包有備用電池：兩顆按鈕都可按")
F.reset()
panel.btnRemove.onclick(panel)
check(F.clientCmds[1] and F.clientCmds[1].args.install == false, "面板取出電池送指令")
W.setCharge(watch, W.NO_BATTERY)
panel:update()
check(not panel.btnRemove.enabled and panel.btnInsert.title == "IGUI_MinidoracatWatch_InsertBattery", "沒電池：只能裝入")
W.setCharge(watch, 0.5)
p.inv:DoRemoveItem(watch)
F.unwear(p, watch)
F.fire("OnClothingUpdated", p)
panel:update()
panel:prerender()
check(not panel.btnInsert.enabled and not panel.btnRemove.enabled, "錶離開身上：按鈕停用、不出錯")
p.inv:AddItem(watch)
F.wear(p, watch)
F.fire("OnClothingUpdated", p)
C.closePanel()
check(not C.isPanelOpen() and not panel.inUI, "關閉面板")

-- ===== 伺服器失敗回報 =====
F.reset()
F.fire("OnServerCommand", W.MODULE, W.CMD_FAILED, { reason = W.FAIL_NO_BATTERY, to = "alice" })
check(#F.halos == 1 and F.halos[1].player == p and F.halos[1].text == W.FAIL_NO_BATTERY, "白名單原因：提示對的玩家")
F.now = F.now + 2000
F.fire("OnServerCommand", W.MODULE, W.CMD_FAILED, { reason = "IGUI_Anything_Else", to = "alice" })
F.fire("OnServerCommand", W.MODULE, W.CMD_FAILED, { reason = W.FAIL_GENERIC, to = "bob" })
check(#F.halos == 1, "未知原因與別人的回報都忽略")

-- ===== 右鍵選單 =====
local function menu(items)
    local opts = {}
    local ctx = { addOption = function(_, name, target, fn, a, b) opts[#opts + 1] = { name = name, target = target, fn = fn, a = a, b = b } end }
    F.fire("OnFillInventoryObjectContextMenu", 0, ctx, items)
    return opts
end
local opts = menu({ { items = { watch, watch } } })
check(#opts == 3 and opts[1].name == "IGUI_MinidoracatWatch_Open", "錶的右鍵：開啟／更換／取出")
check(opts[2].name == "IGUI_MinidoracatWatch_ReplaceBattery" and opts[3].name == "IGUI_MinidoracatWatch_RemoveBattery",
    "有電池時顯示更換與取出")
F.reset()
opts[3].fn(opts[3].target, opts[3].a, opts[3].b)
check(F.clientCmds[1] and F.clientCmds[1].args.install == false and F.clientCmds[1].args.batteryId == nil, "取出電池指令")
local floorWatch = F.item(F.LEFT)
check(#menu({ floorWatch }) == 0, "不在身上的錶不加選項")
check(#menu({ F.item("Base.Battery") }) == 0, "非錶物品不加選項")

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
