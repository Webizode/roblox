"""Arena kit 2 (14.11.2026): new cover, platforms, landmarks and special cover for the arena, so it stops looking like
copies of the same block. Reference in the vault (Wobble Scoops/Wooble scoops Map assets 1/Arena_Referenz_Komplett.png):
    middle cover (jump on, walk on top; 5.1 to 6.4 high, the rule of 14.11.2026):
        WaffleCrates, FallenCone, CookieStack, ChocoBar, CandyBox
    high cover (from 10.85 high, never from the ground):
        SundaeCup, ChocoWall, WaffleArch, GiantCupcake, MacaronStack, CookieTower
    platforms (top 6.0, a ramp or stairs at least 6 wide for a player with a tower):
        WafflePlatform, CakePlatform
    landmarks (big, seen from all over the arena):
        GrandSundae, CreamMountain, LollipopTree
    special cover, both states as models of their own (no game logic yet):
        WobbleTower / WobbleTowerFallen, CreamDispenser / CreamDispenserSpill, GummyPad / GummyPadPressed

Changes against the picture: the cookies lie stacked (standing on edge they had no flat top); the cookie tower is high
cover without the spiral path (a path wide enough for a tower would make it some 26 studs across); the gummy bear stays
on the pad when it is pressed (squashed), only the player will fly.

Run through run_arenakit2.py. Studs, origin at the bottom centre, front -Y. Sizes against an R15 figure (5.2 studs).
Rules: one colour per material (colour as the variant), few triangles, collision as close to the visible model as
boxes, upright cylinders and ramp wedges allow (no invisible walls), surfaces to stand on are flat.
"""

import math
import random

import bmesh
from mathutils import Matrix, Vector

for _name, _hex in {
    "Mint": "#7FE0B8",
    "Lemon": "#FFE15A",
    "Lavender": "#BB9CF0",
    "Cookie": "#D9A15B",
    "ChocoDark": "#5A3320",
    "Sponge": "#F2C27A",
    "Ice": "#BFE9F5",
    "Gummy": "#FF4F8B",
}.items():
    PALETTE[_name] = _hex
    GAME_COLOURS[_name] = _hex

TOP_MID = 5.9  # the walkable top of middle cover
PLATFORM_TOP = 6.0

# --------------------------------------------------------------------------------------------------------------------
# building blocks of this kit


def wedge(width, length, height, center, rise):
    """A collision ramp: width across, length along the slope, rising towards `rise` ("+x", "-x", "+y", "-y"; Blender
    frame). center is the middle of its bounding box. Roblox: a WedgePart is high at +Z, turned by yaw round Y."""
    dx, dy = {"+x": (1, 0), "-x": (-1, 0), "+y": (0, 1), "-y": (0, -1)}[rise]
    yaw = math.degrees(math.atan2(-dx, dy))  # Roblox X is -Blender X, Roblox Z is Blender Y
    return dict(kind="wedge", size=[round(width, 3), round(length, 3), round(height, 3)],
                center=[round(v, 3) for v in center], yaw=round(yaw, 1))


def _turn(ob, angle, about="Z"):
    ob.data.transform(Matrix.Rotation(angle, 4, about))


def _move(ob, offset):
    ob.data.transform(Matrix.Translation(Vector(offset)))


def prism(col, name, colour, outline, y0, y1, bevel=0.06):
    """An outline in (x, z) (any shape, also concave) extruded from y0 to y1, the faces triangulated."""
    bm = bmesh.new()
    front = [bm.verts.new((x, y0, z)) for x, z in outline]
    back = [bm.verts.new((x, y1, z)) for x, z in outline]
    faces = [bm.faces.new(front), bm.faces.new(back[::-1])]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.triangulate(bm, faces=faces, quad_method="BEAUTY", ngon_method="EAR_CLIP")
    ob = _object(col, name, bm, colour, smooth_angle=30)
    if bevel:
        _bevel(ob, bevel, 1, angle=30)
    return ob


def ramp(col, name, colour, width, length, height, center_xy, rise):
    """A visible ramp (a wedge with softened edges) whose low end is at the floor, rising towards `rise`."""
    ob = prism(col, name, colour, [(-length / 2, 0), (length / 2, 0), (length / 2, height)], -width / 2, width / 2,
               bevel=0.08)
    _turn(ob, {"+x": 0, "+y": math.pi / 2, "-x": math.pi, "-y": -math.pi / 2}[rise])
    _move(ob, (center_xy[0], center_xy[1], 0))
    return ob


def waffle_block(col, name, size, center, sides=True):
    """A waffle box with the gold lattice on all four sides (front/back from waffle_panel, the sides from a turned
    second panel whose body is dropped)."""
    body, ridges = waffle_panel(col, name, size, center)
    parts = [body, ridges]
    if sides:
        sx, sy, sz = size
        b2, r2 = waffle_panel(col, name + "_S", (sy, sx, sz), (0, 0, center[2]))
        bpy.data.objects.remove(b2, do_unlink=True)
        _turn(r2, math.pi / 2)
        _move(r2, (center[0], center[1], 0))
        parts.append(r2)
    return parts


def _face_frame(face, size, center):
    """For a vertical face of a box: a function (a, z) -> 3D point slightly off the face, the face's half width and
    its outward normal."""
    sx, sy, sz = size
    cx, cy, cz = center
    off = 0.035
    if face in ("front", "back"):
        s = -1 if face == "front" else 1
        return (lambda a, z: (cx + a, cy + s * (sy / 2 + off), z)), sx / 2, (0, s, 0)
    s = -1 if face == "left" else 1
    return (lambda a, z: (cx + s * (sx / 2 + off), cy - s * a, z)), sy / 2, (s, 0, 0)


def stripes(col, name, colour, size, center, width=1.0, spacing=2.2, faces=("front", "back", "left", "right")):
    """Diagonal candy stripes lying just off the four sides of a box: thin flat bands, clipped to each face."""
    bm = bmesh.new()
    sz = size[2]
    z0, z1 = center[2] - sz / 2, center[2] + sz / 2
    for face in faces:
        at, half, normal = _face_frame(face, size, center)
        dx, dz = 1 / math.sqrt(2), 1 / math.sqrt(2)
        reach = half + sz
        k = -math.ceil(reach / spacing)
        while k * spacing <= reach:
            ends = []
            for side in (-width / 2, width / 2):
                px = k * spacing + side * math.sqrt(2)
                span = _clip_line(px, center[2], dx, dz, -half, half, z0, z1)
                ends.append(None if not span else ((px + dx * span[0], center[2] + dz * span[0]),
                                                   (px + dx * span[1], center[2] + dz * span[1])))
            k += 1
            if None in ends:
                continue
            (a0, a1), (b0, b1) = ends
            quad = [bm.verts.new(at(*p)) for p in (a0, a1, b1, b0)]
            f = bm.faces.new(quad)
            f.normal_update()
            if f.normal.dot(Vector(normal)) < 0:
                f.normal_flip()
    return _object(col, name, bm, colour, smooth_angle=30, recalc=False)


def stuck_sprinkles(col, name, objects, count, z_range, seed, reach=40.0, size=(0.9, 0.3, 0.24), center=(0, 0)):
    """Sprinkles stuck onto the real surface of `objects` (modifiers applied): rays from outside, a little from above,
    towards the model's axis at random angles and heights in z_range; each lands where its ray hits."""
    from mathutils.bvhtree import BVHTree

    deps = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    for ob in objects:
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(deps), depsgraph=deps)
        me.transform(ob.matrix_world)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    tree = BVHTree.FromBMesh(bm)
    rng = random.Random(seed)
    spots = []
    for _ in range(count * 4):
        if len(spots) >= count:
            break
        a, z = rng.uniform(0, 2 * math.pi), rng.uniform(*z_range)
        axis = Vector((center[0], center[1], z))
        origin = axis + Vector((reach * math.cos(a), reach * math.sin(a), reach * 0.35))
        hit = tree.ray_cast(origin, (axis - origin).normalized())
        if hit[0] is not None:
            spots.append((tuple(hit[0]), tuple(hit[1])))
    bm.free()
    return surface_sprinkles(col, name, spots, size=size, seed=seed)


def disc_sprinkles(col, name, radius, z, count, seed, center=(0, 0)):
    rng = random.Random(seed)
    spots = []
    for i in range(count):
        a, r = rng.uniform(0, 2 * math.pi), radius * math.sqrt(rng.uniform(0.05, 1))
        spots.append((center[0] + r * math.cos(a), center[1] + r * math.sin(a), z))
    return sprinkles(col, name, spots, colours=("Pink", "SkyBlue", "Gold", "Mint"), size=(0.9, 0.3, 0.22), seed=seed)


def top_sprinkles(col, name, x_half, y_half, z, count, seed):
    rng = random.Random(seed)
    spots = [(rng.uniform(-x_half, x_half), rng.uniform(-y_half, y_half), z) for _ in range(count)]
    return sprinkles(col, name, spots, colours=("Pink", "SkyBlue", "Gold", "Mint"), size=(0.9, 0.3, 0.22), seed=seed)


def iced_block(col, name, size, top, drips_seed=1, sprinkle_count=7):
    """The cream glaze over a block whose top is at `top` (size: the block's x, y): a flat slab a little wider than
    the block with drips over the front and back, and a few sprinkles. Returns the slab's collision box."""
    length, depth = size[0] + 0.3, size[1] + 0.3
    glaze(col, name + "_Glaze", length, depth, top, thickness=0.55, seed=drips_seed)
    top_sprinkles(col, name + "_Sprinkles", length / 2 - 0.9, depth / 2 - 0.8, top, sprinkle_count, drips_seed + 10)
    return box((length, depth, 0.55), (0, 0, top - 0.275), "Glaze")


def cookie(col, name, radius, thickness, z0, center=(0, 0), seed=1, chips_top=6, chips_side=7):
    cylinder(col, name, "Cookie", radius, thickness, z0, center, segments=24, bevel=min(0.45, thickness * 0.4),
             bevel_segments=2)
    rng = random.Random(seed)
    for i in range(chips_top):
        a, r = rng.uniform(0, 2 * math.pi), rng.uniform(0.6, radius - 0.8)
        ball(col, f"{name}_ChipT{i}", "ChocoDark", 0.38, (center[0] + r * math.cos(a), center[1] + r * math.sin(a),
                                                            z0 + thickness - 0.02), squash=0.45, segments=8)
    for i in range(chips_side):
        a = 2 * math.pi * (i + rng.uniform(-0.25, 0.25)) / chips_side
        ball(col, f"{name}_ChipS{i}", "ChocoDark", 0.34, (center[0] + (radius - 0.02) * math.cos(a),
                                                            center[1] + (radius - 0.02) * math.sin(a),
                                                            z0 + thickness * rng.uniform(0.35, 0.65)),
             segments=8, scale=(0.8, 0.8, 0.8))


def choco_tiles(col, name, size, center, cols, rows, faces=("front", "back"), proud=0.22, gap=0.32):
    """Raised chocolate squares on the front and back of a ChocoDark body: the bar's pieces."""
    sx, sy, sz = size
    cx, cy, cz = center
    tw, th = (sx - gap * (cols + 1)) / cols, (sz - gap * (rows + 1)) / rows
    for face in faces:
        s = -1 if face == "front" else 1
        for i in range(cols):
            for j in range(rows):
                x = cx - sx / 2 + gap + tw / 2 + i * (tw + gap)
                z = cz - sz / 2 + gap + th / 2 + j * (th + gap)
                rounded_box(col, f"{name}_{face}{i}{j}", "Choco", (tw, proud * 2, th), (x, cy + s * sy / 2, z),
                            radius=0.18, segments=1)


def scoop(col, name, colour, radius, center_z, at=(0, 0), part=None, seed=1):
    """An ice cream scoop: a glossy ball, a little squashed, with a drip skirt round its waist."""
    blob(col, name, colour, radius, center_z - radius * 0.75, center_z, center_z + radius * 0.85, at, segments=18,
         part=part)
    drip_skirt(col, name + "_Drips", colour, radius - 0.05, center_z - radius * 0.1, drips=6,
               drop=(radius * 0.18, radius * 0.4), width=(radius * 0.4, radius * 0.7), thickness=0.22, seed=seed,
               center=at, part=part)


# --------------------------------------------------------------------------------------------------------------------
# middle cover


def build_waffle_crates():
    col = hk_collection("WaffleCrates")
    waffle_block(col, "Low", (8.4, 6.0, 2.9), (0, 0, 1.45))
    waffle_block(col, "High", (7.6, 5.4, 2.55), (0.15, 0.1, 2.9 + 1.275))
    rounded_box(col, "Band", "Gold", (8.0, 5.8, 0.25), (0.1, 0.05, 2.9), radius=0.1, segments=1)
    glaze_box = iced_block(col, "Top", (7.6, 5.4), TOP_MID, drips_seed=3)
    glaze_box["center"][0], glaze_box["center"][1] = 0.15, 0.1
    SPECS["WaffleCrates"] = dict(
        collision=[box((8.4, 6.0, 2.9), (0, 0, 1.45), "Low"), box((7.6, 5.4, 2.6), (0.15, 0.1, 4.2), "High"),
                   glaze_box],
        figure=(-6.8, -3.6),
    )


def build_fallen_cone():
    col = hk_collection("FallenCone")
    length, r_tip, r_open = 9.0, 0.6, 2.85
    body, ridges = waffle_cone(col, "Cone", r_tip, r_open, length, 0.0, segments=20)
    half = math.atan((r_open - r_tip) / length)
    for ob in (body, ridges):
        _turn(ob, math.pi / 2, "Y")  # the axis along +x, the opening at +x
        _turn(ob, -half, "Y")  # lifted so the lower side lies along the floor
    lo = min(min((ob.matrix_world @ v.co).z for v in ob.data.vertices) for ob in (body, ridges))
    for ob in (body, ridges):
        _move(ob, (-length / 2 + 0.6, 0, -lo))
    # the scoop rolled out of the opening, flattened where it lies, and a cream puddle
    scoop_ob = blob(col, "Scoop", "Pink", 2.6, None, 0.0, 3.3, (6.4, 0.3), segments=18, part="Scoop")
    drip_skirt(col, "Scoop_Drips", "Pink", 2.5, 1.4, drips=5, drop=(0.4, 0.9), width=(0.9, 1.4), thickness=0.25,
               seed=4, center=(6.4, 0.3), part="Scoop")
    blob(col, "Puddle", "Cream", 3.4, None, 0.02, 0.42, (7.0, 0.6), segments=18)
    stuck_sprinkles(col, "Sprinkles", [scoop_ob], 6, (2.0, 3.0), 11, reach=10.0, center=(6.4, 0.3))
    # stepped boxes along the cone (inside its round outline), and the scoop
    coll = []
    x0 = -length / 2 + 0.6
    for k in range(4):
        xa, xb = x0 + length * k / 4, x0 + length * (k + 1) / 4
        r = r_tip + (r_open - r_tip) * (k + 0.5) / 4
        top = 2 * (r_tip + (r_open - r_tip) * (k + 1) / 4) * math.cos(half) * 0.97
        coll.append(box((xb - xa, 2 * r * 0.82, top), ((xa + xb) / 2, 0, top / 2), f"Cone{k}"))
    coll.append(cyl(2.3, 3.2, (6.4, 0.3), name="Scoop"))
    SPECS["FallenCone"] = dict(collision=coll, figure=(-6.8, -3.4),
                               variants={"Mint": {"Scoop": "Mint"}, "Lemon": {"Scoop": "Lemon"}})


def build_cookie_stack():
    col = hk_collection("CookieStack")
    offsets = [(0, 0), (0.35, -0.2), (-0.25, 0.25), (0.2, 0.15)]
    thick = TOP_MID / 4
    coll = []
    for i, (ox, oy) in enumerate(offsets):
        cookie(col, f"Cookie{i}", 3.1, thick, i * thick, (ox, oy), seed=i + 1, chips_top=6 if i == 3 else 0)
        coll.append(cyl(3.05, thick, (ox, oy), z0=i * thick, name=f"Cookie{i}"))
    SPECS["CookieStack"] = dict(collision=coll, figure=(-5.4, -3.2))


def build_choco_bar():
    col = hk_collection("ChocoBar")
    size, top = (9.0, 4.4, 5.3), TOP_MID
    rounded_box(col, "Body", "ChocoDark", size, (0, 0, size[2] / 2), radius=0.25, segments=2)
    choco_tiles(col, "Tile", size, (0, 0, size[2] / 2), cols=3, rows=2)
    glaze_box = iced_block(col, "Top", (9.0, 4.4), top, drips_seed=6)
    SPECS["ChocoBar"] = dict(collision=[box((9.0, 4.8, 5.35), (0, 0, 2.675), "Body"), glaze_box],
                             figure=(-6.6, -3.2))


def build_candy_box():
    col = hk_collection("CandyBox")
    size = (6.6, 6.6, 5.35)
    rounded_box(col, "Body", "Cream", size, (0, 0, size[2] / 2), radius=0.3, segments=2)
    tag(stripes(col, "Stripes", "Pink", size, (0, 0, size[2] / 2), width=1.0, spacing=2.3), "Stripes")
    glaze_box = iced_block(col, "Top", (6.6, 6.6), TOP_MID, drips_seed=7, sprinkle_count=6)
    SPECS["CandyBox"] = dict(collision=[box(size, (0, 0, size[2] / 2), "Body"), glaze_box], figure=(-5.6, -3.4),
                             variants={"Mint": {"Stripes": "Mint"}, "Blue": {"Stripes": "SkyBlue"}})


# --------------------------------------------------------------------------------------------------------------------
# high cover


def sundae(col, prefix, s, scoops=("Pink", "Lemon", "Choco"), wafers=False):
    """A footed ice-blue glass bowl with three scoops, cream, a cherry; scale s (1: about 12.6 high). Returns the
    collision."""
    lathe(col, prefix + "Foot", "Ice", [(0, 0), (2.6 * s, 0), (2.7 * s, 0.25 * s), (2.3 * s, 0.6 * s),
                                        (0.95 * s, 0.85 * s), (0, 0.85 * s)], segments=24)
    cylinder(col, prefix + "Stem", "Ice", 0.85 * s, 2.6 * s, 0.75 * s, segments=16, bevel=0.1)
    bowl = [(0, 3.2 * s), (1.3 * s, 3.25 * s), (2.6 * s, 3.8 * s), (3.7 * s, 4.9 * s), (4.4 * s, 6.3 * s),
            (4.65 * s, 7.4 * s), (4.4 * s, 7.6 * s), (0, 7.6 * s)]
    lathe(col, prefix + "Bowl", "Ice", bowl, segments=28)
    drip_skirt(col, prefix + "Rim", "Cream", 4.55 * s, 7.45 * s, drips=9, drop=(0.4 * s, 1.1 * s),
               width=(0.9 * s, 1.5 * s), thickness=0.3 * s, seed=21)
    blob(col, prefix + "Cream", "Cream", 4.3 * s, None, 7.5 * s, 8.4 * s, segments=24)
    ring = 1.75 * s
    for i, colour in enumerate(scoops):
        a = math.pi / 2 + 2 * math.pi * i / 3 + math.pi / 3
        scoop(col, f"{prefix}Scoop{i}", colour, 2.25 * s, 9.3 * s, (ring * math.cos(a), ring * math.sin(a)),
              part=f"Scoop{i}", seed=30 + i)
    parts, top = soft_serve(col, prefix + "Swirl", "Cream", 1.6 * s, 10.6 * s, tiers=2, cherry=True)
    dome_sprinkles(col, prefix + "Sprinkles", 3.4 * s, 9.3 * s, 11.2 * s, 10, seed=41)
    if wafers:
        for k, (x, y, lean) in enumerate(((-1.6, 0.9, 0.35), (-0.6, 1.6, 0.15))):
            stick = [[(x * s, y * s, 9.0 * s), ((x - lean * 4) * s, (y + 0.3) * s, 15.0 * s)]]
            _tube(col, f"{prefix}Wafer{k}", "Gold", stick, 0.7 * s, sides=8)
            # the chocolate stripe stops short of both ends, so its end faces never lie on the wafer's
            a, b = Vector(stick[0][0]), Vector(stick[0][1])
            inset = (b - a).normalized() * 0.4 * s
            _tube(col, f"{prefix}WaferStripe{k}", "Choco", [[tuple(a + inset), tuple(b - inset)]], 0.74 * s, sides=4)
    return [cyl(2.6 * s, 0.85 * s, name="Foot"), cyl(0.85 * s, 2.6 * s, z0=0.75 * s, name="Stem"),
            cyl(2.9 * s, 1.6 * s, z0=3.3 * s, name="BowlLow"), cyl(4.3 * s, 2.7 * s, z0=4.9 * s, name="Bowl"),
            cyl(3.9 * s, 3.4 * s, z0=7.6 * s, name="Scoops")], top


def build_sundae_cup():
    col = hk_collection("SundaeCup")
    coll, top = sundae(col, "", 1.0)
    SPECS["SundaeCup"] = dict(collision=coll, figure=(-6.6, -3.6), top=round(top, 2))


def build_choco_wall():
    col = hk_collection("ChocoWall")
    size, top = (12.0, 3.2, 11.3), 11.85
    rounded_box(col, "Body", "ChocoDark", size, (0, 0, size[2] / 2), radius=0.3, segments=2)
    choco_tiles(col, "Tile", size, (0, 0, size[2] / 2), cols=4, rows=4)
    glaze_box = iced_block(col, "Top", (12.0, 3.2), top, drips_seed=9, sprinkle_count=8)
    SPECS["ChocoWall"] = dict(collision=[box((12.0, 3.6, 11.3), (0, 0, 5.65), "Body"), glaze_box],
                              figure=(-8.2, -3.0))


def build_waffle_arch():
    col = hk_collection("WaffleArch")
    width, depth, height = 14.0, 3.2, 11.6
    hole_r, spring = 2.9, 5.2  # the opening: 5.8 wide, round at the top, 8.1 high at its apex
    post = (width / 2 - hole_r)
    waffle_block(col, "PostL", (post, depth, spring), (-(hole_r + post / 2), 0, spring / 2), sides=True)
    waffle_block(col, "PostR", (post, depth, spring), (hole_r + post / 2, 0, spring / 2), sides=True)
    waffle_panel(col, "Upper", (width, depth, height - spring - hole_r), (0, 0, (spring + hole_r + height) / 2))
    # the shoulders round the arch: the band between the springing line and the apex, with the round cut out
    outline = [(-width / 2, spring), (-hole_r, spring)]
    for i in range(17):
        a = math.pi - math.pi * i / 16
        outline.append((hole_r * math.cos(a), spring + hole_r * math.sin(a)))
    outline += [(width / 2, spring), (width / 2, spring + hole_r), (-width / 2, spring + hole_r)]
    prism(col, "Shoulder", "Waffle", outline, -depth / 2, depth / 2)
    # the lattice also on the shoulders beside the round (above it the band stays plain, as round a door frame)
    for side in (-1, 1):
        body, _ = waffle_panel(col, f"ShoulderLattice{side}", (post, depth, hole_r),
                               (side * (hole_r + post / 2), 0, spring + hole_r / 2))
        bpy.data.objects.remove(body, do_unlink=True)
    arc = [[(hole_r * math.cos(math.pi * i / 16), y, spring + hole_r * math.sin(math.pi * i / 16) + 0.05)
            for i in range(17)] for y in (-depth / 2 - 0.05, depth / 2 + 0.05)]
    _tube(col, "ArchTrim", "Gold", arc, 0.42, sides=6)
    glaze_box = iced_block(col, "Top", (width, depth), height + 0.5, drips_seed=13, sprinkle_count=9)
    coll = [box((post, depth, spring), (-(hole_r + post / 2), 0, spring / 2), "PostL"),
            box((post, depth, spring), (hole_r + post / 2, 0, spring / 2), "PostR"),
            box((width, depth, height - spring - hole_r), (0, 0, (spring + hole_r + height) / 2), "Upper"),
            box((post, depth, hole_r), (-(hole_r + post / 2), 0, spring + hole_r / 2), "ShoulderL"),
            box((post, depth, hole_r), (hole_r + post / 2, 0, spring + hole_r / 2), "ShoulderR"),
            glaze_box]
    # inside the shoulders, above the round: steps that stay inside the waffle
    for side in (-1, 1):
        for k in range(3):
            xa, xb = hole_r * k / 3, hole_r * (k + 1) / 3
            z = spring + math.sqrt(max(0.0, hole_r * hole_r - xa * xa))
            if spring + hole_r - z > 0.05:
                coll.append(box((xb - xa, depth, spring + hole_r - z), (side * (xa + xb) / 2, 0,
                                                                        (z + spring + hole_r) / 2), f"Arch{side}{k}"))
    SPECS["WaffleArch"] = dict(collision=coll, figure=(-9.2, -3.2))


def build_giant_cupcake():
    col = hk_collection("GiantCupcake")
    # the paper liner: a ribbed chocolate frustum
    bm = bmesh.new()
    seg, r0, r1, h = 28, 3.5, 4.4, 4.6
    rings = []
    for z, r in ((0.0, r0), (h, r1)):
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            rr = r * (1.0 if i % 2 == 0 else 0.93)
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), z)))
        rings.append(ring)
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[1])
    _object(col, "Liner", bm, "Choco", smooth_angle=20)
    parts, top = soft_serve(col, "Frosting", "Cream", 4.7, h - 0.3, tiers=3, cherry=True)
    frosting = next(p for p in parts if p.name == "Frosting")
    tag(frosting, "Frosting")
    stuck_sprinkles(col, "Sprinkles", [frosting], 16, (h + 0.8, top - 2.2), 7, reach=12.0)
    tiers = [(4.6, h - 0.3, h + 2.6), (3.4, h + 2.6, h + 4.6), (2.4, h + 4.6, top - 1.0)]
    coll = [cyl(3.9, h, name="Liner")] + [cyl(r, b - a, z0=a, name=f"Frosting{k}") for k, (r, a, b) in
                                          enumerate(tiers)]
    SPECS["GiantCupcake"] = dict(collision=coll, figure=(-6.6, -3.4), top=round(top, 2),
                                 variants={"Pink": {"Frosting": "Pink"}, "Mint": {"Frosting": "Mint"}})


def build_macaron_stack():
    col = hk_collection("MacaronStack")
    coll = []
    z = 0.0
    for i, (colour, ox) in enumerate((("Lemon", 0.0), ("SkyBlue", 0.25), ("Pink", -0.15))):
        part = f"Mac{i}"
        blob(col, f"Shell{i}a", colour, 3.5, None, z, z + 1.45, (ox, 0), segments=24, part=part)
        cylinder(col, f"Fill{i}", "Cream", 3.15, 0.75, z + 1.25, (ox, 0), segments=24, bevel=0.3)
        shell = blob(col, f"Shell{i}b", colour, 3.5, None, 0.0, 1.55, (ox, 0), segments=24, part=part)
        _move(shell, (0, 0, z + 1.95))
        coll.append(cyl(3.45, 3.5, (ox, 0), z0=z, name=f"Macaron{i}"))
        z += 3.75
    SPECS["MacaronStack"] = dict(collision=coll, figure=(-5.8, -3.2),
                                 variants={"Lavender": {"Mac1": "Lavender"}, "Mint": {"Mac1": "Mint"}})


def build_cookie_tower():
    col = hk_collection("CookieTower")
    cylinder(col, "Base", "ChocoDark", 3.9, 0.6, 0.0, segments=24, bevel=0.2)
    coll = [cyl(3.9, 0.6, name="Base")]
    thick, z = 1.32, 0.6
    rng = random.Random(5)
    for i in range(8):
        ox, oy = rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3)
        cookie(col, f"Cookie{i}", 3.2, thick, z, (ox, oy), seed=20 + i, chips_top=0, chips_side=3)
        coll.append(cyl(3.15, thick, (ox, oy), z0=z, name=f"Cookie{i}"))
        z += thick
    glaze_top = z
    round_glaze(col, "Top", 3.3, glaze_top + 0.45, thickness=0.5, drips=7, drop=(0.6, 1.4), seed=6)
    disc_sprinkles(col, "Sprinkles", 2.6, glaze_top + 0.45, 9, seed=9)
    coll.append(cyl(3.3, 0.5, z0=glaze_top - 0.05, name="Glaze"))
    SPECS["CookieTower"] = dict(collision=coll, figure=(-5.6, -3.4))


# --------------------------------------------------------------------------------------------------------------------
# platforms


def build_waffle_platform():
    col = hk_collection("WafflePlatform")
    w, d = 16.0, 12.0
    waffle_block(col, "Low", (w, d, 2.8), (0, 0, 1.4))
    waffle_block(col, "High", (w - 0.4, d - 0.4, 2.7), (0, 0, 2.8 + 1.35))
    rounded_box(col, "Band", "Gold", (w - 0.1, d - 0.1, 0.25), (0, 0, 2.8), radius=0.1, segments=1)
    glaze_box = iced_block(col, "Top", (w - 0.4, d - 0.4), PLATFORM_TOP, drips_seed=15, sprinkle_count=10)
    # the caramel ramp in front, 7 wide, its top meeting the glaze
    rw, rl = 7.0, 16.0
    ramp(col, "Ramp", "Caramel", rw, rl, PLATFORM_TOP, (0, -d / 2 - rl / 2 + 0.2), "+y")
    for side in (-1, 1):
        rail = [[(side * (rw / 2 + 0.05), -d / 2 - rl + 0.2, 0.25), (side * (rw / 2 + 0.05), -d / 2 + 0.2,
                                                                      PLATFORM_TOP + 0.25)]]
        _tube(col, f"Rail{side}", "Gold", rail, 0.5, sides=6)
    SPECS["WafflePlatform"] = dict(
        collision=[box((w, d, 2.8), (0, 0, 1.4), "Low"), box((w - 0.4, d - 0.4, 2.65), (0, 0, 4.125), "High"),
                   glaze_box, wedge(rw, rl, PLATFORM_TOP, (0, -d / 2 - rl / 2 + 0.2, PLATFORM_TOP / 2), "+y")],
        figure=(-10.5, -14.0),
    )


def build_cake_platform():
    col = hk_collection("CakePlatform")
    r_low, h_low, r_top = 8.0, 3.4, 5.6
    cylinder(col, "Low", "Sponge", r_low, h_low - 0.4, 0.0, segments=32, bevel=0.3)
    round_glaze(col, "LowGlaze", r_low + 0.15, h_low, thickness=0.55, drips=10, drop=(0.6, 1.3), seed=3)
    cylinder(col, "High", "Sponge", r_top, PLATFORM_TOP - h_low - 0.4, h_low, segments=32, bevel=0.3)
    round_glaze(col, "HighGlaze", r_top + 0.15, PLATFORM_TOP, thickness=0.55, drips=8, drop=(0.6, 1.2), seed=4)
    # strawberries round the lower tier's top, out of the way of the stairs
    for i in range(7):
        a = -math.pi / 2 + 2 * math.pi * (i + 1) / 8
        strawberry(col, f"Berry{i}", ((r_low - 1.0) * math.cos(a), (r_low - 1.0) * math.sin(a), h_low), size=0.9)
    # cream stairs up the front: 8 steps of 0.75, 0.95 deep, 6 wide, to the top tier's edge
    steps, rise, run, sw = 8, PLATFORM_TOP / 8, 0.95, 6.0
    y_end = -r_top + 0.4
    coll = [cyl(r_low, h_low, name="Low"), cyl(r_top + 0.15, PLATFORM_TOP - h_low, z0=h_low, name="High")]
    for k in range(steps):
        top = rise * (k + 1)
        y1 = y_end - (steps - 1 - k) * run
        y0 = y1 - run
        rounded_box(col, f"Step{k}", "Cream", (sw, run, top - 0.03), (0, (y0 + y1) / 2, (top + 0.03) / 2), radius=0.15,
                    segments=1)  # 0.03 off the floor: its bottom never lies on the cake's
        coll.append(box((sw, run, top), (0, (y0 + y1) / 2, top / 2), f"Step{k}"))
    SPECS["CakePlatform"] = dict(collision=coll, figure=(-9.5, -12.0))


# --------------------------------------------------------------------------------------------------------------------
# landmarks


def build_grand_sundae():
    col = hk_collection("GrandSundae")
    coll, top = sundae(col, "", 2.1, wafers=True)
    SPECS["GrandSundae"] = dict(collision=coll, figure=(-12.0, -6.0), top=round(top, 2))


def build_cream_mountain():
    col = hk_collection("CreamMountain")
    cylinder(col, "Base", "Sponge", 12.5, 3.0, 0.0, segments=32, bevel=0.5)
    # the cream peak: a soft dollop of whipped cream, rolls getting smaller towards a curled tip (like a soft serve
    # piped from a bag), its foot overflowing the sponge
    z0, z1, rolls = 2.6, 18.9, 4.5
    profile = [(0.0, z0)]
    steps = 44
    for i in range(steps + 1):
        t = i / steps
        z = z0 + (z1 - z0) * t
        cone = 12.4 * (1 - t) ** 0.9
        roll = 1.1 * (1 - t) * abs(math.sin(math.pi * rolls * t)) ** 0.7
        profile.append((max(0.0, cone + roll), z))
    profile[-1] = (0.0, z1)
    peak = lathe(col, "Peak", "Cream", profile, segments=32, smooth=60)
    drip_skirt(col, "Drips", "Cream", 12.45, 3.0, drips=11, drop=(0.6, 1.6), width=(1.6, 2.6), thickness=0.4, seed=8)
    cherry(col, "Cherry", (0, 0, z1 + 0.6), r=1.4)
    stuck_sprinkles(col, "Sprinkles", [peak], 30, (4.5, 17.0), 13, reach=30.0, size=(1.3, 0.42, 0.32))
    coll = [cyl(12.5, 3.0, name="Base"), cyl(10.5, 4.0, z0=3.0, name="Peak0"), cyl(7.6, 4.0, z0=7.0, name="Peak1"),
            cyl(4.6, 4.5, z0=11.0, name="Peak2"), cyl(2.0, 3.5, z0=15.5, name="Peak3")]
    SPECS["CreamMountain"] = dict(collision=coll, figure=(-15.0, -8.0))


def build_lollipop_tree():
    col = hk_collection("LollipopTree")
    # the mound with candies, the trunk with roots, the spiral lollipop on top
    blob(col, "Mound", "Sponge", 5.5, None, 0.0, 1.4, segments=24)
    for i, (colour, a) in enumerate((("SkyBlue", 0.4), ("Lemon", 2.2), ("Pink", 3.9), ("Mint", 5.2))):
        ball(col, f"Candy{i}", colour, 0.9, (4.6 * math.cos(a), 4.6 * math.sin(a), 0.75), segments=12)
    trunk = [(1.9, 0.6), (1.5, 2.5), (1.25, 6.0), (1.15, 10.0), (1.2, 13.0), (0.0, 13.0)]
    lathe(col, "Trunk", "Choco", [(0, 0.6)] + trunk, segments=16)
    for k in range(5):
        a = 2 * math.pi * k / 5 + 0.3
        root = [[(1.2 * math.cos(a), 1.2 * math.sin(a), 2.2), (3.0 * math.cos(a), 3.0 * math.sin(a), 0.9)]]
        _tube(col, f"Root{k}", "Choco", root, 0.9, sides=6)
    drip_skirt(col, "Glaze", "Cream", 1.5, 13.0, drips=6, drop=(0.5, 1.3), width=(0.6, 1.0), thickness=0.25, seed=2)
    # the lollipop: a thick disc standing upright (facing front), cream with a pink spiral on both faces
    disc_r, disc_t, cz = 6.5, 1.8, 19.0
    disc_n(col, "Disc", "Cream", disc_r, disc_t, (0, 0, cz), (0, -1, 0), segments=32, bevel=0.5)
    for face in (-1, 1):
        pts = []
        for i in range(120):
            t = i / 119
            a = t * 2 * math.pi * 3.2
            r = 0.3 + t * (disc_r - 0.8)
            pts.append((r * math.cos(a), face * (disc_t / 2 + 0.05), cz + r * math.sin(a)))
        tag(_tube(col, f"Spiral{face}", "Pink", [pts], 1.1, sides=6), "Spiral")
    coll = [cyl(5.3, 1.3, name="Mound"), cyl(1.6, 12.0, z0=1.0, name="Trunk")]
    # the disc as stacked boxes inside its round outline
    for k in range(-3, 4):
        z0 = cz + k * 1.85 - 0.925
        z1 = z0 + 1.85
        zf = max(abs(z0 - cz), abs(z1 - cz))
        if zf >= disc_r:
            zf = disc_r - 0.1
        half = math.sqrt(max(0.0, disc_r * disc_r - zf * zf))
        if half > 0.5:
            coll.append(box((2 * half, disc_t, z1 - z0), (0, 0, (z0 + z1) / 2), f"Disc{k + 3}"))
    SPECS["LollipopTree"] = dict(collision=coll, figure=(-9.0, -5.0),
                                 variants={"Blue": {"Spiral": "SkyBlue"}, "Mint": {"Spiral": "Mint"}})


# --------------------------------------------------------------------------------------------------------------------
# special cover (two states each; the game logic comes later)


def _wobble_block(col, name, center, size=(4.4, 4.4, 2.2), turn=0.0, tilt=None):
    parts = waffle_block(col, name, size, (0, 0, 0))
    for ob in parts:
        if tilt:
            _turn(ob, tilt[0], tilt[1])
        _turn(ob, turn)
        _move(ob, center)
    return parts


def build_wobble_tower():
    col = hk_collection("WobbleTower")
    coll = []
    z = 0.0
    for i, (ox, oy, turn) in enumerate(((0, 0, 0), (0.3, -0.2, 0.0), (-0.25, 0.15, 0.0), (0.2, 0.25, 0.0),
                                         (-0.15, -0.2, 0.0))):
        _wobble_block(col, f"Block{i}", (ox, oy, z + 1.1), turn=turn)
        coll.append(box((4.4, 4.4, 2.2), (ox, oy, z + 1.1), f"Block{i}"))
        z += 2.2
    top_box = iced_block(col, "Top", (4.4, 4.4), z + 0.45, drips_seed=17, sprinkle_count=5)
    top_box["center"][0], top_box["center"][1] = -0.15, -0.2
    for ob in col.all_objects:
        if ob.name.startswith("Top_"):
            _move(ob, (-0.15, -0.2, 0))
    coll.append(top_box)
    SPECS["WobbleTower"] = dict(collision=coll, figure=(-5.2, -3.4), state="standing", pair="WobbleTowerFallen")


def build_wobble_tower_fallen():
    col = hk_collection("WobbleTowerFallen")
    # the same five blocks tumbled over: the glazed top one landed upright, one lies on its side, crumbs round them
    layout = [((0, 0, 1.1), 0.0, None), ((-4.6, 0.6, 1.1), 0.5, None), ((4.4, -0.8, 1.1), -0.35, None),
              ((-1.0, 4.6, 1.1), 1.2, None), ((1.8, -4.4, 2.2), 0.0, (math.pi / 2, "Y"))]
    coll = []
    for i, (c, turn, tilt) in enumerate(layout):
        _wobble_block(col, f"Block{i}", c, turn=turn, tilt=tilt)
        if tilt:
            coll.append(box((2.2, 4.4, 4.4), c, f"Block{i}"))  # on its side: tipped round Y
        else:
            # turned blocks: the box that fits inside the turned square
            a = abs(turn) % (math.pi / 2)
            side = 4.4 / (math.cos(a) + math.sin(a)) if a > 1e-3 else 4.4
            coll.append(box((side, side, 2.2), c, f"Block{i}"))
    # the glazed top block came down the right way up
    coll.append(iced_block(col, "Top", (4.4, 4.4), 2.2 + 0.45, drips_seed=17, sprinkle_count=5))
    rng = random.Random(3)
    for i in range(9):
        a, r = rng.uniform(0, 2 * math.pi), rng.uniform(2.5, 7.5)
        rounded_box(col, f"Crumb{i}", "Waffle", (0.7, 0.6, 0.45), (r * math.cos(a), r * math.sin(a), 0.225),
                    radius=0.12, segments=1)
    SPECS["WobbleTowerFallen"] = dict(collision=coll, figure=(-9.0, -6.5), state="fallen", pair="WobbleTower")


def _dispenser(col):
    """The cream dispenser: a chocolate board, a pink and cream striped can, a cream cap and a chocolate nozzle
    pointing forward. Returns the collision and the nozzle's tip."""
    cylinder(col, "Board", "ChocoDark", 2.7, 0.6, 0.0, segments=24, bevel=0.2)
    cylinder(col, "Ring", "Cookie", 2.3, 0.35, 0.6, segments=24, bevel=0.12)
    cylinder(col, "Can", "Cream", 1.55, 4.2, 0.95, segments=20, bevel=0.1)
    lines = []
    for k in range(5):  # candy-cane stripes: one way round only
        a0 = 2 * math.pi * k / 5
        lines.append([(1.6 * math.cos(a0 + 1.4 * i / 10), 1.6 * math.sin(a0 + 1.4 * i / 10), 0.95 + 4.2 * i / 10)
                      for i in range(11)])
    tag(_tube(col, "Stripes", "Pink", lines, 0.75, sides=4), "Stripes")
    cylinder(col, "Cap", "Cream", 1.65, 0.6, 5.15, segments=20, bevel=0.25)
    cylinder(col, "Valve", "ChocoDark", 0.55, 0.7, 5.75, segments=12, bevel=0.15)
    tip = (0.0, -2.4, 6.0)
    _tube(col, "Nozzle", "Choco", [[(0, 0, 6.2), (0, -1.2, 6.45), tip]], 0.55, sides=8)
    _tube(col, "Lever", "Choco", [[(0, 0.2, 6.45), (0, 1.6, 7.1)]], 0.4, sides=6)
    return [cyl(2.7, 0.6, name="Board"), cyl(1.65, 5.15, z0=0.6, name="Can")], tip


def build_cream_dispenser():
    col = hk_collection("CreamDispenser")
    coll, tip = _dispenser(col)
    ball(col, "Drop", "Cream", 0.32, (tip[0], tip[1], tip[2] - 0.3), squash=1.3, segments=10)
    SPECS["CreamDispenser"] = dict(collision=coll, figure=(-4.6, -3.0), state="normal", pair="CreamDispenserSpill",
                                   variants={"Mint": {"Stripes": "Mint"}, "Blue": {"Stripes": "SkyBlue"}})


def build_cream_dispenser_spill():
    col = hk_collection("CreamDispenserSpill")
    coll, tip = _dispenser(col)
    # the cream gushing out and a flat puddle on the floor in front (no collision: you walk through it)
    stream = [[tip, (tip[0] + 0.2, tip[1] - 0.8, tip[2] - 1.6), (tip[0] + 0.4, tip[1] - 1.6, 2.4),
               (tip[0] + 0.5, tip[1] - 2.0, 0.4)]]
    _tube(col, "Stream", "Cream", stream, 0.7, sides=8)
    bm = bmesh.new()
    rng = random.Random(6)
    n = 20
    centre = Vector((0.4, -5.2, 0.02))
    top = []
    bottom = []
    for i in range(n):
        a = 2 * math.pi * i / n
        r = 3.6 * (1 + 0.18 * math.sin(3 * a + 0.7) + rng.uniform(-0.06, 0.06))
        p = centre + Vector((r * math.cos(a), r * 0.8 * math.sin(a), 0))
        bottom.append(bm.verts.new(p))
        top.append(bm.verts.new(p + Vector((0, 0, 0.22))))
    mid = bm.verts.new(centre + Vector((0, 0, 0.3)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
        bm.faces.new((top[i], top[j], mid))
    bm.faces.new(bottom[::-1])
    puddle = _object(col, "Puddle", bm, "Cream", smooth_angle=60)
    _bevel(puddle, 0.08, 1, angle=60)
    SPECS["CreamDispenserSpill"] = dict(collision=coll, figure=(-6.0, -3.0), state="spill", pair="CreamDispenser",
                                        puddle=dict(center=[0.4, -5.2], radius=3.6),
                                        variants={"Mint": {"Stripes": "Mint"}, "Blue": {"Stripes": "SkyBlue"}})


def _gummy_bear(col, z0, squash=1.0, spread=1.0):
    """A sitting gummy bear on the pad (one Gummy part): squash < 1 presses it flat and spread widens it."""
    def at(x, y, z):
        return (x * spread, y * spread, z0 + z * squash)

    blob(col, "Belly", "Gummy", 1.7 * spread, None, z0, z0 + 2.9 * squash, segments=18, part="Bear")
    ball(col, "Head", "Gummy", 1.35, at(0, -0.1, 3.5), segments=16, scale=(spread, spread, squash), )
    for side in (-1, 1):
        ball(col, f"Ear{side}", "Gummy", 0.5, at(side * 0.95, -0.05, 4.65), segments=10,
             scale=(spread, 0.7 * spread, squash))
        ball(col, f"Arm{side}", "Gummy", 0.6, at(side * 1.55, -0.5, 1.9), segments=10,
             scale=(0.8 * spread, 0.9 * spread, 1.3 * squash))
        ball(col, f"Leg{side}", "Gummy", 0.7, at(side * 0.9, -1.2, 0.55), segments=10,
             scale=(spread, 1.3 * spread, 0.8 * squash))
        ball(col, f"Eye{side}", "ChocoDark", 0.16, at(side * 0.45, -1.25, 3.75), segments=8,
             scale=(1, 0.6, squash))
    ball(col, "Snout", "Gummy", 0.55, at(0, -1.25, 3.25), segments=10, scale=(spread, 0.7 * spread, 0.75 * squash))
    for ob in col.all_objects:
        if ob.data.materials and ob.data.materials[0].name == "WS_Gummy":
            tag(ob, "Bear")


def build_gummy_pad():
    col = hk_collection("GummyPad")
    cylinder(col, "Board", "ChocoDark", 3.9, 0.6, 0.0, segments=28, bevel=0.2)
    cylinder(col, "Pad", "Pink", 3.3, 0.55, 0.6, segments=28, bevel=0.22)
    _gummy_bear(col, 1.15)
    SPECS["GummyPad"] = dict(
        collision=[cyl(3.9, 0.6, name="Board"), cyl(3.3, 0.55, z0=0.6, name="Pad"),
                   cyl(1.6, 2.6, (0, -0.2), z0=1.15, name="Bear"), cyl(1.2, 2.0, (0, -0.1), z0=3.75, name="Head")],
        figure=(-6.0, -3.0), state="normal", pair="GummyPadPressed",
        variants={"Mint": {"Bear": "Mint"}, "Lemon": {"Bear": "Lemon"}},
    )


def build_gummy_pad_pressed():
    col = hk_collection("GummyPadPressed")
    cylinder(col, "Board", "ChocoDark", 3.9, 0.6, 0.0, segments=28, bevel=0.2)
    cylinder(col, "Pad", "Pink", 3.45, 0.3, 0.6, segments=28, bevel=0.12)
    _gummy_bear(col, 0.9, squash=0.5, spread=1.25)
    SPECS["GummyPadPressed"] = dict(
        collision=[cyl(3.9, 0.6, name="Board"), cyl(3.45, 0.3, z0=0.6, name="Pad"),
                   cyl(2.0, 1.4, (0, -0.25), z0=0.9, name="Bear"), cyl(1.5, 1.0, (0, -0.1), z0=2.3, name="Head")],
        figure=(-6.0, -3.0), state="pressed", pair="GummyPad",
        variants={"Mint": {"Bear": "Mint"}, "Lemon": {"Bear": "Lemon"}},
    )


def _gummy_cushion(col, top, r, ears_z):
    """The small bouncer's cushion: a flat gummy bear head lying face up (one Gummy part), its top at `top`."""
    blob(col, "Cushion", "Gummy", r, None, 0.45, top, segments=24, part="Bear")
    for side in (-1, 1):
        ball(col, f"Ear{side}", "Gummy", 0.55, (side * r * 0.62, r * 0.55, ears_z), segments=10, scale=(1, 0.8, 0.6))
        ball(col, f"Eye{side}", "ChocoDark", 0.17, (side * 0.6, -0.55, top - 0.08), segments=8, scale=(1, 1, 0.5))
    ball(col, "Snout", "Gummy", 0.5, (0, -1.05, top - 0.22), segments=10, scale=(1.1, 0.8, 0.55))
    ball(col, "Nose", "ChocoDark", 0.16, (0, -1.15, top + 0.02), segments=8, scale=(1.2, 0.8, 0.6))
    for ob in col.all_objects:
        if ob.data.materials and ob.data.materials[0].name == "WS_Gummy":
            tag(ob, "Bear")


def build_gummy_bouncer():
    # the small bouncer (16.11.2026): like the GummyPad but small and flat, for a little hop onto a medium cover or
    # over a low wall. Walkable: its top is lower than a step.
    col = hk_collection("GummyBouncer")
    cylinder(col, "Board", "ChocoDark", 2.9, 0.45, 0.0, segments=24, bevel=0.15)
    _gummy_cushion(col, 1.35, 2.35, 1.05)
    SPECS["GummyBouncer"] = dict(
        collision=[cyl(2.9, 0.45, name="Board"), cyl(2.3, 0.85, z0=0.45, name="Cushion")],
        figure=(-4.6, -3.0), state="normal", pair="GummyBouncerPressed",
        variants={"Mint": {"Bear": "Mint"}, "Lemon": {"Bear": "Lemon"}},
    )


def build_gummy_bouncer_pressed():
    col = hk_collection("GummyBouncerPressed")
    cylinder(col, "Board", "ChocoDark", 2.9, 0.45, 0.0, segments=24, bevel=0.15)
    _gummy_cushion(col, 0.85, 2.6, 0.75)
    SPECS["GummyBouncerPressed"] = dict(
        collision=[cyl(2.9, 0.45, name="Board"), cyl(2.55, 0.35, z0=0.45, name="Cushion")],
        figure=(-4.6, -3.0), state="pressed", pair="GummyBouncer",
        variants={"Mint": {"Bear": "Mint"}, "Lemon": {"Bear": "Lemon"}},
    )


def build_waffle_wall():
    # the waffle arch closed (16.11.2026): a high wall with no opening, real cover like the ChocoWall
    col = hk_collection("WaffleWall")
    width, depth, height = 14.0, 3.2, 11.6
    waffle_block(col, "Body", (width, depth, height), (0, 0, height / 2), sides=True)
    glaze_box = iced_block(col, "Top", (width, depth), height + 0.5, drips_seed=13, sprinkle_count=9)
    SPECS["WaffleWall"] = dict(collision=[box((width, depth, height), (0, 0, height / 2), "Body"), glaze_box],
                               figure=(-9.2, -3.2))


BUILDERS = {
    "WaffleCrates": build_waffle_crates,
    "FallenCone": build_fallen_cone,
    "CookieStack": build_cookie_stack,
    "ChocoBar": build_choco_bar,
    "CandyBox": build_candy_box,
    "SundaeCup": build_sundae_cup,
    "ChocoWall": build_choco_wall,
    "WaffleArch": build_waffle_arch,
    "GiantCupcake": build_giant_cupcake,
    "MacaronStack": build_macaron_stack,
    "CookieTower": build_cookie_tower,
    "WafflePlatform": build_waffle_platform,
    "CakePlatform": build_cake_platform,
    "GrandSundae": build_grand_sundae,
    "CreamMountain": build_cream_mountain,
    "LollipopTree": build_lollipop_tree,
    "WobbleTower": build_wobble_tower,
    "WobbleTowerFallen": build_wobble_tower_fallen,
    "CreamDispenser": build_cream_dispenser,
    "CreamDispenserSpill": build_cream_dispenser_spill,
    "GummyPad": build_gummy_pad,
    "GummyPadPressed": build_gummy_pad_pressed,
    "GummyBouncer": build_gummy_bouncer,
    "GummyBouncerPressed": build_gummy_bouncer_pressed,
    "WaffleWall": build_waffle_wall,
}

for _name in PACK or list(BUILDERS):
    BUILDERS[_name]()
    finish(_name)
write_studio_script()
