-- MinidoracatWatch_Light.lua（shared）：照明模組（Phase 8）的開關、自動熄燈與光源物品。
-- 由 MinidoracatWatch.lua 結尾 require（在 _Modules 之後）；這裡不反向 require，免得 Kahlua 警告 recursive require。
--
-- 做法：開燈＝伺服器（單機＝本機）在玩家「主背包」放一個啟動的隱形光源物品 MinidoracatWatch.LightEmitter，
-- 掛在自訂 AttachedLocation；關燈＝拿掉並刪除。光、其他客戶端可見與晚加入全部走原版：
-- - 動態光：LightingJNI.checkLights 對每位玩家 getActiveLightItems（兩手＋attached，IsoGameCharacter.java:14295-14306）
--   的發光物逐幀 updateTorch（LightingJNI.java:442-465），不經 addLamppost 的整區重算。
-- - 太暗讀不了地圖：attached 發光物讓 IsoPlayer.tooDarkToRead 直接回 false（IsoPlayer.java:8604-8630）。
-- - 別人看得到：擁有者客戶端 setAttachedItem 會送 GameCharacterAttachedItem，伺服器對所有其他連線廣播完整物品
--   （IsoGameCharacter.java:3569-3571、GameCharacterAttachedItemPacket.java:122-135）；伺服器自己的 sendAttachedItem
--   另送範圍內客戶端（LuaManager.java:12394-12401，擁有者那份 processClient 會略過，:101-107）。
--   之後才進範圍／登入的玩家由 ConnectedPlayer 帶 attached 清單、syncActivatedItems 補啟動（GameServer.java:2771-2793）。
-- - 存檔：activated 與 attached 都隨背包存（InventoryItem.java:2032、IsoGameCharacter.java:14579-14586）。
-- 真相只有一個：「主背包裡有啟動中的光源物品」＝燈開著。伺服器每秒校正（沒電、拿下錶、拆模組、槽位失效、
-- 規則關閉、原版切燈鍵把它關掉 ItemBindingHandler.lua:50-61）就刪掉；擁有者客戶端每秒依同一個真相掛上或拿下。
local W = MinidoracatWatchCore

W.LIGHT_TYPE = "MinidoracatWatch.LightEmitter"
W.LIGHT_LOC = "MinidoracatWatchLight"
W.CMD_LIGHT = "light"
W.FAIL_LIGHT = "IGUI_MinidoracatWatch_LightFailed"
W.FAIL_KEYS[W.FAIL_LIGHT] = true

-- 兩端的 shared 都要先定義 location：setItem 對不存在的 location 會丟例外（AttachedLocationGroup.java:63-71），
-- 讀檔時也只還原 location 存在的 attached 物品（IsoGameCharacter.java:14584）。不設 attachmentName＝不渲染。
if AttachedLocations then AttachedLocations.getGroup("Human"):getOrCreateLocation(W.LIGHT_LOC) end

-- 半徑（格，setLightDistance 收 int）與開燈時增加的耗電（%）；照設計稿 BATTERY.lightOn 與「照明半徑 4 格」
function W.lightRadius() return math.floor(W.radius("LightRadius", 4)) end
function W.lightDrain()
    local v = tonumber(W.sandbox("LightDrain", 100))
    if not v or v ~= v or v < 0 then return 100 end
    return v
end

-- 主背包裡的光源物品（getFirstType 全名比對，ItemContainer.java:1540、:1197-1201）；沒有回 nil
function W.lightItem(player)
    local inv = player and player:getInventory()
    return inv and inv:getFirstType(W.LIGHT_TYPE) or nil
end

function W.lightOn(player)
    local item = W.lightItem(player)
    return item ~= nil and item:isActivated()
end

-- 這支錶正在替開著的燈供電嗎（W.drainFactor 用；面板算別支沒戴著的錶時不加）。戴著哪支照狀態快取取，
-- 不直接讀穿戴清單：外觀 MOD 換掉身上衣物時那是複製品（W.wornDetached）
function W.lightLit(player, watch)
    if not watch or not W.lightOn(player) then return false end
    local worn = W.status(player).watch
    return worn ~= false and worn:getID() == watch:getID()
end

-- 現在能不能開著燈：回 true 或 false, 原因鍵（客戶端提示與伺服器校正共用）。
-- 地圖錶系統關閉等同沒裝本 MOD：沒有照明模組可用。其餘照功能閘門（規則、戴錶、電量、模組在有效槽位）。
function W.lightAllowed(player)
    if not W.enabled() then return false, W.REASON_FEATURE_OFF end
    return W.featureDecision(player, "light")
end

local function nudge(player)
    sendServerCommand(player, W.MODULE, W.CMD_LIGHT, { to = player:getUsername() })
end

local function attach(player, item)
    player:setAttachedItem(W.LIGHT_LOC, item)
    if isServer() then
        sendAttachedItem(player, W.LIGHT_LOC, item)
        nudge(player) -- 伺服器端的 setAttachedItem 到不了擁有者：擁有者客戶端自己掛（MinidoracatWatch_LightClient.lua）
    end
end

-- 關燈：先把開燈期間的耗電入帳，再拿下、刪除
function W.lightOff(player, item)
    W.settleNow(player)
    if player:getAttachedItem(W.LIGHT_LOC) then player:setAttachedItem(W.LIGHT_LOC, nil) end
    local c = item:getContainer()
    if c then
        c:DoRemoveItem(item)
        if isServer() then sendRemoveItemFromContainer(c, item) end -- 伺服器的 send* 只送封包，先 DoRemoveItem
    end
    if isServer() then
        sendAttachedItem(player, W.LIGHT_LOC, nil)
        nudge(player)
    end
end

-- 伺服器（MP，OnClientCommand）／單機的唯一突變點：on 只收布林。主背包最多一個光源物品。
function W.applyLight(player, on)
    if isClient() or type(on) ~= "boolean" or not player or player:isDead() then return false, W.FAIL_LIGHT end
    local item = W.lightItem(player)
    if not on then
        if item then W.lightOff(player, item) end
        return true
    end
    if item and item:isActivated() then return true end
    if not W.lightAllowed(player) then return false, W.FAIL_LIGHT end
    if item then W.lightOff(player, item) end -- 原版切燈鍵關掉、還沒被校正刪掉的那個
    W.settleNow(player) -- 耗電倍率要變了：先把舊倍率下的耗電入帳
    local inv = player:getInventory()
    item = inv:AddItem(W.LIGHT_TYPE)
    if not item then return false, W.FAIL_LIGHT end
    item:setActivated(true) -- 先啟動再送：加入物品的封包帶 activated
    if isServer() then sendAddItemToContainer(inv, item) end
    attach(player, item)
    return true
end

-- 每秒校正一位玩家（伺服器／單機）：不合規或被原版切燈鍵關掉就刪；伺服器自己的掛載被改掉就補回
function W.lightCheck(player)
    local item = W.lightItem(player)
    if not item then return end
    if not item:isActivated() or not W.lightAllowed(player) then
        W.lightOff(player, item)
    elseif player:getAttachedItem(W.LIGHT_LOC) ~= item then
        attach(player, item)
    end
end

local LIGHT_POLL_MS = 1000
local lastLightMs = nil
function W.lightTick()
    local now = getTimestampMs()
    if lastLightMs and now >= lastLightMs and now - lastLightMs < LIGHT_POLL_MS then return end
    lastLightMs = now
    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if not p:isDead() then W.lightCheck(p) end
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p and not p:isDead() then W.lightCheck(p) end
        end
    end
end

-- 單機暫停時 OnTick 不跑（GameWindow.java:354-368）：沒電熄燈與扣電同一個事件
if not isClient() then Events.OnTickEvenPaused.Add(W.lightTick) end

-- 死亡：刪光源，屍體（IsoDeadBody 直接接手玩家的背包與 attached，IsoDeadBody.java:326-330）裡不留隱形光源。
-- OnCharacterDeath 由 DoDeath→OnDeath 觸發（IsoGameCharacter.java:2024-2025、4873-4875），早於 becomeCorpse
-- （:14623-14643、14683-14689），SP 與專用伺服器都在權威端跑；MP 客戶端也會觸發，交給伺服器。
-- 不用 OnPlayerDeath：它只在非伺服器的本機玩家觸發（IsoPlayer.java:6554-6570），dedicated 收不到。
function W.lightOnDeath(chr)
    if not instanceof(chr, "IsoPlayer") then return end
    local item = W.lightItem(chr)
    if item then W.lightOff(chr, item) end
end
if not isClient() then Events.OnCharacterDeath.Add(W.lightOnDeath) end
