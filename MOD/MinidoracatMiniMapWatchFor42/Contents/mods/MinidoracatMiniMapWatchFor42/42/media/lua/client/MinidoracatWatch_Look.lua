-- MinidoracatWatch_Look.lua（client）：「看錶」動作。小地圖規則是「看錶時才顯示」（沙盒 MinimapRule 4，或玩家自己勾
-- 「只在看錶時顯示小地圖」）時，角色做這個動作期間才有小地圖；閘門在 _Client 的 C.gate，用 C.lookActive 問。
-- 動作不會自己結束（maxTime -1，BaseAction.java:116）。結束的方式：再觸發一次、跑步、瞄準、排了別的動作、脫錶、沒電。
-- 走路與開車不中斷（使用者 2026-11-24 裁定）。只在客戶端跑、不定義 complete（理由同 _Action.lua 檔頭；這個動作
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

-- 姿勢只在這裡決定。動畫變數要在 setActionAnim 之前設：同步給其他玩家的封包在 setActionAnim 當下收集變數
-- （StatePacket.java:61-78；原版 ISReadABook.lua:146-156 同樣的順序）。
function Look.pose(action)
    action:setAnimVariable("ReadType", "photo") -- 原版沒有看錶的姿勢，借「看照片」（AnimSets/player/actions/photo.xml）
    action:setActionAnim(CharacterActionAnims.Read)
    action:setOverrideHandModels(nil, nil)
end

-- 每幀被問（IsoGameCharacter.java:9176）：脫錶、沒電、模式關掉，下一幀就停
function A:isValid() return C.lookState(self.pn) == true end

function A:start()
    Look.pose(self)
    C.lookAction[self.pn] = self
end

-- 排了別的動作就讓路：這個動作不會結束，不讓路的話後面的動作永遠輪不到
function A:update()
    if #ISTimedActionQueue.getTimedActionQueue(self.character).queue > 1 then self:forceComplete() end
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

-- 開始或停止。正在做＝停；排隊中＝取消；不是這個模式＝沒反應；沒錶、沒電＝提示原因
function Look.toggle(player)
    local queue = ISTimedActionQueue.getTimedActionQueue(player)
    local i = queue:indexOfType(A.Type)
    if i == 1 then
        ISTimedActionQueue.clear(player)
        return
    end
    if i > 1 then
        table.remove(queue.queue, i)
        return
    end
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
