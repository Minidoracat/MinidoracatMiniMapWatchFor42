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
C.gateActive = false
check(C.lookState(0) == nil, "閘門沒註冊成功（主 MOD 太舊）：小地圖其實開著，不算看錶模式")
C.gateActive = true
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
local function step() F.engineUpdate(p) end -- 引擎一幀
Look.toggle(p)
local a = queue()[1]
check(#queue() == 1 and a.Type == A.Type and a.character == p and a.pn == 0, "觸發：排進看錶動作")
check(a.maxTime == -1 and a.stopOnWalk == false and a.stopOnRun == true and a.stopOnAim == true
    and a.useProgressBar == false, "動作：不會自己結束、走路不中斷、跑步與瞄準中斷、不畫進度條")
check(rawget(A, "complete") == nil and rawget(A, "perform") == nil and rawget(A, "stop") == nil,
    "只在客戶端跑：不定義 complete；不靠 perform／stop 收尾")
check(a.action ~= nil and a.action.started == true, "佇列是空的：馬上開始")
check(#a.poseCalls == 1 and a.poseCalls[1] == "anim:MinidoracatWatch_LookL" and a.hands == nil,
    "姿勢：戴左手錶抬左手腕；空手不覆寫持物")
local function poseOf(who, pn)
    local r = setmetatable({ pn = pn, character = who }, A)
    W.invalidate()
    Look.pose(r)
    return r
end
local torch = F.item("Base.HandTorch")
bob.secondary = torch
local posed = poseOf(bob, 1)
check(posed.poseCalls[1] == "hands" and posed.poseCalls[2] == "anim:MinidoracatWatch_LookR", "姿勢：先設持物再設節點；戴右手錶，抬右手腕")
check(posed.hands[1] == nil and posed.hands[2] == torch, "手上的東西照舊拿著：不是武器的持物引擎會藏，用實際拿的覆寫回去")
bob.primary = torch
posed = poseOf(bob, 1)
check(posed.hands[1] == torch and posed.hands[2] == nil, "兩手拿同一件：只傳一次（傳兩次，別的玩家會看到兩件）")
local bat = F.item("Base.BaseballBat")
bat._class = "HandWeapon"
bob.primary = bat
check(poseOf(bob, 1).hands == nil, "有武器：引擎本來就不藏，不覆寫（雙手握的武器在別的玩家畫面不會變兩支）")
bob.primary, bob.secondary = nil, nil
local empty = { getPrimaryHandItem = function() end, getSecondaryHandItem = function() end }
check(poseOf(empty, 7).poseCalls[1] == "anim:MinidoracatWatch_LookL", "姿勢：找不到錶時用左手")
ok, reason, dist, how = gate()
check(C.lookActive(0) == true and ok == true and how == nil, "動作開始：正在看、小地圖放行")
check(a:isValid() == true, "isValid 回布林 true")
p.asleep = true
check(a:isValid() == false, "睡著：動作失效")
p.asleep = nil
step()
check(C.lookActive(0) == true and #queue() == 1, "佇列只有它：繼續看")
p.aiming, p.vehicle = true, {}
step()
check(#queue() == 0 and C.lookActive(0) == false, "在車上瞄準（引擎不會停動作）：自己停")
p.vehicle = nil
Look.toggle(p)
check(#queue() == 1, "走路瞄準中按看錶：照常排進去")
step()
check(#queue() == 0 and C.lookActive(0) == false, "走路瞄準：引擎停掉（stopOnAim）")
p.aiming = nil
-- 排了別的動作：讓路，而且後面的動作真的開始
local Later = ISBaseTimedAction:derive("Later")
function Later:isValid() return true end
function Later:start() self.starts = (self.starts or 0) + 1 end
local function later(aimOk) -- aimOk＝瞄準時也能做的動作（裝彈、喝水）
    local l = ISBaseTimedAction.new(Later, p)
    if aimOk then l.stopOnAim = false end
    ISTimedActionQueue.add(l)
    return l
end
Look.toggle(p)
local nxt = later()
check(nxt.starts == nil and C.lookActive(0) == true, "排了別的動作：這一幀還在看")
step()
check(#queue() == 1 and queue()[1] == nxt and nxt.starts == 1 and C.lookActive(0) == false, "排了別的動作：讓路，下一個動作開始")
ISTimedActionQueue.clear(p)
-- 後面已經排了動作、還沒輪到讓路就按停止（同一幀按兩次）：只結束看錶一次，後面的照做、不會重開看錶
Look.toggle(p)
nxt = later()
Look.toggle(p)
Look.toggle(p)
check(#queue() == 2 and Look.index(p) == 1, "按停止：請引擎結束，這一幀還在佇列")
step()
check(#queue() == 1 and queue()[1] == nxt and nxt.starts == 1, "同一幀按兩次停止：只停看錶，後面的動作開始一次")
step()
check(#queue() == 1 and nxt.starts == 1, "下一幀：後面的動作照跑")
ISTimedActionQueue.clear(p)
-- 排在別的動作後面，輪到時已經不能看：只跳過自己。後面是被打斷後接回來的動作（進食）時，它的進度不能被歸零
local first = later()
Look.toggle(p)
check(Look.index(p) == 2, "別的動作進行中：看錶排在後面")
nxt = later()
nxt.relaunchWithDelta, nxt.action = true, F.javaAction(nxt, 0.5)
W.setCharge(watch, 0)
W.invalidate()
first:forceComplete()
step()
check(Look.index(p) == 1 and queue()[1].poseCalls == nil and C.lookActive(0) == false and gate() == false and nxt.starts == nil,
    "輪到看錶時錶沒電：當成空動作，不擺姿勢、不開小地圖")
step()
check(#queue() == 1 and queue()[1] == nxt and nxt.starts == 1 and nxt:getJobDelta() == 0.5,
    "下一幀：跳過看錶，後面的動作開始，接回來的進度還在")
W.setCharge(watch, 1)
W.invalidate()
ISTimedActionQueue.clear(p)
-- 同一件事，玩家走路瞄準著：空動作不能被引擎的瞄準中斷停掉（停掉＝整列清掉）
first = later(true)
Look.toggle(p)
nxt = later(true)
W.setCharge(watch, 0)
W.invalidate()
p.aiming = true
first:forceComplete()
step()
step()
check(#queue() == 1 and queue()[1] == nxt and nxt.starts == 1, "走路瞄準中輪到沒電的看錶：只跳過自己，後面的動作照做")
p.aiming = nil
W.setCharge(watch, 1)
W.invalidate()
ISTimedActionQueue.clear(p)
-- 開關門這類「做完要接回被打斷動作」的中斷者進行中：這一下不排看錶。排了會夾在中間，接回的動作（吃飽時的吸菸，
-- isValidStart 為假）失去原版只給下一個動作的起始檢查豁免，整列被清掉
local Resume = ISBaseTimedAction:derive("Resume")
function Resume:isValid() return true end
function Resume:isValidStart() return false end
function Resume:start() self.starts = (self.starts or 0) + 1 end
local door, smoke = later(), ISBaseTimedAction.new(Resume, p)
door.retriggerLastAction, smoke.action = true, F.javaAction(smoke, 0.5)
p.retrigger = smoke.action
Look.toggle(p)
check(Look.index(p) == -1 and #queue() == 1, "中斷者進行中按看錶：不排")
door:forceComplete()
step()
step()
check(#queue() == 1 and queue()[1] == smoke and smoke.starts == 1 and smoke:getJobDelta() == 0.5,
    "中斷者做完：被打斷的動作接回來，進度還在")
ISTimedActionQueue.clear(p)

-- 引擎不通知 Lua 就丟掉動作（StartAction 清空清單）：下一次問就不算在看
Look.toggle(p)
check(C.lookActive(0) == true, "（重新開始看）")
p.actions = {}
check(C.lookActive(0) == false and C.lookAction[0] == nil and gate() == false, "引擎丟掉動作：不算在看、紀錄清掉")
-- 換了角色物件（死亡重生）
ISTimedActionQueue.clear(p)
Look.toggle(p)
a = queue()[1]
check(C.lookActive(0) == true, "（重新開始看）")
a.character = F.player("ghost", 5)
check(C.lookActive(0) == false, "動作的角色不是現在這位玩家：不算在看")
a.character = p
ISTimedActionQueue.clear(p)

-- isValid：脫錶、沒電、規則改掉都停
Look.toggle(p)
a = queue()[1]
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
W.setCharge(watch, 0)
W.invalidate()
step()
check(#queue() == 0 and C.lookActive(0) == false, "看到一半沒電：下一幀停止")
W.setCharge(watch, 1)
W.invalidate()

-- 再觸發一次＝停
Look.toggle(p)
check(C.lookActive(0) == true, "（重新開始看）")
Look.toggle(p)
step()
check(#queue() == 0 and C.lookActive(0) == false and gate() == false, "正在看時再觸發：停止、小地圖收起")
-- 坐在地上：動作要等角色坐好才開始。這時按停止，引擎之後開始動作時會把 forceComplete 清掉，也不能讓看錶開始
local sitting, baseWait = true, ISBaseTimedAction.waitToStart
ISBaseTimedAction.waitToStart = function() return sitting end
Look.toggle(p)
a = queue()[1]
check(a.action.started == nil and C.lookActive(0) == false, "坐在地上：動作還在等開始，不算在看")
Look.toggle(p)
sitting = false
step()
check(#queue() == 0 and C.lookActive(0) == false and a.poseCalls == nil, "還在等開始時按停止：之後不會開始看")
ISBaseTimedAction.waitToStart = baseWait
-- 排在別的動作後面：再觸發只取消它
local other = F.action(ISWearClothing, p, watch)
ISTimedActionQueue.add(other)
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
step()
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
step()
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
panel:update()
check(b.title == "IGUI_MinidoracatWatch_Look_Stop" and b.active == true and b.enable, "正在看：按鈕亮起、寫停止看錶")
b:forceClick()
step()
panel:update()
check(#queue() == 0 and b.active == false, "面板按鈕：停止")
W.setCharge(watch, 0)
W.invalidate()
panel:update()
check(b.visible and not b.enable, "沒電：按鈕停用")
-- 底部按鈕排不下時（這裡的假按鈕用翻譯鍵當標題，一定排不下）：文字自己一列，按鈕全部留在面板裡、在文字下面
local inside = panel.footTextW == panel.width - 28
for _, fb in ipairs(panel.footBtns) do
    if fb.visible and (fb.x < 14 or fb.x + fb.width > panel.width - 14 or fb.y < panel.footTextY + 16
            or fb.y + fb.height > panel.height) then
        inside = false
    end
end
check(inside, "底部按鈕放不下：換到文字下面，都在面板裡")
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
