-- MinidoracatWatch_Client.lua：小地圖閘門、家族工具列按鈕、最小電池面板、錶的右鍵選單。
-- 客戶端只讀錶的 modData、送換電池請求；扣電與換電池的權威在伺服器（單機在本機）。
require "MinidoracatWatch"
require "ISUI/ISPanel"
require "ISUI/ISButton"
local W = MinidoracatWatchCore
local C = {}
MinidoracatWatchClient = C -- 內部表（測試與 E2E 用），不是公開 API

-- ===== 戴著的錶（每位本機玩家一格快取）=====
-- gateFn 與 Dock 回呼可能每幀被叫：不翻背包、不配置 table。穿脫衣物會觸發 OnClothingUpdated
-- （本機 setWornItem＝IsoGameCharacter.java:3573、伺服器同步＝SyncClothingPacket.java:222-226），
-- 事件只把世代號 +1；另有 1 秒的保險期限（漏事件時最多晚 1 秒）。電量每次直接讀快取物品的 modData，
-- 伺服器同步過來的 modData 是寫進同一件物品（SyncItemModDataPacket），不必失效。
local CACHE_TTL_MS = 1000
local gen = 0
local cacheItem, cacheGen, cacheAt, warnedTwo = {}, {}, {}, {}

local function refresh(pn, now)
    local player = getSpecificPlayer(pn)
    local item, count = nil, 0
    if player then
        item, count = W.wornWatch(player)
        -- SyncClothing 先於物品封包到時，客戶端會臨時建一件同 ID 的物品掛在身上（SyncClothingPacket.java:192-199），
        -- 它沒有 modData；改讀背包裡同 ID 的那件。穿著的物品仍在主背包（IsoGameCharacter.java:3427-3490）。
        if item then
            local real = player:getInventory():getItemWithID(item:getID()) -- ItemContainer.java:3112
            if real then item = real end
        end
        if count > 1 then
            if not warnedTwo[pn] then
                warnedTwo[pn] = true
                if HaloTextHelper then HaloTextHelper.addBadText(player, getText("IGUI_MinidoracatWatch_TwoWorn")) end
            end
        else
            warnedTwo[pn] = nil
        end
    end
    cacheItem[pn] = item or false
    cacheGen[pn] = gen
    cacheAt[pn] = now
end

function C.watchOf(pn)
    local now = getTimestampMs()
    local at = cacheAt[pn]
    if cacheGen[pn] ~= gen or not at or now < at or now - at >= CACHE_TTL_MS then refresh(pn, now) end
    return cacheItem[pn] or nil
end

Events.OnClothingUpdated.Add(function() gen = gen + 1 end)

-- ===== 小地圖閘門 =====
-- 只管 "minimap"；其他 feature 一律放行（Phase 3 才閘）。
function C.gate(pn, feature)
    if feature ~= "minimap" then return true end
    local enabled, rule = W.enabled(), W.minimapRule()
    if not enabled or rule ~= W.RULE_WATCH then return W.minimapDecision(enabled, rule, false, nil) end
    local watch = C.watchOf(pn)
    if not watch then return W.minimapDecision(enabled, rule, false, nil) end
    return W.minimapDecision(enabled, rule, true, W.charge(watch))
end

-- 守衛先於註冊：主 MOD 太舊（沒有 featureApiVersion 1）就不設閘＝小地圖照舊開放，log 一次並提示管理員，
-- 不讓伺服器以為鎖了其實沒鎖。註冊放 OnGameStart：所有 MOD 的 client 檔都已載入。
C.gateActive = false
local function adminNotice()
    Events.OnTick.Remove(adminNotice)
    if not W.enabled() then return end
    local player = getSpecificPlayer(0)
    -- isAdmin() 只在 MP 客戶端為真（LuaManager.java:9032-9038）；單機玩家就是自己的管理員
    if player and HaloTextHelper and (not isClient() or isAdmin()) then
        HaloTextHelper.addBadText(player, getText("IGUI_MinidoracatWatch_ApiMissing"))
    end
end

function C.registerGate()
    local API = MinidoracatMiniMapAPI
    if type(API) == "table" and type(API.featureApiVersion) == "number" and API.featureApiVersion >= 1
            and type(API.registerFeatureGate) == "function" then
        local ok, res = pcall(API.registerFeatureGate, W.MOD_ID, C.gate)
        C.gateActive = ok and res == true
    end
    if C.gateActive then return end
    W.log("MinidoracatMiniMapAPI.featureApiVersion >= 1 not found: the minimap stays open without a watch")
    Events.OnTick.Add(adminNotice) -- halo 要等玩家在場：第一個 tick 再提示
end
Events.OnGameStart.Add(C.registerGate)

-- ===== 文字 =====
local function timeText(charge, fullHours)
    local d, h = W.timeLeft(charge, fullHours)
    if d == 0 and h == 0 then return getText("IGUI_MinidoracatWatch_TimeUnderHour") end
    if d == 0 then return getText("IGUI_MinidoracatWatch_TimeHours", tostring(h)) end
    if h == 0 then return getText("IGUI_MinidoracatWatch_TimeDays", tostring(d)) end
    return getText("IGUI_MinidoracatWatch_TimeDaysHours", tostring(d), tostring(h))
end

local function percent(charge) return math.ceil(charge * 100) end

function C.statusText(watch)
    if not watch then return getText("IGUI_MinidoracatWatch_Status_NoWatch") end
    local c = W.charge(watch)
    if c == nil then return getText("IGUI_MinidoracatWatch_Status_NoBattery") end
    if c <= 0 then return getText("IGUI_MinidoracatWatch_Status_Dead") end
    return getText("IGUI_MinidoracatWatch_Status_Charge", tostring(percent(c)), timeText(c, W.fullHours()))
end

-- ===== 電池圖示（Dock 與面板共用；不配置 table）=====
local function drawBattery(el, x, y, size, watch)
    local c = watch and W.charge(watch)
    local bw, bh = math.floor(size * 0.72), math.floor(size * 0.42)
    local bx, by = x + math.floor((size - bw) / 2) - 1, y + math.floor((size - bh) / 2)
    local a = watch and 1 or 0.4
    el:drawRectBorder(bx, by, bw, bh, a, 0.85, 0.85, 0.85)
    el:drawRect(bx + bw, by + math.floor(bh / 4), 2, math.floor(bh / 2), a, 0.85, 0.85, 0.85)
    if c and c > 0 then
        local r, g, b = 0.55, 0.85, 0.55
        if c <= W.LOW_CHARGE then r, g, b = 1, 0.65, 0.2 end
        el:drawRect(bx + 2, by + 2, math.max(1, math.floor((bw - 4) * c)), bh - 4, 1, r, g, b)
    elseif watch then
        el:drawRect(bx + 2, by + 2, bw - 4, bh - 4, 0.35, 0.9, 0.3, 0.3)
    end
end

-- ===== 換電池請求 =====
-- 背包樹裡電量最高的電池（ItemContainer.getAllTypeRecurse(String)＝ItemContainer.java:1948；
-- 全名比對 :1197-1201）。只在使用者操作與面板 update（約 100ms）時呼叫，不在閘門熱路徑。
function C.bestBattery(player)
    local list = player:getInventory():getAllTypeRecurse(W.BATTERY_TYPE)
    local best, bestC = nil, -1
    for i = 0, list:size() - 1 do
        local b = list:get(i)
        local c = b:getCurrentUsesFloat()
        if c > bestC then best, bestC = b, c end
    end
    return best
end

-- MP：只送純量，伺服器以連線身分重新解析並全量驗證（server/MinidoracatWatch_Server.lua）。
-- sendClientCommand(player, module, command, args)＝LuaManager.java:8932-8950。
-- 單機：直接呼叫同一份 shared 突變點（不經 OnClientCommand，不會重複執行）。
function C.requestBattery(player, watch, install)
    if not player or not watch then return end
    local batteryId
    if install then
        local b = C.bestBattery(player)
        if not b then return end
        batteryId = b:getID()
    end
    if isClient() then
        sendClientCommand(player, W.MODULE, W.CMD_BATTERY,
            { watchId = watch:getID(), install = install, batteryId = batteryId })
        return
    end
    local ok, reason = W.applyBatteryChange(player, watch:getID(), install, batteryId)
    if not ok then W.notify(player, reason or W.FAIL_GENERIC) end
end

-- 伺服器的失敗回報：只認白名單內的鍵，依 to 找本機玩家（分割畫面共用連線）
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= W.MODULE or command ~= W.CMD_FAILED or type(args) ~= "table" then return end
    if not W.FAIL_KEYS[args.reason] then return end
    for pn = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(pn)
        if p and p:getUsername() == args.to then W.notify(p, args.reason) end
    end
end)

-- ===== 最小電池面板（Phase 2：電量、大約還能用多久、裝入／取出電池）=====
local Panel = ISPanel:derive("MinidoracatWatchPanel")
local panel -- 單例
local PAD, BTN_H = 10, 24

function Panel:createChildren()
    local by = self.height - BTN_H - PAD
    self.btnInsert = ISButton:new(PAD, by, 150, BTN_H, getText("IGUI_MinidoracatWatch_InsertBattery"), self, Panel.onInsert)
    self.btnInsert:initialise()
    self:addChild(self.btnInsert)
    self.btnRemove = ISButton:new(PAD + 160, by, 150, BTN_H, getText("IGUI_MinidoracatWatch_RemoveBattery"), self, Panel.onRemove)
    self.btnRemove:initialise()
    self:addChild(self.btnRemove)
    self.btnClose = ISButton:new(self.width - 22 - PAD / 2, PAD / 2, 22, 22, "X", self, Panel.onClose)
    self.btnClose:initialise()
    self:addChild(self.btnClose)
end

-- 面板對象：從右鍵選單開的那支（還在玩家身上時），否則是戴著的那支
function Panel:target()
    local player = getSpecificPlayer(self.playerNum)
    if not player then return nil, nil end
    local w = self.watchItem
    if w and player:getInventory():getItemWithIDRecursiv(w:getID()) ~= w then
        w = nil
        self.watchItem = nil
    end
    return player, w or C.watchOf(self.playerNum)
end

function Panel:update()
    ISPanel.update(self)
    local player, w = self:target()
    local c = w and W.charge(w)
    self.btnInsert:setTitle(getText(c ~= nil and "IGUI_MinidoracatWatch_ReplaceBattery" or "IGUI_MinidoracatWatch_InsertBattery"))
    self.btnInsert:setEnable(w ~= nil and C.bestBattery(player) ~= nil)
    self.btnRemove:setEnable(w ~= nil and c ~= nil)
end

function Panel:prerender()
    ISPanel.prerender(self)
    local _, w = self:target()
    local title = w and w:getDisplayName() or getText("IGUI_MinidoracatWatch_DockLabel")
    self:drawText(title, PAD, PAD, 1, 1, 1, 1, UIFont.Medium)
    local c = w and W.charge(w)
    local right = self.width - 22 - PAD
    if c ~= nil then
        local pct = percent(c) .. "%"
        local tw = getTextManager():MeasureStringX(UIFont.Small, pct)
        self:drawText(pct, right - tw - 6, PAD + 2, 1, 1, 1, 1, UIFont.Small)
        right = right - tw - 6
    end
    drawBattery(self, right - 30, PAD - 4, 28, w)
    local fh = getTextManager():getFontHeight(UIFont.Small)
    local y = PAD + getTextManager():getFontHeight(UIFont.Medium) + 8
    self:drawText(C.statusText(w), PAD, y, 0.9, 0.9, 0.9, 1, UIFont.Small)
    if w then
        self:drawText(getText("IGUI_MinidoracatWatch_FullRuntime", timeText(1, W.fullHours())),
            PAD, y + fh + 2, 0.6, 0.6, 0.6, 1, UIFont.Small)
    end
end

function Panel:onInsert()
    local player, w = self:target()
    C.requestBattery(player, w, true)
end

function Panel:onRemove()
    local player, w = self:target()
    C.requestBattery(player, w, false)
end

function Panel:onClose() C.closePanel() end

function C.closePanel()
    if panel then panel:removeFromUIManager() end
    panel = nil
end

function C.openPanel(pn, watchItem)
    C.closePanel()
    local w, h = 360, 120
    local o = ISPanel.new(Panel, math.floor((getCore():getScreenWidth() - w) / 2),
        math.floor(getCore():getScreenHeight() * 0.3), w, h)
    o.moveWithMouse = true
    o.backgroundColor = { r = 0.06, g = 0.07, b = 0.08, a = 0.94 }
    o.borderColor = { r = 0.45, g = 0.47, b = 0.5, a = 1 }
    o.playerNum = pn
    o.watchItem = watchItem
    o:initialise()
    o:addToUIManager()
    panel = o
end

function C.togglePanel(pn)
    if panel then C.closePanel() else C.openPanel(pn, nil) end
end

function C.isPanelOpen() return panel ~= nil end

-- ===== 家族工具列（Dock，UI 框架 API rev 13）=====
-- 回呼可能每幀被叫：不建 table。框架缺席、版本不足或登記失敗＝沒有工具列按鈕，面板仍可從錶的右鍵選單開啟。
local DOCK_SPEC = {
    id = "minimapwatch",
    order = 12,
    label = function() return getText("IGUI_MinidoracatWatch_DockLabel") end,
    drawIcon = function(btn, x, y, size) drawBattery(btn, x, y, size, C.watchOf(0)) end,
    getStatus = function() return C.statusText(C.watchOf(0)) end,
    getState = function()
        local w = C.watchOf(0)
        if not w then return nil end
        local c = W.charge(w)
        if c == nil or c <= W.LOW_CHARGE then return "warn" end
        return nil
    end,
    getBadge = function()
        local w = C.watchOf(0)
        if not w then return 0 end
        local c = W.charge(w)
        if c == nil or c <= 0 then return -1 end
        return 0
    end,
    isActive = function() return panel ~= nil end,
    isAvailable = function() return W.enabled() end,
    onClick = function() C.togglePanel(0) end,
}

do
    local ui = MinidoracatUI and MinidoracatUI.v1
    C.docked = false
    if ui and ui.API_MAJOR == 1 and type(ui.API_REVISION) == "number" and ui.API_REVISION >= 13
            and ui.CAPABILITIES and ui.CAPABILITIES.dock == true and ui.Dock then
        local ok, res = pcall(ui.Dock.register, DOCK_SPEC)
        C.docked = ok and res == true
    end
    if not C.docked then W.log("family Dock unavailable: open the watch panel from the watch context menu") end
end

-- ===== 錶的右鍵選單 =====
-- OnFillInventoryObjectContextMenu(playerNum, context, items)：items 是物品或 { items = {...} } 疊
-- （ISInventoryPaneContextMenu.lua:128-137、:935）
local function onContextOpen(watch, pn) C.openPanel(pn, watch) end
local function onContextBattery(watch, pn, install) C.requestBattery(getSpecificPlayer(pn), watch, install) end

Events.OnFillInventoryObjectContextMenu.Add(function(pn, context, items)
    if not W.enabled() then return end
    local player = getSpecificPlayer(pn)
    if not player then return end
    local inv = player:getInventory()
    for _, v in ipairs(items) do
        local item = v
        if not instanceof(v, "InventoryItem") then item = v.items and v.items[1] end
        if W.isWatch(item) and inv:getItemWithIDRecursiv(item:getID()) == item then
            context:addOption(getText("IGUI_MinidoracatWatch_Open"), item, onContextOpen, pn)
            local hasBattery = W.charge(item) ~= nil
            if C.bestBattery(player) then
                context:addOption(getText(hasBattery and "IGUI_MinidoracatWatch_ReplaceBattery"
                    or "IGUI_MinidoracatWatch_InsertBattery"), item, onContextBattery, pn, true)
            end
            if hasBattery then
                context:addOption(getText("IGUI_MinidoracatWatch_RemoveBattery"), item, onContextBattery, pn, false)
            end
            return
        end
    end
end)
