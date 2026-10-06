-- 地圖錶取得方式（Phase 5，伺服器／單機）：殭屍掉落的機率與上限（固定種子）、服裝分組對應原版 clothing.xml、
-- 伺服器設定檔（缺檔寫預設、壞檔保留上一份、逐條驗證、區段各自獨立）、戰利品開關（開局與改沙盒後重排、不重複、
-- 照明模組不進表、表名都在原版 ProceduralDistributions）、配方 OnTest、嗶嗶腕機螢幕（伺服器廣播、單機重建模型）。
-- 原版檔案（PZ_PATH，預設 D:/SteamLibrary/steamapps/common/ProjectZomboid）不在時，對照原版的檢查改用假資料並註明。
-- 用法（repo 根目錄）：lua scripts/test_watch_acquire.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check = F.check
F.mode = "server"
local PZ = os.getenv("PZ_PATH") or "D:/SteamLibrary/steamapps/common/ProjectZomboid"
local function readFile(p)
    local fh = io.open(p, "rb")
    if not fh then return nil end
    local s = fh:read("a")
    fh:close()
    return s
end

-- ===== 假檔案系統（getFileReader／getFileWriter 的路徑相對 Zomboid/Lua；readLine 去掉行尾）=====
local FS, unreadable = {}, {}
local writeFails = false
function getFileReader(path)
    local text = FS[path]
    if text == nil or unreadable[path] then return nil end
    local lines = {}
    for line in (text:sub(-1) == "\n" and text or text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    local i = 0
    return { readLine = function() i = i + 1; return lines[i] end, close = function() end }
end
function cacheFileExists(path) return FS[path] ~= nil end
function getFileWriter(path)
    if writeFails then return nil end
    local buf = {}
    return { write = function(_, s) buf[#buf + 1] = s end, close = function() FS[path] = table.concat(buf) end }
end
function getServerName() return "servertest" end
function getWorld() return { getWorld = function() return "Muldraugh, KY" end } end

-- 原生沙盒（getSandboxOptions():getOptionByName(name):getValue()）
local NATIVE = {}
function getSandboxOptions()
    return { getOptionByName = function(_, n)
        if NATIVE[n] == nil then return nil end
        return { getValue = function() return NATIVE[n] end }
    end }
end
local parses = 0
IsoWorld = { parseDistributions = function() parses = parses + 1 end }
local seq = 0
function ZombRand(n) seq = seq + 1; return (seq * 7919) % n end

require "MinidoracatWatch"
local W = MinidoracatWatchCore
local SB = SandboxVars.MinidoracatWatch
F.load("server/MinidoracatWatch_Drops.lua")
local D, Cfg = W.Drops, W.Config
local function logged(pat)
    for _, l in ipairs(F.logs) do if l:find(pat, 1, true) then return true end end
    return false
end

-- 固定種子的線性同餘亂數（[0,1)），結果與 Lua 版本無關
local function lcg(seed)
    local s = seed
    return function()
        s = (s * 1103515245 + 12345) % 2147483648
        return s / 2147483648
    end
end

-- ===== 預設規則與服裝分組 =====
local defaults = D.defaults()
check(#defaults == 10, "預設 10 條規則")
local parsed = D.parse(defaults)
check(parsed and #parsed == 10, "預設規則通過驗證")
local seen = {}
for _, r in ipairs(defaults) do seen[r.group .. ">" .. r.item] = r.chance end
check(seen["all>watch:valutech"] == 0.2 and seen["survivalist>watch:crt"] == 3 and seen["worker>mod:any"] == 2
    and seen["army>mod:mildetect"] == 1 and seen["spiffo>watch:spiffo"] == 5, "預設規則照設計稿 DEFAULT_DROPS")
check(#D.GROUPS.survivalist == 15 and D.groupsOf["Survivalist03_Late"].survivalist, "生存狂含 02–05 與 _Mid／_Late（15 種）")
local xml = readFile(PZ .. "/media/clothing/clothing.xml")
if xml then
    local names = {}
    for n in xml:gmatch("<m_Name>([^<]+)</m_Name>") do names[n] = true end
    local missing = {}
    for g, list in pairs(D.GROUPS) do
        for _, o in ipairs(list) do if not names[o] then missing[#missing + 1] = g .. ":" .. o end end
    end
    check(#missing == 0, "每個分組的服裝名都在原版 clothing.xml（缺：" .. table.concat(missing, ",") .. "）")
else
    F.print("  (原版 clothing.xml 不在 " .. PZ .. "：跳過服裝名對照)")
end

-- ===== 規則比對 =====
local function rule(g, item, chance, outfits)
    return D.parse({ { group = g, item = item, chance = chance, outfits = outfits } })[1]
end
check(D.matches(rule("army", "watch:ranger", 1), "ArmyCamoDesert"), "軍人：ArmyCamoDesert")
check(not D.matches(rule("army", "watch:ranger", 1), "Police"), "軍人：Police 不算")
check(D.matches(rule("all", "battery", 1), nil) and D.matches(rule("all", "battery", 1), "Tourist"), "所有殭屍：含沒有服裝名的")
check(not D.matches(rule("police", "mod:comm", 1), nil), "沒有服裝名：只有「所有殭屍」")
local custom = rule("custom", "card:ext", 1, { "HazardSuit", "Bandit" })
check(D.matches(custom, "Bandit") and not D.matches(custom, "Police"), "自訂服裝：只比對自己的清單")

-- ===== 掉落機率（固定種子，10 萬隻）=====
local function rate(outfit, rules, cap, n, seed)
    local rand, items, zombies = lcg(seed), 0, 0
    for _ = 1, n do
        local got = #D.roll(outfit, rules, cap, rand)
        items = items + got
        if got > 0 then zombies = zombies + 1 end
    end
    return items / n, zombies / n
end
local N = 100000
local single = { rule("army", "watch:ranger", 2) }
local r1 = rate("ArmyCamoGreen", single, 1, N, 42)
check(math.abs(r1 - 0.02) < 0.0015, string.format("單條 2%%：實得 %.4f", r1))
check(rate("Police", single, 1, N, 42) == 0, "不符合分組：0")
check(rate("ArmyCamoGreen", { rule("army", "watch:ranger", 0) }, 5, 1000, 1) == 0, "機率 0：永遠不掉")
check(rate("ArmyCamoGreen", { rule("army", "watch:ranger", 100) }, 1, 1000, 1) == 1, "機率 100：每隻都掉")
-- 預設規則下的軍人（全部 + 遊騎兵 2% + 軍規偵測 1%）：上限 1 時依序擲、掉到就停
local items1, z1 = rate("ArmyCamoGreen", parsed, 1, N, 7)
local expect1 = 1 - (1 - 0.002) * (1 - 0.02) * (1 - 0.01)
check(math.abs(z1 - expect1) < 0.002 and items1 == z1, string.format("上限 1：每隻最多 1 件（%.4f，期望 %.4f）", z1, expect1))
local items5 = rate("ArmyCamoGreen", parsed, 5, N, 7)
check(math.abs(items5 - 0.032) < 0.002, string.format("上限 5：各規則獨立擲（平均 %.4f 件，期望 0.032）", items5))
-- 上限：三條 100% 的規則
local three = D.parse({ { group = "all", item = "battery", chance = 100 }, { group = "all", item = "card:adv", chance = 100 },
    { group = "all", item = "watch:paws", chance = 100 } })
check(#D.roll("X", three, 1, lcg(1)) == 1 and #D.roll("X", three, 3, lcg(1)) == 3 and #D.roll("X", three, 5, lcg(1)) == 3,
    "上限 1／3／5 對三條 100% 規則：1／3／3 件")
local got = D.roll("X", three, 3, lcg(1))
check(got[1] == "Base.Battery" and got[2] == "MinidoracatWatch.UnlockCard_Adv" and got[3] == "MinidoracatWatch.MapWatch_Paws_Left",
    "照規則順序；電池、進階卡、錶都是左手款")
-- any：隨機款式與隨機一般模組都落在範圍內，且每種都出現過
local styles, mods = {}, {}
local rnd = lcg(99)
for _ = 1, 2000 do
    local t = D.resolve("watch:any", rnd)
    styles[t] = true
    local m = D.resolve("mod:any", rnd)
    mods[m] = true
end
local nS, nM, okM = 0, 0, true
for t in pairs(styles) do nS = nS + 1; if not W.WATCH_TYPES[t] then okM = false end end
for m in pairs(mods) do
    nM = nM + 1
    local def = W.moduleByItem[m]
    if not def or def.class ~= "standard" or m:find("Light") then okM = false end
end
check(nS == 7 and nM == 6 and okM, "watch:any 七款都出現、mod:any 只出六種一般模組（不含照明）")
check(D.resolve("watch:crt", rnd) == "MinidoracatWatch.MapWatch_BB3000_Left" and D.resolve("card:core", rnd) == W.CARD_TYPES.core,
    "crt＝嗶嗶腕機左手款；card:core＝核心卡")

-- ===== 驗證：每條規則 =====
local function rejects(raw, label)
    local v, errs = D.parse(raw)
    check(v == nil and errs and #errs > 0, label .. "（" .. (errs and errs[1] or "沒被擋") .. "）")
end
rejects({ group = "all", item = "battery", chance = 1 }, "不是清單")
rejects({ { group = "zombies", item = "battery", chance = 1 } }, "未知分組")
rejects({ { group = "all", item = "mod:light", chance = 1 } }, "照明模組沒登記成模組：不能當掉落物")
rejects({ { group = "all", item = "watch:pipboy", chance = 1 } }, "未知錶款")
rejects({ { group = "all", item = "battery", chance = 101 } }, "機率超過 100")
rejects({ { group = "all", item = "battery", chance = -1 } }, "機率小於 0")
rejects({ { group = "all", item = "battery", chance = "5" } }, "機率是字串")
rejects({ { group = "all", item = "battery", chance = 0 / 0 } }, "機率 NaN")
rejects({ { group = "custom", item = "battery", chance = 1 } }, "自訂服裝沒有 outfits")
rejects({ { group = "custom", item = "battery", chance = 1, outfits = { "Bad Name" } } }, "服裝名有空白")
rejects({ { group = "army", item = "battery", chance = 1, outfits = { "Police" } } }, "非自訂分組帶 outfits")
rejects({ { group = "all", item = "battery", chance = 1, weight = 2 } }, "未知欄位")
rejects({ { group = "all", item = "battery", chance = 1 }, "x" }, "清單裡有不是物件的")
local many = {}
for i = 1, D.MAX_RULES + 1 do many[i] = { group = "all", item = "battery", chance = 1 } end
rejects(many, "超過規則上限")
check(D.parse({}) and #D.parse({}) == 0, "空清單合法（等於不掉落）")

-- ===== 伺服器設定檔 =====
local PATH = "MinidoracatWatch/servertest/server-settings.json"
check(Cfg.path() == PATH, "dedicated：Zomboid/Lua/MinidoracatWatch/伺服器名/server-settings.json")
F.mode = "sp"
check(Cfg.path() == "MinidoracatWatch/sp_Muldraugh__KY/server-settings.json", "單機：sp_存檔名（非英數換底線）")
F.mode = "server"
F.reset()
Cfg.poll()
check(FS[PATH] ~= nil and logged("server settings written with defaults"), "缺檔：寫一份預設並 log")
local doc = Cfg.decode(FS[PATH])
check(doc and doc.version == 1 and #doc.zombieDrops == 10 and doc.zombieDrops[5].item == "watch:crt", "寫出的檔解得回來、10 條")
check(FS[PATH]:find('"group": "all"', 1, true) and FS[PATH]:find("\n  \"zombieDrops\": [", 1, true), "縮排輸出、鍵照 group 開頭")
local reparsed = D.parse(doc.zombieDrops)
check(reparsed and reparsed[1].chance == 0.2, "寫出的規則再驗證也通過（0.2 不失真）")
-- 管理員改檔：10 秒內套用
local function setFile(text)
    FS[PATH] = text
    F.now = F.now + Cfg.POLL_MS
    F.reset()
    Cfg.tick()
end
setFile('{ "version": 1, "zombieDrops": [ { "group": "custom", "outfits": ["HazardSuit"], "item": "mod:any", "chance": 50 } ] }')
local cur = Cfg.get("zombieDrops")
check(#cur == 1 and cur[1].outfitSet.HazardSuit and logged("server settings loaded"), "改檔：下一次輪詢套用新規則")
setFile("{ not json")
check(Cfg.get("zombieDrops") == cur and logged("not a JSON object"), "壞 JSON：保留上一份有效規則並 log")
F.now = F.now + Cfg.POLL_MS
F.reset()
Cfg.tick()
check(#F.logs == 0, "同一份壞內容不重複 log")
setFile('[1, 2]')
check(Cfg.get("zombieDrops") == cur, "最外層是陣列：保留上一份")
setFile('{ "zombieDrops": [ { "group": "all", "item": "battery", "chance": 1 }, { "group": "army", "item": "nope", "chance": 1 } ] }')
check(Cfg.get("zombieDrops") == cur and logged("rule 2: unknown item nope") and logged("keeping the previous zombieDrops"),
    "有一條不合法：整個區段保留上一份，log 指出第幾條")
setFile('\239\187\191{ "version": 1, "zombieDrops": [ { "group": "all", "item": "battery", "chance": 5 } ], "futureThing": 1 }')
cur = Cfg.get("zombieDrops")
check(#cur == 1 and cur[1].item == "battery" and logged("unknown key futureThing"), "BOM 可讀；未知的鍵只 log、不影響掉落規則")
setFile('{ "version": 1 }')
check(#Cfg.get("zombieDrops") == 10, "缺區段：用預設值")
unreadable[PATH] = true
setFile(FS[PATH])
check(#Cfg.get("zombieDrops") == 10 and logged("unreadable"), "讀不到：保留目前設定並 log")
unreadable[PATH] = nil
-- 可擴充：再登記一個區段（Phase 4 第三方模組耗電會這樣加），兩個區段各自驗證
Cfg.section("testDrain", {
    default = function() return { a = 10 } end,
    parse = function(raw)
        if type(raw) ~= "table" or type(raw.a) ~= "number" then return nil, { "a must be a number" } end
        return { a = raw.a }
    end,
})
setFile('{ "zombieDrops": [ { "group": "all", "item": "battery", "chance": 7 } ], "testDrain": { "a": "x" } }')
check(Cfg.get("zombieDrops")[1].chance == 7 and Cfg.get("testDrain").a == 10 and logged("testDrain: a must be a number"),
    "新區段壞掉：只有它保留上一份，掉落規則照常套用")
FS[PATH] = nil
writeFails = true
F.now = F.now + Cfg.POLL_MS
F.reset()
Cfg.tick()
check(logged("could not be written") and Cfg.get("zombieDrops")[1].chance == 7, "寫不進去：log、沿用記憶體裡的設定")
writeFails = false

-- ===== OnFillContainer =====
FS[PATH] = '{ "zombieDrops": [ { "group": "survivalist", "item": "watch:crt", "chance": 100 }, { "group": "all", "item": "battery", "chance": 100 } ] }'
F.now = F.now + Cfg.POLL_MS
Cfg.tick()
local function fill(room, outfit, c)
    c = c or F.container()
    c._class = "ItemContainer"
    F.fire("OnFillContainer", room, outfit, c)
    return c
end
local c = fill("Zombie", "Survivalist02_Mid")
check(#c.items == 1 and c.items[1].fullType == "MinidoracatWatch.MapWatch_BB3000_Left", "生存狂屍體：上限 1，只放嗶嗶腕機")
check(c.items[1]:getVisual():getTextureChoice() == 0, "掉落的嗶嗶腕機外觀設成綠色（生成時是隨機）")
SB.ZombieDropCap = 3
c = fill("Zombie", "Survivalist02_Mid")
check(#c.items == 2, "上限 3：兩條都掉")
SB.ZombieDropCap = 9
check(D.cap() == 5, "上限超過 5：夾到 5")
SB.ZombieDropCap = nil
check(#fill("Zombie Bag", "Survivalist").items == 0, "不是 Zombie（殭屍的袋子）：不處理")
check(#fill("bedroom", "Survivalist").items == 0, "一般容器：不處理")
F.fire("OnFillContainer", "Zombie", "Survivalist", { items = {} })
check(true, "第三參數不是 ItemContainer：不出錯")
SB.ZombieDrops = false
check(#fill("Zombie", "Survivalist").items == 0, "沙盒關閉殭屍掉落：不放")
SB.ZombieDrops = nil
SB.Enabled = false
check(#fill("Zombie", "Survivalist").items == 0, "地圖錶系統關閉：不放")
SB.Enabled = true

-- ===== 戰利品分佈 =====
local vanilla = readFile(PZ .. "/media/lua/server/Items/ProceduralDistributions.lua")
if vanilla then
    -- 原版檔引用 ClutterTables 等其他全域：沒有的一律給一個可無限索引的假表
    local dummy = setmetatable({}, {})
    getmetatable(dummy).__index = function() return dummy end
    local env = setmetatable({}, { __index = function(_, k) return _G[k] or dummy end })
    assert(load(vanilla, "ProceduralDistributions", "t", env))()
    ProceduralDistributions = env.ProceduralDistributions
else
    F.print("  (原版 ProceduralDistributions.lua 不在：用假表)")
end
F.load("server/MinidoracatWatch_Loot.lua")
local Lt = W.Loot
if not vanilla then
    ProceduralDistributions = { list = {} }
    for name in pairs(Lt.TABLES) do ProceduralDistributions.list[name] = { rolls = 1, items = { "Base.Apple", 1 } } end
end
local list = ProceduralDistributions.list
local missingT = {}
for name in pairs(Lt.TABLES) do if not (list[name] and list[name].items) then missingT[#missingT + 1] = name end end
check(#missingT == 0, "分佈表名都在原版 ProceduralDistributions（缺：" .. table.concat(missingT, ",") .. "）")
local function count(name, item)
    local n, items = 0, list[name].items
    for i = 1, #items, 2 do if items[i] == item then n = n + 1 end end
    return n
end
local function ours()
    local n = 0
    for name in pairs(Lt.TABLES) do
        local items = list[name].items
        for i = 1, #items, 2 do if type(items[i]) == "string" and items[i]:find("^MinidoracatWatch%.") then n = n + 1 end end
    end
    return n
end
local total = 0
for _, e in ipairs(Lt.ENTRIES) do total = total + #e[3] / 2 end
local before = #list.ElectronicStoreMisc.items
F.reset()
Lt.tick()
check(ours() == 0 and parses == 0, "還沒 merge：輪詢不動分佈表")
F.fire("OnPostDistributionMerge")
check(ours() == total and parses == 0 and logged("loot tables prepared"), "開局 merge：加入全部 " .. total .. " 筆、不自己 Parse")
check(count("JewelryWrist", W.watchType("Luthex")) == 1 and count("ArmyBunkerStorage", W.watchType("BB3000")) == 1
    and count("GiftStoreToys", W.watchType("Paws")) == 1, "盧瑟斯在珠寶店、嗶嗶腕機在地堡、貓爪在禮品店")
local lightAnywhere = false
for name in pairs(Lt.TABLES) do if count(name, "MinidoracatWatch.Module_Light") > 0 then lightAnywhere = true end end
check(not lightAnywhere, "照明模組不在任何分佈表")
local wantStyles = {}
for _, e in ipairs(Lt.ENTRIES) do if W.WATCH_TYPES[e[2]] then wantStyles[e[2]] = true end end
local nStyles = 0
for _ in pairs(wantStyles) do nStyles = nStyles + 1 end
check(nStyles == 7, "七款錶都有分佈")
-- 改沙盒（原生選項）：下一次輪詢重排並 Parse；簽章沒變不再 Parse
NATIVE["MinidoracatWatch.LootBB3000"] = false
F.now = F.now + Lt.POLL_MS
F.reset()
Lt.tick()
check(parses == 1 and count("ArmyBunkerStorage", W.watchType("BB3000")) == 0 and count("SurvivalGear", W.watchType("BB3000")) == 0
    and count("SurvivalGear", "MinidoracatWatch.Module_Compass") == 1 and logged("after a sandbox change"),
    "關掉嗶嗶腕機：從所有表移除、其他照舊、Parse 一次")
F.now = F.now + Lt.POLL_MS
Lt.tick()
check(parses == 1, "沒變：不再 Parse")
NATIVE["MinidoracatWatch.LootBB3000"] = true
for _ = 1, 3 do F.now = F.now + Lt.POLL_MS; Lt.tick() end
check(parses == 2 and count("ArmyBunkerStorage", W.watchType("BB3000")) == 1 and ours() == total, "打開回來：每筆只有一份（不重複）")
NATIVE["MinidoracatWatch.LootModules"], NATIVE["MinidoracatWatch.LootCards"] = false, false
F.now = F.now + Lt.POLL_MS
Lt.tick()
check(count("ElectronicStoreMisc", "MinidoracatWatch.Module_GPS") == 0 and count("ElectronicStoreMisc", W.CARD_TYPES.ext) == 0
    and count("ElectronicStoreMisc", W.watchType("ValuTech")) == 1, "關掉模組與解鎖卡：錶照舊")
NATIVE["MinidoracatWatch.Enabled"] = false
F.now = F.now + Lt.POLL_MS
Lt.tick()
check(ours() == 0, "地圖錶系統關閉：本 MOD 的物品全部移除")
check(#list.ElectronicStoreMisc.items == before, "原版的筆數不變（只動本 MOD 的物品）")
NATIVE = {}
F.now = F.now + Lt.POLL_MS
Lt.tick()
check(ours() == total, "原生選項拿不到：退回 SandboxVars（預設全開）")

-- ===== 配方 OnTest =====
check(MinidoracatWatch_Recipe == nil, "配方 OnTest 在 shared 檔，尚未載入")
F.load("shared/MinidoracatWatch_Recipe.lua")
check(MinidoracatWatch_Recipe.canCraft() == true, "預設可以製作")
SB.AllowCraft = false
check(MinidoracatWatch_Recipe.canCraft() == false, "沙盒關閉製作：不能做")
SB.AllowCraft = nil
SB.Enabled = false
check(MinidoracatWatch_Recipe.canCraft() == false, "地圖錶系統關閉：不能做")
SB.Enabled = true

-- ===== 嗶嗶腕機的螢幕：伺服器 =====
local BB = "MinidoracatWatch.MapWatch_BB3000_Left"
local p = F.player("bob", 0)
p.onlineId = 3
local bb = F.item(BB)
bb:getVisual():setTextureChoice(1) -- 生成時隨機到琥珀
p.inv:AddItem(bb)
F.wear(p, bb)
F.reset()
W.visitAll(F.now, false)
local function screens()
    local out = {}
    for _, cmd in ipairs(F.serverCmds) do if cmd.command == W.CMD_SCREEN then out[#out + 1] = cmd end end
    return out
end
local s1 = screens()
check(#s1 == 1 and s1[1].broadcast and s1[1].args.pid == 3 and s1[1].args.choice == 0 and bb:getVisual():getTextureChoice() == 0,
    "戴上：伺服器的外觀改回綠色並廣播給所有連線")
F.reset()
W.visitAll(F.now, false)
check(#screens() == 0, "沒變：不再廣播")
check(W.applyScreen(p, bb:getID(), 1) == true and bb:getModData()[W.SCREEN_KEY] == 1, "切換：寫進錶的 modData")
s1 = screens()
check(#s1 == 1 and s1[1].args.choice == 1 and #F.synced == 1 and bb:getVisual():getTextureChoice() == 1, "切換：同步 modData、廣播琥珀")
local vt = F.item(F.LEFT)
p.inv:AddItem(vt)
local floor = F.item(BB)
for _, bad in ipairs({ { vt:getID(), 0, "其他款" }, { bb:getID(), 2, "choice 2" }, { bb:getID(), "1", "choice 字串" },
        { bb:getID() + 0.5, 1, "id 不是整數" }, { floor:getID(), 1, "不在自己背包" } }) do
    check(W.applyScreen(p, bad[1], bad[2]) == false, "拒絕：" .. bad[3])
end
F.unwear(p, bb)
W.visitAll(F.now, false)
F.reset()
F.wear(p, bb)
W.visitAll(F.now, false)
s1 = screens()
check(#s1 == 1 and s1[1].args.choice == 1, "拿下再戴：再廣播一次（琥珀）")
F.mode = "client"
check(W.applyScreen(p, bb:getID(), 0) == false, "MP 客戶端不能直接改（要送指令）")
-- 單機：直接改外觀、重建模型，不送封包
F.mode = "sp"
F.players = { p }
p.resets = 0
F.reset()
check(W.applyScreen(p, bb:getID(), 0) == true and bb:getVisual():getTextureChoice() == 0 and p.resets == 1 and #screens() == 0,
    "單機：改外觀＋resetModelNextFrame、不廣播")

F.finish("test_watch_acquire")
