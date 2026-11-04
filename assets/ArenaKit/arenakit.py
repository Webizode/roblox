"""The arena kit: shared building blocks for every arena and plot model (cover block, waffle crate, pillar, rim,
entrances, ...). Each model's build script runs this first:
    ASSET_DIR = r"<repo>/assets/ArenaKit"
    exec(open(ASSET_DIR + "/arenakit.py").read())

1 Blender unit = 1 stud. Z is up here; the FBX export turns it into Roblox's Y up. Front is -Y, length along X.
Every model lives in its own collection (AK_<Model>) with its origin at the bottom centre (0, 0, 0), the Roblox
model's pivot.

Colour is the variant: every part uses one of the PALETTE materials and nothing else, so the export can merge a model
into one mesh per colour (<Model>_<Colour>) and Roblox recolours a variant through MeshPart.Color, never through new
meshes. No textures: the waffle lattice, drips and sprinkles are geometry, kept low (the whole cover block is about
3,000 triangles).

Blocks:
    rounded_box     the rounded plinth and every chunky block (Bevel modifier, kept live)
    waffle_panel    a waffle face: a lattice of rounded diagonal ridges on a flat face (two colours: Waffle, Gold)
    glaze           cream icing: a rounded slab on top with drips hanging over the long sides
    sprinkles       a few pill-shaped sprinkles, one mesh per colour
    cone_emblem     the shield with the ice cream cone (Gold rim, Pink field, Waffle cone, Cream swirl)
"""

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

# the arena palette (04.11.2026): material WS_<name>, Roblox part colour per name
PALETTE = {
    "Cream": "#FFF5E8",
    "Pink": "#F06AAE",
    "Waffle": "#D98A32",
    "SkyBlue": "#75D6F2",
    "Gold": "#F5C451",
}
# The same roles as Roblox part colours (04.11.2026): the island's light (CartoonColor +22 % saturation, sky-blue
# ambient and atmosphere) turned the waffle mustard, the gold lemony and the cream bluish, so in the game these are
# set instead. The Blender preview keeps PALETTE; the Studio template ServerStorage.ArenaKit.<Model> uses these.
GAME_COLOURS = {
    "Cream": "#FFE9D0",
    "Pink": "#F06AAE",
    "Waffle": "#E2782C",
    "SkyBlue": "#75D6F2",
    "Gold": "#F2A83C",
}
ROUGHNESS = 0.12  # glossy candy, like the Big Swirl
COAT = 0.5


def srgb_to_linear(hex_colour):
    h = hex_colour.lstrip("#")
    c = [int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    return [((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c] + [1]


def material(name):
    """The glossy material for a palette colour (created once)."""
    m = bpy.data.materials.get("WS_" + name) or bpy.data.materials.new("WS_" + name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = srgb_to_linear(PALETTE[name])
    bsdf.inputs["Roughness"].default_value = ROUGHNESS
    for key in ("Coat Weight", "Clearcoat"):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = COAT
    m.diffuse_color = srgb_to_linear(PALETTE[name])
    return m


def model_collection(name):
    """An empty collection AK_<name> for one model (rebuilt from scratch every run)."""
    col_name = "AK_" + name
    col = bpy.data.collections.get(col_name)
    if col:
        for ob in list(col.all_objects):
            bpy.data.objects.remove(ob, do_unlink=True)
    else:
        col = bpy.data.collections.new(col_name)
    if col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(col)
    return col


def _object(col, name, bm, colour, smooth_angle=35, recalc=True):
    # Roblox draws faces from one side only: closed parts get their normals pointing out; open sheets (the drip
    # curtain) are wound by hand and pass recalc=False
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    me.materials.append(material(colour))
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(smooth_angle))
    return ob


def _bevel(ob, width, segments, angle=35):
    mod = ob.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle)
    mod.harden_normals = False
    return mod


def rounded_box(col, name, colour, size, center, radius=0.25, segments=2):
    """A box (size x, y, z) at center with rounded edges: plinths, posts, caps, feet."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    ob = _object(col, name, bm, colour)
    _bevel(ob, min(radius, min(size) / 2 - 1e-3), segments)
    return ob


def _clip_line(px, pz, dx, dz, x0, x1, z0, z1):
    """The part of the line p + t * d inside the rectangle, as (t0, t1), or None."""
    t0, t1 = -math.inf, math.inf
    for p, d, lo, hi in ((px, dx, x0, x1), (pz, dz, z0, z1)):
        if abs(d) < 1e-9:
            if p < lo or p > hi:
                return None
            continue
        a, b = (lo - p) / d, (hi - p) / d
        t0, t1 = max(t0, min(a, b)), min(t1, max(a, b))
    return (t0, t1) if t1 > t0 else None


def _ridge(bm, a, b, y_face, outward, width, height):
    """A rounded ridge (trapezoid prism) from a to b, (x, z) points on the face plane y = y_face, raised by `height`
    in the `outward` direction (-1: towards -Y)."""
    ax, az = a
    bx, bz = b
    length = math.hypot(bx - ax, bz - az)
    ux, uz = (bx - ax) / length, (bz - az) / length
    nx, nz = -uz, ux  # across the ridge, in the face plane
    profile = [(-width / 2, 0.0), (-width / 4, height), (width / 4, height), (width / 2, 0.0)]
    rings = []
    for px, pz in ((ax, az), (bx, bz)):
        ring = []
        for across, up in profile:
            ring.append(bm.verts.new((px + nx * across, y_face + outward * up, pz + nz * across)))
        rings.append(ring)
    for i in range(len(profile) - 1):
        bm.faces.new((rings[0][i], rings[1][i], rings[1][i + 1], rings[0][i + 1]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[1])


def waffle_panel(col, name, size, center, spacing=1.45, ridge_width=0.5, ridge_height=0.2, faces=("front", "back")):
    """A waffle block: a flat Waffle body (size x, y, z at center) with a diagonal lattice of rounded Gold ridges on
    its front and/or back face. The ridges are clipped to the face; their ends sit under whatever frames the panel
    (posts, glaze, plinth). Returns (body, ridges)."""
    sx, sy, sz = size
    cx, cy, cz = center
    body = rounded_box(col, name + "_Body", "Waffle", size, center, radius=0.08, segments=1)
    bm = bmesh.new()
    x0, x1, z0, z1 = cx - sx / 2, cx + sx / 2, cz - sz / 2, cz + sz / 2
    step = spacing * math.sqrt(2)  # lines at +-45 degrees, `spacing` apart measured across them
    for face in faces:
        outward = -1 if face == "front" else 1
        y_face = cy + outward * sy / 2
        for direction in (1, -1):  # rising and falling diagonals
            dx, dz = 1 / math.sqrt(2), direction / math.sqrt(2)
            # lines through (x, cz) for x every `step`, enough to cover the face
            reach = sx / 2 + sz
            k = -math.ceil(reach / step)
            while k * step <= reach:
                px = cx + k * step + (step / 2 if direction < 0 else 0)
                span = _clip_line(px, cz, dx, dz, x0, x1, z0, z1)
                if span and span[1] - span[0] > ridge_width:
                    a = (px + dx * span[0], cz + dz * span[0])
                    b = (px + dx * span[1], cz + dz * span[1])
                    _ridge(bm, a, b, y_face, outward, ridge_width, ridge_height)
                k += 1
    ridges = _object(col, name + "_Ridges", bm, "Gold", smooth_angle=70)
    return body, ridges


def glaze(col, name, length, depth, top, thickness=0.6, drips=None, drip_base=0.45, columns=30, seed=1):
    """Cream icing on a block: a rounded slab (length x depth, `thickness` high, its top at `top`) and over both long
    sides a curtain hanging down with drips. `drips` is a list of (x, width, length) per side; by default three
    drips of different length, mirrored a little differently on the back. Returns the slab and the curtain."""
    slab = rounded_box(
        col, name + "_Top", "Cream", (length, depth, thickness), (0, 0, top - thickness / 2), radius=0.22, segments=3
    )
    rng = random.Random(seed)
    if drips is None:
        drips = {
            "front": [(-length * 0.30, 2.0, 1.5), (length * 0.02, 1.8, 1.0), (length * 0.30, 1.9, 1.35)],
            "back": [(-length * 0.31, 1.9, 1.2), (-length * 0.01, 2.0, 1.5), (length * 0.29, 1.8, 0.95)],
        }
    bm = bmesh.new()
    bottom_of_slab = top - thickness * 0.6
    for side, outward in (("front", -1), ("back", 1)):
        y = outward * (depth / 2 - 0.02)
        tops, bottoms = [], []
        for i in range(columns + 1):
            x = -length / 2 + length * i / columns
            hang = drip_base + 0.05 * math.sin(x * 2.3 + rng.random())
            for dx, width, drop in drips[side]:
                # a rounded drip: a smooth bump whose tip is round, not pointed
                t = (x - dx) / (width / 2)
                if abs(t) < 1:
                    hang += drop * math.sqrt(1 - t * t) ** 0.8
            tops.append(bm.verts.new((x, y, bottom_of_slab)))
            bottoms.append(bm.verts.new((x, y, bottom_of_slab - hang)))
        for i in range(columns):
            # wound so the normal points away from the block (-Y on the front, +Y on the back); Solidify grows that way
            quad = (tops[i], tops[i + 1], bottoms[i + 1], bottoms[i])
            bm.faces.new(quad[::-1] if outward < 0 else quad)
    curtain = _object(col, name + "_Drips", bm, "Cream", smooth_angle=80, recalc=False)
    solid = curtain.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = 0.32
    solid.offset = 1.0  # outward, off the block's face
    solid.use_even_offset = True
    _bevel(curtain, 0.12, 1, angle=60)  # one segment: rounded enough with smooth shading, a third of the triangles
    return slab, curtain


def sprinkles(col, name, spots, colours=("Pink", "SkyBlue", "Gold"), size=(1.05, 0.34, 0.26), seed=3):
    """Pill-shaped sprinkles lying on a surface: spots are (x, y, z) of their centres. Colours go round in turn,
    each colour one mesh (<name>_<Colour>). Few, by design."""
    rng = random.Random(seed)
    meshes = {c: bmesh.new() for c in colours}
    for i, (x, y, z) in enumerate(spots):
        bm = meshes[colours[i % len(colours)]]
        made = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=4, radius=0.5)
        verts = made["verts"]
        bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(rng.uniform(0, math.pi), 3, "Z"), verts=verts)
        bmesh.ops.translate(bm, vec=Vector((x, y, z + size[2] * 0.35)), verts=verts)
    return [_object(col, f"{name}_{c}", bm, c, smooth_angle=80) for c, bm in meshes.items()]


def _shield_outline(width, height):
    """A shield: flat top with rounded corners, straight sides, a point at the bottom. (u, v) points, v up."""
    w, h = width / 2, height / 2
    pts = []
    for i in range(5):  # rounded top corners
        a = math.pi / 2 * i / 4
        pts.append((w - 0.18 + 0.18 * math.cos(a), h - 0.18 + 0.18 * math.sin(a)))
    pts = pts[::-1]
    left = [(-u, v) for u, v in pts[::-1]]
    return left + pts + [(w, -h * 0.25), (0, -h), (-w, -h * 0.25)]


def _extruded(bm, outline, place, thickness):
    """A flat plate from a closed (u, v) outline, `thickness` deep along the place's normal. place(u, v, n) gives a
    world point."""
    front = [bm.verts.new(place(u, v, thickness)) for u, v in outline]
    back = [bm.verts.new(place(u, v, 0.0)) for u, v in outline]
    bm.faces.new(front)
    bm.faces.new(back[::-1])
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((back[i], back[j], front[j], front[i]))


def cone_emblem(col, name, center, normal, up=(0, 0, 1), width=1.4, height=1.9):
    """The ice cream cone shield on a face: center on the face, `normal` pointing out of it. Gold rim, Pink field,
    Waffle cone, Cream swirl, each its own mesh."""
    n = Vector(normal).normalized()
    v_axis = Vector(up).normalized()
    u_axis = v_axis.cross(n).normalized()
    c = Vector(center)
    s = width / 1.4  # the cone and the swirl are drawn for a 1.4 wide shield

    def placer(offset):
        return lambda u, v, d: c + u_axis * u + v_axis * v + n * (offset + d)

    parts = []
    bm = bmesh.new()
    _extruded(bm, _shield_outline(width, height), placer(0.0), 0.14)
    rim = _object(col, name + "_Rim", bm, "Gold", smooth_angle=50)
    _bevel(rim, 0.05, 1, angle=50)
    parts.append(rim)
    bm = bmesh.new()
    _extruded(bm, _shield_outline(width - 0.32, height - 0.36), placer(0.12), 0.06)
    parts.append(_object(col, name + "_Field", bm, "Pink", smooth_angle=50))
    # the cone: a rounded triangle, its point down
    bm = bmesh.new()
    cone = [(-0.36 * s, 0.05 * s), (0.36 * s, 0.05 * s), (0.0, -0.72 * s)]
    _extruded(bm, cone, placer(0.17), 0.1)
    cone_ob = _object(col, name + "_Cone", bm, "Waffle", smooth_angle=50)
    _bevel(cone_ob, 0.05, 2, angle=50)
    parts.append(cone_ob)
    # the swirl: three soft blobs, smaller towards the top, flattened onto the shield
    bm = bmesh.new()
    for du, dv, r in ((0.0, 0.2, 0.34), (0.02, 0.45, 0.26), (0.0, 0.64, 0.15)):
        made = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=4, radius=r * s)
        for vert in made["verts"]:
            local = vert.co.copy()
            vert.co = c + u_axis * (du * s + local.x) + v_axis * (dv * s + local.z * 0.8) + n * (0.22 + local.y * 0.35)
    parts.append(_object(col, name + "_Swirl", bm, "Cream", smooth_angle=80))
    return parts


def triangles(col):
    """Triangles of the model as exported (modifiers applied)."""
    deps = bpy.context.evaluated_depsgraph_get()
    total = 0
    for ob in col.all_objects:
        if ob.type == "MESH":
            me = ob.evaluated_get(deps).to_mesh()
            me.calc_loop_triangles()
            total += len(me.loop_triangles)
            ob.evaluated_get(deps).to_mesh_clear()
    return total
