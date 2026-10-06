-- MinidoracatWatch_Admin.lua：管理員設定視窗的伺服器端（Phase 4；伺服器／單機）。
-- 使用者裁定（規劃書 §0「管理」）：數值存沙盒、清單存伺服器設定檔。本檔管清單那一半與權限、版本、審計：
--   - 設定檔區段 moduleDrains（第三方模組耗電）與 addonSlots（第三方槽位逐槽設定），讀取端在 shared W.listValue。
--   - 管理員視窗的讀取（adminGet → adminState）與寫回（adminSet → adminResult）：
--     權限＝原版沙盒介面同一個（W.isSettingsAdmin，伺服器這裡再查一次，不信客戶端）；
--     版本＝Cfg.revision（設定檔內容換了就 +1，含手改檔與視窗寫回），請求帶 expected，不同就拒絕（兩位管理員同時改，
--     後送出的不會蓋掉先送出的；照車輛管理 PaidSlots 管理員 SET 的 expectedRevision）；
--     清單逐區段驗證（Cfg.save：任一區段不合格整筆不動），寫檔讀回比對成功才換值；
--     每次套用都要原因，連同「原本 → 改成」寫進同資料夾的 admin-audit.log 與 console。
--   - 沙盒數值由客戶端在 adminResult 成功之後自己送（SandboxOptions:sendToServer；伺服器 Java 端只收有
--     SandboxOptions 權限的連線，PacketTypes.java:421、:301-311；收到後 toLua、存 <伺服器名>_SandboxVars.lua、
--     廣播給所有連線，GameServer.java:1710-1726）。沙盒這一半也算一次套用：版本照樣 +1，另一位管理員的舊畫面會被擋。
--   - 清單變了（任何原因）就廣播給所有客戶端（W.CMD_LISTS）；客戶端第一個 tick 補要一次（W.CMD_LISTS_REQ）。
-- 單機：客戶端直接呼叫 A.state／A.apply（同一個 Lua 狀態），不發指令、不推送。
-- MP 客戶端也會載入 media/lua/server（GameLoadingState.java:148），所以先以 isClient() 早退。
if isClient() then return end
require "MinidoracatWatch"
require "MinidoracatWatch_Config"
require "MinidoracatWatch_Drops" -- zombieDrops 先登記：設定檔裡區段照 zombieDrops、moduleDrains、addonSlots 排
local W = MinidoracatWatchCore
local Cfg = W.Config
local A = {}
W.Admin = A

A.CMD_GET = W.CMD_ADMIN_GET
A.CMD_STATE = W.CMD_ADMIN_STATE
A.CMD_SET = W.CMD_ADMIN_SET
A.CMD_RESULT = W.CMD_ADMIN_RESULT
A.AUDIT_FILE = "admin-audit.log"
A.MAX_ENTRIES = 64     -- moduleDrains／addonSlots 各自最多幾筆
A.MAX_CHANGES = 300    -- 一次套用最多記幾行變更
A.MAX_TEXT = 400       -- 原因與每行變更的長度上限

-- ===== 設定檔區段 =====
-- 物件區段：本檔寫出的空物件是 []（Cfg.encode 把空表當陣列），所以空陣列也收
local function objectOf(raw)
    if type(raw) ~= "table" or raw == Cfg.NULL then return nil end
    if Cfg.isArray(raw) and #raw > 0 then return nil end
    return raw
end
local function intIn(v, lo, hi) return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi end

-- moduleDrains：{ [第三方模組 id] = 0..1000 的整數 % }。內建模組的耗電在沙盒，不收；沒登記的 id 照收
-- （提供模組的 MOD 暫時被移除時設定不消失）。
function A.parseDrains(raw)
    local t = objectOf(raw)
    if not t then return nil, { "must be an object of module id -> drain percent" } end
    local out, problems, n = {}, {}, 0
    for id, v in pairs(t) do
        n = n + 1
        if not W.validId(id) then
            problems[#problems + 1] = "bad module id " .. tostring(id)
        elseif W.BUILTIN[id] then
            problems[#problems + 1] = id .. " is built in: its drain is a sandbox option"
        elseif not intIn(v, 0, 1000) then
            problems[#problems + 1] = id .. ": drain must be a whole number from 0 to 1000"
        else
            out[id] = v
        end
    end
    if n > A.MAX_ENTRIES then problems[#problems + 1] = "more than " .. A.MAX_ENTRIES .. " modules" end
    if #problems > 0 then return nil, problems end
    return out
end

-- addonSlots：{ [第三方槽位 id] = { mode = free|card|econ|off, buy?, buyPrice?, rent?, rentPrice?, card? } }；
-- 沒寫的欄位照沙盒 SlotAddon*（card＝經濟系統也接受解鎖卡）。內建槽位不收。
local SLOT_KEYS = { mode = true, buy = true, buyPrice = true, rent = true, rentPrice = true, card = true }
function A.parseSlots(raw)
    local t = objectOf(raw)
    if not t then return nil, { "must be an object of slot id -> settings" } end
    local out, problems, n = {}, {}, 0
    local function bad(id, why) problems[#problems + 1] = tostring(id) .. ": " .. why end
    for id, e in pairs(t) do
        n = n + 1
        local s = W.validId(id) and W.slotById[id]
        if not W.validId(id) then
            bad(id, "bad slot id")
        elseif s and s.tier ~= "addon" then
            bad(id, "built-in slot: use the sandbox options")
        elseif type(e) ~= "table" or e == Cfg.NULL or Cfg.isArray(e) then
            bad(id, "must be an object")
        else
            local ok = true
            for k in pairs(e) do
                if not SLOT_KEYS[k] then bad(id, "unknown field " .. tostring(k)); ok = false end
            end
            if not W.MODE_VALUE[e.mode] then bad(id, "mode must be free, card, econ or off"); ok = false end
            for _, f in ipairs({ "buy", "rent", "card" }) do
                if e[f] ~= nil and type(e[f]) ~= "boolean" then bad(id, f .. " must be true or false"); ok = false end
            end
            for _, f in ipairs({ "buyPrice", "rentPrice" }) do
                if e[f] ~= nil and not intIn(e[f], 1, 1000000000) then
                    bad(id, f .. " must be a whole number from 1 to 1000000000"); ok = false
                end
            end
            if ok then
                out[id] = { mode = e.mode, buy = e.buy, buyPrice = e.buyPrice, rent = e.rent, rentPrice = e.rentPrice,
                    card = e.card }
            end
        end
    end
    if n > A.MAX_ENTRIES then problems[#problems + 1] = "more than " .. A.MAX_ENTRIES .. " slots" end
    if #problems > 0 then return nil, problems end
    return out
end

Cfg.keyOrder({ "mode", "buy", "buyPrice", "rent", "rentPrice", "card" })
Cfg.section("moduleDrains", { default = function() return {} end, parse = A.parseDrains })
Cfg.section("addonSlots", { default = function() return {} end, parse = A.parseSlots })

-- ===== 推送清單（MP 伺服器）=====
function A.lists()
    return { moduleDrains = W.copyTable(Cfg.get("moduleDrains") or {}), addonSlots = W.copyTable(Cfg.get("addonSlots") or {}) }
end
function A.pushLists(player)
    if not isServer() then return end
    W.invalidate()
    if player then
        local args = A.lists()
        args.to = player:getUsername()
        sendServerCommand(player, W.MODULE, W.CMD_LISTS, args)
    else
        sendServerCommand(W.MODULE, W.CMD_LISTS, A.lists()) -- 沒有 player＝廣播（LuaManager.java:8956-8959）
    end
end
Cfg.onBump = function()
    if isServer() then A.pushLists() else W.invalidate() end
end

-- ===== 讀取（管理員視窗開啟時）=====
-- 先 poll：剛手改過的檔案也算進來（版本跟著 +1）
function A.state()
    Cfg.poll()
    local s = { rev = Cfg.revision, econ = W.econStatus }
    for _, name in ipairs(Cfg.order) do
        local spec, v = Cfg.sections[name], Cfg.values[name]
        s[name] = spec.export and spec.export(v) or W.copyTable(v)
    end
    return s
end

-- ===== 審計紀錄 =====
local function clean(s)
    if type(s) ~= "string" then return nil end
    s = string.gsub(s, "%c", " ")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    if s == "" or #s > A.MAX_TEXT then return nil end
    return s
end

local function stamp()
    local ok, s = pcall(os.date, "!%Y-%m-%d %H:%M:%S", math.floor(getTimestampMs() / 1000))
    return ok and s and (s .. " UTC") or tostring(getTimestampMs())
end

function A.audit(name, rev, reason, changes)
    local lines = { "[" .. stamp() .. "] " .. name .. " (revision " .. rev .. "): " .. reason }
    for _, c in ipairs(changes) do lines[#lines + 1] = "  - " .. c end
    local text = table.concat(lines, "\n") .. "\n"
    local path = Cfg.folder() .. A.AUDIT_FILE
    local ok = pcall(function()
        local w = getFileWriter(path, true, true) -- 第三參數＝附加（LuaManager.java getFileWriter）
        if w == nil then error("no writer") end
        w:write(text)
        w:close()
    end)
    W.log("admin settings changed by " .. name .. " (revision " .. rev .. ", " .. #changes .. " changes): " .. reason)
    if not ok then W.log("admin audit log could not be written: Zomboid/Lua/" .. path) end
    return ok
end

-- ===== 套用 =====
-- args＝{ expected = 版本, reason = 原因, changes = { "原本 → 改成" 文字… }, lists = { 區段名 = 原始值 }?, sandbox = 沙盒改了幾項 }
-- 回 { ok = true, rev } 或 { ok = false, code = denied|bad_request|reason|conflict|invalid|write_failed, rev?, problems? }
local LIST_SECTIONS = { zombieDrops = true, moduleDrains = true, addonSlots = true }
function A.apply(player, args)
    local name = player and tostring(player:getUsername()) or "?"
    if not W.isSettingsAdmin(player) then
        W.log("admin settings refused for " .. name .. ": no SandboxOptions permission")
        return { ok = false, code = "denied" }
    end
    if type(args) ~= "table" or not W.isFiniteInt(args.expected) or type(args.changes) ~= "table"
            or (args.lists ~= nil and type(args.lists) ~= "table") or #args.changes > A.MAX_CHANGES then
        return { ok = false, code = "bad_request" }
    end
    local reason = clean(args.reason)
    if not reason then return { ok = false, code = "reason" } end
    local changes = {}
    for _, c in ipairs(args.changes) do
        local s = clean(c)
        if not s then return { ok = false, code = "bad_request" } end
        changes[#changes + 1] = s
    end
    local lists, any = {}, false
    for k, v in pairs(args.lists or {}) do
        if not LIST_SECTIONS[k] then return { ok = false, code = "bad_request" } end
        lists[k], any = v, true
    end
    if not any and (tonumber(args.sandbox) or 0) <= 0 then return { ok = false, code = "bad_request" } end
    Cfg.poll() -- 剛手改過的檔案先算進版本
    if args.expected ~= Cfg.revision then return { ok = false, code = "conflict", rev = Cfg.revision } end
    if any then
        local ok, problems = Cfg.save(lists)
        if not ok then
            local code = problems[1] == "write_failed" and "write_failed" or "invalid"
            local out = {}
            for i = 1, math.min(8, #problems) do out[i] = problems[i] end
            W.log("admin settings from " .. name .. " rejected: " .. table.concat(out, "; "))
            return { ok = false, code = code, problems = out, rev = Cfg.revision }
        end
    else
        Cfg.bump() -- 只改沙盒：一樣換版本，擋住另一位管理員的舊畫面
    end
    A.audit(name, Cfg.revision, reason, changes)
    return { ok = true, rev = Cfg.revision }
end

-- ===== 指令（MP）=====
-- OnClientCommand 的 player 是伺服器用連線反查的（LuaManager.java:8940），payload 指定不了別人。
-- 節流同 MinidoracatWatch_Server.lua：每位玩家 250 ms 一次（清單補要另一條）。
local MIN_INTERVAL_MS = 250
local lastAt = {}
local function throttled(key, now)
    local last = lastAt[key]
    if last and now >= last and now - last < MIN_INTERVAL_MS then return true end
    lastAt[key] = now
    return false
end

function A.onClientCommand(module, command, player, args)
    if module ~= W.MODULE or not player then return end
    local key = tostring(player:getUsername()) .. ":" .. tostring(player:getOnlineID())
    local now = getTimestampMs()
    if command == W.CMD_LISTS_REQ then
        if not throttled(key .. ":l", now) then A.pushLists(player) end
        return
    end
    if command ~= A.CMD_GET and command ~= A.CMD_SET then return end
    if throttled(key .. ":a", now) then return end
    local to = player:getUsername()
    if command == A.CMD_GET then
        if not W.isSettingsAdmin(player) then
            W.log("admin settings refused for " .. tostring(to) .. ": no SandboxOptions permission")
            sendServerCommand(player, W.MODULE, A.CMD_RESULT, { to = to, ok = false, code = "denied" })
            return
        end
        local s = A.state()
        s.to = to
        sendServerCommand(player, W.MODULE, A.CMD_STATE, s)
        return
    end
    local res = A.apply(player, args)
    res.to = to
    sendServerCommand(player, W.MODULE, A.CMD_RESULT, res)
end
Events.OnClientCommand.Add(A.onClientCommand)
