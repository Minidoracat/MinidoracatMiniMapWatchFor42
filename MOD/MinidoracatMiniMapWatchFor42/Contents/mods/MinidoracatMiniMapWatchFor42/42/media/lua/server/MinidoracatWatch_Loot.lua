-- MinidoracatWatch_Loot.lua：戰利品分佈（伺服器／單機；MP 客戶端不填容器，ItemPickerJava.java:556-562）。
-- 分佈表本身（地點、稀有度、機率基數）在 shared/MinidoracatWatch_DropData.lua 的 W.lootEntries()，玩家看的取得方式也讀它。
-- 沙盒開關（每款錶、模組、解鎖卡、每顆負重核心）怎麼在「開局」與「改沙盒後」都生效：
--   - 開局：IsoWorld.init 依序派 OnPre／OnDistributionMerge／OnPostDistributionMerge 後才 ItemPickerJava.Parse
--     （IsoWorld.java:1886-1901），所以在 OnPostDistributionMerge 照當下的沙盒改 ProceduralDistributions.list。
--     但單機讀舊檔時，存檔的沙盒（map_sand.bin）在這之後才載入（IsoWorld.java:1894-1896），當下讀到的可能不是最終值。
--   - 改沙盒：管理員介面套用時只 Parse、不重派 merge 事件（ISServerSandboxOptionsUI.lua:763-773 →
--     IsoWorld.parseDistributions＝IsoWorld.java:3326-3329），而且是在操作介面的那端；dedicated 收到新沙盒不 Parse
--     （GameServer.java:1710-1726）。
--   所以權威端每 POLL_MS 比對一次開關（讀原生 SandboxOptions：單機介面用 set 寫原生選項、不 toLua，
--   SandboxOptions.java:572-582，SandboxVars 會是舊值）；跟上次套用的不同就重排分佈表並 IsoWorld.parseDistributions()。
--   開局後第一次比對也會補上「merge 時沙盒還沒載入」的情況。
-- 各物品的倍率（2026-10-15）：伺服器設定檔的 lootItems 區段（管理員視窗「取得方式」頁寫回），乘在類別數量之後；0＝不放進表。
--   同一次輪詢也比對倍率的簽章，設定檔改了就重排。開局 merge 時設定檔還沒讀（Cfg 第一次讀在第一個 tick），先當作全部 ×1，
--   第一個 tick 就補排（Cfg.tick 比 L.tick 先登記，同一個 tick 先讀檔）。
if isClient() then return end
require "MinidoracatWatch"
require "MinidoracatWatch_Config"
require "MinidoracatWatch_DropData"
local W = MinidoracatWatchCore
local L = {}
W.Loot = L
L.POLL_MS = 2000
L.PREFIX = "MinidoracatWatch."

L.ENTRIES = W.lootEntries()
L.KEYS = { "Enabled", "LootValuTech", "LootPaws", "LootNexus", "LootSpiffo", "LootRanger", "LootLuthex", "LootBB3000",
    "LootModules", "LootCards", "LootWeight1", "LootWeight2", "LootWeight3" }
L.TABLES = {} -- 本 MOD 碰到的分佈表
L.ITEMS = {} -- 有分佈的物品（lootItems 只收這些）
for _, e in ipairs(L.ENTRIES) do
    L.ITEMS[e[2]] = true
    for i = 1, #e[3], 2 do L.TABLES[e[3][i]] = true end
end

-- 開關預設與原生值優先在 shared W.lootOn，數量在 W.lootAmount（玩家看的取得方式也用同一份）
L.option = W.lootOn

-- 設定檔的 lootItems：{ [物品完整類型] = 倍率 }，只寫改過的物品；倍率只能是 W.LOOT_STEPS 其中之一，寫 1 的當作沒寫。
-- 任何一筆不合法整段不採用（保留上一份有效值，同 zombieDrops）。空物件寫出來是 []（Cfg.encode 把空表當陣列），所以空陣列也收
function L.parseItems(raw)
    local Cfg = W.Config
    if type(raw) ~= "table" or raw == Cfg.NULL or (Cfg.isArray(raw) and #raw > 0) then
        return nil, { "must be an object of item type -> loot factor" }
    end
    local out, problems = {}, {}
    for t, f in pairs(raw) do
        if not L.ITEMS[t] then
            problems[#problems + 1] = "unknown item " .. tostring(t)
        elseif not W.LOOT_STEP_SET[f] then
            problems[#problems + 1] = tostring(t) .. ": factor must be 0, 0.25, 0.5, 1, 2, 4 or 10"
        elseif f ~= 1 then
            out[t] = f
        end
    end
    if #problems > 0 then return nil, problems end
    return out
end
W.Config.section("lootItems", { default = function() return {} end, parse = L.parseItems })

-- 目前開關與數量的簽章（字串比對；每 POLL_MS 一次、16 個選項）：開關一字一位、"|"、數量一字一位
function L.signature()
    local s = ""
    for _, k in ipairs(L.KEYS) do s = s .. (L.option(k) and "1" or "0") end
    s = s .. "|"
    for _, k in ipairs(W.LOOT_AMOUNT_KEYS) do s = s .. W.lootAmount(k) end
    return s
end

-- 逐項倍率：設定檔讀進來之前（開局的 merge 事件）當作全部 ×1。簽章照 ENTRIES 順序，每筆一段
function L.items()
    local Cfg = W.Config
    return Cfg.loaded and Cfg.get("lootItems") or {}
end
function L.itemSignature(items)
    local s = ""
    for _, e in ipairs(L.ENTRIES) do s = s .. "," .. tostring(items[e[2]] or 1) end
    return s
end

-- 把本 MOD 的物品從碰到的表移掉，再依開關、數量與逐項倍率（items，可省略＝全部 ×1）加回；list＝ProceduralDistributions.list。
-- 原地改 items 陣列（其他 MOD 在 merge 時拿到的是同一個 table）。回加入的筆數。
local missingLogged = {}
function L.apply(list, sig, items)
    items = items or {}
    local on, factor = {}, {}
    for i, k in ipairs(L.KEYS) do on[k] = string.sub(sig, i, i) == "1" end
    local base = #L.KEYS + 1 -- "|" 的位置
    for i, k in ipairs(W.LOOT_AMOUNT_KEYS) do
        factor[k] = W.LOOT_FACTORS[tonumber(string.sub(sig, base + i, base + i))] or 1
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
        local f = factor[W.LOOT_AMOUNT_OF[e[1]] or "LootWatchAmount"] * (items[e[2]] or 1)
        if on[e[1]] and f > 0 then -- 逐項倍率 0＝不出現：不放權重 0 的筆
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

L.applied, L.appliedItems = nil, nil
-- parse＝改完要不要讓 Java 重讀分佈表（開局的 merge 事件之後引擎自己會 Parse）
function L.sync(parse)
    local list = ProceduralDistributions and ProceduralDistributions.list
    if type(list) ~= "table" then return end
    local sig, items = L.signature(), L.items()
    local isig = L.itemSignature(items)
    if sig == L.applied and isig == L.appliedItems then return end
    local added = L.apply(list, sig, items)
    L.applied, L.appliedItems = sig, isig
    local tuned = 0
    for _ in pairs(items) do tuned = tuned + 1 end
    local what = " (" .. added .. " entries, switches " .. sig .. ", " .. tuned .. " items tuned)"
    if parse then
        IsoWorld.parseDistributions() -- ItemPickerJava.Parse＋InitSandboxLootSettings（IsoWorld.java:3326-3329）
        W.log("loot tables updated after a settings change" .. what)
    else
        W.log("loot tables prepared" .. what)
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
