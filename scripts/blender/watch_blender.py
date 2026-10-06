"""Blender 5.2 headless：用 watch_model 建男版左手模型、套 MOD 裡剛寫好的貼圖，算預覽（正面、斜側面；人看的，不進 MOD）。
由 build_watch_art.py 呼叫：blender -b --factory-startup --python watch_blender.py -- <media> <out> <pz> <款,款...>

座標：模型是前臂骨頭空間（DirectX 左手系，PZ 讀 .X 時 MAKE_LEFT_HANDED）。放進右手系的 Blender 要做一次鏡像才不會字反：
Blender (X, Y, Z) = (x, −y, z)，三角形繞序跟著反過來。錶面朝 −Y、12 點朝 +Z、字由左往右讀＝+X。
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import watch_model as wm  # noqa: E402

MEDIA, OUT, PZ, ONLY = sys.argv[sys.argv.index("--") + 1:][:4]


def mesh_object(sid, mesh):
    verts, faces, uvs = [], [], []
    for p, _, uv in mesh.tris:
        b = len(verts)
        verts += [(v[0], -v[1], v[2]) for v in p]
        faces.append((b, b + 2, b + 1))
        uvs.append((uv[0], uv[2], uv[1]))
    me = bpy.data.meshes.new(sid)
    me.from_pydata(verts, [], faces)
    layer = me.uv_layers.new(name="UVMap")
    for poly, fuv in zip(me.polygons, uvs):
        for k, li in enumerate(poly.loop_indices):
            layer.data[li].uv = (fuv[k][0], 1.0 - fuv[k][1])
    mat = bpy.data.materials.new(sid)
    mat.use_nodes = True
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(MEDIA, "textures", f"MinidoracatWatch_{sid}.png"))
    tex.interpolation = "Closest"
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.append(mat)
    ob = bpy.data.objects.new(sid, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def render(ob, path, direction, size, pad=1.15):
    sc = bpy.context.scene
    for o in sc.collection.objects:
        if o.type == "MESH":
            o.hide_render = o is not ob
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light, sh.color_type, sh.show_cavity = "STUDIO", "TEXTURE", False
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.view_settings.view_transform = "Standard"
    pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
    center = sum(pts, Vector()) / len(pts)
    d = Vector(direction).normalized()
    cam = sc.camera
    if cam is None:
        cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
    cam.data.type = "ORTHO"
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (-d).to_track_quat("-Z", "Y")
    cam.location = center + d * 1.0
    bpy.context.view_layer.update()
    inv = cam.matrix_world.inverted()
    loc = [inv @ p for p in pts]
    span = max(max(p.x for p in loc) - min(p.x for p in loc), max(p.y for p in loc) - min(p.y for p in loc))
    cam.data.ortho_scale = span * pad
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    arm = wm.read_arm(os.path.join(PZ, "media", "models_X", "Skinned", "MaleBody.x"))
    for sid in ONLY.split(","):
        mesh, _ = wm.build(sid, "M", "L", arm)
        ob = mesh_object(sid, mesh)
        render(ob, os.path.join(OUT, f"front_{sid}.png"), (0.0, -1.0, 0.0), 384)  # 錶面正面：字不能反
        render(ob, os.path.join(OUT, f"side_{sid}.png"), (0.7, -0.5, -0.5), 384)  # 斜側面：錶帶環、配件


main()
