-- 看錶時才顯示小地圖：生效的規則（沙盒規則 × 玩家選項）、閘門（沒在看／正在看／沒錶／沒電、第 4 個回傳值只在這個模式
-- 被擋時是 "hide"）、正在看錶的判定（引擎不通知就丟掉動作、換了角色）、看錶動作（欄位、姿勢順序、isValid、讓路）、
-- 三個入口（快捷鍵、右鍵、面板按鈕；不是這個模式時都不出現不作用）、提示、節能核心說明。
-- 用法（repo 根目錄）：lua scripts/test_watch_look.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check = F.check
F.mode = "client"

F.keys = {}
function getCore()
    return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end,
        getKey = function(_, name) return F.keys[name] end, isKey = function() return false end }
end
KeybindId = { LIGHT_SOURCE = "LIGHT_SOURCE", TOGGLE_VEHICLE_HEADLIGHTS = "TOGGLE_VEHICLE_HEADLIGHTS" }
keyBinding = {}
Keyboard.KEY_SCROLL, Keyboard.KEY_0 = 70, 11 -- LWJGL 鍵碼（org/lwjglx/input/KeyCodes.java）
Keyboard.getKeyName = function(k) return "key" .. tostring(k) end
function getTextManager()
    return { MeasureStringX = function(_, _, s) return #s * 7 end, getFontHeight = function() return 16 end }
end
local Menu = {}
Menu.__index = Menu
local function newMenu() return setmetatable({ options = {} }, Menu) end
function Menu:addOption(name, target, fn, a, b, c, d)
    local o = { name = name, target = target, fn = fn, a = a, b = b, c = c, d = d }
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
F.installUI(15)

require "MinidoracatWatch"
local W = MinidoracatWatchCore
local SB = SandboxVars.MinidoracatWatch
local p = F.player("alice", 0)
local registered = {}
MinidoracatMiniMapAPI = { featureApiVersion = 2, registerFeatureGate = function(_, fn) registered.fn = fn; return true end }
require "MinidoracatWatch_Client"
F.load("client/MinidoracatWatch_LightClient.lua")
F.load("client/MinidoracatWatch_Look.lua")
F.load("client/MinidoracatWatch_Panel.lua")
local C, Snd, Look, A = MinidoracatWatchClient, MinidoracatWatchSound, MinidoracatWatchLook, ISMinidoracatWatchLookAction
C.registerGate()
local function gate() W.invalidate(); return registered.fn(0, "minimap", "mini") end
local function queue() return ISTimedActionQueue.getTimedActionQueue(p).queue end
local function lookOpts(items)
    local ctx, out = newMenu(), {}
    W.invalidate()
    F.fire("OnFillInventoryObjectContextMenu", 0, ctx, items)
    for _, o in ipairs(ctx.options) do if o.name:find("_Look_", 1, true) then out[#out + 1] = o end end
    return out
end
local function tick() F.now = F.now + 1500; F.fire("OnTick") end
local HINT = "IGUI_MinidoracatWatch_Look_Hint"

-- ===== 不是這個模式（預設規則 2）：入口都不出現、不作用 =====
local watch = F.item(F.LEFT)
p.inv:AddItem(watch)
F.wear(p, watch)
W.invalidate()
F.reset()
tick()
check(C.minimapRule() == W.RULE_WATCH and C.lookState(0) == nil and #F.toasts == 0, "規則 2：不是看錶模式、不提示")
Look.toggle(p)
check(#queue() == 0 and #F.halos == 0, "規則 2：觸發看錶沒有反應")
check(#lookOpts({ watch }) == 0, "規則 2：錶的右鍵沒有看錶")
local ok, reason, dist, how = gate()
check(ok == true and how == nil, "規則 2 戴著錶：放行")

-- ===== 生效的規則：沙盒規則 × 玩家選項 =====
local function rule(sandbox, own)
    SB.MinimapRule, Snd.lookOnly = sandbox, own
    return C.minimapRule()
end
check(rule(1, false) == W.RULE_FREE and rule(2, false) == W.RULE_WATCH and rule(3, false) == W.RULE_OFF
    and rule(4, false) == W.RULE_LOOK, "玩家沒勾：照伺服器規則")
check(rule(1, true) == W.RULE_LOOK and rule(2, true) == W.RULE_LOOK, "玩家勾了：不需要錶、戴錶才能用都變成看錶時才顯示")
check(rule(3, true) == W.RULE_OFF and rule(4, true) == W.RULE_LOOK, "玩家勾了：伺服器關閉小地圖照樣關閉")
SB.Enabled = false
check(C.lookState(0) == nil and gate() == true, "地圖錶停用：勾了也沒有看錶模式、小地圖照舊開放")
SB.Enabled = true
SB.MinimapRule, Snd.lookOnly = 1, true
ok, reason, dist, how = gate()
check(ok == false and reason == W.REASON_LOOK and how == "hide", "伺服器不需要錶、玩家自己勾：沒在看就擋")
Snd.lookOnly = false
check(gate() == true, "玩家取消勾選：恢復")

-- ===== 閘門：規則 4 =====
SB.MinimapRule = 4
ok, reason, dist, how = gate()
check(ok == false and reason == W.REASON_LOOK and dist == nil and how == "hide", "規則 4 沒在看：擋、請主 MOD 收起視窗")
check(C.lookState(0) == true, "戴著有電的錶：看了就有畫面")
F.unwear(p, watch)
ok, reason, dist, how = gate()
check(ok == false and reason == W.REASON_NO_WATCH and how == "hide" and select(2, C.lookState(0)) == W.REASON_NO_WATCH
    and C.lookState(0) == false, "規則 4 沒戴錶：擋（原因是沒戴錶）、一樣收起")
F.wear(p, watch)
W.setCharge(watch, 0)
ok, reason, dist, how = gate()
check(ok == false and reason == W.REASON_DEAD and how == "hide" and C.lookState(0) == false, "規則 4 沒電：擋（原因是沒電）")
SB.DeadMode = 2
ok, reason = gate()
check(ok == false and reason == W.REASON_LOOK and C.lookState(0) == true, "沒電時保留小地圖：還是要看錶才有")
SB.DeadMode = nil
W.setCharge(watch, 1)
for _, r in ipairs({ 2, 3 }) do
    SB.MinimapRule = r
    F.unwear(p, watch)
    ok, reason, dist, how = gate()
    check(ok == false and how == nil, "規則 " .. r .. " 被擋：沒有第 4 個回傳值（照舊畫無訊號）")
    F.wear(p, watch)
end
SB.MinimapRule = 4

-- ===== 提示：第一次處在看了就有畫面的狀態時一次 =====
F.reset()
F.toasts = {}
F.keys.MinidoracatWatch_Look = 11
W.invalidate()
tick()
check(#F.toasts == 1 and F.toasts[1] == HINT .. "|key11", "規則 4：提示一次、寫出綁定的鍵")
tick()
check(#F.toasts == 1, "之後不再提示")
local bob = F.player("bob", 1)
local bw = F.item(F.RIGHT)
bob.inv:AddItem(bw)
tick()
check(#F.toasts == 1, "第二位本機玩家沒戴錶：先不提示")
F.wear(bob, bw)
W.invalidate()
tick()
check(#F.toasts == 2 and F.toasts[2] == HINT .. "NoKey", "第二位本機玩家：快捷鍵不是他的，提示面板按鈕與右鍵")
F.keys.MinidoracatWatch_Look = 0
check(Look.hintText(0) == HINT .. "NoKey", "玩家 0 沒綁鍵：提示面板按鈕與右鍵")
F.keys.MinidoracatWatch_Look = 11

-- ===== 看錶動作 =====
F.reset()
Look.toggle(p)
local a = queue()[1]
check(#queue() == 1 and a.Type == A.Type and a.character == p and a.pn == 0, "觸發：排進看錶動作")
check(a.maxTime == -1 and a.stopOnWalk == false and a.stopOnRun == true and a.stopOnAim == true
    and a.useProgressBar == false, "動作：不會自己結束、走路不中斷、跑步與瞄準中斷、不畫進度條")
check(rawget(A, "complete") == nil and rawget(A, "perform") == nil and rawget(A, "stop") == nil,
    "只在客戶端跑：不定義 complete；不靠 perform／stop 收尾")
check(C.lookActive(0) == false and gate() == false, "排進佇列還沒開始：不算在看")
F.startAction(p)
check(a.poseCalls[1] == "var:ReadType=photo" and a.poseCalls[2] == "anim:Read" and a.poseCalls[3] == "hands",
    "姿勢：先設動畫變數再設動作動畫（才會同步給其他玩家）、空手")
ok, reason, dist, how = gate()
check(C.lookActive(0) == true and ok == true and how == nil, "動作開始：正在看、小地圖放行")
check(a:isValid() == true, "isValid 回布林 true")
a:update()
check(a.forced == nil, "佇列只有它：繼續看")
ISTimedActionQueue.add(F.action(ISWearClothing, p, watch))
a:update()
check(a.forced == true, "排了別的動作：讓路")
table.remove(queue(), 2)

-- 引擎不通知 Lua 就丟掉動作（StartAction 清空清單）：下一次問就不算在看
p.actions = {}
check(C.lookActive(0) == false and C.lookAction[0] == nil and gate() == false, "引擎丟掉動作：不算在看、紀錄清掉")
-- 換了角色物件（死亡重生）
ISTimedActionQueue.clear(p)
Look.toggle(p)
a = F.startAction(p)
check(C.lookActive(0) == true, "（重新開始看）")
a.character = F.player("ghost", 5)
check(C.lookActive(0) == false, "動作的角色不是現在這位玩家：不算在看")
a.character = p
ISTimedActionQueue.clear(p)

-- isValid：脫錶、沒電、規則改掉都停
Look.toggle(p)
a = F.startAction(p)
F.unwear(p, watch)
W.invalidate()
check(a:isValid() == false, "脫錶：動作失效")
F.wear(p, watch)
W.setCharge(watch, 0)
W.invalidate()
check(a:isValid() == false, "沒電：動作失效")
W.setCharge(watch, 1)
SB.MinimapRule = 2
W.invalidate()
check(a:isValid() == false, "管理員把規則改掉：動作失效")
SB.MinimapRule = 4
W.invalidate()
check(a:isValid() == true, "（恢復）")

-- 再觸發一次＝停
Look.toggle(p)
check(#queue() == 0 and C.lookActive(0) == false and gate() == false, "正在看時再觸發：停止、小地圖收起")
-- 排在別的動作後面：再觸發只取消它
local other = ISTimedActionQueue.add(F.action(ISWearClothing, p, watch))
Look.toggle(p)
check(#queue() == 2 and Look.index(p) == 2, "別的動作進行中：看錶排在後面")
Look.toggle(p)
check(#queue() == 1 and queue()[1] == other, "排隊中再觸發：只取消看錶，進行中的動作不動")
ISTimedActionQueue.clear(p)

-- 沒錶、沒電時觸發：提示原因、不排動作
F.unwear(p, watch)
W.invalidate()
F.reset()
F.now = F.now + 5000
Look.toggle(p)
check(#queue() == 0 and #F.halos == 1 and F.halos[1].text == W.REASON_NO_WATCH, "沒戴錶觸發：提示沒戴錶、不排動作")
F.wear(p, watch)
W.invalidate()

-- ===== 快捷鍵 =====
F.fire("OnGameBoot")
local bound = nil
for _, b in ipairs(keyBinding) do if b.value == "MinidoracatWatch_Look" then bound = b.key end end
check(bound == 11, "按鍵綁定：預設 0（KEY_0）")
F.fire("OnKeyPressed", 11)
check(#queue() == 1, "按綁定的鍵：開始看錶")
F.fire("OnKeyPressed", 70)
F.fire("OnKeyPressed", 0)
check(#queue() == 1, "別的鍵、鍵碼 0：沒反應")
F.fire("OnKeyPressed", 11)
check(#queue() == 0, "再按一次：停止")
F.keys.MinidoracatWatch_Look = 0
F.fire("OnKeyPressed", 0)
check(#queue() == 0, "沒綁鍵時鍵碼 0 不觸發")
F.keys.MinidoracatWatch_Look = 11
p.dead = true
F.fire("OnKeyPressed", 11)
p.dead = nil
check(#queue() == 0, "死亡：按鍵沒反應")
p.asleep = true
F.fire("OnKeyPressed", 11)
p.asleep = nil
check(#queue() == 0, "睡覺中：按鍵沒反應")

-- ===== 右鍵 =====
local opts = lookOpts({ watch })
check(#opts == 1 and opts[1].name == "IGUI_MinidoracatWatch_Look_Start" and not opts[1].notAvailable, "錶的右鍵：看錶")
opts[1].fn(opts[1].target, opts[1].a)
check(#queue() == 1, "右鍵看錶：開始")
opts = lookOpts({ watch })
check(#opts == 1 and opts[1].name == "IGUI_MinidoracatWatch_Look_Stop", "正在看：右鍵變成停止看錶")
opts[1].fn(opts[1].target, opts[1].a)
check(#queue() == 0, "右鍵停止")
W.setCharge(watch, 0)
opts = lookOpts({ watch })
check(#opts == 1 and opts[1].notAvailable == true, "沒電：右鍵看錶停用")
W.setCharge(watch, 1)
local spare = F.item(F.RIGHT)
p.inv:AddItem(spare)
check(#lookOpts({ spare }) == 0 and #lookOpts({ F.item("Base.Battery") }) == 0, "沒戴的錶、其他物品：右鍵沒有看錶")

-- ===== 面板按鈕 =====
W.invalidate()
C.openPanel(0, nil)
local panel = C.panel()
panel:update()
local b = panel.btnLook
check(b and b.icon == "clock" and b.style == "chip" and b.visible and b.enable and b.active == false
    and b.title == "IGUI_MinidoracatWatch_Look_Start", "面板：看錶按鈕（chip），未啟用")
b:forceClick()
check(#queue() == 1, "面板按鈕：開始看錶")
F.startAction(p)
panel:update()
check(b.title == "IGUI_MinidoracatWatch_Look_Stop" and b.active == true and b.enable, "正在看：按鈕亮起、寫停止看錶")
b:forceClick()
panel:update()
check(#queue() == 0 and b.active == false, "面板按鈕：停止")
W.setCharge(watch, 0)
W.invalidate()
panel:update()
check(b.visible and not b.enable, "沒電：按鈕停用")
W.setCharge(watch, 1)
SB.MinimapRule = 2
W.invalidate()
panel:update()
check(not b.visible, "規則 2：面板沒有看錶按鈕")

-- ===== 節能核心說明：沒電保留小地圖在看錶模式也寫 =====
local function keeps()
    for _, l in ipairs(C.ecoLines()) do if l == "IGUI_MinidoracatWatch_EcoKeepsMap" then return true end end
    return false
end
SB.MinimapRule = 4
check(keeps(), "規則 4：節能核心寫沒電保留小地圖")
SB.MinimapRule = 1
check(not keeps(), "規則 1：用不到，不寫")
Snd.lookOnly = true
check(keeps(), "規則 1 但玩家自己勾了看錶模式：寫")
Snd.lookOnly = false
SB.MinimapRule = 2

F.finish("test_watch_look")
