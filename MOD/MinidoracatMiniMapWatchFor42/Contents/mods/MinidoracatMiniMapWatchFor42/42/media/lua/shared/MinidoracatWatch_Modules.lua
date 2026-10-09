-- MinidoracatWatch_Modules.lua（shared）：模組與槽位登記、對外 API、模組狀態快取、功能閘門決策、
-- 安裝／拆下與解鎖卡（伺服器／單機的唯一突變點）。
--
-- 資料模型
--   錶的 modData[SLOTS_KEY] = { [slotId] = { id = 模組 id, item = 模組物品完整類型, md = 模組物品 modData 的複本或 nil } }
--     模組跟著錶走（交易、換手時 ISClothingExtraAction 整份複製 modData）；安裝＝物品離開背包、紀錄進錶，
--     拆下＝紀錄離開錶、以同類型建回物品並還原 modData（物品數量守恆）。
--   解鎖紀錄：伺服器全域 ModData[UNLOCK_TABLE][帳號][驗證鍵] = { [slotId] = true }，帳號與驗證鍵由 W.account 決定
--     （讀取、用卡寫入、推播都經過它）。綁帳號，換戴別支錶也能用；玩家 modData 會被客戶端整表覆蓋
--     （ObjectModDataPacket.java:50-71），全域 ModData 客戶端改不到（GlobalModDataPacket.java:45-56）。
--     MP 客戶端只拿到自己的那份（登入與變更時由伺服器送，W.clientUnlocks）。
-- 由 MinidoracatWatch.lua 結尾 require（shared 依檔名順序先載入核心）；這裡不反向 require，免得 Kahlua 警告 recursive require。
local W = MinidoracatWatchCore

W.SLOTS_KEY = "MinidoracatWatchSlots"
W.UNLOCK_TABLE = "MinidoracatWatchUnlocks"
W.CMD_MODULE = "module"
W.CMD_UNLOCK = "unlock"
W.CMD_UNLOCKS_REQ = "unlocksReq"
W.CMD_UNLOCKS = "unlocks"

W.RULE_MODULE = "module"
W.CLASSES = { standard = true, advanced = true, core = true }
W.MAX_ADDON_SLOTS = 6 -- 面板「其他 MOD」那一列放得下的數量

W.FAIL_MODULE = "IGUI_MinidoracatWatch_ModuleFailed"
W.FAIL_SCREWDRIVER = "IGUI_MinidoracatWatch_NeedScrewdriver"
W.FAIL_SLOT_INVALID = "IGUI_MinidoracatWatch_SlotNotOpen"
W.FAIL_SLOT_FULL = "IGUI_MinidoracatWatch_SlotFull"
W.FAIL_SLOT_EMPTY = "IGUI_MinidoracatWatch_SlotEmpty"
W.FAIL_CLASS = "IGUI_MinidoracatWatch_SlotWrongClass"
W.FAIL_UNLOCK = "IGUI_MinidoracatWatch_UnlockFailed"
W.FAIL_UNLOCKED = "IGUI_MinidoracatWatch_AlreadyUnlocked"
W.FAIL_UNLOCK_ACCOUNT = "IGUI_MinidoracatWatch_UnlockNoAccount"
for _, k in ipairs({ W.FAIL_MODULE, W.FAIL_SCREWDRIVER, W.FAIL_SLOT_INVALID, W.FAIL_SLOT_FULL, W.FAIL_SLOT_EMPTY,
        W.FAIL_CLASS, W.FAIL_UNLOCK, W.FAIL_UNLOCKED, W.FAIL_UNLOCK_ACCOUNT }) do
    W.FAIL_KEYS[k] = true
end

W.REASON_FEATURE_OFF = "IGUI_MinidoracatWatch_Reason_FeatureOff"
W.REASON_NEED_WATCH = "IGUI_MinidoracatWatch_Reason_NeedWatch"
W.REASON_PAUSED = "IGUI_MinidoracatWatch_Reason_Paused"

-- ===== 沙盒 =====
-- 功能規則：1 不需要錶、2 戴錶就能用、3 需要模組（預設，照設計稿 FEATURE_RULES）、4 關閉。
-- 方向箭頭沒有自己的規則與模組，跟著導航（C.gate 把 arrow 當 nav 判；2026-10-09 使用者裁定）
local RULE_BY_VALUE = { W.RULE_FREE, W.RULE_WATCH, W.RULE_MODULE, W.RULE_OFF }
W.FEATURE_RULE_KEY = { poi = "RulePoi", nav = "RuleNav", share = "RuleShare", scan = "RuleScan", zombie = "RuleZombie" }
function W.featureRule(feature)
    -- 照明只有「需要模組」與「關閉」兩種（設計稿 FEATURE_RULES light 的 opts）：RuleLight 1 需要模組、2 關閉
    if feature == "light" then return W.sandbox("RuleLight", 1) == 2 and W.RULE_OFF or W.RULE_MODULE end
    local key = W.FEATURE_RULE_KEY[feature]
    if not key then return W.RULE_FREE end
    return RULE_BY_VALUE[W.sandbox(key, 3)] or W.RULE_MODULE
end

-- ===== 伺服器設定檔的清單（Phase 4）=====
-- 第三方模組耗電（moduleDrains：[模組 id] = %）與第三方槽位逐槽設定（addonSlots：[槽位 id] = { mode, buy?, buyPrice?,
-- rent?, rentPrice?, card? }）存在伺服器設定檔（server/MinidoracatWatch_Admin.lua 登記區段）。伺服器與單機直接讀設定檔的值；
-- MP 客戶端讀伺服器推來的那份（W.clientLists，登入時要一次、每次變更廣播），閘門與面板才和伺服器一致。
W.CMD_LISTS = "lists"
W.CMD_LISTS_REQ = "listsReq"
-- 管理員設定視窗（server/MinidoracatWatch_Admin.lua）：讀取 get → state、寫回 set → result
W.CMD_ADMIN_GET, W.CMD_ADMIN_STATE = "adminGet", "adminState"
W.CMD_ADMIN_SET, W.CMD_ADMIN_RESULT = "adminSet", "adminResult"
W.clientLists = { moduleDrains = {}, addonSlots = {} }
function W.listValue(name)
    if isClient() then return W.clientLists[name] end
    local Cfg = W.Config
    return Cfg and Cfg.get(name) or nil
end
W.MODE_VALUE = { free = 1, card = 2, econ = 3, off = 4 }
function W.addonSlotCfg(slotId)
    local t = W.listValue("addonSlots")
    local e = t and t[slotId]
    if type(e) == "table" and W.MODE_VALUE[e.mode] then return e end
    return nil
end

-- 槽位開啟方式：1 免費開放、2 解鎖卡、3 經濟系統、4 不開放。經濟系統要伺服器的 Economy 整合是 READY
-- （W.econStatus，MinidoracatWatch_Pay.lua）；Economy 缺席、版本不足、單機時改用解鎖卡。
-- 預設照設計稿 DEFAULT_ADMIN：擴充／進階／核心＝經濟系統，其他 MOD 的槽位＝免費（沙盒 SlotAddon；設定檔有逐槽設定時以它為準）。
W.SLOT_MODE_KEY = { ext = "SlotExt", adv = "SlotAdv", core = "SlotCore", addon = "SlotAddon" }
function W.slotModeValue(slot) -- 沙盒原始值（第三方槽位先看設定檔的逐槽設定）
    local key = W.SLOT_MODE_KEY[slot.tier]
    if not key then return 1 end
    if slot.tier == "addon" then
        local e = W.addonSlotCfg(slot.id)
        if e then return W.MODE_VALUE[e.mode] end
    end
    return W.sandbox(key, slot.tier == "addon" and 1 or 3)
end
function W.slotMode(slot)
    local v = W.slotModeValue(slot)
    if v == 1 then return "free" end
    if v == 4 then return "off" end
    if v == 3 and W.econStatus == "READY" then return "econ" end
    return "card"
end

-- 經濟系統模式「也接受解鎖卡」（沙盒 Slot<級>Card，預設關；第三方槽位先看逐槽設定的 card）
function W.slotCardAlso(slot)
    local key = W.SLOT_MODE_KEY[slot.tier]
    if not key then return false end
    if slot.tier == "addon" then
        local e = W.addonSlotCfg(slot.id)
        if e and e.card ~= nil then return e.card == true end
    end
    return W.sandbox(key .. "Card", false) == true
end
-- 現在能不能用解鎖卡開這個槽位：解鎖卡模式（含沒有 Economy 時的經濟系統），或經濟系統且也接受解鎖卡
function W.acceptsCard(slot)
    local mode = W.slotMode(slot)
    return mode == "card" or (mode == "econ" and W.slotCardAlso(slot))
end

function W.needScrewdriver() return W.sandbox("NeedScrewdriver", true) ~= false end

function W.radius(key, default)
    local r = tonumber(W.sandbox(key, default))
    if not r or r ~= r or r < 1 then return default end
    return r
end

-- ===== 登記 =====
W.modules, W.moduleList, W.moduleByItem, W.watchers = {}, {}, {}, {}
W.slotList, W.slotById = {}, {}

local function validId(id)
    return type(id) == "string" and #id <= 32 and id:match("^[%a][%w_]*$") ~= nil
end
W.validId = validId
local function finite(n, lo, hi) return type(n) == "number" and n == n and n >= lo and n <= hi end

local function reject(what, def, why)
    local id = type(def) == "table" and def.id or nil
    W.log(what .. " rejected (" .. tostring(id) .. "): " .. why)
    return false
end

-- 驗證失敗整筆拒收（fail closed）、記 log 一次；欄位複製進內部表，不留呼叫端的 table
local function registerModule(def)
    if type(def) ~= "table" then return reject("registerWatchModule", def, "def is not a table") end
    if not validId(def.id) then return reject("registerWatchModule", def, "bad id") end
    if W.modules[def.id] then return reject("registerWatchModule", def, "duplicate id") end
    if type(def.name) ~= "string" or def.name == "" then return reject("registerWatchModule", def, "bad name") end
    if not W.CLASSES[def.class] then return reject("registerWatchModule", def, "bad class") end
    if not finite(def.drain, 0, 1000) then return reject("registerWatchModule", def, "bad drain") end
    if type(def.item) ~= "string" or not def.item:match("^[%w_]+%.[%w_]+$") then
        return reject("registerWatchModule", def, "bad item")
    end
    if W.moduleByItem[def.item] then return reject("registerWatchModule", def, "item already used") end
    if def.onStateChanged ~= nil and type(def.onStateChanged) ~= "function" then
        return reject("registerWatchModule", def, "bad onStateChanged")
    end
    local m = { id = def.id, name = def.name, class = def.class, drain = def.drain, item = def.item,
        onStateChanged = def.onStateChanged }
    W.modules[m.id] = m
    W.moduleList[#W.moduleList + 1] = m
    W.moduleByItem[m.item] = m
    if m.onStateChanged then W.watchers[#W.watchers + 1] = m end
    return true
end

local function addSlot(id, name, tier, accepts, price)
    local set = {}
    for _, c in ipairs(accepts) do set[c] = true end
    local s = { id = id, name = name, tier = tier, accepts = set, acceptsList = accepts, price = price }
    W.slotList[#W.slotList + 1] = s
    W.slotById[id] = s
    return s
end

local addonSlots = 0
local function registerSlot(def)
    if type(def) ~= "table" then return reject("registerWatchSlot", def, "def is not a table") end
    if not validId(def.id) then return reject("registerWatchSlot", def, "bad id") end
    if W.slotById[def.id] then return reject("registerWatchSlot", def, "duplicate id") end
    if type(def.name) ~= "string" or def.name == "" then return reject("registerWatchSlot", def, "bad name") end
    if type(def.accepts) ~= "table" or #def.accepts == 0 then return reject("registerWatchSlot", def, "bad accepts") end
    local accepts = {}
    for i, c in ipairs(def.accepts) do
        if not W.CLASSES[c] then return reject("registerWatchSlot", def, "bad accepts") end
        accepts[i] = c
    end
    local p = def.price
    if type(p) ~= "table" or not finite(p.rent, 0, 1e9) or not finite(p.days, 1, 3650) or not finite(p.buy, 0, 1e9) then
        return reject("registerWatchSlot", def, "bad price")
    end
    if addonSlots >= W.MAX_ADDON_SLOTS then return reject("registerWatchSlot", def, "too many slots") end
    addonSlots = addonSlots + 1
    addSlot(def.id, def.name, "addon", accepts, { rent = p.rent, days = p.days, buy = p.buy })
    W.invalidate()
    return true
end

-- ===== 內建：槽位與模組（名稱／類別／耗電照設計稿 data.mjs MODULES）=====
local STD = { "standard" }
addSlot("std1", "IGUI_MinidoracatWatch_Slot_std1", "std", STD)
addSlot("std2", "IGUI_MinidoracatWatch_Slot_std2", "std", STD)
addSlot("std3", "IGUI_MinidoracatWatch_Slot_std3", "std", STD)
addSlot("ext", "IGUI_MinidoracatWatch_Slot_ext", "ext", STD, { rent = 60, days = 7, buy = 400 })
addSlot("adv", "IGUI_MinidoracatWatch_Slot_adv", "adv", { "standard", "advanced" }, { rent = 150, days = 7, buy = 1200 })
addSlot("core", "IGUI_MinidoracatWatch_Slot_core", "core", { "standard", "advanced", "core" },
    { rent = 300, days = 7, buy = 2400 })

-- feature＝這個模組開放的功能（沒有＝不對應功能，例如節能核心）；drainKey＝耗電的沙盒選項
W.BUILTIN = {}
local BUILTIN = {
    { "ledger", "Ledger", "standard", 10, "poi" },
    { "gps", "GPS", "standard", 25, "nav" },
    { "comm", "Comm", "standard", 25, "share" },
    { "scan", "Scan", "standard", 25, "scan" },
    { "detect", "Detect", "standard", 50, "zombie" },
    { "mildetect", "MilDetect", "advanced", 50, "zombie" },
    { "longcomm", "LongComm", "advanced", 25, "share" },
    { "relay", "Relay", "core", 25, "share" },
    { "eco", "Eco", "core", 0, nil },
    -- 照明：裝著不耗電，開燈時另加 LightDrain%（W.drainFactor；沙盒鍵不叫 DrainLight，moduleDrain 才會是 0）
    { "light", "Light", "standard", 0, "light" },
}
for _, b in ipairs(BUILTIN) do
    registerModule({ id = b[1], name = "IGUI_MinidoracatWatch_Module_" .. b[1], class = b[3], drain = b[4],
        item = "MinidoracatWatch.Module_" .. b[2] })
    W.BUILTIN[b[1]] = { feature = b[5], drainKey = "Drain" .. b[2] }
end
-- 每個功能由哪些模組提供（順序＝缺模組時提示哪一個）
W.PROVIDERS = { poi = { "ledger" }, nav = { "gps" }, share = { "comm", "longcomm", "relay" },
    scan = { "scan" }, zombie = { "detect", "mildetect" }, light = { "light" } }

W.CARD_TYPES = { ext = "MinidoracatWatch.UnlockCard_Ext", adv = "MinidoracatWatch.UnlockCard_Adv",
    core = "MinidoracatWatch.UnlockCard_Core", addon = "MinidoracatWatch.UnlockCard_Ext" }
function W.cardType(slot) return W.CARD_TYPES[slot.tier] end

-- 模組耗電（%）：內建模組讀沙盒；第三方讀設定檔 moduleDrains（管理員調整），沒有就用它登記的建議值
function W.moduleDrain(def)
    local b = W.BUILTIN[def.id]
    if not b then
        local t = W.listValue("moduleDrains")
        local v = t and t[def.id]
        if type(v) == "number" and v == v and v >= 0 and v <= 1000 then return v end
        return def.drain
    end
    local v = tonumber(W.sandbox(b.drainKey, def.drain))
    if not v or v ~= v or v < 0 then return def.drain end
    return v
end

-- ===== 管理員設定的權限（Phase 4）=====
-- 和原版沙盒介面同一個權限：SandboxOptions（admin、moderator 有，gm 沒有；Roles.java、封包要求見
-- PacketTypes.java:421 與 :301-311）。單機玩家就是管理員。客戶端拿來決定齒輪分類看不看得到，伺服器收到修改時再查一次。
function W.isSettingsAdmin(player)
    if not isClient() and not isServer() then return true end
    if not player or Capability == nil then return false end
    local ok, res = pcall(function() return player:getRole():hasCapability(Capability.SandboxOptions) end)
    return ok and res == true
end

-- ===== 解鎖紀錄與帳號身分 =====
W.clientUnlocks = {} -- MP 客戶端：[username] = { [slotId] = true }（伺服器送來的）

-- 解鎖名額的帳號（伺服器唯一的身分函式；照家族 conventions.md「玩家身分」與 Economy 權益：帳號鍵＝登入名，
-- SteamID 只當驗證因子）。回 帳號, 驗證鍵；無法驗證回 nil（不能讀、不能用卡）。
-- 伺服器上的 getUsername() 是客戶端送來的：重生與分割畫面加入走 ConnectCoopPacket，只擋空字串與在線重名
-- （ConnectCoopPacket.java:72-97），再直接設成 player.username（GameServer.java:2848），所以改名成離線玩家就能冒名。
-- 連線的登入名在 Lua 拿不到（LuaManager 只在 checkPermissions 內部用 getConnectionFromPlayer，:3056）；
-- SteamID 則來自連線（GameServer.java:2843-2844 setSteamID(connection.getSteamId())），改名帶不走。
--   1. 單機：沒有冒名問題，帳號＝W.seenKey（帳號|本機座位，分割畫面各自一份）、驗證鍵 "sp"。
--   2. MP 的第 2～4 位本機玩家（getPlayerNum ~= 0）：和主玩家共用 SteamID，無從驗證 → nil。
--   3. 名字不是非空字串 → nil。
--   4. no-steam 伺服器（getSteamModeActive() 為 false，LuaManager.java:9359-9364）：沒有驗證因子 → 名字、驗證鍵 "n"。
--      已知殘餘風險：改名成離線玩家仍讀得到對方的名額（README 有寫）。
--   5. Steam 伺服器：驗證鍵＝SteamID 的指紋（IsoPlayer.getSteamID＝IsoPlayer.java:6412；進 Lua 是 double，
--      floor(sid/16) 對 999983 取餘）。冒名者的 SteamID 不同，指紋對不上就讀不到也寫不進別人的名額；
--      同一指紋約 4.8e9 個 SteamID，全域 ModData 任何客戶端都能整表索取（GlobalModData.java:171-196），
--      所以只存指紋、不存 SteamID。SteamID 讀不到或是 0 → nil。
local FP_MOD = 999983
function W.steamMode() return getSteamModeActive() == true end -- 測試與 E2E 可覆寫
function W.account(player)
    if not player then return nil end
    if not isServer() then return W.seenKey(player), "sp" end
    if instanceof(player, "IsoAnimal") or player:getPlayerNum() ~= 0 then return nil end
    local name = player:getUsername()
    if type(name) ~= "string" or name == "" then return nil end
    if not W.steamMode() then return name, "n" end
    local sid = player:getSteamID()
    if type(sid) ~= "number" or sid ~= sid or sid <= 0 or sid == math.huge then return nil end
    local f = math.floor(sid / 16)
    return name, string.format("s%d", f - math.floor(f / FP_MOD) * FP_MOD)
end

function W.unlocksOf(player)
    if isClient() then return W.clientUnlocks[player:getUsername()] end
    local name, key = W.account(player)
    if not name then return nil end
    local t = ModData.getOrCreate(W.UNLOCK_TABLE)[name] -- ModData.java:20
    return type(t) == "table" and t[key] or nil
end

function W.isUnlocked(player, slotId)
    local t = W.unlocksOf(player)
    return type(t) == "table" and t[slotId] == true
end

function W.slotValid(player, slot)
    if slot.orphan then return false end
    local mode = W.slotMode(slot)
    if mode == "free" then return true end
    if mode == "off" then return false end
    if mode == "econ" then return W.payValid(player, slot) or (W.slotCardAlso(slot) and W.isUnlocked(player, slot.id)) end
    return W.isUnlocked(player, slot.id)
end

-- ===== 錶上的模組 =====
function W.slotsOf(watch)
    if not watch or not watch:hasModData() then return nil end
    local t = watch:getModData()[W.SLOTS_KEY]
    if type(t) ~= "table" then return nil end
    return t
end

-- 槽位紀錄（只認得出形狀的；壞資料當空槽）
function W.slotRecord(watch, slotId)
    local slots = W.slotsOf(watch)
    local rec = slots and slots[slotId]
    if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.item) ~= "string" then return nil end
    return rec
end

-- ===== 孤立槽位：提供槽位的 MOD 被移除（這次啟動沒有人登記這個 slotId），錶上還留著模組紀錄 =====
-- 使用者裁定：模組隨時能拆；槽位與付費權益凍結保留（紀錄與解鎖都不刪，MOD 裝回來就恢復）。
-- 孤立槽位一律無效：裡面的模組 paused、不耗電、不能再裝。模組類型也沒登記（提供模組的 MOD 也被移除）時
-- 拆不出物品（applyModuleChange 只建回已登記的類型），這種紀錄不列出、留在錶上。
-- 假槽位依 id 快取（不每次配置）；錶的 modData 是 KahluaTableImpl（LinkedHashMap），pairs 順序＝寫入順序。
local orphanById = {}
function W.orphanSlot(id)
    local s = orphanById[id]
    if not s then
        s = { id = id, name = "IGUI_MinidoracatWatch_Slot_orphan", tier = "orphan", orphan = true,
            accepts = {}, acceptsList = {} }
        orphanById[id] = s
    end
    return s
end

-- 這支錶上拆得下來的孤立槽位（使用者操作與面板掃描時呼叫，不在閘門熱路徑）
function W.orphanSlots(watch)
    local out = {}
    local slots = W.slotsOf(watch)
    if not slots then return out end
    for id in pairs(slots) do
        if type(id) == "string" and not W.slotById[id] then
            local rec = W.slotRecord(watch, id)
            if rec and W.moduleByItem[rec.item] then out[#out + 1] = W.orphanSlot(id) end
        end
    end
    return out
end

-- 錶的耗電倍率：Σ（有效槽位裡、功能沒被關閉的模組耗電%，照明開著時另加 LightDrain%）；節能核心運作時整支錶減半（設計稿 fullRuntime）
function W.drainFactor(player, watch)
    local slots = W.slotsOf(watch)
    if not slots then return 1 end
    local pct, eco, lit = 0, false, false
    for _, slot in ipairs(W.slotList) do
        local rec = slots[slot.id]
        local def = type(rec) == "table" and W.modules[rec.id]
        if def and W.slotValid(player, slot) then
            local b = W.BUILTIN[def.id]
            if not (b and b.feature and W.featureRule(b.feature) == W.RULE_OFF) then
                pct = pct + W.moduleDrain(def)
                if def.id == "eco" then eco = true end
                if def.id == "light" and not lit and W.lightLit(player, watch) then
                    lit = true
                    pct = pct + W.lightDrain()
                end
            end
        end
    end
    local f = 1 + pct / 100
    if eco then f = f / 2 end
    return f
end

-- ===== 狀態快取（閘門與 getWatchModuleState 共用；熱路徑零配置）=====
-- 每位玩家一筆：生效的錶、錶上已知模組與其所在槽位是否有效。期限 1 秒；W.invalidate() 讓所有快取失效
-- （穿脫衣物、安裝／拆下、解鎖、登記槽位）。電量不快取：每次直接讀錶的 modData。
-- 模組清單用平行陣列（ids／states＋n）原地覆寫：不清表、不配置。
local STATUS_TTL_MS = 1000
local statusGen = 0
local statusCache = {}
function W.invalidate() statusGen = statusGen + 1 end
function W.clearStatus() statusCache = {} end

-- SyncClothing 先於物品封包到時，客戶端掛在身上的是臨時建的同 ID 物品（SyncClothingPacket.java:192-199），
-- 它沒有 modData；改讀背包裡同 ID 那件（穿著的物品仍在主背包，IsoGameCharacter.java:3427-3490）。
local function effectiveWatch(player)
    local item, count = W.wornWatch(player)
    if item then
        local real = player:getInventory():getItemWithID(item:getID()) -- ItemContainer.java:3112
        if real then item = real end
    end
    return item, count
end

function W.status(player)
    local now = getTimestampMs()
    local e = statusCache[player]
    if e and e.gen == statusGen and now >= e.at and now - e.at < STATUS_TTL_MS then return e end
    if not e then
        e = { ids = {}, states = {}, n = 0 }
        statusCache[player] = e
    end
    e.gen, e.at = statusGen, now
    local watch, count = effectiveWatch(player)
    e.watch, e.count = watch or false, count
    local n = 0
    local slots = W.slotsOf(watch)
    if slots then
        for _, slot in ipairs(W.slotList) do
            local rec = slots[slot.id]
            if type(rec) == "table" and W.modules[rec.id] then
                n = n + 1
                e.ids[n] = rec.id
                e.states[n] = W.slotValid(player, slot) and "active" or "paused"
            end
        end
        -- 孤立槽位裡的模組一律 paused（槽位凍結）
        for id, rec in pairs(slots) do
            if not W.slotById[id] and type(rec) == "table" and W.modules[rec.id] then
                n = n + 1
                e.ids[n] = rec.id
                e.states[n] = "paused"
            end
        end
    end
    e.n = n
    return e
end

-- 模組在這筆狀態裡：任一份 active＝"active"，否則有 paused＝"paused"，沒裝＝nil
function W.modState(e, id)
    local found = nil
    for i = 1, e.n do
        if e.ids[i] == id then
            if e.states[i] == "active" then return "active" end
            found = "paused"
        end
    end
    return found
end

local function powered(e)
    local c = e.watch and W.power(e.watch) or nil
    return c ~= nil and c > 0
end

-- 優先序照規劃書 §1：disabled＞active＞notRequired＞unpowered＞paused＞missing。
-- 地圖錶系統關閉（Enabled=false）等同沒裝本 MOD：一律 notRequired（和小地圖規則一致，也不套功能規則）。
function W.moduleState(player, id)
    if type(id) ~= "string" or not W.modules[id] or player == nil then return "missing" end
    if not W.enabled() then return "notRequired" end
    local b = W.BUILTIN[id]
    local rule = b and b.feature and W.featureRule(b.feature) or W.RULE_MODULE
    if rule == W.RULE_OFF then return "disabled" end
    local e = W.status(player)
    local on = powered(e)
    local m = on and W.modState(e, id)
    if m == "active" then return "active" end
    if rule == W.RULE_FREE or (rule == W.RULE_WATCH and on) then return "notRequired" end
    if e.watch and not on then return "unpowered" end
    if m == "paused" then return "paused" end
    return "missing"
end

-- 功能閘門的決策（客戶端 gate 與面板功能清單共用）：回 allowed, reasonKey, maxDist。
-- 只有「需要模組」規則套用模組半徑；不需要錶／戴錶就能用時沿用主 MOD 自己的顯示距離。
-- 偵測模組只放行小地圖（surface ~= "world"）；軍規偵測兩種地圖都放行。
function W.featureDecision(player, feature, surface)
    local rule = W.featureRule(feature)
    if not W.enabled() or rule == W.RULE_FREE then return true end
    if rule == W.RULE_OFF then return false, W.REASON_FEATURE_OFF end
    local e = player and W.status(player)
    if not (e and e.watch) then return false, W.REASON_NEED_WATCH end
    local c = W.power(e.watch)
    if c == nil then return false, W.REASON_NO_BATTERY end
    if c <= 0 then return false, W.REASON_DEAD end
    if rule == W.RULE_WATCH then return true end
    if feature == "zombie" then
        if W.modState(e, "mildetect") == "active" then return true, nil, W.radius("MilDetectRadius", 80) end
        if surface == "world" then
            if W.modState(e, "mildetect") == "paused" then return false, W.REASON_PAUSED end
            return false, "IGUI_MinidoracatWatch_Reason_Need_mildetect"
        end
        if W.modState(e, "detect") == "active" then return true, nil, W.radius("DetectRadius", 40) end
    else
        local list = W.PROVIDERS[feature]
        for i = 1, #list do
            if W.modState(e, list[i]) == "active" then
                if feature == "scan" then return true, nil, W.radius("ScanRadius", 60) end
                return true
            end
        end
    end
    local list = W.PROVIDERS[feature]
    for i = 1, #list do
        if W.modState(e, list[i]) == "paused" then return false, W.REASON_PAUSED end
    end
    return false, "IGUI_MinidoracatWatch_Reason_Need_" .. list[1]
end

-- ===== 陣營分享距離（Phase 7；伺服器 registerShareFilter 與面板文案共用）=====
-- 使用者裁定（規劃書 §4 Phase 7）：量分享者到收件者的距離，以兩人中範圍較大的錶為準；兩人都要有運作中的
-- 通訊類模組。範圍（格）是沙盒值；中繼核心不限距離。
W.SHARE_RANGE = { comm = { "CommRange", 2000 }, longcomm = { "LongCommRange", 8000 } }
W.RANGE_UNLIMITED = -1

-- 這位玩家的通訊範圍：中繼核心＝RANGE_UNLIMITED；沒戴錶、沒電、沒有運作中的通訊類模組＝nil
function W.shareRange(player)
    local e = player and W.status(player)
    if not (e and powered(e)) then return nil end
    if W.modState(e, "relay") == "active" then return W.RANGE_UNLIMITED end
    local best = nil
    for id, k in pairs(W.SHARE_RANGE) do
        if W.modState(e, id) == "active" then
            local r = W.radius(k[1], k[2])
            if not best or r > best then best = r end
        end
    end
    return best
end

-- 伺服器轉送一筆分享給這位收件者嗎（MP 伺服器上 status 讀的是伺服器自己的穿戴與錶的 modData，不信客戶端）。
-- 總開關關、不需要錶＝放行；關閉＝不轉；戴錶就能用＝兩人都戴著有電的錶、不限距離；需要模組＝上述距離規則。
-- 距離用兩人當下的位置（歐氏距離，剛好等於範圍也算在內）；分割畫面每位玩家各自是一個 IsoPlayer、各自判斷。
function W.shareAllowed(sender, recipient)
    local rule = W.featureRule("share")
    if not W.enabled() or rule == W.RULE_FREE then return true end
    if rule == W.RULE_OFF or not sender or not recipient then return false end
    if rule == W.RULE_WATCH then
        return W.featureDecision(sender, "share") == true and W.featureDecision(recipient, "share") == true
    end
    local a, b = W.shareRange(sender), W.shareRange(recipient)
    if not (a and b) then return false end
    if a == W.RANGE_UNLIMITED or b == W.RANGE_UNLIMITED then return true end
    local r = math.max(a, b)
    local dx, dy = sender:getX() - recipient:getX(), sender:getY() - recipient:getY()
    return dx * dx + dy * dy <= r * r
end

-- 主 MOD 的伺服器分享過濾 API（主 MOD 的 server 檔在 MP 客戶端也會載入，GameLoadingState.java:148，所以客戶端
-- 也用這個判斷要不要提示管理員）。不足回 nil。
function W.shareApi()
    local S = MinidoracatMiniMapServerAPI
    if type(S) == "table" and type(S.shareApiVersion) == "number" and S.shareApiVersion >= 1
            and type(S.registerShareFilter) == "function" then
        return S
    end
    return nil
end

-- onStateChanged：每秒比對一次（MP 伺服器在扣電迴圈、客戶端與單機在客戶端迴圈），只在狀態改變時呼叫
-- def.onStateChanged(player, newState, oldState)。第一次看到這位玩家時 oldState＝nil。拋錯只 log 一次。
-- 紀錄記下是哪個 IsoPlayer：同一座位換了新物件（重生、分割畫面換人，AddCoopPlayer.java:153-162）就從頭算。
local lastStates = {}
function W.pollStateCallbacks(player, key)
    if #W.watchers == 0 then return end
    local t = lastStates[key]
    if not t or t.obj ~= player then
        t = { obj = player, s = {} }
        lastStates[key] = t
    end
    for _, def in ipairs(W.watchers) do
        local s = W.moduleState(player, def.id)
        local old = t.s[def.id]
        if s ~= old then
            t.s[def.id] = s
            local ok, err = pcall(def.onStateChanged, player, s, old)
            if not ok and not def.errLogged then
                def.errLogged = true
                W.log("onStateChanged of module " .. def.id .. " failed: " .. tostring(err))
            end
        end
    end
end
function W.pruneStateCallbacks(keep) -- keep[key]=true 以外的玩家掉出去
    for k in pairs(lastStates) do if not keep[k] then lastStates[k] = nil end end
end

-- ===== 對外 API（shared；契約見 README「給其他 MOD 的 API」）=====
MinidoracatWatchAPI = MinidoracatWatchAPI or {}
local API = MinidoracatWatchAPI
API.watchApiVersion = 1
API.registerWatchModule = registerModule
API.registerWatchSlot = registerSlot
API.getWatchModuleState = W.moduleState

-- ===== 安裝／拆下（伺服器／單機的唯一突變點）=====
-- MP 由 server/MinidoracatWatch_Server.lua 在 OnClientCommand 內呼叫（player 是連線身分）；單機由計時動作直接呼叫。
-- 只收純量 watchId、slotId、install、itemId；錶與模組只從「這位玩家自己的背包樹」依 ID 重新解析
-- （getItemWithIDRecursiv＝ItemContainer.java:3094）。所有驗證都在第一個突變之前：失敗不留半套。
-- 拆下時只建回「已登記的模組物品類型」：錶的紀錄就算被改，也變不出其他物品；提供模組的 MOD 被移除時
-- （instanceItem 回 nil、或類型不再登記）拆不下來，模組留在錶上，不會被吃掉。
-- 孤立槽位（提供槽位的 MOD 被移除）只能拆、不能裝：slotId 沒登記時只接受格式合法的 id 與拆下。
-- 只複製純資料（字串／數字／布林／巢狀表），深度上限擋住循環參照。
function W.copyTable(t, depth)
    depth = depth or 0
    local out = {}
    for k, v in pairs(t) do
        local tk, tv = type(k), type(v)
        if tk == "string" or tk == "number" then
            if tv == "string" or tv == "number" or tv == "boolean" then
                out[k] = v
            elseif tv == "table" and depth < 8 then
                out[k] = W.copyTable(v, depth + 1)
            end
        end
    end
    return out
end

local function notBroken(item) return not item:isBroken() end
-- containsTagEvalRecurse(ItemTag, LuaClosure)＝ItemContainer.java:1166；ItemTag.SCREWDRIVER＝ItemTag.java:370
-- （原版用例 ISInventoryPaneContextMenu.lua:3791 的 getFirstTagEvalRecurse）
function W.hasScrewdriver(player)
    return player:getInventory():containsTagEvalRecurse(ItemTag.SCREWDRIVER, notBroken)
end

-- 伺服器收到沒登記的槽位或模組物品：最常見的原因是第三方只在 client 檔登記（專用伺服器只算 client 檔的
-- 檢查碼、不執行，GameServer.java:1469-1471、LuaManager.java:1206-1208）。每個名稱 log 一次、最多 32 個名稱。
local unknownLogged, unknownCount = {}, 0
function W.logUnregistered(kind, name)
    if not isServer() or type(name) ~= "string" or unknownLogged[kind .. name] or unknownCount >= 32 then return end
    unknownLogged[kind .. name] = true
    unknownCount = unknownCount + 1
    W.log(kind .. " " .. name .. " is not registered on the server; register watch modules and slots in a shared file")
end

local function takeItem(player, item, container)
    player:removeFromHands(item)
    container:DoRemoveItem(item)
    -- 伺服器的 send* 只送封包、不動容器，所以先 DoRemoveItem（GameServer.java:2405-2421）
    if isServer() then sendRemoveItemFromContainer(container, item) end
end

function W.applyModuleChange(player, watchId, slotId, install, itemId)
    if isClient() then return false, W.FAIL_MODULE end
    if not W.isFiniteInt(watchId) or type(slotId) ~= "string" or type(install) ~= "boolean" then
        return false, W.FAIL_MODULE
    end
    if install and not W.isFiniteInt(itemId) then return false, W.FAIL_MODULE end
    local slot = W.slotById[slotId]
    if not slot and (install or not validId(slotId)) then
        if install and validId(slotId) then W.logUnregistered("slot", slotId) end
        return false, W.FAIL_MODULE
    end
    if not player or player:isDead() then return false, W.FAIL_MODULE end
    local inv = player:getInventory()
    if not inv then return false, W.FAIL_MODULE end
    local watch = inv:getItemWithIDRecursiv(watchId)
    if not W.isWatch(watch) then return false, W.FAIL_MODULE end
    if W.needScrewdriver() and not W.hasScrewdriver(player) then return false, W.FAIL_SCREWDRIVER end
    local rec = W.slotRecord(watch, slotId)

    if install then
        if not W.slotValid(player, slot) then return false, W.FAIL_SLOT_INVALID end
        local slots = W.slotsOf(watch)
        if slots and slots[slotId] ~= nil then return false, W.FAIL_SLOT_FULL end
        local item = inv:getItemWithIDRecursiv(itemId)
        local def = item and W.moduleByItem[item:getFullType()]
        if not def then
            -- 原版物品（Base.*）不可能是模組，不記；其他類型多半是只在 client 登記的第三方模組
            local t = item and item:getFullType()
            if t and t:sub(1, 5) ~= "Base." then W.logUnregistered("module item", t) end
            return false, W.FAIL_MODULE
        end
        if not slot.accepts[def.class] then return false, W.FAIL_CLASS end
        local container = item:getContainer() -- InventoryItem.java:3840：實際所在的袋子
        if not container then return false, W.FAIL_MODULE end
        local md = item:hasModData() and W.copyTable(item:getModData()) or nil
        W.settleNow(player) -- 耗電倍率要變了：先把舊倍率下的耗電入帳
        -- 以下不再有失敗點
        takeItem(player, item, container)
        local wmd = watch:getModData()
        if type(wmd[W.SLOTS_KEY]) ~= "table" then wmd[W.SLOTS_KEY] = {} end
        wmd[W.SLOTS_KEY][slotId] = { id = def.id, item = def.item, md = md }
    else
        if not rec then return false, W.FAIL_SLOT_EMPTY end
        local def = W.moduleByItem[rec.item]
        if not def then return false, W.FAIL_MODULE end
        local item = instanceItem(def.item) -- LuaManager.java:5605
        if not item then return false, W.FAIL_MODULE end
        if type(rec.md) == "table" then
            local md = item:getModData()
            for k, v in pairs(W.copyTable(rec.md)) do md[k] = v end
        end
        W.settleNow(player)
        -- 以下不再有失敗點
        W.slotsOf(watch)[slotId] = nil
        inv:AddItem(item)
        if isServer() then sendAddItemToContainer(inv, item) end
    end
    W.invalidate()
    -- 只有伺服器能同步 modData（LuaManager.java:12326-12334；單機是 no-op）
    if isServer() then syncItemModData(player, watch) end
    return true
end

-- ===== 解鎖卡（伺服器／單機）=====
-- 只在開啟方式是「解鎖卡」（含 Economy 不是 READY 時的經濟系統）、而且還沒開啟時收卡：免費、不開放、經濟系統、已開啟一律拒絕，卡不會被吃。
-- 帳號無法驗證（W.account 回 nil）也拒絕。推播只送給本人、內容是本人帳號的名額（未驗證＝空表）。
function W.pushUnlocks(player)
    if not isServer() then return end
    sendServerCommand(player, W.MODULE, W.CMD_UNLOCKS, { to = player:getUsername(), slots = W.unlocksOf(player) or {} })
end

function W.applyUnlock(player, slotId, cardId)
    if isClient() then return false, W.FAIL_UNLOCK end
    if type(slotId) ~= "string" or not W.isFiniteInt(cardId) then return false, W.FAIL_UNLOCK end
    local slot = W.slotById[slotId]
    local want = slot and W.cardType(slot)
    if not want or not player or player:isDead() then return false, W.FAIL_UNLOCK end
    local name, key = W.account(player)
    if not name then return false, W.FAIL_UNLOCK_ACCOUNT end
    if not W.acceptsCard(slot) then return false, W.FAIL_UNLOCK end
    if W.slotValid(player, slot) then return false, W.FAIL_UNLOCKED end -- 已經開著（解鎖過、買斷、租用中）：不浪費卡
    local inv = player:getInventory()
    local card = inv and inv:getItemWithIDRecursiv(cardId)
    if not card or card:getFullType() ~= want then return false, W.FAIL_UNLOCK end
    local container = card:getContainer()
    if not container then return false, W.FAIL_UNLOCK end
    -- 以下不再有失敗點
    takeItem(player, card, container)
    local all = ModData.getOrCreate(W.UNLOCK_TABLE)
    if type(all[name]) ~= "table" then all[name] = {} end
    if type(all[name][key]) ~= "table" then all[name][key] = {} end
    all[name][key][slotId] = true
    W.invalidate()
    W.pushUnlocks(player)
    return true
end
