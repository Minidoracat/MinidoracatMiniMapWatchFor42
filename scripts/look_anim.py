# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy"]
# ///
"""The "look at the watch" pose (MinidoracatWatch_Look.lua Look.pose): one clip per wrist standing and one per wrist
in a seat (CLIPS), derived from vanilla Bob_IdleLookAtPhoto (the only vanilla clip that raises a hand to the chest and
looks down at it; no vanilla clip checks a watch, look-anim research Q3), and the four action nodes that play them.

    uv run scripts/look_anim.py                      write the clips into MOD media/anims_X/Bob/ and the nodes into
                                                     media/AnimSets/player|player-vehicle/actions/
    uv run scripts/look_anim.py --check              exit 1 when a shipped clip or node differs from a fresh build
                                                     (after a game update or a change here) or a stale one is left
    uv run scripts/look_anim.py --src DIR [--check]  vanilla anims_X/Bob folder (or env PZ_BOB_ANIMS; default the
                                                     Steam install below)

Every run also prints and asserts the self-checks (check()): L and R are mirror images, the wrist sits in front of the
chest, the dial faces the eyes.

The left pose (left_pose) starts from the photo clip at TICK (the seat clips: its masked bones over Bob_IdleDriving,
over()) and is a list of rigid turns (xanim.articulate, any axis) solved from a few model-space targets, so a tuning
round changes a direction, not an axis (values tuned on an offline render of the skinned body and the watch model from
the front, the side and above, standing over Bob_Idle, walking over Bob_Walk, seated over Bob_IdleDriving):
- upper arm: shoulder to elbow along UPPER (down, forward and a little out: the elbow comes up beside the chest) and
  rolled so its elbow hinge (local Y: every vanilla clip sampled, every 4th of anims_X/Bob, bends the elbow about it
  only) is normal to the plane of UPPER and FORE;
- forearm: bent about that hinge to FORE (across the chest toward the middle, slightly rising), then rolled about its
  own axis TWIST of the way that faces the dial at the eyes (the full roll, about 67 degrees: a forearm turned palm
  down. The watch is a static model on Bip01_L_Forearm with the dial normal along local +Y: clothingItems/
  MinidoracatWatch_*_Left.xml m_AttachBone; 528 of the 746 vertices of models_X/Static/Clothes/
  MinidoracatWatch_ValuTech_M_Left.x lie in the dial layer y 0.020-0.028. Vanilla clips never roll the forearm, so
  the elbow skin turns with it; the render showed no pinch, check it in game);
- hand and fingers: relaxed, their local turns from Bob_Idle (the photo's fingers grip the photo);
- head: turned HEAD of the way that would point the face at the dial (people drop the eyes for the rest).
The right clip mirrors the left in model space about the body's middle (x = Bip01's x): a right bone's model turn is
D @ (left twin's) @ S with S = diag(-1, 1, 1) and D = diag(1, -1, 1) (the R bones' local axes are the L ones mirrored
with local Y flipped, measured on Bob_Idle to 2 degrees; the right watch's dial is local -Y,
MinidoracatWatch_ValuTech_M_Right.x), then back to locals under the clip's own parents.

Static pose: the photo clip already holds one pose (two identical keys per upper-body bone, 0 and 3200 at 4800 ticks a
second; read_anim asserts it below), so the clips keep its keys with one pose and the nodes play them at m_SpeedScale
0.00 (vanilla maskingleft/holdingTorchLeft.xml does the same with Bob_IdleFlashLight): a frozen pose, no breathing
loop to tune.

The clips go in anims_X/Bob, named and with AnimationSets after the MOD (a clip's name is its AnimationSet name,
ImportedSkeleton.java:336-345; a MOD reads its own anims_X/Bob, ModelManager.loadModAnimations :1658-1709; other folder
names need a common/media/anims_X, Tesla seat_anim.py). Line endings: the source is CRLF and write_anim keeps it; git
stores them LF (core.autocrlf), so --check compares bytes after turning CRLF into LF.
"""
import glob
import os
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from xanim import articulate, pose, quat, read_anim, write_anim  # noqa: E402

DEFAULT_SRC = "D:/SteamLibrary/steamapps/common/ProjectZomboid/media/anims_X/Bob"
MEDIA = os.path.join(HERE, "..", "MOD", "MinidoracatMiniMapWatchFor42", "Contents", "mods",
                     "MinidoracatMiniMapWatchFor42", "42", "media")
OUT = os.path.join(MEDIA, "anims_X", "Bob")
TICK = 1600                                      # the photo clip's middle (keys at 0 and 3200)
# Model space (pose()): +X the character's left, +Y up, -Z forward; a bone's matrix rows are its local axes, X along it.
UPPER = (0.4, -0.7, -0.6)                        # shoulder -> elbow
FORE = (-0.85, 0.2, -0.5)                        # elbow -> wrist
TWIST, HEAD = 1.0, 0.6
EYE = (0.091, 0.0, 0.05, 1.0)                    # in Bip01_Head's space: front of the head mesh in Bob_Idle.x, 55% up
DIAL = (0.112, 0.024, 0.0, 1.0)                  # dial centre in Bip01_L_Forearm's space (the watch models' x 0.094-0.130)
ARM = ("Clavicle", "UpperArm", "Forearm", "Hand", "Finger0", "Finger1")
MASKED = [f"Bip01_{s}_{b}" for s in "LR" for b in ARM] + ["Bip01_Head"]   # every bone a node plays from the clip
S, D = np.diag([-1.0, 1.0, 1.0]), np.diag([1.0, -1.0, 1.0])
# Standing clips play over Bob_Idle/Bob_Walk; seat clips over Bob_IdleDriving (player-vehicle/idle/default.xml: every
# seat). A node takes the masked bones' local turns from its clip, so a clip solved over Bob_Idle would hang the arm
# and head off Bob_IdleDriving's neck, which leans 16 degrees from Bob_Idle's: the arm drops to the belly, the head
# bows to the chest (offline render). Each set is solved over its own base for the same model-space targets.
CLIPS = {"L": "MinidoracatWatch_LookWatchL", "R": "MinidoracatWatch_LookWatchR",
         "SeatL": "MinidoracatWatch_LookWatchSeatL", "SeatR": "MinidoracatWatch_LookWatchSeatR"}
BASES = {"": None, "Seat": "Bob_IdleDriving.x"}   # clip-name prefix -> base clip (None: the photo clip's own body)
# Self-check limits (model units; the character is about 0.98 tall, so 0.005 is about 1 cm): the R skeleton is not an
# exact mirror of the L one (bone lengths and clavicle offsets differ by up to MIRROR_TOL), the dial within DIAL_DEG
# of the eyes, the wrist between the chest bones' heights and at least CHEST_AHEAD in front of Bip01_Spine1.
MIRROR_TOL, DIAL_DEG, CHEST_AHEAD = 0.005, 30.0, 0.08

# Nodes (AnimSets/player/actions: standing and walking; player-vehicle/actions: driver and passengers). Each node is
# written out in full: no x_extends (Linux dedicated servers do not resolve it, family pitfalls.md).
# - Condition PerformingAction = the node name: BaseAction.setActionAnim(String) sets it (BaseAction.java:269-280).
# - m_SubStateBoneWeights: the watch arm from the clavicle down and the head; every other bone stays on the layer
#   under the actions substate (idle, walking legs and the free arm's swing, the driver's other hand on the wheel).
#   Unlisted bones weigh 0 and a listed one covers its children (AnimationTrack.initBoneWeights :560-598,
#   AnimBoneWeight.java defaults weight 1, includeDescendants true); the clavicle is a child of Bip01_Neck, so the
#   neck itself is left out or both arms would follow (vanilla maskingleft/holdingTorchLeft.xml masks
#   Bip01_L_Clavicle the same way).
# - m_BlendTime 0.32 and m_SyncTrackingEnabled false: vanilla photo.xml takes them from reading.xml.
# - m_SpeedScale 0.00: the static pose above.
NODE_DIRS = ("player", "player-vehicle")


def node_xml(side, folder):
    name, arm = f"MinidoracatWatch_Look{side}", "Bip01_L_Clavicle" if side == "L" else "Bip01_R_Clavicle"
    where = "standing and walking" if folder == "player" else "in a vehicle seat"
    return "\r\n".join([
        '<?xml version="1.0" encoding="utf-8"?>',
        f"<!-- Written by scripts/look_anim.py (reasons in its NODE_DIRS comment): {'left' if side == 'L' else 'right'}"
        f" wrist, {where}. Only the watch arm and the head play the clip. -->",
        "<animNode>",
        f"\t<m_Name>{name}</m_Name>",
        f"\t<m_AnimName>{CLIPS[('' if folder == 'player' else 'Seat') + side]}</m_AnimName>",
        "\t<m_BlendTime>0.32</m_BlendTime>",
        "\t<m_SpeedScale>0.00</m_SpeedScale>",
        "\t<m_SyncTrackingEnabled>false</m_SyncTrackingEnabled>",
        "\t<m_Conditions>", "\t\t<m_Name>PerformingAction</m_Name>", "\t\t<m_Type>STRING</m_Type>",
        f"\t\t<m_Value>{name}</m_Value>", "\t</m_Conditions>",
        "\t<m_SubStateBoneWeights>", f"\t\t<boneName>{arm}</boneName>", "\t</m_SubStateBoneWeights>",
        "\t<m_SubStateBoneWeights>", "\t\t<boneName>Bip01_Head</boneName>", "\t</m_SubStateBoneWeights>",
        "</animNode>", ""])


def nodes():
    return {os.path.join(MEDIA, "AnimSets", d, "actions", f"MinidoracatWatch_Look{s}.xml"): node_xml(s, d)
            for d in NODE_DIRS for s in "LR"}


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def roll(n, t, axis):
    """degrees about `axis` (right-handed) that turn n onto t, both projected off the axis"""
    n, t = n - axis * (n @ axis), t - axis * (t @ axis)
    return float(np.sign(np.cross(n, t) @ axis) * np.degrees(np.arccos(np.clip(unit(n) @ unit(t), -1, 1))))


def swing(a, b):
    """(degrees, axis) of the shortest turn from direction a to b"""
    a, b = unit(a), unit(b)
    return float(np.degrees(np.arccos(np.clip(a @ b, -1, 1)))), unit(np.cross(a, b))


def at(G, bone, v):
    return (np.asarray(v) @ G[bone])[:3]


def local_rot(G, bones):
    parent = dict(bones)
    return {b: G[b][:3, :3] @ np.linalg.inv(G[p][:3, :3]) if p else G[b][:3, :3] for b, p in bones}


def over(bones, clip, base):
    """pose() matrices as a node shows them: MASKED bones' local transforms from clip, the rest from base"""
    out = {}
    for b, p in bones:
        s = clip if b in MASKED else base
        loc = s[b] @ np.linalg.inv(s[p]) if p else s[b]
        out[b] = loc @ out[p] if p else loc
    return out


def left_pose(bones, G, idle):
    """(pose() matrices, articulate edits) of the left clip, from the start matrices G (module docstring)"""
    edits = []
    upper, fore = unit(UPPER), unit(FORE)

    def turn(*e):
        nonlocal G
        edits.append(e)
        G = articulate(bones, G, [e])

    U, F, H = "Bip01_L_UpperArm", "Bip01_L_Forearm", "Bip01_Head"
    turn(U, *swing(G[U][0, :3], upper))
    turn(U, roll(G[U][1, :3], np.cross(unit(upper), unit(fore)), unit(upper)), "twist")
    hinge = G[U][1, :3].copy()
    turn(F, roll(G[F][0, :3], unit(fore), hinge), hinge)
    assert np.allclose(G[F][0, :3], unit(fore), atol=1e-6), "the elbow bent the wrong way"
    turn(F, TWIST * roll(G[F][1, :3], at(G, H, EYE) - at(G, F, DIAL), G[F][0, :3]), "twist")
    rel = local_rot(idle, bones)
    for b in ("Bip01_L_Hand", "Bip01_L_Finger0", "Bip01_L_Finger1"):   # relaxed: Bob_Idle's turn under the parent
        want = rel[b] @ G[dict(bones)[b]][:3, :3]
        R = (np.linalg.inv(G[b][:3, :3]) @ want).T                       # column form of the turn G[b] -> want
        deg = np.degrees(np.arccos(np.clip((np.trace(R) - 1) / 2, -1, 1)))
        if deg > 1e-6:
            turn(b, deg, unit([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]]))
    deg, axis = swing(G[H][2, :3], at(G, F, DIAL) - at(G, H, EYE))      # head local +Z: the face's forward
    turn(H, HEAD * deg, axis)
    return G, edits


def twin(b):
    return b.replace("_L_", "_X_").replace("_R_", "_L_").replace("_X_", "_R_")


def mirrored(bones, G):
    """pose() matrices with every MASKED bone's model turn mirrored from its twin's, positions rebuilt from the
    clip's local offsets under the (unmirrored) rest"""
    loc = {b: G[b] @ np.linalg.inv(G[p]) if p else G[b] for b, p in bones}
    out = {}
    for b, p in bones:
        if b in MASKED:
            m = np.eye(4)
            m[:3, :3] = D @ G[twin(b)][:3, :3] @ S
            m[3, :3] = loc[b][3, :3] @ out[p][:3, :3] + out[p][3, :3]
            out[b] = m
        else:
            out[b] = loc[b] @ out[p] if p else loc[b]
    return out


def build(src, name, Gs, dst):
    """write clip `name` (pose() matrices Gs) as a copy of the photo clip with new rotation keys for MASKED bones"""
    anim = read_anim(src)
    bones = anim[0]
    rel = local_rot(Gs, bones)
    rot = {b: [quat(rel[b])] * len(anim[1][b]["R"][0]) for b in MASKED}
    write_anim(src, dst, CLIPS[name], rot)
    new = read_anim(dst)
    for t in sorted({t for b in MASKED for t in anim[1][b]["R"][0]}):     # every key turns what we asked for
        got = local_rot(pose(new, t), bones)
        bad = max(np.abs(got[b] - rel[b]).max() for b in MASKED)
        assert bad < 1e-4, f"{CLIPS[name]} tick {t}: masked bones off by {bad}"


def poses(src):
    """bones, {clip: edits}, {clip: pose() matrices}"""
    anim = read_anim(src)
    bones = anim[0]
    for b, p in bones:      # the photo clip holds one pose on the bones we use; a game update that animates it fails here
        if b in MASKED or b in ("Bip01_Neck", "Bip01_Spine1", "Bip01_Spine"):
            for c in "RT":
                assert np.ptp(anim[1][b][c][1], axis=0).max() < 1e-6, f"{src}: {b} {c} keys are no longer one pose"
    photo = pose(anim, TICK)
    idle = pose(read_anim(os.path.join(os.path.dirname(src), "Bob_Idle.x")), 0)
    edits, G = {}, {}
    for pre, base in BASES.items():
        G0 = over(bones, photo, pose(read_anim(os.path.join(os.path.dirname(src), base)), 0)) if base else photo
        G[pre + "L"], edits[pre + "L"] = left_pose(bones, G0, idle)
        G[pre + "R"] = mirrored(bones, G[pre + "L"])
    return bones, edits, G


def check(bones, edits, G):
    """assert and print the self-checks"""
    for pre in BASES:
        L, R = G[pre + "L"], G[pre + "R"]
        mid = L["Bip01"][3, 0]
        print(f"{CLIPS[pre + 'L']}:")
        for e in edits[pre + "L"]:
            print(f"  turn {e[0]:16s} {e[1]:7.1f} deg about {e[2] if isinstance(e[2], str) else np.round(e[2], 3)}")
        worst = 0.0
        for b in ("UpperArm", "Forearm", "Hand", "Finger0", "Finger1"):
            for a, c in (("L", "R"), ("R", "L")):
                p = L[f"Bip01_{a}_{b}"][3, :3].copy()
                p[0] = 2 * mid - p[0]
                worst = max(worst, np.abs(R[f"Bip01_{c}_{b}"][3, :3] - p).max())
        print(f"  mirror: worst arm joint {worst:.4f} from the L clip's mirror image (limit {MIRROR_TOL})")
        assert worst < MIRROR_TOL
        for side, Gs, sign in (("L", L, 1), ("R", R, -1)):
            F = f"Bip01_{side}_Forearm"
            w, e = at(Gs, F, (DIAL[0], sign * DIAL[1], 0, 1)), at(Gs, "Bip01_Head", EYE)
            dial = np.degrees(np.arccos(np.clip(unit(sign * Gs[F][1, :3]) @ unit(e - w), -1, 1)))
            hand, chest, neck = Gs[f"Bip01_{side}_Hand"][3, :3], Gs["Bip01_Spine1"][3, :3], Gs["Bip01_Neck"][3, :3]
            elbow = Gs[F][3, :3]
            print(f"  {side}: wrist {np.round(hand, 3)} = {hand[1] - chest[1]:+.3f} over Spine1, {chest[2] - hand[2]:.3f}"
                  f" in front of it, {abs(hand[0] - mid):.3f} off the middle; elbow {np.round(elbow, 3)}; dial"
                  f" {dial:.1f} deg off the eyes, {np.linalg.norm(e - w):.3f} from them")
            assert chest[1] <= hand[1] <= neck[1] and chest[2] - hand[2] >= CHEST_AHEAD and abs(hand[0] - mid) < 0.1
            assert dial <= DIAL_DEG


def main():
    argv = sys.argv[1:]
    check_only = "--check" in argv
    src_dir = argv[argv.index("--src") + 1] if "--src" in argv else os.environ.get("PZ_BOB_ANIMS", DEFAULT_SRC)
    src = os.path.join(src_dir, "Bob_IdleLookAtPhoto.x")
    bones, edits, G = poses(src)
    check(bones, edits, G)
    want = {os.path.normpath(os.path.join(OUT, CLIPS[s] + ".x")): s for s in CLIPS}
    xml = {os.path.normpath(p): t for p, t in nodes().items()}
    have = {os.path.normpath(p) for p in glob.glob(os.path.join(OUT, "MinidoracatWatch_*.x"))
            + glob.glob(os.path.join(MEDIA, "AnimSets", "*", "*", "MinidoracatWatch_*.xml"))}
    old = sorted(have - set(want) - set(xml))
    stale = list(old)

    def text(path):
        return open(path, "rb").read().replace(b"\r\n", b"\n") if os.path.exists(path) else None

    if not check_only:
        os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as d:
        for out, side in want.items():
            tmp = os.path.join(d, CLIPS[side] + ".x")
            build(src, side, G[side], tmp if check_only else out)
            if check_only and text(tmp) != text(out):
                stale.append(out)
    for out, body in xml.items():
        if check_only and text(out) != body.replace("\r\n", "\n").encode():
            stale.append(out)
        elif not check_only:
            os.makedirs(os.path.dirname(out), exist_ok=True)
            open(out, "w", encoding="utf-8", newline="").write(body)
    if check_only:
        print("look_anim: " + (f"{stale} differ from a fresh build or are left over: run without --check" if stale
                               else f"up to date ({len(want)} clips, {len(xml)} nodes)"))
        sys.exit(1 if stale else 0)
    for p in old:
        os.remove(p)
    print(f"look_anim: wrote {len(want)} clips, {len(xml)} nodes; removed {len(old)}")


if __name__ == "__main__":
    main()
