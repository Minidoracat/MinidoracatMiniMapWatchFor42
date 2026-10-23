-- 地圖手錶自己的手腕部位（2026-10-23 使用者裁定：長袖不再藏起地圖手錶）。
-- 原版對長袖外衣寫了 setHideModel(外衣, LEFT_WRIST／RIGHT_WRIST)（BodyLocations.lua:596-627），引擎組角色模型時用
-- 物品腳本的部位查這張表、查到就不畫那件（PopTemplateManager.isItemModelHidden）；規則只能加不能刪
-- （BodyLocation 的 hideModel 是私有清單，沒有移除方法），所以地圖手錶改戴在這裡註冊的部位。
-- Covered 兩個給「長袖蓋住地圖手錶」的玩家選項用；部位規則在 shared/MinidoracatWatch.lua。
-- ModRegistries.init 一律在 ScriptManager.Load 之前跑（GameWindow.java:201-203、IngameState.java:1045-1048、
-- GameServer.java:1446-1447），物品腳本可以直接寫這些 id；Lua 重載前 RegistryReset.resetAll 會清掉（IngameState.java:979），
-- 重新註冊不會撞名。id 會寫進存檔的穿戴紀錄（IsoPlayer.java:1255-1259），不可改名。
MinidoracatWatchLocations = {
    LEFT = ItemBodyLocation.register("MinidoracatWatch:LeftWrist"),
    LEFT_COVERED = ItemBodyLocation.register("MinidoracatWatch:LeftWristCovered"),
    RIGHT = ItemBodyLocation.register("MinidoracatWatch:RightWrist"),
    RIGHT_COVERED = ItemBodyLocation.register("MinidoracatWatch:RightWristCovered"),
}
