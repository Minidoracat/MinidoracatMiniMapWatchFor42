"""地圖錶手腕模型：七款造型的幾何、.X 寫檔、手臂貼合檢查（純 numpy；build_watch_art.py 與 Blender 端共用）。

座標＝前臂骨頭本地空間（公尺），跟原版手腕錶同一套：
- 原版 clothingItems/WristWatch_*.xml 是 m_Static＋m_AttachBone=Bip01_{L,R}_Forearm，模型 models_X/Static/Clothes/*_WristWatch_*.x
  的頂點就在這個空間：把 Skinned/MaleBody.x 的手臂頂點乘上 SkinWeights "Bip01_L_Forearm" 的反綁定矩陣，
  原版錶環剛好包住手腕（x 0.10–0.13）。
- x 沿前臂，0 在手肘、約 0.13 是手腕環、0.13 以後是手（跟著手骨轉，模型不能伸過去）。
- 左手：錶面朝 +y（手背），錶面 12 點朝 +z（原版左手 UV：圖片往下＝-z）。
- 右手：右前臂空間是左前臂的 y 鏡像；原版右手模型＝左手模型繞錶心的 z 向軸轉 180°（x→2xc−x、y→−y），
  字讀起來朝手肘，跟真人右手戴錶一樣。這裡照做：錶殼類零件在設計稿座標裡左右翻，錶帶／護腕依右手臂重算。

設計稿座標（temp/design-minimap-watch-1005/svg.mjs，viewBox 0 0 200 260）：sx 沿手臂（+sx 朝手），sy 繞手腕（小＝12 點）。
錶殼頂面 UV 直接對到設計稿算圖，所以貼圖就是設計稿本身。
"""
import math
import re

import numpy as np

# ---------- 貼圖格局（256×256，像素左上原點；.X 的 v 也是由上往下，見原版 M_WristWatch_Square_Left.x 的錶面 UV） ----------
TEX = 256
FACE_PX, FACE_VB = 192, (0.0, 30.0, 200.0, 200.0)  # 左上 192×192：設計稿 viewBox (0,30,200,200)
STRIP = (192, 0, 256, 192)  # 右側 64×192：錶帶花紋（縱向平鋪）
SW_W, SW_Y, SW_H = 32, 192, 64  # 下排 8 格純色


def face_uv(sx, sy):
    x0, y0, w, h = FACE_VB
    return ((sx - x0) / w * FACE_PX / TEX, (sy - y0) / h * FACE_PX / TEX)


def sw_uv(i):
    return ((i * SW_W + SW_W / 2) / TEX, (SW_Y + SW_H / 2) / TEX)


def strip_uv(fu, fv):
    x0, y0, x1, y1 = STRIP
    return ((x0 + 1 + fu * (x1 - x0 - 2)) / TEX, (y0 + 1 + fv * (y1 - y0 - 2)) / TEX)


# ---------- 設計稿形狀（頂視多邊形，設計稿座標） ----------
def rrect(x, y, w, h, r, n=4):
    r = min(r, w / 2, h / 2)
    pts = []
    for cx, cy, a0 in ((x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90), (x + r, y + r, 180)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def circle(cx, cy, r, n=24):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def grow(pts, f):
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    return [(cx + (x - cx) * f, cy + (y - cy) * f) for x, y in pts]


# ---------- 七款 ----------
# 零件：poly＝頂視多邊形（凸）；top＝頂面高出錶帶頂多少 mm；bot＝None 貼著錶帶，數字＝錶帶頂以上 mm；sw＝側面色格。
# swatches 順序：0 錶殼側面、1 錶帶、其餘配件。顏色照 data.mjs STYLES 的 swatches／wristColor。
# 比例：K_WATCH＝原版數位錶錶殼沿手臂長（M 0.0252、F 0.0172 m，M/F_WristWatch_Square_Left.x）× 1.3 ÷ ValuTech 錶殼 132 單位。
K_WATCH = {"M": 1.3 * 0.0252 / 132, "F": 1.3 * 0.0172 / 132}
H_SCALE = {"M": 1.0, "F": 0.8}


def _p(poly, top, sw, bot=None):
    return {"poly": poly, "top": top, "bot": bot, "sw": sw}


def _mirror_x(poly):
    return [(200 - x, y) for x, y in poly]


_paw_ear = grow([(50, 96), (57, 44), (94, 74)], 1.12)
_rg_oct = [(52, 60), (148, 60), (172, 84), (172, 180), (148, 204), (52, 204), (28, 180), (28, 84)]
_rg_corner = [(28, 84), (52, 60), (66, 60), (38, 90)]
_rg_corners = [_rg_corner, _mirror_x(_rg_corner), [(x, 264 - y) for x, y in _rg_corner], [(200 - x, 264 - y) for x, y in _rg_corner]]

STYLES = {
    "ValuTech": {
        "svg": "valutech", "strap": (66, 134), "swatches": ["#1E1F22", "#1E1F22", "#B4B8BE", "#C9CDD3"],
        "parts": [_p(rrect(34, 62, 132, 136, 18), 6, 0)]
        + [_p(rrect(*r, 2), 4.5, 2, bot=1.5) for r in ((27, 88, 9, 18), (164, 88, 9, 18), (164, 152, 9, 18))],
    },
    "Paws": {
        "svg": "paws", "strap": (72, 128), "swatches": ["#F59BBE", "#8FDDC2", "#E0719E", "#FFD3E2"],
        "parts": [_p(circle(100, 132, 58), 6, 0), _p(_paw_ear, 5.5, 0), _p(_mirror_x(_paw_ear), 5.5, 0),
                  _p(circle(160, 132, 6, 12), 4, 2, bot=1.5)],
    },
    "Nexus": {
        "svg": "nexus", "strap": (70, 130), "swatches": ["#161B22", "#1D232B", "#2B3540", "#3EE6E0"],
        # 實機（1006a）錶面在遊戲光照下全黑、只剩錶帶上幾個青點：3D 貼圖的鏡面底提亮成暗青、光邊加高到看得見側面
        "recolor": {"#05080B": "#0C3A40", "#123E42": "#1C6E6B"},
        "parts": [_p(rrect(40, 62, 120, 136, 34), 6, 0), _p(rrect(46, 68, 108, 124, 29), 7.5, 3, bot=4.5),
                  _p(rrect(160, 108, 8, 28, 3), 4.5, 2, bot=1.5), _p(rrect(160, 146, 8, 16, 3), 4.5, 2, bot=1.5)],
    },
    "Spiffo": {
        "svg": "spiffo", "strap": (72, 128), "swatches": ["#8C8F96", "#3A3C41", "#D9443A", "#5A5D63"],
        "parts": [_p(circle(100, 134, 58), 6, 0), _p(circle(62, 82, 17, 16), 5.5, 0), _p(circle(138, 82, 17, 16), 5.5, 0),
                  _p(circle(160, 134, 5.5, 12), 4, 2, bot=1.5)],
    },
    "Ranger": {
        "svg": "ranger", "strap": (68, 132), "swatches": ["#4F5732", "#5B6340", "#3B4126", "#9AA0A6"],
        "parts": [_p(_rg_oct, 7, 0)] + [_p(c, 8.5, 2) for c in _rg_corners]
        + [_p(rrect(*r, 2), 6, 2, bot=1) for r in ((20, 98, 12, 20), (20, 146, 12, 20), (168, 98, 12, 20), (168, 146, 12, 20))],
        "buckle": 3,
    },
    "Luthex": {
        "svg": "luthex", "strap": (74, 126), "swatches": ["#D4AF37", "#4A2C20", "#C9A046", "#A67C22"],
        "parts": [_p(circle(100, 132, 60, 32), 5.5, 0), _p(rrect(157, 125, 11, 14, 2.5), 4, 2, bot=1.5)],
        "buckle": 0,  # 金色錶扣
    },
    # 嗶嗶腕機：護腕從手腕包到前臂中段（機身 162 單位 ≈ 0.066 m，x 0.061–0.127）；女性橫向縮 0.7。
    "BB3000": {
        "svg": "crt", "svg_alt": {"Amber": "crt-amber"}, "strap": (30, 180), "cuff": True,
        # 實機（1006a）螢幕底色 #08180B 在遊戲光照下是黑的、只剩亮線的點：3D 貼圖的螢幕底提亮（圖示照設計稿）
        "recolor": {"#08180B": "#1E6B28", "#04120A": "#185A20", "#1A0F03": "#6B4410", "#0E0700": "#5A380C"},
        "k": {"M": (0.000407, 0.000407), "F": (0.000407, 0.000285)}, "xc": 0.092,
        "swatches": ["#7A7A52", "#2F3324", "#3A3A28", "#8E8E62", "#FFB000"],
        "parts": [_p(rrect(24, 48, 162, 162, 20), 10, 0), _p(rrect(14, 76, 18, 104, 8), 8, 3, bot=2),
                  _p(circle(164, 100, 19, 20), 13, 2, bot=9), _p(circle(164, 146, 11, 16), 12, 2, bot=9),
                  _p(circle(149, 72, 4, 10), 10.8, 4, bot=9)],
    },
}
WATCH_XC = 0.112  # 錶心 x：原版錶殼 0.103–0.128；放大後往手肘挪，最外緣不過 0.132（手腕環 0.13 之後跟著手骨轉）
MARGIN = 0.006  # 錶帶外緣離手臂截面外框（原版錶環離手腕 4–10 mm）
STRAP_T = 0.002  # 錶帶厚度
# 超橢圓指數：原版手臂截面幾乎是軸向長方形（4 個角就在外框角上），橢圓（p=2）、p=3、p=4 都會被角頂穿；
# p=5＋6 mm 時手臂最外點的超橢圓值 0.74（男）／0.49（女），嗶嗶腕機 0.91（check_fit 門檻 0.95）
P_EXP = 5.0
N_RING = 32


# ---------- 原版手臂（只讀比例與骨架，不複製進 MOD） ----------
def read_arm(body_x_path):
    """回傳左前臂空間的手臂環：[(x 平均, 4×3 角點)]，角點依 (y,z) 角度排序。"""
    t = open(body_x_path, encoding="latin-1").read()
    i = t.index("Mesh Body")
    m = re.search(r"\{\s*(\d+);", t[i:])
    nv = int(m.group(1))
    p = i + m.end()
    nums = re.findall(r"-?\d+\.\d+(?:e-?\d+)?", t[p:p + nv * 80])
    V = np.array([float(x) for x in nums[:nv * 3]]).reshape(nv, 3)
    sw = {}
    for mm in re.finditer(r'SkinWeights\s*\{\s*"([^"]+)";\s*(\d+);', t):
        n = int(mm.group(2))
        vals = re.findall(r"-?\d+(?:\.\d+)?(?:e-?\d+)?", t[mm.end():mm.end() + n * 40 + 600])
        sw[mm.group(1)] = (np.array(list(map(int, vals[:n]))), np.array(list(map(float, vals[n:2 * n]))),
                           np.array(list(map(float, vals[2 * n:2 * n + 16]))).reshape(4, 4))
    idx = set()
    for b in ("Bip01_L_UpperArm", "Bip01_L_Forearm", "Bip01_L_Hand"):
        ii, ww, _ = sw[b]
        idx |= set(ii[ww > 0.05].tolist())
    idx = np.array(sorted(idx))
    P = (np.c_[V[idx], np.ones(len(idx))] @ sw["Bip01_L_Forearm"][2])[:, :3]
    P = np.unique(P.round(6), axis=0)
    P = P[(P[:, 0] > -0.03) & (P[:, 0] < 0.18)]
    P = P[np.argsort(P[:, 0])]
    rings, cur = [], [P[0]]
    for q in P[1:]:
        if q[0] - cur[-1][0] > 0.01:  # 手臂環是斜的（同一環 x 差到 1.6 cm），環與環之間至少差 1.3 cm
            rings.append(np.array(cur))
            cur = []
        cur.append(q)
    rings.append(np.array(cur))
    out = []
    for r in rings:
        if len(r) != 4:
            continue
        c = r[:, 1:].mean(0)
        r = r[np.argsort(np.arctan2(r[:, 2] - c[1], r[:, 1] - c[0]))]
        out.append((r[:, 0].mean(), r))
    assert len(out) >= 4, f"arm rings: {[len(r) for r in rings]}"
    return out


def arm_section(arm, x):
    """x 處的手臂截面 4 角點 (y,z)：沿四條縱向邊在相鄰兩環之間內插。"""
    for (xa, ra), (xb, rb) in zip(arm, arm[1:]):
        if xa <= x <= xb:
            pts = []
            for j in range(4):
                a, b = ra[j], rb[j]
                t = (x - a[0]) / (b[0] - a[0]) if b[0] != a[0] else 0.0
                t = min(1.0, max(0.0, t))
                pts.append(a[1:] + (b[1:] - a[1:]) * t)
            return np.array(pts)
    raise ValueError(f"x={x} outside arm rings")


def fit(arm, x0, x1):
    pts = np.concatenate([arm_section(arm, x) for x in np.linspace(x0 - 0.003, x1 + 0.003, 9)])
    lo, hi = pts.min(0), pts.max(0)
    c, a = (lo + hi) / 2, (hi - lo) / 2 + MARGIN
    return float(c[0]), float(c[1]), float(a[0]), float(a[1])


def spow(v, e):
    return math.copysign(abs(v) ** e, v)


def se_value(y, z, cy, cz, ay, az):
    return abs((y - cy) / ay) ** P_EXP + abs((z - cz) / az) ** P_EXP


def check_fit(arm, sections, label):
    """手臂每一點都要在錶帶內面（半軸−厚度）裡面；回傳最大超橢圓值（<1 才不穿模）。"""
    worst = 0.0
    xs = np.linspace(sections[0][0], sections[-1][0], 25)
    for x in xs:
        cy, cz, ay, az = _interp(sections, x)
        for y, z in arm_section(arm, x):
            worst = max(worst, se_value(y, z, cy, cz, ay - STRAP_T, az - STRAP_T))
    assert worst < 0.95, f"{label}: arm pokes through the strap (superellipse {worst:.3f})"
    return worst


def _interp(sections, x):
    for a, b in zip(sections, sections[1:]):
        if a[0] <= x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0]) if b[0] != a[0] else 0.0
            return tuple(a[i] + (b[i] - a[i]) * t for i in range(1, 5))
    return tuple(sections[-1][1:5])


# ---------- 網格 ----------
class Mesh:
    """逐三角形獨立頂點；每個三角形依「朝外」方向決定繞序（法線＝右手定則，跟原版 .X 一樣）。"""

    def __init__(self):
        self.tris = []  # [(3×3 pos, 3×3 normal, 3×2 uv)]

    def tri(self, p, n, uv, out):
        p, n = np.array(p, float), np.array(n, float)
        if np.dot(np.cross(p[1] - p[0], p[2] - p[0]), out) < 0:
            p, n, uv = p[[0, 2, 1]], n[[0, 2, 1]], [uv[0], uv[2], uv[1]]
        self.tris.append((p, n, list(uv)))

    def quad(self, p, n, uv, out):
        self.tri([p[0], p[1], p[2]], [n[0], n[1], n[2]], [uv[0], uv[1], uv[2]], out)
        self.tri([p[0], p[2], p[3]], [n[0], n[2], n[3]], [uv[0], uv[2], uv[3]], out)

    def flat(self, p, uv, out):
        out = np.array(out, float)
        nn = out / np.linalg.norm(out)
        (self.tri if len(p) == 3 else self.quad)(p, [nn] * len(p), uv, out)

    def bbox(self):
        P = np.concatenate([t[0] for t in self.tris])
        return P.min(0), P.max(0)


def build(sid, gender, side, arm):
    """回傳 (Mesh, 資訊)；arm＝read_arm(<gender>Body.x)（左前臂空間），右手在最後做 y 鏡像。"""
    st = STYLES[sid]
    kx, kz = st.get("k", {}).get(gender) or (K_WATCH[gender], K_WATCH[gender])
    hs = H_SCALE[gender]
    xc = st.get("xc", WATCH_XC)
    zc_ref = 0.0
    flip = side == "R"

    def X(sx):
        return xc + ((200 - sx if flip else sx) - 100) * kx

    sx0, sx1 = st["strap"]
    xa, xb = sorted((X(sx0), X(sx1)))
    if st.get("cuff"):
        xs = [xa] + [r[0] for r in arm if xa < r[0] < xb] + [xb]
        sections = [(x,) + fit(arm, x, x) for x in xs]
    else:
        sections = [(xa,) + fit(arm, xa, xb), (xb,) + fit(arm, xa, xb)]
    worst = check_fit(arm, sections, f"{sid}/{gender}{side}")
    cy, cz, ay, az = _interp(sections, xc)
    zc_ref = cz

    def Z(sy):
        return zc_ref - (sy - 130) * kz

    strap_top = cy + ay
    m = Mesh()

    def strap_y(x, z):
        scy, scz, say, saz = _interp(sections, x)
        u = min(1.0, abs((z - scz) / saz))
        return scy + say * (1 - u ** P_EXP) ** (1 / P_EXP)

    # 錶帶／護腕：超橢圓環沿 x 放樣，外面貼花紋、內面與兩端用錶帶色
    ring = [math.pi + 2 * math.pi * j / N_RING for j in range(N_RING + 1)]
    e = 2 / P_EXP

    def ring_pt(sec, phi, inset):
        x, scy, scz, say, saz = sec
        return np.array([x, scy + (say - inset) * spow(math.cos(phi), e), scz + (saz - inset) * spow(math.sin(phi), e)])

    def ring_n(sec, phi):
        _, scy, scz, say, saz = sec
        c, s = math.cos(phi), math.sin(phi)
        n = np.array([0.0, spow(c, 2 - e) / say, spow(s, 2 - e) / saz])
        return n / (np.linalg.norm(n) or 1)

    strap_sw = sw_uv(1)
    for si in range(len(sections) - 1):
        A, B = sections[si], sections[si + 1]
        fa = (A[0] - xa) / (xb - xa)
        fb = (B[0] - xa) / (xb - xa)
        for j in range(N_RING):
            p0, p1 = ring[j], ring[j + 1]
            P = [ring_pt(A, p0, 0), ring_pt(B, p0, 0), ring_pt(B, p1, 0), ring_pt(A, p1, 0)]
            N = [ring_n(A, p0), ring_n(B, p0), ring_n(B, p1), ring_n(A, p1)]
            out = sum(N)
            fv0, fv1 = j / N_RING, (j + 1) / N_RING
            m.quad(P, N, [strip_uv(fa, fv0), strip_uv(fb, fv0), strip_uv(fb, fv1), strip_uv(fa, fv1)], out)
            Q = [ring_pt(A, p0, STRAP_T), ring_pt(B, p0, STRAP_T), ring_pt(B, p1, STRAP_T), ring_pt(A, p1, STRAP_T)]
            m.quad(Q, [-n for n in N], [strap_sw] * 4, -out)
    for sec, sgn in ((sections[0], -1.0), (sections[-1], 1.0)):
        for j in range(N_RING):
            p0, p1 = ring[j], ring[j + 1]
            m.flat([ring_pt(sec, p0, 0), ring_pt(sec, p1, 0), ring_pt(sec, p1, STRAP_T), ring_pt(sec, p0, STRAP_T)],
                   [strap_sw] * 4, (sgn, 0, 0))

    # 錶殼與配件：頂視多邊形擠出；頂面 UV 對設計稿，側面與底面用色格
    for part in st["parts"]:
        poly = part["poly"]
        top = strap_top + part["top"] * 0.001 * hs
        pos = [(X(sx), Z(sy)) for sx, sy in poly]
        if part["bot"] is None:
            bots = [max(cy, strap_y(x, z) - 0.0015) for x, z in pos]
        else:
            bots = [strap_top + part["bot"] * 0.001 * hs] * len(pos)
        cx_ = sum(p[0] for p in pos) / len(pos)
        cz_ = sum(p[1] for p in pos) / len(pos)
        csx = sum(p[0] for p in poly) / len(poly)
        csy = sum(p[1] for p in poly) / len(poly)
        cbot = min(bots)
        side_uv = sw_uv(part["sw"])
        n = len(pos)
        for i in range(n):
            j = (i + 1) % n
            (x0, z0), (x1, z1) = pos[i], pos[j]
            m.flat([(cx_, top, cz_), (x0, top, z0), (x1, top, z1)],
                   [face_uv(csx, csy), face_uv(*poly[i]), face_uv(*poly[j])], (0, 1, 0))
            m.flat([(cx_, cbot, cz_), (x0, bots[i], z0), (x1, bots[j], z1)], [side_uv] * 3, (0, -1, 0))
            mx, mz = (x0 + x1) / 2 - cx_, (z0 + z1) / 2 - cz_
            m.flat([(x0, bots[i], z0), (x1, bots[j], z1), (x1, top, z1), (x0, top, z0)], [side_uv] * 4, (mx, 0, mz))

    # 錶扣：錶帶最底下（手掌側）一塊小方塊
    if "buckle" in st:
        sec = _interp(sections, xc)
        yb = sec[0] - sec[2]
        hw, hz, hy = (sx1 - sx0) * kx / 2 + 0.001, 0.005 * hs, 0.0025 * hs
        X0, X1, Z0, Z1, Y0, Y1 = xc - hw, xc + hw, sec[1] - hz, sec[1] + hz, yb - hy, yb + 0.002
        uv = [sw_uv(st["buckle"])] * 4
        for q, out in (
            ([(X0, Y0, Z0), (X1, Y0, Z0), (X1, Y0, Z1), (X0, Y0, Z1)], (0, -1, 0)),
            ([(X0, Y1, Z0), (X1, Y1, Z0), (X1, Y1, Z1), (X0, Y1, Z1)], (0, 1, 0)),
            ([(X0, Y0, Z0), (X0, Y1, Z0), (X0, Y1, Z1), (X0, Y0, Z1)], (-1, 0, 0)),
            ([(X1, Y0, Z0), (X1, Y1, Z0), (X1, Y1, Z1), (X1, Y0, Z1)], (1, 0, 0)),
            ([(X0, Y0, Z0), (X1, Y0, Z0), (X1, Y1, Z0), (X0, Y1, Z0)], (0, 0, -1)),
            ([(X0, Y0, Z1), (X1, Y0, Z1), (X1, Y1, Z1), (X0, Y1, Z1)], (0, 0, 1)),
        ):
            m.flat(q, uv, out)

    if flip:  # 右前臂空間＝左前臂的 y 鏡像（MaleBody.x 兩邊反綁定矩陣比對）；繞序由 tri() 依朝外方向重排
        mm, s = Mesh(), np.array([1.0, -1.0, 1.0])
        for p, n, uv in m.tris:
            mm.tri(p * s, n * s, uv, np.cross(p[1] - p[0], p[2] - p[0]) * s)
        m = mm
    lo, hi = m.bbox()
    info = {"sections": sections, "worst": worst, "bbox": (lo, hi), "tris": len(m.tris)}
    return m, info


# ---------- .X（DirectX 文字格式，跟原版 Static/Clothes 同一種；PZ 只取第一個 mesh，ProcessedAiScene.findMesh） ----------
X_HEADER = """xof 0303txt 0032
template Vector {
 <3d82ab5e-62da-11cf-ab39-0020af71e433>
 FLOAT x;
 FLOAT y;
 FLOAT z;
}

template MeshFace {
 <3d82ab5f-62da-11cf-ab39-0020af71e433>
 DWORD nFaceVertexIndices;
 array DWORD faceVertexIndices[nFaceVertexIndices];
}

template Mesh {
 <3d82ab44-62da-11cf-ab39-0020af71e433>
 DWORD nVertices;
 array Vector vertices[nVertices];
 DWORD nFaces;
 array MeshFace faces[nFaces];
 [...]
}

template MeshNormals {
 <f6f23f43-7686-11cf-8f52-0040333594a3>
 DWORD nNormals;
 array Vector normals[nNormals];
 DWORD nFaceNormals;
 array MeshFace faceNormals[nFaceNormals];
}

template Coords2d {
 <f6f23f44-7686-11cf-8f52-0040333594a3>
 FLOAT u;
 FLOAT v;
}

template MeshTextureCoords {
 <f6f23f40-7686-11cf-8f52-0040333594a3>
 DWORD nTextureCoords;
 array Coords2d textureCoords[nTextureCoords];
}

"""


def _rows(items, fmt):
    return ",\n".join("  " + fmt(it) for it in items) + ";"


def write_x(mesh, path, name, texture):
    V, N, U, F, seen = [], [], [], [], {}
    for p, n, uv in mesh.tris:  # 位置＋法線＋UV 全同的角共用頂點（檔案小一半；載入時 JOIN_IDENTICAL_VERTICES 本來也會併）
        f = []
        for k in range(3):
            key = tuple(round(float(c), 6) for c in (*p[k], *n[k], *uv[k]))
            if key not in seen:
                seen[key] = len(V)
                V.append(p[k])
                N.append(n[k])
                U.append(uv[k])
            f.append(seen[key])
        F.append(tuple(f))
    f6 = lambda v: f"{v:.6f}"
    s = [X_HEADER]
    s.append("Material MinidoracatWatchMat {\n 1.000000;1.000000;1.000000;1.000000;;\n 10.000000;\n 0.000000;0.000000;0.000000;;\n"
             f" 0.000000;0.000000;0.000000;;\n\n TextureFilename {{\n  \"{texture}\";\n }}\n}}\n\n")
    s.append(f"Frame {name} {{\n\n FrameTransformMatrix {{\n  1.000000,0.000000,0.000000,0.000000,0.000000,1.000000,0.000000,0.000000,"
             "0.000000,0.000000,1.000000,0.000000,0.000000,0.000000,0.000000,1.000000;;\n }\n\n")
    s.append(f" Mesh {name} {{\n  {len(V)};\n")
    s.append(_rows(V, lambda v: ";".join(f6(c) for c in v) + ";") + "\n")
    s.append(f"  {len(F)};\n" + _rows(F, lambda f: "3;" + ",".join(map(str, f)) + ";") + "\n\n")
    s.append(f"  MeshNormals {{\n  {len(N)};\n" + _rows(N, lambda v: ";".join(f6(c) for c in v) + ";") + "\n")
    s.append(f"  {len(F)};\n" + _rows(F, lambda f: "3;" + ",".join(map(str, f)) + ";") + "\n  }\n\n")
    s.append(f"  MeshMaterialList {{\n   1;\n   {len(F)};\n" + ",\n".join("   0" for _ in F) + ";\n   { MinidoracatWatchMat }\n  }\n\n")
    s.append(f"  MeshTextureCoords {{\n  {len(U)};\n" + _rows(U, lambda t: f"{f6(t[0])};{f6(t[1])};") + "\n  }\n }\n}\n")
    with open(path, "w", encoding="ascii", newline="\n") as fh:
        fh.write("".join(s))


def read_x(path):
    """讀回自己寫的 .X（驗證用）：頂點、三角形、UV。"""
    t = open(path, encoding="ascii").read()
    body = t[t.index("Mesh "):]
    m = re.search(r"\{\s*(\d+);", body)
    nv = int(m.group(1))
    rest = body[m.end():]
    nums = re.findall(r"-?\d+\.\d+", rest)
    V = np.array([float(x) for x in nums[:nv * 3]]).reshape(nv, 3)
    after = rest[rest.index(";;") + 2:]
    nf = int(re.match(r"\s*(\d+);", after).group(1))
    F = np.array([list(map(int, x.split(","))) for x in re.findall(r"3;([\d,]+);", after)[:nf]])
    uvm = re.search(r"MeshTextureCoords\s*\{\s*(\d+);", t)
    uvs = re.findall(r"-?\d+\.\d+", t[uvm.end():])[:nv * 2]
    UV = np.array([float(x) for x in uvs]).reshape(nv, 2)
    return V, F, UV
