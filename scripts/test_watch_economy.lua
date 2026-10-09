-- 地圖錶 Phase 6：Economy 付費槽位。伺服器（守衛退回解鎖卡、產品命名與註冊、凍結旗標、舊版 Economy 缺席產品關閉、
-- 沙盒 → setPlan、狀態對應、到期立刻停用、自動續租到期等 Economy 試扣、讀取失敗、變更通知、validatePurchase、推播、重登、分割畫面）與客戶端
-- （推播、付款流程：報價比對、價格剛變更、沒回應只查原訂單、重複付款、餘額不足、自動續租同意、檢視區文字與按鈕）。
-- 用法（repo 根目錄）：lua scripts/test_watch_economy.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check = F.check
F.mode = "server"

require "MinidoracatWatch"
require "MinidoracatWatch_Pay"
local W = MinidoracatWatchCore
local SB = SandboxVars.MinidoracatWatch
local HOUR = 3600000

-- 第三方槽位（shared 檔載入時登記）：一個合規 id、一個要雜湊的 id
MinidoracatWatchAPI.registerWatchSlot({ id = "acme_slot", name = "IGUI_Acme_Slot", accepts = { "standard" },
    price = { rent = 1, days = 1, buy = 1 } })
MinidoracatWatchAPI.registerWatchSlot({ id = "AcmeBig", name = "IGUI_Acme_Big", accepts = { "standard" },
    price = { rent = 1, days = 1, buy = 1 } })
require "MinidoracatWatch_Economy"
local Econ = W.Econ

-- ===== 產品命名 =====
check(W.productOf("ext") == "watch_ext" and W.productOf("adv") == "watch_adv" and W.productOf("core") == "watch_core",
    "標準三槽是常數產品")
check(W.productOf("acme_slot") == "w_acme_slot", "第三方合規 id：w_＋id")
local h1, h2 = W.productOf("AcmeBig"), W.productOf("Acmebig")
check(h1:match("^w_%x%x%x%x%x%x%x%x$") ~= nil and h1 ~= h2 and h1 == W.productOf("AcmeBig"),
    "大寫 id 改用 8 位雜湊、穩定、不和只差大小寫的撞名")
check(W.productOf(string.rep("a", 27)):match("^w_%x+$") ~= nil and #W.productOf(string.rep("a", 27)) == 10,
    "太長的 id 也雜湊（產品 id ≤ 32）")

-- ===== 狀態對應（W.payEval）=====
local NOW = F.now
local function rental(state, untilMs, extra)
    local r = { id = "o1", quantity = 1, state = state, paidUntil = untilMs, graceUntil = untilMs and untilMs + HOUR,
        autoRenew = false, autoRenewState = "off" }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end
local function ent(perm, rentals) return { permanent = perm or 0, rentals = rentals or {}, revision = 1 } end
for _, s in ipairs({ "active", "paused_terms", "paused_system" }) do
    check(W.payEval(ent(0, { rental(s, NOW + HOUR) }), NOW) == true, s .. "：有效")
end
for _, s in ipairs({ "grace", "expired", "frozen", "pending" }) do
    check(W.payEval(ent(0, { rental(s, NOW + HOUR) }), NOW) == false, s .. "：無效（寬限＝停用）")
end
check(W.payEval(ent(0, { rental("active", NOW) }), NOW) == false, "paidUntil 到了即使 state 還是 active 也無效")
local v1, u1 = W.payEval(ent(1, { rental("grace", NOW - 1) }), NOW)
check(v1 == true and u1 == W.PAY_FOREVER, "買斷永久有效（和租約並存也算）")
check(W.payEval({ permanent = 0 }, NOW) == nil and W.payEval(nil, NOW) == nil, "缺 rentals／不是表：讀取失敗（nil）")
local _, best = W.payEval(ent(0, { rental("active", NOW + HOUR), rental("paused_terms", NOW + 2 * HOUR) }), NOW)
check(best == NOW + 2 * HOUR, "有效到期取最晚的一張")
-- 等續租：自動續租 on 的租約剛到期、Economy 還沒試扣 → 最多 W.PAY_RENEW_WAIT_MS 仍有效；試扣失敗、超過等候、沒開自動續租都無效
local AUTO = { autoRenew = true, autoRenewState = "on" }
local vw, uw = W.payEval(ent(0, { rental("grace", NOW - 700, AUTO) }), NOW)
check(vw == true and uw == NOW - 700 + W.PAY_RENEW_WAIT_MS, "自動續租剛到期、還沒試扣：有效到 paidUntil＋等候上限")
local failedEnt = ent(0, { rental("grace", NOW - 700, AUTO) })
failedEnt.notice = { code = "renewal_failed", error = "insufficient_funds", rental = "o1" }
check(W.payEval(failedEnt, NOW) == false, "Economy 已試扣失敗（renewal_failed）：立刻無效")
failedEnt.notice.rental = "other"
check(W.payEval(failedEnt, NOW) == true, "別張租約的 renewal_failed 不算這張試扣過")
check(W.payEval(ent(0, { rental("grace", NOW - W.PAY_RENEW_WAIT_MS, AUTO) }), NOW) == false, "等候上限到了 Economy 仍沒扣：無效")
check(W.payEval(ent(0, { rental("grace", NOW - 1, { autoRenew = true, autoRenewState = "paused_terms" }) }), NOW) == false,
    "自動續租暫停（不會扣）：到期立刻無效")

-- ===== 假 Economy（server facade）=====
local E = { products = {}, plans = {}, setPlans = {}, ents = {}, listeners = {}, notReady = false }
local function fakeEconomy(rev, caps)
    E.products, E.plans, E.setPlans, E.listeners = {}, {}, {}, {}
    local src = {}
    function src.registerProduct(spec)
        if E.failProduct and E.failProduct == spec.id then return { ok = false, error = "invalid_args", field = "id" } end
        E.products[spec.id] = spec
        return { ok = true }
    end
    function src.setPlan(pid, values, opts)
        if E.notReady then return { ok = false, error = "not_ready" } end
        if not E.products[pid] then return { ok = false, error = "unknown_product" } end
        local n = 0
        for _ in pairs(values) do n = n + 1 end
        if n ~= 12 then return { ok = false, error = "invalid_plan" } end
        E.setPlans[#E.setPlans + 1] = { pid = pid, values = values, opts = opts }
        local old, changed = E.plans[pid], {}
        for k, v in pairs(values) do if not old or old[k] ~= v then changed[#changed + 1] = k end end
        E.plans[pid] = values
        return { ok = true, updated = #changed > 0, changed = changed, revision = #E.setPlans }
    end
    function src.getEntitlement(name, pid)
        E.reads = (E.reads or 0) + 1
        if E.readError then return { ok = false, error = "not_ready" } end
        local e = E.ents[name] and E.ents[name][pid]
        return { ok = true, entitlement = e or ent(0, {}), plan = E.plans[pid] }
    end
    function src.onEntitlementChanged(fn) E.listeners[#E.listeners + 1] = fn; return { ok = true } end
    function src.getPlan(pid) return { ok = true, lastChange = { origin = E.plans[pid] and "source" or "defaults" } } end
    MinidoracatEconomy = { CURRENCIES = { survivor = {}, cat = {} }, v1 = { API_MAJOR = 1, API_REVISION = rev,
        CAPABILITIES = caps, registerSource = function(spec) E.source = spec; return src end } }
end
local CAPS4 = { entitlements = true, rentals = true, setPlan = true, freeze = true }

-- ===== 守衛：沒有 Economy／版本不足／註冊失敗 → 經濟系統的槽位改用解鎖卡 =====
local ext = W.slotById.ext
MinidoracatEconomy = nil
Econ.init()
check(Econ.status == "ABSENT" and W.slotMode(ext) == "card", "沒裝 Economy：ABSENT、擴充槽（經濟系統）改用解鎖卡")
fakeEconomy(1, { entitlements = true, rentals = true, setPlan = true })
Econ.init()
check(Econ.status == "UNSUPPORTED" and W.slotMode(ext) == "card", "API rev 1：UNSUPPORTED、改用解鎖卡")
fakeEconomy(2, { entitlements = true, rentals = true })
Econ.init()
check(Econ.status == "UNSUPPORTED", "缺 setPlan 能力：UNSUPPORTED")
fakeEconomy(4, CAPS4)
E.failProduct = "watch_adv"
F.reset()
Econ.init()
check(Econ.status == "FAILED" and W.slotMode(ext) == "card", "標準產品註冊失敗：FAILED、改用解鎖卡")
E.failProduct = nil
F.mode = "sp"
Econ.init()
check(Econ.status == "OFF" and W.slotMode(ext) == "card", "單機：OFF、經濟系統視同解鎖卡")
F.mode = "server"

-- 解鎖卡在經濟系統退回解鎖卡時照樣能用；READY 後同一張卡的紀錄不算數（兩種方式不疊加）
local alice = F.player("alice", 0)
F.globalModData[W.UNLOCK_TABLE] = { alice = { n = { ext = true } } }
check(W.slotValid(alice, ext) == true, "退回解鎖卡：用過卡的帳號有效")

-- ===== READY：註冊、凍結旗標、setPlan =====
fakeEconomy(4, CAPS4)
F.reset()
Econ.init()
check(Econ.status == "READY" and W.econStatus == "READY" and W.slotMode(ext) == "econ", "rev 4：READY、擴充槽走經濟系統")
local spurious = false
for _, l in ipairs(F.logs) do if l:find("rental price, currency or days changed", 1, true) then spurious = true end end
check(not spurious, "世界第一次從 defaults 換成沙盒價格：不當成改價（不 log、不提醒）")
check(E.source.modId == "MinidoracatMiniMapWatchFor42" and #E.source.reasonCodes == 3, "來源＝mod id、三個必備原因碼")
check(E.products.watch_ext and E.products.watch_adv and E.products.watch_core and E.products.w_acme_slot
    and E.products[h1] ~= nil, "標準三槽與兩個第三方槽位都有產品")
check(E.products.watch_ext.instant == true and E.products.watch_ext.freezeWhenAbsent == nil
    and E.products.w_acme_slot.freezeWhenAbsent == true, "全部 instant；只有第三方帶 freezeWhenAbsent")
check(E.products.w_acme_slot.nameKey == "IGUI_Acme_Slot", "第三方產品名用槽位自己的翻譯鍵")
check(F.globalModData[Econ.KNOWN].w_acme_slot == "acme_slot", "看過的第三方產品記在全域 ModData")
check(W.slotValid(alice, ext) == false, "READY 後解鎖卡紀錄不讓經濟系統槽位有效（不疊加）")

local function planOf(pid)
    for i = #E.setPlans, 1, -1 do if E.setPlans[i].pid == pid then return E.setPlans[i].values, E.setPlans[i].opts end end
end
local pe, opts = planOf("watch_ext")
check(pe and pe.permanentEnabled == true and pe.permanentPrice == 400 and pe.rentalPrice == 60 and pe.rentalDays == 7
    and pe.rentalLimit == 1 and pe.permanentLimit == 1 and pe.graceHours == 24 and pe.autoRenewAllowed == true
    and pe.permanentCurrency == "survivor", "擴充槽方案：12 欄、設計稿價格、上限 1、重試 24 小時")
check(opts.origin == "source" and opts.actor == "watch" and opts.expectedRevision == nil, "setPlan 不帶 expectedRevision（沙盒唯一來源）")
local pa = planOf("w_acme_slot")
check(pa.permanentEnabled == false and pa.rentalEnabled == false and pa.autoRenewAllowed == false,
    "第三方槽位預設免費開放：Economy 方案全關")

local n0 = #E.setPlans
F.now = F.now + 6000
Econ.tick()
check(#E.setPlans == n0, "沙盒沒變：不重送")
SB.SlotExtBuyPrice, SB.PayRetryHours, SB.SlotExtRentPrice = 0, 0, 999
SB.PayCurrency = 2
F.now = F.now + 6000
F.reset()
Econ.tick()
pe = planOf("watch_ext")
check(pe.permanentPrice == 1 and pe.graceHours == 0 and pe.rentalPrice == 999 and pe.rentalCurrency == "cat",
    "沙盒改了 5 秒內重送：價格至少 1、重試 0 小時、幣別貓幣")
local warned = false
for _, c in ipairs(F.serverCmds) do
    if c.command == W.CMD_PLAN_WARN and c.broadcast and c.args.slot == "ext" then warned = true end
end
check(warned, "執行中改租金／幣別：提醒在線管理員（自動續租要重新同意）")
SB.SlotExtBuyPrice, SB.PayRetryHours, SB.SlotExtRentPrice, SB.PayCurrency = nil, nil, nil, nil
SB.SlotAdv = 2
E.notReady = true
F.now = F.now + 6000
local n1 = #E.setPlans
Econ.tick()
check(#E.setPlans == n1, "not_ready：沒送成")
E.notReady = false
F.now = F.now + 6000
Econ.tick()
local padv = planOf("watch_adv")
check(#E.setPlans > n1 and padv.permanentEnabled == false and padv.rentalEnabled == false and padv.autoRenewAllowed == false,
    "not_ready 下一輪重試；進階槽改成解鎖卡：販售與自動續租全關")
check(W.slotMode(W.slotById.adv) == "card", "進階槽改解鎖卡後用卡")
SB.SlotAdv = nil
F.now = F.now + 6000
Econ.tick()

-- ===== 有效判定：買斷、租約、到期立刻停用、通知、讀取失敗 =====
E.ents.alice = { watch_ext = ent(0, { rental("active", F.now + 10000) }) }
Econ.init() -- 清快取
F.now = F.now + 1000
check(W.slotValid(alice, ext) == true, "租用中：有效")
F.reset()
Econ.tick()
local pushed = nil
for _, c in ipairs(F.serverCmds) do if c.command == W.CMD_PAY and c.player == alice then pushed = c.args end end
check(pushed and pushed.to == "alice" and pushed.econ == "READY" and pushed.slots.ext == true and pushed.slots.adv == nil,
    "第一次看到玩家：推 pay（本人、READY、有效槽位）")
F.reset()
F.now = F.now + 1000
Econ.tick()
check(#F.serverCmds == 0, "沒變：不重推")
-- 到期：Economy 的排程還沒通知（快照仍寫 active），1 秒內停用
F.now = F.now + 9000
check(W.slotValid(alice, ext) == false, "paidUntil 到了：不等 Economy 通知就無效")
F.reset()
Econ.tick()
pushed = nil
for _, c in ipairs(F.serverCmds) do if c.command == W.CMD_PAY and c.player == alice then pushed = c.args end end
check(pushed and pushed.slots.ext == nil, "到期當秒推播：擴充槽不在有效清單")
-- 自動續租（重現 mmw-econ-mp-1009rc 首輪的順序）：到期後地圖錶每秒的輪詢先讀到 grace，Economy 那一步才扣款
local function notify(e)
    E.ents.alice.watch_ext = e
    for _, fn in ipairs(E.listeners) do fn("alice", "watch_ext", { ok = true, entitlement = e }) end
end
local function autoLease(untilMs, state, notice)
    local e = ent(0, { rental(state, untilMs, AUTO) })
    e.notice = notice
    return e
end
local function pushedExt() -- 下一秒的 tick：沒推＝nil，推了回擴充槽有沒有效
    F.reset()
    F.now = F.now + 1000
    Econ.tick()
    local got = nil
    for _, c in ipairs(F.serverCmds) do if c.command == W.CMD_PAY and c.player == alice then got = c.args.slots.ext == true end end
    return got
end
local RENEWED = { code = "renewed", rental = "o1" }
local due = F.now + 1500
notify(autoLease(due, "active", RENEWED))
check(pushedExt() == true, "自動續租開著、租用中：推有效")
E.ents.alice.watch_ext = autoLease(due, "grace", RENEWED) -- 過了 paidUntil，Economy 還沒走到這一列
check(pushedExt() == nil and W.slotValid(alice, ext) == true, "到期後 Economy 還沒試扣：不推停用（玩家不會先看到到期）")
notify(autoLease(due, "grace", { code = "grace", rental = "o1" })) -- Economy 那一步：先發 grace 通知，同一步再試扣
notify(autoLease(due + 7 * 24 * HOUR, "active", RENEWED))
check(W.slotValid(alice, ext) == true and pushedExt() == nil, "續租扣到款：從頭到尾沒推過停用")
-- 扣不到款：Economy 同一步發 renewal_failed → 立刻停用，下一秒推播（到期／扣款失敗的 Toast 照報）
due = F.now + 500
notify(autoLease(due, "active", RENEWED))
E.ents.alice.watch_ext = autoLease(due, "grace", RENEWED)
check(pushedExt() == nil and W.slotValid(alice, ext) == true, "扣款前（已過 paidUntil）：同樣先等 Economy")
notify(autoLease(due, "grace", { code = "grace", rental = "o1" }))
check(W.slotValid(alice, ext) == true, "grace 通知（還沒試扣）：仍有效")
notify(autoLease(due, "grace", { code = "renewal_failed", error = "insufficient_funds", rental = "o1" }))
check(W.slotValid(alice, ext) == false and pushedExt() == false, "續租扣款失敗（寬限中）：立刻停用並推播")
-- Economy 一直沒走到這一列：等候上限一到就停用
due = F.now + 5000
notify(autoLease(due, "active", RENEWED))
check(pushedExt() == true, "新一期：推有效")
E.ents.alice.watch_ext = autoLease(due, "grace", RENEWED)
F.now = due + W.PAY_RENEW_WAIT_MS - 1500
check(pushedExt() == nil, "等候上限內：仍有效")
check(pushedExt() == false, "等候上限到了 Economy 仍沒扣：停用並推播")
-- 讀取失敗：沿用上次有效值到它的到期時間；沒有舊值＝無效
E.ents.alice.watch_core = ent(0, { rental("active", F.now + 5000) })
for _, fn in ipairs(E.listeners) do fn("alice", "watch_core", { ok = true, entitlement = E.ents.alice.watch_core }) end
check(W.slotValid(alice, W.slotById.core) == true, "核心槽租用中")
E.readError = true
F.now = F.now + 4000
for _, fn in ipairs(E.listeners) do fn("alice", "watch_core", { ok = false, error = "journal" }) end
check(W.slotValid(alice, W.slotById.core) == true, "讀取失敗：沿用上次有效值")
F.now = F.now + 2000
check(W.slotValid(alice, W.slotById.core) == false, "讀取失敗也不超過原本的到期時間")
local bob = F.player("bob", 0)
check(W.slotValid(bob, W.slotById.core) == false, "讀取失敗又沒有舊值：無效")
E.readError = false
-- 買斷
E.ents.bob = { watch_core = ent(1, {}) }
F.now = F.now + Econ.RETRY_MS
check(W.slotValid(bob, W.slotById.core) == true, "買斷：有效")
-- 分割畫面副座位：沒有帳號
local seat2 = F.player("bob", 1)
check(W.slotValid(seat2, W.slotById.core) == false, "分割畫面副座位：無權益")

-- 模組狀態：有效槽位 active、到期 paused（不耗電、可拆）
local watch = F.item(F.LEFT)
bob.inv:AddItem(watch)
F.wear(bob, watch)
watch:getModData()[W.KEY] = 1
watch:getModData()[W.SLOTS_KEY] = { core = { id = "relay", item = "MinidoracatWatch.Module_Relay" } }
W.invalidate()
check(W.moduleState(bob, "relay") == "active", "買斷的核心槽：中繼核心 active")
E.ents.bob.watch_core = ent(0, { rental("expired", F.now - 1) })
for _, fn in ipairs(E.listeners) do fn("bob", "watch_core", { ok = true, entitlement = E.ents.bob.watch_core }) end
check(W.moduleState(bob, "relay") == "paused" and W.drainFactor(bob, watch) == 1, "租約到期：paused、不耗電")
SB.NeedScrewdriver = false
local ok = W.applyModuleChange(bob, watch:getID(), "core", false, nil)
SB.NeedScrewdriver = nil
check(ok == true and watch:getModData()[W.SLOTS_KEY].core == nil, "到期的槽位：模組照樣拆得下來")

-- 重登：新的 IsoPlayer 物件 → 重推；payReq 清掉簽名 → 下一秒重推
F.reset()
F.now = F.now + 1000
Econ.tick()
local alice2 = F.player("alice", 0)
F.reset()
F.now = F.now + 1000
Econ.tick()
local got = 0
for _, c in ipairs(F.serverCmds) do if c.command == W.CMD_PAY and c.player == alice2 then got = got + 1 end end
check(got == 1, "重登（新的玩家物件）：重推一次")
F.fire("OnClientCommand", W.MODULE, W.CMD_PAY_REQ, alice2, {})
F.reset()
F.now = F.now + 1000
Econ.tick()
got = 0
for _, c in ipairs(F.serverCmds) do if c.command == W.CMD_PAY and c.player == alice2 then got = got + 1 end end
check(got == 1, "payReq：下一秒重推")

-- ===== validatePurchase（D5）=====
check(select(2, Econ.validatePurchase("alice", "nope", "permanent", 1, {})) == "UNKNOWN_SLOT", "不認得的產品：UNKNOWN_SLOT")
SB.SlotExt = 2
check(select(2, Econ.validatePurchase("alice", "watch_ext", "rental", 1, { permanent = 0 })) == "MODE_NOT_ECONOMY",
    "開啟方式不是經濟系統：MODE_NOT_ECONOMY")
SB.SlotExt = nil
check(select(2, Econ.validatePurchase("bob", "watch_ext", "rental", 1, { permanent = 1 })) == "HAVE_PERMANENT",
    "已買斷不能租")
E.ents.alice.watch_ext = ent(0, { rental("active", F.now + HOUR, { autoRenew = true, autoRenewState = "on" }) })
check(select(2, Econ.validatePurchase("alice", "watch_ext", "permanent", 1, { permanent = 1 })) == "RENTING_AUTO_ON",
    "租約開著自動續租時不能買斷")
E.ents.alice.watch_ext = ent(0, { rental("active", F.now + HOUR) })
check(Econ.validatePurchase("alice", "watch_ext", "permanent", 1, { permanent = 1 }) == true, "租用中（自動續租關）可以買斷")
check(Econ.validatePurchase("carol", "watch_ext", "rental", 1, { permanent = 0 }) == true, "新租約：可以")
E.readError = true
check(select(2, Econ.validatePurchase("alice", "watch_ext", "permanent", 1, {})) == "READ_FAILED", "讀不到權益：不賣買斷")
E.readError = false
-- 也接受解鎖卡：用卡開過就拒絕任何付款（含自動續租）；選項關掉時卡的紀錄不擋付款
F.globalModData[W.UNLOCK_TABLE] = F.globalModData[W.UNLOCK_TABLE] or {}
F.globalModData[W.UNLOCK_TABLE].dave = { s123 = { ext = true } }
check(Econ.validatePurchase("dave", "watch_ext", "rental", 1, { permanent = 0 }) == true,
    "沒開「也接受解鎖卡」：舊的卡紀錄不擋付款")
SB.SlotExtCard = true
check(select(2, Econ.validatePurchase("dave", "watch_ext", "rental", 1, { permanent = 0 })) == "CARD_UNLOCKED",
    "也接受解鎖卡、已用卡開啟：拒絕付款（CARD_UNLOCKED）")
check(Econ.validatePurchase("carol", "watch_ext", "rental", 1, { permanent = 0 }) == true, "沒用過卡的人照常付款")
SB.SlotExtCard = nil
F.globalModData[W.UNLOCK_TABLE].dave = nil

-- ===== 第三方槽位的 MOD 被移除 =====
-- rev 4：缺席的產品不註冊（Economy 凍結租約）；舊版：照樣註冊、方案全關
-- 等於這次啟動沒人登記：從登記表拿掉（之後放回）
local acmeSlot = W.slotById.acme_slot
W.slotById.acme_slot = nil
for i, s in ipairs(W.slotList) do if s == acmeSlot then table.remove(W.slotList, i) break end end
fakeEconomy(4, CAPS4)
Econ.init()
check(E.products.w_acme_slot == nil, "rev 4：缺席的第三方產品不註冊（Economy 凍結、不扣租金）")
fakeEconomy(3, { entitlements = true, rentals = true, setPlan = true })
Econ.init()
local pab = planOf("w_acme_slot")
check(E.products.w_acme_slot ~= nil and E.products.w_acme_slot.freezeWhenAbsent == nil and pab
    and pab.autoRenewAllowed == false and pab.rentalEnabled == false and pab.permanentEnabled == false,
    "舊版 Economy：缺席的第三方產品註冊並關掉自動續租與販售")
check(select(2, Econ.validatePurchase("alice", "w_acme_slot", "rental", 1, {})) == "UNKNOWN_SLOT", "缺席的產品不賣")
check(W.slotValid(alice, W.orphanSlot("acme_slot")) == false, "孤立槽位一律無效")
-- 撞名：另一個槽位算出同一個產品 → 後來的不賣
F.globalModData[Econ.KNOWN].w_acme_slot = "other"
W.slotById.acme_slot = acmeSlot
table.insert(W.slotList, 7, acmeSlot)
fakeEconomy(4, CAPS4)
F.reset()
Econ.init()
local collided = false
for _, l in ipairs(F.logs) do if l:find("already slot other", 1, true) then collided = true end end
check(E.products.w_acme_slot == nil and collided, "產品 id 撞名：後來的槽位不賣、log")
F.globalModData[Econ.KNOWN].w_acme_slot = "acme_slot"
Econ.init()

-- ===== 客戶端 =====
F.mode = "client"
W.econStatus = nil
require "MinidoracatWatch_Client"
require "MinidoracatWatch_PayClient"
local C = MinidoracatWatchClient
local P = C.Pay
local me = F.players[1] -- alice（座位 0）
F.fire("OnServerCommand", W.MODULE, W.CMD_PAY, { to = "alice", econ = "READY", slots = { ext = true, bogus = 1 } })
check(W.econStatus == "READY" and W.slotValid(me, ext) == true and W.clientPay.alice.bogus == nil,
    "客戶端：推播的有效槽位與 Economy 狀態；非 true 的值丟掉")
check(W.slotValid(me, W.slotById.core) == false, "客戶端：沒推的槽位無效")
F.reset()
F.fire("OnTick")
local req = 0
for _, c in ipairs(F.clientCmds) do if c.command == W.CMD_PAY_REQ then req = req + 1 end end
check(req >= 1, "客戶端第一個 tick 補要一次 payReq")

-- 沒有 Economy 客戶端 facade
MinidoracatEconomy = nil
P.views = {}
local ui = P.ui(me, nil, ext)
check(ui and ui.lines[1][1] == "IGUI_MinidoracatWatch_PayNoClient", "客戶端沒有 Economy：說明不能付款")

-- 假客戶端 facade
local CE = { states = {}, sent = {}, rid = 0 }
local function env(pid, e, plan, bal)
    plan = plan or { permanentEnabled = true, permanentPrice = 400, permanentCurrency = "survivor", rentalEnabled = true,
        rentalPrice = 60, rentalCurrency = "survivor", rentalDays = 7, graceHours = 24, autoRenewAllowed = true, revision = 5 }
    return { ok = true, productId = pid, plan = plan, entitlement = e, available = true,
        balances = { survivor = { available = bal or 1000 } } }
end
local function send(kind, args)
    CE.rid = CE.rid + 1
    CE.sent[#CE.sent + 1] = { kind = kind, args = args }
    if CE.refuse then return nil, CE.refuse end
    return CE.rid
end
MinidoracatEconomy = { v1 = { Client = { API_MAJOR = 1, API_REVISION = 3,
    CAPABILITIES = { entitlements = true, rentals = true, freeze = true }, Entitlements = {
    getState = function(src, pid) return CE.states[pid] end,
    requestState = function(src, pid) return send("state", { pid = pid }) end,
    quote = function(src, pid, kind, q, cb, rental) CE.cb = cb; return send("quote", { pid = pid, kind = kind, q = q, rental = rental }) end,
    purchase = function(src, quoteId, cb) CE.cb = cb; return send("purchase", { quoteId = quoteId }) end,
    getOrder = function(src, pid, orderId, cb) CE.cb = cb; return send("order", { pid = pid, orderId = orderId }) end,
    setAutoRenew = function(src, pid, en, rev, terms, cb, rental)
        CE.cb = cb; return send("auto", { pid = pid, enabled = en, rev = rev, terms = terms, rental = rental }) end,
    errorText = function(code) return "err:" .. tostring(code) end,
    currencyName = function(id) return "cur:" .. id end,
    orderOutcome = function(r) return (r.order and r.order.status == "paid") and "paid" or "unknown" end,
} } } }
local function lastSent(kind)
    for i = #CE.sent, 1, -1 do if CE.sent[i].kind == kind then return CE.sent[i].args end end
end
local function count(kind)
    local n = 0
    for _, s in ipairs(CE.sent) do if s.kind == kind then n = n + 1 end end
    return n
end
local function btn(u, id)
    for _, b in ipairs(u.buttons) do if b[1] == id then return b end end
end
local function hasLine(u, key)
    for _, l in ipairs(u.lines) do if l[1]:find(key, 1, true) then return true end end
    return false
end
local function fresh() P.views = {}; F.now = F.now + 1 end

-- 還沒讀到：讀取中、要一次狀態
fresh()
ui = P.ui(me, nil, ext)
check(hasLine(ui, "PayLoading") and lastSent("state").pid == "watch_ext", "還沒有權益：讀取中並 requestState")

-- 沒買過：租用／買斷
W.clientPay.alice = {}
CE.states.watch_ext = env("watch_ext", ent(0, {}))
fresh()
ui = P.ui(me, nil, ext)
check(btn(ui, "rent") and btn(ui, "rent")[2]:find("PayBtnRent|7|", 1, true) and btn(ui, "buy")[3] == true
    and hasLine(ui, "PayAccountBound"), "未開啟：租用 7 天、買斷、綁帳號說明")
CE.states.watch_ext.plan.permanentEnabled = false
fresh()
ui = P.ui(me, nil, ext)
check(btn(ui, "buy")[3] == false and hasLine(ui, "PayNoBuy"), "沒開放買斷：按鈕停用並說明")
CE.states.watch_ext.plan.permanentEnabled = true

-- 付款：報價金額相同才付
P.press("buy", me, ext)
fresh()
ui = P.ui(me, nil, ext)
check(P.sheet and P.sheet.kind == "permanent" and hasLine(ui, "PaySheetAmount|IGUI_MinidoracatWatch_Money|400")
    and btn(ui, "pay")[3] == true,
    "買斷確認頁：金額 400、可付款")
P.press("pay", me, ext)
check(lastSent("quote").kind == "permanent" and lastSent("quote").q == 1 and P.busy.watch_ext == "quote", "付款先報價")
fresh()
check(btn(P.ui(me, nil, ext), "pay")[3] == false, "報價中：付款鈕停用（防連點）")
-- 價格剛變更：報價金額不同 → 不付款、提示
CE.cb({ ok = true, quote = { id = "q1", orderId = "q1", amount = 450, currency = "survivor", termsRevision = 6 } })
check(count("purchase") == 0 and P.sheet.notice == true, "報價和確認頁不同（價格剛變更）：不付款")
fresh()
check(hasLine(P.ui(me, nil, ext), "PayPriceChanged"), "確認頁提示價格剛變更")
-- 伺服器沒回應（付款）：鎖住、只查原訂單
P.press("pay", me, ext)
CE.cb({ ok = true, quote = { id = "q2", orderId = "q2", amount = 400, currency = "survivor", termsRevision = 5 } })
check(count("purchase") == 1 and lastSent("purchase").quoteId == "q2", "報價相同：用同一張報價付款")
CE.cb({ ok = false, error = "timeout", unknown = true })
fresh()
ui = P.ui(me, nil, ext)
check(P.orders.watch_ext and hasLine(ui, "PayNoAnswer") and btn(ui, "check") and not btn(ui, "buy"),
    "付款逾時：結果未知，只剩「查詢購買結果」")
P.press("buy", me, ext)
check(P.sheet == nil and count("quote") == 2, "結果未知時不能再開確認頁、不會再報價")
P.press("check", me, ext)
check(lastSent("order").orderId == "q2" and count("purchase") == 1, "查詢只讀原 orderId，不重送購買")
CE.cb({ ok = true, unknown = true })
check(P.orders.watch_ext ~= nil, "查詢也沒回應：仍鎖住")
P.press("check", me, ext)
CE.cb({ ok = true, known = true, order = { orderId = "q2", status = "paid" }, instant = true })
check(P.orders.watch_ext == nil and P.msg.watch_ext[1]:find("PayPaidDone", 1, true), "查回已付款：解鎖、說付款完成")
-- 重複付款：伺服器回 duplicate
P.press("buy", me, ext)
P.press("pay", me, ext)
CE.cb({ ok = true, quote = { id = "q3", orderId = "q3", amount = 400, currency = "survivor", termsRevision = 5 } })
CE.cb({ ok = true, duplicate = true })
check(P.msg.watch_ext[1]:find("PayDuplicate", 1, true) and P.sheet == nil, "duplicate：說明沒有重複扣款")
-- 餘額不足：確認頁停用付款；伺服器拒絕時顯示 Economy 的錯誤文字
CE.states.watch_ext = env("watch_ext", ent(0, {}), nil, 30)
P.press("rent", me, ext)
fresh()
ui = P.ui(me, nil, ext)
check(btn(ui, "pay")[3] == false and hasLine(ui, "PaySheetShort|IGUI_MinidoracatWatch_Money|30"),
    "餘額不足：付款鈕停用、說還差多少")
CE.states.watch_ext = env("watch_ext", ent(0, {}))
P.press("sheetAuto", me, ext)
P.press("pay", me, ext)
CE.cb({ ok = false, error = "insufficient_funds" })
check(P.msg.watch_ext[1] == "err:insufficient_funds" and count("purchase") == 2, "伺服器說餘額不足：顯示原因、沒付款")
-- 新租約勾自動續租：付款後替這張租約（id＝訂單 id）送同意，條款＝報價的版本
P.press("pay", me, ext)
CE.cb({ ok = true, quote = { id = "q4", orderId = "q4", amount = 60, currency = "survivor", termsRevision = 5 } })
CE.cb({ ok = true, orderId = "q4", snapshot = { entitlement = { revision = 9 }, plan = { revision = 5 } } })
local a = lastSent("auto")
check(a and a.enabled == true and a.rental == "q4" and a.terms == 5 and a.rev == 9, "新租約付款後送自動續租同意（訂單 id、報價條款）")
CE.cb({ ok = true })
check(P.msg.watch_ext[1]:find("PayPaidDone", 1, true) and not P.busy.watch_ext, "同意完成：說付款完成")
-- 本機拒絕（facade 回 nil, pending）
CE.refuse = "pending"
P.press("buy", me, ext)
P.press("pay", me, ext)
check(P.msg.watch_ext[1] == "err:pending" and not P.busy.watch_ext, "facade 本機拒絕：顯示原因、解除處理中")
CE.refuse = nil
P.press("cancel", me, ext)
check(P.sheet == nil, "取消：關確認頁")

-- 租用中（有效）：剩餘、自動續租、續租、D5 買斷停用
W.clientPay.alice = { ext = true }
local live = rental("active", F.now + 3 * 24 * HOUR + 6 * HOUR, { autoRenew = true, autoRenewState = "on",
    autoTerms = { price = 60, currency = "survivor", days = 7 } })
CE.states.watch_ext = env("watch_ext", ent(0, { live }))
fresh()
ui = P.ui(me, nil, ext)
check(ui.chip == "rent" and hasLine(ui, "PayRenting|IGUI_MinidoracatWatch_PayDaysHours|3|6") and hasLine(ui, "PayAutoOn")
    and btn(ui, "renew") and btn(ui, "autoOff") and btn(ui, "buy")[3] == false and hasLine(ui, "PayBuyAutoOn")
    and btn(ui, "install"), "租用中：剩 3 天 6 小時、自動續租開、續租、買斷要先關自動續租、空槽可安裝")
P.press("autoOff", me, ext)
a = lastSent("auto")
check(a.enabled == false and a.rental == "o1", "關閉自動續租直接送")
CE.cb({ ok = true })
-- D3：改了租金 → 需要重新同意
CE.states.watch_ext.plan.rentalPrice = 80
fresh()
ui = P.ui(me, nil, ext)
check(hasLine(ui, "PayNeedConsent") and btn(ui, "agree"), "租金改了：顯示「需重新同意」與同意鈕")
P.press("agree", me, ext)
P.press("pay", me, ext)
a = lastSent("auto")
check(a.enabled == true and a.terms == 5 and a.rental == "o1", "同意新條款：以目前方案版本送同意")
CE.cb({ ok = true })
CE.states.watch_ext.plan.rentalPrice = 60

-- 到期、自動續租重試中（餘額不足）：停用、說還差多少與重試期限
W.clientPay.alice = {}
local watch2 = F.item(F.LEFT)
watch2:getModData()[W.SLOTS_KEY] = { ext = { id = "scan", item = "MinidoracatWatch.Module_Scan" } }
CE.states.watch_ext = env("watch_ext", { permanent = 0, revision = 3, rentals = { rental("grace", F.now - 1000,
    { autoRenew = true, autoRenewState = "on", graceUntil = F.now + 18 * HOUR,
        autoTerms = { price = 60, currency = "survivor", days = 7 } }) },
    notice = { code = "renewal_failed", error = "insufficient_funds", rental = "o1" } }, nil, 40)
fresh()
ui = P.ui(me, watch2, ext)
check(ui.chip == "paused" and hasLine(ui, "PayLapsedModule") and hasLine(ui, "PayFailFunds|cur:survivor|20")
    and hasLine(ui, "PayRetryWindow|IGUI_MinidoracatWatch_PayHours|18") and btn(ui, "renew") and btn(ui, "remove"),
    "重試中：模組停用、還差 20、18 小時內每小時重試、可續租、可拆")
check((P.bannerText(me, watch2) or ""):find("BannerRetry", 1, true) ~= nil, "橫幅：租約到期、自動續租重試中")
-- 到期而且空槽：lapsed
CE.states.watch_ext = env("watch_ext", ent(0, { rental("expired", F.now - HOUR) }))
fresh()
ui = P.ui(me, nil, ext)
check(P.lapsed(ext) and ui.chip == "lapsed" and hasLine(ui, "PayLapsed") and btn(ui, "renew")
    and btn(ui, "renew")[2]:find("PayBtnRenew|7|", 1, true), "租約到期的空槽：lapsed、續租（含價格）")
-- 也接受解鎖卡：沒開的槽位多一顆「使用解鎖卡」（沒卡＝停用）；用卡開過＝有效、不再顯示付費
SB.SlotExtCard = true
ui = P.ui(me, nil, ext)
check(hasLine(ui, "PayCardAlso") and btn(ui, "card") and btn(ui, "card")[3] == false and btn(ui, "renew"),
    "也接受解鎖卡：續租之外可以用卡（背包沒卡＝停用）")
local extCard = F.item("MinidoracatWatch.UnlockCard_Ext")
me.inv:AddItem(extCard)
check(btn(P.ui(me, nil, ext), "card")[3] == true, "背包有卡：使用解鎖卡可按")
W.clientUnlocks.alice = { ext = true }
ui = P.ui(me, nil, ext)
check(W.slotValid(me, ext) and ui.chip == "active" and hasLine(ui, "Desc_CardOpened") and btn(ui, "install")
    and not btn(ui, "renew") and not btn(ui, "card"), "用卡開過：有效、說明綁帳號、可安裝、沒有付費按鈕")
W.clientUnlocks.alice, SB.SlotExtCard = nil, nil
me.inv:DoRemoveItem(extCard)
-- 凍結：孤立槽位顯示剩餘時間停在凍結時
CE.states.w_gone = env("w_gone", ent(0, { rental("frozen", F.now + 2 * HOUR) }))
fresh()
ui = P.ui(me, nil, W.orphanSlot("gone"))
check(ui and hasLine(ui, "PayFrozen|IGUI_MinidoracatWatch_PayHours|2"), "第三方 MOD 被移除：租約凍結、剩 2 小時")
-- Economy 不是 READY：經濟系統改用解鎖卡並說明
F.fire("OnServerCommand", W.MODULE, W.CMD_PAY, { to = "alice", econ = "ABSENT", slots = {} })
fresh()
ui = P.ui(me, nil, ext)
check(W.slotMode(ext) == "card" and ui.keep == true and hasLine(ui, "PayNoEcon"), "伺服器沒有經濟系統：解鎖卡＋說明")

-- 管理員改價提醒
F.admin = true
HaloTextHelper = { addBadText = function(p, t) F.halos[#F.halos + 1] = { player = p, text = t } end }
F.reset()
F.fire("OnServerCommand", W.MODULE, W.CMD_PLAN_WARN, { slot = "ext" })
check(#F.halos == 1 and F.halos[1].text:find("PlanTermsChanged", 1, true), "管理員收到改價提醒")
F.admin = false

F.finish("test_watch_economy")
