-- MinidoracatWatch_Server.lua：換電池、安裝／拆下模組、解鎖卡的伺服器權威入口（MP），以及陣營分享的通訊距離。
-- MP 客戶端也會載入 media/lua/server（GameLoadingState.java:148），所以先以 isClient() 早退。
-- 單機不經這裡：客戶端直接呼叫 shared 的 apply*（不發指令，不會重複執行）。
if isClient() then return end

require "MinidoracatWatch"
local W = MinidoracatWatchCore

-- per-player 節流：OnClientCommand 在伺服器主執行緒同步執行，偽造封包每次都會觸發背包重解析。
-- 合法操作是計時動作完成或玩家點選單，間隔遠大於此。解鎖狀態查詢另一條節流（登入時會和其他指令同時到）。
local MIN_INTERVAL_MS = 250
local THROTTLE_TTL_MS = 60000
local lastAt, lastSweepMs = {}, 0

local function throttled(key, now)
    if now < lastSweepMs or now - lastSweepMs >= THROTTLE_TTL_MS then
        for k, at in pairs(lastAt) do
            if now < at or now - at >= THROTTLE_TTL_MS then lastAt[k] = nil end
        end
        lastSweepMs = now
    end
    local last = lastAt[key]
    if last and now >= last and now - last < MIN_INTERVAL_MS then return true end
    lastAt[key] = now
    return false
end

-- 失敗回報只送伺服器自己選的常數鍵；帶 to（帳號）讓同機分割畫面知道是哪位本機玩家。
-- sendServerCommand(player, module, command, args)＝LuaManager.java:8962-8970
local function notifyFail(player, reason)
    sendServerCommand(player, W.MODULE, W.CMD_FAILED, { reason = reason, to = player:getUsername() })
end

-- 每個指令只讀自己的純量欄位；突變點自己做全量驗證
local HANDLERS = {
    [W.CMD_BATTERY] = function(player, args)
        return W.applyBatteryChange(player, args.watchId, args.install, args.batteryId)
    end,
    [W.CMD_LIGHT] = function(player, args)
        return W.applyLight(player, args.on)
    end,
    [W.CMD_MODULE] = function(player, args)
        return W.applyModuleChange(player, args.watchId, args.slotId, args.install, args.itemId)
    end,
    [W.CMD_UNLOCK] = function(player, args)
        return W.applyUnlock(player, args.slotId, args.cardId)
    end,
    [W.CMD_SCREEN] = function(player, args)
        return W.applyScreen(player, args.watchId, args.choice)
    end,
}

-- OnClientCommand(module, command, player, args)：player 是伺服器用連線反查出來的（LuaManager.java:8940、
-- 原版 ClientCommands.lua:1307），payload 指定不了別人。
local function onClientCommand(module, command, player, args)
    if module ~= W.MODULE or not player then return end
    local key = tostring(player:getUsername()) .. ":" .. tostring(player:getOnlineID())
    local now = getTimestampMs()
    if command == W.CMD_UNLOCKS_REQ then
        if not throttled(key .. ":u", now) then W.pushUnlocks(player) end
        return
    end
    local handler = HANDLERS[command]
    if not handler or type(args) ~= "table" or throttled(key, now) then return end
    local ok, reason = handler(player, args)
    if not ok then notifyFail(player, reason or W.FAIL_GENERIC) end
end

Events.OnClientCommand.Add(onClientCommand)

-- ===== 陣營分享的通訊距離（Phase 7）=====
-- 守衛先於註冊：主 MOD 的 server 檔依 MOD 載入序先跑（LoadDirBase 逐 MOD 載入，LuaManager.java:1153-1189；
-- require= 讓主 MOD 排在前面），所以檔案頂層就查得到 API。太舊或註冊失敗＝分享照舊不限距離，log 一次；
-- 管理員提示在客戶端（MinidoracatWatch_Client.lua registerGate，主 MOD 的 server 檔在客戶端也會載入）。
-- 撤回（clearShared）主 MOD 不過濾，收過舊座標的人一定收得到撤回。
local S = W.shareApi()
local ok, res = false, nil
if S then ok, res = pcall(S.registerShareFilter, W.MOD_ID, W.shareAllowed) end
W.shareFilterActive = ok and res == true
if not W.shareFilterActive then
    W.log("MinidoracatMiniMapServerAPI.shareApiVersion >= 1 not found: faction sharing has no comm range")
end
