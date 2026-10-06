-- MinidoracatWatch_Recipe.lua（shared）：模組配方的 OnTest 與電學等級（media/scripts/MinidoracatWatch_recipes.txt）。
-- 引擎對每個候選輸入物品呼叫一次（CraftRecipe.OnTestItem → LuaManager.getFunctionObject 依「表.函式」解析全域），
-- 全部回 false＝配方沒有可用材料。沙盒「允許製作模組」關閉、或地圖錶系統關閉（等於沒裝本 MOD）時不能做。
-- 沙盒還沒載入（主選單）時 W.sandbox 回預設值＝放行，配方不會在讀到設定前被誤鎖。
--
-- 電學等級（沙盒 CraftLevel 0–10，預設 3＝腳本的 SkillRequired）：執行期直接改配方的需求。CraftRecipe 已暴露給 Lua
-- （LuaManager.java:2285），clearRequiredSkills／addRequiredSkill 是公開方法（CraftRecipe.java:980-992）；
-- 驗證每次現讀（CraftRecipeManager.validateHasRequiredSkill，CraftRecipeManager.java:360-375），合成介面也是每次畫
-- 都讀 getRequiredSkillCount／getRequiredSkill（ISCraftRecipeInfoBox.lua:80-82、ISRecipeScrollingListBox.lua:174-176），
-- 所以顯示與判定都跟著改。伺服器與客戶端各自套（兩邊都跑這個 shared 檔），每 2 秒比對、變了才改。
require "MinidoracatWatch"
local W = MinidoracatWatchCore

MinidoracatWatch_Recipe = MinidoracatWatch_Recipe or {}
local R = MinidoracatWatch_Recipe

function MinidoracatWatch_Recipe.canCraft() -- verify 第 18 項依這個寫法找 OnTest
    return W.enabled() and W.sandbox("AllowCraft", true) ~= false
end

R.RECIPES = { "CraftMinidoracatWatchCompass", "CraftMinidoracatWatchLedger", "CraftMinidoracatWatchComm",
    "CraftMinidoracatWatchLight" }
R.POLL_MS = 2000

function R.level()
    local v = tonumber(W.nativeSandbox("CraftLevel", 3))
    if not v or v ~= v then return 3 end
    return math.max(0, math.min(10, math.floor(v)))
end

-- 0＝不需要技能（不加需求）
function R.applyLevel(level)
    local sm = getScriptManager()
    for _, name in ipairs(R.RECIPES) do
        local recipe = sm:getCraftRecipe(name) -- ScriptManager.java:1005
        if recipe then
            recipe:clearRequiredSkills()
            if level > 0 then recipe:addRequiredSkill(Perks.Electricity, level) end
        end
    end
end

R.applied = nil
local lastPoll = nil
function R.tick()
    local now = getTimestampMs()
    if lastPoll and now >= lastPoll and now - lastPoll < R.POLL_MS then return end
    lastPoll = now
    local lv = R.level()
    if lv ~= R.applied then
        R.applyLevel(lv)
        R.applied = lv
    end
end
Events.OnTickEvenPaused.Add(R.tick)
