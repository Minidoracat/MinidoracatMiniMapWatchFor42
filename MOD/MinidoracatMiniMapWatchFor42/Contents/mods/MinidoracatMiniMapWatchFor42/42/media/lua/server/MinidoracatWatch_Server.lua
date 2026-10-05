-- MinidoracatWatch_Server.lua：換電池的伺服器權威入口（MP）。
-- MP 客戶端也會載入 media/lua/server（GameLoadingState.java:148），所以先以 isClient() 早退。
-- 單機不經這裡：客戶端直接呼叫 shared 的 applyBatteryChange（不發指令，不會重複執行）。
if isClient() then return end

require "MinidoracatWatch"
local W = MinidoracatWatchCore

-- per-player 節流：OnClientCommand 在伺服器主執行緒同步執行，偽造封包每次都會觸發背包重解析。
-- 合法操作是玩家點選單，間隔遠大於此。
local MIN_INTERVAL_MS = 250
local THROTTLE_TTL_MS = 60000
local lastAt, lastSweepMs = {}, 0

-- 失敗回報只送伺服器自己選的常數鍵；帶 to（角色名）讓同機分割畫面知道是哪位本機玩家。
-- sendServerCommand(player, module, command, args)＝LuaManager.java:8962-8970
local function notifyFail(player, reason)
    sendServerCommand(player, W.MODULE, W.CMD_FAILED, { reason = reason, to = player:getUsername() })
end

-- OnClientCommand(module, command, player, args)：player 是伺服器用連線反查出來的（LuaManager.java:8940、
-- 原版 ClientCommands.lua:1307），payload 指定不了別人。args 只讀 watchId／install／batteryId 三個純量。
local function onClientCommand(module, command, player, args)
    if module ~= W.MODULE or command ~= W.CMD_BATTERY or not player then return end
    if type(args) ~= "table" then return end
    local key = tostring(player:getUsername()) .. ":" .. tostring(player:getOnlineID())
    local now = getTimestampMs()
    if now < lastSweepMs or now - lastSweepMs >= THROTTLE_TTL_MS then
        for k, at in pairs(lastAt) do
            if now < at or now - at >= THROTTLE_TTL_MS then lastAt[k] = nil end
        end
        lastSweepMs = now
    end
    local last = lastAt[key]
    if last and now >= last and now - last < MIN_INTERVAL_MS then return end
    lastAt[key] = now
    local ok, reason = W.applyBatteryChange(player, args.watchId, args.install, args.batteryId)
    if not ok then notifyFail(player, reason or W.FAIL_GENERIC) end
end

Events.OnClientCommand.Add(onClientCommand)
