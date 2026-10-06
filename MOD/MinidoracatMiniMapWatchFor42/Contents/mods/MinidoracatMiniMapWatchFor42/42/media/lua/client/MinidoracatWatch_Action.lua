-- MinidoracatWatch_Action.lua：地圖錶的計時動作——裝卸模組（約 3 秒）、換電池（約 1 秒）。
-- 只在客戶端（與單機）跑，**不定義 complete**：有 complete 的動作在 MP 會變成伺服器照 new() 參數重建的
-- NetTimedAction，連 character 都由客戶端指定、可以冒充別人（NetTimedAction.java:36-55、142-170；
-- 沒有 complete＝useCustomRemoteTimedActionSync，LuaTimedActionNew.java:76-78）。perform 只送純量指令，
-- 伺服器以連線身分重新解析與驗證（照 AutoDrive ISAutoDriveDeviceAction）；單機直接呼叫同一份 shared 突變點。
-- 走動、跑步、瞄準會中斷（ISBaseTimedAction.new 的 stopOnWalk／stopOnRun／stopOnAim），模組與電池留在背包。
require "TimedActions/ISBaseTimedAction"
require "MinidoracatWatch"
local W = MinidoracatWatchCore

ISMinidoracatWatchAction = ISBaseTimedAction:derive("ISMinidoracatWatchAction")

-- maxTime 的單位是 GameTime multiplier：timeDelta＝m／0.8／60（GameTime.java:999），一秒約 48
local MODULE_TIME, BATTERY_TIME = 150, 50

local function has(inv, item) return item ~= nil and inv:getItemWithIDRecursiv(item:getID()) ~= nil end

function ISMinidoracatWatchAction:isValid()
    local inv = self.character:getInventory()
    if not has(inv, self.watch) then return false end
    if self.install and not has(inv, self.item) then return false end
    if self.kind == "module" and W.needScrewdriver() and not W.hasScrewdriver(self.character) then return false end
    return true
end

function ISMinidoracatWatchAction:perform()
    local p = self.character
    local watchId = self.watch:getID()
    local itemId = self.item and self.item:getID() or nil
    local ok, reason = true, nil
    if self.kind == "module" then
        if isClient() then
            sendClientCommand(p, W.MODULE, W.CMD_MODULE,
                { watchId = watchId, slotId = self.slotId, install = self.install, itemId = itemId })
        else
            ok, reason = W.applyModuleChange(p, watchId, self.slotId, self.install, itemId)
        end
    else
        if isClient() then
            sendClientCommand(p, W.MODULE, W.CMD_BATTERY, { watchId = watchId, install = self.install, batteryId = itemId })
        else
            ok, reason = W.applyBatteryChange(p, watchId, self.install, itemId)
        end
    end
    if not ok then W.notify(p, reason or W.FAIL_GENERIC) end
    ISBaseTimedAction.perform(self)
end

function ISMinidoracatWatchAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return self.kind == "module" and MODULE_TIME or BATTERY_TIME
end

-- kind："module"（item＝要裝的模組、nil＝拆下 slotId 那格）或 "battery"（install＝裝入 item 那顆電池）
function ISMinidoracatWatchAction:new(character, kind, watch, slotId, item, install)
    local o = ISBaseTimedAction.new(self, character)
    o.kind, o.watch, o.slotId, o.item, o.install = kind, watch, slotId, item, install == true
    o.maxTime = o:getDuration()
    return o
end
