-- MinidoracatWatch_Cores.lua（shared）：負重核心的負重上限加成、節能核心的耐力加成（2026-10-14 使用者裁定，規劃書 §0
-- 「負重核心」「節能核心」）。伺服器與單機每秒在扣電迴圈（MinidoracatWatch.lua 的 visit）呼叫；MP 客戶端只看引擎同步來的數值。
--
-- 負重：引擎沒有每人的減重欄位，改提高負重基數 maxWeightBase（預設 8；BodyDamage.UpdateStrength 每次更新重算
--   maxWeight＝int(基數×力量係數)×特質倍率，BodyDamage.java:2066-2072）。基數不入存檔（wp-mp-1013a：重開回到 8），
--   客戶端不重算、由 PlayerDamagePacket 每 2 秒同步（NetworkPlayerManager.java:9），改了下一秒 sendDamage 立刻推。
--   一格＝原版基數的八分之一。只加減自己那一份：別的 MOD 改了基數，照樣只扣回自己加過的格數（用加減寫法的 MOD
--   兩邊都保留、不會越疊越多；直接寫固定值的 MOD 以它的值為準，那段期間我們的格數算在它的值裡面）。
-- 耐力：只在伺服器與單機算（IsoPlayer.calculateStats、updateEndurance 都排除 GameClient.client，IsoPlayer.java:3047、
--   3218），每秒以 PlayerStatsPacket 整份送到客戶端（NetworkPlayerManager.java:10），客戶端自己改會被蓋回。引擎沒有
--   每人的耐力倍率，所以每秒看上一秒的變化：掉了退回 EcoEnduranceDrain%，回升多給 EcoEnduranceRegen%
--   （實測 en-*-1014a～c：比例照設定，MP 客戶端看到的數字只往一個方向走）。
--   ponytail: 每秒一次，單機每秒有一次小跳（衝刺約 0.004）；有人回報喘氣圖示閃動再改成每幀。
local W = MinidoracatWatchCore

W.WEIGHT_UNIT_PCT = 12.5 -- 一格＝原版基數 8 的八分之一

local function intIn(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    return math.max(lo, math.min(hi, math.floor(v)))
end

function W.weightEnabled() return W.sandbox("WeightEnabled", true) ~= false end
-- 每一階的格數（預設 1／2／3）與一支錶的上限（預設 8 格＝+100%）
function W.weightUnits(tier) return intIn(W.sandbox("WeightUnits" .. tier, tier), 0, 8, tier) end
function W.weightCap() return intIn(W.sandbox("WeightCap", 8), 0, 16, 8) end
-- 一支錶最多幾格：負重槽一階一格、只收同一階（第三方不能登記負重核心），所以是 I＋II＋III，再夾在上限。
-- 第二個值＝上限卡得到嗎：三階加起來超過上限才卡得到（預設 1＋2＋3＝6，碰不到 8）；卡不到時玩家面板不寫上限
function W.weightMax()
    local sum, cap = W.weightUnits(1) + W.weightUnits(2) + W.weightUnits(3), W.weightCap()
    return math.min(sum, cap), sum > cap
end

-- 這位玩家現在的加成格數：戴著、有電的錶上，裝在有效負重槽的核心加總，夾在上限（W.status 有 1 秒快取、不配置）
function W.weightBonus(player)
    if not (W.enabled() and W.weightEnabled()) then return 0 end
    local e = W.status(player)
    local c = e.watch and W.power(e.watch)
    if not (c and c > 0) then return 0 end
    local units = 0
    for i = 1, e.n do
        local def = W.modules[e.ids[i]]
        local tier = def and W.WEIGHT_CLASSES[def.class]
        if tier and e.states[i] == "active" then units = units + W.weightUnits(tier) end
    end
    return math.min(units, W.weightCap())
end

-- 每秒：格數變了就把基數加減差額（只動自己那一份），沒變不寫。s＝這位玩家的扣電狀態（只在記憶體：重登、重生都從
-- 原版的 8 重新加）。不在偵測到別人改過時把現值當原值：用加減寫法的 MOD 每改一次就會多疊一次我們的格數
function W.weightCheck(player, s)
    local units = W.weightBonus(player)
    local had = s.wtUnits or 0
    if had == units then return end
    player:setMaxWeightBase(player:getMaxWeightBase() - had + units)
    s.wtUnits = units > 0 and units or nil
    s.wtPush = true
end

-- 上一秒改了基數：這時引擎已經重算過 maxWeight，伺服器立刻推給本人（不推也會在 2 秒內同步）
function W.weightPush(player, s)
    if not s.wtPush then return end
    s.wtPush = nil
    if isServer() then sendDamage(player) end -- LuaManager.java:4320-4326
end

-- 節能核心的耐力加成（%；0＝關）
function W.ecoEnduranceDrain() return intIn(W.sandbox("EcoEnduranceDrain", 25), 0, 100, 25) end
function W.ecoEnduranceRegen() return intIn(W.sandbox("EcoEnduranceRegen", 30), 0, 300, 30) end

-- 每秒：節能核心運作中（戴著、有電、核心槽有效）時，上一秒掉的耐力退回 drain%、回升的多給 regen%。
-- 吃東西、睡醒的回升也算恢復；Stats.set 夾在 0..1。s.endurance 只在記憶體
function W.enduranceCheck(player, s)
    local stats = player:getStats()
    local now = stats:get(CharacterStat.ENDURANCE)
    local prev = s.endurance
    if prev and W.moduleState(player, "eco") == "active" then
        local d = now - prev
        local pct = 0
        if d < 0 then pct = W.ecoEnduranceDrain() elseif d > 0 then pct = W.ecoEnduranceRegen() end
        if pct > 0 then
            stats:set(CharacterStat.ENDURANCE, now + math.abs(d) * pct / 100)
            now = stats:get(CharacterStat.ENDURANCE)
        end
    end
    s.endurance = now
end
