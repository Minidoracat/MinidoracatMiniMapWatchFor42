"""DirectX .x text files (PZ characters): the first mesh with its skin weights and frame matrix, animation keys, the
pose at a tick and skinning (numpy only; after MinidoracatBagsFor42 scripts/satchel_mirror.py), and writing a copy
of an animation with new rotation keys for some bones (write_anim).

Copied from MinidoracatTeslaFor42 scripts/blender/common/xanim.py (commit 9ba39036); the only change is articulate
taking any turn axis (an optional third item per edit), which scripts/look_anim.py needs for the wrist."""
import re
import numpy as np

NUM = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")


def _block(t, i):
    i = t.index("{", i)
    d, j = 0, i
    while True:
        d += (t[j] == "{") - (t[j] == "}")
        if d == 0:
            return i + 1, j
        j += 1


def read_x(path):
    t = open(path, encoding="latin-1").read()
    m = re.search(r"\n\s*Mesh \w* ?\{", t)
    s, e = _block(t, m.start())
    a = np.array(NUM.findall(t[s:t.index("{", s)].rsplit("\n", 1)[0]), float)
    V = a[1:1 + 3 * int(a[0])].reshape(-1, 3)
    sw = {}
    for w in re.finditer(r"SkinWeights \{", t[s:e]):
        bs, be = _block(t, s + w.start())
        body = t[bs:be]
        b = np.array(NUM.findall(body[body.index('";') + 2:]), float)
        n = int(b[0])
        sw[re.search(r'"([^"]+)"', body)[1]] = (b[1:1 + n].astype(int), b[1 + n:1 + 2 * n], b[1 + 2 * n:17 + 2 * n].reshape(4, 4))
    fm = ([None] + list(re.finditer(r"FrameTransformMatrix \{\s*([-\d.,;e\s]*)\}", t[:m.start()])))[-1]
    return V, sw, (np.array(NUM.findall(fm[1]), float).reshape(4, 4) if fm else np.eye(4))


def read_anim(path):
    t = open(path, encoding="latin-1").read()
    a = re.search(r"\nAnimationSet \w+", t).start()
    frames = [(m[2], len(m[1])) for m in re.finditer(r"\n( *)Frame (\w+)", t[:a])]
    bones = [(b, next((frames[j][0] for j in range(i - 1, -1, -1) if frames[j][1] < d), None)) for i, (b, d) in enumerate(frames)]
    keys = {}
    for m in re.finditer(r"Animation\s*\{\s*\{\s*(\w+)\s*\}((?:\s*AnimationKey \w \{[^}]*\})+)", t[a:]):
        keys[m[1]] = {}
        for k in re.finditer(r"AnimationKey (\w) \{([^}]*)\}", m[2]):
            n = np.array(NUM.findall(k[2]), float)
            arr = n[2:].reshape(int(n[1]), -1)
            keys[m[1]][k[1]] = (arr[:, 0], arr[:, 2:])
    return bones, keys


def pose(anim, tick=0):
    """{bone: model matrix} (row vectors, the space of the SkinWeights inverse bind matrices)"""
    bones, keys = anim
    G = {}
    for b, parent in bones:
        L = np.eye(4)
        if b in keys:
            q, s, p = (np.array([np.interp(tick, keys[b][c][0], keys[b][c][1][:, i]) for i in range(keys[b][c][1].shape[1])])
                       for c in "RST")
            w, x, y, z = q / np.linalg.norm(q)
            L[:3, :3] = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]) * s[:, None]
            L[3, :3] = p
        G[b] = L @ G[parent] if parent else L
    return G


def skin(V, sw, G):
    Vh = np.c_[V, np.ones(len(V))]
    out, ws = np.zeros((len(V), 3)), np.zeros(len(V))
    for b, (idx, w, ibm) in sw.items():
        out[idx] += w[:, None] * (Vh[idx] @ ibm @ G[b])[:, :3]
        ws[idx] += w
    return out / np.maximum(ws, 1e-9)[:, None]


def quat(m):
    """3x3 rotation (pose()'s layout) -> unit quaternion (w, x, y, z)"""
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1) * 2
        q = [s / 4, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s]
    else:
        i = int(np.argmax(np.diag(m)))
        j, k = (i + 1) % 3, (i + 2) % 3
        s = np.sqrt(1 + m[i, i] - m[j, j] - m[k, k]) * 2
        q = [0.0] * 4
        q[0], q[1 + i], q[1 + j], q[1 + k] = (m[k, j] - m[j, k]) / s, s / 4, (m[j, i] + m[i, j]) / s, (m[k, i] + m[i, k]) / s
    q = np.array(q)
    return q / np.linalg.norm(q) * (1 if q[0] >= 0 else -1)


def articulate(bones, G, edits):
    """pose() matrices with rigid model-space turns: `edits` [(bone, deg)] or [(bone, deg, axis)], in order, each turns
    the bone and everything under it about `axis` through the bone's joint, right-handed. `axis` is a model-space
    vector, "twist" (the bone's own X, which runs along the bone to its child) or left out for model X (+deg: what
    points forward (-Z) goes up, what points up goes back). The new local of an edited bone is G[b] @ inv(G[parent]);
    the bones under it keep theirs."""
    parent, G = dict(bones), dict(G)
    for bone, deg, *rest in edits:
        axis = rest[0] if rest else (1.0, 0.0, 0.0)
        k = np.asarray(G[bone][0, :3] if isinstance(axis, str) else axis, float)
        k = k / np.linalg.norm(k)
        K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
        p = G[bone][3, :3].copy()
        M = np.eye(4)
        M[:3, :3] = (np.eye(3) + np.sin(np.radians(deg)) * K + (1 - np.cos(np.radians(deg))) * K @ K).T  # Rodrigues
        M[3, :3] = p - p @ M[:3, :3]                      # turn about p (row vectors: v' = v M)
        for b, _ in bones:
            a = b
            while a and a != bone:
                a = parent[a]
            if a:
                G[b] = G[b] @ M
    return G


def write_anim(src, dst, name, rot, pos=None):
    """copy the animation .x `src` to `dst` with the AnimationSet renamed `name`, the rotation keys of the bones in
    `rot` ({bone: [(w, x, y, z) per key]}) and the position keys of those in `pos` ({bone: [(x, y, z) per key]})
    replaced, everything else byte for byte"""
    t = open(src, encoding="latin-1", newline="").read()
    t = re.sub(r"\nAnimationSet \w+ \{", f"\nAnimationSet {name} {{", t, count=1)
    for kind, n, table in (("R", 4, rot), ("T", 3, pos or {})):
        for bone, vs in table.items():
            m = re.search(r"Animation\s*\{\s*\{\s*" + bone + r"\s*\}", t)
            k = re.compile(r"AnimationKey " + kind + r" \{(\s*\d;\s*\d+;)([^}]*)\}").search(t, m.end())
            keys = re.findall(rf"(\d+);{n};[^;]*;;", k[2])
            assert len(keys) == len(vs), (bone, kind, len(keys), len(vs))
            nl = "\r\n" if "\r\n" in k[2] else "\n"
            ind = re.search(r"\n([ \t]*)\d", k[2])[1]
            tail = re.search(r"\s*$", k[2])[0]                 # newline and the closing brace's indent
            body = ("," + nl).join(f"{ind}{tick};{n};" + ",".join(f"{v:.6f}" for v in q) + ";;" for tick, q in zip(keys, vs))
            t = t[:k.start(2)] + nl + body + ";" + tail + t[k.end(2):]
    open(dst, "w", encoding="latin-1", newline="").write(t)
