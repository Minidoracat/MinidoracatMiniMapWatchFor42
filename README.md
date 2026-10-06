# Minidoracat MiniMap - Map Watch for B42

戴上地圖錶才能用小地圖；裝模組解鎖導航、資源點、殭屍偵測與隊友分享，電池以現實時間計算，管理員可調整規則與付費槽位。

Project Zomboid Build 42 MOD，[Minidoracat MiniMap for B42](https://steamcommunity.com/sharedfiles/filedetails/?id=3763913359) 的 addon。

> **開發中，尚未發布。** 以下是已定案的功能方向，實際內容以發布時為準。

## 規劃中的功能

- **地圖錶**：戴上地圖錶才能用小地圖；沒有安裝本 MOD 時，小地圖照舊全部開放
- **七款錶**：ValuTech、貓爪、極光、Spiffo、遊騎兵、盧瑟斯、嗶嗶腕機 BB-3000；外觀不同，槽位、耗電與功能完全相同；同時只能戴一支。嗶嗶腕機的螢幕可以切換綠色或琥珀色（純外觀）
- **取得方式**：錶、模組、解鎖卡依稀有度出現在對應地點的容器裡；羅盤、名錄、通訊、照明模組可以製作；殭屍依服裝帶地圖錶相關物品（屍體第一次被翻找時）
- **模組與槽位**：3 個標準槽，另有擴充、進階、核心槽；裝上模組才解鎖導航、資源點、殭屍偵測、隊友分享等功能。其他 MOD 也能加入自己的模組與槽位
- **付費槽位**：管理員可設為免費開放、解鎖卡、Economy 買斷或租用、不開放
- **電池**：以現實時間計算；預設離線與單人暫停時不耗電，沒電時所有功能停用；各模組耗電可調；管理員可開放在發動中的車上或有電的建築裡慢慢充電
- **管理員設定**：沙盒選項，加上小地圖設定裡只有管理員看得到的「地圖錶管理」分類與獨立設定視窗；殭屍掉落規則依服裝分組
- **不受限制**：世界地圖底圖、搜尋、自己的座標不需要戴錶
- **照明模組**：裝在一般槽位的錶上的燈，開燈照亮身邊約 4 格（半徑可調），所有玩家都看得到；關燈不耗電、開燈耗電 +100%（可調）；沒電、拿下錶、拆模組、槽位失效時自動熄滅。面板按鈕、錶的右鍵、快捷鍵（預設 `,`）開關

## 管理員：殭屍掉落規則檔

數值（掉落總開關、每隻最多幾件、各款錶／模組／解鎖卡是否出現在戰利品）在沙盒「地圖錶」分頁；掉落規則是清單，放在伺服器設定檔：

- 位置：`Zomboid/Lua/MinidoracatWatch/<伺服器名>/server-settings.json`（單人遊戲是 `sp_<存檔名>`，非英數字換成底線）。不存在時自動寫一份預設（10 條）。
- 改檔後 10 秒內生效，不必重開伺服器。檔案不是合法 JSON、或任何一條規則不合法時，整份規則不採用、保留上一份有效的，伺服器 log 會寫出是第幾條、哪裡不對。
- 屍體第一次被翻找時，依規則順序擲機率，掉到「每隻最多幾件」就停；已經翻找過的屍體不受影響。

```json
{
  "version": 1,
  "zombieDrops": [
    { "group": "army", "item": "watch:ranger", "chance": 2 },
    { "group": "custom", "outfits": ["HazardSuit", "Bandit"], "item": "mod:any", "chance": 1.5 }
  ]
}
```

| 欄位 | 值 |
|---|---|
| `group` | `all`（所有殭屍）、`army`、`police`、`fire`、`medic`、`worker`、`office`、`student`、`survivalist`、`rich`、`spiffo`、`outdoor`，或 `custom`（搭配 `outfits`：原版 `clothing.xml` 的服裝名稱清單，MOD 加的殭屍也能用） |
| `item` | `watch:any`、`watch:valutech`／`paws`／`nexus`／`spiffo`／`ranger`／`luthex`／`crt`（嗶嗶腕機）、`mod:any`（隨機一般模組）、`mod:<模組 id>`（含其他 MOD 註冊的模組）、`card:ext`／`adv`／`core`、`battery` |
| `chance` | 每隻的機率，百分比 0–100（可以有小數） |

各分組包含的服裝：軍人 `ArmyCamoGreen` `ArmyCamoDesert` `ArmyInstructor` `ArmyServiceUniform` `Ghillie` `PrivateMilitia`；警察與警衛 `Police` `PoliceState` `Police_SWAT` `PoliceRiot` `PrisonGuard`；消防員 `Fireman` `FiremanFullSuit`；醫護 `Doctor` `Nurse` `AmbulanceDriver` `Pharmacist`；技工與工人 `Mechanic` `MetalWorker` `ConstructionWorker` `Foreman`；上班族 `OfficeWorker` `OfficeWorkerSkirt` `Trader`；學生 `Student` `HonorStudent`；生存狂 `Survivalist`、`Survivalist02`–`05` 與各自的 `_Mid`／`_Late`；富人 `Classy` `Gaudy`；Spiffo `Spiffo` `Waiter_Spiffo` `Cook_Spiffos`；獵人與巡山員 `Hunter` `Ranger` `Camper`。

這個設定檔之後也會存其他 MOD 模組的耗電設定（新的鍵，不影響既有的 `zombieDrops`）。

## 需求

- [Minidoracat MiniMap for B42](https://steamcommunity.com/sharedfiles/filedetails/?id=3763913359)（需要尚未發布的下一版）
- [Minidoracat UI for B42](https://steamcommunity.com/sharedfiles/filedetails/?id=3789836701)

## 安裝

- Steam Workshop：（首次上傳後補上連結）
- 手動安裝：把 `MOD/MinidoracatMiniMapWatchFor42/Contents/mods/MinidoracatMiniMapWatchFor42` 複製到 `%USERPROFILE%\Zomboid\mods\` 並將資料夾改名為 `MinidoracatMiniMapWatchFor42`

## 給其他 MOD 的 API

其他 MOD 可以註冊自己的地圖錶模組，也可以增加槽位。介面是 shared 的全域表 `MinidoracatWatchAPI`（伺服器與客戶端都有）。

| 成員 | 說明 |
|---|---|
| `watchApiVersion` | 目前是 `1`。一律用 `>=` 檢查（不要用 `==`，否則地圖錶升版時你的 MOD 會被擋掉）；新增或改動成員時遞增 |
| `registerWatchModule(def) --> boolean` | `def = { id, name, class, drain, item, onStateChanged }`：`id` 英數字與底線、不可重複；`name` 是翻譯鍵；`class` 是 `"standard"`／`"advanced"`／`"core"`（決定能裝在哪種槽位）；`drain` 是建議耗電百分比（0–1000）；`item` 是模組物品的完整類型（不可和其他模組共用）；`onStateChanged(player, newState, oldState)` 選用，狀態改變時呼叫（每秒比對一次，第一次的 `oldState` 是 `nil`）。驗證失敗整筆拒收、記一筆 log、回 `false` |
| `registerWatchSlot(def) --> boolean` | `def = { id, name, accepts, price }`：`accepts` 是能裝的類別陣列；`price = { rent, days, buy }` 是建議價格。開啟方式（免費／解鎖卡／不開放）與收費由地圖錶處理；最多 6 個 |
| `getWatchModuleState(player, id) --> string` | `"disabled"`（管理員關閉了對應功能）＞`"active"`（裝在戴著、有電的錶的有效槽位）＞`"notRequired"`（地圖錶系統關閉，或規則是不需要錶／戴錶就能用而且條件成立）＞`"unpowered"`（戴著但沒電或沒電池）＞`"paused"`（所在槽位沒有開啟）＞`"missing"`（沒戴錶或沒裝）。可每幀呼叫（快取 1 秒、不配置記憶體） |

**模組與槽位一定要在 `media/lua/shared/` 的檔案裡登記**，讓伺服器與客戶端各登記一次：專用伺服器不執行 `client` 資料夾（只算檢查碼），只在 client 登記的話面板看得到、伺服器卻不認得，安裝一律被拒（伺服器 log 會記一筆「is not registered on the server」）。只讀狀態的 UI 邏輯可以放在 client。

**沒裝地圖錶、版本太舊，或管理員關閉了地圖錶系統時，你的功能應該照常開放**，不要因為少了地圖錶就把功能鎖住：

```lua
-- media/lua/shared/ 的檔案，載入時註冊一次（地圖錶的 shared 檔要先載入：mod.info 用 require= 或 loadModAfter=）
local API = MinidoracatWatchAPI
if type(API) == "table" and type(API.watchApiVersion) == "number" and API.watchApiVersion >= 1
        and type(API.registerWatchModule) == "function" then
    API.registerWatchModule({
        id = "weather",
        name = "IGUI_MyWeather_Module",  -- translation key
        class = "standard",              -- standard / advanced / core
        drain = 15,                      -- suggested extra drain, percent
        item = "MyWeather.WeatherModule",
    })
end

-- 功能入口（可以放 client）：模組裝著而且有電、或地圖錶不要求時才開放
local function canShowForecast(player)
    local API = MinidoracatWatchAPI
    if not (type(API) == "table" and type(API.watchApiVersion) == "number" and API.watchApiVersion >= 1
            and type(API.getWatchModuleState) == "function") then
        return true -- no Map Watch: keep the feature open
    end
    local ok, state = pcall(API.getWatchModuleState, player, "weather")
    return not ok or state == "active" or state == "notRequired"
end

-- 選用：增加一個槽位（顯示在面板錶面下方「其他 MOD」那一列）
if type(API) == "table" and type(API.watchApiVersion) == "number" and API.watchApiVersion >= 1
        and type(API.registerWatchSlot) == "function" then
    API.registerWatchSlot({
        id = "forecast",
        name = "IGUI_MyWeather_Slot",
        accepts = { "standard" },
        price = { rent = 80, days = 7, buy = 600 },
    })
end
```

- 只看「有沒有」的功能（例如 AutoDrive 的 GPS）只認 `"active"`。
- 模組耗電：內建模組由沙盒調整；第三方模組目前用 `drain` 建議值（管理員調整在之後的版本）。
- 其他 MOD 的槽位開啟方式是沙盒「其他 MOD 加入的槽位的開啟方式」（預設免費開放）；選解鎖卡時用擴充槽解鎖卡。
- 解鎖卡開啟的名額綁在帳號（登入名）。多人伺服器上分割畫面的第 2～4 位玩家無法確認身分，不能使用解鎖卡；Steam 伺服器以連線的 SteamID 確認身分，改名冒用別人讀不到對方的名額。**已知殘餘風險**：no-steam 伺服器沒有驗證因子，玩家重生時改名成離線玩家仍能使用對方已開啟的名額。
- 你的 MOD 被移除後（沒有再登記同一個槽位 id），裝在那個槽位裡的模組會停用、不耗電，玩家照樣能從面板或錶的右鍵選單拆下來；槽位與解鎖紀錄保留，MOD 裝回來就恢復。模組的 `item` 類型如果也跟著消失，那個模組會留在錶上、拆不下來，直到 MOD 裝回來。

## 開發

- `link_workshop.bat`：手動同步、唯讀狀態與歸檔卸載；MOD 以實體副本放入 `Zomboid\Workshop\` 與 `Zomboid\mods\`，不使用目錄連結
- `PZ_Test.bat`：暗色點選視窗，啟動前增量同步目前 MOD 與家族依賴；首次預設 no-Steam，之後記住各專案的選擇。需要換檔但遊戲仍在執行時拒絕同步與新啟動，不停止既有遊戲；完整驗證與資料邊界見 `../pz-family-docs/tools.md`
- `Publish_Workshop.bat`：發布到 Steam Workshop（需 Steam 用戶端已登入；可選擇只更新內容／封面／簡介；首發仍走遊戲內上傳器）

## 美術

手腕模型、貼圖與物品圖示都是本 MOD 自製（MIT，產生器在 `scripts/blender/`），沒有使用原版的模型或貼圖檔；`scripts/blender/fonts/` 的字型（OFL）只用來產生貼圖，不在 MOD 裡。

## 版本

版本號格式：`{PZ 版本}-{mod 版本}`（例 `42.21.0-0.1.0`），詳見 [CHANGELOG.md](CHANGELOG.md)。

## 作者

Minidoracat — [Discord](https://discord.gg/Gur2V67) | [Twitch](https://www.twitch.tv/minidoracat)
