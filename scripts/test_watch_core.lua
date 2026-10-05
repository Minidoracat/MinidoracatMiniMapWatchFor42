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
local batCharge = bat:getCurrentUsesFloat()
local ok = W.applyBatteryChange(s, w:getID(), true, bat:getID())
check(ok == true, "裝入袋子裡的電池成功")
check(near(W.charge(w), batCharge), "錶的電量＝那顆電池的剩餘量")
check(bat.container == nil and F.removed[1] == bat, "電池從袋子移除並送出移除封包")
local back = s.inv:getAllTypeRecurse("Base.Battery")
check(back:size() == 1 and near(back:get(0):getCurrentUsesFloat(), 0.5, 0.0035), "舊電池帶 50% 還回背包（誤差 ≤ 半格）")
check(F.added[1] == back:get(0), "還回的電池有送新增封包")
check(#F.synced == 1 and F.synced[1].item == w, "伺服器同步錶的 modData")

F.reset()
local before = W.charge(w)
ok = W.applyBatteryChange(s, w:getID(), false)
check(ok == true and W.charge(w) == nil, "取出電池後錶沒有電池")
local all = s.inv:getAllTypeRecurse("Base.Battery")
check(all:size() == 2 and near(all:get(1):getCurrentUsesFloat(), before, 0.0035), "取出的電池帶原電量")
local r1, r2 = W.applyBatteryChange(s, w:getID(), false)
check(r1 == false and r2 == W.FAIL_NO_BATTERY, "沒電池時取出被拒")

local fresh = F.item(F.LEFT)
s.inv:AddItem(fresh)
F.reset()
check(W.applyBatteryChange(s, fresh:getID(), false) == true and #s.inv:getAllTypeRecurse("Base.Battery")._items == 3,
    "全新錶視為裝著滿電電池，可取出一顆")
check(near(F.added[1]:getCurrentUsesFloat(), 1, 0.0035), "取出的是滿電電池")

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
check(#F.synced == 0, "不到一分鐘不寫 modData")
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
W.setCharge(worn, 0.00001)
run(120000, 100)
check(W.charge(worn) == 0, "沒電後停在 0")
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

F.finish("test_watch_core")
