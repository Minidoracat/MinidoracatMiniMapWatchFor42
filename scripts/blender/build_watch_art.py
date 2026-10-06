# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "numpy", "resvg-py==0.5.0"]
# ///
"""地圖錶美術一鍵重建：設計稿 SVG → 貼圖、七款手腕模型（.X）、物品欄圖示。

用法（repo 根目錄）：
    uv run scripts/blender/build_watch_art.py [--pz "D:/SteamLibrary/steamapps/common/ProjectZomboid"]
        [--blender "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"] [--only ValuTech,Paws]

產物（直接寫進 MOD 的 42/media/）：
    models_X/Static/Clothes/MinidoracatWatch_<款>_<M|F>_<Left|Right>.x   手腕模型（掛 Bip01_{L,R}_Forearm，靜態）
    textures/MinidoracatWatch_<款>.png（嗶嗶腕機另有 _Amber）             模型貼圖 256×256
    textures/Item_MinidoracatWatch_<款>.png、_Module_<模組>.png、_UnlockCard_<等級>.png   32×32 物品欄圖示
中間產物與預覽（不進 MOD、不進版控）：temp/watch-art/（verify.txt、icons_sheet.png、blender/*.png）

需求：node（跑設計稿 design/export_design.mjs）、Blender 5.2（算錶的圖示原圖）、本機 PZ（只讀手臂網格量尺寸，不複製）。
字型：Barlow、IBM Plex Mono（SIL OFL 1.1，fonts/），只烘進 PNG。
"""
import argparse
import io
import json
import os
import subprocess
import sys

import numpy as np
import resvg_py
from PIL import Image, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MEDIA = os.path.join(REPO, "MOD", "MinidoracatMiniMapWatchFor42", "Contents", "mods", "MinidoracatMiniMapWatchFor42", "42", "media")
OUT = os.path.join(REPO, "temp", "watch-art")
FONTS = [os.path.join(HERE, "fonts", f) for f in ("Barlow-SemiBold.ttf", "IBMPlexMono-SemiBold.ttf")]
sys.path.insert(0, HERE)
import watch_model as wm  # noqa: E402

PREFIX = "MinidoracatWatch"
SIDES = {"L": "Left", "R": "Right"}
# 錶帶花紋取設計稿上方錶帶 y 0..STRAP_CROP（不要切到錶殼／貓耳）
STRAP_CROP = {"Paws": 42, "BB3000": 46}

# 模組：設計稿 data.mjs MODULES 的類別（一般／進階／核心）→ TIERS 顏色；圖示顏色沿用目前物品腳本的 ColorRed/Green/Blue。
MODULES = [
    ("Compass", "compass", "std", "#E6C85A"), ("Ledger", "ledger", "std", "#D7823C"), ("GPS", "gps", "std", "#5AC86E"),
    ("Comm", "comm", "std", "#508CE6"), ("Scan", "scan", "std", "#3CC8C8"), ("Detect", "detect", "std", "#E15050"),
    ("Light", "light", "std", "#FFD36E"), ("MilDetect", "mildetect", "adv", "#96AA50"), ("LongComm", "longcomm", "adv", "#508CE6"),
    ("Relay", "relay", "core", "#AA6EF0"), ("Eco", "eco", "core", "#6EDC8C"),
]
TIER_COL = {"std": "#A7B0BA", "ext": "#3FB27F", "adv": "#4C8DF6", "core": "#A970F0"}
CARDS = [("Ext", "ext", 1), ("Adv", "adv", 2), ("Core", "core", 3)]


def svg_doc(inner, vb, w, h, bg=None):
    x, y, vw, vh = vb
    inner = (inner.replace("Bahnschrift, 'Arial Narrow', sans-serif", "Barlow")
             .replace("Georgia, 'Times New Roman', serif", "Barlow")
             .replace("Consolas, 'Courier New', monospace", "IBM Plex Mono"))
    back = f'<rect x="{x}" y="{y}" width="{vw}" height="{vh}" fill="{bg}"/>' if bg else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x} {y} {vw} {vh}" width="{w}" height="{h}">{back}{inner}</svg>'


def render(svg):
    png = resvg_py.svg_to_bytes(svg_string=svg, skip_system_fonts=True, font_files=FONTS, font_family="Barlow",
                                sans_serif_family="Barlow", serif_family="Barlow", monospace_family="IBM Plex Mono")
    return Image.open(io.BytesIO(bytes(png))).convert("RGBA")


def texture(sid, svg_id, design, perim):
    st = wm.STYLES[sid]
    sw = st["swatches"]
    atlas = Image.new("RGBA", (wm.TEX, wm.TEX), sw[0])
    svg = design["watches"][svg_id]
    for old, new in st.get("recolor", {}).items():  # 只動 3D 貼圖（遊戲光照下太暗的面），圖示照設計稿
        svg = svg.replace(old, new)
    face = render(svg_doc(svg, wm.FACE_VB, wm.FACE_PX, wm.FACE_PX, bg=sw[0]))
    atlas.paste(face, (0, 0))
    # 錶帶：上方錶帶那段裁出來，依錶帶周長縱向平鋪（UV 把整圈對到這一條）
    sx0, sx1 = st["strap"]
    crop_h = STRAP_CROP.get(sid, 58)
    x0, y0, x1, y1 = wm.STRIP
    tile = render(svg_doc(svg, (sx0, 0, sx1 - sx0, crop_h), x1 - x0, round((x1 - x0) * crop_h / (sx1 - sx0)), bg=sw[1]))
    k = st.get("k", {}).get("M", (wm.K_WATCH["M"],))[0]
    n = max(1, round(perim / (crop_h * k)))
    th = (y1 - y0) / n
    for i in range(n):
        atlas.paste(tile.resize((x1 - x0, max(1, round(th)))), (x0, y0 + round(i * th)))
    for i in range(wm.TEX // wm.SW_W):
        atlas.paste(Image.new("RGBA", (wm.SW_W, wm.SW_H), sw[i] if i < len(sw) else sw[0]), (i * wm.SW_W, wm.SW_Y))
    atlas.putalpha(255)
    return atlas.convert("RGB")


def perimeter(sec, n=128):
    _, cy, cz, ay, az = sec
    e = 2 / wm.P_EXP
    pts = [(ay * wm.spow(np.cos(t), e), az * wm.spow(np.sin(t), e)) for t in np.linspace(0, 2 * np.pi, n + 1)]
    return float(sum(np.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:])))


def to_icon(im, tilt=0.0):
    """原版物品圖示風格（UI2.pack 的 Item_DigitalWatch_Black 對照）：32×32 透明底、物體約 28 px、1 px 深色外框。"""
    if tilt:
        im = im.rotate(tilt, resample=Image.BICUBIC, expand=True)
    bbox = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    im = im.crop(bbox)
    s = 28.0 / max(im.size)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    a = im.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    im = ImageEnhance.Sharpness(ImageEnhance.Contrast(im.convert("RGB")).enhance(1.15)).enhance(1.3)
    im.putalpha(a)
    canvas = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    canvas.paste(im, ((32 - im.width) // 2, (32 - im.height) // 2), im)
    ring = canvas.getchannel("A").filter(ImageFilter.MaxFilter(3))
    out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (32, 32), (28, 26, 24, 255)), (0, 0), ring)
    out.paste(canvas, (0, 0), canvas)
    return out


def module_svg(design, glyph, tier, color):
    """模組晶片：深色電路板＋上緣金手指＋等級色邊框，中間是設計稿的模組圖示。"""
    g = design["icons"][glyph]
    g = g[g.index(">") + 1:g.rindex("</svg>")]
    pins = "".join(f'<rect x="{11 + i * 6}" y="6" width="3.2" height="7" rx="1" fill="#D9B45A"/>' for i in range(8))
    return (f'<g transform="rotate(-12 32 32)">{pins}'
            f'<rect x="8" y="11" width="48" height="44" rx="5" fill="#23282E" stroke="{TIER_COL[tier]}" stroke-width="4"/>'
            f'<g transform="translate(16 18) scale(1.33)" fill="none" stroke="{color}" stroke-width="2.3" stroke-linecap="round" '
            f'stroke-linejoin="round" style="color:{color}">{g}</g></g>')


def card_svg(tier, pips):
    """解鎖卡：等級色卡片＋磁條＋晶片，右下角 1／2／3 顆點分等級（不單靠顏色）。"""
    c = TIER_COL[tier]
    dots = "".join(f'<circle cx="{46 - i * 7}" cy="44" r="2.6" fill="#F4F6F8"/>' for i in range(pips))
    return (f'<g transform="rotate(-18 32 32)"><rect x="4" y="14" width="56" height="36" rx="5" fill="{c}" stroke="#1C1A18" stroke-width="1"/>'
            f'<rect x="4" y="20" width="56" height="6" fill="#1C1A18" opacity=".75"/>'
            f'<rect x="10" y="32" width="11" height="8" rx="1.5" fill="#E8D08A"/><path d="M10 36h11M15.5 32v8" stroke="#B8994A" stroke-width=".8"/>'
            f'{dots}</g>')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pz", default="D:/SteamLibrary/steamapps/common/ProjectZomboid")
    ap.add_argument("--blender", default="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s] or list(wm.STYLES)
    os.makedirs(OUT, exist_ok=True)
    design = json.loads(subprocess.run(["node", os.path.join(HERE, "design", "export_design.mjs")],
                                       check=True, capture_output=True, text=True, encoding="utf-8").stdout)
    arms = {g: wm.read_arm(os.path.join(a.pz, "media", "models_X", "Skinned", f"{body}.x"))
            for g, body in (("M", "MaleBody"), ("F", "FemaleBody"))}
    clothes = os.path.join(MEDIA, "models_X", "Static", "Clothes")
    tex_dir = os.path.join(MEDIA, "textures")
    os.makedirs(clothes, exist_ok=True)
    os.makedirs(tex_dir, exist_ok=True)
    verify = []
    for sid in only:
        st = wm.STYLES[sid]
        perim = None
        for g in ("M", "F"):
            for s, side in SIDES.items():
                mesh, info = wm.build(sid, g, s, arms[g])
                name = f"{PREFIX}_{sid}_{g}_{side}"
                path = os.path.join(clothes, name + ".x")
                wm.write_x(mesh, path, name, f"{PREFIX}_{sid}.png")
                V, F, UV = wm.read_x(path)  # 讀回：三角形數、範圍、UV 都在 0..1
                lo, hi = info["bbox"]
                assert len(F) == info["tris"] and F.max() < len(V), name
                assert np.allclose(V.min(0), lo, atol=2e-6) and np.allclose(V.max(0), hi, atol=2e-6), name
                assert UV.min() >= 0 and UV.max() <= 1, name
                if g == "M" and s == "L":
                    perim = perimeter((0.0,) + wm._interp(info["sections"], st.get("xc", wm.WATCH_XC)))
                verify.append(f"{name}: tris={info['tris']} arm-in-strap={info['worst']:.2f} "
                              f"bbox=({', '.join(f'{v:.4f}' for v in lo)})..({', '.join(f'{v:.4f}' for v in hi)})")
        texture(sid, st["svg"], design, perim).save(os.path.join(tex_dir, f"{PREFIX}_{sid}.png"))
        for alt, svg_id in st.get("svg_alt", {}).items():
            texture(sid, svg_id, design, perim).save(os.path.join(tex_dir, f"{PREFIX}_{sid}_{alt}.png"))

    # 預覽（人看的，不進 MOD）：Blender 用剛寫好的模型與貼圖算正面、斜側面
    bdir = os.path.join(OUT, "blender")
    os.makedirs(bdir, exist_ok=True)
    subprocess.run([a.blender, "-b", "--factory-startup", "--python", os.path.join(HERE, "watch_blender.py"), "--",
                    MEDIA, bdir, a.pz, ",".join(only)], check=True)
    # 錶的圖示照設計稿 watchIcon：viewBox 14 38 172 172 裁成正方形、只看錶殼（3D 斜看時錶帶環比錶面還大，28 px 下看不出款式）
    icons = []
    for sid in only:
        ic = to_icon(render(svg_doc(design["watches"][wm.STYLES[sid]["svg"]], (14, 38, 172, 172), 256, 256)))
        ic.save(os.path.join(tex_dir, f"Item_{PREFIX}_{sid}.png"))
        icons.append((f"Item_{PREFIX}_{sid}", ic))
    for mid, glyph, tier, color in MODULES:
        ic = to_icon(render(svg_doc(module_svg(design, glyph, tier, color), (0, 0, 64, 64), 256, 256)))
        ic.save(os.path.join(tex_dir, f"Item_{PREFIX}_Module_{mid}.png"))
        icons.append((f"Item_{PREFIX}_Module_{mid}", ic))
    for cid, tier, pips in CARDS:
        ic = to_icon(render(svg_doc(card_svg(tier, pips), (0, 0, 64, 64), 256, 256)))
        ic.save(os.path.join(tex_dir, f"Item_{PREFIX}_UnlockCard_{cid}.png"))
        icons.append((f"Item_{PREFIX}_UnlockCard_{cid}", ic))

    # 預覽總表：原尺寸＋放大 4 倍，灰底（接近物品欄底色）
    sheet = Image.new("RGBA", (len(icons) * 36 + 4, 40), (62, 62, 62, 255))
    for i, (_, ic) in enumerate(icons):
        sheet.paste(ic, (4 + i * 36, 4), ic)
    sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save(os.path.join(OUT, "icons_sheet.png"))
    with open(os.path.join(OUT, "verify.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(verify + [f"icon {n}" for n, _ in icons]) + "\n")
    print("\n".join(verify))
    print(f"icons: {len(icons)} → {tex_dir}")


if __name__ == "__main__":
    main()
