# -*- coding: utf-8 -*-
"""地圖錶面板的槽位外形貼圖（白色＋alpha，遊戲裡以頂點色染色）。

座標照設計稿 panel.mjs 的 SHAPES（56×56 viewBox）：sel＝選取外框（描邊）、ring＝等級色環、fill＝槽底、
deco＝貼紙底（Spiffo）。另有貓耳三角形（貓爪款面板頂端的裝飾）。4 倍超取樣後縮成 2 倍尺寸（112×112），
遊戲裡縮到 56／40px 畫。產物位元級可重現：重跑後 md5 不變。
用法（repo 根目錄）：python scripts/gen_watch_ui_textures.py
"""
import math
import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "MOD", "MinidoracatMiniMapWatchFor42", "Contents", "mods",
                   "MinidoracatMiniMapWatchFor42", "42", "media", "ui", "MinidoracatWatch")
SS = 8      # 超取樣倍率（相對 viewBox）
OUT_K = 2   # 輸出倍率：56 → 112
SEL_W = 2.8  # 選取外框描邊寬（設計稿 .sock-sel stroke-width）


def hex_pts(r):
    return [(28 + r * math.cos(math.pi / 3 * i), 28 + r * math.sin(math.pi / 3 * i)) for i in range(6)]


def oct_pts(m, c):
    return [(m + c, m), (56 - m - c, m), (56 - m, m + c), (56 - m, 56 - m - c), (56 - m - c, 56 - m), (m + c, 56 - m),
            (m, 56 - m - c), (m, m + c)]


def arc(cx, cy, r, a0, a1, n=48):
    return [(cx + r * math.cos(a0 + (a1 - a0) * k / n), cy + r * math.sin(a0 + (a1 - a0) * k / n)) for k in range(n + 1)]


def cat_pts():
    # M10.5 23 L12.5 6 L23 13.4 A19.5 19.5 0 0 1 33 13.4 L43.5 6 L45.5 23 A19.5 19.5 0 1 1 10.5 23 Z
    head = math.sqrt(19.5 ** 2 - 5 ** 2)       # 兩耳之間的小弧：圓心在弦下方
    chin = math.sqrt(19.5 ** 2 - 17.5 ** 2)    # 臉頰的大弧：繞過下巴
    a0, a1 = math.atan2(13.4 - (13.4 + head), 23 - 28), math.atan2(13.4 - (13.4 + head), 33 - 28)
    b0, b1 = math.atan2(23 - (23 + chin), 45.5 - 28), math.atan2(23 - (23 + chin), 10.5 - 28) + 2 * math.pi
    return [(10.5, 23), (12.5, 6)] + arc(28, 13.4 + head, 19.5, a0, a1) + [(43.5, 6)] + arc(28, 23 + chin, 19.5, b0, b1)


def scaled(pts, cx, cy, k):
    return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in pts]


def rrect(x, y, w, h, r):
    if r <= 0:
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    pts = []
    for cx, cy, a in ((x + w - r, y + r, -math.pi / 2), (x + w - r, y + h - r, 0), (x + r, y + h - r, math.pi / 2),
                      (x + r, y + r, math.pi)):
        pts += arc(cx, cy, r, a, a + math.pi / 2, 12)
    return pts


def circle(r):
    return arc(28, 28, r, 0, 2 * math.pi, 96)[:-1]


def canvas(w=56, h=56):
    img = Image.new("L", (w * SS, h * SS), 0)
    return img, ImageDraw.Draw(img)


def up(pts):
    return [(x * SS, y * SS) for x, y in pts]


def filled(pts, w=56, h=56):
    img, d = canvas(w, h)
    d.polygon(up(pts), fill=255)
    return img


def stroked(paths, width, closed=True, w=56, h=56):
    img, d = canvas(w, h)
    for pts in paths:
        p = up(pts) + (up(pts[:1]) if closed else [])
        d.line(p, fill=255, width=round(width * SS), joint="curve")
        r = width * SS / 2
        for x, y in p:  # 圓頭：線段接點補圓，轉角不缺角
            d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    return img


def save(name, alpha):
    w, h = alpha.size
    alpha = alpha.resize((w * OUT_K // SS, h * OUT_K // SS), Image.LANCZOS)
    out = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    out.save(os.path.join(OUT, name + ".png"), optimize=False)


CRT_BRACKETS = [[(5, 17), (5, 5), (17, 5)], [(39, 5), (51, 5), (51, 17)], [(51, 39), (51, 51), (39, 51)],
                [(17, 51), (5, 51), (5, 39)]]

SHAPES = {
    "hex": {"sel": stroked([hex_pts(28 - SEL_W / 2)], SEL_W), "ring": filled(hex_pts(25)), "fill": filled(hex_pts(22.5))},
    "cat": {"sel": stroked([scaled(cat_pts(), 28, 30, 1.12)], SEL_W), "ring": filled(cat_pts()),
            "fill": filled(scaled(cat_pts(), 28, 31, 0.86))},
    "circle": {"sel": stroked([circle(27.5 - SEL_W / 2)], SEL_W), "deco": filled(circle(25.5)),
               "ring": filled(circle(22.5)), "fill": filled(circle(20))},
    "oct": {"sel": stroked([oct_pts(1 + SEL_W / 2, 9)], SEL_W), "ring": filled(oct_pts(4, 8)),
            "fill": filled(oct_pts(6.5, 7))},
    "lcd": {"sel": stroked([rrect(1 + SEL_W / 2, 6 + SEL_W / 2, 54 - SEL_W, 44 - SEL_W, 5)], SEL_W),
            "ring": filled(rrect(3.5, 8.5, 49, 39, 3)), "fill": filled(rrect(6, 11, 44, 34, 2))},
    "crt": {"sel": stroked([rrect(1 + SEL_W / 2, 1 + SEL_W / 2, 54 - SEL_W, 54 - SEL_W, 3)], SEL_W),
            "ring": stroked(CRT_BRACKETS, 3, closed=False), "fill": filled(rrect(9, 9, 38, 38, 1))},
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for shape, parts in SHAPES.items():
        for part, img in parts.items():
            save(f"sock_{shape}_{part}", img)
    save("ear", filled([(15, 0), (30, 22), (0, 22)], 30, 22))
    print("ok", sum(len(p) for p in SHAPES.values()) + 1, "textures ->", os.path.normpath(OUT))
