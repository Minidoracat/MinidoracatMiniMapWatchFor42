-- 地圖錶 Phase 9 畫面狀態（client/MinidoracatWatch_Hud.lua）：小地圖標題列（守衛、電量、警示、不需要電池、分割畫面、
-- 租約到期）、物品停留說明（地圖錶與模組的文字、快取、疊在其他 MOD 的說明下面、右鍵選單開著不畫、下游拋錯照拋）、
-- 重要事件 Toast（基準不報、低電量一次與重新武裝、60 秒不重報、沒電併熄燈、拿掉電池不報、充電與充飽、
-- 解鎖卡槽位失效、經濟系統的到期／扣款失敗／自動續租成功／面板自己付的不報、換錶重設基準）。
-- 用法（repo 根目錄）：lua scripts/test_watch_hud.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check = F.check
F.mode = "client"

function getCore() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
function getTextManager()
    return { MeasureStringX = function(_, _, s) return #s * 7 end, getFontHeight = function() return 16 end }
end
function getScriptManager()
    return { FindItem = function() return { getNormalTexture = function() return "tex" end } end }
end
ISMouseDrag = {}
ISContextMenu = { getNew = function() return {} end }
local UI = F.installUI(16)
UI.CAPABILITIES.focusLabel = true
local toasts = {}
UI.Toast.show = function(o) toasts[#toasts + 1] = { title = o.title, message = o.message } end

-- 原版 ISToolTipInv：render 畫框（drawRect＋drawRectBorder）再畫內容；另一個 MOD 在檔案頂層包一層、把自己的框畫在下面
local drawn
local Tip = {}
Tip.__index = Tip
function Tip:drawRect(x, y, w, h) drawn[#drawn + 1] = { "rect", y, h } end
function Tip:drawRectBorder(x, y, w, h) drawn[#drawn + 1] = { "border", y, h } end
function Tip:drawText(t, x, y) drawn[#drawn + 1] = { "text", y, t } end
ISToolTipInv = setmetatable({}, Tip)
ISToolTipInv.__index = ISToolTipInv
local vanillaDraws = true
function ISToolTipInv:render()
    if not vanillaDraws then return end -- 右鍵選單開著：原版整段跳過（ISToolTipInv.lua:45）
    self:drawRect(0, 0, self.width, 40)
    self:drawRectBorder(0, 0, self.width, 40)
end
local vanillaRender = ISToolTipInv.render
local otherBoom = false
function ISToolTipInv:render() -- 其他 MOD（像 SRJ）：先畫原版，再在框外畫自己的一塊、不回寫高度
    vanillaRender(self)
    if otherBoom then error("other mod failed") end
    if vanillaDraws then self:drawRect(0, 40, self.width, 20) end
end

require "MinidoracatWatch"
local W = MinidoracatWatchCore
local SB = SandboxVars.MinidoracatWatch
local alice = F.player("alice", 0)
local bob = F.player("bob", 1)
require "MinidoracatWatch_Client"
require "MinidoracatWatch_PayClient"
F.load("client/MinidoracatWatch_Panel.lua")
F.load("client/MinidoracatWatch_Hud.lua")
local C = MinidoracatWatchClient
local H = C.Hud
local P = C.Pay
local MOD = function(name) return "MinidoracatWatch.Module_" .. name end

local function wear(p, charge, ft)
    local w = p.inv:AddItem(ft or F.LEFT)
    if charge ~= nil then w:getModData()[W.KEY] = charge end
    F.wear(p, w)
    W.invalidate()
    return w
end
local function put(w, slotId, id, item)
    local md = w:getModData()
    md[W.SLOTS_KEY] = md[W.SLOTS_KEY] or {}
    md[W.SLOTS_KEY][slotId] = { id = id, item = MOD(item), md = {} }
    W.invalidate()
end
local function step(ms) F.now = F.now + (ms or 1000); P.views = {}; W.invalidate() end

-- ===== 標題列：守衛 =====
MinidoracatMiniMapAPI = nil
F.reset()
F.fire("OnGameStart")
local logged = false
for _, l in ipairs(F.logs) do if l:find("titleStatusApiVersion", 1, true) then logged = true end end
check(not H.titleActive and logged, "主 MOD 沒有標題列 API：不註冊、log 一次")
local reg = {}
MinidoracatMiniMapAPI = { titleStatusApiVersion = 1, registerTitleStatus = function(owner, fn) reg[owner] = fn; return true end }
H.registerTitle()
check(H.titleActive and reg[W.MOD_ID] == H.titleStatus, "titleStatusApiVersion 1：註冊")

-- ===== 標題列：狀態 =====
check(H.titleStatus(0) == nil, "沒戴錶：不顯示")
local wa = wear(alice, 0.8)
local t, st = H.titleStatus(0)
check(t == "IGUI_MinidoracatWatch_TitleBattery|80" and st == nil, "電量 80%：正常外觀")
wa:getModData()[W.KEY] = 0.15
t, st = H.titleStatus(0)
check(t == "IGUI_MinidoracatWatch_TitleBattery|15" and st == "warn", "低電量：警示")
wa:getModData()[W.KEY] = 0
check(H.titleStatus(0) == "IGUI_MinidoracatWatch_TitleDead", "沒電：沒電字樣")
wa:getModData()[W.KEY] = W.NO_BATTERY
t, st = H.titleStatus(0)
check(t == "IGUI_MinidoracatWatch_TitleNoBattery" and st == "warn", "沒有電池：警示")
SB.NeedBattery = false
check(H.titleStatus(0) == nil, "不需要電池：不顯示電量")
SB.NeedBattery = nil
local wb = wear(bob, 0.5)
check(H.titleStatus(1) == "IGUI_MinidoracatWatch_TitleBattery|50", "分割畫面：各自的錶（playerNum 1）")
SB.Enabled = false
check(H.titleStatus(1) == nil, "地圖錶系統關閉：不顯示")
SB.Enabled = nil

-- ===== 經濟系統（客戶端 facade 替身；擴充槽＝經濟系統）=====
local states = {}
MinidoracatEconomy = { v1 = { Client = { API_MAJOR = 1, API_REVISION = 3,
    CAPABILITIES = { entitlements = true, rentals = true }, Entitlements = {
        getState = function(_, pid) return states[pid] end,
        requestState = function() return 1 end,
        currencyName = function(id) return "cur:" .. id end,
    } } } }
local function rental(id, untilMs, extra)
    local r = { id = id, state = "active", paidUntil = untilMs, quantity = 1 }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end
local function econ(r, notice, perm)
    states.watch_ext = { ok = true, available = true, balances = { survivor = { available = 0 } },
        plan = { rentalEnabled = true, rentalPrice = 60, rentalCurrency = "survivor", rentalDays = 7, autoRenewAllowed = true },
        entitlement = { permanent = perm and 1 or 0, rentals = { r }, notice = notice } }
end
W.econStatus, SB.SlotExt = "READY", 3
W.clientPay.alice = {}
wa:getModData()[W.KEY] = 0.6
put(wa, "ext", "scan", "Scan")
econ(rental("r1", F.now - 1000, { state = "grace" }))
step()
t, st = H.titleStatus(0)
check(t == "IGUI_MinidoracatWatch_TitleLapsed|IGUI_MinidoracatWatch_TitleBattery|60" and st == "warn",
    "擴充槽租約到期、還裝著模組：電量後面接到期警示")
SB.NeedBattery = false
check(H.titleStatus(0) == "IGUI_MinidoracatWatch_TitleLapsedOnly", "不需要電池：只剩到期警示")
SB.NeedBattery = nil

-- ===== 物品停留說明：文字 =====
put(wa, "std1", "compass", "Compass")
W.clientPay.alice = { ext = true }
econ(rental("r1", F.now + 3 * 86400000))
SB.SlotCore, SB.SlotAdv = 2, 1 -- 核心槽＝解鎖卡、沒開；進階槽免費
step()
local lines = H.tipLines(alice, wa)
local function texts(ls) local o = {} for i, l in ipairs(ls) do o[i] = l[1] end return table.concat(o, "\n") end
local s = texts(lines)
check(lines[1][1] == "IGUI_MinidoracatWatch_Status_Charge|60|" .. C.timeText(0.6, C.fullRuntime(alice, wa))
    and lines[1][2] == false, "地圖錶：電量與大約還能用多久")
check(s:find("Tip_Modules|IGUI_MinidoracatWatch_Module_compassIGUI_MinidoracatWatch_ListSepIGUI_MinidoracatWatch_Tip_ModuleRent|IGUI_MinidoracatWatch_Module_scan", 1, true)
    ~= nil, "已裝模組：租用中的標註")
check(s:find("Tip_PaidSlot|IGUI_MinidoracatWatch_Slot_ext|IGUI_MinidoracatWatch_St_rent", 1, true)
    and s:find("Tip_PaidSlot|IGUI_MinidoracatWatch_Slot_core|IGUI_MinidoracatWatch_St_locked", 1, true)
    and not s:find("Slot_adv", 1, true), "付費槽位：租用中、未開啟；免費開放的不列")
check(H.tipLines(alice, wa) == lines, "250ms 內沿用同一份")
W.clientPay.alice = {}
econ(rental("r1", F.now - 1000, { state = "grace" }))
step(300)
s = texts(H.tipLines(alice, wa))
check(s:find("Tip_ModulePaused|IGUI_MinidoracatWatch_Module_scan", 1, true)
    and s:find("Slot_ext|IGUI_MinidoracatWatch_St_lapsed", 1, true), "租約到期：模組已停用、槽位租約到期")
econ(rental("r1", F.now + 86400000), nil, true)
W.clientPay.alice = { ext = true }
step(300)
s = texts(H.tipLines(alice, wa))
check(s:find("Slot_ext|IGUI_MinidoracatWatch_Tip_Bought", 1, true) and s:find("Module_scan、", 1, false) == nil
    and not s:find("ModuleRent", 1, true), "買斷：已買斷、模組不標租用中")
-- 七個模組：每列 3 項
for i, id in ipairs({ "std2", "std3", "adv" }) do put(wa, id, ({ "ledger", "gps", "mildetect" })[i], ({ "Ledger", "GPS", "MilDetect" })[i]) end
SB.SlotAdv = 1
step(300)
lines = H.tipLines(alice, wa)
check(lines[2][1]:find("^IGUI_MinidoracatWatch_Tip_Modules|") and lines[2][1]:find("ListSep$") and lines[3][1]:find("^    ") ~= nil,
    "模組多時分列：第一列帶標題、後面縮排")
-- 充電中
F.fire("OnServerCommand", W.MODULE, W.CMD_CHARGE, { to = "alice", kind = "car" })
step(300)
check(H.tipLines(alice, wa)[1][1]:find("^IGUI_MinidoracatWatch_Tip_ChargingCar|60|") ~= nil, "車上充電中：電量與大約多久充滿")
check(H.tipLines(alice, alice.inv:AddItem(F.LEFT))[1][1]:find("Status_Charge", 1, true) ~= nil, "沒戴著的那支不寫充電中")
F.fire("OnServerCommand", W.MODULE, W.CMD_CHARGE, { to = "alice", kind = nil })
wa:getModData()[W.KEY] = 0.1
step(300)
check(H.tipLines(alice, wa)[1][2] == true, "低電量：第一列用警示色")
SB.NeedBattery = false
step(300)
lines = H.tipLines(alice, wa)
check(lines[1][1] == "IGUI_MinidoracatWatch_Status_NoBatteryNeeded" and lines[1][2] == false, "不需要電池")
SB.NeedBattery = nil
-- 模組物品
local compass = alice.inv:AddItem(MOD("Compass"))
s = texts(H.tipLines(alice, compass))
check(s == "IGUI_MinidoracatWatch_KV_Class|IGUI_MinidoracatWatch_Class_standard\nIGUI_MinidoracatWatch_KV_Drain|IGUI_MinidoracatWatch_DrainPlus|10\n"
    .. "IGUI_MinidoracatWatch_Tip_Feature|IGUI_MinidoracatWatch_Feature_arrow", "模組：類別、耗電、功能")
check(#H.tipLines(alice, alice.inv:AddItem(MOD("Eco"))) == 2, "節能核心：沒有對應功能，不寫功能列")
check(H.tipLines(alice, alice.inv:AddItem("Base.Apple")) == nil, "其他物品：不加")
check(H.tipLines(alice, { getEnergy = function() end }) == nil, "不是物品（ISEnergyBar 的電力資源）：不碰")
SB.Enabled = false
step(300)
check(H.tipLines(alice, compass) == nil, "系統關閉：不加")
SB.Enabled = nil

-- ===== 物品停留說明：疊法 =====
F.fire("OnGameStart")
local tipObj = setmetatable({ width = 120, y = 300, item = compass, backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 },
    borderColor = { r = 1, g = 1, b = 1, a = 1 },
    tooltip = { getFont = function() return "S" end, getCharacter = function() return alice end } }, ISToolTipInv)
drawn = {}
step(300)
tipObj:render()
local ours = 0
for _, d in ipairs(drawn) do
    if d[1] == "rect" and d[2] == 59 then ours = ours + 1 end
end
check(drawn[1][2] == 0 and drawn[3][2] == 40 and ours == 1 and drawn[#drawn][1] == "text",
    "先畫原版與其他 MOD（框外那塊也量到），我們的框貼在最底下")
check(rawget(tipObj, "drawRect") == nil and rawget(tipObj, "drawRectBorder") == nil, "量測完拿掉實例上的攔截")
vanillaDraws = false
drawn = {}
tipObj:render()
check(#drawn == 0, "右鍵選單開著（下游沒畫）：不畫孤立的框")
vanillaDraws = true
tipObj.item = alice.inv:AddItem("Base.Apple")
drawn = {}
tipObj:render()
check(#drawn == 3, "不是地圖錶或模組：只有下游")
tipObj.item = compass
otherBoom = true
local ok, err = pcall(tipObj.render, tipObj)
check(not ok and tostring(err):find("other mod failed", 1, true) and rawget(tipObj, "drawRect") == nil,
    "下游拋錯：照拋、攔截已拿掉")
otherBoom = false

-- ===== Toast =====
local function said(fragment)
    for _, x in ipairs(toasts) do
        if (x.title or ""):find(fragment, 1, true) or x.message:find(fragment, 1, true) then return true end
    end
    return false
end
SB.SlotExt, SB.SlotAdv, SB.SlotCore = 1, 1, 1
local w2 = wear(alice, 0.25)
H.state = {}
toasts = {}
H.check(0, alice, F.now)
check(#toasts == 0, "第一次看到（換錶、上線）：只記基準")
w2:getModData()[W.KEY] = 0.19
step()
H.check(0, alice, F.now)
check(#toasts == 1 and toasts[1].title == "IGUI_MinidoracatWatch_Toast_Low|19"
    and toasts[1].message:find("^IGUI_MinidoracatWatch_Toast_Low_msg|"), "跨過低電量門檻：提示一次")
w2:getModData()[W.KEY] = 0.18
step()
H.check(0, alice, F.now)
check(#toasts == 1, "一直在門檻下：不再報")
w2:getModData()[W.KEY] = 0.22
step(61000) -- 過了 60 秒不重報的窗口：這裡只靠門檻＋5% 擋
H.check(0, alice, F.now)
w2:getModData()[W.KEY] = 0.19
step()
H.check(0, alice, F.now)
check(#toasts == 1, "門檻上下跳（沒回到門檻＋5%）：不重新武裝")
w2:getModData()[W.KEY] = 0.3
step()
H.check(0, alice, F.now)
w2:getModData()[W.KEY] = 0.19
step()
H.check(0, alice, F.now)
check(#toasts == 2, "回到門檻＋5% 以上再跨下來：再提示一次")
w2:getModData()[W.KEY] = 0.3
step()
H.check(0, alice, F.now)
w2:getModData()[W.KEY] = 0.19
step()
H.check(0, alice, F.now)
check(#toasts == 2, "60 秒內又跨下來：不重報")
-- 沒電＋燈同時熄
local lamp = alice.inv:AddItem(W.LIGHT_TYPE)
lamp.activated = true
w2:getModData()[W.KEY] = 0.01
step()
H.check(0, alice, F.now)
alice.inv:DoRemoveItem(lamp)
w2:getModData()[W.KEY] = 0
step(2000)
H.check(0, alice, F.now)
check(#toasts == 3 and toasts[3].title == "IGUI_MinidoracatWatch_Toast_Dead"
    and toasts[3].message == "IGUI_MinidoracatWatch_Toast_Dead_light|IGUI_MinidoracatWatch_Toast_Dead_msg",
    "沒電：一則，燈剛熄就併在同一則")
step()
H.check(0, alice, F.now)
check(#toasts == 3, "沒電只報一次")
w2:getModData()[W.KEY] = 0.5
step()
H.check(0, alice, F.now)
w2:getModData()[W.KEY] = W.NO_BATTERY
step()
H.check(0, alice, F.now)
check(#toasts == 3, "裝電池、拿掉電池：不報")
-- 充電與充飽
w2:getModData()[W.KEY] = 0.9
step()
H.check(0, alice, F.now)
F.fire("OnServerCommand", W.MODULE, W.CMD_CHARGE, { to = "alice", kind = "car" })
step()
H.check(0, alice, F.now)
check(#toasts == 4 and toasts[4].title == "IGUI_MinidoracatWatch_Toast_Charging"
    and toasts[4].message == "IGUI_MinidoracatWatch_Toast_Charging_car", "開始充電（車上）")
w2:getModData()[W.KEY] = 1
step()
H.check(0, alice, F.now)
check(#toasts == 5 and toasts[5].title == "IGUI_MinidoracatWatch_Toast_Full", "充飽")
F.fire("OnServerCommand", W.MODULE, W.CMD_CHARGE, { to = "alice", kind = nil })
w2:getModData()[W.KEY] = 0.9
step()
H.check(0, alice, F.now)
F.fire("OnServerCommand", W.MODULE, W.CMD_CHARGE, { to = "alice", kind = "car" })
step()
H.check(0, alice, F.now)
check(#toasts == 5, "60 秒內再發動：不重報開始充電")
F.fire("OnServerCommand", W.MODULE, W.CMD_CHARGE, { to = "alice", kind = nil })
-- 解鎖卡槽位失效
SB.SlotExt = 2
W.clientUnlocks.alice = { ext = true }
put(w2, "ext", "scan", "Scan")
step()
H.check(0, alice, F.now)
W.clientUnlocks.alice = {}
step()
H.check(0, alice, F.now)
check(#toasts == 6 and toasts[6].title == "IGUI_MinidoracatWatch_Toast_Paused|IGUI_MinidoracatWatch_Module_scan"
    and toasts[6].message == "IGUI_MinidoracatWatch_Toast_Paused_msg|IGUI_MinidoracatWatch_Slot_ext", "槽位失效：模組停用")
-- 經濟系統：到期、扣款失敗、自動續租成功、面板自己付的不報
SB.SlotExt = 3
W.clientPay.alice = { ext = true }
local due = F.now + 5000
econ(rental("r1", due, { autoRenew = true }))
step()
H.check(0, alice, F.now)
check(#toasts == 6, "租用中：只記基準")
W.clientPay.alice = {}
econ(rental("r1", due, { autoRenew = true, state = "grace" }))
step(6000)
H.check(0, alice, F.now)
check(#toasts == 7 and toasts[7].title == "IGUI_MinidoracatWatch_Toast_Lapsed|IGUI_MinidoracatWatch_Slot_ext"
    and toasts[7].message == "IGUI_MinidoracatWatch_Toast_Lapsed_msg|IGUI_MinidoracatWatch_Module_scan",
    "租約到期：一則，模組停用（不再另報一般的模組停用）")
econ(rental("r1", due, { autoRenew = true, state = "grace", graceUntil = F.now + 3600000 }), { code = "renewal_failed", error = "insufficient_funds" })
step()
H.check(0, alice, F.now)
check(#toasts == 8 and toasts[8].title == "IGUI_MinidoracatWatch_Toast_RenewFailed|IGUI_MinidoracatWatch_Slot_ext"
    and toasts[8].message:find("^IGUI_MinidoracatWatch_PayFailFunds|cur:survivor|60") and toasts[8].message:find("PayRetryWindow", 1, true),
    "自動續租沒扣到款：原因與重試期限")
step()
H.check(0, alice, F.now)
check(#toasts == 8, "同一次失敗不重報")
local later = F.now + 7 * 86400000
econ(rental("r1", later, { autoRenew = true }))
step()
H.check(0, alice, F.now)
check(#toasts == 8, "租約先延長、伺服器還沒推有效：先不報")
W.clientPay.alice = { ext = true }
step()
H.check(0, alice, F.now)
check(#toasts == 9 and toasts[9].title == "IGUI_MinidoracatWatch_Toast_Renewed|IGUI_MinidoracatWatch_Slot_ext",
    "槽位恢復：續租成功")
step(61000)
P.paidAt.watch_ext = F.now
econ(rental("r1", later + 7 * 86400000, { autoRenew = true }))
step()
H.check(0, alice, F.now)
check(#toasts == 9, "面板自己付的續租：不報（檢視區已經說了）")
step(61000)
P.paidAt.watch_ext = F.now - 15000
econ(rental("r1", later + 14 * 86400000, { autoRenew = true }))
step()
H.check(0, alice, F.now)
check(#toasts == 10 and toasts[10].title == "IGUI_MinidoracatWatch_Toast_Renewed|IGUI_MinidoracatWatch_Slot_ext",
    "面板付款 10 秒以後的延長＝自動續租：照常報")
-- 管理員縮短租期後再自動續租：從縮短後的期限算延長
step(61000)
econ(rental("r1", F.now + 15000, { autoRenew = true }))
step()
H.check(0, alice, F.now)
econ(rental("r1", F.now + 15000 + 7 * 86400000, { autoRenew = true }))
step()
H.check(0, alice, F.now)
check(#toasts == 11, "縮短後再延長：報續租成功")
-- 到期那一步就沒扣到款：併成一則
step(61000)
W.clientPay.alice = {}
econ(rental("r1", F.now, { autoRenew = true, state = "grace", graceUntil = F.now + 3600000 }), { code = "renewal_failed", error = "other" })
step()
H.check(0, alice, F.now)
check(#toasts == 12 and toasts[12].message:find("^IGUI_MinidoracatWatch_PayFailOther") ~= nil,
    "到期當下扣款失敗：到期與失敗併成一則")
-- 續租成功＝這段租約事件結束：之後再到期是新的一件事，60 秒內也照報
-- （1006s watch-econ-mp：續租後 43 秒再到期且沒扣到款，被當成重複的到期，什麼都沒報）
W.clientPay.alice = { ext = true }
econ(rental("r1", F.now + 7 * 86400000, { autoRenew = true }))
step()
H.check(0, alice, F.now)
check(#toasts == 13 and toasts[13].title == "IGUI_MinidoracatWatch_Toast_Renewed|IGUI_MinidoracatWatch_Slot_ext", "補到款：續租成功")
W.clientPay.alice = {}
econ(rental("r1", F.now, { autoRenew = true, state = "grace", graceUntil = F.now + 3600000 }),
    { code = "renewal_failed", error = "insufficient_funds" })
step()
H.check(0, alice, F.now)
check(#toasts == 14 and toasts[14].title == "IGUI_MinidoracatWatch_Toast_Lapsed|IGUI_MinidoracatWatch_Slot_ext"
    and toasts[14].message:find("^IGUI_MinidoracatWatch_PayFailFunds") ~= nil, "續租後 60 秒內再到期：照報到期與原因")
-- 換錶：重設基準
wear(alice, 0)
step()
H.check(0, alice, F.now)
check(#toasts == 14, "換一支沒電的錶：基準，不報")

-- ===== 管理員視窗：到經濟中心上架（Economy 客戶端 rev 4＋shopAdd）=====
F.load("client/MinidoracatWatch_AdminUI.lua")
local AU = MinidoracatWatchAdminUI
MinidoracatEconomy = nil
local api, why = AU.shopApi()
check(api == nil and why == "ShopNoEcon", "沒裝 Economy：沒有偵測到")
local shopCalls, shopReply = {}, { true }
local CL = { API_MAJOR = 1, API_REVISION = 3, CAPABILITIES = { shopAdd = true },
    openAdminShop = function(src, items) shopCalls[#shopCalls + 1] = { src = src, items = items }; return shopReply[1], shopReply[2] end }
MinidoracatEconomy = { v1 = { Client = CL } }
api, why = AU.shopApi()
check(api == nil and why == "ShopOldEcon", "rev 3：需要更新 Economy")
CL.API_REVISION, CL.CAPABILITIES.shopAdd = 4, nil
check(select(2, AU.shopApi()) == "ShopOldEcon", "rev 4 但沒有 shopAdd：需要更新")
CL.CAPABILITIES.shopAdd, CL.API_MAJOR = true, 2
check(select(2, AU.shopApi()) == "ShopOldEcon", "API_MAJOR 不是 1：不呼叫")
CL.API_MAJOR = 1
check(AU.shopApi() == CL, "rev 4＋shopAdd：可以上架")
local items = AU.shopItems()
local want = { [W.BATTERY_TYPE] = true }
for _, st in ipairs(W.STYLES) do want[W.watchType(st)] = true end
for _, b in ipairs({ "Compass", "Ledger", "GPS", "Comm", "Scan", "Detect", "MilDetect", "LongComm", "Relay", "Eco", "Light" }) do
    want[MOD(b)] = true
end
local all = #items == 19
for _, t in ipairs(items) do all = all and want[t] == true and not t:find("UnlockCard", 1, true) and not t:find("_Right", 1, true) end
check(all, "上架清單：七款地圖錶（左手款）、十一個模組（含照明）、電池；沒有解鎖卡")
F.reset()
AU.openShop({ player = alice })
check(#shopCalls == 1 and shopCalls[1].src == W.MOD_ID and #shopCalls[1].items == 19 and #F.halos == 0, "按下：交給 Economy、成功不提示")
shopReply = { false, "forbidden" }
AU.openShop({ player = alice })
check(F.halos[1] and F.halos[1].text == "IGUI_MinidoracatWatch_Admin_ShopForbidden", "沒有經濟中心的管理權限：提示")
shopReply = { false, "unavailable" }
F.reset()
AU.openShop({ player = alice })
check(F.halos[1] and F.halos[1].text == "IGUI_MinidoracatWatch_Admin_ShopFailed", "其他失敗：開不了商店頁")
CL.openAdminShop = function() error("boom") end
F.reset()
AU.openShop({ player = alice })
check(F.halos[1] and F.halos[1].text == "IGUI_MinidoracatWatch_Admin_ShopFailed", "facade 拋錯：不炸、提示")

-- 頁尾的「不合法」「沒有修改」是上次按套用的結果：欄位改好、有了修改就清掉（AU.refresh 每次用 liveMsg 重算）
-- （1006r 截圖：滿電時數改回合法後，紅字一直留到確認框都還在）
local AM = MinidoracatWatchAdminModel
local b = AM.readBase({ rev = 1, zombieDrops = W.defaultDrops(), moduleDrains = {}, addonSlots = {} })
local S = { bad = { tf = true }, base = b, draft = AM.copy(b), msg = AM.T("Invalid") }
check(AU.liveMsg(S) == AM.T("Invalid"), "還有不合法欄位：訊息留著")
S.bad = {}
check(AU.liveMsg(S) == nil, "欄位改好：不合法訊息清掉")
S.msg = AM.T("NoChanges")
check(AU.liveMsg(S) == AM.T("NoChanges"), "還是沒有修改：訊息留著")
S.draft.sb.CarHours = S.draft.sb.CarHours + 1
check(AU.liveMsg(S) == nil, "有了修改：沒有修改的訊息清掉")
S.msg = AM.T("Conflict")
check(AU.liveMsg(S) == AM.T("Conflict"), "其他結果訊息照留")

F.finish("test_watch_hud")
