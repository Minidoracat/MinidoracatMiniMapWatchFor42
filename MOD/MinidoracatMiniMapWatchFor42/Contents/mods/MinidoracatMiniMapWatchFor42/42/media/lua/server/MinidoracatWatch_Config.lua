-- MinidoracatWatch_Config.lua：伺服器設定檔（使用者裁定：數值放沙盒，清單類設定放伺服器設定檔）。
-- 位置：Zomboid/Lua/MinidoracatWatch/<伺服器名；單機 sp_<存檔名>>/server-settings.json（資料夾規則照車輛管理
-- MinidoracatVehicleManager_Export.lua X.folder；getFileReader／getFileWriter 的路徑相對於 Zomboid/Lua）。
-- 格式：一個 JSON 物件，一個區段一個鍵，例如 { "version": 1, "zombieDrops": [ … ] }。區段由 Cfg.section 登記
-- （本階段只有殭屍掉落；Phase 4 的第三方模組耗電加一個區段即可），各自驗證、各自保留上一份有效值：
--   - 檔案不存在：用各區段目前的值（新伺服器＝預設）寫一份；寫完讀回比對才算成功（PrintWriter 吞 I/O 錯誤）。
--   - 讀不到、不是 JSON、最外層不是物件：每個區段都保留上一份有效值，log 一次（同一份內容不重報）。
--   - 缺某個區段：那個區段用預設值。區段驗證失敗：那個區段保留上一份有效值，log 每個問題。未知的鍵：log、不影響其他區段。
-- 每 POLL_MS 比對一次檔案文字（OnTickEvenPaused：空服暫停時 OnTick 不跑），有變才重讀，管理員改檔不必重開伺服器。
-- MP 客戶端也會載入 media/lua/server（GameLoadingState.java:148）：客戶端不碰設定檔。
if isClient() then return end
require "MinidoracatWatch"
local W = MinidoracatWatchCore

local Cfg = { sections = {}, order = {}, values = {}, lastText = nil, loaded = false }
W.Config = Cfg
Cfg.DIR = "MinidoracatWatch/"
Cfg.FILE = "server-settings.json"
Cfg.VERSION = 1
Cfg.POLL_MS = 10000
Cfg.NULL = setmetatable({}, { __tostring = function() return "null" end })

-- ===== JSON（解碼照 Economy ECCore.jsonDecode；編碼縮排輸出，給管理員手改）=====
local function skipSpace(s, pos)
    local _, e = string.find(s, "^[ \t\r\n]*", pos)
    return e + 1
end

local function decodeError(s, pos, msg)
    return nil, msg .. " at " .. tostring(pos) .. " near '" .. string.sub(s, pos, pos + 12) .. "'"
end

-- Kahlua 的字串是 UTF-16（StringLib.java:760-768）；離線 Lua 是 UTF-8
local function unicodeChar(code)
    if utf8 and utf8.char then return utf8.char(code) end
    if code < 65536 then return string.char(code) end
    code = code - 65536
    return string.char(55296 + math.floor(code / 1024), 56320 + code % 1024)
end

local ESCAPES = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }

local function decodeString(s, pos)
    local out, i, n = {}, pos + 1, #s
    while i <= n do
        local c = string.sub(s, i, i)
        if c == '"' then return table.concat(out), i + 1 end
        if c == "\\" then
            local e = string.sub(s, i + 1, i + 1)
            if e == "u" then
                local hex = string.sub(s, i + 2, i + 5)
                if not string.match(hex, "^%x%x%x%x$") then return nil end
                local code = tonumber(hex, 16)
                if code >= 55296 and code <= 56319 then
                    local lowHex = string.sub(s, i + 8, i + 11)
                    if string.sub(s, i + 6, i + 7) ~= "\\u" or not string.match(lowHex, "^%x%x%x%x$") then return nil end
                    local low = tonumber(lowHex, 16)
                    if low < 56320 or low > 57343 then return nil end
                    code = 65536 + (code - 55296) * 1024 + low - 56320
                    i = i + 6
                elseif code >= 56320 and code <= 57343 then
                    return nil
                end
                out[#out + 1] = unicodeChar(code)
                i = i + 6
            elseif ESCAPES[e] then
                out[#out + 1] = ESCAPES[e]
                i = i + 2
            else
                return nil
            end
        else
            if string.byte(c) < 32 then return nil end
            out[#out + 1] = c
            i = i + 1
        end
    end
    return nil
end

local decodeValue
decodeValue = function(s, pos)
    pos = skipSpace(s, pos)
    local c = string.sub(s, pos, pos)
    if c == "{" then
        local obj = {}
        pos = skipSpace(s, pos + 1)
        if string.sub(s, pos, pos) == "}" then return obj, pos + 1 end
        while true do
            pos = skipSpace(s, pos)
            if string.sub(s, pos, pos) ~= '"' then return decodeError(s, pos, "expected key") end
            local key, np = decodeString(s, pos)
            if not key then return decodeError(s, pos, "bad string") end
            pos = skipSpace(s, np)
            if string.sub(s, pos, pos) ~= ":" then return decodeError(s, pos, "expected ':'") end
            local value, np2 = decodeValue(s, pos + 1)
            if type(np2) ~= "number" then return nil, np2 end
            obj[key] = value
            pos = skipSpace(s, np2)
            local d = string.sub(s, pos, pos)
            if d == "," then pos = pos + 1
            elseif d == "}" then return obj, pos + 1
            else return decodeError(s, pos, "expected ',' or '}'") end
        end
    elseif c == "[" then
        local arr = {}
        pos = skipSpace(s, pos + 1)
        if string.sub(s, pos, pos) == "]" then return arr, pos + 1 end
        while true do
            local value, np = decodeValue(s, pos)
            if type(np) ~= "number" then return nil, np end
            arr[#arr + 1] = value
            pos = skipSpace(s, np)
            local d = string.sub(s, pos, pos)
            if d == "," then pos = pos + 1
            elseif d == "]" then return arr, pos + 1
            else return decodeError(s, pos, "expected ',' or ']'") end
        end
    elseif c == '"' then
        local str, np = decodeString(s, pos)
        if not str then return decodeError(s, pos, "bad string") end
        return str, np
    elseif string.sub(s, pos, pos + 3) == "true" then return true, pos + 4
    elseif string.sub(s, pos, pos + 4) == "false" then return false, pos + 5
    elseif string.sub(s, pos, pos + 3) == "null" then return Cfg.NULL, pos + 4
    end
    local numStr = string.match(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    local num = numStr and tonumber(numStr)
    if not num then return decodeError(s, pos, "unexpected token") end
    return num, pos + #numStr
end

-- 回 value 或 nil, 訊息。物件＝字串鍵 table、陣列＝1 起序列、null＝Cfg.NULL（驗證時當錯誤）
function Cfg.decode(s)
    if type(s) ~= "string" then return nil, "not a string" end
    -- Windows PowerShell 5.1 的 Set-Content -Encoding UTF8 會寫 BOM（Java 讀成 U+FEFF）
    if string.byte(s, 1) == 65279 then s = string.sub(s, 2)
    elseif string.sub(s, 1, 3) == "\239\187\191" then s = string.sub(s, 4) end
    local value, np = decodeValue(s, 1)
    if type(np) ~= "number" then return nil, np end
    np = skipSpace(s, np)
    if np <= #s then return decodeError(s, np, "trailing garbage") end
    return value
end

-- 陣列＝1..n 連續整數鍵（空表也當陣列：本檔寫出的空表只會是清單）
function Cfg.isArray(t)
    if type(t) ~= "table" or t == Cfg.NULL then return false end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n == #t
end

local function encodeString(s)
    return '"' .. string.gsub(s, '[%c"\\]', function(ch)
        if ch == '"' then return '\\"' elseif ch == "\\" then return "\\\\" elseif ch == "\n" then return "\\n" end
        return string.format("\\u%04x", string.byte(ch))
    end) .. '"'
end

-- 物件鍵依 KEY_ORDER 排：version 先、各區段照登記順序、區段內的鍵照 Cfg.keyOrder，其餘照字母
local KEY_ORDER = { version = 1 }
function Cfg.keyOrder(names)
    for i, k in ipairs(names) do KEY_ORDER[k] = KEY_ORDER[k] or 1000 + i end
end
local function keyLess(a, b)
    local ra, rb = KEY_ORDER[a] or 1e9, KEY_ORDER[b] or 1e9
    if ra ~= rb then return ra < rb end
    return a < b
end

local function encode(v, indent)
    local t = type(v)
    if t == "string" then return encodeString(v) end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%.0f", v) end
        return string.format("%.6g", v)
    end
    if t ~= "table" then return "null" end
    local inner = indent .. "  "
    local parts = {}
    if Cfg.isArray(v) then
        if #v == 0 then return "[]" end
        for i = 1, #v do parts[i] = inner .. encode(v[i], inner) end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end
    -- 插入排序（Kahlua 的 table.sort 比較子不一致時會拋錯，家族規則不用；鍵只有幾個）
    local keys = {}
    for k in pairs(v) do
        local key, j = tostring(k), #keys
        while j > 0 and keyLess(key, keys[j]) do keys[j + 1] = keys[j]; j = j - 1 end
        keys[j + 1] = key
    end
    for i, k in ipairs(keys) do parts[i] = inner .. encodeString(k) .. ": " .. encode(v[k], inner) end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end
function Cfg.encode(v) return encode(v, "") end

-- ===== 區段 =====
-- spec.default()：新的一份預設值（不共用 table）；spec.parse(raw)：回 正規化後的值 或 nil, { 問題… }。
-- 呼叫端只讀 Cfg.get 回的值，不改它。
function Cfg.section(name, spec)
    if Cfg.sections[name] then return end
    Cfg.sections[name] = spec
    Cfg.order[#Cfg.order + 1] = name
    KEY_ORDER[name] = 10 + #Cfg.order
    Cfg.values[name] = spec.default()
end

function Cfg.get(name)
    if not Cfg.loaded then Cfg.poll() end
    return Cfg.values[name]
end

-- 套用一份檔案內容；回 true 或 false, { 問題… }（問題已 log）
function Cfg.apply(text)
    local doc, err = Cfg.decode(text)
    if type(doc) ~= "table" or doc == Cfg.NULL or (Cfg.isArray(doc) and #doc > 0) then
        local why = err or "top level is not an object"
        W.log("server settings unchanged, file is not a JSON object: " .. why)
        return false, { why }
    end
    local problems = {}
    for k in pairs(doc) do
        if k ~= "version" and not Cfg.sections[k] then problems[#problems + 1] = "unknown key " .. tostring(k) end
    end
    for _, name in ipairs(Cfg.order) do
        local raw = doc[name]
        if raw == nil then
            Cfg.values[name] = Cfg.sections[name].default()
        else
            local value, errs = Cfg.sections[name].parse(raw)
            if value ~= nil then
                Cfg.values[name] = value
            else
                for _, e in ipairs(errs or { "invalid" }) do
                    problems[#problems + 1] = name .. ": " .. e .. " (keeping the previous " .. name .. ")"
                end
            end
        end
    end
    for _, p in ipairs(problems) do W.log("server settings: " .. p) end
    return #problems == 0, problems
end

-- 一個世界一個資料夾：dedicated 用伺服器名，單機用存檔名
function Cfg.folder()
    local name = isServer() and getServerName() or ("sp_" .. tostring(getWorld():getWorld()))
    name = string.gsub(tostring(name or ""), "[^%w%-_]", "_")
    if name == "" or name == "sp_" then name = "default" end
    return Cfg.DIR .. name .. "/"
end
function Cfg.path() return Cfg.folder() .. Cfg.FILE end

-- getFileReader 把開檔錯誤吞掉回 nil（LuaManager.java:5949-5960），用 cacheFileExists 分辨不存在與讀不到
local function readText(path)
    local ok, r = pcall(getFileReader, path, false)
    if not ok or r == nil then
        local checked, exists = pcall(cacheFileExists, path)
        if checked and not exists then return nil, "missing" end
        return nil, "unreadable"
    end
    local lines = {}
    while true do
        local line = r:readLine()
        if line == nil then break end
        lines[#lines + 1] = line
    end
    r:close()
    return table.concat(lines, "\n")
end

local function writeText(path, text)
    local ok = pcall(function()
        local w = getFileWriter(path, true, false)
        if w == nil then error("no writer") end
        w:write(text .. "\n")
        w:close()
    end)
    return ok and readText(path) == text
end

function Cfg.document()
    local doc = { version = Cfg.VERSION }
    for _, name in ipairs(Cfg.order) do doc[name] = Cfg.values[name] end
    return doc
end

function Cfg.poll()
    Cfg.loaded = true
    local path = Cfg.path()
    local text, why = readText(path)
    if why == "missing" then
        local out = Cfg.encode(Cfg.document())
        if writeText(path, out) then
            Cfg.lastText = out
            W.log("server settings written with defaults: Zomboid/Lua/" .. path)
        elseif Cfg.lastText ~= "write_failed" then
            Cfg.lastText = "write_failed"
            W.log("server settings could not be written: Zomboid/Lua/" .. path)
        end
        return
    end
    if text == nil then
        if Cfg.lastText ~= "unreadable" then
            Cfg.lastText = "unreadable"
            W.log("server settings unreadable, keeping the previous settings: Zomboid/Lua/" .. path)
        end
        return
    end
    if text == Cfg.lastText then return end
    Cfg.lastText = text
    if Cfg.apply(text) then W.log("server settings loaded: Zomboid/Lua/" .. path) end
end

local lastPoll = nil
function Cfg.tick()
    local now = getTimestampMs()
    if lastPoll and now >= lastPoll and now - lastPoll < Cfg.POLL_MS then return end
    lastPoll = now
    Cfg.poll()
end
Events.OnTickEvenPaused.Add(Cfg.tick)
