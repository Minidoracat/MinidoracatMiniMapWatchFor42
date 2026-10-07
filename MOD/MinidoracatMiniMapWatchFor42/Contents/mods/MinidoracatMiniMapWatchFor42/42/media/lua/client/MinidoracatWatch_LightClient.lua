-- MinidoracatWatch_LightClient.lua：照明模組的客戶端——開關入口（面板按鈕在 _Panel、錶的右鍵、快捷鍵）、
-- 擁有者自己掛上／拿下光源、每台客戶端把所有人的燈半徑改成沙盒值。開關的權威在伺服器（單機在本機，shared _Light）。
require "MinidoracatWatch_Client"
local W, C = MinidoracatWatchCore, MinidoracatWatchClient

-- MP 送純量、單機直接套用；開燈前先在本機判一次，原因直接提示（伺服器失敗只回通用鍵）
function C.requestLight(player, on)
    if not player then return end
    if on then
        local ok, why = W.lightAllowed(player)
        if not ok then return W.notify(player, why) end
    end
    if isClient() then
        sendClientCommand(player, W.MODULE, W.CMD_LIGHT, { on = on })
        return
    end
    local ok, reason = W.applyLight(player, on)
    if not ok then return W.notify(player, reason) end
    C.syncLight(player) -- 單機：開關音效不等下一秒
end

function C.toggleLight(player) C.requestLight(player, not W.lightOn(player)) end

-- 擁有者端：伺服器的 setAttachedItem 不會到本機玩家（GameCharacterAttachedItemPacket.java:101-107），
-- 所以照「主背包裡有啟動中的光源」自己掛上或拿下；本機 setAttachedItem 會送封包、伺服器轉給其他所有連線
-- （IsoGameCharacter.java:3569-3571、Packet.java:122-135）。原版切燈鍵把它關掉時同樣在這裡拿下。
-- 啟動狀態隨附掛物品的完整物品資料送出（InventoryItem.java:2032），晚加入的人另有 syncActivatedItems
-- （GameServer.java:2775-2790），不必另送 syncItemActivated。旁人只在「自己此刻看得到的格子」上看到這盞燈
-- （約 3.5 格內或視野錐內），和原版手電筒相同（features.md）。
-- 開關燈的音效也在這裡：狀態真的變了才響（伺服器開關、自動熄燈、原版切燈鍵都算；剛上線只記基準）。
function C.syncLight(p)
    local item = W.lightItem(p)
    local want = item ~= nil and item:isActivated() and item or nil
    if p:getAttachedItem(W.LIGHT_LOC) ~= want then p:setAttachedItem(W.LIGHT_LOC, want) end
    MinidoracatWatchSound.lightSeen(p, want ~= nil)
end

-- 半徑只來自 script、不存檔也不入封包（Item.java:1826-1829）：每台客戶端改自己記憶體裡每位玩家那份，
-- 下一次 TorchInfo.set 就讀到（IsoGameCharacter.java:17288-17291）
local function fitRadius(p, r)
    local item = p:getAttachedItem(W.LIGHT_LOC)
    if item and item:getLightDistance() ~= r then item:setLightDistance(r) end
end

local POLL_MS = 1000
local lastPoll = nil
function C.lightPoll()
    local now = getTimestampMs()
    if lastPoll and now >= lastPoll and now - lastPoll < POLL_MS then return end
    lastPoll = now
    local r = W.lightRadius()
    for pn = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(pn)
        if p and not p:isDead() then
            C.syncLight(p)
            fitRadius(p, r)
        end
    end
    if isClient() then
        local list = getOnlinePlayers() -- MP 客戶端＝GameClient 的玩家表（LuaManager.java:4453-4463）
        for i = 0, list:size() - 1 do fitRadius(list:get(i), r) end
    end
end
Events.OnTick.Add(C.lightPoll)

-- 伺服器開關燈後的提醒（只送給本人）：不等下一秒，立刻對齊
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= W.MODULE or command ~= W.CMD_LIGHT or type(args) ~= "table" then return end
    for pn = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(pn)
        if p and p:getUsername() == args.to then C.syncLight(p) end
    end
end)

-- ===== 錶的右鍵：戴著、裝了照明模組的那支 =====
local function onLight(_, pn) C.toggleLight(getSpecificPlayer(pn)) end
Events.OnFillInventoryObjectContextMenu.Add(function(pn, context, items)
    local player = getSpecificPlayer(pn)
    if not player or not W.enabled() then return end
    local e = W.status(player)
    if not (e.watch and W.modState(e, "light")) then return end
    for _, v in ipairs(items) do
        local item = v
        if not instanceof(v, "InventoryItem") then item = v.items and v.items[1] end
        if item and W.isWatch(item) and item:getID() == e.watch:getID() then
            local on = W.lightOn(player)
            local opt = context:addOption(getText(on and "IGUI_MinidoracatWatch_LightOff" or "IGUI_MinidoracatWatch_LightOn"),
                item, onLight, pn)
            if not on and not W.lightAllowed(player) then opt.notAvailable = true end
            return
        end
    end
end)

-- ===== 快捷鍵（選項 → 按鍵綁定 → [MinidoracatWatch]，可改鍵）=====
-- 預設 Scroll Lock（KEY_SCROLL＝70）：原版 keyBinding.lua 未綁；原版 Lua 沒有 KEY_SCROLL 也沒有裸 70；反編譯 Java
-- 直接讀鍵的呼叫沒有 70（只在 org/lwjglx/input/KeyCodes.java 的 GLFW 281↔70 對照表）；家族未用（小地圖 / ; '、
-- DevProfiler \、Economy [、UI Dock .）；本機 Workshop 424 個項目 0 次。不用 ,：EquipmentUI（3780682550）與
-- NeatUI_Equipment（3790656296）拿它開裝備視窗。筆電與小配列常沒有 Scroll Lock：照明另有面板按鈕與錶的右鍵選單，
-- 也能改鍵。文字輸入期間引擎不派送按鍵事件（GameKeyboard isDoingTextEntry）。
Events.OnGameBoot.Add(function()
    table.insert(keyBinding, { value = "[MinidoracatWatch]" })
    table.insert(keyBinding, { value = "MinidoracatWatch_Light", key = Keyboard.KEY_SCROLL })
end)

Events.OnKeyPressed.Add(function(key)
    if key == 0 or key ~= getCore():getKey("MinidoracatWatch_Light") then return end
    local p = getSpecificPlayer(0)
    if p and not p:isDead() and W.enabled() then C.toggleLight(p) end
end)
