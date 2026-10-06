-- 地圖錶模組與槽位（shared）：API 驗證、getWatchModuleState 優先序真值表、安裝／拆下伺服器驗證與模組守恆、
-- 解鎖卡（不能重複使用、帳號鍵、客戶端不能偽造）、耗電倍率（模組、節能核心、槽位失效）、onStateChanged。
-- 用法（repo 根目錄）：lua scripts/test_watch_modules.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check, near = F.check, F.near
F.mode = "server"
require "MinidoracatWatch"
local W = MinidoracatWatchCore
local API = MinidoracatWatchAPI
local SB = SandboxVars.MinidoracatWatch
local H = 3600000
local MOD = function(name) return "MinidoracatWatch.Module_" .. name end

-- ===== API：版本、內建登記、驗證 =====
check(type(API) == "table" and API.watchApiVersion == 1, "MinidoracatWatchAPI.watchApiVersion = 1")
check(type(API.registerWatchModule) == "function" and type(API.registerWatchSlot) == "function"
    and type(API.getWatchModuleState) == "function", "三個 API 函式")
check(#W.moduleList == 10 and W.modules.compass and W.modules.eco and not W.modules.light, "內建 10 個模組（照明是 Phase 8）")
check(W.modules.mildetect.class == "advanced" and W.modules.relay.class == "core" and W.modules.gps.drain == 25,
    "內建模組的類別與耗電照設計稿")
check(#W.slotList == 6 and W.slotById.adv.accepts.advanced and not W.slotById.ext.accepts.advanced
    and W.slotById.core.accepts.core, "內建 6 個槽位，可裝類別照 ACCEPTS")

local function rejects(fn, def, label)
    F.reset()
    local ok = fn(def)
    check(ok == false and #F.logs == 1, "拒收並 log 一次：" .. label)
end
local good = { id = "weather", name = "IGUI_X_Weather", class = "standard", drain = 15, item = "MyWeather.WeatherModule" }
local function with(k, v)
    local t = {}
    for kk, vv in pairs(good) do t[kk] = vv end
    t[k] = v
    return t
end
rejects(API.registerWatchModule, nil, "def 不是 table")
rejects(API.registerWatchModule, with("id", ""), "空 id")
rejects(API.registerWatchModule, with("id", "bad id"), "id 有空白")
rejects(API.registerWatchModule, with("id", 5), "id 不是字串")
rejects(API.registerWatchModule, with("id", "compass"), "id 和內建重複")
rejects(API.registerWatchModule, with("name", ""), "空 name")
rejects(API.registerWatchModule, with("class", "legendary"), "未知 class")
rejects(API.registerWatchModule, with("drain", 0 / 0), "drain 是 NaN")
rejects(API.registerWatchModule, with("drain", -1), "drain 是負數")
rejects(API.registerWatchModule, with("drain", 1 / 0), "drain 是無限大")
rejects(API.registerWatchModule, with("drain", "15"), "drain 是字串")
rejects(API.registerWatchModule, with("item", "NoModule"), "item 沒有 module 前綴")
rejects(API.registerWatchModule, with("item", MOD("GPS")), "item 已被其他模組使用")
rejects(API.registerWatchModule, with("onStateChanged", "yes"), "onStateChanged 不是函式")
check(W.modules.weather == nil and #W.moduleList == 10, "拒收的 def 沒有留下任何登記")
local calls = {}
local def = with("onStateChanged", function(p, s, old) calls[#calls + 1] = { s = s, old = old } end)
check(API.registerWatchModule(def) == true, "合法的第三方模組登記成功")
def.drain = 999
check(W.modules.weather.drain == 15, "登記時複製欄位，呼叫端之後改 def 不影響")
rejects(API.registerWatchModule, with("item", "MyWeather.Other"), "重複 id（第二次登記）")

local slotGood = { id = "forecast", name = "IGUI_X_Slot", accepts = { "standard" }, price = { rent = 80, days = 7, buy = 600 } }
local function slotWith(k, v)
    local t = {}
    for kk, vv in pairs(slotGood) do t[kk] = vv end
    t[k] = v
    return t
end
rejects(API.registerWatchSlot, slotWith("id", "ext"), "槽位 id 和內建重複")
rejects(API.registerWatchSlot, slotWith("accepts", {}), "accepts 空的")
rejects(API.registerWatchSlot, slotWith("accepts", { "standard", "mythic" }), "accepts 有未知類別")
rejects(API.registerWatchSlot, slotWith("accepts", "standard"), "accepts 不是陣列")
rejects(API.registerWatchSlot, slotWith("price", nil), "沒有 price")
rejects(API.registerWatchSlot, slotWith("price", { rent = -1, days = 7, buy = 0 }), "price 負數")
rejects(API.registerWatchSlot, slotWith("price", { rent = 1, days = 0, buy = 0 }), "price 天數 0")
rejects(API.registerWatchSlot, slotWith("name", nil), "槽位沒有 name")
check(API.registerWatchSlot(slotGood) == true and W.slotById.forecast.tier == "addon"
    and W.slotList[7] == W.slotById.forecast, "第三方槽位登記在內建之後")
rejects(API.registerWatchSlot, slotGood, "重複的槽位 id")
for i = 1, 5 do API.registerWatchSlot(slotWith("id", "extra" .. i)) end
rejects(API.registerWatchSlot, slotWith("id", "extra6"), "超過 6 個第三方槽位")
-- 後面的測試只要一個第三方槽位：移除多出來的（登記表是內部資料，測試直接整理）
for i = #W.slotList, 8, -1 do W.slotById[W.slotList[i].id] = nil; W.slotList[i] = nil end

-- ===== 共用場景 =====
F.reset()
local alice = F.player("alice", 0)
local function give(p, t) local it = F.item(t); p.inv:AddItem(it); return it end
local watch = give(alice, F.RIGHT)
F.wear(alice, watch)
local screwdriver = give(alice, "Base.Screwdriver")
local function install(p, w, slotId, item) return W.applyModuleChange(p, w:getID(), slotId, true, item:getID()) end
local function remove(p, w, slotId) return W.applyModuleChange(p, w:getID(), slotId, false) end

-- ===== 安裝／拆下：happy path、modData 往返 =====
local compass = give(alice, MOD("Compass"))
compass:getModData().serial = "C-1"
compass:getModData().nested = { a = 1, b = { "x" } }
F.reset()
check(install(alice, watch, "std1", compass) == true, "安裝羅盤到標準槽 1")
check(compass.container == nil and F.removed[1] == compass, "模組物品離開背包並送移除封包")
local rec = W.slotRecord(watch, "std1")
check(rec and rec.id == "compass" and rec.item == MOD("Compass") and rec.md.serial == "C-1" and rec.md.nested.b[1] == "x",
    "紀錄進錶的 modData（含模組物品 modData 的複本）")
check(#F.synced == 1 and F.synced[1].item == watch, "同步錶的 modData")
F.reset()
check(remove(alice, watch, "std1") == true, "拆下")
local back = alice.inv:getAllTypeRecurse(MOD("Compass"))
check(back:size() == 1 and back:get(0) ~= compass and back:get(0):getModData().serial == "C-1"
    and back:get(0):getModData().nested.a == 1, "拆下：以同類型建回物品，modData 還原")
check(W.slotRecord(watch, "std1") == nil and F.added[1] == back:get(0) and #F.synced == 1, "槽位清空、送新增封包、同步錶")
compass = back:get(0)

-- ===== 反例：每一條都不得動到任何東西，總數守恆 =====
local bob = F.player("bob", 1)
local bobWatch = give(bob, F.LEFT)
local bobModule = give(bob, MOD("Ledger"))
give(bob, "Base.Screwdriver")
local gps = give(alice, MOD("GPS"))
local mil = give(alice, MOD("MilDetect"))
local relay = give(alice, MOD("Relay"))
local battery = give(alice, "Base.Battery")
install(alice, watch, "std2", gps)

-- 世界上所有模組（背包裡的物品＋所有錶上的紀錄）
local function moduleCount()
    local n = 0
    local function walk(c)
        for _, it in ipairs(c.items) do
            if W.moduleByItem[it.fullType] then n = n + 1 end
            if W.isWatch(it) and W.slotsOf(it) then
                for _ in pairs(W.slotsOf(it)) do n = n + 1 end
            end
            if it.bag then walk(it.bag) end
        end
    end
    for _, p in ipairs(F.players) do walk(p.inv) end
    return n
end
local function snapshot()
    local s = {}
    for _, p in ipairs(F.players) do
        for _, it in ipairs(p.inv.items) do s[#s + 1] = tostring(it.id) end
    end
    for _, w in ipairs({ watch, bobWatch }) do
        for k, v in pairs(W.slotsOf(w) or {}) do s[#s + 1] = w.id .. ":" .. k .. "=" .. v.id end
    end
    table.sort(s)
    return table.concat(s, ",")
end
local total = moduleCount()
local function untouched(label, expectReason, ...)
    F.reset()
    local before = snapshot()
    local ok, reason = W.applyModuleChange(...)
    check(ok == false and snapshot() == before and moduleCount() == total and #F.synced == 0 and #F.added == 0
        and #F.removed == 0 and (expectReason == nil or reason == expectReason), label .. "（reason=" .. tostring(reason) .. "）")
end
local wid = watch:getID()
untouched("別人的錶", W.FAIL_MODULE, alice, bobWatch:getID(), "std3", true, compass:getID())
untouched("別人的模組", W.FAIL_MODULE, alice, wid, "std3", true, bobModule:getID())
untouched("地上的模組（不在任何人背包）", W.FAIL_MODULE, alice, wid, "std3", true, F.item(MOD("Scan")):getID())
untouched("拿電池當模組", W.FAIL_MODULE, alice, wid, "std3", true, battery:getID())
untouched("拿錶當模組", W.FAIL_MODULE, alice, wid, "std3", true, wid)
untouched("watchId 指向模組", W.FAIL_MODULE, alice, compass:getID(), "std3", true, compass:getID())
untouched("未知槽位", W.FAIL_MODULE, alice, wid, "std9", true, compass:getID())
untouched("槽位 id 不是字串", W.FAIL_MODULE, alice, wid, 1, true, compass:getID())
untouched("非整數 watchId", W.FAIL_MODULE, alice, wid + 0.5, "std3", true, compass:getID())
untouched("非整數 itemId", W.FAIL_MODULE, alice, wid, "std3", true, compass:getID() + 0.25)
untouched("NaN id", W.FAIL_MODULE, alice, 0 / 0, "std3", true, compass:getID())
untouched("無限大 id", W.FAIL_MODULE, alice, wid, "std3", true, 1 / 0)
untouched("字串 id", W.FAIL_MODULE, alice, tostring(wid), "std3", true, compass:getID())
untouched("install 不是布林", W.FAIL_MODULE, alice, wid, "std3", "yes", compass:getID())
untouched("槽位已滿", W.FAIL_SLOT_FULL, alice, wid, "std2", true, compass:getID())
untouched("進階模組裝標準槽", W.FAIL_CLASS, alice, wid, "std3", true, mil:getID())
untouched("核心模組裝標準槽", W.FAIL_CLASS, alice, wid, "std3", true, relay:getID())
untouched("拆空槽", W.FAIL_SLOT_EMPTY, alice, wid, "std3", false)
SB.SlotExt = 2
untouched("解鎖卡模式、沒用卡：擴充槽無效", W.FAIL_SLOT_INVALID, alice, wid, "ext", true, compass:getID())
SB.SlotExt = 4
untouched("不開放的擴充槽", W.FAIL_SLOT_INVALID, alice, wid, "ext", true, compass:getID())
SB.SlotExt = 3
untouched("經濟系統（Phase 6 前當解鎖卡）、沒用卡", W.FAIL_SLOT_INVALID, alice, wid, "ext", true, compass:getID())
SB.SlotCore = 1
alice.inv:DoRemoveItem(screwdriver)
untouched("沒有螺絲起子", W.FAIL_SCREWDRIVER, alice, wid, "std3", true, compass:getID())
untouched("沒有螺絲起子也不能拆", W.FAIL_SCREWDRIVER, alice, wid, "std2", false)
local broken = give(alice, "Base.Screwdriver")
broken.broken = true
untouched("壞掉的螺絲起子不算", W.FAIL_SCREWDRIVER, alice, wid, "std3", true, compass:getID())
alice.inv:DoRemoveItem(broken)
local bag = F.bag(alice.inv)
bag:AddItem(screwdriver)
check(install(alice, watch, "core", relay) == true, "袋子裡的螺絲起子也算；核心模組裝核心槽（核心槽免費時）")
check(remove(alice, watch, "core") == true, "核心槽拆下")
relay = alice.inv:getAllTypeRecurse(MOD("Relay")):get(0)
SB.SlotCore = 3
SB.NeedScrewdriver = false
bag:DoRemoveItem(screwdriver)
check(install(alice, watch, "std3", compass) == true, "沙盒關掉螺絲起子：不需要工具")
check(remove(alice, watch, "std3") == true, "沙盒關掉螺絲起子：拆下也不需要")
compass = alice.inv:getAllTypeRecurse(MOD("Compass")):get(0)
SB.NeedScrewdriver = true
alice.inv:AddItem(screwdriver)
alice.dead = true
untouched("死掉的玩家", W.FAIL_MODULE, alice, wid, "std3", true, compass:getID())
alice.dead = nil
untouched("沒有玩家", W.FAIL_MODULE, nil, wid, "std3", true, compass:getID())
F.mode = "client"
untouched("MP 客戶端不能直接改", W.FAIL_MODULE, alice, wid, "std3", true, compass:getID())
F.mode = "server"
-- 錶上的紀錄被改成別的物品類型：拆不出那個物品（只建回已登記的模組類型）
watch:getModData()[W.SLOTS_KEY].std3 = { id = "compass", item = "Base.Katana" }
total = moduleCount()
untouched("紀錄被改成其他物品：拆不出來", W.FAIL_MODULE, alice, wid, "std3", false)
check(alice.inv:getAllTypeRecurse("Base.Katana"):size() == 0, "沒有憑空變出物品")
watch:getModData()[W.SLOTS_KEY].std3 = nil
total = moduleCount()
-- 提供模組的 MOD 被移除（物品類型不存在）：拆不下來，模組留在錶上、不被吃掉
F.missingTypes[MOD("GPS")] = true
untouched("模組物品類型不存在：留在錶上", W.FAIL_MODULE, alice, wid, "std2", false)
check(W.slotRecord(watch, "std2") ~= nil, "紀錄還在")
F.missingTypes[MOD("GPS")] = nil

-- 隨機序列：合法與不合法的指令混著跑，模組總數永遠守恆
math.randomseed(42)
local items = { compass, mil, relay }
local slots = { "std1", "std2", "std3", "ext", "adv", "core", "forecast", "bogus" }
local conserved, applied = true, 0
for _ = 1, 400 do
    local inst = math.random() < 0.5
    local it = alice.inv:getAllTypeRecurse(MOD(({ "Compass", "MilDetect", "Relay", "GPS" })[math.random(4)])):get(0)
        or items[math.random(#items)]
    SB.SlotAdv = math.random(4)
    if W.applyModuleChange(alice, wid, slots[math.random(#slots)], inst, it:getID()) then applied = applied + 1 end
    if moduleCount() ~= total then conserved = false end
end
SB.SlotAdv = 3
check(conserved and applied >= 40, "400 次隨機安裝／拆下（成功 " .. applied .. " 次）：模組總數守恆（" .. total .. "）")

-- ===== 解鎖卡 =====
F.reset()
SB.SlotExt = 2
local card = give(alice, "MinidoracatWatch.UnlockCard_Ext")
local cardAdv = give(alice, "MinidoracatWatch.UnlockCard_Adv")
local ext = W.slotById.ext
check(W.slotValid(alice, ext) == false, "解鎖卡模式：沒用卡前擴充槽無效")
local r1, r2 = W.applyUnlock(alice, "ext", cardAdv:getID())
check(r1 == false and cardAdv.container == alice.inv, "卡種不對：拒絕、卡不被吃")
r1 = W.applyUnlock(alice, "ext", give(bob, "MinidoracatWatch.UnlockCard_Ext"):getID())
check(r1 == false, "別人的卡：拒絕")
F.reset()
check(W.applyUnlock(alice, "ext", card:getID()) == true, "用擴充槽解鎖卡")
check(card.container == nil and F.removed[1] == card, "卡用掉（移除封包）")
check(W.slotValid(alice, ext) == true, "擴充槽有效")
check(F.globalModData[W.UNLOCK_TABLE].alice and F.globalModData[W.UNLOCK_TABLE].alice.n.ext == true,
    "紀錄在伺服器全域 ModData，鍵＝登入名、no-steam 的驗證鍵 n")
local push = F.serverCmds[1]
check(push and push.player == alice and push.command == W.CMD_UNLOCKS and push.args.to == "alice"
    and push.args.slots.ext == true, "變更時把自己的解鎖狀態送給客戶端")
local card2 = give(alice, "MinidoracatWatch.UnlockCard_Ext")
r1, r2 = W.applyUnlock(alice, "ext", card2:getID())
check(r1 == false and r2 == W.FAIL_UNLOCKED and card2.container == alice.inv, "已開啟：第二張卡被拒、不被吃（不能重複使用）")
SB.SlotExt = 1
check(W.applyUnlock(alice, "forecast", card2:getID()) == false and card2.container == alice.inv, "免費槽位：不收卡")
SB.SlotExt = 4
check(W.slotValid(alice, ext) == false and W.applyUnlock(alice, "ext", card2:getID()) == false,
    "不開放：已解鎖也無效、不收卡")
SB.SlotExt = 2
check(W.applyUnlock(alice, "std1", card2:getID()) == false, "標準槽不用卡")
check(W.applyUnlock(alice, "nope", card2:getID()) == false, "未知槽位")
check(W.applyUnlock(alice, "adv", card2:getID() + 0.5) == false, "非整數 cardId")
SB.SlotAddon = 2
check(W.applyUnlock(alice, "forecast", card2:getID()) == true, "其他 MOD 的槽位用擴充槽解鎖卡")
SB.SlotAddon = 1
-- 帳號身分（W.account）：MP 伺服器上分割畫面第 2～4 位不能用；Steam 伺服器以 SteamID 指紋驗證，改名冒用讀不到
local alice1 = F.player("alice", 1)
alice1.inv:AddItem(F.item("MinidoracatWatch.UnlockCard_Adv"))
check(W.slotValid(alice1, ext) == false and W.account(alice1) == nil, "分割畫面第 2 位玩家取名 alice：讀不到 alice 的名額")
local r3, r4 = W.applyUnlock(alice1, "adv", alice1.inv:getAllTypeRecurse("MinidoracatWatch.UnlockCard_Adv"):get(0):getID())
check(r3 == false and r4 == W.FAIL_UNLOCK_ACCOUNT and alice1.inv:getAllTypeRecurse("MinidoracatWatch.UnlockCard_Adv"):size() == 1,
    "身分無法驗證：不能用卡、卡不被吃")
F.reset()
W.pushUnlocks(alice1)
check(F.serverCmds[1] and next(F.serverCmds[1].args.slots) == nil, "身分無法驗證：推播空表")
check(W.account(F.player("", 0)) == nil, "空名字：無法驗證")
-- Steam 伺服器：alice（SteamID A）用卡；mallory（SteamID B）在同一座位重生、改名 alice（ConnectCoopPacket.java:72-97）
F.steam = true
local sa, sb = 76561198000000000, 76561198012345680
local steamAlice = F.player("salice", 0)
steamAlice.sid = sa
local sCard = F.item("MinidoracatWatch.UnlockCard_Ext")
steamAlice.inv:AddItem(sCard)
check(W.applyUnlock(steamAlice, "ext", sCard:getID()) == true and W.slotValid(steamAlice, ext), "Steam：alice 用卡開擴充槽")
local impostor = F.player("salice", 0)
impostor.sid = sb
check(W.slotValid(impostor, ext) == false, "Steam：同座位重生改名成 alice（SteamID 不同）讀不到 alice 的名額")
local iCard = F.item("MinidoracatWatch.UnlockCard_Ext")
impostor.inv:AddItem(iCard)
check(W.applyUnlock(impostor, "ext", iCard:getID()) == true and W.slotValid(impostor, ext), "冒名者用自己的卡只開自己那份")
local back = F.player("salice", 0)
back.sid = sa
check(W.slotValid(back, ext) and F.globalModData[W.UNLOCK_TABLE].salice ~= nil, "alice 回來：自己的名額還在、沒被蓋掉")
local stored = false
for _, v in pairs(F.globalModData[W.UNLOCK_TABLE].salice) do if v == sa then stored = true end end
for k in pairs(F.globalModData[W.UNLOCK_TABLE].salice) do if k:find(string.format("%.0f", sa), 1, true) then stored = true end end
check(not stored, "全域 ModData 只存指紋、不存 SteamID")
local noSid = F.player("salice", 0)
check(W.slotValid(noSid, ext) == false and W.account(noSid) == nil, "Steam 伺服器上讀不到 SteamID：無法驗證")
F.steam = false
check(W.account(steamAlice) == "salice", "no-steam：沒有驗證因子，回登入名（已知殘餘風險）")
F.mode = "sp"
check(W.account(alice1) == W.seenKey(alice1), "單機：帳號＝帳號|本機座位（分割畫面各自一份）")
F.mode = "server"
-- 換戴別支錶也能用
local watch2 = give(alice, F.LEFT)
compass = give(alice, MOD("Compass"))
check(install(alice, watch2, "ext", compass) == true, "換一支錶：擴充槽一樣有效（綁帳號，不綁錶）")
remove(alice, watch2, "ext")
compass = alice.inv:getAllTypeRecurse(MOD("Compass")):get(0)
-- 客戶端不能偽造：玩家 modData 被整表覆蓋不影響；MP 客戶端不能直接改；客戶端送的 unlocks 指令伺服器不認
alice.md = { MinidoracatWatchUnlocks = { adv = true } }
check(W.slotValid(alice, W.slotById.adv) == false, "玩家 modData 寫什麼都不算")
F.mode = "client"
check(W.applyUnlock(alice, "adv", give(alice, "MinidoracatWatch.UnlockCard_Adv"):getID()) == false, "MP 客戶端不能直接解鎖")
W.clientUnlocks.alice = { adv = true }
check(W.slotValid(alice, W.slotById.adv) == true, "MP 客戶端只看伺服器送來的那份（顯示用）")
W.clientUnlocks.alice = nil
F.mode = "server"
check(F.globalModData[W.UNLOCK_TABLE].alice.n.adv == nil, "伺服器紀錄沒有被客戶端改到")

-- ===== 耗電倍率 =====
local w3 = give(alice, F.RIGHT)
check(W.drainFactor(alice, w3) == 1, "沒有模組＝1")
install(alice, w3, "std1", compass)
install(alice, w3, "std2", alice.inv:getAllTypeRecurse(MOD("GPS")):get(0) or give(alice, MOD("GPS")))
check(near(W.drainFactor(alice, w3), 1.35), "羅盤 10% ＋ 定位 25%＝1.35")
SB.DrainGPS = 40
check(near(W.drainFactor(alice, w3), 1.5), "沙盒調整內建模組耗電")
SB.DrainGPS = nil
SB.SlotCore = 1
install(alice, w3, "core", give(alice, MOD("Eco")))
check(near(W.drainFactor(alice, w3), 1.35 / 2), "節能核心：整支錶減半")
SB.SlotCore = 4
check(near(W.drainFactor(alice, w3), 1.35), "核心槽失效：節能核心停用（paused），不再減半")
SB.SlotCore = 1
SB.RuleNav = 4
check(near(W.drainFactor(alice, w3), 1.10 / 2), "功能被關閉（disabled）的模組不耗電")
SB.RuleNav = nil
SB.SlotExt = 1
install(alice, w3, "ext", give(alice, MOD("Scan")))
check(near(W.drainFactor(alice, w3), 1.60 / 2), "擴充槽的掃描模組 +25%")
SB.SlotExt = 4
check(near(W.drainFactor(alice, w3), 1.35 / 2), "擴充槽改成不開放：模組不耗電")
SB.SlotExt = 1
SB.SlotAddon = 1
API.registerWatchModule({ id = "radar", name = "IGUI_X", class = "standard", drain = 30, item = "Other.Radar" })
install(alice, w3, "forecast", give(alice, "Other.Radar"))
check(near(W.drainFactor(alice, w3), 1.90 / 2), "第三方模組用它自己的建議耗電")
-- 伺服器扣電整合：一分鐘、倍率 0.95
F.players = { alice }
alice.worn = {}
F.wear(alice, w3)
W.setCharge(w3, 1)
local function run(ms, step)
    local t = 0
    while t < ms do F.now = F.now + step; t = t + step; W.onTick() end
end
W.onTick()
run(60000, 100)
local per = 1 / (72 * H)
check(near((1 - W.charge(w3)) / per, 60000 * 0.95, 1200), "伺服器扣電套用模組倍率（"
    .. math.floor((1 - W.charge(w3)) / per) .. " ms 當量）")

-- ===== 提供槽位的 MOD 被移除（孤立槽位）：槽位與權益凍結、模組停用不耗電、隨時能拆 =====
-- 登記表是內部資料：測試直接拿掉／放回，模擬 MOD 移除與裝回
local function dropSlot(id)
    for i = #W.slotList, 1, -1 do if W.slotList[i].id == id then table.remove(W.slotList, i) end end
    local s = W.slotById[id]
    W.slotById[id] = nil
    W.invalidate()
    return s
end
local function reregister(s)
    W.slotList[#W.slotList + 1] = s
    W.slotById[s.id] = s
    W.invalidate()
end
check(API.getWatchModuleState(alice, "radar") == "active", "孤立前：第三方槽位裡的模組 active")
local forecast = dropSlot("forecast")
local orphans = W.orphanSlots and W.orphanSlots(w3) or {}
check(#orphans == 1 and orphans[1].id == "forecast" and orphans[1].orphan == true, "錶上列得出孤立槽位")
check(orphans[1] and W.slotValid(alice, orphans[1]) == false, "孤立槽位一律無效（就算原本是免費或已解鎖）")
check(API.getWatchModuleState(alice, "radar") == "paused", "孤立槽位裡的模組 paused")
check(near(W.drainFactor(alice, w3), 1.60 / 2), "孤立槽位裡的模組不耗電")
local spareRadar = give(alice, "Other.Radar")
local okI = W.applyModuleChange(alice, w3:getID(), "forecast", true, spareRadar:getID())
check(okI == false and spareRadar.container == alice.inv, "不能裝進孤立槽位")
local okBad, rBad = W.applyModuleChange(alice, w3:getID(), "bad id!", false)
check(okBad == false and rBad == W.FAIL_MODULE, "格式不對的槽位 id 一律拒絕")
local okNone, rNone = W.applyModuleChange(alice, w3:getID(), "ghost", false)
check(okNone == false and rNone == W.FAIL_SLOT_EMPTY, "錶上沒有紀錄的未知槽位：拆不出東西")
w3:getModData()[W.SLOTS_KEY].forecast.md = { tag = "R1" }
local radarsBefore = alice.inv:getAllTypeRecurse("Other.Radar"):size()
F.reset()
check(remove(alice, w3, "forecast") == true, "孤立槽位裡的模組可以拆下")
local radars = alice.inv:getAllTypeRecurse("Other.Radar")
check(radars:size() == radarsBefore + 1 and W.slotRecord(w3, "forecast") == nil and #F.synced == 1,
    "拆下：物品回背包、紀錄清掉、同步錶")
local restored = false
for i = 0, radars:size() - 1 do
    local it = radars:get(i)
    if it:hasModData() and it:getModData().tag == "R1" then restored = true end
end
check(restored, "拆下的物品還原 modData")
check(#(W.orphanSlots and W.orphanSlots(w3) or { 0 }) == 0, "拆空之後不再列出")
reregister(forecast)
SB.SlotAddon = 2
check(W.slotValid(alice, forecast), "MOD 裝回：解鎖卡開啟的權益還在（凍結保留）")
check(install(alice, w3, "forecast", radars:get(0)) == true, "MOD 裝回：可以再裝")
dropSlot("forecast")
local radarDef = W.modules.radar
W.modules.radar, W.moduleByItem["Other.Radar"] = nil, nil
W.invalidate()
check(#(W.orphanSlots and W.orphanSlots(w3) or { 0 }) == 0, "模組類型也沒登記：不列出")
local okU = remove(alice, w3, "forecast")
check(okU == false and W.slotRecord(w3, "forecast") ~= nil, "模組類型也沒登記：拆不下來、紀錄留在錶上")
W.modules.radar, W.moduleByItem["Other.Radar"] = radarDef, radarDef
reregister(forecast)
check(API.getWatchModuleState(alice, "radar") == "active", "兩個 MOD 都裝回：恢復運作")
SB.SlotAddon = 1

-- ===== getWatchModuleState 優先序真值表 =====
-- 欄位：Enabled、RuleArrow（1 免／2 錶／3 模組／4 關）、戴錶、電量（nil＝沒電池）、羅盤在擴充槽、擴充槽有效 → 預期
local st = F.player("tess", 5)
local tw = give(st, F.RIGHT)
give(st, "Base.Screwdriver")
local tc = give(st, MOD("Compass"))
SB.SlotExt = 1
W.applyModuleChange(st, tw:getID(), "ext", true, tc:getID())
local rows = {
    { false, 4, true, 0.5, true, true, "notRequired" },
    { false, 3, false, 0.5, false, true, "notRequired" },
    { true, 4, true, 0.5, true, true, "disabled" },
    { true, 4, false, 0.5, false, true, "disabled" },
    { true, 3, true, 0.5, true, true, "active" },
    { true, 1, true, 0.5, true, true, "active" },
    { true, 2, true, 0.5, true, true, "active" },
    { true, 1, false, 0.5, false, true, "notRequired" },
    { true, 2, true, 0.5, false, true, "notRequired" },
    { true, 2, true, 0, false, true, "unpowered" },
    { true, 2, false, 0.5, false, true, "missing" },
    { true, 3, true, nil, true, true, "unpowered" },
    { true, 3, true, 0, true, true, "unpowered" },
    { true, 3, true, 0, true, false, "unpowered" },
    { true, 3, true, 0.5, true, false, "paused" },
    { true, 2, true, 0.5, true, false, "notRequired" },
    { true, 3, true, 0.5, false, true, "missing" },
    { true, 3, false, 0.5, true, true, "missing" },
}
local allRows = true
local stash = nil -- 「沒裝」列：紀錄先拿出錶外（放進錶上任何別的鍵都會變成孤立槽位）
for i, r in ipairs(rows) do
    SB.Enabled, SB.RuleArrow = r[1], r[2]
    st.worn = {}
    if r[3] then F.wear(st, tw) end
    W.setCharge(tw, r[4] == nil and W.NO_BATTERY or r[4])
    local slotsT = tw:getModData()[W.SLOTS_KEY]
    if r[5] then slotsT.ext = slotsT.ext or stash; stash = nil
    else stash = slotsT.ext or stash; slotsT.ext = nil end
    SB.SlotExt = r[6] and 1 or 4
    W.invalidate()
    local got = API.getWatchModuleState(st, "compass")
    if got ~= r[7] then
        allRows = false
        check(false, "真值表第 " .. i .. " 列：預期 " .. r[7] .. "，得到 " .. tostring(got))
    end
end
check(allRows, "getWatchModuleState 真值表 " .. #rows .. " 列")
SB.Enabled, SB.RuleArrow, SB.SlotExt = true, nil, 1
check(API.getWatchModuleState(st, "nope") == "missing" and API.getWatchModuleState(nil, "compass") == "missing",
    "未登記的 id、沒有玩家＝missing")
check(API.getWatchModuleState(st, "radar") == "missing", "第三方模組沒裝＝missing")
SB.Enabled = false
check(API.getWatchModuleState(st, "radar") == "notRequired", "地圖錶系統關閉＝notRequired")
SB.Enabled = true

-- 快取：同一秒內連續查詢不翻穿戴清單、不配置
st.worn = {}
F.wear(st, tw)
W.setCharge(tw, 0.5)
W.invalidate()
API.getWatchModuleState(st, "compass")
local scans = 0
local realWorn = st.getWornItems
st.getWornItems = function(self) scans = scans + 1; return realWorn(self) end
collectgarbage("collect")
collectgarbage("stop")
local kb = collectgarbage("count")
for _ = 1, 20000 do API.getWatchModuleState(st, "compass") end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
check(scans == 0 and grew < 1, "getWatchModuleState 20000 次：不翻穿戴清單、不配置（" .. string.format("%.2f", grew) .. " KB）")
st.getWornItems = nil

-- ===== onStateChanged（伺服器在扣電迴圈每秒比對）=====
calls = {}
F.players = { st }
local wmod = give(st, "MyWeather.WeatherModule")
run(2000, 500)
check(#calls == 1 and calls[1].s == "missing" and calls[1].old == nil, "第一次看到玩家：通知目前狀態")
run(3000, 500)
check(#calls == 1, "狀態沒變不再呼叫")
W.applyModuleChange(st, tw:getID(), "std1", true, wmod:getID())
run(1500, 500)
check(#calls == 2 and calls[2].s == "active" and calls[2].old == "missing", "裝上後通知 active")
W.modules.weather.onStateChanged = function() error("boom") end
W.applyModuleChange(st, tw:getID(), "std1", false)
F.reset()
run(1500, 500)
W.applyModuleChange(st, tw:getID(), "std1", true, st.inv:getAllTypeRecurse("MyWeather.WeatherModule"):get(0):getID())
run(1500, 500)
local errLogs = 0
for _, l in ipairs(F.logs) do if l:find("onStateChanged", 1, true) then errLogs = errLogs + 1 end end
check(errLogs == 1, "callback 拋錯：只 log 一次、不中斷扣電")

F.finish("test_watch_modules")
