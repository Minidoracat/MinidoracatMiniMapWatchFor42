-- MinidoracatWatch_Loot.lua：戰利品分佈（伺服器／單機；MP 客戶端不填容器，ItemPickerJava.java:556-562）。
-- 地點與稀有度照設計稿 data.mjs（STYLES 的 where／rarity、MODULES 的 get），表名都在原版
-- media/lua/server/Items/ProceduralDistributions.lua 查過。數字＝每輪每筆的機率基數（0.1＝每輪 0.1%，
-- 再乘沙盒 loot 倍率；ItemPickerJava.java:1280-1300、2093-2109）。原版參考：住宅抽屜的數位錶 0.1、
-- 錶櫃 10、珠寶店金錶 8、軍用電子櫃的軍錶 10。
-- 沙盒開關（每款錶、模組、解鎖卡）怎麼在「開局」與「改沙盒後」都生效：
--   - 開局：IsoWorld.init 依序派 OnPre／OnDistributionMerge／OnPostDistributionMerge 後才 ItemPickerJava.Parse
--     （IsoWorld.java:1886-1901），所以在 OnPostDistributionMerge 照當下的沙盒改 ProceduralDistributions.list。
--     但單機讀舊檔時，存檔的沙盒（map_sand.bin）在這之後才載入（IsoWorld.java:1894-1896），當下讀到的可能不是最終值。
--   - 改沙盒：管理員介面套用時只 Parse、不重派 merge 事件（ISServerSandboxOptionsUI.lua:763-773 →
--     IsoWorld.parseDistributions＝IsoWorld.java:3326-3329），而且是在操作介面的那端；dedicated 收到新沙盒不 Parse
--     （GameServer.java:1710-1726）。
--   所以權威端每 POLL_MS 比對一次開關（讀原生 SandboxOptions：單機介面用 set 寫原生選項、不 toLua，
--   SandboxOptions.java:572-582，SandboxVars 會是舊值）；跟上次套用的不同就重排分佈表並 IsoWorld.parseDistributions()。
--   開局後第一次比對也會補上「merge 時沙盒還沒載入」的情況。
if isClient() then return end
require "MinidoracatWatch"
local W = MinidoracatWatchCore
local L = {}
W.Loot = L
L.POLL_MS = 2000
L.PREFIX = "MinidoracatWatch."

local function mod(name) return "MinidoracatWatch.Module_" .. name end
local function card(tier) return W.CARD_TYPES[tier] end

-- { 沙盒鍵, 物品完整類型, { 分佈表, 機率, … } }
L.ENTRIES = {
    -- ValuTech（常見）：電器行、一般住宅、加油站櫃檯
    { "LootValuTech", W.watchType("ValuTech"), { "StoreDisplayWatches", 4, "ElectronicStoreMisc", 2,
        "BedroomDresser", 0.2, "BedroomSidetable", 0.2, "LivingRoomSideTable", 0.1, "GasStoreSpecial", 1 } },
    -- 貓爪（少見）：玩具店、禮品店、小孩房（原版玩具店的櫃位用 GiftStoreToys，Distributions.lua toystore）
    { "LootPaws", W.watchType("Paws"), { "GiftStoreToys", 1, "CrateToys", 0.5,
        "BedroomDresserChild", 0.1, "BedroomSidetableChild", 0.1 } },
    -- 極光（少見）：電器行高階櫃（electronicstore.displaycase＝StoreDisplayWatches）、商場
    { "LootNexus", W.watchType("Nexus"), { "StoreDisplayWatches", 1, "DepartmentStoreWatches", 1 } },
    -- Spiffo（少見）：Spiffo's 餐廳、小孩房（原版沒有遊樂場的分佈表）
    { "LootSpiffo", W.watchType("Spiffo"), { "SpiffosKitchenSpecial", 1, "CrateSpiffoMerch", 1,
        "BedroomDresserChild", 0.05 } },
    -- 遊騎兵（稀有）：軍事據點、警察局武器室
    { "LootRanger", W.watchType("Ranger"), { "ArmyStorageElectronics", 0.5, "ArmySurplusMisc", 0.5,
        "LockerArmyBedroom", 0.2, "PoliceStorageGuns", 0.2 } },
    -- 盧瑟斯（很稀有）：珠寶店、豪宅（原版沒有豪宅專用表，用 Classy 臥室）
    { "LootLuthex", W.watchType("Luthex"), { "JewelryWrist", 0.5, "BedroomDresserClassy", 0.05,
        "BedroomSidetableClassy", 0.05 } },
    -- 嗶嗶腕機（稀有）：軍事據點、緊急避難所（地堡）、生存狂的藏身處
    { "LootBB3000", W.watchType("BB3000"), { "ArmyStorageElectronics", 0.3, "ArmyBunkerStorage", 0.3,
        "ArmyBunkerLockers", 0.3, "SurvivalGear", 0.5 } },
    -- 模組：常見（名錄、照明）、少見（定位、通訊）、一般（掃描、偵測）、稀有（軍規偵測、長距通訊）、很稀有（中繼、節能）
    { "LootModules", mod("Ledger"), { "ElectronicStoreMisc", 1, "CrateElectronics", 1 } },
    { "LootModules", mod("Light"), { "ElectronicStoreMisc", 1, "CrateElectronics", 1, "SurvivalGear", 1 } },
    { "LootModules", mod("GPS"), { "ElectronicStoreMisc", 0.5, "ArmyStorageElectronics", 1 } },
    { "LootModules", mod("Comm"), { "ElectronicStoreMisc", 0.5, "PoliceLockers", 0.5 } },
    { "LootModules", mod("Scan"), { "ElectronicStoreMisc", 0.5, "CrateElectronics", 0.5 } },
    { "LootModules", mod("Detect"), { "ElectronicStoreMisc", 0.5, "CrateElectronics", 0.5 } },
    { "LootModules", mod("MilDetect"), { "ArmyStorageElectronics", 0.3 } },
    { "LootModules", mod("LongComm"), { "ArmyStorageElectronics", 0.3, "PoliceLockers", 0.2 } },
    { "LootModules", mod("Relay"), { "ArmyStorageElectronics", 0.05, "ArmyBunkerStorage", 0.05 } },
    { "LootModules", mod("Eco"), { "ElectronicStoreMisc", 0.05, "ArmyStorageElectronics", 0.05 } },
    -- 解鎖卡（很少）：擴充＝電器行、進階＝軍警、核心＝軍事地堡
    { "LootCards", card("ext"), { "ElectronicStoreMisc", 0.1, "CrateElectronics", 0.1 } },
    { "LootCards", card("adv"), { "ArmyStorageElectronics", 0.1, "PoliceLockers", 0.05 } },
    { "LootCards", card("core"), { "ArmyBunkerStorage", 0.05, "ArmyStorageElectronics", 0.03 } },
}
L.KEYS = { "Enabled", "LootValuTech", "LootPaws", "LootNexus", "LootSpiffo", "LootRanger", "LootLuthex", "LootBB3000",
    "LootModules", "LootCards" }
-- 數量（Phase 4，設計稿取得方式的「很少／少／一般／多」）：每類一個 enum 沙盒，乘上 ENTRIES 的機率；一般＝建議值
L.AMOUNT_KEYS = { "LootWatchAmount", "LootModuleAmount", "LootCardAmount" }
L.AMOUNT_OF = { LootModules = "LootModuleAmount", LootCards = "LootCardAmount" } -- 其餘（七款錶）＝LootWatchAmount
L.FACTORS = { 0.25, 0.5, 1, 2 }
L.AMOUNT_DEFAULT = { LootCardAmount = 1 } -- 解鎖卡預設「很少」（設計稿預設）；其餘「一般」
L.TABLES = {} -- 本 MOD 碰到的分佈表
for _, e in ipairs(L.ENTRIES) do
    for i = 1, #e[3], 2 do L.TABLES[e[3][i]] = true end
end

-- 原生沙盒值優先（W.nativeSandbox）：單機的原版沙盒介面只改原生選項
function L.option(key) return W.nativeSandbox(key, true) ~= false end
function L.amount(key)
    local default = L.AMOUNT_DEFAULT[key] or 3
    local v = tonumber(W.nativeSandbox(key, default))
    if v and L.FACTORS[v] then return v end
    return default
end

-- 目前開關與數量的簽章（字串比對；每 POLL_MS 一次、13 個選項）：開關一字一位、"|"、數量一字一位
function L.signature()
    local s = ""
    for _, k in ipairs(L.KEYS) do s = s .. (L.option(k) and "1" or "0") end
    s = s .. "|"
    for _, k in ipairs(L.AMOUNT_KEYS) do s = s .. L.amount(k) end
    return s
end

-- 把本 MOD 的物品從碰到的表移掉，再依開關與數量加回；list＝ProceduralDistributions.list。原地改 items 陣列
-- （其他 MOD 在 merge 時拿到的是同一個 table）。回加入的筆數。
local missingLogged = {}
function L.apply(list, sig)
    local on, factor = {}, {}
    for i, k in ipairs(L.KEYS) do on[k] = string.sub(sig, i, i) == "1" end
    local base = #L.KEYS + 1 -- "|" 的位置
    for i, k in ipairs(L.AMOUNT_KEYS) do
        factor[k] = L.FACTORS[tonumber(string.sub(sig, base + i, base + i))] or 1
    end
    for name in pairs(L.TABLES) do
        local items = list[name] and list[name].items
        if type(items) == "table" then
            local j, n = 1, #items
            for i = 1, n, 2 do
                local it = items[i]
                if not (type(it) == "string" and string.sub(it, 1, #L.PREFIX) == L.PREFIX) then
                    items[j], items[j + 1] = it, items[i + 1]
                    j = j + 2
                end
            end
            for k = n, j, -1 do items[k] = nil end
        elseif not missingLogged[name] then
            missingLogged[name] = true
            W.log("loot table " .. name .. " not found in ProceduralDistributions; skipped")
        end
    end
    local added = 0
    if not on.Enabled then return 0 end
    for _, e in ipairs(L.ENTRIES) do
        if on[e[1]] then
            local f = factor[L.AMOUNT_OF[e[1]] or "LootWatchAmount"]
            for i = 1, #e[3], 2 do
                local t = list[e[3][i]]
                if t and type(t.items) == "table" then
                    table.insert(t.items, e[2])
                    table.insert(t.items, e[3][i + 1] * f)
                    added = added + 1
                end
            end
        end
    end
    return added
end

L.applied = nil
-- parse＝改完要不要讓 Java 重讀分佈表（開局的 merge 事件之後引擎自己會 Parse）
function L.sync(parse)
    local list = ProceduralDistributions and ProceduralDistributions.list
    if type(list) ~= "table" then return end
    local sig = L.signature()
    if sig == L.applied then return end
    local added = L.apply(list, sig)
    L.applied = sig
    if parse then
        IsoWorld.parseDistributions() -- ItemPickerJava.Parse＋InitSandboxLootSettings（IsoWorld.java:3326-3329）
        W.log("loot tables updated after a sandbox change (" .. added .. " entries, switches " .. sig .. ")")
    else
        W.log("loot tables prepared (" .. added .. " entries, switches " .. sig .. ")")
    end
end

Events.OnPostDistributionMerge.Add(function() L.sync(false) end)

local lastPoll = nil
function L.tick()
    if L.applied == nil then return end -- 還沒 merge（主選單、載入中）
    local now = getTimestampMs()
    if lastPoll and now >= lastPoll and now - lastPoll < L.POLL_MS then return end
    lastPoll = now
    L.sync(true)
end
Events.OnTickEvenPaused.Add(L.tick)
