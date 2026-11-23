-- MinidoracatWatch_Recipe.lua（shared）：製作配方的 OnTest 與電學等級（media/scripts/MinidoracatWatch_recipes.txt），
-- 以及不讓別的配方把地圖手錶當材料（R.protectWatches）。
-- 引擎對每個候選輸入物品呼叫一次（CraftRecipe.OnTestItem → LuaManager.getFunctionObject 依「表.函式」解析全域），
-- 全部回 false＝配方沒有可用材料。沙盒「允許製作」關閉、或地圖錶系統關閉（等於沒裝本 MOD）時不能做。
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

-- 同一批配方的 OnAddToMenu：做不了就不列出。只靠 OnTest 的話，合成視窗連材料都不放進輸入，每格顯示 0、
-- 只寫「缺少必需物品」，玩家以為缺材料（家族 pitfalls.md「CraftRecipe」；2026-10-19 Knox Pass 玩家回報同一個畫面）。
-- 引擎經 callLuaBool 只用全域名稱查（LuaManager.java:5745-5746），所以是全域函式；
-- 原版清單與圖示兩種排法都問它（ISRecipeScrollingListBox.lua:344-348、ISTiledIconPanel.lua:193-197）
function MinidoracatWatch_recipeShown()
    return MinidoracatWatch_Recipe.canCraft()
end

-- Neat Crafting（Workshop 3502080466）自己畫清單、不問 OnAddToMenu，每條清單路徑都經 NC_FilterBar:shouldIncludeRecipe
-- （1.7.4 的 NC_FilterBar.lua:351、562、608、630），所以替 OnAddToMenu 是上面那個函式的配方代問。
-- 它是 client 檔、比本檔晚載入，遊戲開始才包（同 PackThrow Recipes.lua、Knox Pass Core.lua）
function MinidoracatWatch_Recipe.wrapNeatCrafting()
    local F = NC_FilterBar
    if type(F) ~= "table" or type(F.shouldIncludeRecipe) ~= "function" or F.minidoracatWatchFilter then return false end
    local orig = F.shouldIncludeRecipe
    F.shouldIncludeRecipe = function(self, recipe)
        if recipe ~= nil and recipe:getOnAddToMenu() == "MinidoracatWatch_recipeShown"
            and not MinidoracatWatch_Recipe.canCraft() then return false end
        return orig(self, recipe)
    end
    F.minidoracatWatchFilter = true
    return true
end
Events.OnGameStart.Add(MinidoracatWatch_Recipe.wrapNeatCrafting)

-- 產出物完整類型 → 配方名（media/scripts/MinidoracatWatch_recipes.txt）；取得方式（C.acquireInfo）也查這張表
R.RECIPES = {
    ["MinidoracatWatch.Module_Ledger"] = "CraftMinidoracatWatchLedger",
    ["MinidoracatWatch.Module_Comm"] = "CraftMinidoracatWatchComm",
    ["MinidoracatWatch.Module_Light"] = "CraftMinidoracatWatchLight",
    [W.watchType("ValuTech")] = "CraftMinidoracatWatchValuTech",
}
R.POLL_MS = 2000

function R.level()
    local v = tonumber(W.nativeSandbox("CraftLevel", 3))
    if not v or v ~= v then return 3 end
    return math.max(0, math.min(10, math.floor(v)))
end

-- 0＝不需要技能（不加需求）
function R.applyLevel(level)
    local sm = getScriptManager()
    for _, name in pairs(R.RECIPES) do
        local recipe = sm:getCraftRecipe(name) -- ScriptManager.java:1005
        if recipe then
            recipe:clearRequiredSkills()
            if level > 0 then recipe:addRequiredSkill(Perks.Electricity, level) end
        end
    end
end

-- 別的配方用 tag 收料時會把地圖手錶一起收進去：原版「拆解電子產品」寫 tags[base:digital]（recipes_electrical.txt:48），
-- 沒戴、沒收藏的錶會被拆成 1 個電子零件，錶上的模組與電池跟著消失。base:digital 不能拿掉：HUD 時鐘靠它顯示日期與
-- 氣溫（Clock.java:342）。材料驗證與合成介面的材料格查的是同一份物品清單（InputScript.containsItem／
-- getPossibleInputItems，InputScript.java:101-103、484-486），所以從那份清單拿掉「只因為 tag 才收」的地圖手錶。
-- 不動的：沒有 tag 的輸入；同一格另外指名的那款錶（getItems 是腳本寫的物品名，:1161）；拿掉後會變空的清單
-- （只有地圖手錶帶那個 tag＝衝著它來的，而且合成介面讀清單第 0 項，空的會出錯，ISWidgetInput.lua:322-340）。
-- items＝完整類型 → 物品腳本。回這一格拿掉幾個
local function strip(input, name, items, sm)
    local tags = input:getItemTags()
    if tags:isEmpty() then return 0 end
    local list, written, named, drop = input:getPossibleInputItems(), input:getItems(), {}, {}
    for i = 0, written:size() - 1 do
        local item = sm:getItem(written:get(i)) -- 引擎展開時同一個查法（:868）
        if item then named[item:getFullName()] = true end
    end
    for fullType, item in pairs(items) do
        if not named[fullType] and list:contains(item) then drop[#drop + 1] = item end
    end
    if #drop == 0 then return 0 end
    if #drop == list:size() then
        R.kept[#R.kept + 1] = list
        return 0
    end
    for _, item in ipairs(drop) do
        list:remove(item)
        -- 展開時每命中一個 tag 登記一筆（:884-896），照樣一筆一筆拿掉：物品右鍵的配方清單才不再列這條
        local used, it = item:getUsedInRecipes(), tags:iterator()
        while it:hasNext() do
            if item:hasTag(it:next()) then used:remove(name) end
        end
    end
    return #drop
end

-- 清單在世界載入時才展開（OnPostWorldDictionaryInit，:797），比本檔晚，所以跟著輪詢做。展開時每個物品登記
-- 「用在哪些配方」（Item.getUsedInRecipes，只記短名）：14 個錶的登記筆數和上次掃完一樣就不必再掃（每輪 14 次查表）；
-- 變了才走訪全部配方，只處理名字登記過的。用配方物件而不是 getCraftRecipe(短名)：短名只查得到 Base 模組的
-- （ScriptBucketCollection.java:72-90），別的 MOD 寫在自己模組裡的配方會漏掉。實體內嵌的配方載入時都帶
-- EntityRecipe tag（CraftRecipeComponentScript.java:58），在 getAllBuildableRecipes 那一份（ScriptManager.java:898）。
-- R.kept＝因為會變空而沒動的清單：之後有別的物品進了那份清單（登記筆數不一定跟著變）也要重看。
-- 伺服器與客戶端各自套。回傳拿掉幾筆
R.usedSum, R.kept = nil, {}
local function mixed(list)
    for i = 0, list:size() - 1 do
        if not W.WATCH_TYPES[list:get(i):getFullName()] then return true end
    end
    return false
end
function R.protectWatches()
    local sm, items = getScriptManager(), {}
    local function sum()
        local total = 0
        for _, item in pairs(items) do total = total + item:getUsedInRecipes():size() end
        return total
    end
    for fullType in pairs(W.WATCH_TYPES) do items[fullType] = sm:FindItem(fullType) end
    local stale = sum() ~= R.usedSum
    for _, list in ipairs(R.kept) do stale = stale or mixed(list) end
    if not stale then return 0 end
    local names, n = {}, 0
    R.kept = {}
    for _, item in pairs(items) do
        local used = item:getUsedInRecipes()
        for i = 0, used:size() - 1 do names[used:get(i)] = true end
    end
    for _, recipes in ipairs({ sm:getAllCraftRecipes(), sm:getAllBuildableRecipes() }) do
        for i = 0, recipes:size() - 1 do
            local recipe = recipes:get(i)
            local name = recipe:getName()
            if names[name] then
                local inputs = recipe:getInputs()
                for j = 0, inputs:size() - 1 do n = n + strip(inputs:get(j), name, items, sm) end
            end
        end
    end
    R.usedSum = sum()
    return n
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
    R.protectWatches()
end
Events.OnTickEvenPaused.Add(R.tick)
