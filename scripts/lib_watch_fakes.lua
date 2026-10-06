-- 地圖錶離線測試共用的假 PZ 全域（test_*.lua 與 smoke_harness.lua 以 dofile 載入）。
-- 形狀照 42.21 反編譯：WornItems 依部位順序排列（WornItems.java:53-82，左腕在右腕前）、
-- 電池用量照 DrainableComboItem（UseDelta 0.007、setCurrentUsesFloat 夾 0..1 後 round，:83-92）、
-- syncItemModData／send* 只在伺服器有作用（LuaManager.java:12326-12334、GameServer.java:2405-2421）。
local F = {}
F.MEDIA = "MOD/MinidoracatMiniMapWatchFor42/Contents/mods/MinidoracatMiniMapWatchFor42/42/media/lua"

F.now = 5000000
F.mode = "server" -- "server"｜"client"｜"sp"
F.paused = false
F.logs, F.halos, F.synced, F.added, F.removed, F.clientCmds, F.serverCmds = {}, {}, {}, {}, {}, {}, {}

function F.reset()
    F.logs, F.halos, F.synced, F.added, F.removed, F.clientCmds, F.serverCmds = {}, {}, {}, {}, {}, {}, {}
end

function getTimestampMs() return F.now end
function isClient() return F.mode == "client" end
function isServer() return F.mode == "server" end
function isGamePaused() return F.paused end
function isAdmin() return F.admin == true end
F.steam = false
function getSteamModeActive() return F.steam end -- LuaManager.java:9359-9364
function getItemNameFromFullType(t) return "item:" .. t end
function getText(key, ...)
    local out = key
    for i = 1, select("#", ...) do
        local a = select(i, ...)
        if a == nil then break end
        out = out .. "|" .. tostring(a)
    end
    return out
end
function instanceof(o, cls) return type(o) == "table" and o._class == cls end
local realPrint = print
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    F.logs[#F.logs + 1] = table.concat(parts, " ")
end
F.print = realPrint

SandboxVars = { MinidoracatWatch = { Enabled = true, MinimapRule = 2, FullHours = 72, DrainOffline = false, DrainPaused = false } }

HaloTextHelper = { addBadText = function(player, text) F.halos[#F.halos + 1] = { player = player, text = text } end }

-- ===== Events =====
F.handlers = {}
Events = setmetatable({}, { __index = function(t, name)
    local ev = {
        Add = function(fn) F.handlers[name] = F.handlers[name] or {}; table.insert(F.handlers[name], fn) end,
        Remove = function(fn)
            local list = F.handlers[name] or {}
            for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
        end,
    }
    rawset(t, name, ev)
    return ev
end })
function F.fire(name, ...)
    local list = {}
    for i, fn in ipairs(F.handlers[name] or {}) do list[i] = fn end
    for _, fn in ipairs(list) do fn(...) end
end

-- ===== Java 風格清單 =====
function F.javaList(items)
    return { size = function() return #items end, get = function(_, i) return items[i + 1] end, _items = items }
end

-- ===== 物品 =====
local nextId = 1000
local function newId() nextId = nextId + 1; return nextId end

local Item = {}
Item.__index = Item
function Item:getID() return self.id end
function Item:getFullType() return self.fullType end
function Item:hasModData() return self.md ~= nil end
function Item:getModData() self.md = self.md or {}; return self.md end
function Item:getContainer() return self.container end
function Item:getDisplayName() return self.fullType end
function Item:isBroken() return self.broken == true end
function Item:getTex() return "tex:" .. self.fullType end
-- ItemVisual：textureChoice 初值 -1（ItemVisual.java:31）；setTextureChoice 只賦值（:735-740）
local Visual = {}
Visual.__index = Visual
function Visual:getTextureChoice() return self.choice end
function Visual:setTextureChoice(c) self.choice = c end
function Visual:getItemType() return self.fullType end
function F.visual(fullType, choice) return setmetatable({ fullType = fullType, choice = choice or -1 }, Visual) end
function Item:getVisual()
    self.visual = self.visual or F.visual(self.fullType)
    return self.visual
end
-- Battery：UseDelta 是 Java float 0.007f（Lua 讀到 0.007000000216066837）；uses 是整數格
function Item:getUseDelta() return self.useDelta end
function Item:getMaxUses() return math.floor(1 / self.useDelta) end
function Item:getCurrentUses() return self.uses end
function Item:setCurrentUses(n)
    assert(math.type and math.type(n) == "integer" or n == math.floor(n), "setCurrentUses needs an int")
    self.uses = n
end
function Item:getCurrentUsesFloat() return self.uses * self.useDelta end
-- DrainableComboItem.setCurrentUsesFloat：夾 0..1 後 Math.round（四捨五入，DrainableComboItem.java:83-87）
function Item:setCurrentUsesFloat(f)
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    self.uses = math.floor(f / self.useDelta + 0.5)
end

F.BATTERY_DELTA = 0.007000000216066837
function F.item(fullType)
    local it = setmetatable({ id = newId(), fullType = fullType, _class = "InventoryItem" }, Item)
    if fullType == "Base.Battery" then
        it.useDelta = F.BATTERY_DELTA
        it.uses = it:getMaxUses() -- 新電池＝getMaxUses（142 格）
    end
    if fullType == "Base.Screwdriver" then it.tags = { Screwdriver = true } end
    return it
end
-- 物品類型不存在時 instanceItem 回 nil（InventoryItemFactory.CreateItem）：測試把類型放進 missingTypes
F.missingTypes = {}
-- 全域 ModData（ModData.java:20）
F.globalModData = {}
ModData = { getOrCreate = function(tag)
    F.globalModData[tag] = F.globalModData[tag] or {}
    return F.globalModData[tag]
end }
F.RIGHT = "MinidoracatWatch.MapWatch_ValuTech_Right"
F.LEFT = "MinidoracatWatch.MapWatch_ValuTech_Left"
function instanceItem(fullType)
    if F.missingTypes[fullType] then return nil end
    return F.item(fullType)
end
ItemTag = { SCREWDRIVER = "Screwdriver" } -- ItemTag.java:370

-- ===== 容器 =====
local Container = {}
Container.__index = Container
-- Lua 數字進 Java int 參數：小數向 0 截斷、NaN→0、±Inf 夾到 int 範圍（KahluaNumberConverter；
-- 所以「型別是 number」不夠，id 必須先驗整數）。假容器照這個語意查，非整數 id 才會真的命中別件物品。
local function javaInt(n)
    if type(n) ~= "number" then error("expected int, got " .. type(n)) end
    if n ~= n then return 0 end
    if n >= 2147483647 then return 2147483647 end
    if n <= -2147483648 then return -2147483648 end
    return n >= 0 and math.floor(n) or -math.floor(-n)
end
-- AddItem 也收字串（ItemContainer.AddItem(String) 建一件再放進來）
function Container:AddItem(item)
    if type(item) == "string" then item = F.item(item) end
    if item.container then item.container:DoRemoveItem(item) end
    table.insert(self.items, item)
    item.container = self
    return item
end
function Container:DoRemoveItem(item)
    for i = #self.items, 1, -1 do
        if self.items[i] == item then table.remove(self.items, i) end
    end
    item.container = nil
end
function Container:getItemWithID(id)
    for _, it in ipairs(self.items) do if it.id == id then return it end end
    return nil
end
function Container:getItemWithIDRecursiv(id)
    id = javaInt(id)
    for _, it in ipairs(self.items) do
        if it.id == id then return it end
        if it.bag then
            local found = it.bag:getItemWithIDRecursiv(id)
            if found then return found end
        end
    end
    return nil
end
function Container:getAllTypeRecurse(fullType)
    local out = {}
    local function walk(c)
        for _, it in ipairs(c.items) do
            if it.fullType == fullType then out[#out + 1] = it end
            if it.bag then walk(it.bag) end
        end
    end
    walk(self)
    return F.javaList(out)
end
-- containsTagEvalRecurse(ItemTag, LuaClosure)：ItemContainer.java:1166
function Container:containsTagEvalRecurse(tag, fn)
    local function walk(c)
        for _, it in ipairs(c.items) do
            if it.tags and it.tags[tag] and fn(it) then return true end
            if it.bag and walk(it.bag) then return true end
        end
        return false
    end
    return walk(self)
end
function F.container() return setmetatable({ items = {} }, Container) end
function F.bag(inv)
    local b = F.item("Base.Bag_Schoolbag")
    b.bag = F.container()
    inv:AddItem(b)
    return b.bag
end

-- ===== 玩家 =====
local LOC_ORDER = { leftwrist = 1, rightwrist = 2 }
local Player = {}
Player.__index = Player
function Player:getInventory() return self.inv end
function Player:isDead() return self.dead == true end
function Player:getModData() return self.md end
function Player:getPlayerNum() return self.pn end
function Player:getUsername() return self.name end
function Player:getOnlineID() return self.onlineId end
-- SteamID 來自連線（GameServer.java:2843-2844）：改名帶不走；no-steam 是 0
function Player:getSteamID() return self.sid or 0 end
function Player:removeFromHands() end
function Player:isTimedActionInstant() return false end
function Player:getX() return self.x or 0 end
function Player:getY() return self.y or 0 end
function Player:resetModelNextFrame() self.resets = (self.resets or 0) + 1 end
-- 遠端玩家畫的是 remotePlayerItemVisuals（IsoPlayer.java:7679-7689）；測試直接放 visual
function Player:getItemVisuals() return F.javaList(self.remoteVisuals or {}) end
function getPlayerByOnlineID(id)
    for _, p in ipairs(F.players) do if p.onlineId == id then return p end end
    return nil
end
function Player:getWornItems()
    local list = {}
    for _, w in ipairs(self.worn) do list[#list + 1] = { getItem = function() return w.item end } end
    return F.javaList(list)
end
-- 測試用：直接穿上（照 WornItems.setItem 的部位排序；同部位覆蓋）
function F.wear(player, item)
    local loc = item.fullType:find("Left") and "leftwrist" or "rightwrist"
    for i = #player.worn, 1, -1 do
        if player.worn[i].loc == loc or player.worn[i].item == item then table.remove(player.worn, i) end
    end
    table.insert(player.worn, { loc = loc, item = item })
    table.sort(player.worn, function(a, b) return LOC_ORDER[a.loc] < LOC_ORDER[b.loc] end)
end
function F.unwear(player, item)
    for i = #player.worn, 1, -1 do if player.worn[i].item == item then table.remove(player.worn, i) end end
end
-- 充電：所在車輛（BaseVehicle.isEngineRunning）與所在格（IsoGridSquare 的 getRoom／haveElectricity／hasGridPower）。
-- 格子只給這三個方法，發電機（{ fuel = n }）藏在 closure 裡：被測程式碰到別的方法就當場報錯，也碰不到燃料。
function Player:getVehicle() return self.vehicle end
function Player:getCurrentSquare() return self.square end
function F.vehicle(running)
    return { running = running, isEngineRunning = function(v) return v.running == true end }
end
function F.square(room, generator, grid)
    return { getRoom = function() return room end,
        haveElectricity = function() return generator ~= nil and generator.fuel > 0 end,
        hasGridPower = function() return grid == true end }
end

F.players = {}
function F.player(name, pn)
    local p = setmetatable({ inv = F.container(), worn = {}, md = {}, pn = pn or 0, name = name or "alice",
        onlineId = #F.players, _class = "IsoPlayer" }, Player)
    F.players[#F.players + 1] = p
    return p
end
function getOnlinePlayers()
    if F.mode ~= "server" then return F.javaList({}) end
    return F.javaList(F.players)
end
function getNumActivePlayers() return F.mode == "server" and 0 or #F.players end
function getSpecificPlayer(pn)
    for _, p in ipairs(F.players) do if p.pn == pn then return p end end
    return nil
end

-- ===== 網路 =====
function syncItemModData(player, item)
    if F.mode == "server" then F.synced[#F.synced + 1] = { player = player, item = item } end
end
function sendAddItemToContainer(c, item) if F.mode == "server" then F.added[#F.added + 1] = item end end
function sendRemoveItemFromContainer(c, item) if F.mode == "server" then F.removed[#F.removed + 1] = item end end
function sendClientCommand(player, module, command, args)
    F.clientCmds[#F.clientCmds + 1] = { player = player, module = module, command = command, args = args }
end
-- 有 player 的多載只送那位玩家；沒有 player 的多載廣播給所有連線（LuaManager.java:8956-8970）
function sendServerCommand(player, module, command, args)
    if type(player) == "string" then
        player, module, command, args = nil, player, module, command
    end
    F.serverCmds[#F.serverCmds + 1] = { player = player, module = module, command = command, args = args,
        broadcast = player == nil }
end

-- ===== 照明（Phase 8）：光源物品、attached、AttachedLocations =====
-- activated 是物品自己的狀態；LightDistance 初值照 script（4）。getFirstType 全名比對、只看主背包（ItemContainer.java:1540）。
function Item:isActivated() return self.activated == true end
function Item:setActivated(on) self.activated = on end
function Item:getLightDistance() return self.lightDistance or 4 end
function Item:setLightDistance(n) self.lightDistance = n end
function Container:getFirstType(t)
    for _, it in ipairs(self.items) do if it.fullType == t then return it end end
    return nil
end
-- setItem 對沒定義的 location 丟例外（AttachedLocationGroup.java:63-71）；MP 客戶端的本機玩家掛東西會送封包（IsoGameCharacter.java:3569-3571）
F.attachedLocs, F.attachPackets, F.attachSent = {}, {}, {}
AttachedLocations = { getGroup = function()
    return { getOrCreateLocation = function(_, id) F.attachedLocs[id] = true end }
end }
function Player:getAttachedItem(loc) return self.attached and self.attached[loc] or nil end
function Player:setAttachedItem(loc, item)
    if not F.attachedLocs[loc] then error("no attached location " .. tostring(loc)) end
    self.attached = self.attached or {}
    self.attached[loc] = item
    if F.mode == "client" then F.attachPackets[#F.attachPackets + 1] = { player = self, loc = loc, item = item } end
end
-- 伺服器的 sendAttachedItem 送範圍內客戶端（LuaManager.java:12394-12401）；其他端是 no-op
function sendAttachedItem(player, loc, item)
    if F.mode == "server" then F.attachSent[#F.attachSent + 1] = { player = player, loc = loc, item = item } end
end

-- ===== 原版穿戴動作（只留 isValid／complete 的形狀）=====
ISWearClothing = { isValid = function(self) return true end,
    complete = function(self) F.wear(self.character, self.item); return true end }
ISClothingExtraAction = { isValid = function(self) return true end,
    complete = function(self)
        -- 原版：舊物移除、instanceItem 新物、複製 modData、穿上（ISClothingExtraAction.lua:121-137）
        local p, old = self.character, self.item
        F.unwear(p, old)
        local new = F.item(self.extra)
        if old.md then new.md = {}; for k, v in pairs(old.md) do new.md[k] = v end end
        p.inv:DoRemoveItem(old)
        p.inv:AddItem(new)
        F.wear(p, new)
        return true
    end }
function F.action(cls, character, item, extra)
    return setmetatable({ character = character, item = item, extra = extra }, { __index = cls })
end

-- ===== 計時動作（ISBaseTimedAction.lua:173-184 的形狀；ISTimedActionQueue 只留 add 與佇列）=====
ISBaseTimedAction = {}
ISBaseTimedAction.__index = ISBaseTimedAction
function ISBaseTimedAction:derive(name)
    local c = setmetatable({ Type = name }, { __index = self })
    c.__index = c
    return c
end
function ISBaseTimedAction.new(cls, character)
    return setmetatable({ character = character, stopOnWalk = true, stopOnRun = true, maxTime = -1 }, cls)
end
function ISBaseTimedAction:perform() F.performed = (F.performed or 0) + 1 end
F.queues = {}
ISTimedActionQueue = {
    add = function(a)
        F.queues[a.character] = F.queues[a.character] or {}
        table.insert(F.queues[a.character], a)
        return a
    end,
    getTimedActionQueue = function(p) return { queue = F.queues[p] or {} } end,
}
-- 跑完一位玩家佇列裡的所有動作：isValid 為假＝動作被取消（不 perform）
function F.runActions(p)
    local q = F.queues[p] or {}
    F.queues[p] = {}
    local done = 0
    for _, a in ipairs(q) do
        if a:isValid() then a:perform(); done = done + 1 end
    end
    return done
end

-- ===== require：本 MOD 模組載真檔，原版模組已由上面的假物件代替 =====
local MODULES = {
    MinidoracatWatch = F.MEDIA .. "/shared/MinidoracatWatch.lua",
    MinidoracatWatch_Modules = F.MEDIA .. "/shared/MinidoracatWatch_Modules.lua",
    MinidoracatWatch_Light = F.MEDIA .. "/shared/MinidoracatWatch_Light.lua",
    MinidoracatWatch_Action = F.MEDIA .. "/client/MinidoracatWatch_Action.lua",
    MinidoracatWatch_Client = F.MEDIA .. "/client/MinidoracatWatch_Client.lua",
    MinidoracatWatch_Config = F.MEDIA .. "/server/MinidoracatWatch_Config.lua",
    MinidoracatWatch_Pay = F.MEDIA .. "/shared/MinidoracatWatch_Pay.lua",
    MinidoracatWatch_PayClient = F.MEDIA .. "/client/MinidoracatWatch_PayClient.lua",
    MinidoracatWatch_Economy = F.MEDIA .. "/server/MinidoracatWatch_Economy.lua",
}
local loaded = {}
function require(name)
    if loaded[name] then return end
    loaded[name] = true
    if MODULES[name] then dofile(MODULES[name]) end
end
function F.load(rel) dofile(F.MEDIA .. "/" .. rel) end

-- ===== 斷言 =====
F.failures, F.count = 0, 0
function F.check(ok, label)
    F.count = F.count + 1
    if not ok then
        F.failures = F.failures + 1
        F.print("  FAIL  " .. label)
    end
end
function F.near(a, b, eps) return a ~= nil and b ~= nil and math.abs(a - b) <= (eps or 1e-9) end
function F.finish(name)
    if F.failures > 0 then
        F.print(name .. ": " .. F.failures .. " / " .. F.count .. " FAIL")
        os.exit(1)
    end
    F.print(name .. ": " .. F.count .. " checks OK")
end

return F
