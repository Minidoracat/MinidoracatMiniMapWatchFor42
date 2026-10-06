-- MinidoracatWatch.lua（shared）：地圖錶的電池、扣電、穿戴限制與小地圖決策表。
-- MinidoracatWatchCore 是本 addon 的內部表，不是公開 API（公開 API MinidoracatWatchAPI 在 MinidoracatWatch_Modules.lua）。
--
-- 電量放在錶的 modData[KEY]：nil＝全新的錶（視為裝著滿電電池）、-1＝沒有電池、0..1＝剩餘電量。
-- 原版的耗電類別用不上：AlarmClockClothing 與 DrainableComboItem 都是 final
-- （AlarmClockClothing.java:36、DrainableComboItem.java:32）。
-- 換手（ISClothingExtraAction）會建新物品、ID 改變，但整份 modData 會複製過去
-- （ISClothingExtraAction.lua:107-108），所以狀態只綁 modData，不綁物品 ID。
-- 物品 modData 只放這一個數字：上次在線時間放伺服器的全域 ModData（家族規則：物品身上不存時間戳）。
--
-- 權威：扣電與換電池只在伺服器（MP）或單機執行。MP 客戶端只讀 modData、送請求。

local W = {}
MinidoracatWatchCore = W

W.MOD_ID = "MinidoracatMiniMapWatchFor42"
W.MODULE = "MinidoracatWatch" -- client／server command module
W.CMD_BATTERY = "battery"
W.CMD_FAILED = "failed"
W.KEY = "MinidoracatWatchBattery"
W.NO_BATTERY = -1
W.BATTERY_TYPE = "Base.Battery"
-- 七款錶（外觀只影響外觀：槽位、耗電、功能完全相同）。每款左右手各一個物品（ClothingItemExtra 互換）。
W.STYLES = { "ValuTech", "Paws", "Nexus", "Spiffo", "Ranger", "Luthex", "BB3000" }
W.WATCH_TYPES = {}
for _, s in ipairs(W.STYLES) do
    W.WATCH_TYPES["MinidoracatWatch.MapWatch_" .. s .. "_Left"] = true
    W.WATCH_TYPES["MinidoracatWatch.MapWatch_" .. s .. "_Right"] = true
end
-- 戰利品、殭屍掉落產生的那一隻：左手（原版分佈表也只放 WristWatch_Left_*；嗶嗶腕機照原作戴左前臂）
function W.watchType(style) return "MinidoracatWatch.MapWatch_" .. style .. "_Left" end

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

-- 續航（現實時間）＝滿電小時數 ÷ 耗電倍率（1＋模組耗電%÷100，節能核心再減半；W.drainFactor）
function W.drain(charge, ms, fullHours, factor)
    if charge == nil or ms <= 0 then return charge end
    local c = charge - ms * (factor or 1) / (fullHours * 3600000)
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
        -- 換手會複製舊錶的 modData 到新物品（ISClothingExtraAction.lua:107-108）：先把還沒入帳的耗電寫進舊錶
        if W.isWatch(self.item) then W.settleNow(self.character) end
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
-- 電池的電量是整數格（uses × UseDelta，Battery 0.007＝最多 142 格，DrainableComboItem.java:67-69、:90-92）。
-- 還電池時一律無條件捨去到整數格：setCurrentUsesFloat 是四捨五入（:83-87），反覆拆裝能把已扣的電補回來。
-- 裝入時錶的電量取「格數 × UseDelta」的 Lua 雙精度值（不用 float 運算的 getCurrentUsesFloat），
-- 拆出來時同一個值除回去才會剛好是原格數；+1e-9 只吸收除法的 1 ulp 誤差。
-- 回傳 true 或 false, 翻譯鍵。
function W.batteryUses(charge, useDelta, maxUses)
    local n = math.floor(charge / useDelta + 1e-9)
    if n < 0 then return 0 end
    if n > maxUses then return maxUses end
    return n
end

local function giveBattery(player, charge)
    local inv = player:getInventory()
    local battery = instanceItem(W.BATTERY_TYPE) -- LuaManager.java:5605
    if not battery or not inv then return end
    -- getUseDelta／getMaxUses／setCurrentUses(int)：DrainableComboItem.java:458、:67-69、:72-75
    battery:setCurrentUses(W.batteryUses(charge, battery:getUseDelta(), battery:getMaxUses()))
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
    W.settleNow(player) -- 戴著的錶先把還沒入帳的耗電寫進去，退回的電池才不會多出這段電
    local old = W.charge(watch)

    if install then
        local battery = inv:getItemWithIDRecursiv(batteryId)
        if not battery or battery:getFullType() ~= W.BATTERY_TYPE then return false, W.FAIL_GENERIC end
        local container = battery:getContainer() -- InventoryItem.java:3840：實際所在的袋子
        if not container then return false, W.FAIL_GENERIC end
        -- 格數 × UseDelta（InventoryItem.java:2584、DrainableComboItem.java:458）；超過 1 的格數
        -- （例如 setCurrentUsesFloat(1) 會四捨五入成 143 格＝1.001）存進錶之前夾回 1
        local charge = math.min(1, battery:getCurrentUses() * battery:getUseDelta())
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
    W.invalidate()
    if isServer() then syncItemModData(player, watch) end
    return true
end

-- ===== 嗶嗶腕機的螢幕顏色（純外觀）=====
-- 選擇存錶的 modData（nil／0＝綠、1＝琥珀＝clothing xml 的 textureChoices 索引），跟著錶走（換手時整份 modData
-- 複製過去，ISClothingExtraAction.lua:107-108）。ItemVisual 才是畫面用的值：
-- - textureChoice＝-1 時引擎會隨機挑一張並寫回（ItemVisual.java:185-194），物品一生成就已隨機定色
--   （Item.java:1909-1913 → InventoryItem.synchWithVisual → getVisual → pickUninitializedValues），所以戴著時一律照 modData 改。
-- - SyncClothing 雖帶 textureChoice，但同 ID、同部位的既有衣物不套用（SyncClothingPacket.java:193-213）；SyncVisuals
--   不帶 textureChoice（SyncVisualsPacket.java:56-128）。所以伺服器改好自己的 ItemVisual 後，用沒有 player 參數的
--   sendServerCommand 廣播給所有連線（LuaManager.java:8956-8959 → GameServer.java:3521-3524），各客戶端自己改。
-- - 之後才連進來的玩家由 ConnectedPacket 帶伺服器的 ItemVisuals（ConnectedPacket.java:269-271）；存檔照存 textureChoice
--   （InventoryItem.java:1678-1680、ItemVisual.java:302-304）。
W.SCREEN_KEY = "MinidoracatWatchScreen"
W.CMD_SCREEN = "screen"
W.SCREEN_TYPES = {
    ["MinidoracatWatch.MapWatch_BB3000_Left"] = true,
    ["MinidoracatWatch.MapWatch_BB3000_Right"] = true,
}

function W.hasScreen(item) return item ~= nil and W.SCREEN_TYPES[item:getFullType()] == true end

function W.screenOf(item)
    return (item:hasModData() and item:getModData()[W.SCREEN_KEY] == 1) and 1 or 0
end

-- 套到一個 ItemVisual；有改才回 true。setTextureChoice 只賦值、不刷新模型也不同步（ItemVisual.java:735-740）
function W.setChoice(visual, choice)
    if not visual or visual:getTextureChoice() == choice then return false end
    visual:setTextureChoice(choice)
    return true
end

-- 伺服器（MP）／單機的唯一突變點：只收純量 watchId、choice；錶只從這位玩家自己的背包樹依 ID 解析。
-- 外觀由 W.showScreen 套用（扣電迴圈每秒一次，這裡也立刻呼叫）。
function W.applyScreen(player, watchId, choice)
    if isClient() then return false, W.FAIL_GENERIC end
    if not W.isFiniteInt(watchId) or (choice ~= 0 and choice ~= 1) then return false, W.FAIL_GENERIC end
    if not player or player:isDead() then return false, W.FAIL_GENERIC end
    local inv = player:getInventory()
    local watch = inv and inv:getItemWithIDRecursiv(watchId)
    if not W.hasScreen(watch) then return false, W.FAIL_GENERIC end
    watch:getModData()[W.SCREEN_KEY] = choice
    if isServer() then syncItemModData(player, watch) end
    W.showScreen(player)
    return true
end

-- ===== 扣電（伺服器與單機；MP 客戶端不跑）=====
-- 一個全域的「有效時間」計數器 activeMs：每幀加上 tickDelta（暫停、時鐘倒退、大跳躍只在這一處處理）。
-- 每位玩家記下「上次入帳時的 activeMs」與「那時戴著的錶」。每秒入帳一次（只寫伺服器記憶體裡的 modData），
-- 每分鐘把有變動的錶同步給客戶端一次。戴著的錶換了（穿脫、換手、掉落、其他 MOD 改穿戴）就先把累積的
-- 耗電記在舊錶上並同步；換電池與穿戴動作完成前另外立刻入帳（settleNow），不留一秒的誤差。
-- 掛 OnTickEvenPaused 而不是 OnTick：單機暫停時 GameWindow 跳過 states.update（OnTick 不觸發），只派
-- OnTickEvenPaused（GameWindow.java:354-368）；沒暫停時 IngameState.updateInternal 每幀派一次（IngameState.java:1347）。
-- 所以「暫停時也耗電」要靠它才算得到暫停的時間；暫停與否用 isGamePaused 判斷（LuaManager.java:7986-7992 →
-- GameTime.java:184-193，單機＝遊戲速度 0）。專用伺服器的暫停（沒人在線）時沒有人在戴錶，不需要特別處理。
--
-- 「離線也耗電」的上次在線時間放伺服器的全域 ModData（ModData.java:20）：玩家 modData 會被客戶端整表覆蓋
-- （ObjectModDataPacket.java:54-62、KahluaTableImpl.load 先清空），客戶端送來的全域 ModData 則只觸發
-- OnReceiveGlobalModData、不改伺服器的表（GlobalModDataPacket.java:45-56）。
W.POLL_MS = 1000
W.SEEN_TABLE = "MinidoracatWatchSeen"
local activeMs, lastTickMs, lastPollMs, lastSyncMs = 0, nil, nil, nil
local state = {} -- [IsoPlayer] = { mark = 上次入帳時的 activeMs, watch = 那時戴著的錶或 false, dirty = 有沒同步的變動, screen = 上次套用的螢幕鍵 }

function W.seenKey(player)
    return tostring(player:getUsername()) .. "|" .. tostring(player:getPlayerNum())
end

-- 只同步還在這位玩家背包樹裡的錶：同步封包以容器＋物品 ID 定位（SyncItemModDataPacket），掉在地上或已被
-- 換手刪掉的舊物品沒有東西可對。
local function sync(player, w)
    if isServer() and player:getInventory():getItemWithIDRecursiv(w:getID()) == w then
        syncItemModData(player, w)
    end
end

local function drainWatch(player, w, ms, fullHours)
    if ms <= 0 then return false end
    local c = W.charge(w)
    if c == nil or c <= 0 then return false end
    W.setCharge(w, W.drain(c, ms, fullHours, W.drainFactor(player, w)))
    return true
end

local function accrue(player, s, fullHours, enabled)
    local ms = activeMs - s.mark
    s.mark = activeMs
    if s.watch and enabled and drainWatch(player, s.watch, ms, fullHours) then s.dirty = true end
end

-- 換電池、安裝／拆下模組與穿戴動作完成前呼叫：把這位玩家還沒入帳的耗電立刻記到目前那支錶上
function W.settleNow(player)
    if isClient() or not player then return end
    local s = state[player]
    if s then accrue(player, s, W.fullHours(), W.enabled()) end
end

-- 讓戴著的嗶嗶腕機外觀等於 modData（伺服器／單機）：同一支錶、同一個選擇只套一次（每次戴上、切換時各一次）。
-- 伺服器的 ItemVisual 可能是 nil（clothing 資產沒載入時 getVisual 回 nil，InventoryItem.java:2323-2338），照樣廣播。
-- 單機直接 resetModelNextFrame（IsoGameCharacter.java:1783-1789 → ModelManager.ResetNextFrame）。
local function showScreen(player, s)
    local w = W.wornWatch(player)
    if not W.hasScreen(w) then s.screenId = nil return end
    local choice = W.screenOf(w)
    if s.screenId == w:getID() and s.screenChoice == choice then return end
    s.screenId, s.screenChoice = w:getID(), choice
    W.setChoice(w:getVisual(), choice)
    if isServer() then
        sendServerCommand(W.MODULE, W.CMD_SCREEN, { pid = player:getOnlineID(), id = w:getID(), choice = choice })
    else
        player:resetModelNextFrame()
    end
end

function W.showScreen(player)
    local s = not isClient() and player and state[player]
    if s then showScreen(player, s) end -- 還沒有狀態（登入第一秒）：下一次扣電迴圈會套
end

local function visit(player, now, doSync, seen, drainOffline, fullHours, enabled)
    if player:isDead() then return nil end
    local key = W.seenKey(player)
    local w = W.wornWatch(player) or false
    local s = state[player]
    if not s then
        -- 第一次看到（登入、讀檔、重生）：只有「離線也耗電」開啟時補扣離線時間；MP 順便送這位玩家自己的解鎖狀態
        s = { mark = activeMs, watch = w, dirty = false }
        if w and enabled and drainWatch(player, w, W.offlineMs(now, seen[key], drainOffline), fullHours) then
            s.dirty = true
        end
        W.pushUnlocks(player)
    else
        accrue(player, s, fullHours, enabled)
        if s.watch ~= w then
            if s.dirty and s.watch then sync(player, s.watch) end
            s.watch, s.dirty = w, false
        end
    end
    if doSync and s.dirty and w then
        sync(player, w)
        s.dirty = false
    end
    showScreen(player, s)
    seen[key] = now
    -- 第三方模組的 onStateChanged：MP 伺服器在這裡比對；客戶端與單機在客戶端迴圈（MinidoracatWatch_Client.lua）
    if isServer() then W.pollStateCallbacks(player, player) end
    return s
end

function W.visitAll(now, doSync)
    local seen = ModData.getOrCreate(W.SEEN_TABLE)
    local drainOffline = W.sandbox("DrainOffline", false) == true
    local fullHours, enabled = W.fullHours(), W.enabled()
    local nextState = doSync and {} or state
    if isServer() then
        local players = getOnlinePlayers() -- LuaManager.java:4453-4463（單機回空清單）
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            local s = visit(p, now, doSync, seen, drainOffline, fullHours, enabled)
            if s then state[p] = s; nextState[p] = s end
        end
    else
        for i = 0, getNumActivePlayers() - 1 do -- LuaManager.java:3880-3886
            local p = getSpecificPlayer(i)
            local s = p and visit(p, now, doSync, seen, drainOffline, fullHours, enabled)
            if s then state[p] = s; nextState[p] = s end
        end
    end
    if doSync then
        -- 每分鐘重建一次：離線與死亡的玩家掉出去（扣電狀態、模組狀態快取、onStateChanged 的上次狀態）
        state = nextState
        W.clearStatus()
        if isServer() then W.pruneStateCallbacks(nextState) end
    end
end

function W.onTick()
    local now = getTimestampMs() -- 牆鐘（LuaManager.java:9291-9297 → System.currentTimeMillis）
    local paused = not isServer() and isGamePaused()
    activeMs = activeMs + W.tickDelta(now, lastTickMs, paused, W.sandbox("DrainPaused", false) == true)
    lastTickMs = now
    if lastPollMs and now >= lastPollMs and now - lastPollMs < W.POLL_MS then return end
    lastPollMs = now
    local doSync = not lastSyncMs or now < lastSyncMs or now - lastSyncMs >= W.SETTLE_MS
    if doSync then lastSyncMs = now end
    W.visitAll(now, doSync)
end

if not isClient() then Events.OnTickEvenPaused.Add(W.onTick) end

-- 模組、槽位、狀態快取與對外 API（扣電倍率 W.drainFactor、W.invalidate 等都在那裡）
require "MinidoracatWatch_Modules"
