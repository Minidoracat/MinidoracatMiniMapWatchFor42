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

F.print()
if F.failures > 0 then
    F.print(F.failures .. " 項失敗")
    os.exit(1)
end
F.print("全部通過（" .. F.count .. " 項）")
