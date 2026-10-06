-- MinidoracatWatch_DropData.lua（shared）：殭屍掉落規則的資料（服裝分組、掉落物 id、預設規則）。
-- 伺服器（server/MinidoracatWatch_Drops.lua 擲機率與驗證設定檔）與管理員視窗（client/MinidoracatWatch_AdminModel.lua
-- 下拉選單與句子）共用同一份。只放資料、不 require 其他檔（shared 依檔名順序在核心之後載入）。
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
W.GENERAL_MODULES = { "compass", "ledger", "gps", "comm", "scan", "detect", "light" }
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
