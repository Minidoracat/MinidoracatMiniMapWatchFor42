# -*- coding: utf-8 -*-
"""Watch 專屬檢查：scripts/verify_mod.py（家族模板副本）第 19 項會呼叫；單獨跑 `python scripts/verify_local.py`。
2026-11-26 verify_mod.py 換成家族模板時，從舊副本原樣搬來模板沒有的檢查：
  6b. 原版 UI 元件禁用      — client 一律用家族 UI 框架；例外 ISContextMenu／ISUIElement
  16. Lua 字串字面值只有 ASCII — Kahlua LexState 以 (byte)c 存 token（LexState.java:194-199），中文字面值變亂碼；
                          依序切出註解與字串再掃（模板第 4b 項逐行從 -- 切開，字串裡有 -- 的同一行會漏掃）
  18. craftRecipe 腳本      — module Base、輸入 token（mode／flags／tags 照 InputScript 的 throw 路徑）、物品引用存在、
                          OnTest 有 Lua 實作、OnAddToMenu 是 Lua 的全域函式、四語 Recipes.json；任一錯誤整條配方靜默消失
  19. 七款錶資產完整        — 每款左右手物品、自己的 clothing xml＋GUID、模型與貼圖檔、圖示、四語說明、全名不含 Classic、
                          自製圖示不帶 Color*（會被染色）
  17. Lua 單元測試          — scripts/test_*.lua 自動全跑（非零碼＝FAIL）；PATH 沒有 lua 則 SKIP；先自檢判定方式
  21. 看錶動畫是最新          — scripts/look_anim.py --check：四支 clip 與四個節點 xml 等於重新產生的結果（手改產出、改了
                          產生器沒重產、遊戲更新改了原版 clip 都會不過）。需要遊戲的 anims_X/Bob（PZ_PATH），找不到則 SKIP
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

passed, failed, skipped = [], [], []


def ok(label):
    passed.append(label)
    print(f"  PASS  {label}")


def fail(label, details=None):
    # 不讀 verify_ignore.txt，verify_mod.py 第 19 項也不對本檔輸出套用豁免：要豁免就在本檔處理
    details = details or []
    if not details:
        # 呼叫端說「失敗」卻沒附細節：照失敗算，不能因為清單是空的就變成 PASS
        details = ["（呼叫端沒有附失敗細節）"]
    failed.append(label)
    print(f"  FAIL  {label}")
    for d in details:
        print(f"        {d}")


def skip(label, why):
    skipped.append(label)
    print(f"  SKIP  {label} — {why}")


def find_media():
    hits = []
    mod_root = os.path.join(REPO, "MOD")
    if os.path.isdir(mod_root):
        for folder in os.listdir(mod_root):
            p = os.path.join(mod_root, folder, "Contents", "mods")
            if not os.path.isdir(p):
                continue
            for inner in os.listdir(p):
                media = os.path.join(p, inner, "42", "media")
                if os.path.isdir(media):
                    hits.append(media)
    return hits


def iter_files(root, exts):
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in (".git",)]
        for name in files:
            if os.path.splitext(name)[1] in exts:
                yield os.path.join(base, name)


MEDIA_DIRS = find_media()
if not MEDIA_DIRS:
    print("找不到 MOD/*/Contents/mods/*/42/media，中止")
    sys.exit(2)

LUA_FILES = [f for m in MEDIA_DIRS for f in iter_files(os.path.join(m, "lua"), {".lua"})
             if os.path.isdir(os.path.join(m, "lua"))]

PZ_PATH = os.environ.get("PZ_PATH", r"D:\SteamLibrary\steamapps\common\ProjectZomboid")

# ---- 6b. 原版 UI 元件禁用（本 repo）----
# 規劃書 §0 使用者裁定：面板、按鈕與所有控制項一律用家族 UI 框架（MinidoracatUIFor42）的元件，不用原版外觀。
# 允許的例外：ISContextMenu（物品右鍵選單，引擎的選單，不是面板控制項）；ISUIElement（槽位區這種自繪元件的
# 基底，外觀全由 theme token＋Skin＋Icons 畫，不帶原版外觀）。
BANNED_UI = ("ISButton", "ISPanel", "ISPanelJoypad", "ISCollapsableWindow", "ISModalDialog", "ISModalRichText",
             "ISTickBox", "ISComboBox", "ISScrollingListBox", "ISTextEntryBox", "ISRadioButtons", "ISSliderPanel")
hits_ui = []
for f in LUA_FILES:
    if os.sep + "client" + os.sep not in f:
        continue
    rel = os.path.relpath(f, REPO)
    with open(f, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            code = line.split("--", 1)[0]
            for name in BANNED_UI:
                if re.search(rf"(?<![\w_]){name}(?![\w_])", code):
                    hits_ui.append(f"{rel}:{lineno} 用了 {name}")
fail("原版 UI 元件禁用（用 UI 框架；例外 ISContextMenu／ISUIElement）", hits_ui) if hits_ui \
    else ok("原版 UI 元件禁用（用 UI 框架；例外 ISContextMenu／ISUIElement）")

# ---- 16. Lua 字串字面值禁非 ASCII ----
# Kahlua 的 LexState 把 token 存進 byte[]、以 (byte)c 截斷（LexState.java:194-199），中文字面值送到畫面是亂碼；
# luac 與標準 Lua 測試都照 UTF-8 處理、攔不住。註解可以寫中文，只掃字串（含長字串）。
_LUA_STR = re.compile(r"--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[(.*?)\]\2\]|\"((?:\\.|[^\"\\\n])*)\"|'((?:\\.|[^'\\\n])*)'", re.S)
bad = []
for f in LUA_FILES:
    with open(f, encoding="utf-8") as fh:
        src = fh.read()
    for mm in _LUA_STR.finditer(src):
        body = mm.group(3) or mm.group(4) or mm.group(5) or ""
        if any(ord(ch) > 127 for ch in body):
            bad.append(f"{os.path.relpath(f, REPO)}:{src.count(chr(10), 0, mm.start()) + 1} {body[:30]}")
fail("Lua 字串字面值只有 ASCII（玩家文字放翻譯檔）", bad) if bad \
    else ok("Lua 字串字面值只有 ASCII（玩家文字放翻譯檔）")

# ---- 18. craftRecipe 腳本 ----
# 引擎逐 token 解析輸入行（InputScript.java:617-766）：mode 的 key 字面大小寫敏感（:666）、值不分大小寫，非法值與
# 不認得的 token 當下 throw（:687、:762）；flags 走 InputFlag.valueOf，無 trim、大小寫敏感（:744-748）。任一 throw
# 整條配方消失、玩家端零訊息。配方必須在 module Base（短名引用只查 Base，家族 pitfalls.md「CraftRecipe 學習管線」）；
# 引用的物品要真的存在（本 MOD 的看 scripts、Base.* 看原版 scripts，找不到原版就只驗本 MOD）；OnTest 的「表.函式」
# 要有 Lua 實作；OnAddToMenu 經 callLuaBool 只用全域名稱查（LuaManager.java:5745-5746），點號或查不到＝配方永遠不列出；
# 配方名在四語 Recipes.json 都有翻譯（Translator.getRecipeName，Translator.java:691-699）。
# 名單抄 AutoDrive verify_mod.py（42.20.4 InputFlag.java 逐字）；引擎升版新增 flag 時這裡會假紅——補名單即可。
VALID_ITEM_MODES = {"use", "keep", "destroy", "useprop1", "useprop2", "keepprop1", "keepprop2", "prop1", "prop2"}
INPUT_FLAGS = {
    "HandcraftOnly", "AutomationOnly", "IsFull", "NotFull", "ItemIsUses", "ItemIsFluid", "ItemIsEnergy", "IsEmpty",
    "NotEmpty", "Prop1", "Prop2", "ToolLeft", "ToolRight", "IsDamaged", "IsUndamaged", "IsWholeFoodItem",
    "IsEmptyContainer", "IsUncookedFoodItem", "IsCookedFoodItem", "IsNotDull", "IsHeadPart", "IsSharpenable",
    "DontPutBack", "InheritColor", "InheritCondition", "InheritEquipped", "InheritSharpness", "InheritHeadCondition",
    "MayDegrade", "MayDegradeLight", "MayDegradeVeryLight", "MayDegradeHeavy", "SharpnessCheck", "InheritUses",
    "InheritUsesAndEmpty", "InheritFood", "InheritFoodAge", "InheritCooked", "InheritModelVariation", "InheritWeight",
    "InheritName", "InheritFreezingTime", "DontInheritCondition", "AllowFrozenItem", "AllowRottenItem", "NoBrokenItems",
    "AllowDestroyedItem", "IsWorn", "IsNotWorn", "InheritAmmunition", "CopyClothing", "AllowFavorite", "InheritFavorite",
    "FakeOutput", "DontReplace", "CanBeDoneFromFloor", "ItemCount", "IsExclusive", "RecordInput", "DontRecordInput",
    "ResearchInput", "IsBlunt", "HasOneUse", "HasNoUses", "IsSealed", "IsNotSealed", "Unseal", "EquipSecondary",
    "SetActivated",
}
RECIPE_REQUIRED = ("timedAction", "time", "category")


def recipe_input_errors(rest):
    """一條輸入行數量之後的 token；回錯誤清單（空＝引擎載得進來）。"""
    errs = []
    for tok in rest.split():
        t = tok.rstrip(",")
        if not t:
            continue
        lb, rb = t.find("["), t.find("]")
        if t.startswith("mode:"):
            if t[5:].lower() not in VALID_ITEM_MODES:
                errs.append(f"`{t}` 非法 mode（InputScript.java:687 throw）")
        elif t.startswith("[") or t.startswith("tags") or t.startswith("flags") or t.startswith("mappers"):
            if lb < 0 or rb < lb:
                errs.append(f"`{t}` 缺括號（substring 越界 throw）")
            elif t.startswith("flags"):
                errs += [f"flags 值 `{e}` 不在 InputFlag（valueOf throw，:748）"
                         for e in t[lb + 1:rb].split(";") if e not in INPUT_FLAGS]
            elif t.startswith("tags"):
                errs += [f"tags 項 `{e}` 空值或空 namespace（ResourceLocation.of throw）"
                         for e in t[lb + 1:rb].split(";") if not e or e.startswith(":") or e.endswith(":")]
        elif t.startswith("categories") or t.startswith("apply:"):
            errs.append(f"`{t}` 不能用在物品輸入（InputScript.java:663、:735 throw）")
        elif not t.startswith("overlayMapper") and not t.startswith("shapedIndex:"):
            errs.append(f"`{t}` 不認得的參數（InputScript.java:762 throw）")
    return errs


def script_blocks(text, kind):
    """(module, 名稱, 內文) 清單；內文含巢狀 inputs/outputs。text 已去掉註解。"""
    out = []
    for mm in re.finditer(r"(?m)^\s*module\s+(\w+)\s*\{", text):
        depth, i, start = 1, mm.end(), mm.end()
        while i < len(text) and depth:
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        body = text[start:i - 1]
        for bm in re.finditer(rf"(?m)^\s*{kind}\s+(\w+)\s*\{{", body):
            d, j = 1, bm.end()
            while j < len(body) and d:
                d += {"{": 1, "}": -1}.get(body[j], 0)
                j += 1
            out.append((mm.group(1), bm.group(1), body[bm.end():j - 1]))
    return out


# 原版物品（Base.*）：掃一次原版 scripts；找不到遊戲就不驗 Base.*（寫進標籤）
_vanilla_items = None
_vs = os.path.join(PZ_PATH, "media", "scripts")
if os.path.isdir(_vs):
    _vanilla_items = set()
    for f in iter_files(_vs, {".txt"}):
        with open(f, encoding="utf-8", errors="replace") as fh:
            _vanilla_items.update(re.findall(r"(?m)^\s*item\s+(\w+)\s*\{?\s*$", fh.read()))

_lua_src = ""
for f in LUA_FILES:
    with open(f, encoding="utf-8") as fh:
        _lua_src += fh.read() + "\n"

recipe_bad, recipe_names, mod_items = [], [], set()
for m in MEDIA_DIRS:
    sdir = os.path.join(m, "scripts")
    if not os.path.isdir(sdir):
        continue
    texts = []
    for f in iter_files(sdir, {".txt"}):
        with open(f, encoding="utf-8") as fh:
            texts.append((os.path.relpath(f, REPO), re.sub(r"/\*.*?\*/", "", fh.read(), flags=re.S)))
    for _, txt in texts:
        for module, name, _ in script_blocks(txt, "item"):
            mod_items.add(f"{module}.{name}")
    for rel, txt in texts:
        for module, name, body in script_blocks(txt, "craftRecipe"):
            recipe_names.append(name)
            where = f"{rel} craftRecipe {name}"
            if module != "Base":
                recipe_bad.append(f"{where}：在 module {module}，要放 module Base")
            for key in RECIPE_REQUIRED:
                if not re.search(rf"(?m)^\s*{key}\s*=", body):
                    recipe_bad.append(f"{where}：缺 {key}")
            ot = re.search(r"(?m)^\s*OnTest\s*=\s*([\w.]+)\s*,", body)
            if ot and not re.search(rf"function\s+{re.escape(ot.group(1))}\s*\(|{re.escape(ot.group(1))}\s*=\s*function",
                                    _lua_src):
                recipe_bad.append(f"{where}：OnTest {ot.group(1)} 在 Lua 裡找不到")
            om = re.search(r"(?m)^\s*OnAddToMenu\s*=\s*([\w.]+)\s*,", body)
            if om and ("." in om.group(1) or not re.search(rf"(?m)^function\s+{re.escape(om.group(1))}\s*\(", _lua_src)):
                recipe_bad.append(f"{where}：OnAddToMenu {om.group(1)} 要是 Lua 裡的全域函式（不能有點號）")
            for k in ("inputs", "outputs"):
                sm = re.search(rf"(?ms)^\s*{k}\s*\{{(.*?)^\s*\}}", body)
                if not sm:
                    recipe_bad.append(f"{where}：缺 {k}")
                    continue
                lines = [l.strip() for l in sm.group(1).splitlines() if l.strip()]
                if not lines:
                    recipe_bad.append(f"{where}：{k} 是空的")
                for line in lines:
                    im = re.match(r"item\s+(\S+)\s+(.*?),?$", line)
                    if not im:
                        recipe_bad.append(f"{where}：{k} 這行看不懂 `{line}`")
                        continue
                    try:
                        float(im.group(1))
                    except ValueError:
                        recipe_bad.append(f"{where}：數量 `{im.group(1)}` 不是數字")
                    rest = im.group(2)
                    if k == "inputs":
                        recipe_bad += [f"{where}：{e}" for e in recipe_input_errors(rest)]
                        refs = [t.strip() for sel in re.findall(r"(?:^|\s)\[([^\]]+)\]", rest) for t in sel.split(";")]
                    else:
                        refs = rest.split()[:1]
                    for ref in refs:
                        mod_name, _, short = ref.rpartition(".")
                        if not mod_name:
                            recipe_bad.append(f"{where}：`{ref}` 要寫完整類型（module.名稱）")
                        elif mod_name == "Base":
                            if _vanilla_items is not None and short not in _vanilla_items:
                                recipe_bad.append(f"{where}：原版沒有 {ref}")
                        elif ref not in mod_items:
                            recipe_bad.append(f"{where}：本 MOD 沒有 {ref}")
    for lang in ("EN", "CH", "CN", "JP"):
        rp = os.path.join(m, "lua", "shared", "Translate", lang, "Recipes.json")
        keys = set()
        if os.path.isfile(rp):
            with open(rp, encoding="utf-8") as fh:
                keys = set(json.load(fh))
        recipe_bad += [f"{lang}/Recipes.json 缺 {n}" for n in recipe_names if n not in keys]
_rl = f"craftRecipe 腳本（{len(recipe_names)} 條：module Base、輸入 token、物品引用、OnTest、OnAddToMenu、四語配方名" + \
      ("" if _vanilla_items is not None else "；找不到原版 scripts，Base.* 未驗") + "）"
fail(_rl, recipe_bad) if recipe_bad else ok(_rl)

# ---- 19. 七款錶資產完整 ----
# 每款（shared/MinidoracatWatch.lua 的 W.STYLES）左右手兩個物品：ClothingItem 指向自己的 xml（共用原版名稱會讓殭屍的
# 原版錶變成地圖錶，ScriptManager.java:1883-1892）、xml 的 GUID 登記在 42/media/fileGuidTable.xml（OutfitManager 依
# GUID 載入）、模型與 textureChoices 貼圖檔存在、圖示貼圖存在、說明有四語翻譯、物品全名不含 Classic
# （AlarmClockClothing.java:54-66 會當成指針錶）。自製圖示的物品不可寫 ColorRed/Green/Blue（UIElement.java:548-551 染色）。
# BodyLocation 是 42/media/registries.lua 註冊的 MinidoracatWatch:<Left|Right>Wrist（原版手腕會被長袖藏起來，
# BodyLocations.lua:596-627；沒註冊的 id 解析成 null，錶戴不上）；xml 要有套袖模型 m_AltMaleModel／m_AltFemaleModel
# （穿 3D 袖子外衣時引擎改畫它，PopTemplateManager.isItemModelAlt；缺了錶帶會埋進袖子裡）。
asset_bad, n_styles = [], 0
_reg_re = re.compile(r'ItemBodyLocation\.register\("([^"]+)"\)')
for m in MEDIA_DIRS:
    core = os.path.join(m, "lua", "shared", "MinidoracatWatch.lua")
    if not os.path.isfile(core):
        continue
    with open(core, encoding="utf-8") as fh:
        sm = re.search(r"W\.STYLES\s*=\s*\{([^}]*)\}", fh.read())
    styles = re.findall(r'"(\w+)"', sm.group(1)) if sm else []
    n_styles = len(styles)
    if not styles:
        asset_bad.append("shared/MinidoracatWatch.lua 找不到 W.STYLES")
    item_bodies = {}
    for f in iter_files(os.path.join(m, "scripts"), {".txt"}):
        with open(f, encoding="utf-8") as fh:
            txt = re.sub(r"/\*.*?\*/", "", fh.read(), flags=re.S)
        for module, name, body in script_blocks(txt, "item"):
            item_bodies[f"{module}.{name}"] = body
    reg_path = os.path.join(m, "registries.lua")
    registered = set()
    if os.path.isfile(reg_path):
        with open(reg_path, encoding="utf-8") as fh:
            registered = {r.lower() for r in _reg_re.findall(fh.read())}
    guids = {}
    guid_path = os.path.join(m, "fileGuidTable.xml")
    if os.path.isfile(guid_path):
        with open(guid_path, encoding="utf-8") as fh:
            for p, g in re.findall(r"<path>([^<]+)</path>\s*<guid>([^<]+)</guid>", fh.read()):
                guids[p.replace("\\", "/")] = g
    tips = {}
    for lang in ("EN", "CH", "CN", "JP"):
        tp = os.path.join(m, "lua", "shared", "Translate", lang, "Tooltip.json")
        tips[lang] = set()
        if os.path.isfile(tp):
            with open(tp, encoding="utf-8") as fh:
                tips[lang] = set(json.load(fh))

    def tex(name, m=m):
        return os.path.isfile(os.path.join(m, "textures", name + ".png"))

    for s in styles:
        if not tex(f"Item_MinidoracatWatch_{s}"):
            asset_bad.append(f"{s}：缺圖示 textures/Item_MinidoracatWatch_{s}.png")
        for lang, keys in tips.items():
            if f"Tooltip_MinidoracatWatch_{s}" not in keys:
                asset_bad.append(f"{s}：{lang}/Tooltip.json 缺 Tooltip_MinidoracatWatch_{s}")
        for side, other in (("Left", "Right"), ("Right", "Left")):
            full = f"MinidoracatWatch.MapWatch_{s}_{side}"
            body = item_bodies.get(full)
            if body is None:
                asset_bad.append(f"缺物品 {full}")
                continue
            want = {"ClothingItem": f"MinidoracatWatch_{s}_{side}", "Icon": f"MinidoracatWatch_{s}",
                    "ClothingItemExtra": f"MinidoracatWatch.MapWatch_{s}_{other}",
                    "Tooltip": f"Tooltip_MinidoracatWatch_{s}", "BodyLocation": f"MinidoracatWatch:{side}Wrist"}
            for k, v in want.items():
                got = re.search(rf"(?m)^\s*{k}\s*=\s*([^,\r\n]+)", body)
                if not got or got.group(1).strip() != v:
                    asset_bad.append(f"{full}：{k} 應為 {v}（實得 {got.group(1).strip() if got else '未宣告'}）")
            if f"minidoracatwatch:{side.lower()}wrist" not in registered:
                asset_bad.append(f"{full}：部位 MinidoracatWatch:{side}Wrist 沒有在 42/media/registries.lua 註冊")
            xml_rel = f"media/clothing/clothingItems/MinidoracatWatch_{s}_{side}.xml"
            xml_path = os.path.join(m, "clothing", "clothingItems", f"MinidoracatWatch_{s}_{side}.xml")
            if not os.path.isfile(xml_path):
                asset_bad.append(f"{full}：缺 {xml_rel}")
                continue
            with open(xml_path, encoding="utf-8") as fh:
                x = fh.read()
            g = re.search(r"<m_GUID>([^<]+)</m_GUID>", x)
            if not g or guids.get(xml_rel) != g.group(1):
                asset_bad.append(f"{xml_rel}：GUID 沒有登記在 42/media/fileGuidTable.xml（或不一致）")
            for tag in ("m_AltMaleModel", "m_AltFemaleModel"):
                if f"<{tag}>" not in x:
                    asset_bad.append(f"{xml_rel}：缺套袖模型 <{tag}>（長袖外衣會蓋住錶帶）")
            for mdl in re.findall(r"<m_(?:Alt)?(?:Male|Female)Model>([^<]+)</m_(?:Alt)?(?:Male|Female)Model>", x):
                rel = mdl.replace("\\", "/")
                if not rel.startswith("media/") or not os.path.isfile(os.path.join(m, rel[len("media/"):])):
                    asset_bad.append(f"{xml_rel}：模型 {mdl} 不在本 MOD")
            for t in re.findall(r"<textureChoices>([^<]+)</textureChoices>", x):
                if not tex(t):
                    asset_bad.append(f"{xml_rel}：貼圖 textures/{t}.png 不存在")
    for full, body in item_bodies.items():
        if "Classic" in full and full.startswith("MinidoracatWatch.MapWatch_"):
            asset_bad.append(f"{full}：錶的物品全名不可含 Classic")
        icon = re.search(r"(?m)^\s*Icon\s*=\s*(MinidoracatWatch_\w+)", body)
        if icon and re.search(r"(?m)^\s*Color(Red|Green|Blue)\s*=", body):
            asset_bad.append(f"{full}：自製圖示不可再寫 ColorRed/Green/Blue（會被染色）")
        if icon and not tex("Item_" + icon.group(1)):
            asset_bad.append(f"{full}：圖示 textures/Item_{icon.group(1)}.png 不存在")
_al = f"七款錶資產完整（{n_styles} 款 × 左右手：物品、部位、clothing xml、GUID、模型與套袖模型、貼圖、圖示、說明）"
fail(_al, asset_bad) if asset_bad else ok(_al)

# ---- 17. Lua 單元測試（scripts/test_*.lua 自動全跑）----
# 每支測試失敗時以非零碼結束、最後一行印摘要；沒有 lua 直譯器＝SKIP（防線沒跑到，不能列 PASS）。
# 判定只看退出碼與有沒有輸出，細節一律帶退出碼：沒輸出的非零退出也必須是 FAIL。
def lua_test_verdict(lua_bin, script, cwd):
    """回 (True, 摘要) 或 (False, 細節清單)。"""
    r = subprocess.run([lua_bin, script], capture_output=True, cwd=cwd)
    lines = [l for l in (r.stdout or b"").decode("utf-8", "replace").splitlines() if l.strip()]
    err_tail = [l for l in (r.stderr or b"").decode("utf-8", "replace").splitlines() if l.strip()][-3:]
    if r.returncode != 0:
        return False, [f"退出碼 {r.returncode}"] + lines[-3:] + err_tail
    if not lines:
        return False, ["退出碼 0 但沒有任何輸出"] + err_tail
    return True, lines[-1]


_lua_bin = shutil.which("lua")
if not _lua_bin:
    skip("Lua 測試執行器自檢", "PATH 沒有 lua")
else:
    # 自檢：沒輸出的 exit 1、沒輸出的 exit 0、error() 都要判 FAIL，有摘要的 exit 0 判 PASS
    _self_bad = []
    with tempfile.TemporaryDirectory() as _td:
        for _name, _src, _want in (("silent_exit1.lua", "os.exit(1)", False),
                                   ("silent_exit0.lua", "os.exit(0)", False),
                                   ("error.lua", "error('boom')", False),
                                   ("good.lua", "print('x: 1 checks OK')", True)):
            with open(os.path.join(_td, _name), "w", encoding="utf-8") as _fh:
                _fh.write(_src + "\n")
            _got, _ = lua_test_verdict(_lua_bin, _name, _td)
            if _got != _want:
                _self_bad.append(f"{_name}：預期 {'PASS' if _want else 'FAIL'}，得到 {'PASS' if _got else 'FAIL'}")
    fail("Lua 測試執行器自檢", _self_bad) if _self_bad else ok("Lua 測試執行器自檢（非零退出與無輸出都判 FAIL）")

_tests = sorted(n for n in os.listdir(os.path.join(REPO, "scripts")) if re.fullmatch(r"test_.*\.lua", n))
for _script in _tests:
    _gate = f"Lua 單元測試（{_script}）"
    if not _lua_bin:
        skip(_gate, "PATH 沒有 lua")
        continue
    _ok, _info = lua_test_verdict(_lua_bin, f"scripts/{_script}", REPO)
    ok(f"{_gate}：{_info}") if _ok else fail(_gate, _info)

# ---- 21. 看錶動畫是最新（scripts/look_anim.py --check）----
_t = "看錶動畫與節點等於 look_anim.py 重新產生的結果"
_bob = os.path.join(PZ_PATH, "media", "anims_X", "Bob")
if not os.path.isdir(_bob) or not shutil.which("uv"):
    skip(_t, f"找不到遊戲的 {_bob}（設定 PZ_PATH）或 PATH 沒有 uv")
else:
    _r = subprocess.run(["uv", "run", "--quiet", "scripts/look_anim.py", "--src", _bob, "--check"], cwd=REPO,
                        capture_output=True, text=True, encoding="utf-8", errors="replace")
    ok(_t) if _r.returncode == 0 else fail(_t, (_r.stdout + _r.stderr).strip().splitlines()[-8:])

print()
print(f"PASS {len(passed)} / FAIL {len(failed)} / SKIP {len(skipped)}")
sys.exit(1 if failed else 0)
