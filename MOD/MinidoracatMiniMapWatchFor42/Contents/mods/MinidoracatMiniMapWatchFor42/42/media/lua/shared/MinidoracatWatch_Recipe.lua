-- MinidoracatWatch_Recipe.lua（shared）：模組配方的 OnTest（media/scripts/MinidoracatWatch_recipes.txt）。
-- 引擎對每個候選輸入物品呼叫一次（CraftRecipe.OnTestItem → LuaManager.getFunctionObject 依「表.函式」解析全域），
-- 全部回 false＝配方沒有可用材料。沙盒「允許製作模組」關閉、或地圖錶系統關閉（等於沒裝本 MOD）時不能做。
-- 沙盒還沒載入（主選單）時 W.sandbox 回預設值＝放行，配方不會在讀到設定前被誤鎖。
require "MinidoracatWatch"
local W = MinidoracatWatchCore

MinidoracatWatch_Recipe = MinidoracatWatch_Recipe or {}

function MinidoracatWatch_Recipe.canCraft()
    return W.enabled() and W.sandbox("AllowCraft", true) ~= false
end
