-- 地圖錶 shared 核心：扣電公式與邊界、換電池守恆、伺服器驗證反例、同時只能戴一支、閘門決策表、結算節奏。
-- 用法（repo 根目錄）：lua scripts/test_watch_core.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check, near = F.check, F.near
require "MinidoracatWatch"
local W = MinidoracatWatchCore
local H = 3600000

-- 扣電掛在 OnTickEvenPaused：單機暫停時 OnTick 不觸發（GameWindow.java:354-368）
local registered = false
for _, fn in ipairs(F.handlers.OnTickEvenPaused or {}) do if fn == W.onTick then registered = true end end
check(registered and not (F.handlers.OnTick and #F.handlers.OnTick > 0), "扣電掛 OnTickEvenPaused、不掛 OnTick")

-- ===== 扣電公式 =====
check(near(W.drain(1, 72 * H, 72), 0), "滿電 72 小時扣完")
check(near(W.drain(1, 36 * H, 72), 0.5), "36 小時剩一半")
check(W.drain(0.1, 72 * H, 72) == 0, "扣過頭夾在 0")
check(W.drain(0, H, 72) == 0, "空電池不變負")
check(W.drain(nil, H, 72) == nil, "沒有電池不扣")
check(W.drain(0.5, 0, 72) == 0.5 and W.drain(0.5, -5, 72) == 0.5, "零或負時間不扣")
check(near(W.drain(1, 24 * H, 24), 0), "FullHours 換成 24 也成立")

-- tickDelta：時鐘倒退、暫停、大跳躍
check(W.tickDelta(1000, nil, false, false) == 0, "第一個 tick 不計")
check(W.tickDelta(1100, 1000, false, false) == 100, "正常 tick 計入實際間隔")
check(W.tickDelta(900, 1000, false, false) == 0, "時鐘倒退計 0")
check(W.tickDelta(1000 + 10 * H, 1000, false, false) == W.MAX_TICK_MS, "大跳躍截到 MAX_TICK_MS")
check(W.tickDelta(1100, 1000, true, false) == 0, "暫停且不允許暫停耗電＝0")
check(W.tickDelta(1100, 1000, true, true) == 100, "允許暫停耗電時照算")

-- 離線補扣
check(W.offlineMs(10 * H, 2 * H, false) == 0, "預設離線不耗電")
check(W.offlineMs(10 * H, 2 * H, true) == 8 * H, "開啟後補扣離線時間")
check(W.offlineMs(2 * H, 10 * H, true) == 0, "離線期間時鐘倒退＝0")
check(W.offlineMs(10 * H, nil, true) == 0, "沒有上次時間（新角色）＝0")
check(W.offlineMs(1e15, 0, true) == W.MAX_OFFLINE_MS, "離線大跳躍有上限")
check(W.offlineMs(10 * H, 0 / 0, true) == 0, "NaN 上次時間＝0")

-- 剩餘時間
local d, h = W.timeLeft(1, 72)
check(d == 3 and h == 0, "滿電 72 小時＝3 天")
d, h = W.timeLeft(0.5, 72)
check(d == 1 and h == 12, "一半＝1 天 12 小時")
d, h = W.timeLeft(0.01, 72)
check(d == 0 and h == 0, "不到 1 小時")

-- ===== 電量讀寫 =====
local watch = F.item(F.RIGHT)
check(W.charge(watch) == 1 and watch.md == nil, "全新的錶（沒有 modData）＝滿電，讀取不建 modData")
W.setCharge(watch, W.NO_BATTERY)
check(W.charge(watch) == nil, "-1＝沒有電池")
watch.md[W.KEY] = "junk"
check(W.charge(watch) == nil, "壞值當作沒有電池")
watch.md[W.KEY] = 1.5
check(W.charge(watch) == 1, "超過 1 夾回 1")
check(W.isWatch(watch) and not W.isWatch(F.item("Base.WristWatch_Right_DigitalBlack")) and not W.isWatch(nil),
    "只認本 MOD 的錶")

-- ===== 閘門決策表 =====
local cases = {
    -- enabled, rule, hasWatch, charge, allowed, reason
    { false, W.RULE_OFF, false, nil, true, nil },
    { true, W.RULE_FREE, false, nil, true, nil },
    { true, W.RULE_OFF, true, 1, false, W.REASON_OFF },
    { true, W.RULE_WATCH, false, nil, false, W.REASON_NO_WATCH },
    { true, W.RULE_WATCH, true, nil, false, W.REASON_NO_BATTERY },
    { true, W.RULE_WATCH, true, 0, false, W.REASON_DEAD },
    { true, W.RULE_WATCH, true, 0.01, true, nil },
}
for i, c in ipairs(cases) do
    local ok, reason = W.minimapDecision(c[1], c[2], c[3], c[4])
    check(ok == c[5] and reason == c[6], "決策表第 " .. i .. " 列")
end
-- 沒電時保留小地圖（DeadMode 2）：沒電、沒電池都放行；沒戴錶、規則關閉照樣擋
check(W.minimapDecision(true, W.RULE_WATCH, true, 0, true) == true
    and W.minimapDecision(true, W.RULE_WATCH, true, nil, true) == true, "沒電時保留小地圖：沒電／沒電池放行")
check(select(2, W.minimapDecision(true, W.RULE_WATCH, false, nil, true)) == W.REASON_NO_WATCH
    and select(2, W.minimapDecision(true, W.RULE_OFF, true, 0, true)) == W.REASON_OFF, "保留小地圖不放行沒戴錶與關閉")
check(W.deadKeepsMinimap() == false, "DeadMode 預設＝所有功能停用")
SandboxVars.MinidoracatWatch.DeadMode = 2
check(W.deadKeepsMinimap() == true, "DeadMode 2＝保留小地圖")
SandboxVars.MinidoracatWatch.DeadMode = nil
SandboxVars.MinidoracatWatch.MinimapRule = 9
check(W.minimapRule() == W.RULE_WATCH, "未知規則值退回 watch")
SandboxVars.MinidoracatWatch.MinimapRule = 2
SandboxVars.MinidoracatWatch.FullHours = 0
check(W.fullHours() == 1, "FullHours 下限 1")
SandboxVars.MinidoracatWatch.FullHours = 72

-- ===== 同時只能戴一支 =====
F.mode = "sp"
local p = F.player("alice", 0)
local a, b = F.item(F.LEFT), F.item(F.RIGHT)
p.inv:AddItem(a)
p.inv:AddItem(b)
check(F.action(ISWearClothing, p, a):isValid() == true, "沒戴錶時可戴第一支")
F.wear(p, a)
check(F.action(ISWearClothing, p, b):isValid() == false, "已戴一支：isValid 擋第二支")
check(#F.halos == 1 and F.halos[1].text == "IGUI_MinidoracatWatch_OneWatchOnly", "被擋時 halo 提示")
check(F.action(ISWearClothing, p, b):complete() == false, "complete（伺服器權威）也擋")
check(#p.worn == 1 and p.worn[1].item == a, "被擋後身上仍只有一支")
check(F.action(ISClothingExtraAction, p, b, F.LEFT):isValid() == false,
    "改戴另一手（ClothingExtra）用在沒戴的第二支也擋")
local swap = F.action(ISClothingExtraAction, p, a, F.RIGHT)
check(swap:isValid() == true and swap:complete() == true, "同一支左右手互換允許")
check(#p.worn == 1 and p.worn[1].item.fullType == F.RIGHT, "互換後戴在右手")
check(F.action(ISWearClothing, p, F.item("Base.WristWatch_Left_DigitalBlack")):isValid() == true,
    "原版手錶不受限制")
-- 存檔裡已戴兩支（舊資料、其他 MOD、直接送 SyncClothing）：生效的是部位順序第一支（左腕）
local q = F.player("bob", 1)
local qa, qb = F.item(F.RIGHT), F.item(F.LEFT)
q.inv:AddItem(qa); q.inv:AddItem(qb)
F.wear(q, qa); F.wear(q, qb)
local eff, n = W.wornWatch(q)
check(eff == qb and n == 2, "兩支都戴時左腕那支生效、回報 2 支")

-- MP 客戶端：伺服器在 complete 裡穿上時就送穿戴同步、之後才送完成，客戶端每幀先問 isValid 才看完成。
-- ClothingExtra 穿上的是新建的物品（右鍵「戴在左手／右手」與換手都走這條），動作開始後不能把它當成另一支
F.mode = "client"
F.halos = {}
local m = F.player("dave", 2)
local mOld = F.item(F.LEFT)
m.inv:AddItem(mOld)
local started = { isStarted = function() return true end }
local function serverWore(action, newType) -- 伺服器的結果到了：舊物移除、新物（新 ID）穿上
    F.unwear(m, action.item)
    m.inv:DoRemoveItem(action.item)
    local new = F.item(newType)
    m.inv:AddItem(new)
    F.wear(m, new)
    return new
end
local wearLeft = F.action(ISClothingExtraAction, m, mOld, F.LEFT)
check(wearLeft:isValid() == true, "MP：右鍵戴在左手，開始前可戴")
wearLeft.action = started
local mWorn = serverWore(wearLeft, F.LEFT)
check(wearLeft:isValid() == true and #F.halos == 0, "MP：伺服器穿上的新錶不算另一支、不跳提示")
local toRight = F.action(ISClothingExtraAction, m, mWorn, F.RIGHT)
check(toRight:isValid() == true, "MP：左手換右手，開始前可換")
toRight.action = started
serverWore(toRight, F.RIGHT)
check(toRight:isValid() == true and #F.halos == 0, "MP：換手後的新錶不算另一支、不跳提示")
local mSecond = F.item(F.LEFT)
m.inv:AddItem(mSecond)
check(F.action(ISClothingExtraAction, m, mSecond, F.LEFT):isValid() == false and #F.halos == 1,
    "MP：開始前照樣擋第二支並提示")

-- ===== 換電池：守恆與反例（伺服器模式）=====
F.mode = "server"
F.reset()
local s = F.player("carol", 0)
local w = F.item(F.RIGHT)
s.inv:AddItem(w)
W.setCharge(w, 0.5)
local bag = F.bag(s.inv)
local bat = F.item("Base.Battery")
bat:setCurrentUsesFloat(0.8)
bag:AddItem(bat)
local batCharge = bat:getCurrentUses() * bat:getUseDelta()
local UD = F.BATTERY_DELTA
local ok = W.applyBatteryChange(s, w:getID(), true, bat:getID())
check(ok == true, "裝入袋子裡的電池成功")
check(near(W.charge(w), batCharge), "錶的電量＝那顆電池的剩餘量")
check(bat.container == nil and F.removed[1] == bat, "電池從袋子移除並送出移除封包")
local back = s.inv:getAllTypeRecurse("Base.Battery")
local backC = back:size() == 1 and back:get(0):getCurrentUsesFloat()
check(backC and backC <= 0.5 and backC > 0.5 - UD, "舊電池還回背包：無條件捨去到整數格（≤ 原電量、少不到一格）")
check(F.added[1] == back:get(0), "還回的電池有送新增封包")
check(#F.synced == 1 and F.synced[1].item == w, "伺服器同步錶的 modData")

F.reset()
local before = W.charge(w)
ok = W.applyBatteryChange(s, w:getID(), false)
check(ok == true and W.charge(w) == nil, "取出電池後錶沒有電池")
local all = s.inv:getAllTypeRecurse("Base.Battery")
local outC = all:size() == 2 and all:get(1):getCurrentUsesFloat()
check(outC and outC <= before + 1e-12 and outC > before - UD, "取出的電池帶原電量（捨去到整數格）")
local r1, r2 = W.applyBatteryChange(s, w:getID(), false)
check(r1 == false and r2 == W.FAIL_NO_BATTERY, "沒電池時取出被拒")

local fresh = F.item(F.LEFT)
s.inv:AddItem(fresh)
F.reset()
check(W.applyBatteryChange(s, fresh:getID(), false) == true and #s.inv:getAllTypeRecurse("Base.Battery")._items == 3,
    "全新錶視為裝著滿電電池，可取出一顆")
check(F.added[1]:getCurrentUses() == 142, "取出的是滿電電池（142 格，與新電池相同）")

-- 反覆拆裝不得生電：0.503 用四捨五入會變成 72 格＝0.504
local function totalCharge(p, watch)
    local t = W.charge(watch) or 0
    local list = p.inv:getAllTypeRecurse("Base.Battery")
    for i = 0, list:size() - 1 do t = t + list:get(i):getCurrentUses() * list:get(i):getUseDelta() end
    return t
end
local loop = F.player("erin", 4)
local lw = F.item(F.RIGHT)
loop.inv:AddItem(lw)
W.setCharge(lw, 0.503)
local start, grew = totalCharge(loop, lw), false
for _ = 1, 30 do
    W.applyBatteryChange(loop, lw:getID(), false)
    if totalCharge(loop, lw) > start + 1e-12 then grew = true end
    local b = loop.inv:getAllTypeRecurse("Base.Battery"):get(0)
    W.applyBatteryChange(loop, lw:getID(), true, b:getID())
    if totalCharge(loop, lw) > start + 1e-12 then grew = true end
end
check(not grew, "反覆拆裝 30 次，總電量從未增加")
check(totalCharge(loop, lw) > start - UD, "反覆拆裝最多損失一格（第一次捨去）")
-- 裝入 143 格的電池（setCurrentUsesFloat(1) 四捨五入出來的）夾回 1
local over = F.item("Base.Battery")
over:setCurrentUsesFloat(1)
loop.inv:AddItem(over)
W.applyBatteryChange(loop, lw:getID(), true, over:getID())
check(over.uses == 143 and W.charge(lw) == 1, "超過 1 的電池裝入後夾回 1")

-- 反例：每一條都不得動到任何物品
local function untouched(label, ...)
    F.reset()
    local snapshot = W.charge(w)
    local n0 = #s.inv.items
    local res, reason = W.applyBatteryChange(...)
    check(res == false and reason ~= nil and W.charge(w) == snapshot and #s.inv.items == n0
        and #F.synced == 0 and #F.added == 0 and #F.removed == 0, label)
end
local spare = s.inv:getAllTypeRecurse("Base.Battery"):get(0)
local other = F.player("mallory", 3)
local foreignWatch, foreignBat = F.item(F.RIGHT), F.item("Base.Battery")
other.inv:AddItem(foreignWatch); other.inv:AddItem(foreignBat)
untouched("別人的錶", s, foreignWatch:getID(), true, spare:getID())
untouched("別人的電池", s, w:getID(), true, foreignBat:getID())
untouched("地上的電池（不在任何人背包）", s, w:getID(), true, F.item("Base.Battery"):getID())
untouched("錯誤型別：拿手電筒當電池", s, w:getID(), true, (function()
    -- 手電筒也是 drainable（有 getCurrentUsesFloat），只能靠型別檢查擋
    local t = F.item("Base.HandTorch"); t.useDelta, t.uses = 0.006, 100; s.inv:AddItem(t); return t:getID() end)())
untouched("錯誤型別：watchId 指向電池", s, spare:getID(), true, spare:getID())
untouched("錯誤型別：原版手錶", s, (function()
    local t = F.item("Base.WristWatch_Right_DigitalBlack"); s.inv:AddItem(t); return t:getID() end)(), false)
untouched("非整數 watchId", s, w:getID() + 0.5, true, spare:getID())
untouched("非整數 batteryId", s, w:getID(), true, spare:getID() + 0.25)
untouched("NaN id", s, 0 / 0, true, spare:getID())
untouched("無限大 id", s, w:getID(), true, 1 / 0)
untouched("字串 id", s, tostring(w:getID()), true, spare:getID())
untouched("install 不是布林", s, w:getID(), "yes", spare:getID())
untouched("沒有玩家", nil, w:getID(), true, spare:getID())
s.dead = true
untouched("死掉的玩家", s, w:getID(), true, spare:getID())
s.dead = nil
F.mode = "client"
untouched("MP 客戶端不能直接改", s, w:getID(), true, spare:getID())
F.mode = "server"

-- ===== 結算：伺服器每分鐘扣一次、只扣戴著的那支、只在伺服器同步 =====
F.players = {}
F.reset()
local z = F.player("dave", 0)
local worn, pocket = F.item(F.LEFT), F.item(F.RIGHT)
z.inv:AddItem(worn); z.inv:AddItem(pocket)
F.wear(z, worn)
local function run(ms, step)
    local t = 0
    while t < ms do F.now = F.now + step; t = t + step; W.onTick() end
end
W.onTick() -- 第一次看到玩家：只記錄、不扣
check(W.charge(worn) == 1 and #F.synced == 0, "第一次結算不扣（預設離線不耗電）")
run(60000, 100)
check(#F.synced == 1, "一分鐘同步一次")
check(near(W.charge(worn), 1 - 60000 / (72 * H), 1e-6), "一分鐘扣 1/4320")
check(W.charge(pocket) == 1 and not pocket.md, "沒戴的錶不扣")
F.reset()
run(30000, 100)
check(#F.synced == 0, "不到一分鐘不送同步封包")
F.now = F.now - 3600000 -- 時鐘倒退一小時
run(60000, 100)
local afterBack = W.charge(worn)
check(afterBack > 1 - 3 * 60000 / (72 * H) - 1e-9, "時鐘倒退不會多扣")
local c0 = W.charge(worn)
F.now = F.now + 10 * H -- 系統時鐘往前跳 10 小時
run(61000, 100)
check(c0 - W.charge(worn) < 2 * 66000 / (72 * H), "大跳躍只計 MAX_TICK_MS")
SandboxVars.MinidoracatWatch.Enabled = false
local c1 = W.charge(worn)
run(120000, 100)
check(W.charge(worn) == c1, "總開關關閉時不扣")
SandboxVars.MinidoracatWatch.Enabled = true
W.setCharge(worn, 0.000001)
F.reset()
run(1500, 100) -- 遠小於一分鐘
check(W.charge(worn) == 0, "沒電後停在 0")
check(#F.synced == 1 and F.synced[1].item == worn, "沒電當下同步一次（不等一分鐘：客戶端的無訊號、提示與熄燈同一刻）")
F.reset()
run(120000, 100)
check(#F.synced == 0, "沒電的錶不再同步")

-- 離線耗電（重新看到玩家時補扣）
SandboxVars.MinidoracatWatch.DrainOffline = true
W.setCharge(worn, 1)
F.players = {} -- 下線
run(60000, 1000)
F.now = F.now + 6 * H
F.players = { z } -- 上線
run(60000, 1000)
check(near(W.charge(worn), 1 - (6 * H + 60000) / (72 * H), 0.002), "離線也耗電：補扣離線 6 小時")
SandboxVars.MinidoracatWatch.DrainOffline = false
W.setCharge(worn, 1)
F.players = {}
run(60000, 1000)
F.now = F.now + 6 * H
F.players = { z }
run(60000, 1000)
check(W.charge(worn) > 1 - 3 * 60000 / (72 * H), "預設離線不補扣")

-- 結算間隔內換錶、脫錶：耗電記在當時戴著的那支（誤差 ≤ 一次入帳間隔 1 秒）
local per = 1 / (72 * H)
W.setCharge(worn, 1); W.setCharge(pocket, 1)
F.reset()
run(30000, 100)
F.unwear(z, worn); F.wear(z, pocket)
run(30000, 100)
check(math.abs((1 - W.charge(worn)) / per - 30000) <= 1100, "換錶前 30 秒記在第一支（" .. math.floor((1 - W.charge(worn)) / per) .. " ms）")
check(math.abs((1 - W.charge(pocket)) / per - 30000) <= 1100, "換錶後 30 秒記在第二支")
local syncedOld = false
for _, e in ipairs(F.synced) do if e.item == worn then syncedOld = true end end
check(syncedOld, "換下的錶同步一次最後的電量")
local p0 = W.charge(pocket)
run(30000, 100)
F.unwear(z, pocket)
run(90000, 100)
check(math.abs((p0 - W.charge(pocket)) / per - 30000) <= 1100, "結算前脫錶：戴著的 30 秒照扣、脫下後不扣")

-- 換手與換電池當下立刻入帳（不留 1 秒誤差）：先對齊到剛入帳完，再走 500ms 不觸發入帳
F.wear(z, pocket)
run(3000, 1000)
local function halfSecond()
    run(1000, 1000) -- 這一幀剛好入帳
    W.setCharge(pocket, 71 * F.BATTERY_DELTA + 1e-6)
    F.now = F.now + 500
    W.onTick() -- 有效時間 +500ms，但不到入帳間隔
end
halfSecond()
local swapped = F.action(ISClothingExtraAction, z, pocket, F.RIGHT)
swapped:complete()
local newWatch = W.wornWatch(z)
check(newWatch ~= pocket and W.charge(newWatch) < 71 * F.BATTERY_DELTA, "換手前先把 500ms 的耗電寫進舊錶再複製")
pocket = newWatch
halfSecond()
F.reset()
W.applyBatteryChange(z, pocket:getID(), false)
check(F.added[1] and F.added[1]:getCurrentUses() == 70, "取電池前先入帳：退回 70 格而不是 71 格")
W.setCharge(pocket, 1)

-- 客戶端整表覆蓋玩家 modData 之後重登：離線時間仍以伺服器的紀錄計算
SandboxVars.MinidoracatWatch.DrainOffline = true
run(61000, 1000)
z.md = {} -- 客戶端 transmitModData 用舊表覆蓋（ObjectModDataPacket.java:54-62）
F.players = {}
run(61000, 1000)
F.now = F.now + 6 * H
F.players = { z }
run(2000, 1000)
check(near(W.charge(pocket), 1 - 6 * H / (72 * H), 0.002), "玩家 modData 被覆蓋也照樣補扣離線 6 小時")
check(F.globalModData[W.SEEN_TABLE] and F.globalModData[W.SEEN_TABLE][W.seenKey(z)] == F.now,
    "上次在線時間存在伺服器的全域 ModData")
SandboxVars.MinidoracatWatch.DrainOffline = false
worn = pocket

-- 單機暫停
F.mode = "sp"
F.reset()
W.setCharge(worn, 1)
run(60000, 100)
F.paused = true
run(61000, 100) -- 暫停前尚未結算的那段在這裡入帳
local c2 = W.charge(worn)
check(c2 < 1, "暫停前的時間照扣")
run(600000, 100)
check(W.charge(worn) == c2, "單機暫停時不耗電")
SandboxVars.MinidoracatWatch.DrainPaused = true
run(120000, 100)
check(W.charge(worn) < c2, "允許暫停耗電時照扣")
check(#F.synced == 0, "單機不送同步封包")
F.paused = false
SandboxVars.MinidoracatWatch.DrainPaused = false

-- ===== 充電：車上（引擎發動）、有電的室內；外部供電期間不扣電，只充電 =====
check(W.chargeHours("car") == 6 and W.chargeHours("house") == 12, "預設車上 6、建築 12 小時充滿")
check(near(W.recharge(0, 3 * H, 6), 0.5) and W.recharge(0, 6 * H, 6) == 1, "6 小時的速率：3 小時半滿、6 小時全滿")
check(W.recharge(0.9, 6 * H, 6) == 1, "充過頭夾在 1")
check(W.recharge(nil, H, 6) == nil and W.recharge(0.4, 0, 6) == 0.4 and W.recharge(0.4, -5, 6) == 0.4,
    "沒電池不充、零或負時間不充")
local sbw = SandboxVars.MinidoracatWatch
sbw.CarHours, sbw.HouseHours = 0, 999
check(W.chargeHours("car") == 1 and W.chargeHours("house") == 168, "小時數夾在 1..168")
sbw.CarHours, sbw.HouseHours = 0 / 0, nil
check(W.chargeHours("car") == 1 and W.chargeHours("house") == 12, "NaN 當 1、沒設定用預設")
sbw.CarHours = nil

F.mode, F.paused = "server", false
F.players = {}
run(61000, 1000) -- 前面的玩家掉出去
local cp = F.player("erin", 0)
local cw = F.item(F.LEFT)
cp.inv:AddItem(cw); F.wear(cp, cw)
W.setCharge(cw, 0.5)
run(2000, 1000)
local CAR, HOUSE = 1 / (6 * H), 1 / (12 * H)
local function measure(ms)
    local before = W.charge(cw)
    run(ms, 1000)
    return W.charge(cw) - before
end
local function chargeCmds()
    local out = {}
    for _, c in ipairs(F.serverCmds) do if c.command == W.CMD_CHARGE then out[#out + 1] = c end end
    return out
end

cp.vehicle = F.vehicle(true)
check(measure(60000) < 0 and W.chargeState(cp) == nil, "預設不開放：坐在發動的車上照樣扣電")
sbw.ChargeCar = true
F.reset()
run(1000, 1000) -- 取樣到外部供電（下一段起算）
local cmds = chargeCmds()
check(#cmds == 1 and cmds[1].player == cp and cmds[1].args.to == "erin" and cmds[1].args.kind == "car",
    "開始充電：只送給本人一次（kind=car）")
sbw.FullHours = 1 -- 扣電極快：充電期間若還在扣，數字會差很多
check(near(measure(60000), 60000 * CAR, 1e-9), "車上：一分鐘充 1/360，不扣電（FullHours=1 也一樣）")
check(W.chargeState(cp) == "car", "chargeState＝car")
check(near(W.chargeHoursToFull(cp, cw), (1 - W.charge(cw)) * 6, 1e-9), "大約多久充滿＝剩餘比例 × 6 小時")
check(#chargeCmds() == 1, "充電中狀態沒變就不再送")
sbw.FullHours = nil

cp.vehicle.running = false
F.reset()
run(1000, 1000)
cmds = chargeCmds()
check(#cmds == 1 and cmds[1].args.kind == nil, "熄火：送一次停止（kind=nil）")
check(measure(60000) < 0 and W.chargeState(cp) == nil and W.chargeHoursToFull(cp, cw) == nil, "熄火後停充、照常扣電")
cp.vehicle = nil
check(measure(60000) < 0, "不在車上不充")

-- 充耗同時：同一分鐘裡前 30 秒在車上、後 30 秒下車＝+30 秒充電 −30 秒耗電（誤差一次取樣 1 秒）
cp.vehicle = F.vehicle(true)
run(1000, 1000)
local mixBefore = W.charge(cw)
run(30000, 1000)
cp.vehicle = nil
run(30000, 1000)
local drainPer = 1 / (72 * H)
check(math.abs((W.charge(cw) - mixBefore) - (30000 * CAR - 30000 * drainPer)) <= 1000 * (CAR + drainPer),
    "前 30 秒充、後 30 秒扣，淨值相加")

-- 建築：室內＋（發電機或市電）；不開放、室外、停電都不充；發電機燃料不動
local gen = { fuel = 5 }
cp.square = F.square({}, gen, false)
check(measure(60000) < 0, "建築充電預設不開放")
sbw.ChargeHouse = true
run(1000, 1000)
check(near(measure(60000), 60000 * HOUSE, 1e-9) and W.chargeState(cp) == "house", "發電機供電的室內：12 小時的速率")
check(gen.fuel == 5, "發電機燃料不變")
cp.square = F.square({}, nil, true)
run(1000, 1000)
check(near(measure(60000), 60000 * HOUSE, 1e-9), "市電的室內也充")
cp.square = F.square(nil, gen, true)
run(1000, 1000)
check(measure(60000) < 0 and W.chargeState(cp) == nil, "室外（沒有房間）不充")
cp.square = F.square({}, nil, false)
run(1000, 1000)
check(measure(60000) < 0, "停電（沒市電、沒發電機）不充")
cp.square = F.square({}, { fuel = 0 }, false)
run(1000, 1000)
check(measure(60000) < 0, "發電機沒油＝沒電，不充")
cp.square = F.square({}, gen, false)
cp.vehicle = F.vehicle(true)
run(1000, 1000)
check(W.chargeState(cp) == "car" and near(measure(60000), 60000 * CAR, 1e-9), "兩個條件都成立：車上優先")
cp.vehicle = nil

-- 上限：充到 1 停、充飽立刻同步、之後照樣外部供電不扣電；chargeState 回 nil
W.setCharge(cw, 1 - 2000 * HOUSE)
F.reset()
run(5000, 1000)
check(W.charge(cw) == 1, "充到 1 停")
check(#F.synced == 1 and F.synced[1].item == cw, "充飽當下同步一次（不等一分鐘）")
run(120000, 1000)
check(W.charge(cw) == 1, "滿電時仍由外部供電，不在 1 上下來回")
check(W.chargeState(cp) == nil and W.chargeHoursToFull(cp, cw) == nil, "充飽後不算充電中")

-- 沒電池不充；總開關關閉不充
W.setCharge(cw, W.NO_BATTERY)
run(61000, 1000)
check(W.charge(cw) == nil and W.chargeState(cp) == nil, "沒有電池不充")
W.setCharge(cw, 0)
run(1000, 1000)
check(measure(60000) > 0, "沒電的電池照樣能充")
sbw.Enabled = false
check(measure(60000) == 0, "總開關關閉不充")
sbw.Enabled = true

-- 離線不充（離線也耗電開著時照樣只補扣）
run(1000, 1000)
local offBefore = W.charge(cw)
F.players = {}
run(61000, 1000)
F.now = F.now + 6 * H
F.players = { cp }
run(1000, 1000)
check(W.charge(cw) - offBefore <= 1000 * HOUSE + 1e-12, "離線 6 小時不充")

-- 單機暫停：跟 DrainPaused 同一套（不允許暫停耗電＝暫停期間不充；允許＝照充）
F.mode = "sp"
run(2000, 1000)
F.paused = true
run(2000, 100)
local pausedAt = W.charge(cw)
run(120000, 100)
check(W.charge(cw) == pausedAt, "單機暫停時不充")
sbw.DrainPaused = true
run(60000, 100)
check(W.charge(cw) > pausedAt, "允許暫停耗電時暫停期間也照充")
sbw.DrainPaused, F.paused = false, false
check(W.chargeState(cp) == "house", "單機直接讀本機狀態")

-- MP 客戶端：只信伺服器推的 kind（白名單），依 to 找本機玩家
F.mode = "client"
local other = F.player("frank", 1)
F.fire("OnServerCommand", W.MODULE, W.CMD_CHARGE, { to = "erin", kind = "car" })
check(W.chargeState(cp) == "car" and W.chargeState(other) == nil, "客戶端：收到 car，只套在 erin")
check(near(W.chargeHoursToFull(cp, cw), (1 - W.charge(cw)) * 6, 1e-9), "客戶端也算得出多久充滿")
F.fire("OnServerCommand", W.MODULE, W.CMD_CHARGE, { to = "erin", kind = "bogus" })
check(W.chargeState(cp) == nil, "不認得的 kind 當作沒在充電")
F.fire("OnServerCommand", W.MODULE, W.CMD_CHARGE, { to = "erin", kind = "house" })
F.fire("OnServerCommand", W.MODULE, W.CMD_CHARGE, { to = "erin" })
check(W.chargeState(cp) == nil, "收到 kind=nil 停止")
check(W.chargeState(nil) == nil, "沒有玩家回 nil")
-- 擋「用錶充一般電池」（規劃書 §4 充電，2026-10-06）：取出的電池不超過裝入時的電量，不生電
F.mode = "server"
cp.square, cp.vehicle = nil, nil
sbw.CarHours = 1
run(2000, 1000)
local function insert(c)
    local b = F.item("Base.Battery")
    b:setCurrentUsesFloat(c)
    cp.inv:AddItem(b)
    W.applyBatteryChange(cp, cw:getID(), true, b:getID())
    return b:getCurrentUses() * b:getUseDelta()
end
local function chargeInCar(ms)
    cp.vehicle = F.vehicle(true)
    run(1000, 1000)
    run(ms, 1000)
    cp.vehicle = nil
    run(1000, 1000)
end
local function newest()
    local list = cp.inv:getAllTypeRecurse("Base.Battery")
    return list:get(list:size() - 1):getCurrentUses() * F.BATTERY_DELTA
end
local lowC = insert(0.3)
check(cw.md[W.CAP_KEY] == lowC, "裝入時把電量記在錶的 modData")
chargeInCar(3600000)
check(W.charge(cw) > 0.99, "車上充飽（1 小時速率）")
W.applyBatteryChange(cp, cw:getID(), false)
local outLow = newest()
check(outLow <= lowC + 1e-12 and outLow > lowC - F.BATTERY_DELTA, "充飽後取出：電池只有裝入時的電量（" .. outLow .. "）")
check(cw.md[W.CAP_KEY] == nil, "取出後清掉紀錄")
lowC = insert(0.3)
chargeInCar(1200000)
local mid = W.charge(cw)
insert(0.9)
local swapped = cp.inv:getAllTypeRecurse("Base.Battery")
local back2 = swapped:get(swapped:size() - 1):getCurrentUses() * F.BATTERY_DELTA
check(mid > lowC + 0.2 and back2 <= lowC + 1e-12, "換電池：退回的舊電池也不超過它裝入時的電量")
run(1000, 1000)
local drained = W.charge(cw) -- 沒有充電、照常扣電：取出時就是目前電量
W.applyBatteryChange(cp, cw:getID(), false)
check(newest() <= drained + 1e-12 and newest() > drained - F.BATTERY_DELTA, "扣過電的電池照目前電量退回")
-- 舊資料（沒有紀錄）：第一次充電前補記目前電量
W.setCharge(cw, 0.4)
cw.md[W.CAP_KEY] = nil
chargeInCar(1200000)
check(cw.md[W.CAP_KEY] == 0.4 or (cw.md[W.CAP_KEY] and cw.md[W.CAP_KEY] <= 0.4 and cw.md[W.CAP_KEY] > 0.39),
    "舊資料：充電前補記當時的電量")
W.applyBatteryChange(cp, cw:getID(), false)
check(newest() <= 0.4 + 1e-12, "舊資料充過電再取出：不超過補記的電量")
check(W.returnCharge(F.item(F.LEFT), 1) == 1, "出廠電池（沒有紀錄、沒有 modData）照原電量退回")
sbw.CarHours = nil

-- 需要電池關閉：不扣、不充；閘門與狀態用 W.power＝1（沒電池也一樣）
lowC = insert(0.5)
sbw.NeedBattery = false
check(W.power(cw) == 1 and W.charge(cw) == lowC, "不需要電池：W.power＝1，W.charge 照實")
check(measure(60000) == 0, "不需要電池：不扣電")
cp.vehicle = F.vehicle(true)
run(1000, 1000)
check(measure(60000) == 0 and W.chargeState(cp) == nil, "不需要電池：車上也不充")
cp.vehicle = nil
W.setCharge(cw, W.NO_BATTERY)
check(W.power(cw) == 1, "不需要電池：沒裝電池也算有電")
sbw.NeedBattery = nil
check(W.power(cw) == nil, "需要電池（預設）：沒電池＝nil")

sbw.ChargeCar, sbw.ChargeHouse = nil, nil
F.mode = "sp"

-- ===== Pack Mule 相容：它的「手錶」選項開著才把地圖手錶搬到它的手錶部位 =====
do
    local items = {}
    local savedSM = getScriptManager
    getScriptManager = function()
        return { FindItem = function(_, t)
            if t:find("Luthex_Right", 1, true) then return nil end -- 缺一件腳本也不影響其他
            items[t] = items[t] or { setBodyLocation = function(self, loc) self.loc = loc end }
            return items[t]
        end }
    end
    local LEFT_W, RIGHT_W = { "mule:left_watch" }, { "mule:right_watch" }
    SandboxVars.B42PackMule = { Watch = true }
    check(W.packMuleWatchSlots() == false and next(items) == nil, "沒裝 Pack Mule：不動地圖手錶的部位")
    MuleBodyLocations = { LEFT_WATCH = LEFT_W, RIGHT_WATCH = RIGHT_W }
    SandboxVars.B42PackMule.Watch = false
    check(W.packMuleWatchSlots() == false and next(items) == nil, "Pack Mule 的手錶選項關著：不動")
    SandboxVars.B42PackMule.Watch = true
    check(W.packMuleWatchSlots() == true, "選項開著：搬到 Pack Mule 的手錶部位")
    local ok = true
    for _, s in ipairs(W.STYLES) do
        local l = items["MinidoracatWatch.MapWatch_" .. s .. "_Left"]
        local r = items["MinidoracatWatch.MapWatch_" .. s .. "_Right"]
        ok = ok and l ~= nil and l.loc == LEFT_W and (s == "Luthex" or (r ~= nil and r.loc == RIGHT_W))
    end
    check(ok, "七款的左手款進左手位、右手款進右手位；缺一件腳本不影響其他")
    MuleBodyLocations, SandboxVars.B42PackMule, getScriptManager = nil, nil, savedSM
end

F.finish("test_watch_core")
