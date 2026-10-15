-- MinidoracatWatch_DropData.lua（shared）：取得方式的資料——殭屍掉落規則（服裝分組、掉落物 id、預設規則）與戰利品分佈。
-- 殭屍掉落：伺服器（server/MinidoracatWatch_Drops.lua 擲機率與驗證設定檔）與管理員視窗（client/MinidoracatWatch_AdminModel.lua
-- 下拉選單與句子）共用。戰利品：伺服器排分佈表（server/MinidoracatWatch_Loot.lua）與玩家看的取得方式（C.acquireInfo）共用。
-- 只放資料、不 require 其他檔（shared 依檔名順序在核心之後載入）。
local W = MinidoracatWatchCore

-- 服裝分組（設計稿 data.mjs ZOMBIE_GROUPS；每個名字都在原版 media/clothing/clothing.xml 查過 m_Name，大小寫照原文）。
-- all＝所有殭屍（含沒有服裝名的）；custom＝規則自己帶 outfits。W.DROP_GROUP_IDS 是畫面上的順序。
W.DROP_GROUP_IDS = { "all", "army", "police", "fire", "medic", "worker", "office", "student", "survivalist", "rich",
    "spiffo", "outdoor", "custom" }
W.DROP_GROUPS = {
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
        table.insert(W.DROP_GROUPS.survivalist, base .. suffix)
    end
end

-- 掉落物（設計稿 DROP_ITEMS）：watch:<款>、watch:any、mod:<模組 id>、mod:any（隨機一般模組）、card:<槽位等級>、battery
W.STYLE_BY_ID = { valutech = "ValuTech", paws = "Paws", nexus = "Nexus", spiffo = "Spiffo", ranger = "Ranger",
    luthex = "Luthex", crt = "BB3000" }
W.STYLE_IDS = { "valutech", "paws", "nexus", "spiffo", "ranger", "luthex", "crt" }
W.GENERAL_MODULES = { "ledger", "gps", "comm", "scan", "detect", "light" }
W.CARD_TIERS = { "ext", "adv", "core" }

-- 預設 13 條（設計稿 DEFAULT_DROPS 的 10 條＋負重核心 3 條；機率單位是 %）。每次回新的一份。
-- 負重核心只從軍人掉、階越高越稀有（2026-10-14 使用者裁定）；排在最後，同一隻已經掉滿上限就輪不到
function W.defaultDrops()
    local out = {}
    for _, r in ipairs({
        { "all", "watch:valutech", 0.2 }, { "army", "watch:ranger", 2 }, { "army", "mod:mildetect", 1 },
        { "police", "mod:comm", 2 }, { "survivalist", "watch:crt", 3 }, { "spiffo", "watch:spiffo", 5 },
        { "rich", "watch:luthex", 1 }, { "student", "watch:paws", 1 }, { "office", "watch:nexus", 1 },
        { "worker", "mod:any", 2 },
        { "army", "mod:weight1", 0.5 }, { "army", "mod:weight2", 0.2 }, { "army", "mod:weight3", 0.05 },
    }) do
        out[#out + 1] = { group = r[1], item = r[2], chance = r[3] }
    end
    return out
end

-- 戰利品分佈：{ 沙盒開關, 物品完整類型, { 原版分佈表, 機率, … } }。地點與稀有度照設計稿 data.mjs（STYLES 的 where／rarity、
-- MODULES 的 get），表名都在原版 media/lua/server/Items/ProceduralDistributions.lua 查過。數字＝每輪每筆的機率基數
-- （0.1＝每輪 0.1%，再乘沙盒 loot 倍率；ItemPickerJava.java:1280-1300、2093-2109）。原版參考：住宅抽屜的數位錶 0.1、
-- 錶櫃 10、珠寶店金錶 8、軍用電子櫃的軍錶 10。
-- 解鎖卡類型在 _Modules.lua（依檔名排在本檔之後），所以第一次呼叫才建，之後回同一份。
local lootEntries = nil
function W.lootEntries()
    if lootEntries then return lootEntries end
    local function mod(name) return "MinidoracatWatch.Module_" .. name end
    local function card(tier) return W.CARD_TYPES[tier] end
    lootEntries = {
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
        -- 模組：常見（名錄、照明）、少見（定位、通訊）、一般（掃描、偵測）、稀有（軍規偵測、長距通訊）、很稀有（中繼、節能）。
        -- 模組用到的每張表都要有地點名稱翻譯 IGUI_MinidoracatWatch_LootPlace_<表名>（面板的取得方式，test_watch_acquire.lua 對照）
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
        -- 負重核心：每顆一個開關（LootWeight1..3，預設關、不受 LootModules 影響）；數量跟著「模組的數量」
        { "LootWeight1", mod("Weight1"), { "ArmyStorageElectronics", 0.05 } },
        { "LootWeight2", mod("Weight2"), { "ArmyBunkerStorage", 0.03 } },
        { "LootWeight3", mod("Weight3"), { "ArmyBunkerStorage", 0.01 } },
        -- 解鎖卡（很少）：擴充＝電器行、進階＝軍警、核心＝軍事地堡
        { "LootCards", card("ext"), { "ElectronicStoreMisc", 0.1, "CrateElectronics", 0.1 } },
        { "LootCards", card("adv"), { "ArmyStorageElectronics", 0.1, "PoliceLockers", 0.05 } },
        { "LootCards", card("core"), { "ArmyBunkerStorage", 0.05, "ArmyStorageElectronics", 0.03 } },
    }
    return lootEntries
end

-- 戰利品沙盒開關（e[1]）現在開著沒：原生值優先、拿不到退回 SandboxVars；負重核心預設關，其餘預設開。
-- 伺服器排分佈表（L.option）與面板的取得方式共用
local LOOT_DEFAULT_OFF = { LootWeight1 = true, LootWeight2 = true, LootWeight3 = true }
function W.lootOn(key)
    if LOOT_DEFAULT_OFF[key] then return W.nativeSandbox(key, false) == true end
    return W.nativeSandbox(key, true) ~= false
end

-- 戰利品的數量（管理員視窗的「數量」）：每類一個 enum 沙盒，1 很少（×0.25）、2 少（×0.5）、3 一般（建議值）、4 多（×2），
-- 乘在 W.lootEntries() 的機率上。伺服器排分佈表與玩家看的稀有度共用
W.LOOT_AMOUNT_KEYS = { "LootWatchAmount", "LootModuleAmount", "LootCardAmount" }
W.LOOT_AMOUNT_OF = { LootModules = "LootModuleAmount", LootCards = "LootCardAmount", LootWeight1 = "LootModuleAmount",
    LootWeight2 = "LootModuleAmount", LootWeight3 = "LootModuleAmount" } -- 其餘（七款錶）＝LootWatchAmount
W.LOOT_FACTORS = { 0.25, 0.5, 1, 2 }
W.LOOT_AMOUNT_DEFAULT = { LootCardAmount = 1 } -- 解鎖卡預設「很少」（設計稿預設）；其餘「一般」
function W.lootAmount(key)
    local default = W.LOOT_AMOUNT_DEFAULT[key] or 3
    local v = tonumber(W.nativeSandbox(key, default))
    if v and W.LOOT_FACTORS[v] then return v end
    return default
end

-- 各物品的戰利品倍率（管理員視窗「取得方式」頁、伺服器設定檔 lootItems 區段）：乘在類別數量之後；0＝不出現
W.LOOT_STEPS = { 0, 0.25, 0.5, 1, 2, 4, 10 }
W.LOOT_STEP_SET = {}
for _, v in ipairs(W.LOOT_STEPS) do W.LOOT_STEP_SET[v] = true end

-- ===== 取得方式總覽（2026-10-15 使用者裁定）=====
-- 玩家能看到的取得方式（沙盒 AcquireGuide）：1 不開放、2 只列取得方式（地點、殭屍類型、製作）、3 再加稀有度與每隻的機率。
-- 「取得方式」視窗與面板「需要 X 模組」的說明都照它；伺服器推給玩家的清單也照它裁切（server/MinidoracatWatch_Admin.lua
-- 的 A.lists），開放程度不夠的欄位，玩家從封包也讀不到
W.GUIDE_OFF, W.GUIDE_METHODS, W.GUIDE_RATES = 1, 2, 3
function W.guideLevel()
    local v = tonumber(W.nativeSandbox("AcquireGuide", W.GUIDE_METHODS))
    if v == W.GUIDE_OFF or v == W.GUIDE_RATES then return v end
    return W.GUIDE_METHODS
end

-- 一筆戰利品（W.lootEntries() 的一列）在玩家眼中的最後倍率：開關關著＝0；否則 類別數量 × 逐項倍率。
-- 逐項倍率讀玩家看得到的那份（W.guideList：開放程度 2 只有「不出現」的物品，3 才有全部倍率）
function W.lootFactor(e)
    if not W.lootOn(e[1]) then return 0 end
    local items = W.guideList("lootItems")
    local f = items and items[e[2]]
    return W.LOOT_FACTORS[W.lootAmount(W.LOOT_AMOUNT_OF[e[1]] or "LootWatchAmount")] * (type(f) == "number" and f or 1)
end

-- 容器的稀有度：w＝分佈表權重 × 最後倍率。門檻照預設表定：名錄 1 常見、通訊 0.5 少見、軍規偵測 0.3 稀有、節能 0.05 很稀有，
-- 更低的（解鎖卡 0.1×0.25）極稀有。只拿來和其他地圖手錶物品比較，不換算成機率：原版還乘「其他」稀有度、擲骰次數，
-- 殭屍多的地方每次擲骰另加固定的機率（ItemPickerJava.java:2091-2110），一個數字會誤導
W.LOOT_TIERS = { { 1, "common" }, { 0.5, "uncommon" }, { 0.2, "rare" }, { 0.05, "veryRare" } }
function W.lootTier(w)
    for _, t in ipairs(W.LOOT_TIERS) do
        if w >= t[1] then return t[2] end
    end
    return "scarce"
end

-- 掉落物 id → 物品完整類型（指定物品的那幾種）；watch:any、mod:any 由擲骰挑（伺服器 D.resolve），這裡回 nil。
-- 伺服器擲掉落與玩家看的取得方式共用
function W.dropItemType(id)
    if id == "battery" then return W.BATTERY_TYPE end
    local kind, rest = string.match(tostring(id), "^(%a+):([%w_]+)$")
    if kind == "watch" then return W.STYLE_BY_ID[rest] and W.watchType(W.STYLE_BY_ID[rest]) or nil end
    if kind == "mod" then return W.modules[rest] and W.modules[rest].item or nil end
    if kind == "card" then return W.CARD_TYPES[rest] end
    return nil
end
