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

-- 模組說明接上伺服器設定的範圍（和閘門、分享過濾讀同一份沙盒，不寫死）或這台伺服器的處境；
-- 面板檢視區每幀都畫，同一個模組 250ms 內沿用同一份文字
local function later() F.now = F.now + 300 end
check(C.moduleDesc("comm") == "IGUI_MinidoracatWatch_ShareRange|IGUI_MinidoracatWatch_ModuleDesc_comm|2000"
    and C.moduleDesc("longcomm") == "IGUI_MinidoracatWatch_ShareRange|IGUI_MinidoracatWatch_ModuleDesc_longcomm|8000",
    "預設：通訊 2000、長距 8000")
check(C.moduleDesc("detect") == "IGUI_MinidoracatWatch_ModuleRange|IGUI_MinidoracatWatch_ModuleDesc_detect|40"
    and C.moduleDesc("mildetect") == "IGUI_MinidoracatWatch_ModuleRange|IGUI_MinidoracatWatch_ModuleDesc_mildetect|80"
    and C.moduleDesc("scan") == "IGUI_MinidoracatWatch_ModuleRange|IGUI_MinidoracatWatch_ModuleDesc_scan|60",
    "預設：偵測 40、軍規偵測 80、掃描 60")
SB.CommRange, SB.LongCommRange, SB.DetectRadius, SB.MilDetectRadius = 1234, 30000, 60, 70
check(C.moduleDesc("detect"):find("|40", 1, true), "250ms 內沿用同一份文字")
later()
check(C.moduleDesc("comm"):find("|1234", 1, true) and C.moduleDesc("longcomm"):find("|30000", 1, true)
    and C.moduleDesc("detect"):find("|60", 1, true) and C.moduleDesc("mildetect"):find("|70", 1, true),
    "說明的範圍跟著沙盒改（軍規偵測不再寫死成偵測的兩倍）")
SB.CommRange, SB.LongCommRange, SB.DetectRadius, SB.MilDetectRadius = nil, nil, nil, nil
later()
check(C.moduleDesc("relay") == "IGUI_MinidoracatWatch_ShareRangeUnlimited|IGUI_MinidoracatWatch_ModuleDesc_relay",
    "中繼核心：不限距離")
check(C.moduleDesc("gps") == "IGUI_MinidoracatWatch_ModuleDesc_gps" and C.moduleDesc("eco") == "IGUI_MinidoracatWatch_ModuleDesc_eco"
    and C.moduleDesc("light") == "IGUI_MinidoracatWatch_ModuleDesc_light|4", "沒有範圍的模組只有說明；照明的半徑本來就在說明裡")
SB.RuleShare, SB.RuleZombie, SB.RuleLight = 2, 4, 2
later()
check(C.moduleDesc("comm") == "IGUI_MinidoracatWatch_ModuleNotNeeded|IGUI_MinidoracatWatch_ModuleDesc_comm|IGUI_MinidoracatWatch_Feature_share",
    "陣營分享是「戴錶就能用」：不寫距離，註明不裝模組也能用")
check(C.moduleDesc("detect") == "IGUI_MinidoracatWatch_ModuleRuleOff|IGUI_MinidoracatWatch_ModuleDesc_detect|IGUI_MinidoracatWatch_Feature_zombie"
    and C.moduleDesc("light"):find("IGUI_MinidoracatWatch_ModuleRuleOff|", 1, true) == 1, "功能關閉：註明沒有作用、不耗電")
SB.RuleShare, SB.RuleZombie, SB.RuleLight = nil, nil, nil
local gateApi = MinidoracatMiniMapAPI
MinidoracatMiniMapAPI = { featureApiVersion = 2, featureServerOff = function(f) return f == "scan" end }
later()
check(C.moduleDesc("scan") == "IGUI_MinidoracatWatch_ModuleServerOff|IGUI_MinidoracatWatch_ModuleDesc_scan|IGUI_MinidoracatWatch_Feature_scan"
    and C.moduleDesc("detect"):find("IGUI_MinidoracatWatch_ModuleRange|", 1, true) == 1,
    "小地圖設定沒開放掃描：註明裝了也看不到；其他照舊")
MinidoracatMiniMapAPI = gateApi
later()

-- 耗電照伺服器現在的設定（和 W.drainFactor 同一套：功能關閉的模組不計、不需要電池時整支錶不耗電）
local function drainOf(id) return C.drainText(W.modules[id]) end
check(drainOf("detect") == "IGUI_MinidoracatWatch_DrainPlus|50" and drainOf("eco") == "IGUI_MinidoracatWatch_DrainHalf"
    and drainOf("light") == "IGUI_MinidoracatWatch_DrainLight|100", "預設：偵測 +50%、節能核心減半、照明開燈時 +100%")
SB.RuleZombie, SB.RuleLight = 4, 2
check(drainOf("detect") == "IGUI_MinidoracatWatch_DrainNone" and drainOf("mildetect") == "IGUI_MinidoracatWatch_DrainNone"
    and drainOf("light") == "IGUI_MinidoracatWatch_DrainNone" and drainOf("scan") == "IGUI_MinidoracatWatch_DrainPlus|25",
    "功能關閉：那幾個模組寫不耗電，其他照舊")
SB.RuleZombie, SB.RuleLight = nil, nil
SB.NeedBattery = false
check(drainOf("scan") == "IGUI_MinidoracatWatch_DrainNoBattery" and drainOf("eco") == "IGUI_MinidoracatWatch_DrainNoBattery",
    "不需要電池：每個模組都寫不耗電")
check(drainOf("weight1") == "IGUI_MinidoracatWatch_DrainNoBattery", "不需要電池：負重核心也不耗電")
SB.NeedBattery = nil
SB.DrainWeight1 = 150
check(drainOf("weight1") == "IGUI_MinidoracatWatch_DrainPlus|150" and drainOf("weight3") == "IGUI_MinidoracatWatch_DrainPlus|300",
    "負重核心耗電照沙盒（I 改成 150%、III 預設 300%）")
SB.WeightEnabled = false
check(drainOf("weight1") == "IGUI_MinidoracatWatch_DrainNone" and drainOf("weight3") == "IGUI_MinidoracatWatch_DrainNone"
    and drainOf("scan") == "IGUI_MinidoracatWatch_DrainPlus|25", "負重核心整個關閉：寫不耗電（W.moduleOff），其他模組照舊")
SB.WeightEnabled, SB.DrainWeight1 = nil, nil

-- 缺模組時的取得方式：只用客戶端有的沙盒值與 shared 的戰利品表（殭屍掉落不公開）
F.load("shared/MinidoracatWatch_Recipe.lua")
local function acquire(id)
    local t = C.acquireLines(id)
    return t and table.concat(t, "\n")
end
local LOOT, SEP, PLACE = "IGUI_MinidoracatWatch_Acquire_Loot|", "IGUI_MinidoracatWatch_ListSep", "IGUI_MinidoracatWatch_LootPlace_"
check(acquire("ledger") == LOOT .. PLACE .. "ElectronicStoreMisc" .. SEP .. PLACE .. "CrateElectronics\n"
    .. "IGUI_MinidoracatWatch_Acquire_Craft|3", "名錄模組：電器行、倉庫的電子用品箱；可以製作（電學 3）")
check(acquire("gps") == LOOT .. PLACE .. "ElectronicStoreMisc" .. SEP .. PLACE .. "ArmyStorageElectronics",
    "定位模組：沒有配方，只寫地點")
SB.LootModules, SB.CraftLevel = false, 0
check(acquire("ledger") == "IGUI_MinidoracatWatch_Acquire_CraftAny" and acquire("gps") == nil,
    "模組不出現在容器：只剩製作（電學 0＝不需要技能）；兩樣都沒有就不寫")
SB.LootModules, SB.CraftLevel, SB.AllowCraft = nil, nil, false
check(acquire("comm") == LOOT .. PLACE .. "ElectronicStoreMisc" .. SEP .. PLACE .. "PoliceLockers", "關閉製作：不寫可以製作")
SB.AllowCraft = nil
-- 負重核心：每顆自己的戰利品開關（LootWeight1..3，預設關、不看 LootModules）
local function lootOf(id) return ((acquire(id) or ""):match("Acquire_Loot|([^\n]*)")) end
check(lootOf("weight1") == nil and lootOf("weight3") == nil and lootOf("gps") ~= nil,
    "負重核心的戰利品開關預設關：不寫地點；其他模組照舊")
SB.LootWeight1 = true
check(lootOf("weight1") == PLACE .. "ArmyStorageElectronics" and lootOf("weight2") == nil, "打開負重核心 I：只寫它的地點")
SB.LootModules = false
check(lootOf("weight1") ~= nil and lootOf("gps") == nil, "關掉模組戰利品：負重核心 I 照自己的開關，其他模組不寫")
SB.LootModules, SB.LootWeight1 = nil, nil

-- ===== 取得方式總覽（2026-10-15）：開放程度三段；殭屍規則與逐項倍率只讀伺服器推來、已裁切的清單（W.clientLists）=====
do
local ZOMBIE, GROUP = "IGUI_MinidoracatWatch_Acquire_Zombie|", "IGUI_MinidoracatWatch_Admin_Group_"
SB.AcquireGuide = 1
check(acquire("ledger") == nil and C.acquireInfo(MOD("Ledger")) == nil, "開放程度 1：面板說明與取得方式都沒有")
SB.AcquireGuide = nil
W.clientLists.drops = { { group = "police", item = "mod:comm", chance = 2 }, { group = "worker", item = "mod:any", chance = 2 },
    { group = "custom", item = "mod:comm" } }
check(acquire("comm") == LOOT .. PLACE .. "ElectronicStoreMisc" .. SEP .. PLACE .. "PoliceLockers\n" .. ZOMBIE .. GROUP .. "police"
    .. SEP .. GROUP .. "worker" .. SEP .. "IGUI_MinidoracatWatch_Guide_GroupCustom\nIGUI_MinidoracatWatch_Acquire_Craft|3",
    "開放程度 2：說明多一句哪些殭屍會帶（自訂服裝寫成「穿特定服裝的殭屍」）")
local ginfo = C.acquireInfo(MOD("Comm"))
check(ginfo.drops[1].pct == nil and ginfo.drops[2].random == true and ginfo.drops[1].random == false
    and ginfo.loot[1].tier == nil and ginfo.dropCap == nil, "開放程度 2：清單裡就算有機率也不寫，容器不寫稀有度")
check(not (acquire("eco") or ""):find("Acquire_Zombie", 1, true), "隨機一般模組不含核心：節能核心不寫殭屍")
SB.AcquireGuide = 3
W.clientLists.dropCap = 1
ginfo = C.acquireInfo(MOD("Comm"))
check(ginfo.drops[1].pct == 2 and F.near(ginfo.drops[2].pct, 2 / 6) and ginfo.drops[3].pct == nil
    and ginfo.loot[1].tier == "uncommon" and ginfo.loot[2].tier == "uncommon" and ginfo.dropCap == 1,
    "開放程度 3：每隻的機率（隨機一般模組平分成六份）、容器寫稀有度、每隻上限")
local eco = C.acquireInfo(MOD("Eco"))
check(#eco.loot == 2 and eco.loot[1].tier == "veryRare" and #eco.drops == 0 and eco.craft == false,
    "節能核心：兩個地點都很稀有、殭屍不帶、不能製作")
W.clientLists.lootItems = { [MOD("Eco")] = 4, [MOD("Ledger")] = 0 }
check(C.acquireInfo(MOD("Eco")).loot[1].tier == "rare" and #C.acquireInfo(MOD("Ledger")).loot == 0
    and C.acquireInfo(MOD("Ledger")).craft == 3, "逐項倍率：節能核心 ×4 變稀有；×0 的名錄模組不寫地點，製作照舊")
SB.LootWatchAmount = 1
check(C.acquireInfo(W.watchType("ValuTech")).loot[1].tier == "common"
    and C.acquireInfo(W.watchType("Luthex")).loot[1].tier == "veryRare", "數量照沙盒：錶很少（×0.25）時展示櫃 4→1 仍常見、盧瑟斯降到很稀有")
SB.LootWatchAmount = nil
check(C.dropShare("watch:any", W.watchType("Luthex")) == 1 / 7 and C.dropShare("mod:any", MOD("Eco")) == 0
    and C.dropShare("mod:any", MOD("Light")) == 1 / 6 and C.dropShare("battery", W.BATTERY_TYPE) == 1
    and C.dropShare("card:ext", W.CARD_TYPES.ext) == 1 and C.dropShare("mod:comm", MOD("GPS")) == 0,
    "掉落規則對物品的比例：隨機一款錶 1/7、隨機一般模組 1/6（不含核心）、指定物品全份、別的物品 0")
check(C.pctText(2) == "2" and C.pctText(2 / 6) == "0.33" and C.pctText(0.05) == "0.05" and C.pctText(0.2 / 7) == "0.029"
    and C.pctText(0.0001) == "<0.001", "機率的寫法：整數不帶小數、0.1 以上兩位、更小三位")
local bat = C.acquireInfo(W.BATTERY_TYPE)
check(bat.vanilla == true and #bat.loot == 0 and bat.craft == false, "電池：原版物品、不在本 MOD 的分佈表、不能製作")
W.clientLists.drops, W.clientLists.dropCap, W.clientLists.lootItems, SB.AcquireGuide = nil, nil, {}, nil
end

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
    arrow = { key = "RuleNav", mods = { "GPS" }, need = "gps" }, -- 方向箭頭跟著導航：同一條規則、同一個模組
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
expect("nav：沒模組、沒裝置＝擋；裝了 AutoDrive＝原因是定位模組或 GPS 導航儀", "nav", nil, false,
    "IGUI_MinidoracatWatch_Reason_Need_gpsOrDevice", nil)
hasDevice = true
SB.RuleNav = 4
expect("nav 關閉：有裝置也擋", "nav", nil, false, W.REASON_FEATURE_OFF, nil)
SB.RuleNav = nil
F.unwear(p, watch)
F.fire("OnClothingUpdated", p)
expect("nav：沒戴錶、有裝置＝放行", "nav", nil, true, nil, nil)
hasDevice = false
expect("nav：沒戴錶、沒裝置＝原因照舊是戴錶（只換定位模組那條）", "nav", nil, false, W.REASON_NEED_WATCH, nil)
hasDevice = true
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
expect("hasNavDevice 拋錯：當沒有（API 在，原因仍提導航儀）", "nav", nil, false, "IGUI_MinidoracatWatch_Reason_Need_gpsOrDevice", nil)
expect("hasNavDevice 再拋錯", "nav", nil, false, "IGUI_MinidoracatWatch_Reason_Need_gpsOrDevice", nil)
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

-- 外觀 MOD（Mirage Wardrobe）從 OnTick 到畫完，把身上衣物整份換成重建的複製品（新 ID、不在背包、沒有我們的 modData；
-- 隱藏的部位換成 Base.Belt2）：期限到也不讀複製品、沿用上一筆，換回來後第一次呼叫就重算
do
    local function swapAppearance(items)
        local real = p.worn
        p.worn = {}
        for i, it in ipairs(items) do p.worn[i] = { loc = "look" .. i, item = it } end
        return function() p.worn = real end
    end
    W.setCharge(watch, W.NO_BATTERY)
    tick()
    check(C.watchOf(0) == watch and W.moduleState(p, "gps") == "unpowered", "（換上前：背包那支、沒電池、定位模組停用中）")
    local restore = swapAppearance({ F.item("Base.Tshirt_DefaultTEXTURE"), F.item(F.RIGHT) })
    tick()
    F.fire("OnClothingUpdated", p) -- 它換上時的 resetModel 也會觸發這個事件
    check(C.watchOf(0) == watch, "乾淨外觀：期限到也不讀複製品（100%、沒有模組），沿用背包那支")
    check(W.moduleState(p, "gps") == "unpowered" and select(2, gate(0, "minimap")) == W.REASON_NO_BATTERY,
        "乾淨外觀：模組與小地圖閘門照舊是沒電池")
    restore()
    check(C.watchOf(0) == watch, "換回來：讀背包那支")
    restore = swapAppearance({ F.item("Base.Belt2") })
    tick()
    check(C.watchOf(0) == watch, "隱藏原本衣物（手腕換成 Base.Belt2）：不當成沒戴錶")
    restore()
    W.clearStatus()
    restore = swapAppearance({ F.item(F.RIGHT) })
    check(C.watchOf(0) == nil, "第一次就碰上：不讀複製品，先當沒戴錶")
    restore()
    check(C.watchOf(0) == watch, "換回來不必等期限就讀到背包那支")
    -- 充電中：複製品沒有電量鍵（＝100%），不能被當成已充飽
    W.setCharge(watch, 0.5)
    F.fire("OnServerCommand", W.MODULE, W.CMD_CHARGE, { to = "alice", kind = "car" })
    restore = swapAppearance({ F.item(F.RIGHT) })
    tick()
    check(W.chargeState(p) == "car", "乾淨外觀：照舊是車上充電中")
    restore()
    F.fire("OnServerCommand", W.MODULE, W.CMD_CHARGE, { to = "alice" })
    -- 身上真的只剩背包裡沒有的物品（例如 SyncClothing 送來、背包沒有的化妝品）：連續 3 秒都這樣就照看到的算
    restore = swapAppearance({ F.item("Base.MakeUp_Lipstick") })
    tick()
    check(C.watchOf(0) == watch, "只剩對不回背包的物品：3 秒內沿用")
    F.now = F.now + 3000
    check(C.watchOf(0) == nil, "連續 3 秒都對不回背包：照看到的算（沒戴錶）")
    restore()
    F.fire("OnClothingUpdated", p)
    check(C.watchOf(0) == watch, "（換回來）")
end

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
-- 工具列電池：原色殼（白色頂點色）＋窗口內電量；窗口 64px 座標 x 14..48、y 25..38（28px 時往內取整成 x 7..20、y 11..16）
do
    local SHELL = "tex:media/ui/MinidoracatWatch/dock_battery_shell.png"
    local shells, rects = {}, {}
    local el = setmetatable({}, Element)
    function el:drawTextureScaled(t, x, y, w, h, a, r, g, b) shells[#shells + 1] = { t = t, x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b } end
    function el:drawRect(x, y, w, h, a, r, g, b) rects[#rects + 1] = { x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b } end
    local th = { colors = { text = { r = 0.9, g = 0.9, b = 0.9 }, accent = { r = 0, g = 1, b = 0 }, warnStrong = { r = 1, g = 0.5, b = 0 },
        errorText = { r = 1, g = 0, b = 0 } } }
    local function draw(w, size)
        shells, rects, F.icons = {}, {}, {}
        C.drawDockBattery(el, 100, 200, size or 28, w, th)
        return shells[1], rects[1]
    end
    local function inWindow(r, size)
        local k = (size or 28) / 64
        return r.x >= 100 + 14 * k and r.x + r.w <= 100 + 49 * k and r.y >= 200 + 25 * k and r.y + r.h <= 200 + 39 * k
    end
    C.dockShellTex = nil
    W.setCharge(watch, 0.7)
    local s, r = draw(watch)
    check(s and s.t == SHELL and s.x == 100 and s.y == 200 and s.w == 28 and s.h == 28 and s.a == 1 and s.r == 1 and s.g == 1 and s.b == 1
        and #F.icons == 0, "工具列電池：原色殼（白色頂點色、不染色）蓋滿圖示格，不畫框架的白色電池")
    check(r and #rects == 1 and r.x == 107 and r.y == 211 and r.w == math.floor(14 * 0.7) and r.h == 6 and r.g == 1 and r.r == 0
        and inWindow(r), "70%：窗口內寬度 ×0.7、accent 色")
    s, r = draw(watch, 64)
    check(r.x == 114 and r.y == 225 and r.w == math.floor(35 * 0.7) and r.h == 14 and inWindow(r, 64), "64px：窗口剛好是 x 14..48、y 25..38")
    W.setCharge(watch, 0.1)
    s, r = draw(watch)
    check(r and r.r == 1 and r.g == 0.5 and r.w == 1 and inWindow(r), "低電：warnStrong 色、至少 1px")
    W.setCharge(watch, 0)
    s, r = draw(watch)
    check(r and r.r == 1 and r.g == 0 and r.a == 0.5 and r.w == 14 and r.h == 6 and inWindow(r), "沒電：整格 errorText 半透明")
    s, r = draw(nil)
    check(s and s.a == 0.4 and r == nil, "沒錶：殼 alpha 0.4、不畫電量")
    W.setCharge(watch, 0.5)
    shells = {}
    dockSpec.drawIcon(el, 0, 0, 28)
    check(shells[1] and shells[1].t == SHELL, "Dock drawIcon 走工具列電池")
    -- 貼圖讀不到：記住失敗，之後都退回舊畫法（框架 Icons battery＋內框電量）
    local realGet, tries = getTexture, 0
    getTexture = function() tries = tries + 1; return nil end
    C.dockShellTex = nil
    s, r = draw(watch)
    draw(watch)
    check(s == nil and F.icons[1] == "battery" and r and tries == 1 and C.dockShellTex == false,
        "缺圖：退回 Icons battery＋電量，只讀一次貼圖")
    getTexture = function() error("boom") end
    C.dockShellTex = nil
    s = draw(watch)
    check(s == nil and F.icons[1] == "battery", "getTexture 丟錯：一樣退回舊畫法")
    getTexture = realGet
    C.dockShellTex = nil
end
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
local ledger = give(MOD("Ledger"))
F.reset()
C.requestModule(p, watch, "std2", ledger)
local act = F.queues[p][1]
check(act and act.kind == "module" and act.maxTime == 150 and act.install == true, "安裝排進計時動作（約 3 秒）")
F.runActions(p)
cmd = F.clientCmds[1]
check(cmd and cmd.command == W.CMD_MODULE and cmd.args.watchId == watch.id and cmd.args.slotId == "std2"
    and cmd.args.install == true and cmd.args.itemId == ledger.id and scalars(cmd.args), "完成時送純量安裝指令")
F.reset()
C.requestModule(p, watch, "std2", ledger)
p.inv:DoRemoveItem(ledger)
F.runActions(p)
check(#F.clientCmds == 0, "模組在動作途中離開背包：取消")
p.inv:AddItem(ledger)
local sd = p.inv:getAllTypeRecurse("Base.Screwdriver"):get(0)
p.inv:DoRemoveItem(sd)
F.reset()
C.requestModule(p, watch, "std2", ledger)
check(not (F.queues[p] and F.queues[p][1]) and F.halos[1] and F.halos[1].text == W.FAIL_SCREWDRIVER,
    "沒有螺絲起子：不排動作、提示")
SB.NeedScrewdriver = false
C.requestModule(p, watch, "std2", ledger)
check(F.queues[p][1] ~= nil, "沙盒關掉螺絲起子：可以排")
F.queues[p] = {}
SB.NeedScrewdriver = true
p.inv:AddItem(sd)
-- 單機：完成時直接套用 shared 突變點
F.mode = "sp"
local ledgerBefore = p.inv:getAllTypeRecurse(MOD("Ledger")):size() - 1
C.requestModule(p, watch, "std2", ledger)
F.runActions(p)
check(W.slotRecord(watch, "std2") and W.slotRecord(watch, "std2").id == "ledger" and ledger.container == nil,
    "單機：動作完成就裝好")
C.requestModule(p, watch, "std2", nil)
F.runActions(p)
check(W.slotRecord(watch, "std2") == nil and ledger.container == nil and p.inv:getAllTypeRecurse(MOD("Ledger")):size() == ledgerBefore + 1, "單機：拆下")
ledger = p.inv:getAllTypeRecurse(MOD("Ledger")):get(ledgerBefore)
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
sp(W.applyModuleChange, p, watch:getID(), "std1", true, ledger:getID())
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
local realBatt, realDock, nBatt, nDock = C.drawBattery, C.drawDockBattery, 0, 0
C.drawBattery = function(...) nBatt = nBatt + 1; return realBatt(...) end
C.drawDockBattery = function(...) nDock = nDock + 1; return realDock(...) end
panel:prerender()
panel.sockets:prerender()
C.drawBattery, C.drawDockBattery = realBatt, realDock
check(nBatt >= 1 and nDock == 0, "標題列電量膠囊照舊用 Icons 電池（不用工具列的原色殼）")
check(F.draws >= 40, "面板畫出錶面、槽位、檢視區、功能清單與電量列（" .. F.draws .. " 次繪製）")
local iconSet = {}
for _, k in ipairs(F.icons) do iconSet[k] = true end
check(iconSet.lock and iconSet.check and iconSet.battery, "鎖、功能勾、電池都用 UI.Icons，不自己畫")
-- 主 MOD 回報伺服器把這項功能整個關了（featureApiVersion 2 的 featureServerOff）：功能清單寫「伺服器未開放」、打叉
local function featOf(id)
    for _, f in ipairs(panel:buildFeatures()) do
        if f.label == "IGUI_MinidoracatWatch_Feature_" .. id then return f end
    end
end
local OFF = "IGUI_MinidoracatWatch_Reason_ServerOff"
local mainApi = MinidoracatMiniMapAPI
local off = { zombie = true }
MinidoracatMiniMapAPI = { featureApiVersion = 2, featureServerOff = function(f) return off[f] == true end }
local z = featOf("zombie")
check(z.ok == false and z.icon == "close" and z.note == OFF, "伺服器關了殭屍點位：功能清單寫伺服器未開放、打叉")
check(featOf("scan").note ~= OFF, "伺服器沒關的功能照舊")
MinidoracatMiniMapAPI = { featureApiVersion = 1, featureServerOff = function() return true end }
check(featOf("zombie").note ~= OFF, "主 MOD 舊於 v2：不問 featureServerOff")
F.reset()
MinidoracatMiniMapAPI = { featureApiVersion = 2, featureServerOff = function() error("boom") end }
check(featOf("zombie").note ~= OFF and featOf("scan").note ~= OFF, "featureServerOff 拋錯：當作沒關")
local offLogs = 0
for _, l in ipairs(F.logs) do if l:find("featureServerOff", 1, true) then offLogs = offLogs + 1 end end
check(offLogs == 1, "拋錯只 log 一次")
MinidoracatMiniMapAPI = mainApi
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
-- ValuTech 一列排開：↓ 到下面的負重列（三格對齊錶面三欄，照座標找最近那格）；負重列是最後一列時再 ↓ 交給 Focus
check(sk.layout == "row" and sk:onFocusKey(Keyboard.KEY_DOWN) and sk.cur == slotIndex("wt1"),
    "ValuTech：↓ 從六格那列移到負重列（標準槽 2 下面是負重槽 I）")
check(sk:onFocusKey(Keyboard.KEY_RIGHT) and sk.cur == slotIndex("wt2") and sk:onFocusKey(Keyboard.KEY_RIGHT)
    and sk.cur == slotIndex("wt3"), "負重列 →：I → II → III")
check(sk:onFocusKey(Keyboard.KEY_DOWN) == false and sk.cur == slotIndex("wt3"),
    "負重列下面沒有其他 MOD 的槽位：↓ 不處理（交給 Focus 移到下一個目標）")
check(sk:onFocusKey(Keyboard.KEY_UP) and sk.cur <= 6 and panel.sel == slotIndex("std3"), "負重列 ↑：回到六格那列，選取不變")
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
-- 模組等級：核心槽收三種等級。按鈕依核心→進階→一般排、左緣畫等級色條、滑過說明等級；篩選列在按鈕上方
selectSlot("core")
local RANK = { core = 3, advanced = 2, standard = 1 }
local function modBtns()
    local out = {}
    for _, b in ipairs(panel.actBtns) do if b.visible and b.internal == "module" then out[#out + 1] = b end end
    return out
end
local function sortedByTier(list)
    for i = 2, #list do if RANK[list[i].def.class] > RANK[list[i - 1].def.class] then return false end end
    return true
end
local function filters()
    local s = {}
    for _, b in ipairs(panel.filterBtns) do
        if b.visible then s[#s + 1] = b.internal .. (b.active and "*" or "") .. (b.enable and "" or "-") end
    end
    return table.concat(s, ",")
end
local coreMods = modBtns()
local tiers = {}
for _, b in ipairs(coreMods) do tiers[b.def.class] = true end
check(#coreMods >= 3 and tiers.core and tiers.advanced and tiers.standard and sortedByTier(coreMods)
    and coreMods[1].def.class == "core", "核心槽：三種等級都列出，依核心→進階→一般排")
-- 滑過說明：類別、耗電，內建模組再加說明。說明用 wrap 斷成不超過 300px 的行（替身量字寬 #s*7）、以 <LINE> 接起來；
-- 不能含 \n（原版 ISButton 看到 \n 就不換行）
local function tipOk(b, class)
    local t = b.tooltip or ""
    local cls, drain, desc = t:match("^(.-) <LINE> (.-) <LINE> (.+)$")
    if not desc or t:find("\n", 1, true) then return false, 0 end
    local narrow, lines = true, 0
    for line in (desc .. " <LINE> "):gmatch("(.-) <LINE> ") do lines, narrow = lines + 1, narrow and #line * 7 <= 300 end
    return cls == "IGUI_MinidoracatWatch_KV_Class|IGUI_MinidoracatWatch_Class_" .. class
        and drain == "IGUI_MinidoracatWatch_KV_Drain|" .. C.drainText(b.def)
        and desc:gsub(" <LINE> ", "") == C.moduleDesc(b.def.id) and narrow, lines
end
local topOk, topLines = tipOk(coreMods[1], "core")
check(topOk and topLines > 1 and tipOk(coreMods[#coreMods], "standard"),
    "模組按鈕的滑過說明：等級、耗電與模組說明（長說明斷成多行）")
MinidoracatWatchAPI.registerWatchModule({ id = "radio", name = "IGUI_X_Radio", class = "standard", drain = 5,
    item = "MyRadio.RadioModule", desc = "IGUI_X_RadioDesc" })
check(C.moduleDesc("radio") == "IGUI_X_RadioDesc" and C.moduleDesc("weather") == nil,
    "其他 MOD 的模組說明：登記時帶 desc 回翻譯後的文字，沒帶回 nil")
local wItem, rItem = give("MyWeather.WeatherModule"), give("MyRadio.RadioModule")
tick()
panel:update()
local wBtn, rBtn
for _, b in ipairs(modBtns()) do
    if b.def.id == "weather" then wBtn = b elseif b.def.id == "radio" then rBtn = b end
end
check(wBtn and wBtn.tooltip == "IGUI_MinidoracatWatch_KV_Class|IGUI_MinidoracatWatch_Class_standard <LINE> "
    .. "IGUI_MinidoracatWatch_KV_Drain|IGUI_MinidoracatWatch_DrainPlus|15", "其他 MOD 的模組沒帶 desc：只有等級與耗電")
check(rBtn and rBtn.tooltip == "IGUI_MinidoracatWatch_KV_Class|IGUI_MinidoracatWatch_Class_standard <LINE> "
    .. "IGUI_MinidoracatWatch_KV_Drain|IGUI_MinidoracatWatch_DrainPlus|5 <LINE> IGUI_X_RadioDesc",
    "其他 MOD 的模組帶 desc：等級、耗電，再加說明")
p.inv:DoRemoveItem(wItem)
p.inv:DoRemoveItem(rItem)
tick()
panel:update()
local bars = {}
for i, b in ipairs({ coreMods[1], coreMods[#coreMods] }) do
    b.drawRect = function(_, x, y, w, h, a, r, g, bl) bars[i] = { x = x, w = w, r = r, g = g, b = bl } end
    b:render()
    b.drawRect = nil
end
local cCore, cStd = panel.inspTheme.colors.tierCore, panel.inspTheme.colors.tierStd
check(bars[1] and bars[1].x < 10 and bars[1].r == cCore.r and bars[1].g == cCore.g and bars[1].b == cCore.b
    and bars[2] and bars[2].r == cStd.r and bars[2].b == cStd.b, "左緣色條＝槽位外框的等級色（核心紫、一般灰），畫在圖示左邊")
check(filters() == "all*,standard,advanced,core", "篩選列：全部（選中）＋這個槽位收的三種等級")
local targets2 = panel:keyboardTargets()
local function at(c) for i, t in ipairs(targets2) do if t == c then return i end end end
check(panel.filterBtns[1].y < coreMods[1].y and at(panel.filterBtns[1]) < at(coreMods[1]),
    "篩選列在模組按鈕上方，Tab 先到篩選列")
panel.filterBtns[3]:forceClick() -- 進階
tick()
panel:update()
local advOnly = modBtns()
check(#advOnly >= 1 and filters() == "all,standard,advanced*,core", "按「進階」：選中進階")
local onlyAdv = true
for _, b in ipairs(advOnly) do if b.def.class ~= "advanced" then onlyAdv = false end end
check(onlyAdv, "按「進階」：只列進階模組")
panel.filterBtns[4]:forceClick() -- 核心
tick()
panel:update()
local relays = p.inv:getAllTypeRecurse(MOD("Relay"))
local relayItem = relays:get(0)
p.inv:DoRemoveItem(relayItem)
tick()
panel:update()
check(panel.modFilter == nil and filters() == "all*,standard,advanced,core-" and sortedByTier(modBtns()),
    "選中的等級沒有模組了：回到全部，那個等級停用")
p.inv:AddItem(relayItem)
panel.filterBtns[3]:forceClick()
selectSlot("std3")
check(panel.modFilter == nil and filters() == "", "換到只收一般模組的標準槽：篩選重設、沒有篩選列")
-- 檢視區的文字（上一幀量到的底緣）壓到按鈕：檢視區長高，按鈕整塊移到文字下方
selectSlot("core")
local tb = panel.actTop + 40
panel.textBottom = tb
panel:update()
check(panel.actTop >= tb + 6 and panel.filterBtns[1].y >= tb + 6, "文字壓到按鈕時檢視區長高，篩選列與按鈕移到文字下方")
-- ===== 負重列（設計稿 claim 2–3）：錶面下方自己一列、三格對齊錶面三欄、44px 畫得出等級標籤；只列同一階的核心；
-- 檢視區兩列三格；沒電的格子畫電池徽章、停用的畫暫停 =====
local function drew(want) return table.concat(F.texts):find(want, 1, true) ~= nil end
local function iconCount(name)
    local n = 0
    for _, k in ipairs(F.icons) do if k == name then n = n + 1 end end
    return n
end
local rowOk = true
local _, wy0 = sk:socketRect(slotIndex("wt1"))
for t = 1, 3 do
    local x, y, s = sk:socketRect(slotIndex("wt" .. t))
    if not (s == 44 and y == wy0 and y > sk:faceH() + 16 and math.abs(x + s / 2 - (t - 0.5) * sk.width / 3) <= 1) then
        rowOk = false
    end
end
check(rowOk and sk.height >= wy0 + 44 + 16 + 2,
    "負重列：錶面與標題下方一列、三格 44px 對齊錶面三欄（不是其他 MOD 的 40px 排法），槽位區包得住等級標籤")
-- 字型放大（字高 30）：槽位區照樣包得住負重格底下的等級標籤（標籤底緣＝格底＋1＋字高＋2）
do
    local tm = getTextManager
    getTextManager = function() return { MeasureStringX = function(_, _, s) return #s * 7 end, getFontHeight = function() return 30 end } end
    local _, wy, ws = sk:socketRect(slotIndex("wt3"))
    local ok = sk:areaH() >= wy + ws + 1 + 30 + 2
    getTextManager = tm
    check(ok, "字型放大：槽位區高度算進負重格的等級標籤")
end
SB.SlotWt1, SB.SlotWt2, SB.SlotWt3 = 1, 1, 1
W.setCharge(watch, 0.5)
local w1a, w1b, w2a, w3a = give(MOD("Weight1")), give(MOD("Weight1")), give(MOD("Weight2")), give(MOD("Weight3"))
tick()
selectSlot("wt1")
local wmods = modBtns()
check(#wmods == 1 and wmods[1].def.id == "weight1" and filters() == "",
    "選負重槽 I：模組按鈕只列負重核心 I（不列 II、III 與其他模組），沒有篩選列")
local wbar
wmods[1].drawRect = function(_, x, y, w, h, a, r, g, bl) wbar = { r = r, g = g, b = bl } end
wmods[1]:render()
wmods[1].drawRect = nil
local cW = panel.inspTheme.colors.tierWeight
check(wbar and cW and wbar.r == cW.r and wbar.g == cW.g and wbar.b == cW.b, "負重核心按鈕的左緣色條＝負重槽色 tierWeight")
local wtip = wmods[1].tooltip or ""
check(wtip:find("^IGUI_MinidoracatWatch_KV_ClassWeight <LINE> IGUI_MinidoracatWatch_KV_Tier|I <LINE> ") ~= nil
    and wtip:find("IGUI_MinidoracatWatch_WeightNeeds <LINE> IGUI_MinidoracatWatch_ModuleDesc_weight1", 1, true) ~= nil
    and not wtip:find("\n", 1, true), "負重核心按鈕的滑過說明：類別、階級、加成、耗電、生效條件，再接說明")
selectSlot("std3")
local noWeight = true
for _, b in ipairs(modBtns()) do if W.WEIGHT_CLASSES[b.def.class] then noWeight = false end end
check(noWeight, "標準槽不列負重核心")
SB.WeightUnits2 = 3
sp(W.applyModuleChange, p, watch:getID(), "wt1", true, w1a:getID())
sp(W.applyModuleChange, p, watch:getID(), "wt2", true, w2a:getID())
tick()
selectSlot("wt2")
check(panel.weightText == "IGUI_MinidoracatWatch_WeightRowMax|IGUI_MinidoracatWatch_WeightUnitsShort|4|12",
    "負重列標題：這支錶 +4 格（負重核心 II 照沙盒 3 格），戴著、有電再接角色現在的負重上限")
F.texts = {}
sk:prerender()
check(drew("IGUI_MinidoracatWatch_Tag_wt1") and drew("IGUI_MinidoracatWatch_Tag_wt2") and drew("IGUI_MinidoracatWatch_Tag_wt3")
    and drew("IGUI_MinidoracatWatch_WeightCores") and drew(panel.weightText) and not drew("IGUI_MinidoracatWatch_OtherMods"),
    "負重列：自己的標題與總加成、三格都畫等級標籤；沒有其他 MOD 的槽位就不畫「其他 MOD」")
-- ValuTech 一排六格的格距只有 48px：擴充、進階、核心三個等級標籤最寬 46px、相鄰兩個不重疊（假字寬下鍵名一定比格距長）
do
    local pills, rowY = {}, select(2, sk:socketRect(slotIndex("core"))) + 44 + 1
    panel.theme.fill = function(_, _, x, y, w, _, _, shape)
        if shape == "pill" and y == rowY then pills[#pills + 1] = { x = x, w = w } end
    end
    sk:prerender()
    panel.theme.fill = nil
    table.sort(pills, function(a, b) return a.x < b.x end)
    local ok = #pills == 3
    for j, q in ipairs(pills) do
        if q.w > 46 or (pills[j + 1] and q.x + q.w >= pills[j + 1].x) then ok = false end
    end
    check(ok, "ValuTech 一排六格：擴充、進階、核心三個等級標籤最寬 46px，相鄰兩個不重疊")
end
-- 標題和總加成一行放不下（假字寬 7px／字：鍵名一定放不下）就把總加成換到第二行、負重列往下一行；放得下就同一行
do
    local function sumY()
        local got
        sk.drawText = function(_, t, _, y) if t == panel.weightText then got = y end end
        sk:prerender()
        sk.drawText = nil
        return got
    end
    local wrapY = sumY()
    local _, wrapTop = sk:socketRect(slotIndex("wt1"))
    local realTM = getTextManager
    getTextManager = function() return { MeasureStringX = function() return 10 end, getFontHeight = function() return 16 end } end
    panel.scanAt = nil
    panel:update()
    local fits, oneY = panel.weightWrap, sumY()
    local _, oneTop = sk:socketRect(slotIndex("wt1"))
    getTextManager = realTM
    panel.scanAt = nil
    panel:update()
    check(panel.weightWrap == true and fits == false and wrapY == oneY + 16 and wrapTop == oneTop + 16,
        "負重列標題放不下一行：總加成換到第二行、三格往下一行；放得下就同一行")
end
p.maxWeight, p.maxWeightBase = 17.5, 99
F.texts = {}
panel:prerender()
check(drew("IGUI_MinidoracatWatch_KV_Tier|II") and drew("IGUI_MinidoracatWatch_KV_Bonus|IGUI_MinidoracatWatch_WeightUnits|3|37.5")
    and drew("IGUI_MinidoracatWatch_KV_Drain|IGUI_MinidoracatWatch_DrainPlus|200")
    and drew("IGUI_MinidoracatWatch_KV_Slot|IGUI_MinidoracatWatch_St_active")
    and drew("IGUI_MinidoracatWatch_KV_WatchTotal|IGUI_MinidoracatWatch_WeightUnitsShort|4"),
    "檢視區（負重核心 II）：階級、加成、耗電、槽位、這支錶合計五格")
check(drew("IGUI_MinidoracatWatch_WeightNow|17.5") and not drew("|99"), "角色現在的負重上限讀 getMaxWeight（不從不同步的基數算）")
SB.WeightEnabled = false
panel.scanAt = nil
panel:update()
F.texts = {}
panel:prerender()
check(panel.weightText == "IGUI_MinidoracatWatch_WeightRowMax|IGUI_MinidoracatWatch_WeightUnitsShort|0|17.5"
    and drew("IGUI_MinidoracatWatch_KV_Drain|IGUI_MinidoracatWatch_DrainNone"),
    "負重核心整個關閉：合計 0 格、不耗電；標題的負重上限也讀 getMaxWeight（不從基數算）")
SB.WeightEnabled = nil
W.setCharge(watch, 0)
tick()
panel.scanAt = nil
panel:update()
F.icons, F.texts = {}, {}
sk:prerender() -- 只算槽位區的圖示（面板的電量膠囊、功能清單另有電池與暫停圖示）
local deadBatt, deadPause = iconCount("battery"), iconCount("pause")
panel:prerender()
check(deadBatt == 3 and deadPause == 0 and panel.weightText == "IGUI_MinidoracatWatch_WeightRowDead"
    and drew("IGUI_MinidoracatWatch_St_dead"),
    "沒電：有模組的三格（標準槽 1、負重槽 I、II）畫電池徽章（不是暫停）、負重列只寫 +0 格（沒電）不接上限、狀態寫沒電")
W.setCharge(watch, 0.5)
SB.SlotWt2 = 4
tick()
panel.scanAt = nil
panel:update()
F.icons = {}
sk:prerender()
check(iconCount("pause") == 1 and iconCount("battery") == 0
    and panel.weightText == "IGUI_MinidoracatWatch_WeightRowMax|IGUI_MinidoracatWatch_WeightUnitsShort|1|17.5",
    "負重槽 II 不開放：那一格畫暫停徽章、合計只剩 I 的 1 格")
local spare = give(F.LEFT)
W.setCharge(spare, 0.5)
panel.watchItem, panel.scanAt = spare, nil
panel:update()
check(panel.weightText == "IGUI_MinidoracatWatch_WeightUnitsShort|0",
    "背包裡那支（沒戴著）：負重列只寫這支錶的格數，不接角色的負重上限（上限不含它的加成）")
p.inv:DoRemoveItem(spare)
panel.watchItem, panel.scanAt = nil, nil
panel:update()
sk.cur = slotIndex("wt1")
check(sk:onFocusKey(Keyboard.KEY_UP) and sk.cur <= 6, "負重列 ↑ 回到六格")
watch:getModData()[W.SLOTS_KEY].wt1, watch:getModData()[W.SLOTS_KEY].wt2 = nil, nil
for _, it in ipairs({ w1b, w3a }) do p.inv:DoRemoveItem(it) end
SB.SlotWt1, SB.SlotWt2, SB.SlotWt3, SB.WeightUnits2, p.maxWeight, p.maxWeightBase = nil, nil, nil, nil, nil, nil
W.invalidate()
tick()
selectSlot("core")
selectSlot("std3")
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
local _, wty, wts = panel.sockets:socketRect(slotIndex("wt1"))
F.texts = {}
panel.sockets:prerender()
check(fss == 40 and fsx == 0 and fsy >= wty + wts + 16 + 2 and panel.sockets.height >= fsy + fss
    and hasText("IGUI_MinidoracatWatch_OtherMods"),
    "其他 MOD 的槽位排在負重列與等級標籤下面（40px、有「其他 MOD」標題），槽位區跟著長高")
sk.cur = slotIndex("wt1")
check(sk:onFocusKey(Keyboard.KEY_DOWN) and sk.cur == slotIndex("forecast"), "負重列 ↓：到其他 MOD 的槽位")
-- C.toast 把 holdMs 交給框架的 Toast（負重相關的停 8 秒、給到 8 行，恢復方法才不會被截掉）；沒給＝框架預設、3 行。
-- 框架 rev 18 以前標題只畫一行（284px，假字寬 7px／字：40 字放得下、41 字放不下）：放不下就併進訊息開頭、多給兩行；
-- 框架有 toastTitleWrap（rev 19，標題自己換行）就原樣交給框架
local shown = {}
local realShow = C.ui().Toast.show
C.ui().Toast.show = function(o) shown[#shown + 1] = o end
C.toast(p, "msg", "title", 8000)
C.toast(p, "msg2")
C.toast(p, "msg3", string.rep("t", 40))
C.toast(p, "msg4", string.rep("t", 41), 8000)
C.ui().CAPABILITIES.toastTitleWrap = true
C.toast(p, "msg5", string.rep("t", 41))
C.ui().CAPABILITIES.toastTitleWrap = nil
C.ui().Toast.show = realShow
check(shown[1] and shown[1].holdMs == 8000 and shown[1].title == "title" and shown[1].message == "msg" and shown[1].maxLines == 8
    and shown[2] and shown[2].holdMs == nil and shown[2].maxLines == 3, "C.toast：holdMs 交給 UI.Toast（沒給就不帶）；停久的給 8 行")
check(shown[3] and shown[3].title == string.rep("t", 40) and shown[3].message == "msg3" and shown[3].maxLines == 3
    and shown[4] and shown[4].title == nil and shown[4].message == "IGUI_MinidoracatWatch_ToastFold|" .. string.rep("t", 41) .. "|msg4"
    and shown[4].maxLines == 10 and shown[4].holdMs == 8000,
    "C.toast：舊框架的標題放得下照舊；放不下就併進訊息開頭、多給兩行（停留時間照帶）")
check(shown[5] and shown[5].title == string.rep("t", 41) and shown[5].message == "msg5" and shown[5].maxLines == 3,
    "C.toast：框架會自己換標題（toastTitleWrap）時，放不下的標題也原樣交給框架")
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
-- 節能核心的檢視區：說明下面接耐力與保留小地圖（照沙盒，和物品停留說明同一份；scan 每 250ms 重算，畫的時候只讀）
SB.EcoEnduranceDrain, SB.EcoEnduranceRegen = 10, 0
panel.scanAt = nil
panel:update()
F.texts = {}
panel:prerender()
check(hasText("IGUI_MinidoracatWatch_EcoEndurance|IGUI_MinidoracatWatch_EcoEnduranceDrain|10") and not hasText("EcoEnduranceRegen")
    and hasText("IGUI_MinidoracatWatch_EcoKeepsMap"), "節能核心的檢視區：耐力消耗 −10%（恢復設 0 不寫）、沒電時保留小地圖")
SB.EcoEnduranceDrain, SB.EcoEnduranceRegen = nil, nil
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
-- 「需要 X 模組」的膠囊：滑過顯示取得方式（每句斷成 300px、以 <LINE> 接起來）；移開收掉、關面板也收掉
ISToolTip = {}
ISToolTip.__index = ISToolTip
function ISToolTip:new() return setmetatable({ visible = false }, ISToolTip) end
function ISToolTip:setOwner(o) self.owner = o end
function ISToolTip:setVisible(v) self.visible = v end
function ISToolTip:getIsVisible() return self.visible end
function ISToolTip:setAlwaysOnTop() end
function ISToolTip:addToUIManager() self.inUI = true end
function ISToolTip:removeFromUIManager() self.inUI = false end
local needChip, okChip
for _, f in ipairs(panel.feats) do
    if f.tip and not needChip then needChip = f end
    if f.ok then okChip = f end
end
local needId = needChip and W.PROVIDERS[needChip.label:match("Feature_(.+)$")][1]
check(needChip and needChip.note:find("Reason_Need_", 1, true)
    and needChip.tip:gsub(" <LINE> ", "") == table.concat(C.acquireLines(needId)) and okChip and okChip.tip == nil,
    "缺模組的功能有取得方式的說明；能用的功能沒有")
panel.mouseOver, panel.mx, panel.my = true, needChip.x + 2, needChip.y + 2
panel:update()
local featTip = panel.featTip
check(featTip and featTip.visible and featTip.inUI and featTip.owner == panel and featTip.maxLineWidth == 300
    and featTip.description == needChip.tip, "滑到膠囊上：顯示取得方式")
panel.my = needChip.y - 200
panel:update()
check(not featTip.visible and not featTip.inUI, "滑鼠移開：收掉")
panel.my = needChip.y + 2
panel:update()
check(featTip.visible and panel.featTip == featTip, "滑回來：同一個說明框再顯示")
local px, py = 333, 222
panel.x, panel.y = px, py
panel:close()
check(not C.isPanelOpen() and not panel.inUI, "關閉鈕：關閉面板")
check(not featTip.visible and not featTip.inUI, "關閉面板：功能清單的說明框一起收掉")
panel.mouseOver = nil
check(F.avoid.MinidoracatWatchPanel() == nil, "關閉後 Toast 不再避開")
-- 引擎把移除排到下一幀（UIManager.java:119-123、:497-501），關掉的那一幀照樣呼叫 update（UIElement.java:1661-1676）
check(pcall(panel.update, panel), "關掉後同一幀還跑到 update：不拋錯（槽位區讀自己的面板，不讀已清空的單例）")
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
check(opts[1].name == "IGUI_MinidoracatWatch_UseCard" and opts[1].sub and #opts[1].sub.options == 2
    and opts[1].sub.options[1].name == "IGUI_MinidoracatWatch_OpenSlot|IGUI_MinidoracatWatch_Slot_ext"
    and opts[1].sub.options[2].name == "IGUI_MinidoracatWatch_OpenSlot|IGUI_MinidoracatWatch_Slot_wt1",
    "擴充槽解鎖卡右鍵：開啟擴充槽、負重槽 I（同一張卡）")
W.clientUnlocks.alice = { ext = true }
W.invalidate()
opts = context({ card })
check(not opts[1].notAvailable and #opts[1].sub.options == 1
    and opts[1].sub.options[1].name == "IGUI_MinidoracatWatch_OpenSlot|IGUI_MinidoracatWatch_Slot_wt1", "擴充槽已開啟：只剩負重槽 I")
W.clientUnlocks.alice = { ext = true, wt1 = true }
W.invalidate()
opts = context({ card })
check(opts[1].notAvailable, "兩格都已開啟：選項停用")
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

-- ===== 取得方式視窗（2026-10-15）：面板的按鈕排在功能清單後面、點「需要 X 模組」的膠囊選到那個模組、齒輪設定的入口；
-- 開放程度 1 或框架沒有 NavList 時都不出現，開著的視窗自己關掉 =====
;(function() -- 自己的函式作用域：主程式的 local 已接近 Lua 上限 200
    local UI = F.installUI(17)
    for _, k in ipairs({ "navList", "scrollPanel", "textWrap" }) do UI.CAPABILITIES[k] = true end
    UI.Text = { wrap = function(s) return { s } end, fit = function(s) return s end }
    local Widget = Element:derive("FakeGuideWidget")
    function Widget:contentWidth() return self.width - 12 end
    function Widget:scrollTo(el) self.scrolledTo = el end
    function Widget:setYScroll(v) self.yscroll = v end
    function Widget:setSelected(id, silent)
        self.selected = id
        if not silent and self.onSelect then self.onSelect(nil, id, self) end
    end
    function Widget:getSelected() return self.selected end
    local function widget(o)
        local e = Element.new(Widget, o.x or 0, o.y or 0, o.width or 100, o.height or 100)
        for k, v in pairs(o) do if e[k] == nil then e[k] = v end end
        return e
    end
    UI.ScrollPanel, UI.NavList = { new = widget }, { new = widget }
    F.load("client/MinidoracatWatch_Guide.lua")
    local G = MinidoracatWatchGuide
    check(G.available(), "框架 rev 17＋NavList、開放程度 2：視窗開得了")
    C.openPanel(0, watch)
    local pg = F.lastPanel
    pg:update()
    local gb, last = pg.btnGuide, pg.feats[#pg.feats]
    check(gb.visible and (gb.y > last.y or gb.x >= last.x + last.w), "面板：「取得方式」按鈕排在最後一個膠囊後面")
    local inTargets = false
    for _, t in ipairs(pg:keyboardTargets()) do if t == gb then inTargets = true end end
    check(inTargets, "按鈕是框架按鈕：鍵盤與手把的焦點走得到")
    local need = nil
    for _, f in ipairs(pg.feats) do if f.need and not need then need = f end end
    check(need and need.tip and need.tip:find("Acquire_More", 1, true), "膠囊說明最後一句：按一下看完整的取得方式")
    pg:onMouseDown(need.x + 2, need.y + 2)
    pg:onMouseUp(need.x + 2, need.y - 200)
    check(G.win == nil, "在膠囊按下、移開才放開：不打開")
    pg:onMouseDown(need.x + 2, need.y + 2)
    pg:onMouseUp(need.x + 2, need.y + 2)
    local want = W.modules[need.need].item
    check(G.win ~= nil and G.current == want and G.nav.selected == want, "點膠囊：打開取得方式視窗、選到缺的模組")
    local n, groups = 0, G.nav.groups
    for _, g in ipairs(groups) do n = n + #g.items end
    check(#groups == 6 and n == 24 and groups[6].items[1].id == W.BATTERY_TYPE, "左欄：六組 24 樣，最後是電池")
    local function texts(t)
        local out = {}
        for _, o in ipairs((G.layout(t, 300))) do if o.text then out[#out + 1] = o.text end end
        return table.concat(out, "\n")
    end
    local ecoText = texts(MOD("Eco"))
    check(not ecoText:find("Tier_", 1, true) and ecoText:find("Guide_NoteMethods", 1, true)
        and ecoText:find("Guide_ZombieNone", 1, true) and ecoText:find("Guide_CraftNone", 1, true),
        "開放程度 2：不寫稀有度、寫這台伺服器不公開機率；節能核心殭屍不帶、不能製作")
    SB.AcquireGuide = 3
    W.clientLists.drops, W.clientLists.dropCap = { { group = "police", item = "mod:comm", chance = 2 } }, 1
    local commText = texts(MOD("Comm"))
    check(texts(MOD("Eco")):find("Tier_veryRare", 1, true) and commText:find("Guide_Pct|2", 1, true)
        and commText:find("Guide_NoteCap|1", 1, true) and commText:find("Guide_NoteTier", 1, true),
        "開放程度 3：稀有度、每隻的機率、每隻上限")
    gb:forceClick()
    check(G.win ~= nil and G.win.onTop and G.current == want, "開著時再按「取得方式」：同一個視窗拉到最上面")
    local action = MinidoracatWatchSound.SECTION.actions[1]
    check(action.enabled() == true and action.label == "IGUI_MinidoracatWatch_Guide_Open", "齒輪設定「地圖錶」分類：查看取得方式")
    SB.AcquireGuide = 1
    F.now = F.now + 1000
    pg.scanAt = nil
    pg:update()
    check(not pg.btnGuide.visible and action.enabled() == false, "開放程度 1：面板按鈕與齒輪入口都不出現")
    G.win:update()
    check(G.win == nil, "開放程度 1：開著的取得方式視窗自己關掉")
    pg:onMouseDown(need.x + 2, need.y + 2)
    pg:onMouseUp(need.x + 2, need.y + 2)
    check(G.win == nil, "開放程度 1：點膠囊也不開")
    SB.AcquireGuide, W.clientLists.drops, W.clientLists.dropCap = nil, nil, nil
    C.closePanel()
    UI.CAPABILITIES.navList = false
    F.reset()
    check(not G.available() and not G.available(), "框架沒有 NavList：開不了")
    local logs = 0
    for _, l in ipairs(F.logs) do if l:find("no acquisition guide window", 1, true) then logs = logs + 1 end end
    check(logs == 1, "框架太舊：只 log 一次")
    F.installUI(15)
end)()

-- ===== UI 框架版本不足：不登記、不出錯 =====
F.installUI(13)
F.dockSpec = nil
F.reset()
F.load("client/MinidoracatWatch_Client.lua")
check(MinidoracatWatchClient.docked == false and F.dockSpec == nil, "rev 13（沒有 battery 圖示）：不登記 Dock")
MinidoracatUI = nil
F.load("client/MinidoracatWatch_Client.lua")
check(MinidoracatWatchClient.docked == false, "沒有 UI 框架：照樣載入")

-- ===== 單人設定的通知（2026-10-22）：這次載入改了值，進遊戲後跳一次 Toast（停 10 秒），只列改了的那幾類 =====
do
    F.installUI(15) -- 上一段把框架拿掉了
    local body = C.soloText({ "SlotExt", "MinimapRule", "SlotWt2", "LootCards" })
    local a, b, c = body:find("Solo_Minimap", 1, true), body:find("Solo_Slots", 1, true), body:find("Solo_Cards", 1, true)
    check(body:find("IGUI_MinidoracatWatch_Solo_Body|", 1, true) == 1 and a and b and c and a < b and b < c
        and select(2, body:gsub("Solo_Slots", "")) == 1, "通知內文：小地圖、槽位、解鎖卡照固定順序，槽位只寫一次")
    check(not C.soloText({ "SlotAdv" }):find("Solo_Minimap", 1, true), "只改了槽位：不寫小地圖")
    local shown = {}
    local realShow = C.ui().Toast.show
    C.ui().Toast.show = function(o) shown[#shown + 1] = o end
    W.soloApplied = { "MinimapRule" }
    C.soloStart()
    F.fire("OnTick")
    F.fire("OnTick")
    check(#shown == 1 and shown[1].holdMs == 10000 and shown[1].title == "IGUI_MinidoracatWatch_Solo_Title"
        and shown[1].message:find("Solo_Minimap", 1, true) ~= nil and W.soloApplied == nil,
        "改了值：進遊戲跳一次、停 10 秒，之後不再跳")
    shown = {}
    C.soloStart()
    F.fire("OnTick")
    check(#shown == 0, "沒改任何值：不跳")
    C.ui().Toast.show = realShow
end

F.finish("test_watch_client")
