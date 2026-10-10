-- MinidoracatWatch_DropData.lua（shared）：取得方式的資料——殭屍掉落規則（服裝分組、掉落物 id、預設規則）與戰利品分佈。
-- 殭屍掉落：伺服器（server/MinidoracatWatch_Drops.lua 擲機率與驗證設定檔）與管理員視窗（client/MinidoracatWatch_AdminModel.lua
-- 下拉選單與句子）共用。戰利品：伺服器排分佈表（server/MinidoracatWatch_Loot.lua）與面板的取得方式（C.acquireLines）共用。
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

-- 預設 10 條（設計稿 DEFAULT_DROPS；機率單位是 %）。每次回新的一份
function W.defaultDrops()
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
        -- 解鎖卡（很少）：擴充＝電器行、進階＝軍警、核心＝軍事地堡
        { "LootCards", card("ext"), { "ElectronicStoreMisc", 0.1, "CrateElectronics", 0.1 } },
        { "LootCards", card("adv"), { "ArmyStorageElectronics", 0.1, "PoliceLockers", 0.05 } },
        { "LootCards", card("core"), { "ArmyBunkerStorage", 0.05, "ArmyStorageElectronics", 0.03 } },
    }
    return lootEntries
end
