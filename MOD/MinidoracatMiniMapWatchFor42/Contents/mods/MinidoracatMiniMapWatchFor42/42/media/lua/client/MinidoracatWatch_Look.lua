-- MinidoracatWatch_Look.lua（client）：「看錶」動作。小地圖規則是「看錶時才顯示」（沙盒 MinimapRule 4，或玩家自己勾
-- 「只在看錶時顯示小地圖」）時，角色做這個動作期間才有小地圖；閘門在 _Client 的 C.gate，用 C.lookActive 問。
-- 動作不會自己結束（maxTime -1，BaseAction.java:116）。結束的方式：再觸發一次、跑步、瞄準（車上也算）、排了別的動作、
-- 脫錶、沒電、睡著。走路與開車不中斷（使用者 2026-11-24 裁定）。只在客戶端跑、不定義 complete（理由同 _Action.lua 檔頭；這個動作
-- 不改任何狀態，伺服器不必知道）。其他玩家看得到姿勢：動作子狀態與動畫變數由引擎同步（PlayerActionsState.java:128-146）。
-- 入口三個：快捷鍵（綁定在 _LightClient 的 OnGameBoot，同一個分組）、錶的右鍵選單、面板按鈕（_Panel）。
-- 不是這個模式時三個入口都不出現、不作用（C.lookState 回 nil）。
require "TimedActions/ISBaseTimedAction"
require "MinidoracatWatch"
require "MinidoracatWatch_Client"
local W = MinidoracatWatchCore
local C = MinidoracatWatchClient
local Look = {}
MinidoracatWatchLook = Look -- 內部表（_Panel、測試與 E2E 用），不是公開 API

ISMinidoracatWatchLookAction = ISBaseTimedAction:derive("ISMinidoracatWatchLookAction")
local A = ISMinidoracatWatchLookAction

-- 姿勢只在這裡決定：自製的看錶節點（scripts/look_anim.py 產生；姿勢、遮罩與權重的理由寫在那裡），抬起戴著生效那支錶
-- （C.watchOf，和閘門同一個來源）的手腕。setActionAnim(String) 設 PerformingAction（BaseAction.java:265-280），節點條件就是它；
-- 同名節點在 AnimSets/player（站、走）與 player-vehicle（座位）各一份，跟原版 Bandage 等動作一樣由角色當下的
-- AnimSet 挑。錶的物品類型固定分左右（MapWatch_*_Left／_Right），戴在哪個部位都一樣；找不到錶時用左手。
-- 手上的東西照舊拿著：計時動作期間，兩手都不是武器時引擎會把持物藏起來（PlayerActionsState.java:40-47、
-- ModelManager.java:630-634），用角色實際拿的東西覆寫回去（:650-666）；要在 setActionAnim 之前設好（多人進入動作狀態時讀）。
-- 有武器時引擎本來就不藏，不覆寫：覆寫會以模型名傳給其他玩家（PlayerActionsState.java:112-114），雙手握的同一件
-- 在別人畫面變成兩件、槍的配件不見。兩手是同一件時只傳一次。
function Look.pose(action)
    local p = action.character
    local a, b = p:getPrimaryHandItem(), p:getSecondaryHandItem()
    if (a or b) and not (instanceof(a, "HandWeapon") or instanceof(b, "HandWeapon")) then
        action:setOverrideHandModels(a, a ~= b and b or nil)
    end
    local w = C.watchOf(action.pn)
    local side = (w and w:getFullType():sub(-6) == "_Right") and "R" or "L"
    action:setActionAnim("MinidoracatWatch_Look" .. side)
end

-- 每幀被問（IsoGameCharacter.java:9176）：脫錶、沒電、模式關掉、睡著，下一幀就停
-- （睡覺：單人與伺服器由引擎清動作，多人客戶端不清，IsoGameCharacter.java:9091,9118-9122，所以自己查）
function A:isValid() return self.skip or (C.lookState(self.pn) == true and not self.character:isAsleep()) end

-- 輪到時已經不能看（排隊期間脫錶、沒電、規則改了）：當成空動作開始（skip），start 馬上請引擎結束它，下一幀
-- 佇列照原版的路換下一個。照常開始的話引擎不啟動它，佇列發現第一個動作不在引擎清單就整列清掉
-- （ISTimedActionQueue.lua:117-125），排在後面的動作跟著沒了；也不能在這裡自己呼叫 onCompleted：這時就在原版
-- onCompleted 裡面，它回去後會把這個動作的進度寫到下一個動作上（:77-95，進食到一半被打斷再接回來的會歸零）。
-- 空動作不因跑步、瞄準中斷：引擎先處理玩家輸入才更新動作（IsoPlayer.java:2074-2080,2400-2402），被它停掉＝整列清掉；
-- 這兩個欄位在建 Java 動作時讀（LuaTimedActionNew.java:38-55），所以在 begin 之前改。
function A:begin()
    self.skip = not self:isValid() or nil
    if self.skip then self.stopOnRun, self.stopOnAim = false, false end
    ISBaseTimedAction.begin(self)
end

function A:start()
    if self.skip then return self:forceComplete() end
    Look.pose(self)
    C.lookAction[self.pn] = self
end

-- 排了別的動作就讓路：這個動作不會結束，不讓路的話後面的動作永遠輪不到。
-- 瞄準自己查：走路時引擎會停（stopOnAim），車上那條更新路徑只設瞄準狀態、不停動作（IsoPlayer.java:4396-4446）
function A:update()
    if self.character:isAiming() or #ISTimedActionQueue.getTimedActionQueue(self.character).queue > 1 then
        self:forceComplete()
    end
end

function A:new(character)
    local o = ISBaseTimedAction.new(self, character)
    o.pn = character:getPlayerNum()
    o.maxTime = -1
    o.stopOnWalk, o.stopOnRun, o.stopOnAim = false, true, true
    o.useProgressBar = false -- 沒有終點的動作不畫進度條（LuaTimedActionNew.java:62-64）
    return o
end

-- 看錶動作在佇列的第幾個：1＝正在做，>1＝排在別的動作後面，-1＝沒有（ISTimedActionQueue.lua:30-37）
function Look.index(player)
    return ISTimedActionQueue.getTimedActionQueue(player):indexOfType(A.Type)
end

-- 開始或停止。正在做＝停（只結束這個動作，排在後面的照做）；排隊中＝取消；不是這個模式＝沒反應；沒錶、沒電＝提示原因
function Look.toggle(player)
    local queue = ISTimedActionQueue.getTimedActionQueue(player)
    local i = queue:indexOfType(A.Type)
    if i == 1 then
        -- 佇列第 1 個已經交給引擎（addToQueue 同步 begin，ISTimedActionQueue.lua:9-17）。先標成 skip：它還在等開始時
        -- （坐在地上，BaseAction.java:97-102），引擎的 start 會把 forceComplete 清掉（:133-135），靠 A:start 再結束一次
        local a = queue.queue[1]
        a.skip = true
        a:forceComplete()
        return
    end
    if i > 1 then
        queue:removeFromQueue(queue.queue[i])
        return
    end
    -- 佇列正在跑「做完要接回被打斷動作」的中斷者（原版只有開關門，ISTimedActionQueue.lua:60-75）：這一下不排。
    -- 排了會夾在中斷者與接回的動作之間，接回的動作就失去原版給它的 isValidStart 豁免（吃飽時接回吸菸會被整列清掉）
    local cur = queue.current
    if cur and cur.retriggerLastAction and player:getTimedActionToRetrigger() then return end
    local ok, reason = C.lookState(player:getPlayerNum())
    if ok == nil then return end
    if not ok then
        W.notify(player, reason)
        return
    end
    ISTimedActionQueue.add(A:new(player))
end

-- ===== 快捷鍵（玩家 0；手把與分割畫面的其他玩家用面板按鈕或右鍵選單）=====
Events.OnKeyPressed.Add(function(key)
    if key == 0 or key ~= getCore():getKey("MinidoracatWatch_Look") then return end
    local p = getSpecificPlayer(0)
    if p and not p:isDead() and not p:isAsleep() then Look.toggle(p) end
end)

-- ===== 錶的右鍵：戴著、生效的那支 =====
local function onLook(_, pn)
    local p = getSpecificPlayer(pn)
    if p then Look.toggle(p) end
end
Events.OnFillInventoryObjectContextMenu.Add(function(pn, context, items)
    local player = getSpecificPlayer(pn)
    if not player then return end
    local state = C.lookState(pn)
    if state == nil then return end
    local watch = C.watchOf(pn)
    if not watch then return end
    for _, v in ipairs(items) do
        local item = v
        if not instanceof(v, "InventoryItem") then item = v.items and v.items[1] end
        if item and item:getID() == watch:getID() then
            local queued = Look.index(player) ~= -1
            local opt = context:addOption(getText(queued and "IGUI_MinidoracatWatch_Look_Stop" or "IGUI_MinidoracatWatch_Look_Start"),
                item, onLook, pn)
            if not queued and not state then opt.notAvailable = true end
            return
        end
    end
end)

-- ===== 提示怎麼看錶 =====
-- 每次進遊戲、每位本機玩家一次：第一次處在「看了就有畫面」的狀態時跳 Toast（管理員中途改成這個規則，在線玩家也會收到）。
-- 玩家 0 且快捷鍵有綁：寫鍵名；其他寫面板按鈕與右鍵選單。
local POLL_MS = 1000
local lastPoll = nil
local hinted = {}
function Look.hintText(pn)
    local key = pn == 0 and getCore():getKey("MinidoracatWatch_Look") or 0
    if key and key ~= 0 then return getText("IGUI_MinidoracatWatch_Look_Hint", Keyboard.getKeyName(key)) end
    return getText("IGUI_MinidoracatWatch_Look_HintNoKey")
end
function Look.poll()
    local now = getTimestampMs()
    if lastPoll and now >= lastPoll and now - lastPoll < POLL_MS then return end
    lastPoll = now
    for pn = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(pn)
        if p and not p:isDead() and not hinted[pn] and C.lookState(pn) == true then
            hinted[pn] = true
            C.toast(p, Look.hintText(pn), getText("IGUI_MinidoracatWatch_Look_HintTitle"), 8000)
        end
    end
end
Events.OnTick.Add(Look.poll)
