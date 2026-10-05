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
function getText(key, a, b) return key .. (a and ("|" .. a) or "") .. (b and ("|" .. b) or "") end
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
function Item:getCurrentUsesFloat() return self.uses * self.useDelta end
function Item:setCurrentUsesFloat(f)
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    self.uses = math.floor(f / self.useDelta + 0.5)
end

function F.item(fullType)
    local it = setmetatable({ id = newId(), fullType = fullType, _class = "InventoryItem" }, Item)
    if fullType == "Base.Battery" then
        it.useDelta = 0.007
        it.uses = math.floor(1 / it.useDelta) -- 新電池＝getMaxUses
    end
    return it
end
F.RIGHT = "MinidoracatWatch.MapWatch_ValuTech_Right"
F.LEFT = "MinidoracatWatch.MapWatch_ValuTech_Left"
function instanceItem(fullType) return F.item(fullType) end

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
function Container:AddItem(item)
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
function Player:removeFromHands() end
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
function sendServerCommand(player, module, command, args)
    F.serverCmds[#F.serverCmds + 1] = { player = player, module = module, command = command, args = args }
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

-- ===== require：本 MOD 模組載真檔，原版模組已由上面的假物件代替 =====
local MODULES = {
    MinidoracatWatch = F.MEDIA .. "/shared/MinidoracatWatch.lua",
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
