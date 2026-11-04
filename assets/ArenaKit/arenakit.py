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
    banner          a cone_emblem hanging from a Gold rod, for round faces (pillars)
    cylinder        a round block (discs, rings, stems), rounded edges
    waffle_cylinder a Waffle cylinder with the diagonal Gold lattice wound round it
    drip_curtain    cream drips hanging from any line (straight, round, arched), one Solidify sheet
    round_glaze     a Cream cap on a cylinder with drips all round
    soft_serve      the swirl on top: stacked soft tiers and a tip, plus a Cherry if asked
    cone_pillar     the waffle-cone pillar used by the Ice Cream Pillar, the rim pillars and the entrance
    arc_box         a block bent round the arena centre (the rim): radius R, `span` degrees, origin on its arc
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
    "Cherry": "#E8384F",  # only the cherry on a swirl
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
    "Cherry": "#E8384F",
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


def banner(col, name, center, normal, width=1.9, height=2.6):
    """A cone_emblem hanging from a short Gold rod: on a round face the flat shield only touches in the middle, the
    rod makes that read as a hanging banner."""
    parts = cone_emblem(col, name, center, normal, width=width, height=height)
    n = Vector(normal).normalized()
    u = Vector((0, 0, 1)).cross(n).normalized()
    c = Vector(center) + Vector((0, 0, height / 2 + 0.12)) + n * 0.12
    rod = rounded_box(col, name + "_Rod", "Gold", (width + 0.5, 0.3, 0.3), (0, 0, 0), radius=0.1, segments=1)
    rod.rotation_euler = (0, 0, math.atan2(u.y, u.x))
    rod.location = c
    parts.append(rod)
    return parts


def cylinder(col, name, colour, radius, height, z0, center=(0, 0), segments=24, bevel=0.15, radius_top=None,
             bevel_segments=2):
    """An upright round block from z0 to z0 + height (radius_top: a cone frustum), rounded edges."""
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius if radius_top is None else radius_top,
        depth=height,
    )
    bmesh.ops.translate(bm, vec=Vector((center[0], center[1], z0 + height / 2)), verts=bm.verts)
    ob = _object(col, name, bm, colour, smooth_angle=40)
    if bevel:
        _bevel(ob, min(bevel, height / 2 - 1e-3), bevel_segments, angle=40)
    return ob


def _tube(col, name, colour, points, thickness, sides=4):
    """A thin tube along points (a poly curve with a bevel, made a mesh): lattice ridges, stems."""
    curve = bpy.data.curves.new(name + "_curve", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = thickness / 2
    curve.bevel_resolution = max(0, sides // 2 - 2)
    curve.use_fill_caps = True
    for pts in points:
        spline = curve.splines.new("POLY")
        spline.points.add(len(pts) - 1)
        for p, (x, y, z) in zip(spline.points, pts):
            p.co = (x, y, z, 1)
    tmp = bpy.data.objects.new(name + "_tmp", curve)
    col.objects.link(tmp)
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(deps), depsgraph=deps)
    bpy.data.objects.remove(tmp, do_unlink=True)
    bpy.data.curves.remove(curve)
    me.name = name
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    me.materials.clear()
    me.materials.append(material(colour))
    me.shade_smooth()
    return ob


def waffle_cylinder(col, name, radius, height, z0, center=(0, 0), spacing=1.45, ridge=0.42, segments=24,
                    step_len=0.7):
    """A Waffle cylinder with the lattice of the waffle panels wound round it: rising and falling 45 degree helices
    `spacing` apart, Gold tubes half sunk into the surface. Returns (body, ridges)."""
    body = cylinder(col, name + "_Body", "Waffle", radius, height, z0, center, segments, bevel=0.06, bevel_segments=1)
    count = max(3, round(2 * math.pi * radius / (spacing * math.sqrt(2))))
    lines = []
    r = radius + ridge * 0.12
    steps = max(6, int(height / step_len))  # step_len 0.7: about 20 degrees round per step on a 2-stud pillar
    for direction in (1, -1):
        for k in range(count):
            a0 = 2 * math.pi * k / count + (math.pi / count if direction < 0 else 0)
            pts = []
            for i in range(steps + 1):
                z = height * i / steps
                a = a0 + direction * z / radius  # 45 degrees: one stud up per stud round
                pts.append((center[0] + r * math.cos(a), center[1] + r * math.sin(a), z0 + z))
            lines.append(pts)
    ridges = _tube(col, name + "_Ridges", "Gold", lines, ridge)
    return body, ridges


def drip_curtain(col, name, tops, hangs, outward, thickness=0.3):
    """Cream drips hanging from a line: tops (points), how far each hangs (studs down) and the outward direction
    there. One sheet, wound outwards, thickened outwards by Solidify and softened by a Bevel."""
    bm = bmesh.new()
    tv = [bm.verts.new(p) for p in tops]
    bv = [bm.verts.new(Vector(p) - Vector((0, 0, h))) for p, h in zip(tops, hangs)]
    for i in range(len(tops) - 1):
        f = bm.faces.new((tv[i], tv[i + 1], bv[i + 1], bv[i]))
        f.normal_update()
        if f.normal.dot(Vector(outward[i])) < 0:
            f.normal_flip()
    curtain = _object(col, name, bm, "Cream", smooth_angle=80, recalc=False)
    solid = curtain.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = thickness
    solid.offset = 1.0
    solid.use_even_offset = True
    _bevel(curtain, 0.1, 1, angle=60)
    return curtain


def drip_profile(length, drips, base=0.4, wobble=0.05, seed=1):
    """How far a curtain hangs along its length: a base plus round drips (position along, width, drop)."""
    rng = random.Random(seed)
    phase = rng.random() * 6

    def hang(s):
        h = base + wobble * math.sin(s * 2.3 + phase)
        for at, width, drop in drips:
            t = (s - at) / (width / 2)
            if abs(t) < 1:
                h += drop * math.sqrt(1 - t * t) ** 0.8
        return h

    return hang


def round_glaze(col, name, radius, top, thickness=0.7, drips=7, drop=(0.6, 1.3), center=(0, 0), seed=2, columns=32,
                segments=24, bevel_segments=2):
    """A Cream cap on a cylinder (slab of `radius`, its top at `top`) with drips all round. Returns slab, curtain."""
    slab = cylinder(col, name + "_Top", "Cream", radius, thickness, top - thickness, center, segments, bevel=0.25,
                    bevel_segments=bevel_segments)
    rng = random.Random(seed)
    circumference = 2 * math.pi * radius
    spots = [
        (circumference * (i + rng.uniform(-0.2, 0.2)) / drips, rng.uniform(1.0, 1.6), rng.uniform(*drop))
        for i in range(drips)
    ]
    # wrap the drips round the seam: each drip also counted one circumference before and after
    wrapped = [(s + k * circumference, w, d) for s, w, d in spots for k in (-1, 0, 1)]
    hang = drip_profile(circumference, wrapped, wobble=0.0, seed=seed)
    z = top - thickness * 0.55
    tops, hangs, out = [], [], []
    r = radius - 0.06
    for i in range(columns + 1):
        a = 2 * math.pi * i / columns
        tops.append((center[0] + r * math.cos(a), center[1] + r * math.sin(a), z))
        hangs.append(hang(circumference * i / columns))
        out.append((math.cos(a), math.sin(a), 0))
    curtain = drip_curtain(col, name + "_Drips", tops, hangs, out)
    return slab, curtain


def soft_serve(col, name, colour, radius, z0, tiers=3, cherry=True):
    """The soft swirl on top: tiers of soft rounded discs getting smaller and a tip, plus a Cherry with a stem.
    Returns the parts and the height of its top."""
    bm = bmesh.new()
    z = z0
    r = radius
    for i in range(tiers):
        h = r * 0.62
        made = bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=7, radius=1.0)
        bmesh.ops.scale(bm, vec=Vector((r, r, h)), verts=made["verts"])
        bmesh.ops.translate(bm, vec=Vector((0, 0, z + h * 0.55)), verts=made["verts"])
        z += h * 0.85
        r *= 0.74
    made = bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=r * 0.95, radius2=0.05, depth=r * 1.3)
    bmesh.ops.translate(bm, vec=Vector((0, 0, z + r * 0.45)), verts=made["verts"])
    top = z + r * 1.1
    parts = [_object(col, name, bm, colour, smooth_angle=80)]
    if cherry:
        cr = max(0.35, radius * 0.24)
        bm = bmesh.new()
        made = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=cr)
        bmesh.ops.translate(bm, vec=Vector((0, 0, top + cr * 0.6)), verts=made["verts"])
        parts.append(_object(col, name + "_Cherry", bm, "Cherry", smooth_angle=80))
        stem = [[(0, 0, top + cr * 1.4), (cr * 0.3, 0, top + cr * 2.2), (cr * 0.9, 0, top + cr * 2.7)]]
        parts.append(_tube(col, name + "_Stem", "Cherry", stem, cr * 0.25))
        top += cr * 2.7
    return parts, top


def cone_pillar(col, name, radius, body_height, base=0.7, swirl="Pink", cherry=True, banners=(-1,), seed=4,
                center=(0, 0), lean=False):
    """A waffle-cone pillar: Cream foot, Gold ring, Waffle body with lattice, Cream glaze with drips, the swirl on
    top and a banner on the front (-1: -Y) and/or back (+1: +Y). Standing at center, its foot at z 0. Returns the
    height of its top. lean: fewer segments and a coarser lattice, for pillars that stand many times on the map
    (the entrances)."""
    seg, bseg = (16, 1) if lean else (24, 2)
    cylinder(col, name + "_Foot", "Cream", radius * 1.28, base, 0, center, seg, bevel=0.3, bevel_segments=bseg)
    cylinder(col, name + "_Ring", "Gold", radius * 1.1, 0.45, base, center, seg, bevel=0.15, bevel_segments=bseg)
    waffle_cylinder(col, name + "_Waffle", radius, body_height, base + 0.3, center, segments=seg,
                    spacing=1.9 if lean else 1.45, step_len=1.0 if lean else 0.7)
    top = base + 0.3 + body_height
    glaze_t = max(0.6, radius * 0.32)
    round_glaze(col, name + "_Glaze", radius * 1.2, top + glaze_t * 0.75, thickness=glaze_t, seed=seed,
                drop=(radius * 0.15, radius * 0.35), center=center, columns=24 if lean else 32, segments=seg,
                bevel_segments=bseg)
    parts, tip = soft_serve(col, name + "_Swirl", swirl, radius * 1.05, top + glaze_t * 0.6, cherry=cherry)
    for ob in parts:
        ob.location = (center[0], center[1], 0)
    # banners in front of the lattice ridges (they stand ~0.25 proud) and below the drips
    height = min(body_height * 0.62, radius * 1.4)
    mid = base + 0.3 + body_height * 0.45
    for side in banners:
        banner(col, f"{name}_Banner{'F' if side < 0 else 'B'}", (center[0], center[1] + side * (radius + 0.3), mid),
               (0, side, 0), width=radius * 1.08, height=height)
    return tip


def _arc_point(R, r, phi, z):
    """A point of a block bent round the arena centre, in the frame where the arc of radius R passes the origin
    and the centre lies at (0, -R): r from the arena centre, phi the angle off the middle."""
    return (r * math.sin(phi), -R + r * math.cos(phi), z)


def arc_box(col, name, colour, R, r0, r1, z0, z1, span, segments=10, radius=0.2, phi0=0.0):
    """A block bent round the arena centre: from radius r0 to r1, z0 to z1, `span` degrees, centred on phi0."""
    bm = bmesh.new()
    rings = []
    half = math.radians(span) / 2
    for i in range(segments + 1):
        phi = phi0 - half + 2 * half * i / segments
        rings.append(
            [bm.verts.new(_arc_point(R, r, phi, z)) for r, z in ((r0, z0), (r1, z0), (r1, z1), (r0, z1))]
        )
    for i in range(segments):
        for k in range(4):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % 4], rings[i + 1][(k + 1) % 4], rings[i + 1][k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    ob = _object(col, name, bm, colour, smooth_angle=30)
    _bevel(ob, min(radius, (z1 - z0) / 2 - 1e-3, (r1 - r0) / 2 - 1e-3), 2, angle=30)
    return ob


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
