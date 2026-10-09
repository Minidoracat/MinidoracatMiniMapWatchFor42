-- MinidoracatWatch_Sound.lua（client）：地圖錶音效與玩家設定（Phase 9；規劃書 §0：只有自己聽得到、有音量設定，
-- 「定時掃描更新」提示音玩家可開、預設關）。觸發點：裝好／拆下模組（_Action 單機、_Client 收伺服器確認）、
-- 開關燈（_LightClient 的 syncLight 看到狀態真的變了）、電量不足／沒電／租約到期（_Hud 的 Toast 同一處、同樣不重報）、
-- 定時掃描更新（主 MOD registerScanListener）。
-- 播放走玩家 emitter 的本機路徑 playSoundImpl(name, nil)：不送 PlaySound 封包（FMODSoundEmitter.java:484-492、
-- 對照 playSound :389-402），MP 其他玩家聽不到；逐次音量 emitter:setVolume(ref, v)（:284-298）。照 AutoDrive MDAD_Voice.lua。
-- 名稱查不到（sound script 沒載）＝回 0（:485-487）。sound script 在 media/scripts/MinidoracatWatch_sounds.txt。
-- 設定存本機 PZAPI.ModOptions（Zomboid/Lua/ModOptions.ini，不跟存檔；ESC 選項的「Minidoracat 地圖錶」頁也看得到），
-- 小地圖齒輪設定的「地圖錶」分類讀寫同一份（照 AutoDrive MDAD_HUD.lua：ModOptions 必須在 MainOptions:create
-- 前於檔案頂層建立，MainOptions.lua:2796 load、:3760-3766 save）。
require "MinidoracatWatch"
local W = MinidoracatWatchCore
local Snd = {}
MinidoracatWatchSound = Snd -- 內部表（_Action／_Client／_LightClient／_Hud、測試與 E2E 用），不是公開 API

Snd.VOLUME_DEFAULT = 70
Snd.SCAN_MERGE_MS = 1000 -- 殭屍與載具動物兩種掃描常常同一刻更新：1 秒內只響一次
Snd.REMOVE, Snd.LIGHT, Snd.LOW, Snd.DEAD, Snd.LAPSED, Snd.SCAN = "MinidoracatWatch_RemoveModule",
    "MinidoracatWatch_LightToggle", "MinidoracatWatch_BatteryLow", "MinidoracatWatch_BatteryDead",
    "MinidoracatWatch_SlotLapsed", "MinidoracatWatch_ScanPing"
Snd.INSTALL = {}
for _, s in ipairs(W.STYLES) do Snd.INSTALL[s] = "MinidoracatWatch_Install_" .. s end

-- ===== 設定 =====
local opts = nil
if PZAPI and PZAPI.ModOptions then
    opts = PZAPI.ModOptions:create("MinidoracatWatch", "IGUI_MinidoracatWatch_Options")
    opts:addSlider("Volume", "IGUI_MinidoracatWatch_Sound_Volume", 0, 100, 5, Snd.VOLUME_DEFAULT,
        "IGUI_MinidoracatWatch_Sound_Volume_tooltip")
    opts:addTickBox("ScanPing", "IGUI_MinidoracatWatch_Sound_ScanPing", false,
        "IGUI_MinidoracatWatch_Sound_ScanPing_tooltip")
    -- 家族工具列的地圖錶按鈕（預設顯示；使用者 2026-10-08 裁定每個入口都要能隱藏）
    opts:addTickBox("ShowButton", "IGUI_MinidoracatWatch_ShowButton", true,
        "IGUI_MinidoracatWatch_ShowButton_tooltip")
end

local function opt(id, default)
    local o = opts and opts:getOption(id)
    local v = o and o:getValue()
    if type(v) ~= type(default) or v ~= v then return default end
    return v
end

local function setOpt(id, v)
    local o = opts and opts:getOption(id)
    if not o then return end
    o:setValue(v)
    PZAPI.ModOptions:save()
end

function Snd.volume() return math.max(0, math.min(100, opt("Volume", Snd.VOLUME_DEFAULT))) end
-- 值真的變了才寫回，並排一次試聽（面板音量列、齒輪分類都走這裡）
function Snd.setVolume(v)
    if type(v) ~= "number" or v ~= v then return end
    v = math.max(0, math.min(100, v))
    if v == Snd.volume() then return end
    setOpt("Volume", v)
    Snd.preview()
end
function Snd.scanPing() return opt("ScanPing", false) end
function Snd.setScanPing(on) setOpt("ScanPing", on == true) end

-- 工具列按鈕顯示：Dock 的 isAvailable 可能每幀被叫，只讀這個快取（_Client 的 DOCK_SPEC）。
-- 更新點：OnGameStart（原版 LoadMainScreenPanelIngame 先註冊、先跑 ModOptions:load，MainScreen.lua:2180、
-- MainOptions.lua:2796）、按套用（MainOptions.lua:3760-3762 每頁 options:apply()）與齒輪分類的 set（存檔後走同一個
-- apply）；讀不到＝顯示。
Snd.showButton = true
function Snd.loadShowButton()
    Snd.showButton = opt("ShowButton", true)
    local C = MinidoracatWatchClient
    local ui = C and C.docked and C.ui()
    if ui then ui.Dock.refresh() end
end
if opts then opts.apply = Snd.loadShowButton end
Events.OnGameStart.Add(Snd.loadShowButton)
function Snd.showButtonOpt() return opt("ShowButton", true) end
function Snd.setShowButton(on)
    setOpt("ShowButton", on == true)
    if opts then opts:apply() end
end

-- ===== 播放 =====
local warned = {}
-- 回 ref（非 0）＝真的播了；音量 0、沒有玩家、名稱沒登記＝nil
function Snd.play(player, name)
    local v = Snd.volume() / 100
    if v <= 0 or not player then return nil end
    local emitter = player:getEmitter()
    local ref = emitter and emitter:playSoundImpl(name, nil)
    if type(ref) ~= "number" or ref == 0 then
        if not warned[name] then
            warned[name] = true
            W.log("sound not registered: " .. tostring(name))
        end
        return nil
    end
    emitter:setVolume(ref, v)
    return ref
end

function Snd.styleOf(watch)
    return watch and watch:getFullType():match("^MinidoracatWatch%.MapWatch_(%w+)_") or nil
end

-- 裝好依戴著的錶款；沒戴錶（替背包裡的錶裝）就依那支錶
function Snd.moduleDone(player, install, watch)
    if not install then return Snd.play(player, Snd.REMOVE) end
    local name = Snd.INSTALL[Snd.styleOf(W.status(player).watch)] or Snd.INSTALL[Snd.styleOf(watch)]
    return Snd.play(player, name or Snd.INSTALL.ValuTech)
end

-- ===== 調音量時試聽（使用者 2026-10-09 裁定，照公告板 NBPanel：拖動中不播，停下來才播一次）=====
-- setVolume 每次變動都把試聽往後排 PREVIEW_MS；停下來才播戴著那款的裝好音效（沒戴錶＝ValuTech），播之前先停掉
-- 上一個試聽（stopSoundLocal 只停這個 ref、不送封包，CharacterSoundEmitter.java:286-290）。音量 0 不播。
-- ESC 選項頁的滑桿照公告板不試聽：SP 開 ESC 會暫停，玩家 emitter 的聲音排在 toStart，要等角色 update 的
-- tick 才開始播（FMODSoundEmitter.java:564-578、IsoGameCharacter.java:1552-1555），會在回到遊戲時才響。
Snd.PREVIEW_MS = 300
local preview = {}
function Snd.preview() preview.at = getTimestampMs() + Snd.PREVIEW_MS end
function Snd.previewTick()
    if not preview.at or getTimestampMs() < preview.at then return end
    preview.at = nil
    local p = getSpecificPlayer(0)
    if not p then return end
    if preview.ref then pcall(preview.emitter.stopSoundLocal, preview.emitter, preview.ref) end
    preview.ref = Snd.play(p, Snd.INSTALL[Snd.styleOf(W.status(p).watch)] or Snd.INSTALL.ValuTech)
    preview.emitter = preview.ref and p:getEmitter()
end
Events.OnTickEvenPaused.Add(Snd.previewTick)

-- 開關燈：每位本機玩家記上一次看到的狀態，真的變了才響；換了角色（重生）只記基準
local lit = {}
function Snd.lightSeen(player, on)
    local pn = player:getPlayerNum()
    local s = lit[pn]
    if s and s.obj == player then
        if s.on ~= on then
            s.on = on
            Snd.play(player, Snd.LIGHT)
        end
    else
        lit[pn] = { obj = player, on = on }
    end
end

-- ===== 定時掃描更新（主 MOD scanApiVersion >= 1）=====
-- 主 MOD 只在定時模式（沙盒間隔 > 0）真的重新取樣後呼叫；這裡再看玩家開了沒、對應功能能不能用（同功能閘門）
local FEATURE = { zombie = "zombie", vehicleAnimal = "scan" }
local lastPing = {}
function Snd.onScan(pn, kind)
    local feature = FEATURE[kind]
    if not feature or not Snd.scanPing() then return end
    local p = getSpecificPlayer(pn)
    if not p or p:isDead() or not W.featureDecision(p, feature, "mini") then return end
    local now = getTimestampMs()
    local last = lastPing[pn]
    if last and now >= last and now - last < Snd.SCAN_MERGE_MS then return end
    lastPing[pn] = now
    Snd.play(p, Snd.SCAN)
end

-- ===== 註冊（OnGameStart：所有 MOD 的 client 檔都已載入）=====
-- 齒輪設定的分類要 settingsApiVersion >= 4（sliders；v3 會丟掉滑桿）：不足就不註冊、log 一次，ESC 選項照樣能改。
-- 分類所有玩家都看得到（沒有 visible）；owner 和「地圖錶管理」分開（同 owner 再註冊＝覆蓋）。
-- icon／group／order 是 settingsApiVersion 5 的欄位（設定視窗「擴充功能」群組的圖標與排序），舊版主 MOD 忽略。
Snd.SECTION = {
    label = "IGUI_MinidoracatWatch_Sound_Section",
    icon = "watch", group = "addon", order = 12,
    sliders = { { label = "IGUI_MinidoracatWatch_Sound_Volume", tooltip = "IGUI_MinidoracatWatch_Sound_Volume_tooltip",
        min = 0, max = 100, step = 5, default = Snd.VOLUME_DEFAULT, fmt = "%d%%", get = Snd.volume, set = Snd.setVolume } },
    ticks = { { label = "IGUI_MinidoracatWatch_Sound_ScanPing", tooltip = "IGUI_MinidoracatWatch_Sound_ScanPing_tooltip",
        default = false, get = Snd.scanPing, set = Snd.setScanPing },
        { label = "IGUI_MinidoracatWatch_ShowButton", tooltip = "IGUI_MinidoracatWatch_ShowButton_tooltip",
        default = true, get = Snd.showButtonOpt, set = Snd.setShowButton } },
}
Snd.OWNER = W.MOD_ID .. ":player"

function Snd.register()
    local api = MinidoracatMiniMapAPI
    local isApi = type(api) == "table"
    Snd.scanActive, Snd.sectionActive = false, false
    if isApi and type(api.scanApiVersion) == "number" and api.scanApiVersion >= 1
            and type(api.registerScanListener) == "function" then
        local ok, res = pcall(api.registerScanListener, W.MOD_ID, Snd.onScan)
        Snd.scanActive = ok and res == true
    end
    if not Snd.scanActive then W.log("MinidoracatMiniMapAPI.scanApiVersion >= 1 not found: no scan update sound") end
    Snd.SECTION.ticks[1].tooltip = Snd.scanActive and "IGUI_MinidoracatWatch_Sound_ScanPing_tooltip"
        or "IGUI_MinidoracatWatch_Sound_ScanPing_old"
    if isApi and type(api.settingsApiVersion) == "number" and api.settingsApiVersion >= 4
            and type(api.registerSettingsSection) == "function" then
        local ok, res = pcall(api.registerSettingsSection, Snd.OWNER, Snd.SECTION)
        Snd.sectionActive = ok and res == true
    end
    if not Snd.sectionActive then
        W.log("MinidoracatMiniMapAPI.settingsApiVersion >= 4 not found: watch sound settings only in the ESC mod options")
    end
end
Events.OnGameStart.Add(Snd.register)
