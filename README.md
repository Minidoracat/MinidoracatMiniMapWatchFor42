# Minidoracat MiniMap - Map Watch for B42

戴上地圖錶才能用小地圖；裝模組解鎖導航、資源點、殭屍偵測與隊友分享，電池以現實時間計算，管理員可調整規則與付費槽位。

Project Zomboid Build 42 MOD，[Minidoracat MiniMap for B42](https://steamcommunity.com/sharedfiles/filedetails/?id=3763913359) 的 addon。

> **開發中，尚未發布。** 以下是已定案的功能方向，實際內容以發布時為準。

## 規劃中的功能

- **地圖錶**：戴上地圖錶才能用小地圖；沒有安裝本 MOD 時，小地圖照舊全部開放
- **七款錶**：ValuTech、貓爪、極光、Spiffo、遊騎兵、盧瑟斯、嗶嗶腕機 BB-3000；外觀不同，槽位、耗電與功能完全相同；同時只能戴一支
- **模組與槽位**：3 個標準槽，另有擴充、進階、核心槽；裝上模組才解鎖導航、資源點、殭屍偵測、隊友分享等功能。其他 MOD 也能加入自己的模組與槽位
- **付費槽位**：管理員可設為免費開放、解鎖卡、Economy 買斷或租用、不開放
- **電池**：以現實時間計算；預設離線與單人暫停時不耗電，沒電時所有功能停用；各模組耗電可調；管理員可開放在發動中的車上或有電的建築裡慢慢充電
- **管理員設定**：沙盒選項，加上小地圖設定裡只有管理員看得到的「地圖錶管理」分類與獨立設定視窗；殭屍掉落規則依服裝分組
- **不受限制**：世界地圖底圖、搜尋、自己的座標不需要戴錶

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

## 版本

版本號格式：`{PZ 版本}-{mod 版本}`（例 `42.21.0-0.1.0`），詳見 [CHANGELOG.md](CHANGELOG.md)。

## 作者

Minidoracat — [Discord](https://discord.gg/Gur2V67) | [Twitch](https://www.twitch.tv/minidoracat)
