--[[
煙霧測試骨架：用假的 PZ 全域載入**真正的** MOD Lua，跑行為情境並斷言結果。

    lua scripts/smoke_harness.lua        （repo 根目錄執行；標準 Lua 5.x 即可）

為什麼需要（兩類 luac -p 抓不到的錯誤，皆為正式服實際事故）：
- 改函式簽章漏改呼叫點：語法完全合法，要等該路徑真的執行才炸
  （實例：hotspotKey 兩參數改三參數，刪除成功後的 log 聚合路徑必崩）
- 邏輯回歸：安全把關（範圍／阻隔／保護規則）被改壞時，「執行到並斷言」是唯一防線

限制（必須誠實面對）：這是標準 Lua，不是遊戲的 Kahlua。
- 標準 Lua 有 next/xpcall，Kahlua 沒有——本 harness **測不出**誤用，
  那由 scripts/verify_mod.py 的靜態掃描負責（發版前兩者都要跑）
- Kahlua 專屬行為（table.sort 遞迴深度、Java instance field 不暴露、rawget 呼叫形式、
  每個 table 都是 LinkedHashMap 的記憶體成本）只能靠反編譯查證與實機測試

寫情境的原則：
- 情境要「執行到會炸的路徑」——刪除後的收尾、跨 tick 的第二輪、聚合輸出，都是重災區
- 安全邊界要有**反面**斷言（範圍外／被阻隔／受保護的對象必須存活），不是只測 happy path
- 新防線寫完先「植入違規證明它會抓」再信任它——測不出來的測試等於沒有測試
]]

-- 假全域與載入工具共用 scripts/lib_watch_fakes.lua（test_watch_*.lua 也用同一份）
local F = dofile("scripts/lib_watch_fakes.lua")
local check, near = F.check, F.near

-- 專用伺服器視角：載入真正的 shared 與 server 檔
F.mode = "server"
require "MinidoracatWatch"
F.load("server/MinidoracatWatch_Server.lua")
local W = MinidoracatWatchCore
local H = 3600000

local function tick(ms, step)
    local t = 0
    while t < ms do F.now = F.now + step; t = t + step; F.fire("OnTickEvenPaused") end
end
local function command(player, args)
    F.fire("OnClientCommand", W.MODULE, W.CMD_BATTERY, player, args)
end

F.print("情境一：戴錶 → 伺服器每分鐘扣電並同步")
local alice = F.player("alice", 0)
local watch = F.item(F.RIGHT)
alice.inv:AddItem(watch)
F.action(ISWearClothing, alice, watch):complete()
tick(1000, 100)
tick(10 * 60000, 500)
check(#F.synced == 10, "十分鐘同步十次（不是每 tick）")
check(near(W.charge(watch), 1 - 10 * 60000 / (72 * H), 1e-4), "扣掉十分鐘的電")

F.print("情境二：換電池（client command）→ 電量守恆、節流、反例")
local bat = F.item("Base.Battery")
bat:setCurrentUsesFloat(0.6)
alice.inv:AddItem(bat)
local old = W.charge(watch)
F.reset()
command(alice, { watchId = watch:getID(), install = true, batteryId = bat:getID() })
check(near(W.charge(watch), bat:getCurrentUsesFloat()) and bat.container == nil, "裝入：錶的電量＝電池剩餘量")
local returned = F.added[1]
local rc = returned and returned:getCurrentUsesFloat()
check(rc and rc <= old and rc > old - F.BATTERY_DELTA, "舊電池帶剩餘量還回背包（捨去到整數格）")
check(#F.synced == 1, "換電池後同步錶的 modData")
command(alice, { watchId = watch:getID(), install = false })
check(W.charge(watch) ~= nil, "250ms 內的第二個指令被節流")
F.now = F.now + 300
command(alice, { watchId = watch:getID(), install = false })
check(W.charge(watch) == nil, "節流期過後取出成功")

local mallory = F.player("mallory", 1)
local loot = F.item("Base.Battery")
alice.inv:AddItem(loot)
F.reset()
F.now = F.now + 300
command(mallory, { watchId = watch:getID(), install = true, batteryId = loot:getID() })
check(W.charge(watch) == nil and loot.container == alice.inv, "冒用別人的錶與電池：不動任何東西")
check(#F.serverCmds == 1 and F.serverCmds[1].player == mallory and F.serverCmds[1].args.reason == W.FAIL_GENERIC
    and F.serverCmds[1].args.to == "mallory", "失敗只回給送指令的人、只帶常數鍵")
F.now = F.now + 300
command(mallory, "junk")
command(alice, { watchId = "1001", install = true, batteryId = loot:getID() })
check(W.charge(watch) == nil, "非 table／字串 id 一律不處理")

F.print("情境三：換手保留電量、同時只能戴一支")
F.now = F.now + 300
command(alice, { watchId = watch:getID(), install = true, batteryId = loot:getID() })
local before = W.charge(watch)
local swap = F.action(ISClothingExtraAction, alice, watch, F.LEFT)
check(swap:complete() == true, "伺服器端換手完成")
local moved = W.wornWatch(alice)
check(moved ~= watch and moved.fullType == F.LEFT and W.charge(moved) == before, "新物品 ID 不同、電量隨 modData 過去")
local second = F.item(F.RIGHT)
alice.inv:AddItem(second)
check(F.action(ISWearClothing, alice, second):complete() == false, "伺服器 complete 擋第二支")
F.reset()
tick(60000, 500)
check(#F.synced == 1 and F.synced[1].item == moved, "扣電跟著換手後的新物品")

-- 指令經 OnClientCommand（player＝連線身分）：每個指令之間隔開節流期
local function send(player, cmd, args)
    F.now = F.now + 300
    F.fire("OnClientCommand", W.MODULE, cmd, player, args)
end
local function fails(player)
    local n = 0
    for _, c in ipairs(F.serverCmds) do
        if c.player == player and c.command == W.CMD_FAILED and W.FAIL_KEYS[c.args.reason] then n = n + 1 end
    end
    return n
end

F.print("情境四：裝卸模組（client command）→ 物品進出、錶同步、功能狀態")
local SB = SandboxVars.MinidoracatWatch
local API = MinidoracatWatchAPI
local driver = F.item("Base.Screwdriver")
alice.inv:AddItem(driver)
local gps = F.item("MinidoracatWatch.Module_GPS")
alice.inv:AddItem(gps)
F.reset()
check(API.getWatchModuleState(alice, "gps") == "missing", "裝之前定位模組 missing")
send(alice, W.CMD_MODULE, { watchId = moved:getID(), slotId = "std1", install = true, itemId = gps:getID() })
check(gps.container == nil and W.slotRecord(moved, "std1").id == "gps" and #F.synced == 1 and F.removed[1] == gps,
    "安裝：模組離開背包、紀錄進錶、同步")
check(API.getWatchModuleState(alice, "gps") == "active", "伺服器上 getWatchModuleState＝active（AutoDrive 讀這個）")
F.reset()
local c0 = W.charge(moved)
tick(60000, 500)
check(near((c0 - W.charge(moved)) * 72 * H, 60000 * 1.25, 1000) and #F.synced == 1,
    "定位模組 +25%：一分鐘扣 1.25 分鐘的電，照樣每分鐘同步一次")
F.reset()
send(alice, W.CMD_MODULE, { watchId = moved:getID(), slotId = "std1", install = false })
local back = alice.inv:getAllTypeRecurse("MinidoracatWatch.Module_GPS")
check(back:size() == 1 and W.slotRecord(moved, "std1") == nil and F.added[1] == back:get(0), "拆下：物品回背包、送新增封包")
check(API.getWatchModuleState(alice, "gps") == "missing", "拆下後 missing")
F.reset()
send(mallory, W.CMD_MODULE, { watchId = moved:getID(), slotId = "std1", install = true, itemId = back:get(0):getID() })
check(W.slotRecord(moved, "std1") == nil and back:get(0).container == alice.inv and fails(mallory) == 1,
    "冒用別人的錶與模組：不動、失敗只回給送指令的人")
send(alice, W.CMD_MODULE, { watchId = moved:getID(), slotId = "ext", install = true, itemId = back:get(0):getID() })
check(W.slotRecord(moved, "ext") == nil and fails(alice) == 1, "擴充槽（預設經濟系統＝解鎖卡）未開啟：拒絕")
send(alice, W.CMD_MODULE, "junk")
send(alice, W.CMD_MODULE, { watchId = tostring(moved:getID()), slotId = "std1", install = true, itemId = back:get(0):getID() })
check(W.slotRecord(moved, "std1") == nil, "非 table／字串 id 一律不處理")

F.print("情境五：解鎖卡（client command）→ 伺服器紀錄、只送給本人、不能重複、客戶端偽造無效")
local card = F.item("MinidoracatWatch.UnlockCard_Ext")
alice.inv:AddItem(card)
F.reset()
send(alice, W.CMD_UNLOCKS, { to = "alice", slots = { ext = true, adv = true, core = true } })
send(alice, W.CMD_UNLOCK, { slotId = "adv", cardId = card:getID() })
check(not W.isUnlocked(alice, "ext") and not W.isUnlocked(alice, "adv") and card.container == alice.inv,
    "客戶端送 unlocks 或拿錯卡：伺服器不認、卡不被吃")
F.reset()
send(alice, W.CMD_UNLOCK, { slotId = "ext", cardId = card:getID() })
check(W.isUnlocked(alice, "ext") and card.container == nil, "擴充槽解鎖卡：開啟、卡用掉")
local pushed = F.serverCmds[1]
check(pushed and pushed.player == alice and pushed.command == W.CMD_UNLOCKS and pushed.args.slots.ext == true,
    "只把 alice 的解鎖狀態送給 alice")
local card2 = F.item("MinidoracatWatch.UnlockCard_Ext")
alice.inv:AddItem(card2)
send(alice, W.CMD_UNLOCK, { slotId = "ext", cardId = card2:getID() })
check(card2.container == alice.inv and fails(alice) == 1, "第二張卡：拒絕、不被吃")
check(not W.isUnlocked(mallory, "ext"), "mallory 沒有因此開啟")
send(alice, W.CMD_MODULE, { watchId = moved:getID(), slotId = "ext", install = true, itemId = back:get(0):getID() })
check(W.slotRecord(moved, "ext") and W.slotRecord(moved, "ext").id == "gps", "開啟後裝得上擴充槽")
F.reset()
send(alice, W.CMD_UNLOCKS_REQ, {})
check(F.serverCmds[1] and F.serverCmds[1].player == alice and F.serverCmds[1].args.slots.ext == true, "客戶端補要：回自己的那份")

F.print("情境六：槽位失效 → 模組 paused、不耗電；重登（新的 IsoPlayer）解鎖還在、登入時送解鎖狀態")
SB.SlotExt = 4
tick(1500, 500)
check(API.getWatchModuleState(alice, "gps") == "paused", "擴充槽改成不開放：paused")
check(W.drainFactor(alice, moved) == 1, "paused 的模組不耗電")
SB.SlotExt = nil
-- 重登：伺服器上是新的 IsoPlayer 物件，同帳號同 playerNum；錶在背包裡（modData 隨物品存檔）
local relog = F.player("alice", 0)
relog.inv = alice.inv
relog.worn = alice.worn
F.players = { relog, mallory }
F.reset()
tick(2000, 500)
local sent = false
for _, c in ipairs(F.serverCmds) do
    if c.player == relog and c.command == W.CMD_UNLOCKS and c.args.slots.ext == true then sent = true end
end
check(sent, "第一次看到重登的玩家：主動送解鎖狀態")
check(W.isUnlocked(relog, "ext") and API.getWatchModuleState(relog, "gps") == "active", "重登後解鎖與模組都還在")

F.print("情境七：其他 MOD 的槽位 → 那個 MOD 被移除（下次啟動沒人登記）→ 模組 paused、不耗電，照樣能拆、不能再裝")
check(API.registerWatchSlot({ id = "forecast", name = "IGUI_X_Slot", accepts = { "standard" },
    price = { rent = 80, days = 7, buy = 600 } }) == true, "第三方 MOD 登記槽位")
local comm = F.item("MinidoracatWatch.Module_Comm")
relog.inv:AddItem(comm)
send(relog, W.CMD_MODULE, { watchId = moved:getID(), slotId = "forecast", install = true, itemId = comm:getID() })
check(W.slotRecord(moved, "forecast") and comm.container == nil, "裝進第三方槽位")
-- 模擬下次啟動沒有那個 MOD：登記表裡沒有這個槽位（錶的 modData 隨存檔還在）
for i = #W.slotList, 1, -1 do if W.slotList[i].id == "forecast" then table.remove(W.slotList, i) end end
W.slotById.forecast = nil
W.invalidate()
check(API.getWatchModuleState(relog, "comm") == "paused" and W.drainFactor(relog, moved) == 1.25,
    "孤立槽位裡的通訊模組 paused、不耗電（只剩擴充槽的定位模組 +25%）")
local spare = F.item("MinidoracatWatch.Module_Scan")
relog.inv:AddItem(spare)
F.reset()
send(relog, W.CMD_MODULE, { watchId = moved:getID(), slotId = "forecast", install = false })
local backComm = relog.inv:getAllTypeRecurse("MinidoracatWatch.Module_Comm")
check(W.slotRecord(moved, "forecast") == nil and backComm:size() == 1 and F.added[1] == backComm:get(0) and #F.synced == 1,
    "孤立槽位的模組拆下：回背包、送新增封包、同步錶")
send(relog, W.CMD_MODULE, { watchId = moved:getID(), slotId = "forecast", install = true, itemId = spare:getID() })
check(W.slotRecord(moved, "forecast") == nil and spare.container == relog.inv and fails(relog) == 1,
    "孤立槽位不能再裝")

F.print("情境八：第三方只在 client 檔登記（專用伺服器不執行 client 檔）→ 伺服器拒絕安裝，每個名稱 log 一次")
-- 客戶端那邊看得到的槽位與模組，伺服器的登記表裡沒有
local onlyClient = F.item("Other.ClientOnlyModule")
relog.inv:AddItem(onlyClient)
F.reset()
for _ = 1, 2 do
    send(relog, W.CMD_MODULE, { watchId = moved:getID(), slotId = "clientonly", install = true, itemId = onlyClient:getID() })
    send(relog, W.CMD_MODULE, { watchId = moved:getID(), slotId = "std3", install = true, itemId = onlyClient:getID() })
end
local slotLogs, itemLogs = 0, 0
for _, l in ipairs(F.logs) do
    if l:find("slot clientonly is not registered on the server", 1, true) then slotLogs = slotLogs + 1 end
    if l:find("module item Other.ClientOnlyModule is not registered on the server", 1, true) then itemLogs = itemLogs + 1 end
end
check(onlyClient.container == relog.inv and W.slotRecord(moved, "clientonly") == nil and W.slotRecord(moved, "std3") == nil
    and fails(relog) == 4, "伺服器沒登記的槽位與模組：拒絕、物品不動")
check(slotLogs == 1 and itemLogs == 1, "每個沒登記的名稱只 log 一次（提示要放 shared）")
F.reset()
send(relog, W.CMD_MODULE, { watchId = moved:getID(), slotId = "std3", install = true, itemId = F.item("Base.Battery"):getID() })
local battery = F.item("Base.Battery")
relog.inv:AddItem(battery)
send(relog, W.CMD_MODULE, { watchId = moved:getID(), slotId = "std3", install = true, itemId = battery:getID() })
check(#F.logs == 0, "原版物品不是模組，不記 log")

F.print()
if F.failures > 0 then
    F.print(F.failures .. " 項失敗")
    os.exit(1)
end
F.print("全部通過（" .. F.count .. " 項）")
