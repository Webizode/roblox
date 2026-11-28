"""Renders for the Meshy tower scoops (build_meshy.py, scene MeshyScoops), inside Blender:
    exec(open(ASSET_DIR + "/render_meshy.py").read())
    render_each(fids)                      # meshy/renders/<fid>.png, LOD0 from the front, a little above
    sheet(fids, path)                      # one picture: the renders in a grid
    compare(fids, refs, path)              # reference next to render, per flavor (refs: {fid: picture path})
    tower(order, path)                     # a stack of LOD0s, 1.5 studs apart like the game (Config/Tower scoopSpacing)
"""

import math
import os

import bpy
import numpy as np

ASSET_DIR = globals().get("ASSET_DIR") or os.path.dirname(bpy.data.filepath)
RENDERS = os.path.join(ASSET_DIR, "meshy", "renders")
BG = np.array([0.93, 0.92, 0.95], np.float32)


def _scene():
    sc = bpy.data.scenes["MeshyScoops"]
    bpy.context.window.scene = sc
    return sc


def _only(sc, names):
    for o in sc.objects:
        if o.type == "MESH":
            o.hide_render = o.name not in names


def render_each(fids, size=400):
    sc = _scene()
    os.makedirs(RENDERS, exist_ok=True)
    cam = sc.objects["MS_cam"]
    cam.location = (0, -4.4, 1.7)
    cam.rotation_euler = (math.radians(72), 0, 0)
    sc.render.resolution_x = sc.render.resolution_y = size
    for fid in fids:
        ob = bpy.data.objects[f"MS_{fid}_LOD0"]
        ob.location = (0, 0, 0)
        ob.rotation_euler = (0, 0, 0)
        _only(sc, {ob.name})
        sc.render.filepath = os.path.join(RENDERS, f"{fid}.png")
        bpy.ops.render.render(write_still=True)


def _load(path):
    im = bpy.data.images.load(path, check_existing=False)
    w, h = im.size
    a = np.array(im.pixels[:], np.float32).reshape(h, w, 4)[::-1].copy()
    bpy.data.images.remove(im)
    return a[..., :3] * a[..., 3:] + (1 - a[..., 3:]) * BG


def _fit(a, s):
    h, w = a.shape[:2]
    ys = (np.arange(s) * h / s).astype(int)
    xs = (np.arange(s) * w / s).astype(int)
    return a[ys][:, xs]


def _save(canvas, path):
    h, w = canvas.shape[:2]
    im = bpy.data.images.new(os.path.basename(path), w, h)
    im.pixels[:] = np.dstack([canvas, np.ones((h, w, 1), np.float32)])[::-1].ravel()
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


def sheet(fids, path, cols=6, s=260):
    rows = (len(fids) + cols - 1) // cols
    canvas = np.ones((rows * s, cols * s, 3), np.float32) * BG
    for k, fid in enumerate(fids):
        a = _fit(_load(os.path.join(RENDERS, f"{fid}.png"))[40:360, 40:360], s)
        r, c = divmod(k, cols)
        canvas[r * s : (r + 1) * s, c * s : (c + 1) * s] = a
    _save(canvas, path)


def compare(fids, refs, path, cols=4, s=220, g=10, bad=()):
    rows = (len(fids) + cols - 1) // cols
    w = cols * (2 * s + 3 * g) + g
    h = rows * (s + g) + g
    canvas = np.ones((h, w, 3), np.float32) * BG
    for k, fid in enumerate(fids):
        r, c = divmod(k, cols)
        x = g + c * (2 * s + 3 * g)
        y = g + r * (s + g)
        canvas[y : y + s, x : x + s] = _fit(_load(refs[fid]), s)
        canvas[y : y + s, x + s + g : x + 2 * s + g] = _fit(_load(os.path.join(RENDERS, f"{fid}.png"))[40:360, 40:360], s)
        if fid in bad:
            red = (0.85, 0.1, 0.1)
            x0, x1 = x + s + g, x + 2 * s + g
            canvas[y : y + 4, x0:x1] = red
            canvas[y + s - 4 : y + s, x0:x1] = red
            canvas[y : y + s, x0 : x0 + 4] = red
            canvas[y : y + s, x1 - 4 : x1] = red
    _save(canvas, path)


def tower(order, path, size=(700, 1100)):
    sc = _scene()
    for o in [o for o in sc.objects if o.name.startswith("STACK_")]:
        bpy.data.objects.remove(o, do_unlink=True)
    names = set()
    for i, fid in enumerate(order):
        c = bpy.data.objects[f"MS_{fid}_LOD0"].copy()
        c.name = f"STACK_{i}"
        sc.collection.objects.link(c)
        c.location = (0, 0, 0.86 + i * 1.5)
        c.rotation_euler = (0, 0, math.radians(i * 37))
        names.add(c.name)
    _only(sc, names)
    top = 0.86 + (len(order) - 1) * 1.5
    cam = sc.objects["MS_cam"]
    cam.location = (0, -(top * 0.9 + 6), top / 2 + 1.5)
    cam.rotation_euler = (math.radians(86), 0, 0)
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o in [o for o in sc.objects if o.name.startswith("STACK_")]:
        bpy.data.objects.remove(o, do_unlink=True)
