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

## 開發

- `link_workshop.bat`：手動同步、唯讀狀態與歸檔卸載；MOD 以實體副本放入 `Zomboid\Workshop\` 與 `Zomboid\mods\`，不使用目錄連結
- `PZ_Test.bat`：暗色點選視窗，啟動前增量同步目前 MOD 與家族依賴；首次預設 no-Steam，之後記住各專案的選擇。需要換檔但遊戲仍在執行時拒絕同步與新啟動，不停止既有遊戲；完整驗證與資料邊界見 `../pz-family-docs/tools.md`
- `Publish_Workshop.bat`：發布到 Steam Workshop（需 Steam 用戶端已登入；可選擇只更新內容／封面／簡介；首發仍走遊戲內上傳器）

## 版本

版本號格式：`{PZ 版本}-{mod 版本}`（例 `42.21.0-0.1.0`），詳見 [CHANGELOG.md](CHANGELOG.md)。

## 作者

Minidoracat — [Discord](https://discord.gg/Gur2V67) | [Twitch](https://www.twitch.tv/minidoracat)
