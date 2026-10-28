"""Builds the Big Swirl in Blender from scratch, one collection per module.

Run inside Blender (Blender MCP or the Text Editor):
    ASSET_DIR = r"<repo>/assets/BigSwirl"
    exec(open(ASSET_DIR + "/build_bigswirl.py").read())

1 Blender unit = 1 stud. Z is up here; the FBX export turns it into Roblox's Y up. Front is -Y (the stairs and the
sign). Colours: a pastel cartoon palette (PAL) that sits well next to the island's sand, cream and pinks, one glossy
material per colour, so each part keeps a plain colour in Roblox; the trough mix carries one small swirl picture.

The arms: every LauncherArm_N is an empty at its joint on the hub. Its local +X runs along the arm, a turn about its
local Y pitches it (positive pitch = up; set_arm_pitch below). ArmN_Muzzle marks the scoop in the cup. The cycle the
code plays later: down into the trough (SCOOP_PITCH), scoop, swing up, pull back (PULL_PITCH), fire, back to rest
(IDLE_PITCH). The trough of ice mix runs around the base; at SCOOP_PITCH the cup sits in the mix.
"""

import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

# where the textures go (and animate_bigswirl.py writes its bake): this repo folder, whatever .blend is open, when
# ASSET_DIR is set before exec (see the module doc); otherwise next to the .blend.
ASSET_DIR = globals().get("ASSET_DIR") or os.path.dirname(bpy.data.filepath)

PAL = {  # pastel cartoon palette, checked against the colours of Kornel's island
    "pink": "#FF9EC7",  # candy pink
    "lightpink": "#FFC8DD",
    "blue": "#9BD8FF",  # baby blue
    "mint": "#A8F0D1",
    "lemon": "#FFE48A",  # instead of gold
    "lavender": "#CDB8FF",
    "cream": "#FFF6E5",  # warm cream instead of white
    "chocolate": "#9A6244",
    "cherry": "#FF5A6E",
    "glass": "#DFF4FF",
}

# layout (studs)
BASE_R, BASE_H = 15.0, 3.2
DECK_Z = 3.9  # top of the drum and lip: the walkable deck
TIER_R, TIER_H = 11.5, 1.8
HUB_R, HUB_Z0 = 8.6, 5.7
CUP_Z0, CUP_Z1 = 12.6, 19.0
TROUGH_WALL, MIX_Z, TROUGH_FLOOR = 2.9, 2.2, -0.4  # the floor sits a little below the plaza: room for a deep dip
STAIR_GAP = math.radians(15)  # half the opening in the trough and the railing for each staircase
# arms: joint on the hub's shoulder; the trough sits where it is (the machine stays 52 across), and each arm is just
# long enough that the cup's centre goes right down into the mix
JOINT_R, JOINT_Z = 9.5, 14.0
TROUGH_IN, TROUGH_OUT, TROUGH_RIM = 15.4, 26.0, 0.5  # out to 26: the machine is 52 across
TROUGH_MID = (TROUGH_IN + TROUGH_OUT) / 2
CUP_SCOOP_Z = 2.6  # the level cup sits deep in the mix, its rim just above it
ARM_REACH = math.hypot(TROUGH_MID - JOINT_R, JOINT_Z - CUP_SCOOP_Z)
SCOOP_PITCH = -math.atan2(JOINT_Z - CUP_SCOOP_Z, TROUGH_MID - JOINT_R)
# six arms, every 60 degrees from +X (Blender): the stairs (front and back) lie between two arms
ARM_YAWS_DEG = (0, 60, 120, 180, 240, 300)
BARREL_R = 1.45  # slim, to suit the snug cups
# the scoop in the cup: the game shows the flying scoop (2 studs across, ShotRenderer) at Config/BigSwirl.scoopInCupScale
# while it rides in the cup, so the cup is built around that size. It hugs the scoop's lower third: two thirds stick
# out. SCOOP_AT is the scoop's centre in the wrist's frame (the release points and the game's scoopOffset use it).
SCOOP_R = 1.0 * 1.8
SCOOP_AT = 0.9
CUP_GAP, CUP_WALL = 0.08, 0.35
# the poses the animation uses, all checked against the rest of the machine; pulled back past 37 degrees (overshoot
# included) an arm touches the cream
IDLE_PITCH, PULL_PITCH, PULL_LIMIT = math.radians(25), math.radians(35), math.radians(37)
SCOOP_TILT_LIMIT = math.radians(15)  # how far the cup may tip in the mix without touching the trough
IDLE_CUP_TILT = math.radians(12)  # at rest the cup leans a little outward, showing its scoop


def lin(h):
    h = h.lstrip("#")
    c = [int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    return [((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c] + [1]


def mat(name):
    m = bpy.data.materials.get("BS_" + name) or bpy.data.materials.new("BS_" + name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = lin(PAL[name])
    b.inputs["Roughness"].default_value = 0.12  # glossy candy
    for key in ("Coat Weight", "Clearcoat"):
        if key in b.inputs:
            b.inputs[key].default_value = 0.5
    if name == "glass":
        b.inputs["Alpha"].default_value = 0.4
        m.surface_render_method = "BLENDED" if hasattr(m, "surface_render_method") else m.surface_render_method
    m.diffuse_color = lin(PAL[name])
    return m


root = bpy.data.collections.get("BigSwirl") or bpy.data.collections.new("BigSwirl")
if root.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(root)
for c in list(root.children):
    for ob in list(c.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.collections.remove(c)


def module(name):
    col = bpy.data.collections.new(name)
    root.children.link(col)
    return col


def finish(ob, col, color, bevel=0.0, segs=1, smooth_angle=40, parent=None, name=None):
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    col.objects.link(ob)
    if name:
        ob.name = name
        ob.data.name = name
    ob.data.materials.clear()
    for cname in color if isinstance(color, (list, tuple)) else [color]:
        ob.data.materials.append(mat(cname))
    if bevel > 0:
        m = ob.modifiers.new("Bevel", "BEVEL")
        m.width = bevel
        m.segments = segs
        m.limit_method = "ANGLE"
        m.angle_limit = math.radians(35)
    ob.data.shade_smooth()
    ob.data.set_sharp_from_angle(angle=math.radians(smooth_angle))
    if parent:
        ob.parent = parent
        ob.matrix_parent_inverse = parent.matrix_world.inverted()
    return ob


def cyl(r, depth, z=0, verts=48, r2=None, loc=(0, 0)):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=(loc[0], loc[1], z + depth / 2))
    else:
        bpy.ops.mesh.primitive_cone_add(
            vertices=verts, radius1=r, radius2=r2, depth=depth, location=(loc[0], loc[1], z + depth / 2)
        )
    return bpy.context.active_object


def torus(R, r, z, major=48, minor=12, loc=(0, 0)):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=R, minor_radius=r, major_segments=major, minor_segments=minor, location=(loc[0], loc[1], z)
    )
    return bpy.context.active_object


def sphere(r, loc, seg=24, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=r, location=loc)
    return bpy.context.active_object


def box(size, loc, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    ob = bpy.context.active_object
    ob.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return ob


def capsule(p0, p1, r, seg=8):
    """A rounded drop from p0 down to p1: a cylinder with a ball at the lower end."""
    p0, p1 = Vector(p0), Vector(p1)
    length = (p1 - p0).length
    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=r, depth=length, location=(p0 + p1) / 2)
    c = bpy.context.active_object
    c.rotation_euler = Vector((0, 0, 1)).rotation_difference(p1 - p0).to_euler()
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r * 1.15, location=p1)
    s = bpy.context.active_object
    bpy.ops.object.select_all(action="DESELECT")
    c.select_set(True)
    s.select_set(True)
    bpy.context.view_layer.objects.active = c
    bpy.ops.object.join()
    return c


def lathe(name, profile, seg=64, twist=None, arc=None):
    """Spins a (radius, z) profile around Z. A radius of 0 closes that end in a point; a full spin caps the first ring.
    twist(theta, s) scales the radius, s running 0..1 along the profile. arc=(a0, a1) spins only that range of angles
    and closes both ends (the trough pieces)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    full = arc is None
    a0, a1 = (0.0, 2 * math.pi) if full else arc
    count = seg if full else seg + 1
    rings = []
    n = len(profile)
    for i, (r, z) in enumerate(profile):
        s = i / (n - 1)
        if r <= 1e-4:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        ring = []
        for k in range(count):
            th = a0 + (a1 - a0) * k / seg
            f = twist(th, s) if twist else 1
            ring.append(bm.verts.new((r * f * math.cos(th), r * f * math.sin(th), z)))
        rings.append(ring)
    # UVs: U runs once around (0..1), V along the profile (0..1)
    uv = bm.loops.layers.uv.new("UVMap")
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        if len(a) == 1 and len(b) == 1:
            continue
        va, vb = i / (n - 1), (i + 1) / (n - 1)
        for k in range(seg):
            k1 = (k + 1) % count
            ua, ub = k / seg, (k + 1) / seg
            if len(b) == 1:
                f = bm.faces.new((a[k], a[k1], b[0]))
                coords = ((ua, va), (ub, va), ((ua + ub) / 2, vb))
            elif len(a) == 1:
                f = bm.faces.new((a[0], b[k1], b[k]))
                coords = (((ua + ub) / 2, va), (ub, vb), (ua, vb))
            else:
                f = bm.faces.new((a[k], a[k1], b[k1], b[k]))
                coords = ((ua, va), (ub, va), (ub, vb), (ua, vb))
            for loop, c in zip(f.loops, coords):
                loop[uv].uv = c
    if full and len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if not full:
        for end in (0, count - 1):
            bm.faces.new([ring[end] for ring in rings if len(ring) > 1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def stripes(ob, count, first=0):
    """Alternates the side faces of a cylinder between material 0 and 1 in `count` vertical stripes."""
    for f in ob.data.polygons:
        if abs(f.normal.z) < 0.5:
            ang = math.atan2(f.center.y, f.center.x) % (2 * math.pi)
            f.material_index = (int(ang / (2 * math.pi) * count) + first) % 2
        else:
            f.material_index = 1


def near_arm(a, tolerance=math.radians(16)):
    """Within `tolerance` of an arm's direction, where it swings past the cupcake and dips into the trough."""
    return any(abs(math.remainder(a - math.radians(d), 2 * math.pi)) < tolerance for d in ARM_YAWS_DEG)


def stair_arcs():
    """The trough and the railing run in two arcs, open where the stairs are (front -Y and back +Y)."""
    return [(-math.pi / 2 + STAIR_GAP, math.pi / 2 - STAIR_GAP), (math.pi / 2 + STAIR_GAP, 3 * math.pi / 2 - STAIR_GAP)]


# ================= Base: wide striped drum, a second tier, railing, big stairs =================
col = module("Base")
drum = finish(cyl(BASE_R, BASE_H, 0, 40), col, ["pink", "cream"], bevel=0.4, name="Base_Drum")
stripes(drum, 16)
finish(cyl(BASE_R + 0.35, DECK_Z - BASE_H, BASE_H, 40), col, "lemon", bevel=0.25, name="Base_Lip")
tier = finish(cyl(TIER_R, TIER_H, DECK_Z, 40), col, ["mint", "cream"], bevel=0.35, name="Base_Tier")
stripes(tier, 24)
# railing: posts every 22.5 degrees and rounded bars between them, open at the stairs and where the arms dip
RAIL_R, RAIL_H = BASE_R - 0.6, 1.4
posts = []
for k in range(16):
    a = 2 * math.pi * k / 16
    near_stairs = abs(math.cos(a)) < 0.3
    posts.append(None if near_stairs or near_arm(a, math.radians(12)) else a)
for k, a in enumerate(posts):
    if a is None:
        continue
    p = (RAIL_R * math.cos(a), RAIL_R * math.sin(a))
    finish(cyl(0.32, RAIL_H, DECK_Z, 8, loc=p), col, "chocolate", name=f"Base_Post_{k}")
    finish(sphere(0.45, (p[0], p[1], DECK_Z + RAIL_H), 6, 3), col, "lemon", name=f"Base_PostKnob_{k}")
    b = posts[(k + 1) % 16]
    if b is not None:
        q = (RAIL_R * math.cos(b), RAIL_R * math.sin(b))
        bar = capsule((p[0], p[1], DECK_Z + RAIL_H - 0.3), (q[0], q[1], DECK_Z + RAIL_H - 0.3), 0.2, 6)
        finish(bar, col, "chocolate", name=f"Base_Rail_{k}")
# big stairs front and back, from the ground over the trough up to the deck
STEP_COLORS = ["pink", "lemon", "mint", "blue", "lavender"]
STEPS = 7
for side, nm in ((-1, "Front"), (1, "Back")):
    for i in range(STEPS):
        h = DECK_Z * (i + 1) / STEPS
        st = box((8, 1.5, h), (0, side * (TROUGH_OUT + 1.2 - i * 1.5), h / 2))
        finish(st, col, STEP_COLORS[i % len(STEP_COLORS)], bevel=0.3, name=f"Stairs_{nm}_{i + 1}")
    for x in (-4.3, 4.3):
        y0, y1 = side * (TROUGH_OUT + 1.8), side * (BASE_R - 0.5)
        rail = capsule((x, y0, 1.6), (x, y1, DECK_Z + 1.4), 0.3, 8)
        finish(rail, col, "chocolate", name=f"Stairs_{nm}_Rail")

# ================= Trough of ice mix around the base =================
MIX_REPEATS = 3  # the mix picture repeats this often along each half of the trough
MIX_COLORS = ["pink", "mint", "blue", "lemon", "chocolate"]
MIX_DOME = 1.0  # how far the middle of the mix bulges above MIX_Z: a heaped, overfull trough
# scoop-shaped humps poking out of the mix, so it reads as ice cream waiting to be scooped (flavour colour, size)
MIX_HUMPS = [("pink", 1.7), ("mint", 1.5), ("lemon", 1.6), ("blue", 1.4), ("chocolate", 1.6)]


def srgb(name):
    return [int(PAL[name][i : i + 2], 16) / 255 for i in (1, 3, 5)]


def painted_material(key, rgb, display):
    """A material showing a picture this script paints (rgb: an h x w x 3 array of sRGB values, row 0 at the bottom).
    The picture is saved next to the .blend as textures/<key>.png: the file Roblox gets. `display` is the palette
    colour the material shows in Blender's solid view, which cannot show pictures."""
    import numpy as np

    h, w = rgb.shape[:2]
    rgba = np.concatenate([rgb, np.ones((h, w, 1))], axis=2).astype(np.float32)
    img = bpy.data.images.get(key)
    if img and tuple(img.size) != (w, h):
        bpy.data.images.remove(img)
        img = None
    img = img or bpy.data.images.new(key, w, h, alpha=False)
    img.pixels.foreach_set(rgba.ravel())
    folder = os.path.join(ASSET_DIR, "textures")
    os.makedirs(folder, exist_ok=True)
    img.filepath_raw = os.path.join(folder, key + ".png")
    img.file_format = "PNG"
    img.save()

    m = bpy.data.materials.get("BS_" + key) or bpy.data.materials.new("BS_" + key)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    for n in [n for n in nodes if n.type == "TEX_IMAGE"]:
        nodes.remove(n)
    b = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Roughness"].default_value = 0.15
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    m.node_tree.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    m.diffuse_color = lin(PAL[display])
    return m


def swirl_material():
    """The trough mix: blotches and swirls of the five flavours, like ice cream stirred together, with thin cream
    ribbons where two flavours meet. Tiles along U."""
    import numpy as np

    w, h = 512, 256
    U, V = np.meshgrid((np.arange(w) + 0.5) / w, (np.arange(h) + 0.5) / h)
    tau = 2 * math.pi
    # a swirling warp; every term repeats exactly across U, so the picture tiles without a seam
    Uw = U + 0.06 * np.sin(tau * (2 * U + 1.5 * V)) + 0.03 * np.sin(tau * (5 * U - V))
    Vw = V + 0.18 * np.sin(tau * (3 * U + 0.5 * V)) + 0.08 * np.sin(tau * (7 * U))
    # one smooth field per flavour; at every point the strongest one shows, so they form round blotches
    waves = [(2, 1.0, 0.0, 5, 0.7, 1.3), (3, -1.2, 1.7, 4, 1.4, 4.1), (1, 1.6, 3.1, 6, -0.9, 2.2),
             (4, 0.6, 4.4, 2, -1.6, 0.4), (5, -0.5, 5.6, 3, 1.1, 3.3)]
    fields = np.stack([np.sin(tau * (a * Uw + b * Vw) + p) + np.sin(tau * (c * Uw + d * Vw) + q)
                       for a, b, p, c, d, q in waves])
    order = np.argsort(fields, axis=0)
    first, second = order[-1], order[-2]
    gap = np.take_along_axis(fields, order[-1:], 0)[0] - np.take_along_axis(fields, order[-2:-1], 0)[0]
    cols = np.array([srgb(c) for c in MIX_COLORS])
    mix = np.clip(0.5 + gap / 0.5, 0.5, 1.0)[..., None]  # soft edges between two flavours
    rgb = cols[first] * mix + cols[second] * (1 - mix)
    ribbon = np.clip(1 - gap / 0.06, 0, 1)[..., None] * 0.8  # a thin cream ribbon where they meet
    rgb = rgb * (1 - ribbon) + np.array(srgb("cream")) * ribbon
    return painted_material("trough_mix", rgb, "pink")


def cream_material(turns, phase_shift=0.0):
    """The cream: warm cream with a pink stripe running up the groove between the rolls (U around, V up the
    profile, the same phase the roll geometry follows)."""
    import numpy as np

    w, h = 512, 512
    U, V = np.meshgrid((np.arange(w) + 0.5) / w, (np.arange(h) + 0.5) / h)
    groove = 0.5 + 0.5 * np.sin(2 * math.pi * (U - turns * V) + phase_shift)
    stripe = np.clip((0.2 - groove) / 0.08, 0, 1) * np.clip((V - 0.05) / 0.05, 0, 1) * np.clip((0.88 - V) / 0.05, 0, 1)
    cream, pink = np.array(srgb("cream")), np.array(srgb("pink"))
    return painted_material("cream_swirl", cream * (1 - stripe[..., None]) + pink * stripe[..., None], "cream")


col = module("Trough")
trough_profile = [
    (TROUGH_IN, TROUGH_FLOOR - 0.2),
    (TROUGH_IN, TROUGH_WALL - 0.25),
    (TROUGH_IN + TROUGH_RIM / 2, TROUGH_WALL),
    (TROUGH_IN + TROUGH_RIM, TROUGH_WALL - 0.25),
    (TROUGH_IN + TROUGH_RIM, TROUGH_FLOOR),
    (TROUGH_OUT - TROUGH_RIM, TROUGH_FLOOR),
    (TROUGH_OUT - TROUGH_RIM, TROUGH_WALL - 0.25),
    (TROUGH_OUT - TROUGH_RIM / 2, TROUGH_WALL),
    (TROUGH_OUT, TROUGH_WALL - 0.25),
    (TROUGH_OUT, TROUGH_FLOOR - 0.2),
]
for i, arc in enumerate(stair_arcs()):
    shell = lathe(f"Trough_Shell_{i + 1}", trough_profile, seg=28, arc=arc)
    finish(shell, col, ["blue", "cream"], smooth_angle=50, name=f"Trough_Shell_{i + 1}")
    stripes(shell, 48)
    # the mix: a heaped, gently lumpy surface filling the trough; the colours are in the picture (few faces)
    me = bpy.data.meshes.new(f"Trough_Mix_{i + 1}")
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    a0, a1 = arc
    SEG, RAD = 40, 4
    grid = []
    for k in range(SEG + 1):
        th = a0 + (a1 - a0) * k / SEG
        row = []
        for j in range(RAD + 1):
            r = TROUGH_IN + TROUGH_RIM + (TROUGH_OUT - TROUGH_IN - 2 * TROUGH_RIM) * j / RAD
            across = math.sin(j / RAD * math.pi)  # 0 at the walls, 1 in the middle
            lumps = 0.3 * math.sin(th * 23 + j * 1.7) * across
            z = MIX_Z - 0.15 + MIX_DOME * across**0.7 + lumps
            row.append(bm.verts.new((r * math.cos(th), r * math.sin(th), z)))
        grid.append(row)
    for k in range(SEG):
        for j in range(RAD):
            f = bm.faces.new((grid[k][j], grid[k + 1][j], grid[k + 1][j + 1], grid[k][j + 1]))
            for loop, (kk, jj) in zip(f.loops, ((k, j), (k + 1, j), (k + 1, j + 1), (k, j + 1))):
                loop[uv].uv = (MIX_REPEATS * kk / SEG, jj / RAD)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    mix = bpy.data.objects.new(f"Trough_Mix_{i + 1}", me)
    bpy.context.scene.collection.objects.link(mix)
    finish(mix, col, "cream", smooth_angle=60, name=f"Trough_Mix_{i + 1}")
    mix.data.materials[0] = swirl_material()
    # scoop humps poking out of the mix, spread along this half, away from the stairs and the four dipping spots
    mid_r = (TROUGH_IN + TROUGH_OUT) / 2
    spots = [a0 + (a1 - a0) * (h + 0.5) / 7 for h in range(7)]
    for h, a in enumerate(s for s in spots if not near_arm(s)):
        color, size = MIX_HUMPS[(h + 2 * i) % len(MIX_HUMPS)]
        r = mid_r + (1.6 if h % 2 else -1.4)
        hump = sphere(size, (r * math.cos(a), r * math.sin(a), MIX_Z + MIX_DOME * 0.6), 10, 5)
        finish(hump, col, color, name=f"Trough_Hump_{i + 1}_{h + 1}")

# ================= CentralHub: short, wide, pink with gold =================
col = module("CentralHub")
finish(cyl(HUB_R, 5.5, HUB_Z0, 32), col, "lavender", bevel=0.5, name="Hub_Body")
finish(cyl(HUB_R + 0.45, 1.3, 8.0, 32), col, "cream", bevel=0.35, name="Hub_Band")
finish(torus(HUB_R + 0.15, 0.4, HUB_Z0 + 0.15, 32, 5), col, "lemon", name="Hub_RingFoot")
finish(torus(HUB_R + 0.15, 0.4, 11.2, 32, 5), col, "lemon", name="Hub_RingTop")
finish(cyl(8.4, 1.6, 11.2, 32, r2=7.6), col, "lightpink", bevel=0.35, name="Hub_Cap")

# ================= IceCreamTower: a fat cupcake, overflowing =================
col = module("IceCreamTower")
cup = lathe(
    "Tower_Cup",
    [(7.4, CUP_Z0), (7.6, CUP_Z0 + 0.4), (9.6, CUP_Z1 - 0.4), (9.8, CUP_Z1)],
    seg=40,
    twist=lambda th, s: 1 + 0.035 * math.cos(20 * th),
)
finish(cup, col, "lemon", smooth_angle=60, name="Tower_Cup")
finish(cyl(7.5, 0.6, CUP_Z0 - 0.3, 32), col, "chocolate", bevel=0.25, name="Tower_CupBase")
RIM_Z = CUP_Z1 + 0.3
finish(torus(10.1, 1.1, RIM_Z, 40, 6), col, "chocolate", name="Tower_ChocoRim")
for k in range(12):
    a = 2 * math.pi * (k + 0.5) / 12
    if near_arm(a):
        continue
    length = 1.8 + 1.4 * ((k * 7) % 3) / 2
    p = (10.4 * math.cos(a), 10.4 * math.sin(a))
    drip = capsule((p[0], p[1], RIM_Z), (p[0], p[1], RIM_Z - length), 0.6, 8)
    finish(drip, col, "chocolate", name=f"Tower_ChocoDrip_{k}")
drape = lathe(
    "Tower_PinkDrape",
    [(10.4, RIM_Z + 0.1), (11.1, RIM_Z + 0.8), (11.2, RIM_Z + 1.6), (10.6, RIM_Z + 2.3)],
    seg=48,
    twist=lambda th, s: 1 + 0.03 * math.sin(10 * th),
)
finish(drape, col, "pink", smooth_angle=70, name="Tower_PinkDrape")
# the cream: fat and overflowing, a thick roll winding up three times into a soft, rounded peak
CREAM_Z = RIM_Z + 1.2
CREAM_R, CREAM_H, PEAK_H, CREAM_TURNS = 12.2, 12.5, 3.6, 3.0
prof = [(10.6, CREAM_Z - 1.0), (11.9, CREAM_Z - 0.5)]
N = 26
for i in range(N + 1):
    t = i / N
    phi = t * math.pi / 2
    prof.append((CREAM_R * (math.cos(phi) ** 0.6) + 0.4 * (1 - t), CREAM_Z + CREAM_H * math.sin(phi) ** 1.2))
prof = [p for p in prof if p[0] > 3.2]
top_r, top_z = prof[-1]
for i in range(1, 7):
    t = i / 6
    prof.append((top_r * math.cos(t * math.pi / 2) ** 0.8 if i < 6 else 0.0, top_z + PEAK_H * math.sin(t * math.pi / 2)))


def cream_phase(th, s):
    return th - 2 * math.pi * CREAM_TURNS * s


def cream_swirl(th, s):
    ridge = 0.5 + 0.5 * math.sin(cream_phase(th, s))
    return 1 + 0.17 * (ridge**2) * (1 - 0.35 * s) - 0.05  # soft, round rolls


CREAM_SEG = 48
dome = lathe("Tower_Cream", prof, seg=CREAM_SEG, twist=cream_swirl)
finish(dome, col, "cream", smooth_angle=80, name="Tower_Cream")
dome.data.materials[0] = cream_material(CREAM_TURNS)  # the pink swirl runs up the groove between the rolls
# drips running over the rim: cream from the cream, pink from the pink frosting, none on the arms' diagonals
for k in range(14):
    a = 2 * math.pi * (k + 0.1) / 14
    if near_arm(a) or abs(math.remainder(a + math.pi / 2, 2 * math.pi)) < math.radians(28):  # not on the sign
        continue
    pink = k % 3 == 1
    length = (2.0 if pink else 2.6) + 1.6 * ((k * 5) % 3) / 2
    r = (10.9 if pink else CREAM_R - 0.6)
    top = RIM_Z + 1.2 if pink else CREAM_Z
    p = (r * math.cos(a), r * math.sin(a))
    drip = capsule((p[0], p[1], top), (p[0] * 1.03, p[1] * 1.03, top - length), 0.7 if pink else 0.9, 10)
    finish(drip, col, "pink" if pink else "cream", name=f"Tower_Drip_{k}")
peak = prof[-1][1]
finish(sphere(2.3, (0.2, 0, peak + 1.7), 16, 8), col, "cherry", name="Tower_Cherry")
stem = capsule((0.4, 0, peak + 3.6), (1.4, 0, peak + 5.6), 0.18, 6)
finish(stem, col, "chocolate", name="Tower_CherryStem")

# ================= LauncherArms: short, fat, a big cup that reaches the trough =================
def cup_rim():
    """The cup's rim: its radius and height in the wrist's frame. It sits a third of the scoop up from its bottom, so
    two thirds of the scoop stick out."""
    inner, outer = SCOOP_R + CUP_GAP, SCOOP_R + CUP_GAP + CUP_WALL
    rim = -SCOOP_R / 3  # from the scoop's centre
    r_in = math.sqrt(inner**2 - rim**2)
    r_out = math.sqrt(outer**2 - rim**2)
    return (r_in + r_out) / 2, SCOOP_AT + rim


def cup_profile(steps=5):
    """A bowl hugging the scoop: the outer shell up to the rim, across the rim, and the inner shell back down, as a
    (radius, z) profile in the wrist's frame (the scoop's centre at SCOOP_AT)."""
    inner, outer = SCOOP_R + CUP_GAP, SCOOP_R + CUP_GAP + CUP_WALL
    rim = -SCOOP_R / 3
    out_top, in_top = math.acos(-rim / outer), math.acos(-rim / inner)
    profile = []
    for i in range(steps + 1):  # outer shell, bottom up
        a = out_top * i / steps
        profile.append((outer * math.sin(a), SCOOP_AT - outer * math.cos(a)))
    for i in range(steps, -1, -1):  # inner shell, rim down
        a = in_top * i / steps
        profile.append((inner * math.sin(a), SCOOP_AT - inner * math.cos(a)))
    return profile


scoop_colors = ["pink", "mint", "chocolate", "blue", "lemon", "lavender"]
along = Matrix.Rotation(math.pi / 2, 3, "Y")  # a primitive's local Z onto the arm's X
across = Matrix.Rotation(math.pi / 2, 3, "X")
arm_yaws = {}
for k in range(len(ARM_YAWS_DEG)):
    yaw = math.radians(ARM_YAWS_DEG[k])
    arm_yaws[k + 1] = yaw
    col = module(f"LauncherArm_{k + 1}")
    pivot = bpy.data.objects.new(f"LauncherArm_{k + 1}", None)
    pivot.empty_display_type = "ARROWS"
    pivot.empty_display_size = 3
    col.objects.link(pivot)
    pivot.location = (JOINT_R * math.cos(yaw), JOINT_R * math.sin(yaw), JOINT_Z)
    pivot.rotation_euler = Euler((0, 0, yaw), "XYZ")  # built level, pitched to rest at the end
    bpy.context.view_layer.update()
    M = pivot.matrix_world.copy()
    R = M.to_3x3()

    def place(ob, x, y=0.0, z=0.0, local_rot=Matrix.Identity(3)):
        ob.matrix_world = Matrix.Translation(M @ Vector((x, y, z))) @ (R @ local_rot).to_4x4()
        return ob

    finish(place(cyl(2.1, 3.2, -1.6, 12), 0, 0, 0, across), col, "lavender", bevel=0.4, parent=pivot, name=f"Arm{k + 1}_Joint")
    for side in (-1.75, 1.75):
        cap = place(cyl(1.35, 0.4, -0.2, 12), 0, side, 0, across)
        finish(cap, col, "lemon", parent=pivot, name=f"Arm{k + 1}_JointCap")
    barrel_len = ARM_REACH - 4.6  # from the joint drum to the knuckle
    barrel = place(cyl(BARREL_R, barrel_len, -barrel_len / 2, 12), barrel_len / 2 + 1.2, 0, 0, along)
    finish(barrel, col, "pink", bevel=0.4, parent=pivot, name=f"Arm{k + 1}_Barrel")
    for x in (3.4, barrel_len - 0.6):
        band = place(cyl(BARREL_R + 0.3, 1.1, -0.55, 12), x + 1.2, 0, 0, along)
        finish(band, col, "lemon", bevel=0.2, parent=pivot, name=f"Arm{k + 1}_Band")
    # the wrist: a second joint at the cup's centre, so the cup can stay level while the arm swings (it dips flat
    # into the trough), tip to scoop and flick forward when it fires. Its local axes start as the arm's.
    wrist = bpy.data.objects.new(f"Arm{k + 1}_Wrist", None)
    wrist.empty_display_type = "ARROWS"
    wrist.empty_display_size = 2
    col.objects.link(wrist)
    wrist.parent = pivot
    wrist.location = (ARM_REACH, 0, 0)
    bpy.context.view_layer.update()
    knuckle = place(cyl(1.15, 2.8, -1.4, 12), ARM_REACH - 2.7, 0, -0.5, across)
    finish(knuckle, col, "lemon", bevel=0.3, parent=pivot, name=f"Arm{k + 1}_Knuckle")
    # the ScoopCup on the wrist: a snug chocolate bowl around the scoop's lower third, opening along the wrist's +Z
    bowl = lathe(f"Arm{k + 1}_ScoopCup", cup_profile(), seg=14)
    place(bowl, ARM_REACH)
    finish(bowl, col, "chocolate", smooth_angle=60, parent=wrist, name=f"Arm{k + 1}_ScoopCup")
    rim_r, rim_z = cup_rim()
    rim = place(torus(rim_r, CUP_WALL / 2 + 0.06, 0, 14, 4), ARM_REACH, 0, rim_z)
    finish(rim, col, "lemon", parent=wrist, name=f"Arm{k + 1}_CupRim")
    ball = place(sphere(SCOOP_R, (0, 0, 0), 14, 7), ARM_REACH, 0, SCOOP_AT)  # preview only: the game shows it
    finish(ball, col, scoop_colors[k], parent=wrist, name=f"Arm{k + 1}_Scoop")
    muzzle = bpy.data.objects.new(f"Arm{k + 1}_Muzzle", None)
    muzzle.empty_display_type = "SPHERE"
    muzzle.empty_display_size = 0.8
    col.objects.link(muzzle)
    muzzle.matrix_world = Matrix.Translation(M @ Vector((ARM_REACH, 0, SCOOP_AT)))
    muzzle.parent = wrist
    muzzle.matrix_parent_inverse = wrist.matrix_world.inverted()


def set_arm_pose(n, pitch, cup_tilt=0.0):
    """Pitches arm n about its shoulder (positive = up) and turns its wrist so the cup's opening leans cup_tilt from
    straight up (positive = outward, away from the machine)."""
    bpy.data.objects[f"LauncherArm_{n}"].rotation_euler = Euler((0, -pitch, arm_yaws[n]), "XYZ")
    bpy.data.objects[f"Arm{n}_Wrist"].rotation_euler = Euler((0, pitch + cup_tilt, 0), "XYZ")


def set_arm_pitch(n, pitch):
    set_arm_pose(n, pitch, IDLE_CUP_TILT)


for n in arm_yaws:
    set_arm_pose(n, IDLE_PITCH, IDLE_CUP_TILT)

# ================= IceTanks: glass tubes with ice, on the tier =================
col = module("IceTanks")
fills = ["pink", "blue", "mint", "lemon"]
for k, deg in enumerate((30, 150, 210, 330)):  # between the arms, clear of the stairs
    a = math.radians(deg)
    p = (10.4 * math.cos(a), 10.4 * math.sin(a))
    finish(cyl(1.8, 7.0, HUB_Z0, 12, loc=p), col, "glass", bevel=0.3, name=f"IceTank_{k + 1}_Glass")
    finish(cyl(1.55, 4.8, HUB_Z0 + 0.6, 12, loc=p), col, fills[k], bevel=0.3, name=f"IceTank_{k + 1}_Ice")
    finish(cyl(2.1, 0.9, HUB_Z0 + 6.9, 12, loc=p), col, "chocolate", bevel=0.35, name=f"IceTank_{k + 1}_Cap")
    finish(cyl(2.1, 0.6, HUB_Z0, 12, loc=p), col, "lemon", bevel=0.25, name=f"IceTank_{k + 1}_Foot")

# ================= Sign: BIG SWIRL, big on the front of the cupcake =================
col = module("Sign")
TILT = math.radians(90 - 8)
SIGN_Y, SIGN_Z = -12.3, 15.6  # out in front of the cup, held by a strut, so the two front arms swing past its edges
SIGN_W, SIGN_H = 4.2, 3.2  # half width and height
board = lathe("Sign_Board", [(0, -0.45), (1, -0.45), (1, 0.45), (0, 0.45)], seg=40)
board.scale = (SIGN_W, SIGN_H, 1)
board.rotation_euler = (TILT, 0, 0)
board.location = (0, SIGN_Y, SIGN_Z)
bpy.context.view_layer.objects.active = board
for o in bpy.context.selected_objects:
    o.select_set(False)
board.select_set(True)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
finish(board, col, "cream", smooth_angle=50, name="Sign_Board")
border = torus(1.0, 0.09, 0, 40, 5)
border.scale = (SIGN_W, SIGN_H, SIGN_H)
border.rotation_euler = (TILT, 0, 0)
border.location = (0, SIGN_Y - 0.05, SIGN_Z)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
finish(border, col, "lemon", name="Sign_Border")
strut = capsule((0, -8.4, SIGN_Z - 0.6), (0, SIGN_Y + 0.4, SIGN_Z - 0.6), 0.45, 10)
finish(strut, col, "lemon", name="Sign_Strut")
# The lettering is preview only: in Roblox it is a SurfaceGui text on the board (no triangles, always sharp), so it
# lives outside the BigSwirl collection and is never exported.
preview = bpy.data.collections.get("PreviewOnly") or bpy.data.collections.new("PreviewOnly")
if preview.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(preview)
for ob in list(preview.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
for txt, z, size in (("BIG", 16.7, 2.4), ("SWIRL", 14.4, 1.9)):
    bpy.ops.object.text_add(location=(0, SIGN_Y - 0.55 + (z - SIGN_Z) * 0.14, z), rotation=(TILT, 0, 0))
    t = bpy.context.active_object
    t.data.body = txt
    t.data.size = size
    t.data.extrude = 0.3
    t.data.bevel_depth = 0.1
    t.data.bevel_resolution = 1
    t.data.resolution_u = 2
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    bpy.ops.object.convert(target="MESH")
    finish(bpy.context.active_object, preview, "pink", smooth_angle=30, name=f"Sign_{txt}")


def report():
    deps = bpy.context.evaluated_depsgraph_get()
    total = 0
    for c in root.children:
        n = 0
        for ob in c.all_objects:
            if ob.type == "MESH":
                e = ob.evaluated_get(deps)
                me = e.to_mesh()
                me.calc_loop_triangles()
                n += len(me.loop_triangles)
                e.to_mesh_clear()
        total += n
        print(f"{c.name}: {n}")
    print("TOTAL", total)
    mins = Vector((1e9,) * 3)
    maxs = Vector((-1e9,) * 3)
    for ob in root.all_objects:
        if ob.type == "MESH":
            for v in ob.bound_box:
                w = ob.matrix_world @ Vector(v)
                mins = Vector(map(min, mins, w))
                maxs = Vector(map(max, maxs, w))
    print("bounds", tuple(round(x, 1) for x in mins), tuple(round(x, 1) for x in maxs))


bpy.context.view_layer.update()
report()
