-- 地圖錶陣營分享距離（Phase 7，伺服器端）：W.shareAllowed 的規則 × 模組組合 × 距離邊界、範圍取兩人中較大者、
-- 中繼核心不限距離、收件者沒有通訊類模組、分享者沒電、總開關、拆模組後立刻生效（狀態快取失效）、分割畫面各自判斷；
-- server 檔的守衛（主 MOD 沒有／太舊／註冊拋錯 → log 一次、不註冊）與註冊後的過濾函式。
-- 用法（repo 根目錄）：lua scripts/test_watch_share.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check = F.check
F.mode = "server"
require "MinidoracatWatch"
local W = MinidoracatWatchCore
local SB = SandboxVars.MinidoracatWatch
SB.SlotAdv, SB.SlotCore = 1, 1 -- 進階與核心槽免費開放（長距通訊、中繼核心裝得上）

-- 戴著一支錶的玩家；mods＝{ [slotId] = 模組 id }；charge nil＝全新滿電
local function person(name, pn, mods, x, y, charge)
    local p = F.player(name, pn)
    local w = F.item(F.RIGHT)
    p.inv:AddItem(w)
    F.wear(p, w)
    local slots = {}
    for slotId, id in pairs(mods or {}) do slots[slotId] = { id = id, item = W.modules[id].item } end
    w:getModData()[W.SLOTS_KEY] = slots
    if charge then W.setCharge(w, charge) end
    p.x, p.y = x or 0, y or 0
    W.invalidate()
    return p, w
end
local function at(p, x, y) p.x, p.y = x, y end
local allowed = W.shareAllowed

local COMM, LONG, RELAY = { std1 = "comm" }, { adv = "longcomm" }, { core = "relay" }

-- ===== 需要模組（預設）：通訊 × 通訊，距離邊界（預設 2000 格）=====
local a = person("a", 0, COMM, 10000, 10000)
local b = person("b", 0, COMM, 12000, 10000)
check(W.shareRange(a) == 2000 and W.shareRange(b) == 2000, "通訊模組：範圍＝沙盒預設 2000")
check(allowed(a, b) == true, "通訊 × 通訊：剛好 2000 格收得到")
at(b, 12001, 10000)
check(allowed(a, b) == false, "通訊 × 通訊：超出 1 格收不到")
at(b, 10000 + 1200, 10000 + 1600)
check(allowed(a, b) == true, "斜向 (1200,1600)＝2000 格：收得到（歐氏距離）")
at(b, 10000 + 1201, 10000 + 1600)
check(allowed(a, b) == false, "斜向 (1201,1600)：超出")
at(b, 10000 - 2000, 10000)
check(allowed(b, a) == true and allowed(a, b) == true, "反方向、對調分享者與收件者結果相同")

-- ===== 範圍取兩人中較大者 =====
local l = person("l", 0, LONG, 10000, 10000 + 8000)
check(W.shareRange(l) == 8000, "長距通訊：範圍＝沙盒預設 8000")
check(allowed(a, l) == true and allowed(l, a) == true, "通訊 × 長距通訊：8000 格（任一方是長距）收得到")
at(l, 10000, 10000 + 8001)
check(allowed(a, l) == false and allowed(l, a) == false, "通訊 × 長距通訊：8001 格收不到")
local both = person("both", 0, { std1 = "comm", adv = "longcomm" }, 10000, 10000 + 8000)
check(W.shareRange(both) == 8000 and allowed(a, both) == true, "同一支錶裝通訊＋長距：取較大的 8000")

-- ===== 中繼核心：任一方就不限距離 =====
local r = person("r", 0, RELAY, 10000 + 500000, 10000)
check(W.shareRange(r) == W.RANGE_UNLIMITED, "中繼核心：不限距離")
check(allowed(a, r) == true and allowed(r, a) == true, "中繼核心在收件者或分享者身上：50 萬格也收得到")

-- ===== 收件者沒有通訊類模組 =====
local none = person("none", 0, { std1 = "compass" }, 10000, 10000)
check(W.shareRange(none) == nil and allowed(a, none) == false and allowed(r, none) == false,
    "收件者沒有通訊類模組：同一格、對方有中繼核心也收不到")
local bare = F.player("bare", 0)
bare.x, bare.y = 10000, 10000
check(allowed(a, bare) == false and allowed(bare, a) == false, "沒戴錶：送不出也收不到")

-- ===== 分享者沒電、沒電池 =====
local dead = person("dead", 0, RELAY, 10000, 10000, 0)
check(W.shareRange(dead) == nil and allowed(dead, a) == false, "分享者的錶沒電（中繼核心也一樣）：不轉送")
local nobat = person("nobat", 0, COMM, 10000, 10000, W.NO_BATTERY)
check(allowed(nobat, a) == false and allowed(a, nobat) == false, "沒電池：送不出也收不到")

-- ===== 模組在沒開啟的槽位（paused）=====
SB.SlotExt = 2 -- 解鎖卡、還沒用
local paused = person("paused", 0, { ext = "comm" }, 10000, 10000)
check(MinidoracatWatchAPI.getWatchModuleState(paused, "comm") == "paused" and allowed(a, paused) == false,
    "通訊模組在沒開啟的擴充槽（paused）：收不到")
SB.SlotExt = nil

-- ===== 沙盒範圍：讀管理員設定、壞值退回預設 =====
SB.CommRange = 50
at(b, 10050, 10000)
W.invalidate()
check(allowed(a, b) == true, "CommRange=50：50 格收得到")
at(b, 10051, 10000)
check(allowed(a, b) == false, "CommRange=50：51 格收不到")
for _, bad in ipairs({ 0, -5, 0 / 0, "abc" }) do
    SB.CommRange = bad
    check(W.shareRange(a) == 2000, "CommRange 壞值（" .. tostring(bad) .. "）退回 2000")
end
SB.CommRange = nil
SB.LongCommRange = 30000
check(W.shareRange(l) == 30000, "LongCommRange 讀沙盒")
SB.LongCommRange = nil

-- ===== 拆下通訊模組：狀態快取立刻失效 =====
local c, cw = person("c", 0, COMM, 10010, 10000)
c.inv:AddItem(F.item("Base.Screwdriver"))
check(allowed(a, c) == true, "拆之前收得到")
check(W.applyModuleChange(c, cw:getID(), "std1", false) == true, "伺服器拆下收件者的通訊模組")
check(allowed(a, c) == false, "拆下後（同一秒內）立刻收不到：applyModuleChange 讓快取失效")

-- ===== 功能規則與總開關 =====
local far = person("far", 0, nil, 10000 + 500000, 10000) -- 戴著有電的錶、沒有模組、很遠
SB.RuleShare = 1
check(allowed(bare, bare) == true and allowed(none, far) == true, "不需要錶：一律放行")
SB.RuleShare = 2
check(allowed(none, far) == true, "戴錶就能用：兩人戴著有電的錶，不限距離、不看模組")
check(allowed(dead, far) == false and allowed(far, dead) == false, "戴錶就能用：任一方沒電就不轉")
check(allowed(bare, far) == false and allowed(far, bare) == false, "戴錶就能用：任一方沒戴錶就不轉")
SB.RuleShare = 4
check(allowed(r, r) == false and allowed(a, b) == false, "關閉：誰都不轉（中繼核心也一樣）")
SB.Enabled = false
check(allowed(bare, bare) == true and allowed(dead, far) == true, "總開關關：不限制（功能規則的關閉也不生效）")
SB.Enabled, SB.RuleShare = nil, nil
check(allowed(a, nil) == false and allowed(nil, a) == false, "缺玩家：不轉")

-- ===== 分割畫面：同一連線的多位玩家各自判斷 =====
local s0 = person("split1", 0, COMM, 10020, 10000)
local s1 = person("split2", 1, nil, 10020, 10000)
check(allowed(a, s0) == true and allowed(a, s1) == false, "同機兩位玩家：有通訊模組的收得到、沒有的收不到")
check(allowed(s1, a) == false and allowed(s0, a) == true, "同機兩位玩家當分享者也各自判斷")

-- ===== server 檔的守衛與註冊 =====
local function loadServer() F.reset(); F.load("server/MinidoracatWatch_Server.lua") end
local function guardLogs()
    local n = 0
    for _, s in ipairs(F.logs) do if s:find("shareApiVersion >= 1 not found", 1, true) then n = n + 1 end end
    return n
end
MinidoracatMiniMapServerAPI = nil
loadServer()
check(W.shareFilterActive == false and guardLogs() == 1, "主 MOD 沒有伺服器 API：不註冊、log 一次")
local oldCalled = false
MinidoracatMiniMapServerAPI = { shareApiVersion = 0, registerShareFilter = function() oldCalled = true; return true end }
loadServer()
check(not oldCalled and W.shareFilterActive == false and guardLogs() == 1, "主 MOD 太舊（shareApiVersion 0）：不呼叫、log 一次")
MinidoracatMiniMapServerAPI = { shareApiVersion = 1 }
loadServer()
check(W.shareFilterActive == false and guardLogs() == 1, "有版本欄位但沒有 registerShareFilter：不註冊、log 一次")
MinidoracatMiniMapServerAPI = { shareApiVersion = 1, registerShareFilter = function() error("boom") end }
loadServer()
check(W.shareFilterActive == false and guardLogs() == 1, "註冊拋錯：不 crash、log 一次")
MinidoracatMiniMapServerAPI = { shareApiVersion = 1, registerShareFilter = function() return false end }
loadServer()
check(W.shareFilterActive == false and guardLogs() == 1, "註冊回 false：當作沒生效、log 一次")
local reg = {}
MinidoracatMiniMapServerAPI = { shareApiVersion = 2, registerShareFilter = function(owner, fn)
    reg.owner, reg.fn = owner, fn; return true end }
loadServer()
check(W.shareFilterActive == true and guardLogs() == 0 and reg.owner == W.MOD_ID and reg.fn == W.shareAllowed,
    "shareApiVersion >= 1：以 Mod ID 註冊 W.shareAllowed、不 log")
-- 主 MOD 照 (sender, recipient, x, y) 呼叫、只看「明確 false」
at(b, 10000 + 2000, 10000)
check(reg.fn(a, b, 1, 2) == true and reg.fn(a, none, 1, 2) == false, "主 MOD 的呼叫形式：範圍內 true、沒模組明確 false")

F.finish("test_watch_share")
