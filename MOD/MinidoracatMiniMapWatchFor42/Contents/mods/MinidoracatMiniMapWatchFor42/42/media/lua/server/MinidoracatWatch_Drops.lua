-- MinidoracatWatch_Drops.lua：殭屍掉落（伺服器／單機）。
-- 事件：OnFillContainer("Zombie", 服裝名, 屍體容器)（規劃書 §4 Phase 5 裁定）。只在權威端填：MP 客戶端不填
-- （ItemPickerJava.java:556-562）。屍體的 containerType 是 IsoDeadBody.getOutfitName＝clothing.xml 的 m_Name
-- （ItemPickerJava.java:614-622、637-653；IsoDeadBody.java:2202-2203；Outfit.java:17-20），可能是 nil。
-- dedicated：屍體第一次被翻找時，客戶端送 RequestItemsForContainer，伺服器先 setExplored(true)、fillContainer（本事件在
-- 裡面同步執行），再把容器全部物品送給客戶端（RequestItemsForContainerPacket.java:44-50）。所以這裡 AddItem 就好，
-- 不用自己 sendAddItemToContainer；explored 隨容器存檔（ItemContainer.java:2435-2450），同一具屍體不會再填。
-- 不用 OnZombieDead：客戶端也會觸發，火燒致死還會再觸發一次（IsoZombie.java:5409、IsoGameCharacter.java:5949,6461）。
-- 規則清單存伺服器設定檔的 zombieDrops 區段（MinidoracatWatch_Config.lua）；總開關與每隻上限在沙盒。
if isClient() then return end
require "MinidoracatWatch"
require "MinidoracatWatch_Config"
local W = MinidoracatWatchCore
local D = {}
W.Drops = D

D.MAX_RULES = 200
D.MAX_OUTFITS = 64

-- 服裝分組（設計稿 data.mjs ZOMBIE_GROUPS；每個名字都在原版 media/clothing/clothing.xml 查過 m_Name，大小寫照原文）。
-- all＝所有殭屍（含沒有服裝名的）；custom＝規則自己帶 outfits。
D.GROUPS = {
    army = { "ArmyCamoGreen", "ArmyCamoDesert", "ArmyInstructor", "ArmyServiceUniform", "Ghillie", "PrivateMilitia" },
    police = { "Police", "PoliceState", "Police_SWAT", "PoliceRiot", "PrisonGuard" },
    fire = { "Fireman", "FiremanFullSuit" },
    medic = { "Doctor", "Nurse", "AmbulanceDriver", "Pharmacist" },
    worker = { "Mechanic", "MetalWorker", "ConstructionWorker", "Foreman" },
    office = { "OfficeWorker", "OfficeWorkerSkirt", "Trader" },
    student = { "Student", "HonorStudent" },
    survivalist = {},
    rich = { "Classy", "Gaudy" },
    spiffo = { "Spiffo", "Waiter_Spiffo", "Cook_Spiffos" },
    outdoor = { "Hunter", "Ranger", "Camper" },
}
for _, base in ipairs({ "Survivalist", "Survivalist02", "Survivalist03", "Survivalist04", "Survivalist05" }) do
    for _, suffix in ipairs({ "", "_Mid", "_Late" }) do
        table.insert(D.GROUPS.survivalist, base .. suffix)
    end
end
D.groupsOf = {} -- [服裝名] = { [分組] = true }
for g, list in pairs(D.GROUPS) do
    for _, o in ipairs(list) do
        D.groupsOf[o] = D.groupsOf[o] or {}
        D.groupsOf[o][g] = true
    end
end

-- 掉落物（設計稿 DROP_ITEMS）：watch:<款>、watch:any、mod:<模組 id>、mod:any（隨機一般模組）、card:<槽位等級>、battery
D.STYLE_BY_ID = { valutech = "ValuTech", paws = "Paws", nexus = "Nexus", spiffo = "Spiffo", ranger = "Ranger",
    luthex = "Luthex", crt = "BB3000" }
D.STYLE_IDS = { "valutech", "paws", "nexus", "spiffo", "ranger", "luthex", "crt" }
D.GENERAL_MODULES = { "compass", "ledger", "gps", "comm", "scan", "detect", "light" }
D.CARD_TIERS = { ext = true, adv = true, core = true }

-- 預設 10 條（設計稿 DEFAULT_DROPS；機率單位是 %）
function D.defaults()
    local out = {}
    for _, r in ipairs({
        { "all", "watch:valutech", 0.2 }, { "army", "watch:ranger", 2 }, { "army", "mod:mildetect", 1 },
        { "police", "mod:comm", 2 }, { "survivalist", "watch:crt", 3 }, { "spiffo", "watch:spiffo", 5 },
        { "rich", "watch:luthex", 1 }, { "student", "watch:paws", 1 }, { "office", "watch:nexus", 1 },
        { "worker", "mod:any", 2 },
    }) do
        out[#out + 1] = { group = r[1], item = r[2], chance = r[3] }
    end
    return out
end

-- 掉落物 id 合法嗎（mod:<id> 要是已登記的模組；第三方模組在 shared 檔登記，伺服器讀設定檔時已登記完）
function D.itemValid(id)
    if type(id) ~= "string" then return false end
    if id == "watch:any" or id == "mod:any" or id == "battery" then return true end
    local kind, rest = string.match(id, "^(%a+):([%w_]+)$")
    if kind == "watch" then return D.STYLE_BY_ID[rest] ~= nil end
    if kind == "mod" then return W.modules[rest] ~= nil end
    if kind == "card" then return D.CARD_TIERS[rest] == true end
    return false
end

local RULE_KEYS = { group = true, outfits = true, item = true, chance = true }
W.Config.keyOrder({ "group", "outfits", "item", "chance" })

-- 設定檔的 zombieDrops 區段：每條規則都驗證，任何一條不合法就整個區段不採用（保留上一份有效規則）。
-- 回 { { group, item, chance, outfits = 陣列或 nil, outfitSet = 集合或 nil } … } 或 nil, { 問題… }
function D.parse(raw)
    local Cfg = W.Config
    if not Cfg.isArray(raw) then return nil, { "must be a list of rules" } end
    if #raw > D.MAX_RULES then return nil, { "more than " .. D.MAX_RULES .. " rules" } end
    local out, problems = {}, {}
    local function bad(i, why) problems[#problems + 1] = "rule " .. i .. ": " .. why end
    for i, r in ipairs(raw) do
        if type(r) ~= "table" or r == Cfg.NULL or (Cfg.isArray(r) and #r > 0) then
            bad(i, "not an object")
        else
            local ok = true
            for k in pairs(r) do
                if not RULE_KEYS[k] then bad(i, "unknown field " .. tostring(k)); ok = false end
            end
            local g, item, chance = r.group, r.item, r.chance
            if not (g == "all" or g == "custom" or (type(g) == "string" and D.GROUPS[g])) then
                bad(i, "unknown group " .. tostring(g)); ok = false
            end
            if not D.itemValid(item) then bad(i, "unknown item " .. tostring(item)); ok = false end
            if type(chance) ~= "number" or chance ~= chance or chance < 0 or chance > 100 then
                bad(i, "chance must be a number from 0 to 100"); ok = false
            end
            local outfits, set = nil, nil
            if g == "custom" then
                local list = r.outfits
                if not Cfg.isArray(list) or #list == 0 or #list > D.MAX_OUTFITS then
                    bad(i, "custom rules need outfits: a list of 1-" .. D.MAX_OUTFITS .. " outfit names"); ok = false
                else
                    outfits, set = {}, {}
                    for _, o in ipairs(list) do
                        if type(o) ~= "string" or not string.match(o, "^[%w_%-]+$") or #o > 64 then
                            bad(i, "bad outfit name " .. tostring(o)); ok = false
                        else
                            outfits[#outfits + 1] = o
                            set[o] = true
                        end
                    end
                end
            elseif r.outfits ~= nil then
                bad(i, "outfits is only for the custom group"); ok = false
            end
            if ok then out[#out + 1] = { group = g, item = item, chance = chance, outfits = outfits, outfitSet = set } end
        end
    end
    if #problems > 0 then return nil, problems end
    return out
end

W.Config.section("zombieDrops", {
    default = function()
        local out = {}
        for i, r in ipairs(D.defaults()) do out[i] = { group = r.group, item = r.item, chance = r.chance } end
        return out
    end,
    parse = D.parse,
})

function D.matches(rule, outfit)
    if rule.group == "all" then return true end
    if outfit == nil then return false end
    if rule.group == "custom" then return rule.outfitSet ~= nil and rule.outfitSet[outfit] == true end
    local gs = D.groupsOf[outfit]
    return gs ~= nil and gs[rule.group] == true
end

-- 掉落物 id → 物品完整類型（any 類用 rand 挑）；nil＝這次啟動解析不到（例如第三方模組的物品沒登記）
function D.resolve(id, rand)
    if id == "battery" then return W.BATTERY_TYPE end
    if id == "watch:any" then
        return W.watchType(D.STYLE_BY_ID[D.STYLE_IDS[math.floor(rand() * #D.STYLE_IDS) + 1]])
    end
    if id == "mod:any" then
        local def = W.modules[D.GENERAL_MODULES[math.floor(rand() * #D.GENERAL_MODULES) + 1]]
        return def and def.item
    end
    local kind, rest = string.match(id, "^(%a+):([%w_]+)$")
    if kind == "watch" then return D.STYLE_BY_ID[rest] and W.watchType(D.STYLE_BY_ID[rest]) end
    if kind == "mod" then return W.modules[rest] and W.modules[rest].item end
    if kind == "card" then return W.CARD_TYPES[rest] end
    return nil
end

-- 純函式：依規則順序擲機率（rand 回 [0,1)），掉到 cap 件就停。回物品完整類型的清單。
function D.roll(outfit, rules, cap, rand)
    local out = {}
    for _, rule in ipairs(rules or {}) do
        if #out >= cap then break end
        if rule.chance > 0 and D.matches(rule, outfit) and rand() * 100 < rule.chance then
            local t = D.resolve(rule.item, rand)
            if t then out[#out + 1] = t end
        end
    end
    return out
end

function D.cap()
    local n = tonumber(W.sandbox("ZombieDropCap", 1))
    if not n or n ~= n then return 1 end
    return math.max(1, math.min(5, math.floor(n)))
end

-- ZombRand(n)＝0..n-1 的整數（LuaManager.java ZombRand）；離線測試換成固定種子的亂數
function D.rand() return ZombRand(1000000) / 1000000 end

function D.onFill(roomName, containerType, container)
    if roomName ~= "Zombie" then return end
    -- 原版會對 OnFillContainer 傳非容器的第三參數（"Zombie Bag" 傳分佈物件，ItemPickerJava.java:630；家族 pitfalls.md）
    if not instanceof(container, "ItemContainer") then return end
    if not W.enabled() or W.sandbox("ZombieDrops", true) == false then return end
    local outfit = type(containerType) == "string" and containerType or nil
    for _, t in ipairs(D.roll(outfit, W.Config.get("zombieDrops"), D.cap(), D.rand)) do
        local item = container:AddItem(t)
        -- 嗶嗶腕機生成時已隨機定色（ItemVisual.java:185-194）：先改回預設的綠色，戴上時再照 modData 套
        if item and W.hasScreen(item) then W.setChoice(item:getVisual(), 0) end
    end
end

Events.OnFillContainer.Add(D.onFill)
