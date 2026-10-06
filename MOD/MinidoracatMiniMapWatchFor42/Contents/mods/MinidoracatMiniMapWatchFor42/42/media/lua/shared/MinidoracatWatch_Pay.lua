-- MinidoracatWatch_Pay.lua（shared）：Economy 付費槽位（Phase 6）兩端共用的部分——產品命名、權益判讀、槽位有效。
-- 伺服器端（註冊、方案、權益快取、推播）在 server/MinidoracatWatch_Economy.lua；客戶端付款在
-- client/MinidoracatWatch_PayClient.lua。shared 依檔名順序在核心與 Modules 之後載入；這裡不 require 別的檔。
-- 規格：主 MOD docs/plan-minimap-watch-economy.md（Economy 選用整合，不 require=）。
local W = MinidoracatWatchCore

W.ECON_SOURCE = W.MOD_ID -- Economy 來源 id＝mod id（車輛管理同慣例）
W.CMD_PAY = "pay"
W.CMD_PAY_REQ = "payReq"
W.CMD_PLAN_WARN = "planWarn"
-- 伺服器：開服偵測的 Economy 整合狀態（OFF／ABSENT／UNSUPPORTED／FAILED／READY）；MP 客戶端：伺服器推來的。
-- nil＝沒有偵測（單機、客戶端還沒收到）。不是 READY 時「經濟系統」的槽位改用解鎖卡（W.slotMode）。
W.econStatus = nil
W.clientPay = {} -- MP 客戶端：[username] = { [slotId] = true }（伺服器判定有效的 Economy 槽位）

-- ===== 產品命名 =====
-- 標準三槽是常數；第三方槽位 w_＋槽位 id（符合 Economy 產品 id 規則 ^[a-z0-9_]{1,32}$ 時），否則 w_＋8 位十六進位雜湊
-- （不做字元替換，免得兩個 id 撞成同一個）。純函式：重啟、兩端都算得出同一個；撞名由伺服器註冊時擋。
local STD_PRODUCT = { ext = "watch_ext", adv = "watch_adv", core = "watch_core" }
local HEX = "0123456789abcdef"
local function hash8(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end -- djb2；Kahlua 的 byte 是 UTF-16 碼元，仍 < 2^53
    local out = ""
    for _ = 1, 8 do
        local d = h % 16
        out = HEX:sub(d + 1, d + 1) .. out
        h = math.floor(h / 16)
    end
    return out
end
function W.productOf(slotId)
    local std = STD_PRODUCT[slotId]
    if std then return std end
    if #slotId <= 26 and slotId:match("^[a-z0-9_]+$") then return "w_" .. slotId end
    return "w_" .. hash8(slotId)
end

-- ===== 權益判讀 =====
-- 一份 Economy 權益（snapshot.entitlement）在 now 時這個槽位有沒有效：回 有效, 有效到（ms；買斷＝W.PAY_FOREVER）。
-- 形狀不對回 nil（讀取失敗，呼叫端決定怎麼處理）。
-- 使用者裁定「租約到期立刻停用」：只認買斷，或 state 是 active／paused_terms／paused_system 而且 paidUntil 還沒到的租約；
-- grace（寬限＝自動續租重試時間）、expired、frozen（產品缺席，槽位本來就孤立）一律無效。
-- 不用 entitlement.usable：它把寬限算成可用（Economy leaseLive）。paused_*：已付期間仍屬玩家（停售／系統暫停不是到期）。
W.PAY_FOREVER = 1e300
local LIVE = { active = true, paused_terms = true, paused_system = true }
function W.payEval(ent, now)
    if type(ent) ~= "table" or type(ent.rentals) ~= "table" then return nil end
    if type(ent.permanent) == "number" and ent.permanent >= 1 then return true, W.PAY_FOREVER end
    local best = nil
    for _, r in ipairs(ent.rentals) do
        if type(r) == "table" and LIVE[r.state] and type(r.paidUntil) == "number" and r.paidUntil > now
            and (best == nil or r.paidUntil > best) then
            best = r.paidUntil
        end
    end
    if best then return true, best end
    return false, nil
end

-- 「經濟系統」開啟方式的槽位有沒有效（W.slotValid 在 mode＝econ 時呼叫）。MP 客戶端讀伺服器推來的結果，
-- 伺服器讀 Economy 權益快取（W.Econ.valid）；兩端都沒有＝無效。
function W.payValid(player, slot)
    if isClient() then
        local t = W.clientPay[player:getUsername()]
        return t ~= nil and t[slot.id] == true
    end
    local E = W.Econ
    return E ~= nil and E.valid(player, slot) == true
end
