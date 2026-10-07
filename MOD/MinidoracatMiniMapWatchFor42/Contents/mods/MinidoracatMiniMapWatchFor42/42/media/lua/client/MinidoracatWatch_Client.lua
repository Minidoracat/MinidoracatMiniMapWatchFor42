-- MinidoracatWatch_Client.lua：功能閘門、家族工具列按鈕、請求（換電池／裝卸模組／解鎖卡）、右鍵選單。
-- 客戶端只讀錶的 modData、送請求；扣電、裝卸與解鎖的權威在伺服器（單機在本機）。面板在 MinidoracatWatch_Panel.lua。
require "MinidoracatWatch"
require "MinidoracatWatch_Action"
local W = MinidoracatWatchCore
local C = {}
MinidoracatWatchClient = C -- 內部表（測試與 E2E 用），不是公開 API

-- ===== 戴著的錶 =====
-- gateFn 與 Dock 回呼可能每幀被叫：一律讀 shared 狀態快取 W.status（期限 1 秒，不翻背包、不配置 table）。
-- 穿脫衣物會觸發 OnClothingUpdated（本機 setWornItem＝IsoGameCharacter.java:3573、伺服器同步＝
-- SyncClothingPacket.java:222-226）：讓快取立刻失效。電量每次直接讀錶的 modData，伺服器同步過來的 modData
-- 是寫進同一件物品（SyncItemModDataPacket）。
function C.watchOf(pn)
    local p = getSpecificPlayer(pn)
    return p and W.status(p).watch or nil
end

Events.OnClothingUpdated.Add(function() W.invalidate() end)

-- ===== 功能閘門 =====
-- 自駕 GPS「任一即可」：AutoDrive 的 hasNavDevice（隨身充電 GPS 或所在車輛有電的 GPS）也放行 nav；
-- 規則是「關閉」時一律擋。守衛：表存在、版本 >= 1、函式存在，pcall（拋錯當沒有、只 log 一次）。
local navErrLogged = false
function C.navDevice(pn)
    local api = MinidoracatAutoDriveAPI
    if type(api) ~= "table" or type(api.navDeviceApiVersion) ~= "number" or api.navDeviceApiVersion < 1
            or type(api.hasNavDevice) ~= "function" then
        return false
    end
    local ok, has = pcall(api.hasNavDevice, pn)
    if not ok then
        if not navErrLogged then
            navErrLogged = true
            W.log("MinidoracatAutoDriveAPI.hasNavDevice failed: " .. tostring(has))
        end
        return false
    end
    return has == true
end

function C.gate(pn, feature, surface)
    local player = getSpecificPlayer(pn)
    if feature == "minimap" then
        local enabled, rule = W.enabled(), W.minimapRule()
        if not enabled or rule ~= W.RULE_WATCH then return W.minimapDecision(enabled, rule, false, nil) end
        local watch = player and W.status(player).watch
        if not watch then return W.minimapDecision(enabled, rule, false, nil) end
        return W.minimapDecision(enabled, rule, true, W.power(watch), W.deadKeepsMinimap())
    end
    local ok, reason, dist = W.featureDecision(player, feature, surface)
    if not ok and feature == "nav" and reason ~= W.REASON_FEATURE_OFF and C.navDevice(pn) then return true end
    return ok, reason, dist
end

-- 守衛先於註冊：主 MOD 太舊（沒有 featureApiVersion 1）就不設閘＝小地圖照舊開放，log 一次並提示管理員，
-- 不讓伺服器以為鎖了其實沒鎖。註冊放 OnGameStart：所有 MOD 的 client 檔都已載入。
-- MP 另查主 MOD 的伺服器分享過濾 API（伺服器會自己 log；主 MOD 的 server 檔在客戶端也會載入，GameLoadingState.java:148
-- 早於 OnGameStart＝IngameState.java:766，兩端是同一版主 MOD）：太舊＝通訊距離沒生效，也提示管理員。
C.gateActive = false
local notices = {}
local function adminNotice()
    Events.OnTick.Remove(adminNotice)
    local player = getSpecificPlayer(0)
    -- isAdmin() 只在 MP 客戶端為真（LuaManager.java:9032-9038）；單機玩家就是自己的管理員
    if W.enabled() and player and HaloTextHelper and (not isClient() or isAdmin()) then
        for _, key in ipairs(notices) do HaloTextHelper.addBadText(player, getText(key)) end
    end
    notices = {}
end

function C.registerGate()
    local API = MinidoracatMiniMapAPI
    if type(API) == "table" and type(API.featureApiVersion) == "number" and API.featureApiVersion >= 1
            and type(API.registerFeatureGate) == "function" then
        local ok, res = pcall(API.registerFeatureGate, W.MOD_ID, C.gate)
        C.gateActive = ok and res == true
    end
    if not C.gateActive then
        W.log("MinidoracatMiniMapAPI.featureApiVersion >= 1 not found: the minimap stays open without a watch")
        notices[#notices + 1] = "IGUI_MinidoracatWatch_ApiMissing"
    end
    if isClient() and not W.shareApi() and W.featureRule("share") ~= W.RULE_FREE then
        notices[#notices + 1] = "IGUI_MinidoracatWatch_ShareApiMissing"
    end
    if #notices > 0 then Events.OnTick.Add(adminNotice) end -- halo 要等玩家在場：第一個 tick 再提示
end
Events.OnGameStart.Add(C.registerGate)

-- ===== 文字 =====
-- 這支錶目前的滿電續航（小時）：滿電小時數 ÷ 耗電倍率（模組、節能核心）
function C.fullRuntime(player, watch)
    if not player or not watch then return W.fullHours() end
    return W.fullHours() / W.drainFactor(player, watch)
end

function C.timeText(charge, hours)
    local d, h = W.timeLeft(charge, hours)
    if d == 0 and h == 0 then return getText("IGUI_MinidoracatWatch_TimeUnderHour") end
    if d == 0 then return getText("IGUI_MinidoracatWatch_TimeHours", tostring(h)) end
    if h == 0 then return getText("IGUI_MinidoracatWatch_TimeDays", tostring(d)) end
    return getText("IGUI_MinidoracatWatch_TimeDaysHours", tostring(d), tostring(h))
end

function C.percent(charge) return math.ceil(charge * 100) end

function C.statusText(watch, player)
    if not watch then return getText("IGUI_MinidoracatWatch_Status_NoWatch") end
    if not W.needBattery() then return getText("IGUI_MinidoracatWatch_Status_NoBatteryNeeded") end
    local c = W.charge(watch)
    if c == nil then return getText("IGUI_MinidoracatWatch_Status_NoBattery") end
    if c <= 0 then return getText("IGUI_MinidoracatWatch_Status_Dead") end
    local hours = C.fullRuntime(player, watch)
    local d, h = W.timeLeft(c, hours)
    if d == 0 and h == 0 then return getText("IGUI_MinidoracatWatch_Status_ChargeUnderHour", tostring(C.percent(c))) end
    return getText("IGUI_MinidoracatWatch_Status_Charge", tostring(C.percent(c)), C.timeText(c, hours))
end

-- ===== 家族 UI 框架 =====
-- 面板、Dock、通知都用框架元件（規劃書 §0）：API rev 14（Window、Button 的 Texture 圖示與 setIcon、battery 等圖示、
-- onAccent／titleText token）＋controls＋window。不足＝回 nil：面板開不了（提示一次）、沒有 Dock、通知退回 HaloText。
function C.ui()
    local UI = MinidoracatUI and MinidoracatUI.v1
    local caps = UI and UI.CAPABILITIES
    if UI and UI.API_MAJOR == 1 and type(UI.API_REVISION) == "number" and UI.API_REVISION >= 14 and caps
            and caps.controls == true and caps.window == true and UI.Window and UI.Button and UI.Icons then
        return UI
    end
    return nil
end

-- 面板、付款與重要事件的通知：右上角 Toast（面板開著時避開面板，見 Panel 的 Toast.setAvoid）；框架缺席退回角色頭上的字
function C.toast(player, text, title)
    local UI = C.ui()
    if UI and UI.CAPABILITIES.toast and UI.Toast then
        UI.Toast.show({ title = title, message = text, maxLines = 3 })
    elseif player and HaloTextHelper then
        HaloTextHelper.addBadText(player, title and (title .. " " .. text) or text)
    end
end

-- ===== 請求 =====
-- 背包樹裡電量最高的電池（ItemContainer.getAllTypeRecurse(String)＝ItemContainer.java:1948；
-- 全名比對 :1197-1201）。只在使用者操作與面板 update 時呼叫，不在閘門熱路徑。
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

-- 換電池與裝卸模組都是計時動作（MinidoracatWatch_Action.lua）：完成時才送純量指令或在單機直接套用。
function C.requestBattery(player, watch, install)
    if not player or not watch then return end
    local battery = nil
    if install then
        battery = C.bestBattery(player)
        if not battery then return end
    end
    ISTimedActionQueue.add(ISMinidoracatWatchAction:new(player, "battery", watch, nil, battery, install))
end

-- item＝要裝進 slotId 的模組；nil＝拆下 slotId 那格的模組（孤立槽位也能拆：錶上有紀錄就排動作，伺服器再驗）
function C.requestModule(player, watch, slotId, item)
    if not player or not watch then return end
    if not (W.slotById[slotId] or (item == nil and W.slotRecord(watch, slotId))) then return end
    if W.needScrewdriver() and not W.hasScrewdriver(player) then
        W.notify(player, W.FAIL_SCREWDRIVER)
        return
    end
    ISTimedActionQueue.add(ISMinidoracatWatchAction:new(player, "module", watch, slotId, item, item ~= nil))
end

function C.cards(player, slot)
    local t = W.cardType(slot)
    if not t then return nil end
    return player:getInventory():getAllTypeRecurse(t)
end

-- 解鎖卡不經計時動作（不需要工具、沒有物品移進錶裡）：MP 送純量、單機直接套用
function C.requestUnlock(player, slotId)
    local slot = player and W.slotById[slotId]
    local list = slot and C.cards(player, slot)
    if not list or list:size() == 0 then return end
    local cardId = list:get(0):getID()
    if isClient() then
        sendClientCommand(player, W.MODULE, W.CMD_UNLOCK, { slotId = slotId, cardId = cardId })
        return
    end
    local ok, reason = W.applyUnlock(player, slotId, cardId)
    if not ok then W.notify(player, reason) end
end

-- 嗶嗶腕機的螢幕顏色（純外觀，不經計時動作）：MP 送純量、單機直接套用；外觀由伺服器／單機的 W.showScreen 套
function C.requestScreen(player, watch)
    if not player or not W.hasScreen(watch) then return end
    local choice = 1 - W.screenOf(watch)
    if isClient() then
        sendClientCommand(player, W.MODULE, W.CMD_SCREEN, { watchId = watch:getID(), choice = choice })
        return
    end
    local ok, reason = W.applyScreen(player, watch:getID(), choice)
    if not ok then W.notify(player, reason) end
end

function C.screenLabel(watch)
    return getText(W.screenOf(watch) == 1 and "IGUI_MinidoracatWatch_ScreenGreen" or "IGUI_MinidoracatWatch_ScreenAmber")
end

-- 伺服器廣播的螢幕顏色（沒有 to：所有連線都收）。pid 找不到＝那位玩家還沒載入，之後的 ConnectedPacket 會帶伺服器的外觀。
-- 遠端玩家畫的是 remotePlayerItemVisuals（IsoPlayer.java:7684-7689），本機玩家畫 WornItems 的 visual：兩邊都改，
-- 有改才 resetModelNextFrame。
function C.onScreen(args)
    local choice = args.choice
    if not W.isFiniteInt(args.pid) or (choice ~= 0 and choice ~= 1) then return end
    local p = getPlayerByOnlineID(args.pid) -- LuaManager.java:3940-3945
    if not p then return end
    local changed = false
    local worn = p:getWornItems()
    for i = 0, (worn and worn:size() or 0) - 1 do
        local it = worn:get(i):getItem()
        if W.hasScreen(it) and W.setChoice(it:getVisual(), choice) then changed = true end
    end
    local vis = p:getItemVisuals()
    for i = 0, (vis and vis:size() or 0) - 1 do
        local v = vis:get(i)
        if W.SCREEN_TYPES[v:getItemType()] and W.setChoice(v, choice) then changed = true end
    end
    if changed then p:resetModelNextFrame() end
end

-- 伺服器回報：失敗只認白名單內的鍵；解鎖狀態只收「槽位 id＝true」。依 to 找本機玩家（分割畫面共用連線）
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= W.MODULE or type(args) ~= "table" then return end
    if command == W.CMD_SCREEN then return C.onScreen(args) end
    if type(args.to) ~= "string" then return end
    if command == W.CMD_FAILED then
        if not W.FAIL_KEYS[args.reason] then return end
        for pn = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(pn)
            if p and p:getUsername() == args.to then W.notify(p, args.reason) end
        end
    elseif command == W.CMD_UNLOCKS and type(args.slots) == "table" then
        local slots = {}
        for k, v in pairs(args.slots) do
            if type(k) == "string" and v == true then slots[k] = true end
        end
        W.clientUnlocks[args.to] = slots
        W.invalidate()
    elseif command == W.CMD_MODULE then
        -- 伺服器確認裝卸成功（MinidoracatWatch_Server.lua）：只播音效
        for pn = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(pn)
            if p and p:getUsername() == args.to then
                local watch = W.isFiniteInt(args.watchId) and p:getInventory():getItemWithIDRecursiv(args.watchId) or nil
                MinidoracatWatchSound.moduleDone(p, args.install == true, watch)
            end
        end
    end
end)

-- ===== 每秒：戴兩支提示、onStateChanged（客戶端與單機）、MP 補要一次解鎖狀態 =====
-- 伺服器第一次看到玩家時會主動送解鎖狀態（MinidoracatWatch.lua visit）；客戶端在自己第一個 tick 再要一次，
-- 補上「伺服器送的時候客戶端還在載入」的空檔。
local POLL_MS = 1000
local lastPoll = nil
local warnedTwo, asked = {}, {}
function C.poll()
    local now = getTimestampMs()
    if lastPoll and now >= lastPoll and now - lastPoll < POLL_MS then return end
    lastPoll = now
    for pn = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(pn)
        if p and not p:isDead() then
            if isClient() and not asked[pn] then
                asked[pn] = true
                sendClientCommand(p, W.MODULE, W.CMD_UNLOCKS_REQ, {})
            end
            if W.status(p).count > 1 then
                if not warnedTwo[pn] then
                    warnedTwo[pn] = true
                    if HaloTextHelper then HaloTextHelper.addBadText(p, getText("IGUI_MinidoracatWatch_TwoWorn")) end
                end
            else
                warnedTwo[pn] = nil
            end
            if not isServer() then W.pollStateCallbacks(p, pn) end
        end
    end
end
Events.OnTick.Add(C.poll)
Events.OnCreatePlayer.Add(function() W.clearStatus() end) -- 重生是新的 IsoPlayer：舊的快取不留

-- ===== 家族工具列（Dock，UI 框架 API rev 13；電池圖示要 rev 14 的 Icons battery）=====
-- 回呼可能每幀被叫：不建 table。框架缺席、版本不足或登記失敗＝沒有工具列按鈕，面板仍可從錶的右鍵選單開啟；
-- 玩家在「選項 → MODS」關掉 ShowButton 也一樣（快取與套用在 MinidoracatWatch_Sound.lua）。
-- 圖示畫法在 MinidoracatWatch_Panel.lua（C.drawBattery）、配色是預設 theme（MinidoracatWatch_Skins.lua）：呼叫時才取。
local DOCK_SPEC = {
    id = "minimapwatch",
    order = 12,
    label = function() return getText("IGUI_MinidoracatWatch_DockLabel") end,
    drawIcon = function(btn, x, y, size)
        C.drawBattery(btn, x, y, size, C.watchOf(0), C.Skins.defaultTheme(C.ui()))
    end,
    getStatus = function() return C.statusText(C.watchOf(0), getSpecificPlayer(0)) end,
    getState = function()
        local w = C.watchOf(0)
        if not w then return nil end
        local c = W.power(w)
        if c == nil or c <= W.LOW_CHARGE then return "warn" end
        return nil
    end,
    getBadge = function()
        local w = C.watchOf(0)
        if not w then return 0 end
        local c = W.power(w)
        if c == nil or c <= 0 then return -1 end
        return 0
    end,
    isActive = function() return C.isPanelOpen() end,
    isAvailable = function() return MinidoracatWatchSound.showButton and W.enabled() end,
    onClick = function() C.togglePanel(0) end,
}

do
    local ui = C.ui()
    C.docked = false
    if ui and ui.CAPABILITIES.dock == true and ui.Dock then
        local ok, res = pcall(ui.Dock.register, DOCK_SPEC)
        C.docked = ok and res == true
    end
    if not C.docked then W.log("family Dock unavailable: open the watch panel from the watch context menu") end
end

-- ===== 右鍵選單 =====
-- OnFillInventoryObjectContextMenu(playerNum, context, items)：items 是物品或 { items = {...} } 疊
-- （ISInventoryPaneContextMenu.lua:128-137、:935）。子選單照原版 ISContextMenu:getNew／addSubMenu。
function C.slotName(slot) return getText(slot.name) end
-- 這個槽位要用的解鎖卡物品名（其他 MOD 的槽位用擴充槽解鎖卡，不是「槽位名＋解鎖卡」）；getItemNameFromFullType＝LuaManager.java:8603-8608
function C.cardName(slot)
    local t = W.cardType(slot)
    return t and getItemNameFromFullType(t) or ""
end
function C.moduleName(id)
    local def = W.modules[id]
    return def and getText(def.name) or id
end

-- 內建模組的說明；通訊類模組在「需要模組」規則下接上分享距離（範圍從沙盒讀，和伺服器 W.shareAllowed 同一份；
-- 句間空白依語言不同，所以說明本身也當 %1 交給翻譯）
function C.moduleDesc(id)
    if id == "light" then return getText("IGUI_MinidoracatWatch_ModuleDesc_light", tostring(W.lightRadius())) end
    local s = getText("IGUI_MinidoracatWatch_ModuleDesc_" .. id)
    if not W.enabled() or W.featureRule("share") ~= W.RULE_MODULE then return s end
    if id == "relay" then return getText("IGUI_MinidoracatWatch_ShareRangeUnlimited", s) end
    local k = W.SHARE_RANGE[id]
    if not k then return s end
    return getText("IGUI_MinidoracatWatch_ShareRange", s, tostring(math.floor(W.radius(k[1], k[2]))))
end

-- 身上的地圖錶：戴著的那支排第一
function C.watchesOn(player)
    local out = {}
    local worn = W.status(player).watch
    if worn then out[1] = worn end
    for t in pairs(W.WATCH_TYPES) do
        local list = player:getInventory():getAllTypeRecurse(t)
        for i = 0, list:size() - 1 do
            local w = list:get(i)
            if w ~= worn then out[#out + 1] = w end
        end
    end
    return out
end

-- 這個模組能裝進這支錶的哪些槽位：有效、空著、類別相符
function C.installTargets(player, watch, def)
    local out = {}
    local slots = W.slotsOf(watch)
    for _, slot in ipairs(W.slotList) do
        if slot.accepts[def.class] and not (slots and slots[slot.id] ~= nil) and W.slotValid(player, slot) then
            out[#out + 1] = slot
        end
    end
    return out
end

local function subMenu(context, text)
    local opt = context:addOption(text)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(opt, sub)
    return sub, opt
end

local function onOpen(watch, pn) C.openPanel(pn, watch) end
local function onScreen(watch, pn) C.requestScreen(getSpecificPlayer(pn), watch) end
local function onBattery(watch, pn, install) C.requestBattery(getSpecificPlayer(pn), watch, install) end
local function onModule(watch, pn, slotId, item) C.requestModule(getSpecificPlayer(pn), watch, slotId, item) end
local function onUnlock(slotId, pn) C.requestUnlock(getSpecificPlayer(pn), slotId) end

local function watchMenu(context, player, pn, item)
    context:addOption(getText("IGUI_MinidoracatWatch_Open"), item, onOpen, pn)
    local hasBattery = W.charge(item) ~= nil
    if C.bestBattery(player) then
        context:addOption(getText(hasBattery and "IGUI_MinidoracatWatch_ReplaceBattery"
            or "IGUI_MinidoracatWatch_InsertBattery"), item, onBattery, pn, true)
    end
    if hasBattery then
        context:addOption(getText("IGUI_MinidoracatWatch_RemoveBattery"), item, onBattery, pn, false)
    end
    if W.hasScreen(item) then context:addOption(C.screenLabel(item), item, onScreen, pn) end
    local sub = nil
    local function addRemove(slot)
        local rec = W.slotRecord(item, slot.id)
        if rec then
            sub = sub or subMenu(context, getText("IGUI_MinidoracatWatch_RemoveModule"))
            sub:addOption(getText("IGUI_MinidoracatWatch_SlotAndModule", C.slotName(slot), C.moduleName(rec.id)),
                item, onModule, pn, slot.id, nil)
        end
    end
    for _, slot in ipairs(W.slotList) do addRemove(slot) end
    for _, slot in ipairs(W.orphanSlots(item)) do addRemove(slot) end
end

local function moduleMenu(context, player, pn, item, def)
    local any = false
    local sub, opt = subMenu(context, getText("IGUI_MinidoracatWatch_InstallToWatch"))
    for _, w in ipairs(C.watchesOn(player)) do
        for _, slot in ipairs(C.installTargets(player, w, def)) do
            any = true
            sub:addOption(getText("IGUI_MinidoracatWatch_WatchAndSlot", w:getDisplayName(), C.slotName(slot)),
                w, onModule, pn, slot.id, item)
        end
    end
    if not any then
        opt.notAvailable = true
        opt.subOption = nil
    end
end

local function cardMenu(context, player, pn, item)
    local any = false
    local sub, opt = subMenu(context, getText("IGUI_MinidoracatWatch_UseCard"))
    for _, slot in ipairs(W.slotList) do
        if W.cardType(slot) == item:getFullType() and W.acceptsCard(slot) and not W.slotValid(player, slot) then
            any = true
            sub:addOption(getText("IGUI_MinidoracatWatch_OpenSlot", C.slotName(slot)), slot.id, onUnlock, pn)
        end
    end
    if not any then
        opt.notAvailable = true
        opt.subOption = nil
    end
end

local CARD_TYPES = {}
for _, t in pairs(W.CARD_TYPES) do CARD_TYPES[t] = true end

Events.OnFillInventoryObjectContextMenu.Add(function(pn, context, items)
    if not W.enabled() then return end
    local player = getSpecificPlayer(pn)
    if not player then return end
    local inv = player:getInventory()
    for _, v in ipairs(items) do
        local item = v
        if not instanceof(v, "InventoryItem") then item = v.items and v.items[1] end
        if item and inv:getItemWithIDRecursiv(item:getID()) == item then
            local t = item:getFullType()
            if W.isWatch(item) then return watchMenu(context, player, pn, item) end
            local def = W.moduleByItem[t]
            if def then return moduleMenu(context, player, pn, item, def) end
            if CARD_TYPES[t] then return cardMenu(context, player, pn, item) end
        end
    end
end)
