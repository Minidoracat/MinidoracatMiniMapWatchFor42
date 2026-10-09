-- 地圖錶管理員設定（Phase 4）：沙盒欄位表對照 sandbox-options.txt、「目前設定一覽」與「這次會改變」的文字（載真的 CH 翻譯）、
-- 快速方案、送出內容、伺服器端的權限拒絕／驗證與壞值／expectedRevision 衝突／手改檔也換版本／審計紀錄／推送清單、
-- 清單在閘門與 Economy 方案上的效果（第三方耗電、逐槽設定）、客戶端收清單、取得方式的數量套到分佈表、沙盒套用（單機／MP）。
-- 用法（repo 根目錄）：lua scripts/test_watch_admin.lua
local F = dofile("scripts/lib_watch_fakes.lua")
local check = F.check
F.mode = "server"

-- ===== 真的 CH 翻譯（getText 照 Translator：%1..%9 代入、%% → %）=====
local TR = {}
local function loadTr(path)
    for line in io.lines(path) do
        local k, v = line:match('^%s*"([^"]+)":%s*"(.*)",?%s*$')
        if k then
            v = v:gsub('\\n', '\n'):gsub('\\"', '"'):gsub('\\\\', '\\')
            TR[k] = v
        end
    end
end
local TDIR = F.MEDIA .. "/shared/Translate/CH/"
loadTr(TDIR .. "IG_UI.json")
loadTr(TDIR .. "Sandbox.json")
loadTr(TDIR .. "ItemName.json")
local missingKeys = {}
function getText(key, ...)
    local v = TR[key]
    if not v then
        missingKeys[#missingKeys + 1] = key
        return key
    end
    local args = { ... }
    v = v:gsub("%%%%", "\0")
    v = v:gsub("%%(%d)", function(d)
        local a = args[tonumber(d)]
        return a ~= nil and tostring(a) or ("%" .. d)
    end)
    return (v:gsub("%z", "%%"))
end
function getItemNameFromFullType(t)
    local short = t:match("%.(.+)$")
    return TR["ItemName_" .. t] or TR["ItemName_MinidoracatWatch." .. tostring(short)] or t
end

-- ===== 假檔案系統（getFileWriter 第三參數＝附加）=====
local FS = {}
local writeFails = false
function getFileReader(path)
    local text = FS[path]
    if text == nil then return nil end
    local lines = {}
    for line in (text:sub(-1) == "\n" and text or text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    local i = 0
    return { readLine = function() i = i + 1; return lines[i] end, close = function() end }
end
function cacheFileExists(path) return FS[path] ~= nil end
function getFileWriter(path, create, append)
    if writeFails then return nil end
    local buf = {}
    return { write = function(_, s) buf[#buf + 1] = s end,
        close = function() FS[path] = (append and FS[path] or "") .. table.concat(buf) end }
end
function getServerName() return "servertest" end
function getWorld() return { getWorld = function() return "Muldraugh, KY" end } end

-- 原生沙盒（單機套用：set＋toLua；MP：SandboxOptions.new 複本 set＋sendToServer）
local NATIVE = {}
local sent, toLuaCalls = nil, 0
local Options = {}
Options.__index = Options
function Options:getOptionByName(n)
    if self.values[n] == nil then return nil end
    local values = self.values
    return { getValue = function() return values[n] end }
end
function Options:set(n, v)
    if self.values[n] == nil then error("unknown SandboxOption " .. n) end
    self.values[n] = v
end
function Options:toLua()
    toLuaCalls = toLuaCalls + 1
    for n, v in pairs(self.values) do
        local short = n:match("^MinidoracatWatch%.(.+)$")
        if short then SandboxVars.MinidoracatWatch[short] = v end
    end
end
function Options:copyValuesFrom(o) for k, v in pairs(o.values) do self.values[k] = v end end
function Options:sendToServer() sent = self.values end
local live = setmetatable({ values = NATIVE }, Options)
function getSandboxOptions() return live end
SandboxOptions = { new = function() return setmetatable({ values = {} }, Options) end }
local parses = 0
IsoWorld = { parseDistributions = function() parses = parses + 1 end }

-- 角色權限（Role.hasCapability(Capability.SandboxOptions)；admin、moderator 有，gm 沒有）
Capability = { SandboxOptions = "SandboxOptions", AddItem = "AddItem" }
local function role(caps)
    return { hasCapability = function(_, c) return caps[c] == true end }
end

require "MinidoracatWatch"
local W = MinidoracatWatchCore
F.load("server/MinidoracatWatch_Admin.lua")
F.load("server/MinidoracatWatch_Loot.lua")
local Cfg, A, L = W.Config, W.Admin, W.Loot
local PlayerMeta = getmetatable(F.player("probe"))
PlayerMeta.getRole = function(self) return self.role end

-- 沙盒預設值（照 sandbox-options.txt 解析），同時放進 SandboxVars 與原生選項
local SB = SandboxVars.MinidoracatWatch
local options = {}
do
    local text = io.open(F.MEDIA .. "/../sandbox-options.txt", "rb"):read("a")
    for name, body in text:gmatch("option MinidoracatWatch%.([%w_]+)%s*(%b{})") do
        local o = { name = name, type = body:match("type%s*=%s*(%a+)"), page = body:match("page%s*=%s*([%w_]+)") }
        o.min, o.max = tonumber(body:match("min%s*=%s*([%-%d%.]+)")), tonumber(body:match("max%s*=%s*([%-%d%.]+)"))
        o.numValues = tonumber(body:match("numValues%s*=%s*(%d+)"))
        local d = body:match("default%s*=%s*([%w%.]+)")
        if o.type == "boolean" then o.default = d == "true" else o.default = tonumber(d) end
        options[name] = o
        options[#options + 1] = o
        SB[name] = o.default
        NATIVE["MinidoracatWatch." .. name] = o.default
    end
end
local function resetSandbox()
    for _, o in ipairs(options) do
        SB[o.name] = o.default
        NATIVE["MinidoracatWatch." .. o.name] = o.default
    end
end

F.mode = "client" -- 模型與視窗在客戶端
dofile(F.MEDIA .. "/client/MinidoracatWatch_AdminModel.lua")
local M = MinidoracatWatchAdminModel
F.mode = "server"

-- ===== 1. 沙盒欄位表＝sandbox-options.txt（型別、範圍、預設）=====
do
    local bad = {}
    for _, f in ipairs(M.FIELDS) do
        local o = options[f[1]]
        if not o then
            bad[#bad + 1] = f[1] .. " missing in sandbox-options.txt"
        else
            local kind = ({ boolean = "bool", integer = "int", enum = "enum" })[o.type]
            if kind ~= f[2] then bad[#bad + 1] = f[1] .. " type" end
            if f[2] == "int" and (o.min ~= f[3] or o.max ~= f[4]) then bad[#bad + 1] = f[1] .. " range" end
            if f[2] == "enum" and (f[3] ~= 1 or o.numValues ~= f[4]) then bad[#bad + 1] = f[1] .. " numValues" end
            if o.default ~= f[5] then bad[#bad + 1] = f[1] .. " default" end
        end
    end
    for _, o in ipairs(options) do
        if not M.FIELD[o.name] then bad[#bad + 1] = o.name .. " not in the admin window" end
    end
    check(#bad == 0, "admin field table matches sandbox-options.txt: " .. table.concat(bad, ", "))
    -- 順序與分頁：M.FIELDS＝檔案順序；四頁照視窗分頁（總覽＋功能／槽位與價格／電池／取得方式＋殭屍掉落），每頁連續
    local function tabOf(k)
        if k:find("^Slot") or k:find("^Pay") then return "Slots" end
        if k:find("^Drain") or k:find("^Charge") or k:find("Hours$") or k == "LightDrain" or k == "NeedBattery"
            or k == "DeadMode" then return "Battery" end
        if k:find("^Loot") or k:find("^Zombie") or k:find("Craft") or k == "NeedScrewdriver" then return "Acquire" end
        return "Features"
    end
    local order, pages, seq = {}, {}, {}
    for i, o in ipairs(options) do
        if not M.FIELDS[i] or M.FIELDS[i][1] ~= o.name then order[#order + 1] = i .. ":" .. o.name end
        if o.page ~= "MinidoracatWatch" .. tabOf(o.name) then pages[#pages + 1] = o.name .. "@" .. tostring(o.page) end
        if seq[#seq] ~= o.page then seq[#seq + 1] = o.page end
    end
    check(#order == 0 and #M.FIELDS == #options, "admin field table follows the sandbox file order: " .. table.concat(order, ", "))
    check(#pages == 0, "every sandbox option sits on the page of its admin tab: " .. table.concat(pages, ", "))
    check(table.concat(seq, ",") == "MinidoracatWatchFeatures,MinidoracatWatchSlots,MinidoracatWatchBattery,MinidoracatWatchAcquire",
        "four sandbox pages, each contiguous, in admin tab order: " .. table.concat(seq, ","))
end

-- ===== 2. 目前設定一覽（設計稿 summaryItems）=====
local function has(lines, s)
    for _, l in ipairs(lines) do if l == s then return true end end
    return false
end
local function find(lines, pat)
    for _, l in ipairs(lines) do if l:find(pat, 1, true) then return l end end
    return nil
end
local base = M.readBase({ rev = 1, zombieDrops = W.defaultDrops(), moduleDrains = {}, addonSlots = {} })
do
    check(base.sb.FullHours == 72 and base.sb.ChargeCar == false, "base reads the sandbox, charge fields included")
    local s = M.summary(base, false)
    check(has(s, "小地圖：戴錶就能用"), "summary: minimap rule")
    check(has(s, "導航：需要定位模組") and not has(s, "方向箭頭"), "summary: module rule names the module; the arrow has no rule of its own")
    check(has(s, "照明：需要照明模組"), "summary: light rule")
    check(has(s, "擴充槽：目前沒有經濟系統，暫時改用解鎖卡"), "summary: economy tier without Economy falls back to cards")
    check(has(s, "電池：滿電約 72 小時（現實時間），離線時不耗電，暫停時不耗電"), "summary: battery line")
    check(has(s, "模組耗電：建議值，開燈時 +100%"), "summary: drains at defaults")
    check(has(s, "戰利品：7 款地圖手錶都會出現"), "summary: all seven styles in loot")
    check(has(s, "殭屍掉落：10 條規則，每隻最多 1 件"), "summary: drops")
    check(has(s, "充電：只能換電池"), "summary: charge defaults to battery swaps only")
    s = M.summary(base, true)
    check(has(s, "擴充槽：租用每 7 天 60 倖存幣，或買斷 400 倖存幣"), "summary: rent and buy with Economy")
    check(has(s, "核心槽：租用每 7 天 300 倖存幣，或買斷 2,400 倖存幣"), "summary: thousands separator")
    local d = M.copy(base)
    d.sb.SlotAdvBuy, d.sb.SlotAdvRent = false, false
    d.sb.DrainLedger, d.sb.ZombieDrops, d.sb.LootPaws = 30, false, false
    d.sb.ChargeCar, d.sb.CarHours, d.sb.ChargeHouse, d.sb.HouseHours = true, 6, false, 12
    s = M.summary(d, true)
    check(has(s, "進階槽：經濟系統，但買斷和租用都沒有開放"), "summary: economy with nothing on sale")
    check(has(s, "模組耗電：已調整 1 項，開燈時 +100%"), "summary: tuned drains counted")
    check(has(s, "殭屍掉落：關閉") and has(s, "戰利品：6 款地圖手錶會出現"), "summary: drops off, six styles")
    check(has(s, "充電：車上約 6 小時充滿"), "summary: charge line names the car hours")
    check(has(s, "沒電時：所有功能停用"), "summary: dead mode line")
    d.sb.SlotExtCard = true
    check(has(M.summary(d, true), "擴充槽：租用每 7 天 60 倖存幣，或買斷 400 倖存幣，也接受解鎖卡"),
        "summary: economy tier that also takes unlock cards")
    d.sb.NeedBattery = false
    s = M.summary(d, true)
    check(has(s, "電池：不需要電池，地圖手錶不會沒電") and not find(s, "充電：") and not find(s, "沒電時："),
        "summary: no battery needed replaces the battery, drain and charge lines")
    d.sb.Enabled = false
    s = M.summary(d, true)
    check(#s == 1 and s[1] == "地圖手錶：已停用，所有功能都和現在一樣，不需要錶", "summary: disabled is a single line")
end

-- ===== 3. 這次會改變什麼（原本 → 改成）=====
do
    local d = M.copy(base)
    local lines, warn, n = M.diff(base, d)
    check(#lines == 0 and n == 0 and not warn, "diff: nothing changed")
    d.sb.FullHours = 48
    d.sb.RuleZombie = 4
    d.sb.LootModuleAmount = 1
    d.sb.SlotCoreRentPrice = 500
    table.remove(d.drops, 1)
    d.drops[#d.drops + 1] = { group = "custom", outfits = { "HazardSuit", "Bandit" }, item = "card:core", chance = 0.5 }
    lines, warn, n = M.diff(base, d)
    check(has(lines, "滿電可用時間（小時）：從 72 改成 48（所有地圖手錶的剩餘時間照比例改變）"), "diff: full hours with note")
    check(has(lines, "殭屍點位：從 需要偵測模組 改成 關閉這個功能（所有人都用不到）"), "diff: rule names both sides")
    check(has(lines, "戰利品：模組的數量：從 一般 改成 很少"), "diff: enum uses the sandbox option names")
    check(find(lines, "核心槽：每期租金：從 300 改成 500") ~= nil, "diff: price")
    check(has(lines, "刪除掉落規則：所有殭屍每隻有 0.2% 機率掉落ValuTech 地圖手錶")
        or find(lines, "刪除掉落規則：所有殭屍每隻有 0.2% 機率掉落") ~= nil, "diff: removed drop rule as a sentence")
    check(find(lines, "新增掉落規則：穿 HazardSuit, Bandit 的殭屍每隻有 0.5% 機率掉落") ~= nil, "diff: added custom rule")
    check(warn and lines[#lines]:find("重新同意", 1, true) ~= nil and n == #lines - 1,
        "diff: rent price change warns about re-consent (Phase 6 D3), last line, not counted")
    local c = M.copy(base)
    c.sb.NeedBattery, c.sb.DeadMode, c.sb.CraftLevel = false, 2, 5
    lines = M.diff(base, c)
    check(has(lines, "需要電池：從 開 改成 關") and has(lines, "沒電時：從 所有功能停用 改成 只保留小地圖")
        and has(lines, "製作模組需要的電學等級：從 3 改成 5"), "diff: battery switch, dead mode and craft level")
    -- 同一條規則只改順序不算
    local e = M.copy(base)
    e.drops[1], e.drops[2] = e.drops[2], e.drops[1]
    local _, _, n2 = M.diff(base, e)
    check(n2 == 0, "diff: reordering drop rules is not a change")
    check(#missingKeys == 0, "every admin text key exists in CH: " .. table.concat(missingKeys, ", "))
end

-- ===== 4. 快速方案 =====
do
    local d = M.copy(base)
    M.applyPreset(d, "easy")
    check(d.sb.FullHours == 168 and d.sb.MinimapRule == 2 and d.sb.RuleNav == 1 and d.sb.SlotCore == 1
        and d.sb.SlotAddon == 1 and d.sb.RuleLight == 1 and d.sb.DeadMode == 2,
        "preset easy: 7 days, minimap needs a watch, rest free, slots free, minimap kept when dead")
    check(M.T("Preset_easy_desc"):find("沒電時保留小地圖", 1, true) ~= nil, "preset easy text says the minimap stays")
    M.applyPreset(d, "hard")
    check(d.sb.FullHours == 24 and d.sb.RuleNav == 3 and d.sb.SlotCore == 1 and d.sb.DeadMode == 1,
        "preset hard: 1 day, modules, keeps slot modes, everything off when dead")
    check(not M.applyPreset(d, "nope"), "unknown preset refused")
end

-- ===== 5. 送出內容與驗證 =====
do
    local d = M.copy(base)
    d.sb.FullHours = 48
    local args = M.payload(base, d, 7, "why", { "x" })
    local nLists = 0
    for _ in pairs(args.lists) do nLists = nLists + 1 end
    check(args.expected == 7 and args.sandbox == 1 and nLists == 0, "payload: sandbox only, no list sections")
    d.drops[1].chance = 3
    args = M.payload(base, d, 7, "why", { "x" })
    check(args.lists.zombieDrops and #args.lists.zombieDrops == 10 and args.lists.zombieDrops[1].outfits == nil,
        "payload: changed drops sent in the file shape")
    check(M.problems(d) == 0, "valid draft has no problems")
    d.sb.FullHours = 0
    d.drops[2].chance = 101
    d.drops[3].group = "custom"
    check(M.problems(d) == 3, "problems: out-of-range hours, chance over 100, custom rule without outfits")
    check(M.parseOutfits("HazardSuit, Bandit")[2] == "Bandit" and M.parseOutfits("bad name!") == nil
        and M.parseOutfits("  ") == nil, "outfit list parsing")
end

-- ===== 6. 伺服器：權限、驗證、版本、審計、推送 =====
local admin = F.player("boss")
admin.role = role({ SandboxOptions = true })
local gm = F.player("gm1")
gm.role = role({ AddItem = true })
local plain = F.player("joe")
local auditPath = "MinidoracatWatch/servertest/admin-audit.log"
local cfgPath = "MinidoracatWatch/servertest/server-settings.json"

check(W.isSettingsAdmin(admin) and not W.isSettingsAdmin(gm) and not W.isSettingsAdmin(plain),
    "permission: SandboxOptions capability only (gm and players refused)")
F.mode = "sp"
check(W.isSettingsAdmin(plain), "permission: the single player is the admin")
F.mode = "server"

local st = A.state()
local rev0 = st.rev
check(type(rev0) == "number" and #st.zombieDrops == 10 and FS[cfgPath] ~= nil, "state: revision, default drops, file written")

local function req(lists, extra)
    local a = { expected = Cfg.revision, reason = "balance", changes = { "a: 1 to 2" }, lists = lists, sandbox = 0 }
    for k, v in pairs(extra or {}) do a[k] = v end
    return a
end
do
    local fileBefore = FS[cfgPath]
    local r = A.apply(gm, req({ moduleDrains = { weather = 10 } }))
    check(r.ok == false and r.code == "denied" and FS[cfgPath] == fileBefore and FS[auditPath] == nil,
        "denied: gm cannot change settings, file and audit untouched")
    r = A.apply(plain, req({ moduleDrains = { weather = 10 } }))
    check(r.code == "denied", "denied: a plain player")
    check(A.apply(admin, req({ moduleDrains = { weather = 10 } }, { reason = "   " })).code == "reason", "reason required")
    check(A.apply(admin, req({ bogus = {} })).code == "bad_request", "unknown list section refused")
    check(A.apply(admin, req({ moduleDrains = { weather = 10 } }, { changes = { 5 } })).code == "bad_request",
        "change lines must be text")
    check(A.apply(admin, req({}, { sandbox = 0 })).code == "bad_request", "empty request refused")
    local revBefore = Cfg.revision
    r = A.apply(admin, req({ zombieDrops = { { group = "all", item = "battery", chance = 150 } } }))
    check(r.code == "invalid" and FS[cfgPath] == fileBefore and Cfg.revision == revBefore,
        "invalid: chance 150 refused, file and revision unchanged")
    r = A.apply(admin, req({ moduleDrains = { ledger = 5 } }))
    check(r.code == "invalid" and r.problems[1]:find("built in", 1, true), "invalid: built-in module drain belongs to the sandbox")
    r = A.apply(admin, req({ moduleDrains = { weather = 2.5 } }))
    check(r.code == "invalid", "invalid: drain must be a whole number")
    r = A.apply(admin, req({ addonSlots = { ext = { mode = "free" } } }))
    check(r.code == "invalid", "invalid: built-in slot in addonSlots")
    r = A.apply(admin, req({ addonSlots = { weather = { mode = "gratis" } } }))
    check(r.code == "invalid", "invalid: unknown mode")
    r = A.apply(admin, req({ addonSlots = { weather = { mode = "econ", buyPrice = 0 } } }))
    check(r.code == "invalid", "invalid: price below 1")
    r = A.apply(admin, req({ addonSlots = { weather = { mode = "econ", card = "yes" } } }))
    check(r.code == "invalid", "invalid: card must be true or false")
    r = A.apply(admin, req({ moduleDrains = { weather = 10 }, zombieDrops = { { group = "army", item = "nope", chance = 1 } } }))
    check(r.code == "invalid" and Cfg.get("moduleDrains").weather == nil,
        "invalid: one bad section rejects the whole request (valid section not applied)")
    writeFails = true
    r = A.apply(admin, req({ moduleDrains = { weather = 10 } }))
    writeFails = false
    check(r.code == "write_failed" and Cfg.get("moduleDrains").weather == nil, "write failure: nothing applied")
end

-- 成功、版本、審計、推送
do
    F.reset()
    local rev = Cfg.revision
    local r = A.apply(admin, req({ moduleDrains = { weather = 40 },
        addonSlots = { weather = { mode = "econ", buy = false, rentPrice = 90 } } }, { reason = "balance pass", sandbox = 2 }))
    check(r.ok and r.rev == rev + 1 and Cfg.revision == rev + 1, "applied: revision +1")
    check(Cfg.get("moduleDrains").weather == 40 and Cfg.get("addonSlots").weather.rentPrice == 90, "applied: values live")
    check(FS[cfgPath]:find('"moduleDrains"', 1, true) and FS[cfgPath]:find('"rentPrice": 90', 1, true)
        and not FS[cfgPath]:find("outfitSet", 1, true), "applied: written to the settings file (file shape only)")
    local audit = FS[auditPath] or ""
    check(audit:find("boss (revision " .. (rev + 1) .. "): balance pass", 1, true) and audit:find("  - a: 1 to 2", 1, true),
        "audit: who, revision, reason and the change lines")
    local pushed = nil
    for _, c in ipairs(F.serverCmds) do if c.command == W.CMD_LISTS and c.broadcast then pushed = c.args end end
    check(pushed and pushed.moduleDrains.weather == 40 and pushed.addonSlots.weather.mode == "econ",
        "lists broadcast to every client after a change")
    -- 衝突：兩位管理員從同一個版本開始
    local admin2 = F.player("boss2")
    admin2.role = role({ SandboxOptions = true })
    local start = Cfg.revision
    local a1 = req({ moduleDrains = { weather = 50 } })
    local a2 = req({ moduleDrains = { weather = 60 } })
    check(A.apply(admin, a1).ok, "conflict: first admin applies")
    local before = FS[cfgPath]
    r = A.apply(admin2, a2)
    check(r.ok == false and r.code == "conflict" and r.rev == start + 1 and FS[cfgPath] == before
        and Cfg.get("moduleDrains").weather == 50, "conflict: second admin with the old revision is refused, no overwrite")
    -- 只改沙盒也換版本
    local sbOnly = req(nil, { sandbox = 1 })
    r = A.apply(admin2, sbOnly)
    check(r.ok and Cfg.revision == start + 2, "sandbox-only apply bumps the revision too")
    check(A.apply(admin, req(nil, { sandbox = 1, expected = start + 1 })).code == "conflict",
        "conflict: a stale sandbox-only apply is refused")
    -- 手改設定檔：下一次讀取就換版本，舊畫面送出被擋
    local mid = Cfg.revision
    FS[cfgPath] = FS[cfgPath]:gsub('"weather": 50', '"weather": 55')
    r = A.apply(admin, req({ moduleDrains = { weather = 70 } }, { expected = mid }))
    check(r.code == "conflict" and Cfg.get("moduleDrains").weather == 55, "hand-edited file: new revision, stale apply refused")
end

-- 指令（MP）：一般玩家偽造 adminSet／adminGet 被拒、回 denied；管理員拿得到 state
do
    F.reset()
    F.now = F.now + 1000
    local before = FS[cfgPath]
    A.onClientCommand(W.MODULE, W.CMD_ADMIN_SET, plain, req({ moduleDrains = { weather = 1 } }))
    A.onClientCommand(W.MODULE, W.CMD_ADMIN_GET, gm, {})
    local denied = 0
    for _, c in ipairs(F.serverCmds) do
        if c.command == W.CMD_ADMIN_RESULT and c.args.code == "denied" then denied = denied + 1 end
        check(c.command ~= W.CMD_ADMIN_STATE, "no state sent to a non-admin")
    end
    check(denied == 2 and FS[cfgPath] == before, "forged admin commands: refused with denied, file unchanged")
    F.reset()
    A.onClientCommand(W.MODULE, W.CMD_ADMIN_GET, admin, {})
    local stateCmd = F.serverCmds[1]
    check(stateCmd and stateCmd.command == W.CMD_ADMIN_STATE and stateCmd.player == admin and stateCmd.args.to == "boss"
        and stateCmd.args.rev == Cfg.revision, "admin gets the state with the current revision")
    F.reset()
    A.onClientCommand(W.MODULE, W.CMD_LISTS_REQ, plain, {})
    check(F.serverCmds[1] and F.serverCmds[1].command == W.CMD_LISTS and F.serverCmds[1].player == plain,
        "any player can ask for the lists (gates need them)")
end

-- ===== 7. 清單的效果：第三方耗電、逐槽設定（閘門與 Economy 方案）=====
do
    MinidoracatWatchAPI.registerWatchModule({ id = "weather", name = "Weather", class = "standard", drain = 15,
        item = "TestMod.Weather" })
    MinidoracatWatchAPI.registerWatchSlot({ id = "weather", name = "Weather Slot", accepts = { "standard" },
        price = { rent = 80, days = 7, buy = 600 } })
    local def = W.modules.weather
    check(W.moduleDrain(def) == 55, "moduleDrains overrides a third-party module's drain")
    local slot = W.slotById.weather
    check(W.slotModeValue(slot) == 3, "addonSlots overrides SlotAddon for that slot")
    require "MinidoracatWatch_Pay"
    F.load("server/MinidoracatWatch_Economy.lua")
    local plan = W.Econ.planValues(slot, false)
    check(plan.permanentEnabled == false and plan.rentalEnabled == true and plan.rentalPrice == 90
        and plan.permanentPrice == 600, "Economy plan uses the per-slot settings, unset fields fall back to SlotAddon*")
    Cfg.save({ addonSlots = {} })
    check(W.slotModeValue(slot) == 1 and W.Econ.planValues(slot, false).rentalPrice == 80,
        "without a per-slot entry the slot follows SlotAddon again")
    -- 客戶端：收廣播、只收認得的形狀
    F.mode = "client"
    F.load("client/MinidoracatWatch_AdminUI.lua")
    local AU = MinidoracatWatchAdminUI
    AU.onLists({ moduleDrains = { weather = 33, bad = "x" }, addonSlots = { weather = { mode = "off", rentPrice = "9" },
        other = { mode = "nope" } } })
    check(W.listValue("moduleDrains").weather == 33 and W.listValue("moduleDrains").bad == nil, "client keeps valid drains")
    check(W.slotModeValue(slot) == 4 and W.listValue("addonSlots").weather.rentPrice == nil
        and W.listValue("addonSlots").other == nil, "client keeps valid slot entries only")
    AU.onLists({ moduleDrains = { weather = 33 }, addonSlots = { weather = { mode = "econ", buy = false, card = true } } })
    local we = W.listValue("addonSlots").weather
    check(we.buy == false and we.card == true and W.slotCardAlso(slot) == true,
        "client keeps false booleans and the per-slot card switch")
    check(W.moduleDrain(def) == 33, "client drain factor follows the server lists")
    -- 齒輪分類：主 MOD 太舊（< 3）就不註冊
    MinidoracatMiniMapAPI = { settingsApiVersion = 2, registerSettingsSection = function() return true end }
    AU.register()
    check(AU.registered == false, "settings category needs settingsApiVersion >= 3")
    local got = nil
    MinidoracatMiniMapAPI = { settingsApiVersion = 4, registerSettingsSection = function(id, spec) got = spec; return true end }
    AU.register()
    admin.pn, plain.pn = 0, 1
    check(AU.registered and got and got.visible(0) == false, "category hidden from a client without the permission role")
    check(got.icon == "settings" and got.group == "admin" and got.order == 12,
        "category spec carries the v5 icon/group/order (admin group, order 12)")
    local sv = admin.role
    F.players = { admin, plain }
    check(got.visible(0) == true and got.visible(1) == false, "category visible to the admin only")
    admin.role = sv
    F.mode = "server"
end

-- ===== 8. 取得方式的數量套到分佈表 =====
do
    local list = {}
    for name in pairs(L.TABLES) do list[name] = { items = { "Base.Spoon", 5 } } end
    resetSandbox()
    local sig = L.signature()
    check(sig == "1111111111|331", "loot signature carries the three amounts (cards default to very few)")
    L.apply(list, sig)
    local function weight(tbl, item)
        local items = list[tbl].items
        for i = 1, #items, 2 do if items[i] == item then return items[i + 1] end end
        return nil
    end
    check(weight("ElectronicStoreMisc", "MinidoracatWatch.Module_Ledger") == 1, "normal amount keeps the base weight")
    check(math.abs(weight("ElectronicStoreMisc", W.CARD_TYPES.ext) - 0.025) < 1e-12, "cards default to very few: x0.25")
    NATIVE["MinidoracatWatch.LootModuleAmount"] = 1
    NATIVE["MinidoracatWatch.LootCardAmount"] = 4
    NATIVE["MinidoracatWatch.LootWatchAmount"] = 2
    sig = L.signature()
    L.apply(list, sig)
    check(sig == "1111111111|214", "signature follows the native options")
    check(weight("ElectronicStoreMisc", "MinidoracatWatch.Module_Ledger") == 0.25, "very few modules: x0.25")
    check(weight("ElectronicStoreMisc", W.CARD_TYPES.ext) == 0.2, "many cards: x2")
    check(weight("StoreDisplayWatches", W.watchType("ValuTech")) == 2, "few watches: x0.5")
    check(weight("ElectronicStoreMisc", "Base.Spoon") == 5, "vanilla entries untouched")
    local n = 0
    for _, it in ipairs(list.ElectronicStoreMisc.items) do if it == "MinidoracatWatch.Module_Ledger" then n = n + 1 end end
    check(n == 1, "re-applying does not duplicate entries")
    -- 輪詢：數量變了就重排並 Parse
    ProceduralDistributions = { list = list }
    L.applied = "1111111111|333"
    parses = 0
    L.sync(true)
    check(parses == 1 and L.applied == "1111111111|214", "amount change reparses the distributions")
    NATIVE["MinidoracatWatch.LootModuleAmount"], NATIVE["MinidoracatWatch.LootCardAmount"] = 3, 1
    NATIVE["MinidoracatWatch.LootWatchAmount"] = 3
end

-- ===== 9. 沙盒套用：單機 set＋toLua、MP 複本＋sendToServer =====
do
    resetSandbox()
    F.mode = "sp"
    toLuaCalls = 0
    M.applySandbox({ { "FullHours", 48 }, { "DrainOffline", true } })
    check(NATIVE["MinidoracatWatch.FullHours"] == 48 and SB.FullHours == 48 and SB.DrainOffline == true and toLuaCalls == 1,
        "single player: native options set and SandboxVars refreshed (toLua)")
    F.mode = "client"
    resetSandbox()
    sent = nil
    M.applySandbox({ { "ZombieDropCap", 3 } })
    check(sent and sent["MinidoracatWatch.ZombieDropCap"] == 3 and sent["MinidoracatWatch.FullHours"] == 72
        and NATIVE["MinidoracatWatch.ZombieDropCap"] == 1, "MP: a copy with the change is sent; local options wait for the server")
    sent = nil
    M.applySandbox({})
    check(sent == nil, "nothing to send without sandbox changes")
    F.mode = "server"
end

F.finish("test_watch_admin")
