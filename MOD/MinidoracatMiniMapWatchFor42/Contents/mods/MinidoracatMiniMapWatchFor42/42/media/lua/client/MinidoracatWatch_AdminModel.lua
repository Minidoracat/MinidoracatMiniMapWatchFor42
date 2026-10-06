-- MinidoracatWatch_AdminModel.lua（client）：管理員設定視窗的資料與文字（Phase 4）。純函式為主，離線測試直接呼叫；
-- 視窗在 MinidoracatWatch_AdminUI.lua，伺服器端在 server/MinidoracatWatch_Admin.lua。
-- 狀態（base／draft）＝{ sb = { 沙盒鍵 = 值 }, drops = { 掉落規則… }, drains = { 第三方模組 id = % }, addon = { 第三方槽位 id = 設定 } }。
-- 「目前設定一覽」與「這次會改變什麼」都由同一份狀態算出（設計稿 admin.mjs summaryItems 的做法）。
-- 本檔只能寫 ASCII 字串字面值（verify 第 16 項）：所有文字都經翻譯鍵 IGUI_MinidoracatWatch_Admin_*。
require "MinidoracatWatch"
require "MinidoracatWatch_DropData"
local W = MinidoracatWatchCore
local M = {}
MinidoracatWatchAdminModel = M -- 內部表（測試與 E2E 用），不是公開 API

local function T(key, ...) return getText("IGUI_MinidoracatWatch_Admin_" .. key, ...) end
M.T = T

-- ===== 沙盒欄位（順序＝sandbox-options.txt；test_watch_admin.lua 逐項對照型別、範圍、預設）=====
local B, I, E = "bool", "int", "enum"
M.FIELDS = {
    { "Enabled", B, nil, nil, true }, { "MinimapRule", E, 1, 3, 2 }, { "FullHours", I, 1, 720, 72 },
    { "DrainOffline", B, nil, nil, false }, { "DrainPaused", B, nil, nil, false },
    { "RuleArrow", E, 1, 4, 3 }, { "RulePoi", E, 1, 4, 3 }, { "RuleNav", E, 1, 4, 3 }, { "RuleShare", E, 1, 4, 3 },
    { "RuleScan", E, 1, 4, 3 }, { "RuleZombie", E, 1, 4, 3 },
    { "SlotExt", E, 1, 4, 3 }, { "SlotAdv", E, 1, 4, 3 }, { "SlotCore", E, 1, 4, 3 }, { "SlotAddon", E, 1, 4, 1 },
    { "SlotExtBuy", B, nil, nil, true }, { "SlotExtBuyPrice", I, 1, 1000000000, 400 },
    { "SlotExtRent", B, nil, nil, true }, { "SlotExtRentPrice", I, 1, 1000000000, 60 },
    { "SlotAdvBuy", B, nil, nil, true }, { "SlotAdvBuyPrice", I, 1, 1000000000, 1200 },
    { "SlotAdvRent", B, nil, nil, true }, { "SlotAdvRentPrice", I, 1, 1000000000, 150 },
    { "SlotCoreBuy", B, nil, nil, true }, { "SlotCoreBuyPrice", I, 1, 1000000000, 2400 },
    { "SlotCoreRent", B, nil, nil, true }, { "SlotCoreRentPrice", I, 1, 1000000000, 300 },
    { "SlotAddonBuy", B, nil, nil, true }, { "SlotAddonBuyPrice", I, 1, 1000000000, 600 },
    { "SlotAddonRent", B, nil, nil, true }, { "SlotAddonRentPrice", I, 1, 1000000000, 80 },
    { "PayCurrency", E, 1, 2, 1 }, { "PayRentDays", I, 1, 365, 7 }, { "PayRetryHours", I, 0, 168, 24 },
    { "PayReminderHours", I, 0, 168, 24 }, { "PayAutoRenew", B, nil, nil, true }, { "NeedScrewdriver", B, nil, nil, true },
    { "ScanRadius", I, 1, 1000, 60 }, { "DetectRadius", I, 1, 1000, 40 }, { "MilDetectRadius", I, 1, 1000, 80 },
    { "CommRange", I, 1, 50000, 2000 }, { "LongCommRange", I, 1, 50000, 8000 },
    { "DrainCompass", I, 0, 1000, 10 }, { "DrainLedger", I, 0, 1000, 10 }, { "DrainGPS", I, 0, 1000, 25 },
    { "DrainComm", I, 0, 1000, 25 }, { "DrainScan", I, 0, 1000, 25 }, { "DrainDetect", I, 0, 1000, 50 },
    { "DrainMilDetect", I, 0, 1000, 50 }, { "DrainLongComm", I, 0, 1000, 25 }, { "DrainRelay", I, 0, 1000, 25 },
    { "LootValuTech", B, nil, nil, true }, { "LootPaws", B, nil, nil, true }, { "LootNexus", B, nil, nil, true },
    { "LootSpiffo", B, nil, nil, true }, { "LootRanger", B, nil, nil, true }, { "LootLuthex", B, nil, nil, true },
    { "LootBB3000", B, nil, nil, true }, { "LootModules", B, nil, nil, true }, { "LootCards", B, nil, nil, true },
    { "AllowCraft", B, nil, nil, true }, { "ZombieDrops", B, nil, nil, true }, { "ZombieDropCap", I, 1, 5, 1 },
    { "RuleLight", E, 1, 2, 1 }, { "LightRadius", I, 1, 20, 4 }, { "LightDrain", I, 0, 1000, 100 },
    { "LootWatchAmount", E, 1, 4, 3 }, { "LootModuleAmount", E, 1, 4, 3 }, { "LootCardAmount", E, 1, 4, 3 },
    -- 充電（feat/charge 的沙盒鍵）：選用欄位＝這個沙盒選項存在才顯示、才比對（還沒合併的分支裡沒有）
    { "ChargeCar", B, nil, nil, false, true }, { "CarHours", I, 1, 168, 6, true },
    { "ChargeHouse", B, nil, nil, false, true }, { "HouseHours", I, 1, 168, 12, true },
}
M.FIELD = {}
for _, f in ipairs(M.FIELDS) do
    M.FIELD[f[1]] = { key = f[1], kind = f[2], min = f[3], max = f[4], default = f[5], optional = f[6] == true }
end

-- 功能規則（設計稿 FEATURE_RULES）：沙盒值 → free／watch／module／off
M.FEATURES = {
    { id = "minimap", key = "MinimapRule", values = { "free", "watch", "off" } },
    { id = "arrow", key = "RuleArrow" }, { id = "poi", key = "RulePoi" }, { id = "nav", key = "RuleNav" },
    { id = "share", key = "RuleShare" }, { id = "scan", key = "RuleScan" }, { id = "zombie", key = "RuleZombie" },
    { id = "light", key = "RuleLight", values = { "module", "off" } },
}
local RULE4 = { "free", "watch", "module", "off" }
for _, f in ipairs(M.FEATURES) do f.values = f.values or RULE4 end

-- 付費槽位（內建三種＋其他 MOD 的預設）：沙盒鍵前綴
M.TIERS = { { id = "ext", key = "SlotExt" }, { id = "adv", key = "SlotAdv" }, { id = "core", key = "SlotCore" } }
M.MODES = { "free", "card", "econ", "off" } -- 沙盒值 1..4
-- 內建模組的耗電鍵（面板順序）；照明另外是 LightDrain（開燈時）
M.DRAINS = { { "compass", "DrainCompass" }, { "ledger", "DrainLedger" }, { "gps", "DrainGPS" }, { "comm", "DrainComm" },
    { "scan", "DrainScan" }, { "detect", "DrainDetect" }, { "mildetect", "DrainMilDetect" },
    { "longcomm", "DrainLongComm" }, { "relay", "DrainRelay" } }
M.LOOT_STYLES = { "ValuTech", "Paws", "Nexus", "Spiffo", "Ranger", "Luthex", "BB3000" } -- 沙盒 Loot<款>
M.PRESETS = { "easy", "standard", "hard" }

-- ===== 讀目前的值 =====
-- 原生沙盒值優先（單機的原版沙盒介面只 set 原生選項、不更新 SandboxVars，SandboxOptions.java:572-582）
-- 選用欄位（充電）在這個版本沒有對應的沙盒選項時回 nil：畫面不顯示、一覽不列、不比對
function M.current(key)
    local f = M.FIELD[key]
    local opts = getSandboxOptions and getSandboxOptions()
    local o = opts and opts:getOptionByName("MinidoracatWatch." .. key)
    local v
    if o then
        v = o:getValue()
    else
        v = W.sandbox(key, nil)
        if v == nil then
            if f.optional then return nil end
            v = f.default
        end
    end
    if f.kind == B then return v == true end
    v = tonumber(v)
    if not v then return f.default end
    return v
end

local function copyDrops(list)
    local out = {}
    for i, r in ipairs(list or {}) do
        local outfits = nil
        if type(r.outfits) == "table" then
            outfits = {}
            for j, o in ipairs(r.outfits) do outfits[j] = o end
        end
        out[i] = { group = r.group, item = r.item, chance = r.chance, outfits = outfits }
    end
    return out
end
M.copyDrops = copyDrops

-- st＝伺服器的 adminState（或單機 W.Admin.state()）：rev、zombieDrops、moduleDrains、addonSlots
function M.readBase(st)
    local s = { sb = {}, drops = copyDrops(st and st.zombieDrops), drains = {}, addon = {} }
    for _, f in ipairs(M.FIELDS) do s.sb[f[1]] = M.current(f[1]) end
    for id, v in pairs(st and st.moduleDrains or {}) do
        if type(id) == "string" and type(v) == "number" then s.drains[id] = v end
    end
    for id, e in pairs(st and st.addonSlots or {}) do
        if type(id) == "string" and type(e) == "table" and W.MODE_VALUE[e.mode] then
            s.addon[id] = { mode = e.mode, buy = e.buy, buyPrice = e.buyPrice, rent = e.rent, rentPrice = e.rentPrice }
        end
    end
    return s
end

function M.copy(s)
    local out = { sb = {}, drops = copyDrops(s.drops), drains = {}, addon = {} }
    for k, v in pairs(s.sb) do out.sb[k] = v end
    for k, v in pairs(s.drains) do out.drains[k] = v end
    for k, e in pairs(s.addon) do
        out.addon[k] = { mode = e.mode, buy = e.buy, buyPrice = e.buyPrice, rent = e.rent, rentPrice = e.rentPrice }
    end
    return out
end

-- 第三方模組／槽位（這次啟動登記的；設定檔裡沒登記的 id 照樣保存、送出，只是畫面上不列）
function M.addonModules()
    local out = {}
    for _, m in ipairs(W.moduleList) do
        if not W.BUILTIN[m.id] then out[#out + 1] = m end
    end
    return out
end
function M.addonSlots()
    local out = {}
    for _, s in ipairs(W.slotList) do
        if s.tier == "addon" then out[#out + 1] = s end
    end
    return out
end
-- 第三方槽位實際生效的設定（逐槽設定，沒寫的欄位照 SlotAddon*）
function M.slotEntry(s, id)
    local e = s.addon[id] or {}
    local function pick(field, key)
        if e[field] ~= nil then return e[field] end
        return s.sb[key]
    end
    return { mode = e.mode or M.MODES[s.sb.SlotAddon] or "free", buy = pick("buy", "SlotAddonBuy"),
        buyPrice = pick("buyPrice", "SlotAddonBuyPrice"), rent = pick("rent", "SlotAddonRent"),
        rentPrice = pick("rentPrice", "SlotAddonRentPrice") }
end
function M.addonDrain(s, def)
    local v = s.drains[def.id]
    if type(v) == "number" then return v end
    return def.drain
end

-- ===== 文字 =====
-- 千分位（2,400）
function M.num(n)
    local s = tostring(math.floor(n))
    local out = s
    while true do
        local nx, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
        out = nx
        if k == 0 then break end
    end
    return out
end

function M.moduleName(id)
    local def = W.modules[id]
    return def and getText(def.name) or id
end
function M.featureName(id) return getText("IGUI_MinidoracatWatch_Feature_" .. id) end
function M.sbLabel(key) return getText("Sandbox_MinidoracatWatch_" .. key) end

function M.ruleId(feature, value) return feature.values[value] end
function M.ruleText(feature, value)
    local r = feature.values[value]
    if r == "module" then return T("Rule_module", M.moduleName(W.PROVIDERS[feature.id][1])) end
    return T("Rule_" .. tostring(r))
end

function M.currencyName(s) return getText("Sandbox_MinidoracatWatch_PayCurrency_option" .. tostring(s.sb.PayCurrency)) end

-- 一個付費槽位的開啟方式（白話）；e＝{ mode, buy, buyPrice, rent, rentPrice }
function M.tierText(s, e, econReady)
    if e.mode ~= "econ" then return T("Mode_" .. e.mode) end
    if not econReady then return T("Mode_noEcon") end
    local cur, days = M.currencyName(s), tostring(s.sb.PayRentDays)
    if e.rent and e.buy then return T("Mode_rentBuy", days, M.num(e.rentPrice), cur, M.num(e.buyPrice)) end
    if e.rent then return T("Mode_rent", days, M.num(e.rentPrice), cur) end
    if e.buy then return T("Mode_buy", M.num(e.buyPrice), cur) end
    return T("Mode_none")
end
function M.tierEntry(s, key)
    return { mode = M.MODES[s.sb[key]] or "free", buy = s.sb[key .. "Buy"], buyPrice = s.sb[key .. "BuyPrice"],
        rent = s.sb[key .. "Rent"], rentPrice = s.sb[key .. "RentPrice"] }
end
function M.slotName(slot) return getText(slot.name) end

-- 掉落規則寫成一句話（設計稿 ruleSentence）：「[殭屍類型]每隻有 [機率]% 機率掉落[掉落物]」
function M.groupName(id) return T("Group_" .. tostring(id)) end
function M.itemName(id)
    if id == "watch:any" then return T("Item_watchAny") end
    if id == "mod:any" then return T("Item_modAny") end
    if id == "battery" then return getItemNameFromFullType(W.BATTERY_TYPE) end
    local kind, rest = string.match(tostring(id), "^(%a+):([%w_]+)$")
    if kind == "watch" and W.STYLE_BY_ID[rest] then return getItemNameFromFullType(W.watchType(W.STYLE_BY_ID[rest])) end
    if kind == "mod" then return M.moduleName(rest) end
    if kind == "card" and W.CARD_TYPES[rest] then return getItemNameFromFullType(W.CARD_TYPES[rest]) end
    return tostring(id)
end
function M.outfitsText(r)
    if type(r.outfits) ~= "table" or #r.outfits == 0 then return T("Rule_noOutfit") end
    return table.concat(r.outfits, ", ")
end
function M.chanceText(c)
    if c == math.floor(c) then return tostring(math.floor(c)) end
    return tostring(math.floor(c * 1000 + 0.5) / 1000)
end
function M.ruleSentence(r)
    local who = r.group == "custom" and T("Rule_custom", M.outfitsText(r)) or M.groupName(r.group)
    return T("Rule_sentence", who, M.chanceText(r.chance), M.itemName(r.item))
end
-- 下拉選單：殭屍類型、掉落物（設計稿 DROP_ITEMS 的順序；模組照登記順序，含第三方）
function M.groupOptions()
    local out = {}
    for i, id in ipairs(W.DROP_GROUP_IDS) do out[i] = { id = id, label = M.groupName(id) } end
    return out
end
function M.itemOptions()
    local out = { { id = "watch:any", label = M.itemName("watch:any") } }
    for _, s in ipairs(W.STYLE_IDS) do out[#out + 1] = { id = "watch:" .. s, label = M.itemName("watch:" .. s) } end
    out[#out + 1] = { id = "mod:any", label = M.itemName("mod:any") }
    for _, m in ipairs(W.moduleList) do out[#out + 1] = { id = "mod:" .. m.id, label = M.moduleName(m.id) } end
    for _, t in ipairs(W.CARD_TIERS) do out[#out + 1] = { id = "card:" .. t, label = M.itemName("card:" .. t) } end
    out[#out + 1] = { id = "battery", label = M.itemName("battery") }
    return out
end

-- 續航試算（設計稿 runtimeHours／fmtH）：滿電小時 ÷（1＋Σ耗電%÷100，開燈再加照明%），節能核心 ×2
M.SAMPLE_THREE = { "compass", "gps", "scan" }
M.SAMPLE_FULL = { "compass", "gps", "light", "scan", "mildetect", "relay" }
function M.drainOf(s, id)
    for _, d in ipairs(M.DRAINS) do
        if d[1] == id then return s.sb[d[2]] or 0 end
    end
    return 0
end
function M.runtime(s, mods, lit)
    local pct, eco = 0, false
    for _, id in ipairs(mods) do
        pct = pct + M.drainOf(s, id)
        if id == "eco" then eco = true end
    end
    if lit then pct = pct + (s.sb.LightDrain or 0) end
    return s.sb.FullHours / (1 + pct / 100) * (eco and 2 or 1)
end
function M.hoursText(h)
    local n = math.floor(h + 0.5)
    if n < 48 then return T("Hours", tostring(n)) end
    local d, r = math.floor(n / 24), n % 24
    if r == 0 then return T("Days", tostring(d)) end
    return T("DaysHours", tostring(d), tostring(r))
end

-- ===== 目前設定一覽（設計稿 summaryItems）=====
-- econReady＝伺服器的 Economy 整合是 READY（W.econStatus）；充電還沒實作，不列。
function M.summary(s, econReady)
    if not s.sb.Enabled then return { T("Sum_Disabled") } end
    local out = {}
    for _, f in ipairs(M.FEATURES) do
        out[#out + 1] = T("Sum_Line", M.featureName(f.id), M.ruleText(f, s.sb[f.key]))
    end
    for _, t in ipairs(M.TIERS) do
        out[#out + 1] = T("Sum_Line", getText("IGUI_MinidoracatWatch_Slot_" .. t.id), M.tierText(s, M.tierEntry(s, t.key), econReady))
    end
    for _, slot in ipairs(M.addonSlots()) do
        out[#out + 1] = T("Sum_Line", M.slotName(slot), M.tierText(s, M.slotEntry(s, slot.id), econReady))
    end
    out[#out + 1] = T("Sum_Battery", tostring(s.sb.FullHours), T(s.sb.DrainOffline and "Sum_OfflineOn" or "Sum_OfflineOff"),
        T(s.sb.DrainPaused and "Sum_PauseOn" or "Sum_PauseOff"))
    local tuned = 0
    for _, d in ipairs(M.DRAINS) do
        if s.sb[d[2]] ~= M.FIELD[d[2]].default then tuned = tuned + 1 end
    end
    for _, m in ipairs(M.addonModules()) do
        if M.addonDrain(s, m) ~= m.drain then tuned = tuned + 1 end
    end
    if s.sb.LightDrain ~= M.FIELD.LightDrain.default then tuned = tuned + 1 end
    out[#out + 1] = T("Sum_Drains", tuned > 0 and T("Sum_DrainsTuned", tostring(tuned)) or T("Sum_DrainsDefault"),
        tostring(s.sb.LightDrain))
    -- 充電（設計稿 summaryItems 的 charge；沙盒有充電選項時才列）
    if s.sb.ChargeCar ~= nil and s.sb.ChargeHouse ~= nil then
        local car, house = s.sb.ChargeCar, s.sb.ChargeHouse
        local how
        if car and house then how = T("Charge_both", tostring(s.sb.CarHours), tostring(s.sb.HouseHours))
        elseif car then how = T("Charge_car", tostring(s.sb.CarHours))
        elseif house then how = T("Charge_house", tostring(s.sb.HouseHours))
        else how = T("Charge_none") end
        out[#out + 1] = T("Sum_Charge", how)
    end
    local styles = 0
    for _, st in ipairs(M.LOOT_STYLES) do
        if s.sb["Loot" .. st] then styles = styles + 1 end
    end
    if styles == #M.LOOT_STYLES then
        out[#out + 1] = T("Sum_LootAll", tostring(styles))
    elseif styles > 0 then
        out[#out + 1] = T("Sum_LootSome", tostring(styles))
    else
        out[#out + 1] = T("Sum_LootNone")
    end
    if s.sb.ZombieDrops then
        out[#out + 1] = T("Sum_Drops", tostring(#s.drops), tostring(s.sb.ZombieDropCap))
    else
        out[#out + 1] = T("Sum_DropsOff")
    end
    return out
end

-- ===== 這次會改變什麼（原本 → 改成）=====
function M.valueText(key, v)
    local f = M.FIELD[key]
    if f.kind == B then return T(v and "On" or "Off") end
    if f.kind == E then return getText("Sandbox_MinidoracatWatch_" .. key .. "_option" .. tostring(v)) end
    return M.num(v)
end

-- 改了會讓自動續租暫停、要玩家重新同意的欄位（Economy 的設計，Phase 6 D3）：租金、幣別、天數
local TERMS = { SlotExtRentPrice = true, SlotAdvRentPrice = true, SlotCoreRentPrice = true, SlotAddonRentPrice = true,
    PayCurrency = true, PayRentDays = true }
local RULE_KEYS = {}
for _, f in ipairs(M.FEATURES) do RULE_KEYS[f.key] = f end

local function sameEntry(a, b)
    if a == nil or b == nil then return a == b end
    return a.mode == b.mode and a.buy == b.buy and a.buyPrice == b.buyPrice and a.rent == b.rent
        and a.rentPrice == b.rentPrice
end

-- 回 lines（白話）, priceWarn（租約條款改了）, count（改了幾項，給「有 N 項修改」）
function M.diff(a, b)
    local lines, warn = {}, false
    for _, f in ipairs(M.FIELDS) do
        local k = f[1]
        if a.sb[k] ~= b.sb[k] then
            local feature = RULE_KEYS[k]
            local line
            if feature then
                line = T("Diff_Line", M.featureName(feature.id), M.ruleText(feature, a.sb[k]), M.ruleText(feature, b.sb[k]))
                local to = feature.values[b.sb[k]]
                if to == "module" or to == "off" then line = T("Diff_Note", line, T("Note_rule_" .. to)) end
            else
                line = T("Diff_Line", M.sbLabel(k), M.valueText(k, a.sb[k]), M.valueText(k, b.sb[k]))
                if k == "FullHours" then line = T("Diff_Note", line, T("Note_FullHours")) end
            end
            lines[#lines + 1] = line
            if TERMS[k] then warn = true end
        end
    end
    -- 第三方模組耗電
    local seen = {}
    for _, m in ipairs(M.addonModules()) do
        seen[m.id] = true
        local x, y = M.addonDrain(a, m), M.addonDrain(b, m)
        if x ~= y then lines[#lines + 1] = T("Diff_Drain", M.moduleName(m.id), tostring(x), tostring(y)) end
    end
    for id, v in pairs(b.drains) do
        if not seen[id] and a.drains[id] ~= v then
            lines[#lines + 1] = T("Diff_Drain", id, tostring(a.drains[id] or "-"), tostring(v))
        end
    end
    -- 第三方槽位逐槽設定
    for _, slot in ipairs(M.addonSlots()) do
        if not sameEntry(a.addon[slot.id], b.addon[slot.id]) then
            local x, y = M.slotEntry(a, slot.id), M.slotEntry(b, slot.id)
            lines[#lines + 1] = T("Diff_Line", M.slotName(slot), M.tierText(a, x, true), M.tierText(b, y, true))
            if b.addon[slot.id] and y.mode == "econ" and (x.rentPrice ~= y.rentPrice) then warn = true end
        end
    end
    -- 掉落規則：以句子比對（同一句出現幾次就算幾條）
    local count = {}
    for _, r in ipairs(a.drops) do
        local t = M.ruleSentence(r)
        count[t] = (count[t] or 0) + 1
    end
    local added = {}
    for _, r in ipairs(b.drops) do
        local t = M.ruleSentence(r)
        if (count[t] or 0) > 0 then count[t] = count[t] - 1 else added[#added + 1] = t end
    end
    for _, r in ipairs(a.drops) do
        local t = M.ruleSentence(r)
        if (count[t] or 0) > 0 then
            count[t] = count[t] - 1
            lines[#lines + 1] = T("Diff_DropDel", t)
        end
    end
    for _, t in ipairs(added) do lines[#lines + 1] = T("Diff_DropAdd", t) end
    local n = #lines
    if warn then lines[#lines + 1] = T("Diff_PriceWarn") end
    return lines, warn, n
end

-- ===== 快速方案（設計稿 PRESETS）=====
function M.applyPreset(s, id)
    local hours = { easy = 168, standard = 72, hard = 24 }
    if not hours[id] then return false end
    s.sb.FullHours = hours[id]
    s.sb.MinimapRule = 2
    for _, f in ipairs(M.FEATURES) do
        if f.id ~= "minimap" and f.id ~= "light" then s.sb[f.key] = id == "easy" and 1 or 3 end
    end
    if id ~= "easy" then s.sb.RuleLight = 1 end
    if id == "easy" then
        for _, t in ipairs(M.TIERS) do s.sb[t.key] = 1 end
        s.sb.SlotAddon = 1
        for _, e in pairs(s.addon) do e.mode = "free" end
    end
    return true
end

-- ===== 驗證（送出前；伺服器另外再驗）=====
function M.validInt(key, v)
    local f = M.FIELD[key]
    return type(v) == "number" and v == math.floor(v) and v >= f.min and v <= f.max
end
function M.validChance(c) return type(c) == "number" and c == c and c >= 0 and c <= 100 end
-- 自訂服裝欄的文字 → 清單（逗號或空白分隔；名字只收英數、底線、連字號，和伺服器一致）；不合法回 nil
function M.parseOutfits(text)
    local out = {}
    for part in string.gmatch(tostring(text or ""), "[^,%s]+") do
        if not string.match(part, "^[%w_%-]+$") or #part > 64 then return nil end
        out[#out + 1] = part
    end
    if #out == 0 or #out > 64 then return nil end
    return out
end
-- 回問題數（0＝可以送）
function M.problems(s)
    local n = 0
    for _, f in ipairs(M.FIELDS) do
        local v = s.sb[f[1]]
        if v ~= nil or not f[6] then -- 選用欄位在這個版本沒有沙盒選項時略過
            if f[2] == I and not M.validInt(f[1], v) then n = n + 1 end
            if f[2] == E and not (type(v) == "number" and v >= f[3] and v <= f[4]) then n = n + 1 end
            if f[2] == B and type(v) ~= "boolean" then n = n + 1 end
        end
    end
    for _, r in ipairs(s.drops) do
        if not M.validChance(r.chance) then n = n + 1 end
        if r.group == "custom" and not (type(r.outfits) == "table" and #r.outfits > 0) then n = n + 1 end
    end
    for _, v in pairs(s.drains) do
        if not (type(v) == "number" and v == math.floor(v) and v >= 0 and v <= 1000) then n = n + 1 end
    end
    return n
end

-- ===== 送出 =====
-- 改了哪些沙盒鍵：{ { key, value } … }（照 FIELDS 順序）
function M.sandboxChanges(a, b)
    local out = {}
    for _, f in ipairs(M.FIELDS) do
        if a.sb[f[1]] ~= b.sb[f[1]] then out[#out + 1] = { f[1], b.sb[f[1]] } end
    end
    return out
end

local function dropsEqual(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        local x, y = a[i], b[i]
        if x.group ~= y.group or x.item ~= y.item or x.chance ~= y.chance then return false end
        local ox, oy = x.outfits or {}, y.outfits or {}
        if #ox ~= #oy then return false end
        for j = 1, #ox do if ox[j] ~= oy[j] then return false end end
    end
    return true
end
local function mapEqual(a, b, same)
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k, v in pairs(b) do if not same(a[k], v) then return false end end
    return true
end
local function eq(x, y) return x == y end

-- 伺服器 adminSet 的 args：只帶有改的清單區段（設定檔的形狀）
function M.payload(a, b, rev, reason, changes)
    local lists = {}
    if not dropsEqual(a.drops, b.drops) then
        local out = {}
        for i, r in ipairs(b.drops) do
            out[i] = { group = r.group, item = r.item, chance = r.chance }
            if r.group == "custom" then out[i].outfits = r.outfits end
        end
        lists.zombieDrops = out
    end
    if not mapEqual(a.drains, b.drains, eq) then lists.moduleDrains = b.drains end
    if not mapEqual(a.addon, b.addon, sameEntry) then lists.addonSlots = b.addon end
    return { expected = rev, reason = reason, changes = changes, lists = lists, sandbox = #M.sandboxChanges(a, b) }
end

-- 套用沙盒（伺服器 adminResult 成功之後）：
--   MP：照原版沙盒介面（ISServerSandboxOptionsUI.lua:762-771）複製一份、改值、sendToServer；伺服器 Java 端驗權限、
--       toLua、存 <伺服器名>_SandboxVars.lua、廣播給所有連線（GameServer.java:1710-1726，客戶端 load＋toLua＝GameClient.java:2772-2779）。
--   單機：直接 set 原生選項再 toLua（SandboxOptions.java:279-285）讓 SandboxVars 立刻跟上；存檔時寫進 map_sand.bin
--       （GameWindow.save，GameWindow.java:1032-1040）。
function M.applySandbox(changes)
    if #changes == 0 then return end
    if isClient() then
        local copy = SandboxOptions.new()
        copy:copyValuesFrom(getSandboxOptions())
        for _, c in ipairs(changes) do copy:set("MinidoracatWatch." .. c[1], c[2]) end
        copy:sendToServer()
    else
        local opts = getSandboxOptions()
        for _, c in ipairs(changes) do opts:set("MinidoracatWatch." .. c[1], c[2]) end
        opts:toLua()
    end
end

return M
