-- MinidoracatWatch.lua（shared）：地圖錶的電池、扣電、穿戴限制與閘門判定。
-- MinidoracatWatchCore 是本 addon 的內部表，不是公開 API（公開 API MinidoracatWatchAPI 等 Phase 3 模組做好才開）。
--
-- 電量放在錶的 modData[KEY]：nil＝全新的錶（視為裝著滿電電池）、-1＝沒有電池、0..1＝剩餘電量。
-- 原版的耗電類別用不上：AlarmClockClothing 與 DrainableComboItem 都是 final
-- （AlarmClockClothing.java:36、DrainableComboItem.java:32）。
-- 換手（ISClothingExtraAction）會建新物品、ID 改變，但整份 modData 會複製過去
-- （ISClothingExtraAction.lua:107-108），所以狀態只綁 modData，不綁物品 ID。
-- 物品 modData 只放這一個數字：時間戳放玩家 modData（家族規則：物品身上不存時間戳）。
--
-- 權威：扣電與換電池只在伺服器（MP）或單機執行。MP 客戶端只讀 modData、送請求。

local W = {}
MinidoracatWatchCore = W

W.MOD_ID = "MinidoracatMiniMapWatchFor42"
W.MODULE = "MinidoracatWatch" -- client／server command module
W.CMD_BATTERY = "battery"
W.CMD_FAILED = "batteryFailed"
W.KEY = "MinidoracatWatchBattery"
W.SEEN_KEY = "MinidoracatWatchSeenMs" -- 玩家 modData：上次結算的牆鐘時間（只給「離線也耗電」用）
W.NO_BATTERY = -1
W.BATTERY_TYPE = "Base.Battery"
W.WATCH_TYPES = {
    ["MinidoracatWatch.MapWatch_ValuTech_Right"] = true,
    ["MinidoracatWatch.MapWatch_ValuTech_Left"] = true,
}

W.SETTLE_MS = 60000 -- 每分鐘把累積的耗電寫進 modData 並同步一次
-- 單一 tick 最多計入的時間：伺服器卡頓、系統時鐘往前跳、單機在沒有 tick 的時段都只算這麼多。
-- 伺服器正常 tick 遠小於此；誤差上限是「卡頓次數 × 超出的部分」，對 72 小時的電池可忽略。
W.MAX_TICK_MS = 5000
W.MAX_OFFLINE_MS = 30 * 24 * 3600000 -- 離線耗電的上限（系統時鐘大跳躍時不至於清空）
W.LOW_CHARGE = 0.2

W.RULE_FREE, W.RULE_WATCH, W.RULE_OFF = 1, 2, 3

W.FAIL_GENERIC = "IGUI_MinidoracatWatch_BatteryFailed"
W.FAIL_NO_BATTERY = "IGUI_MinidoracatWatch_NoBatteryToRemove"
W.REASON_OFF = "IGUI_MinidoracatWatch_Reason_Off"
W.REASON_NO_WATCH = "IGUI_MinidoracatWatch_Reason_NoWatch"
W.REASON_NO_BATTERY = "IGUI_MinidoracatWatch_Reason_NoBattery"
W.REASON_DEAD = "IGUI_MinidoracatWatch_Reason_Dead"
-- 伺服器回給客戶端的失敗原因只能是這幾個鍵（客戶端照表核對才 getText）
W.FAIL_KEYS = { [W.FAIL_GENERIC] = true, [W.FAIL_NO_BATTERY] = true }

function W.log(msg)
    print("[" .. W.MOD_ID .. "] " .. tostring(msg))
end

-- SandboxVars 在 MP 由伺服器整包推送（ConnectionDetails.java:137-138），兩端讀到的是同一份
function W.sandbox(name, default)
    local sb = SandboxVars and SandboxVars.MinidoracatWatch
    local v = sb and sb[name]
    if v == nil then return default end
    return v
end

function W.enabled() return W.sandbox("Enabled", true) ~= false end

function W.minimapRule()
    local r = W.sandbox("MinimapRule", W.RULE_WATCH)
    if r == W.RULE_FREE or r == W.RULE_OFF then return r end
    return W.RULE_WATCH
end

function W.fullHours()
    local h = tonumber(W.sandbox("FullHours", 72))
    if not h or h ~= h or h < 1 then return 1 end
    if h > 720 then return 720 end
    return h
end

-- Java int 參數收到小數會被截斷、NaN／±Inf 變垃圾 id（照 AutoDrive MDAD.isFiniteInt）
function W.isFiniteInt(n)
    if type(n) ~= "number" then return false end
    if n * 0 ~= 0 then return false end
    return math.floor(n) == n
end

function W.isWatch(item)
    return item ~= nil and W.WATCH_TYPES[item:getFullType()] == true
end

-- 剩餘電量 0..1；沒有電池回 nil。hasModData 先問：getModData 會替沒有 modData 的物品建空表。
function W.charge(item)
    if not item:hasModData() then return 1 end
    local v = item:getModData()[W.KEY]
    if v == nil then return 1 end
    if type(v) ~= "number" or v ~= v or v < 0 then return nil end
    if v > 1 then return 1 end
    return v
end

function W.setCharge(item, charge)
    item:getModData()[W.KEY] = charge
end

-- 續航（現實時間）＝滿電小時數 ÷（1＋模組耗電%÷100）。Phase 2 沒有模組，只有基礎耗電。
function W.drain(charge, ms, fullHours)
    if charge == nil or ms <= 0 then return charge end
    local c = charge - ms / (fullHours * 3600000)
    if c < 0 then return 0 end
    return c
end

-- 剩餘時間拆成（天, 小時）；不到 1 小時回 0, 0
function W.timeLeft(charge, fullHours)
    local h = math.floor(charge * fullHours)
    if h < 24 then return 0, h end
    return math.floor(h / 24), h % 24
end

-- 這個 tick 要計入多少耗電時間：時鐘倒退＝0；暫停且不允許暫停耗電＝0；大跳躍截到 MAX_TICK_MS
function W.tickDelta(now, last, paused, drainPaused)
    if last == nil or now <= last then return 0 end
    if paused and not drainPaused then return 0 end
    local d = now - last
    if d > W.MAX_TICK_MS then return W.MAX_TICK_MS end
    return d
end

-- 第一次看到這位玩家（登入、讀檔、重生）時要補扣的離線時間
function W.offlineMs(now, seen, drainOffline)
    if not drainOffline or type(seen) ~= "number" or seen ~= seen or now <= seen then return 0 end
    local d = now - seen
    if d > W.MAX_OFFLINE_MS then return W.MAX_OFFLINE_MS end
    return d
end

-- 小地圖閘門的決策表（純函式）：回 allowed, reasonKey
function W.minimapDecision(enabled, rule, hasWatch, charge)
    if not enabled or rule == W.RULE_FREE then return true end
    if rule == W.RULE_OFF then return false, W.REASON_OFF end
    if not hasWatch then return false, W.REASON_NO_WATCH end
    if charge == nil then return false, W.REASON_NO_BATTERY end
    if charge <= 0 then return false, W.REASON_DEAD end
    return true
end

-- 身上第一支（except 以外的）地圖錶與總支數。WornItems 依 BodyLocationGroup 順序排列
-- （WornItems.java:53-82），原版左腕排在右腕前（BodyLocations.lua:32-33），所以兩支都戴時
-- 生效的是左手那支——規則固定、不看戴上的先後。不配置 table。
function W.wornWatch(player, except)
    local worn = player:getWornItems()
    local first, count = nil, 0
    if not worn then return nil, 0 end
    for i = 0, worn:size() - 1 do
        local it = worn:get(i):getItem()
        if it ~= except and W.isWatch(it) then
            count = count + 1
            if not first then first = it end
        end
    end
    return first, count
end

-- ===== 同時只能戴一支 =====
-- 所有穿戴入口（右鍵穿戴、雙擊、拖曳、手把、快捷列）都建 ISWearClothing（ISInventoryPaneContextMenu.lua:2888-2895、
-- ISInventoryPane.lua:1189-1190）；換手與「改戴另一手」走 ISClothingExtraAction（:4396-4411），它對沒戴著的錶也會直接
-- 穿上（ISClothingExtraAction.lua:121-137），所以兩個動作都要攔。
-- 擋在兩層：isValid（客戶端與單機，拒絕並提示）、complete（MP 只在伺服器執行，LuaTimedActionNew.java:163-167；
-- 回 false＝動作被拒，NetTimedAction.java:132-139）。伺服器不跑 isValid，所以 complete 才是權威。
-- 擋不到的：客戶端直接送 SyncClothing 封包（SyncClothingPacket.java:230-237 伺服器照收）。這種情況由
-- wornWatch 的固定生效規則收斂：永遠只有一支在扣電、閘門也只看那一支。
function W.blockingWatch(action)
    local item = action.item
    if not W.isWatch(item) or not action.character then return nil end
    return (W.wornWatch(action.character, item))
end

local lastHaloMs = {}
function W.notify(player, key)
    if isServer() or not player or not HaloTextHelper then return end
    local pn = player:getPlayerNum()
    local now = getTimestampMs()
    local last = lastHaloMs[pn]
    if last and now >= last and now - last < 1000 then return end -- isValid 同一次可能被問好幾遍
    lastHaloMs[pn] = now
    HaloTextHelper.addBadText(player, getText(key))
end

function W.guardWearAction(cls)
    local isValid, complete = cls.isValid, cls.complete
    cls.isValid = function(self)
        if W.blockingWatch(self) then
            W.notify(self.character, "IGUI_MinidoracatWatch_OneWatchOnly")
            return false
        end
        return isValid(self)
    end
    cls.complete = function(self)
        if W.blockingWatch(self) then return false end
        return complete(self)
    end
end

require "TimedActions/ISWearClothing"
require "TimedActions/ISClothingExtraAction"
if ISWearClothing then W.guardWearAction(ISWearClothing) end
if ISClothingExtraAction then W.guardWearAction(ISClothingExtraAction) end

-- ===== 換電池（伺服器／單機的唯一突變點）=====
-- MP 由 server/MinidoracatWatch_Server.lua 在 OnClientCommand 內呼叫（player 是連線身分）；單機由客戶端直接呼叫。
-- 只收純量：watchId、install、batteryId；兩件物品都只從「這位玩家自己的背包樹」依 ID 重新解析
-- （ItemContainer.getItemWithIDRecursiv＝ItemContainer.java:3094），地上、別人身上、車上的物品都拿不到。
-- 電量守恆：裝入＝錶的電量變成那顆電池的剩餘量、那顆電池移除；錶原本有電池就以當時剩餘量還一顆回背包。
-- 回傳 true 或 false, 翻譯鍵。
local function giveBattery(player, charge)
    local inv = player:getInventory()
    local battery = instanceItem(W.BATTERY_TYPE) -- LuaManager.java:5605
    if not battery or not inv then return end
    battery:setCurrentUsesFloat(charge) -- InventoryItem.java:2601（DrainableComboItem 依 UseDelta 取整，DrainableComboItem.java:83-87）
    inv:AddItem(battery)
    -- 伺服器的 send* 只送封包、不動容器，所以先 AddItem（GameServer.java:2405-2421；原版順序 ISClothingExtraAction.lua:128-129）
    if isServer() then sendAddItemToContainer(inv, battery) end
end

function W.applyBatteryChange(player, watchId, install, batteryId)
    if isClient() then return false, W.FAIL_GENERIC end
    if not W.isFiniteInt(watchId) or type(install) ~= "boolean" then return false, W.FAIL_GENERIC end
    if install and not W.isFiniteInt(batteryId) then return false, W.FAIL_GENERIC end
    if not player or player:isDead() then return false, W.FAIL_GENERIC end
    local inv = player:getInventory()
    if not inv then return false, W.FAIL_GENERIC end
    local watch = inv:getItemWithIDRecursiv(watchId)
    if not W.isWatch(watch) then return false, W.FAIL_GENERIC end
    local old = W.charge(watch)

    if install then
        local battery = inv:getItemWithIDRecursiv(batteryId)
        if not battery or battery:getFullType() ~= W.BATTERY_TYPE then return false, W.FAIL_GENERIC end
        local container = battery:getContainer() -- InventoryItem.java:3840：實際所在的袋子
        if not container then return false, W.FAIL_GENERIC end
        -- InventoryItem.java:2597；Battery 的 uses 是 round(f/0.007) 的整數，setCurrentUsesFloat(1) 會讀成 1.001
        -- （DrainableComboItem.java:83-92），存進錶之前夾回 1
        local charge = math.min(1, battery:getCurrentUsesFloat())
        -- 以下不再有失敗點
        player:removeFromHands(battery)
        container:DoRemoveItem(battery)
        if isServer() then sendRemoveItemFromContainer(container, battery) end
        W.setCharge(watch, charge)
        if old ~= nil then giveBattery(player, old) end
    else
        if old == nil then return false, W.FAIL_NO_BATTERY end
        W.setCharge(watch, W.NO_BATTERY)
        giveBattery(player, old)
    end
    -- 只有伺服器能同步 modData：sendToRelative 給玩家附近的所有連線（含本人），客戶端以容器＋物品 ID
    -- 找到同一件物品後整表覆蓋（LuaManager.java:12326-12334、SyncItemModDataPacket；單機是 no-op）
    if isServer() then syncItemModData(player, watch) end
    return true
end

-- ===== 扣電（伺服器與單機；MP 客戶端不跑）=====
-- 一個全域的「有效時間」計數器 activeMs：每幀加上 tickDelta。每位玩家記下上次結算時的 activeMs，
-- 每分鐘結算一次「這段時間的有效毫秒數」扣在當時戴著的那支錶上，寫 modData 並同步。
-- 暫停、時鐘倒退、大跳躍都只在 tickDelta 一處處理。
-- 掛 OnTickEvenPaused 而不是 OnTick：單機暫停時 GameWindow 跳過 states.update（OnTick 不觸發），只派
-- OnTickEvenPaused（GameWindow.java:354-368）；沒暫停時 IngameState.updateInternal 每幀派一次（IngameState.java:1347）。
-- 所以「暫停時也耗電」要靠它才算得到暫停的時間；暫停與否用 isGamePaused 判斷（LuaManager.java:7986-7992 →
-- GameTime.java:184-193，單機＝遊戲速度 0）。專用伺服器的暫停（沒人在線）時沒有人在戴錶，不需要特別處理。
local activeMs, lastTickMs, lastSettleMs = 0, nil, nil
local marks = {} -- [IsoPlayer] = 上次結算時的 activeMs

local function settlePlayer(player, now, nextMarks, drainOffline, fullHours, enabled)
    if player:isDead() then return end
    local pmd = player:getModData()
    local mark = marks[player]
    local ms
    if mark == nil then
        ms = W.offlineMs(now, pmd[W.SEEN_KEY], drainOffline)
    else
        ms = activeMs - mark
    end
    nextMarks[player] = activeMs
    pmd[W.SEEN_KEY] = now
    if not enabled or ms <= 0 then return end
    local watch = W.wornWatch(player)
    if not watch then return end
    local c = W.charge(watch)
    if c == nil or c <= 0 then return end
    W.setCharge(watch, W.drain(c, ms, fullHours))
    if isServer() then syncItemModData(player, watch) end
end

function W.settleAll(now)
    local nextMarks = {}
    local drainOffline = W.sandbox("DrainOffline", false) == true
    local fullHours, enabled = W.fullHours(), W.enabled()
    if isServer() then
        local players = getOnlinePlayers() -- LuaManager.java:4453-4463（單機回空清單）
        for i = 0, players:size() - 1 do
            settlePlayer(players:get(i), now, nextMarks, drainOffline, fullHours, enabled)
        end
    else
        for i = 0, getNumActivePlayers() - 1 do -- LuaManager.java:3880-3886
            local p = getSpecificPlayer(i)
            if p then settlePlayer(p, now, nextMarks, drainOffline, fullHours, enabled) end
        end
    end
    marks = nextMarks -- 離線的玩家自然掉出去
end

function W.onTick()
    local now = getTimestampMs() -- 牆鐘（LuaManager.java:9291-9297 → System.currentTimeMillis）
    local paused = not isServer() and isGamePaused()
    activeMs = activeMs + W.tickDelta(now, lastTickMs, paused, W.sandbox("DrainPaused", false) == true)
    lastTickMs = now
    if lastSettleMs and now >= lastSettleMs and now - lastSettleMs < W.SETTLE_MS then return end
    lastSettleMs = now
    W.settleAll(now)
end

if not isClient() then Events.OnTickEvenPaused.Add(W.onTick) end
