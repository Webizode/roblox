"""The other 47 tower scoops after the approved prototype 2 (build_proto.py, approved 18.11.2026): the same forms,
toppings as real parts, baked maps. Each flavor is a recipe in RECIPES: its form, its seed, the ice (colour, gloss,
flecks) and its toppings, made from the building blocks below (and those of build_proto.py).

Run inside Blender:
    ASSET_DIR = r"<repo>/assets/TowerScoops"
    exec(open(ASSET_DIR + "/build_rollout.py").read())   # execs build_proto.py too
    for fid in ROLLOUT[:6]: build(fid)                    # a few per call: one flavor bakes in about 25 s

The rarer, the richer (so the rarity shows in the look too, not only in the beacon and the trail):
- common: the ice and one kind of topping
- uncommon: a fruit or a sauce as the topping
- rare: a sauce strand plus toppings
- epic: a glaze cap or whipped cream, toppings, more gloss
- legendary: all of that plus gold and crystals

LOD0 maps are 512 (the 5 prototypes keep 1024): with 52 flavors the texture memory counts, and a scoop is 2 studs.
"""

import math
import os
import random

exec(open(os.path.join(ASSET_DIR, "build_proto.py")).read())

TEX["LOD0"] = 512

# ------------------------------------------------------------------------------------------- building blocks


def mats(spec):
    """A material from (colour, roughness[, extra]) or a material."""
    if isinstance(spec, bpy.types.Material):
        return spec
    colour, rough = spec[0], spec[1]
    extra = spec[2] if len(spec) > 2 else {}
    name = "R_" + "_".join(str(x) for x in (colour, rough, sorted(extra.items())))
    # one material per look, shared: material() would replace an existing one and strip it from earlier parts
    return bpy.data.materials.get(name) or material(name, colour, rough, **extra)


GLOSS = {"clearcoat": 1.0}

# the toppings' size against the recipes' numbers: the first rollout (18.11.2026) came out far smaller than in the
# reference pictures
S = 1.6


def glaze_cap(name, surf, mat, base=40, wave=8, lobes=7, drips=(), thick=0.06, phase=0.0):
    """A glaze over the top of the scoop (honey, icing, chocolate): a shell on the surface from the edge elev(theta) up
    to the top, thickest inside and thinning to nothing at its wavy edge, with tongues running down at `drips`
    [(theta degrees, length degrees)]. Open below: it lies on the ice."""
    around, rows = 72, 9
    bm = bmesh.new()
    grid = []
    for s in range(around):
        theta = 360 * s / around
        edge = base - wave * 0.5 * (1 + math.cos(math.radians(theta) * lobes + phase))
        for t, length in drips:
            delta = (theta - t + 180) % 360 - 180
            # a round tongue: wide, with a round end, not a V
            x = abs(delta) / 13
            edge -= length * (math.sqrt(max(0.0, 1 - x * x)) if x < 1 else 0.0)
        col = []
        for r in range(rows):
            k = r / (rows - 1)
            elev = edge + (86 - edge) * (k ** 0.8)
            p, n = surf.at(theta, elev)
            lip = min(1.0, k * 4) ** 0.6
            col.append(bm.verts.new(p + n * (0.005 + thick * lip)))
        grid.append(col)
    top_p, top_n = surf.at(0, 90)
    top = bm.verts.new(top_p + top_n * (0.005 + thick))
    for s in range(around):
        a, b = grid[s], grid[(s + 1) % around]
        for r in range(rows - 1):
            bm.faces.new((a[r], b[r], b[r + 1], a[r + 1]))
        bm.faces.new((a[-1], b[-1], top))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj_from_bm(name, bm, mat)


def blobs(name, parts, mat, seg=12, rings=8):
    """Several squashed spheres in one object: [(centre, radius, scale Vector, rotation Matrix or None)]."""
    bm = bmesh.new()
    for centre, radius, scale, rot in parts:
        sub = bmesh.new()
        bmesh.ops.create_uvsphere(sub, u_segments=seg, v_segments=rings, radius=radius)
        for v in sub.verts:
            v.co = Vector((v.co.x * scale.x, v.co.y * scale.y, v.co.z * scale.z))
        m = Matrix.Translation(centre) @ (rot or Matrix.Identity(4))
        bmesh.ops.transform(sub, matrix=m, verts=sub.verts)
        mesh = bpy.data.meshes.new("tmp")
        sub.to_mesh(mesh)
        sub.free()
        bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
    return obj_from_bm(name, bm, mat)


def berries(name, surf, spots, radius, mat, sink=0.35, dimple=0.0):
    """Round fruit half sunk in (blueberries, grapes, arils, gum balls, melon balls): spots [(theta, elev)]."""
    out = []
    radius *= S
    for k, (theta, elev) in enumerate(spots):
        p, n = surf.at(theta, elev)
        r = radius * (0.9 + 0.2 * ((k * 37) % 10) / 10)
        out.append(sphere(f"{name}{k}", p + n * r * (1 - 2 * sink), r, mat, dimple=dimple, seg=14, rings=9,
                          frame_m=frame((n + Vector((0, 0, 1))).normalized())))
    return out


def drupes(name, surf, spots, radius, mat):
    """Raspberries and blackberries: a round cluster of little drupelets, half sunk in."""
    out = []
    radius *= S
    for k, (theta, elev) in enumerate(spots):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=3, radius=radius)
        seeds = [Vector(v) for v in bmesh_icosphere_points(1)]
        for v in bm.verts:
            d = min((v.co.normalized() - s).length for s in seeds)
            v.co *= 1 + 0.16 * max(0.0, 1 - d / 0.42) ** 2
            v.co.z *= 1.15
        p, n = surf.at(theta, elev)
        m = Matrix.Translation(p + n * radius * 0.35) @ frame(n, k)
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        out.append(obj_from_bm(f"{name}{k}", bm, mat))
    return out


def bmesh_icosphere_points(sub):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    pts = [v.co.copy().normalized() for v in bm.verts]
    bm.free()
    return pts


def slices(name, surf, spots, radius, flesh, peel, thick=0.07, half=True, lean=0.25):
    """Fruit slices (citrus, peach, melon, coconut, kiwi) stuck in edgewise, a third sunk: spots [(theta, elev)]."""
    out = []
    radius *= S / 1.25
    thick *= 1.3
    for k, (theta, elev) in enumerate(spots):
        p, n = surf.at(theta, elev)
        side = n.cross(Vector((0, 0, 1))).normalized()
        axis = (n * math.cos(lean) + side * math.sin(lean)).normalized()
        out.append(disc(f"{name}{k}", p - n * radius * 0.25, axis, radius, thick, flesh, half=half, rim=peel,
                        spin=k * 1.9))
    return out


def cubes(name, surf, spots, size, mat, sink=0.45, seed=0):
    """Rounded cubes (mango, caramel, brownie, cake, honeycomb-ish), tilted, half sunk."""
    rng = random.Random(seed)
    size *= S
    out = []
    for k, (theta, elev) in enumerate(spots):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=size * rng.uniform(0.85, 1.15))
        bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=size * 0.18, segments=2, affect="EDGES")
        p, n = surf.at(theta, elev)
        m = Matrix.Translation(p - n * size * (sink - 0.5)) @ frame(n, rng.uniform(0, 6.28))
        m = m @ Matrix.Rotation(rng.uniform(-0.4, 0.4), 4, "X") @ Matrix.Rotation(rng.uniform(-0.4, 0.4), 4, "Y")
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        out.append(obj_from_bm(f"{name}{k}", bm, mat, smooth=True))
    return out


def chunks_at(name, surf, spots, size, mat, sharp=True, flat=0.7, seed=0):
    size *= S
    return [chunk(f"{name}{k}", surf, t, e, size * (0.85 + 0.3 * ((k * 53) % 10) / 10), mat, seed=seed + k, sink=0.5,
                  flat=flat, sharp=sharp) for k, (t, e) in enumerate(spots)]


def sprinkles(name, surf, count, colours, seed=0, emin=-5, emax=60):
    """Little sugar strands lying on the ice in several colours (one object per colour)."""
    rng = random.Random(seed)
    groups = {c: [] for c in colours}
    for k in range(count):
        groups[colours[k % len(colours)]].append((rng.uniform(0, 360), rng.uniform(emin, emax), rng.uniform(0, 6.28)))
    out = []
    for c, items in groups.items():
        bm = bmesh.new()
        for theta, elev, turn in items:
            p, n = surf.at(theta, elev)
            side = n.cross(Vector((0, 0, 1))).normalized()
            up = side.cross(n).normalized()
            d = side * math.cos(turn) + up * math.sin(turn)
            sub = tube("tmp", [p + n * 0.025 - d * 0.085, p + n * 0.025 + d * 0.085], 0.036, mats((c, 0.4)), sides=6, taper=0.3)
            bm.from_mesh(sub.data)
            bpy.data.meshes.remove(sub.data)
        out.append(obj_from_bm(f"{name}_{c}", bm, mats((c, 0.4))))
    return out


def beans(name, surf, spots, mat, size=0.11):
    """Coffee beans: squashed ovals with the groove, lying on the ice."""
    out = []
    size *= S
    for k, (theta, elev) in enumerate(spots):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=size)
        for v in bm.verts:
            v.co = Vector((v.co.x * 1.0, v.co.y * 0.72, v.co.z * 0.5))
            if v.co.z > 0 and abs(v.co.y) < size * 0.18:
                v.co.z -= size * 0.18
        p, n = surf.at(theta, elev)
        m = Matrix.Translation(p + n * size * 0.15) @ frame(n, k * 1.3)
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        out.append(obj_from_bm(f"{name}{k}", bm, mat))
    return out


def flowers(name, surf, spots, petal, centre, size=0.16):
    """Small five-petal blossoms lying on the ice."""
    out = []
    size *= S
    for k, (theta, elev) in enumerate(spots):
        p, n = surf.at(theta, elev)
        f = frame(n, k * 0.7)
        parts = []
        for i in range(5):
            a = 2 * math.pi * i / 5
            off = f @ Vector((math.cos(a) * size * 0.55, math.sin(a) * size * 0.55, 0.02))
            rot = f @ Matrix.Rotation(a, 4, "Z")
            parts.append((p + off, size * 0.5, Vector((1.0, 0.62, 0.22)), rot))
        out.append(blobs(f"{name}{k}", parts, petal, seg=10, rings=6))
        out.append(sphere(f"{name}{k}_mid", p + n * 0.03, size * 0.22, centre, seg=10, rings=6))
    return out


def stick(name, surf, a, b, radius, mat, lift=0.6):
    """A stick or biscuit lying on the ice from (theta, elev) a to b (cinnamon stick, ladyfinger, vanilla pod)."""
    pts = []
    for s in range(6):
        t = s / 5
        p, n = surf.at(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        pts.append(p + n * radius * lift)
    return tube(name, pts, radius, mat, sides=10, taper=0.2)


def curl(name, surf, theta, elev, radius, mat, turns=2.2, size=0.16):
    """A rolled curl lying on the ice (a cinnamon roll, a chocolate curl): a flat spiral tube."""
    p, n = surf.at(theta, elev)
    side = n.cross(Vector((0, 0, 1))).normalized()
    up = side.cross(n).normalized()
    pts = []
    for s in range(28):
        t = s / 27
        a = t * turns * 2 * math.pi
        r = size * (0.15 + 0.85 * t)
        pts.append(p + n * (radius * 0.8) + (side * math.cos(a) + up * math.sin(a)) * r)
    return tube(name, pts, radius, mat, sides=8, taper=0.06, flat=1.0)


def cherry_pair(name, surf, theta, elev, fruit, stem_m, leaf_m=None, radius=0.2):
    out = []
    p1, n1 = surf.at(theta - 13, elev + 4)
    p2, n2 = surf.at(theta + 13, elev - 2)
    c1, c2 = p1 + n1 * radius * 0.55, p2 + n2 * radius * 0.5
    out.append((sphere(f"{name}_a", c1, radius, fruit, dimple=0.35, frame_m=frame((n1 + Vector((0, 0, 1.6))).normalized())), 1.3, True))
    out.append((sphere(f"{name}_b", c2, radius * 0.95, fruit, dimple=0.35, frame_m=frame((n2 + Vector((0, 0, 1.6))).normalized())), 1.3, True))
    top, tn = surf.at(theta, elev + 22)
    joint = top + tn * 0.16
    for k, c in enumerate((c1, c2)):
        start = c + Vector((0, 0, radius))
        mid = start.lerp(joint, 0.5) + Vector((0, 0, 0.06))
        out.append((tube(f"{name}_stem{k}", [start, mid, joint], 0.026, stem_m, sides=6, taper=0.05), 0.3, k == 0))
    if leaf_m:
        out.append((leaf(f"{name}_leaf", joint, Vector((-0.8, -0.3, 0.15)), 0.36, 0.11, leaf_m), 0.35, False))
    return out


# sauce paths, (theta, elev) round the scoop; ROT turns one round
# all of them cross the front (theta 0) at the height a tower still shows (under the scoop above, elev below ~38)
PATHS = {
    "diag": [(-110, 8), (-70, 14), (-30, 22), (10, 30), (50, 34), (90, 30), (130, 22)],
    "low": [(-100, 2), (-60, 8), (-20, 12), (20, 10), (60, 6), (100, 2)],
    "rise": [(-90, -6), (-55, 4), (-20, 16), (15, 28), (50, 36), (85, 40), (120, 42)],
    "wave": [(-90, 14), (-45, 26), (0, 14), (45, 26), (90, 14), (135, 26), (180, 14)],
}


def path(kind, rot=0):
    # the recipes' turns, damped: the strand stays on the front, two strands still part
    return [((t + rot * 0.3) % 360, e) for t, e in PATHS[kind]]


# ------------------------------------------------------------------------------------------------ the recipes
# A recipe: form, seed, body = (colour, roughness, flecks or None), parts = a function surf -> [(object, weight, LOD1)].


def W(objs, weight=1.0, keep_first=True, keep_all=False):
    """Weights for a list of parts: the first (the biggest) stays on LOD1."""
    if not isinstance(objs, list):
        objs = [objs]
    return [(o, weight if i == 0 else weight * 0.5, keep_all or (keep_first and i == 0)) for i, o in enumerate(objs)]


def sauce_parts(name, surf, kind, colour, width=0.1, rot=0, drips=((2, 26),), gloss=True):
    m = mats((colour, 0.12, GLOSS if gloss else {}))
    s = sauce(name, surf, path(kind, rot), width * 1.25, m, drips=drips)
    return [(x, 1.2 if i == 0 else 0.35, i == 0) for i, x in enumerate(s)]


GOLD = ("#F7BE2E", 0.2, GLOSS)


def gems_at(name, surf, spots, colour, size=0.12):
    size *= 1.3
    m = mats((colour, 0.08, GLOSS))
    out = []
    for k, (theta, elev) in enumerate(spots):
        p, n = surf.at(theta, elev)
        out.append((gem(f"{name}{k}", p, n, size, m, spin=k * 1.3), 0.45, False))
    return out


RECIPES = {
    # ---------------------------------------------------------------------------------------------- common
    "chocolate": ("smooth", 61, ("#6A3F2A", 0.35, None), lambda s: (
        sauce_parts("choc_s", s, "diag", "#3A1F12", rot=30)
        + W(chunks_at("choc_c", s, [(-20, 10), (100, 20), (220, 6), (300, 28)], 0.14, mats(("#4A2817", 0.5))), 0.5))),
    "strawberry": ("swirl", 62, ("#FF8FA3", 0.5, ("#D9344A", 7, 0.08)), lambda s: (
        W(blobs("straw_b", [(s.at(-15, 14)[0] + s.at(-15, 14)[1] * 0.06, 0.2, Vector((0.85, 0.85, 1.1)), frame(s.at(-15, 14)[1]))],
                mats(("#D9203A", 0.25, {"specks": ("#FFE27A", 14, 0.08), "clearcoat": 0.6})), seg=16, rings=10), 1.2)
        + W(chunks_at("straw_c", s, [(70, 26), (160, 8), (250, 30), (320, 4)], 0.1, mats(("#C8203A", 0.3, GLOSS))), 0.4))),
    "mint": ("ridged", 63, ("#9DE0C4", 0.6, None), lambda s: (
        W(chunks_at("mint_chip", s, [(t, e) for t, e in ((-30, 10), (20, 34), (70, 4), (120, 26), (170, 12),
                                                          (220, 36), (270, 8), (320, 24))], 0.075, mats(("#3B2416", 0.4))), 0.3)
        + [(leaf("mint_leaf", s.at(0, 30)[0] + s.at(0, 30)[1] * 0.02, Vector((0.6, -0.8, 0.1)), 0.38, 0.14,
                 mats(("#3FA34A", 0.4))), 0.6, True)])),
    "lemon": ("smooth", 64, ("#FFD84A", 0.55, ("#F0B020", 9, 0.05)), lambda s: (
        W(slices("lemon_sl", s, [(-10, 16)], 0.3, mats(("#FFEB7A", 0.3, {"specks": ("#FFF8DC", 9, 0.12)})),
                 mats(("#F7C81C", 0.4))), 1.6, keep_all=True)
        + W([stick(f"lemon_zest{k}", s, (t, e), (t + 14, e + 6), 0.022, mats(("#E8A817", 0.5))) for k, (t, e) in
             enumerate(((80, 10), (160, 28), (240, 14), (300, 34)))], 0.3))),
    "bubblegum": ("smooth", 65, ("#FF8AD8", 0.45, None), lambda s: sum(
        (W(berries(f"gum{k}", s, [spot], 0.13, mats((c, 0.2, GLOSS)), sink=0.4), 0.5, keep_first=k < 2) for k, (spot, c) in
         enumerate((((-20, 14), "#4FB6F0"), ((60, 30), "#FFE34D"), ((130, 8), "#8FD14F"), ((200, 26), "#8A6CFF"),
                    ((280, 10), "#FFFFFF"), ((330, 38), "#4FB6F0")))), [])),
    "pistachio": ("lumpy", 66, ("#B9D98C", 0.75, ("#6E9638", 8, 0.08)), lambda s: (
        W(chunks_at("pist_n", s, [(-20, 12), (50, 30), (120, 6), (190, 24), (260, 10), (320, 34)], 0.12,
                    mats(("#7FA83C", 0.6, {"specks": ("#E4F2C2", 10, 0.2)})), sharp=False, flat=0.6), 0.5))),
    "mango": ("smooth", 67, ("#FFA53D", 0.45, None), lambda s: (
        W(cubes("mango_c", s, [(-15, 12), (60, 28), (140, 8), (220, 26), (300, 12)], 0.17,
                mats(("#E8770F", 0.25, GLOSS)), seed=67), 0.6))),
    "stracciatella": ("ridged", 68, ("#FFF6E8", 0.6, ("#3B2416", 10, 0.05)), lambda s: (
        sauce_parts("strac_s", s, "wave", "#3B2416", width=0.05, rot=10, drips=())
        + W(chunks_at("strac_c", s, [(40, 16), (150, 30), (250, 10), (320, 22)], 0.12, mats(("#2E1B10", 0.4)), flat=0.3), 0.4))),
    "watermelon": ("smooth", 69, ("#F2545B", 0.5, ("#2B2D42", 10, 0.06)), lambda s: (
        W(slices("wm_sl", s, [(-10, 14)], 0.36, mats(("#F2545B", 0.35, {"specks": ("#2B2D42", 12, 0.08)})),
                 mats(("#4FAE45", 0.45))), 1.6, keep_all=True)
        + W(berries("wm_seed", s, [(70, 20), (150, 8), (230, 28), (300, 14)], 0.05, mats(("#2B2D42", 0.3)), sink=0.5), 0.2))),
    # ---------------------------------------------------------------------------------------------- uncommon
    "blueberry": ("swirl", 71, ("#8E92EE", 0.5, ("#3B3F9E", 8, 0.06)), lambda s: (
        sauce_parts("blue_s", s, "diag", "#4A4FC2", rot=60)
        + W(berries("blue_b", s, [(-25, 12), (-5, 6), (-15, 26), (150, 14)], 0.13, mats(("#2E2F7A", 0.35, {"specks": ("#9EA6FF", 16, 0.1)})),
                    dimple=0.3), 0.9, keep_all=False))),
    "raspberry": ("lumpy", 72, ("#E8557E", 0.5, ("#B8264E", 8, 0.07)), lambda s: (
        W(drupes("rasp_d", s, [(-15, 14), (100, 26), (220, 10)], 0.16, mats(("#C2185B", 0.35, GLOSS))), 1.0))),
    "peach": ("smooth", 73, ("#FFBE8A", 0.5, ("#F59A4A", 8, 0.08)), lambda s: (
        W(slices("peach_sl", s, [(-10, 14), (150, 20)], 0.3, mats(("#FFC36A", 0.3, GLOSS)), mats(("#E8502A", 0.4)),
                 thick=0.1), 1.3)
        + W(cubes("peach_c", s, [(70, 30), (260, 10)], 0.12, mats(("#FFB04A", 0.3, GLOSS)), seed=73), 0.4))),
    "grape": ("swirl", 74, ("#A65BE0", 0.5, ("#7B3CC0", 8, 0.07)), lambda s: (
        W(berries("grape_a", s, [(-24, 12), (-10, 20), (-2, 8), (-16, 2)], 0.12, mats(("#5A1E9C", 0.2, GLOSS))), 0.8)
        + W(berries("grape_b", s, [(160, 18), (174, 26), (180, 12)], 0.11, mats(("#5A1E9C", 0.2, GLOSS))), 0.5)
        + [(stick("grape_stem", s, (-14, 26), (-6, 34), 0.02, mats(("#6E5A2A", 0.6))), 0.2, False)])),
    "coconut": ("lumpy", 75, ("#F3E6D6", 0.7, ("#FFFFFF", 9, 0.12)), lambda s: (
        W(slices("coco_sl", s, [(-10, 12)], 0.32, mats(("#FFFFFF", 0.6)), mats(("#5A3820", 0.8)), thick=0.1), 1.5, keep_all=True)
        + W(chunks_at("coco_f", s, [(60, 26), (130, 8), (200, 30), (270, 14), (330, 36)], 0.09, mats(("#FFFFFF", 0.6)), flat=0.3), 0.3))),
    "pineapple": ("ridged", 76, ("#FFEAA0", 0.55, None), lambda s: (
        W(cubes("pine_c", s, [(-20, 10), (40, 28), (110, 6), (180, 24), (250, 8), (310, 30)], 0.16,
                mats(("#F5B01E", 0.3, {"specks": ("#FFE36A", 9, 0.2), "clearcoat": 0.5})), seed=76), 0.6))),
    "orange": ("smooth", 77, ("#FF7F30", 0.5, ("#D9531A", 9, 0.06)), lambda s: (
        W(slices("or_sl", s, [(-10, 14)], 0.32, mats(("#FFB347", 0.3, {"specks": ("#FFF0D8", 8, 0.14)})), mats(("#F05A0A", 0.4))),
          1.5, keep_all=True)
        + sauce_parts("or_s", s, "low", "#FFD7A3", rot=40, gloss=False))),
    "lime": ("swirl", 78, ("#A9DE3E", 0.5, ("#5FA82A", 9, 0.06)), lambda s: (
        W(slices("lime_sl", s, [(-10, 14)], 0.3, mats(("#D8F28A", 0.3, {"specks": ("#F2FFD8", 8, 0.14)})), mats(("#3E8E1E", 0.4))),
          1.5, keep_all=True)
        + sauce_parts("lime_s", s, "diag", "#4C9A22", rot=80))),
    "caramel": ("smooth", 79, ("#E8933C", 0.35, None), lambda s: (
        sauce_parts("car_s", s, "diag", "#A85316", width=0.11, rot=20)
        + W(cubes("car_c", s, [(-15, 10), (120, 22), (240, 8), (300, 30)], 0.15, mats(("#C9762A", 0.2, GLOSS)), seed=79), 0.5))),
    "blue_raspberry": ("swirl", 80, ("#33B5F2", 0.45, None), lambda s: (
        sauce_parts("brasp_s", s, "diag", "#1D4FC8", rot=50)
        + W(drupes("brasp_d", s, [(-15, 14), (170, 20)], 0.15, mats(("#1E3FA8", 0.35, GLOSS))), 1.0))),
    # ---------------------------------------------------------------------------------------------- rare
    "cotton_candy": ("swirl", 81, ("#96D6FF", 0.6, None), lambda s: (
        [(chunk("cc_puff", s, 0, 75, 0.38, mats(("#FF86CF", 0.8)), seed=81, sink=0.4, flat=0.75), 1.4, True)]
        + sauce_parts("ccandy_s", s, "low", "#FF86CF", rot=10, gloss=False)
        + W(sprinkles("ccandy_sp", s, 12, ["#B57BFF", "#FFFFFF", "#FF5FB0"], seed=81), 0.3, keep_first=False))),
    "red_velvet": ("smooth", 82, ("#B0243E", 0.5, ("#FFE2D2", 9, 0.05)), lambda s: (
        [(dollop("rv_whip", s.at(0, 90)[0] - Vector((0, 0, 0.04)), 0.46, 0.38, mats(("#FFF4EC", 0.55))), 1.4, True)]
        + sauce_parts("rv_s", s, "low", "#FFF0E4", rot=30, gloss=False)
        + W(cubes("rv_c", s, [(-15, 12), (130, 20), (250, 8)], 0.15, mats(("#7E1630", 0.7, {"specks": ("#3D0A1F", 9, 0.12)})), seed=82), 0.5))),
    "birthday_cake": ("ridged", 83, ("#FFF3DE", 0.55, None), lambda s: (
        sauce_parts("bday_s", s, "wave", "#FF6FB5", rot=0, drips=((1, 22), (4, 24)), gloss=False)
        + W(sprinkles("bday_sp", s, 22, ["#FF4F7B", "#FFC83D", "#3EC1F0", "#6BD66B", "#B57BFF"], seed=83), 0.3, keep_first=False)
        + W(cubes("bday_c", s, [(-15, 8), (200, 24)], 0.15, mats(("#FFE08A", 0.7)), seed=83), 0.5))),
    "brownie": ("lumpy", 84, ("#A3744E", 0.5, None), lambda s: (
        sauce_parts("brow_s", s, "diag", "#4A2817", width=0.11, rot=70)
        + W(cubes("brow_c", s, [(-15, 12), (60, 30), (150, 6), (250, 22)], 0.18,
                  mats(("#3C2214", 0.6, {"specks": ("#6A4028", 8, 0.15)})), seed=84), 0.7))),
    "coffee": ("ridged", 85, ("#D6B089", 0.55, ("#8A5A34", 9, 0.05)), lambda s: (
        sauce_parts("cof_s", s, "diag", "#5A3520", rot=40)
        + W(beans("cof_b", s, [(-20, 12), (0, 22), (90, 8), (180, 18), (270, 6)], mats(("#4E2C16", 0.3, GLOSS))), 0.4))),
    "dragon_fruit": ("smooth", 86, ("#E62E9E", 0.45, ("#1A1A1A", 12, 0.05)), lambda s: (
        W(slices("drag_sl", s, [(-10, 14)], 0.32, mats(("#FFF5FA", 0.4, {"specks": ("#1A1A1A", 14, 0.1)})),
                 mats(("#E62E9E", 0.35)), thick=0.09), 1.5, keep_all=True)
        + W(cubes("drag_c", s, [(90, 24), (200, 8), (290, 30)], 0.14, mats(("#FFF5FA", 0.4, {"specks": ("#1A1A1A", 14, 0.1)})), seed=86), 0.5)
        + sauce_parts("drag_s", s, "low", "#B0126E", width=0.08, rot=120))),
    "pomegranate": ("lumpy", 87, ("#E86F90", 0.45, None), lambda s: (
        sauce_parts("pom_s", s, "diag", "#A3122E", width=0.09, rot=100)
        + W(berries("pom_a", s, [(t, e) for t, e in ((-30, 8), (-15, 16), (-5, 6), (20, 26), (60, 12), (110, 30),
                                                        (160, 10), (210, 24), (260, 6), (300, 18), (330, 32), (10, 40))],
                    0.065, mats(("#C0102E", 0.08, GLOSS)), sink=0.3), 0.15))),
    "honey": ("smooth", 88, ("#FFCC66", 0.35, None), lambda s: (
        W(glaze_cap("honey_g", s, mats(("#E89412", 0.08, GLOSS)), base=40, drips=((0, 26), (120, 30), (230, 22))), 2.0, keep_all=True)
        + [(disc("honey_comb", s.at(-30, 10)[0] - s.at(-30, 10)[1] * 0.05, s.at(-30, 10)[1], 0.17, 0.12,
                 mats(("#F5A623", 0.25, GLOSS)), seg=6), 0.4, True)]
        + [(stick("honey_dipper", s, (20, 2), (45, 16), 0.04, mats(("#B8742E", 0.6))), 0.4, False),
           (blobs("honey_dip_head", [(s.at(18, 0)[0] + s.at(18, 0)[1] * 0.05, 0.09, Vector((1.0, 1.0, 1.4)),
                                      frame(s.at(18, 0)[1]))], mats(("#C98A3E", 0.5))), 0.3, False)]
        + sauce_parts("honey_s", s, "low", "#E89412", width=0.08, rot=150))),
    "maple_syrup": ("ridged", 89, ("#F5D5A2", 0.5, None), lambda s: (
        W(glaze_cap("maple_g", s, mats(("#C2501A", 0.1, GLOSS)), base=44, drips=((30, 30), (170, 26), (280, 22))), 2.0, keep_all=True)
        + W(chunks_at("maple_n", s, [(-20, 10), (100, 14), (220, 6)], 0.12, mats(("#8A4A1E", 0.5)), sharp=False, flat=0.55), 0.5)
        + [(leaf("maple_leaf", s.at(10, 22)[0] + s.at(10, 22)[1] * 0.03, Vector((0.7, -0.6, 0.2)), 0.32, 0.16,
                 mats(("#D13A1A", 0.5))), 0.35, False)])),
    # ---------------------------------------------------------------------------------------------- epic
    "tiramisu": ("smooth", 91, ("#E8CCA4", 0.6, ("#6B4022", 11, 0.08)), lambda s: (
        [(dollop("tira_whip", s.at(0, 90)[0] - Vector((0, 0, 0.04)), 0.5, 0.36, mats(("#FFF6E4", 0.6, {"specks": ("#7A4A2A", 16, 0.2)}))), 1.4, True)]
        + [(stick("tira_lady0", s, (-40, 8), (-5, 18), 0.07, mats(("#F2D6A0", 0.75, {"specks": ("#FFF0CF", 12, 0.2)}))), 0.7, True),
           (stick("tira_lady1", s, (150, 14), (185, 6), 0.07, mats(("#F2D6A0", 0.75, {"specks": ("#FFF0CF", 12, 0.2)}))), 0.5, False)]
        + sauce_parts("tira_s", s, "low", "#4A2817", rot=60))),
    "white_chocolate": ("ridged", 92, ("#FFF3D8", 0.45, None), lambda s: (
        sauce_parts("wc_s", s, "diag", "#EAD3A4", rot=10)
        + W(chunks_at("wc_c", s, [(-20, 12), (90, 26), (200, 10), (290, 30)], 0.15, mats(("#FFFBF0", 0.3, GLOSS)), flat=0.5), 0.6)
        + [(curl("wc_curl", s, 40, 10, 0.035, mats(("#F2E2C0", 0.3, GLOSS))), 0.6, False)])),
    "black_cherry": ("swirl", 93, ("#B83D6A", 0.4, ("#3D0A1F", 9, 0.05)), lambda s: (
        cherry_pair("bc_ch", s, -10, 10, mats(("#4A0A1E", 0.1, GLOSS)), mats(("#5A7A2A", 0.5)), mats(("#3E7A1E", 0.45)))
        + sauce_parts("bc_s", s, "diag", "#3D0A1F", rot=40)
        + sauce_parts("bc_s2", s, "low", "#3D0A1F", width=0.08, rot=200, drips=((3, 22),)))),
    "pistachio_cream": ("smooth", 94, ("#D2E69A", 0.55, ("#8DB34A", 9, 0.06)), lambda s: (
        W(glaze_cap("pc_g", s, mats(("#FFF6DC", 0.4)), base=46, drips=((60, 24), (250, 20))), 1.8, keep_all=True)
        + W(chunks_at("pc_n", s, [(-20, 10), (80, 6), (170, 16), (280, 8)], 0.12, mats(("#7FA83C", 0.6, {"specks": ("#E4F2C2", 10, 0.2)})),
                      sharp=False, flat=0.6), 0.5)
        + [(dollop("pc_whip", s.at(0, 90)[0] + Vector((0, 0, 0.0)), 0.3, 0.26, mats(("#FFF6DC", 0.5))), 0.8, False)])),
    "salted_caramel": ("smooth", 95, ("#F3C58E", 0.4, None), lambda s: (
        W(glaze_cap("sc_g", s, mats(("#B8601A", 0.1, GLOSS)), base=42, drips=((20, 28), (150, 24), (260, 30))), 2.0, keep_all=True)
        + W(cubes("sc_c", s, [(-20, 8), (100, 14), (220, 6)], 0.14, mats(("#D9852E", 0.2, GLOSS)), seed=95), 0.5)
        + W(chunks_at("sc_salt", s, [(30, 60), (130, 58), (200, 64), (300, 56), (70, 70), (250, 72)], 0.04,
                      mats(("#FFFFFF", 0.3))), 0.15))),
    "marzipan": ("lumpy", 96, ("#F2CBB2", 0.6, ("#C68A55", 8, 0.06)), lambda s: (
        W(glaze_cap("marz_g", s, mats(("#FFF4E4", 0.45)), base=48, drips=((90, 20), (300, 24))), 1.6, keep_all=True)
        + W(blobs("marz_alm", [(s.at(t, e)[0] + s.at(t, e)[1] * 0.03, 0.12, Vector((1.0, 0.62, 0.36)), frame(s.at(t, e)[1], k))
                               for k, (t, e) in enumerate(((-20, 12), (110, 18), (230, 10)))],
                  mats(("#C68A55", 0.5, {"specks": ("#8A5A34", 14, 0.15)}))), 0.8)
        + sauce_parts("marz_s", s, "low", "#5A3420", width=0.08, rot=150))),
    "cinnamon_roll": ("swirl", 97, ("#E8B87C", 0.55, ("#8A4A1E", 9, 0.06)), lambda s: (
        W(glaze_cap("cin_g", s, mats(("#FFF6EA", 0.4)), base=46, drips=((40, 26), (200, 22))), 1.6, keep_all=True)
        + [(curl("cin_roll", s, -10, 14, 0.06, mats(("#B86A2E", 0.6, {"specks": ("#8A4A1E", 10, 0.15)})), turns=2.0, size=0.2), 1.2, True)]
        + [(stick("cin_stick0", s, (100, 8), (130, 20), 0.045, mats(("#7A3E18", 0.7))), 0.5, False),
           (stick("cin_stick1", s, (110, 4), (140, 14), 0.045, mats(("#7A3E18", 0.7))), 0.5, False)])),
    "cheesecake": ("smooth", 98, ("#FFF0C6", 0.55, None), lambda s: (
        sauce_parts("chc_s", s, "diag", "#C2183A", rot=20)
        + W(chunks_at("chc_crumb", s, [(t, -14 + (k % 3) * 4) for k, t in enumerate(range(0, 360, 40))], 0.08,
                      mats(("#C9954A", 0.8))), 0.15)
        + W(blobs("chc_straw", [(s.at(-15, 30)[0] + s.at(-15, 30)[1] * 0.06, 0.18, Vector((0.85, 0.85, 1.1)), frame(s.at(-15, 30)[1]))],
                  mats(("#D9203A", 0.25, {"specks": ("#FFE27A", 14, 0.08), "clearcoat": 0.6})), seg=16, rings=10), 1.0))),
    "mocha": ("ridged", 99, ("#9A6A4C", 0.5, None), lambda s: (
        [(dollop("mocha_whip", s.at(0, 90)[0] - Vector((0, 0, 0.04)), 0.48, 0.4, mats(("#FFF0DC", 0.55))), 1.4, True)]
        + sauce_parts("mocha_s", s, "low", "#4A2817", rot=80)
        + W(beans("mocha_b", s, [(-20, 12), (110, 20), (230, 8)], mats(("#3E2214", 0.3, GLOSS))), 0.4))),
    "passion_fruit": ("swirl", 100, ("#FFB830", 0.4, ("#1E1A14", 12, 0.05)), lambda s: (
        W(glaze_cap("pf_g", s, mats(("#F07A10", 0.1, GLOSS)), base=42, drips=((60, 26), (190, 30), (300, 22))), 1.8, keep_all=True)
        + W(slices("pf_half", s, [(-10, 12)], 0.27, mats(("#FFC83D", 0.2, {"specks": ("#1E1A14", 12, 0.16), "clearcoat": 1.0})),
                   mats(("#7A2E6E", 0.4)), thick=0.14, half=False, lean=0.2), 1.2, keep_all=True))),
    # ---------------------------------------------------------------------------------------------- legendary
    "midnight_berry": ("swirl", 101, ("#6A2FA0", 0.35, ("#D63FA8", 10, 0.04)), lambda s: (
        W(glaze_cap("mb_g", s, mats(("#3E1478", 0.08, GLOSS)), base=44, drips=((30, 26), (160, 30), (280, 24))), 1.6, keep_all=True)
        + sauce_parts("mb_s", s, "low", "#D63FA8", width=0.08, rot=20)
        + W(berries("mb_b", s, [(-25, 10), (-8, 4), (-16, 20)], 0.12, mats(("#2A1050", 0.3, {"specks": ("#9EA6FF", 16, 0.1)})), dimple=0.3), 0.7)
        + W(drupes("mb_r", s, [(110, 14)], 0.14, mats(("#C2185B", 0.3, GLOSS))), 0.6)
        + gems_at("mb_gem", s, [(200, 10), (60, 30)], "#B57BFF"))),
    "frosted_melon": ("smooth", 102, ("#FFA766", 0.5, None), lambda s: (
        W(glaze_cap("fm_g", s, mats(("#EAFBFF", 0.3)), base=46, drips=((50, 24), (210, 22))), 1.6, keep_all=True)
        + W(berries("fm_ball", s, [(-20, 10), (0, 18), (140, 12)], 0.15, mats(("#9BD36A", 0.25, GLOSS)), sink=0.35), 0.8)
        + gems_at("fm_ice", s, [(80, 8), (260, 14), (320, 30), (180, 30)], "#BFEFFF", size=0.1)
        + sauce_parts("fm_s", s, "low", "#F7BE2E", width=0.05, rot=250, drips=()))),
    "velvet_dream": ("smooth", 103, ("#C23A64", 0.45, ("#E8B020", 10, 0.04)), lambda s: (
        [(dollop("vd_whip", s.at(0, 90)[0] - Vector((0, 0, 0.04)), 0.5, 0.4, mats(("#FFF2EC", 0.55))), 1.4, True)]
        + sauce_parts("vd_s", s, "rise", "#F08AA8", width=0.1, rot=40)
        + gems_at("vd_gem", s, [(-25, 8), (150, 14), (260, 26)], "#FF5F9A")
        + W(cubes("vd_c", s, [(90, 8)], 0.15, mats(("#7E1630", 0.7)), seed=103), 0.4))),
    "mystic_plum": ("swirl", 104, ("#C25AB8", 0.4, None), lambda s: (
        W(glaze_cap("mp_g", s, mats(("#8A2A90", 0.08, GLOSS)), base=44, drips=((0, 24), (130, 28), (250, 26))), 1.6, keep_all=True)
        + W(blobs("mp_plum", [(s.at(-15, 12)[0] + s.at(-15, 12)[1] * 0.08, 0.2, Vector((1.0, 0.95, 0.9)), frame(s.at(-15, 12)[1]))],
                  mats(("#5A1A60", 0.15, {"specks": ("#8A3A90", 10, 0.1), "clearcoat": 1.0})), seg=16, rings=10), 1.0)
        + sauce_parts("mp_s", s, "low", "#E6B8F2", width=0.07, rot=120, gloss=False)
        + gems_at("mp_star", s, [(70, 20), (190, 10), (300, 30)], "#FFD24A", size=0.1))),
    "arctic_coconut": ("lumpy", 105, ("#F0F7FF", 0.6, ("#7A5030", 9, 0.04)), lambda s: (
        W(slices("ac_sl", s, [(-10, 12)], 0.3, mats(("#FFFFFF", 0.5)), mats(("#5A3820", 0.8)), thick=0.1), 1.3, keep_all=True)
        + sauce_parts("ac_s", s, "diag", "#5EC8F2", rot=60)
        + gems_at("ac_ice", s, [(80, 10), (160, 26), (240, 8), (310, 30)], "#9FE6FF", size=0.11))),
    "crimson_velvet": ("smooth", 106, ("#7E0F24", 0.4, ("#E8B020", 11, 0.04)), lambda s: (
        W(glaze_cap("cv_g", s, mats(("#C0182E", 0.06, GLOSS)), base=44, drips=((20, 30), (140, 24), (260, 28))), 1.6, keep_all=True)
        + sauce_parts("cv_s", s, "low", "#F6E2CF", width=0.07, rot=60, gloss=False)
        + gems_at("cv_gold", s, [(-20, 10), (100, 18), (220, 6)], "#F7BE2E")
        + W(cubes("cv_c", s, [(300, 14)], 0.15, mats(("#4A0A16", 0.7)), seed=106), 0.4))),
    "honey_blossom": ("smooth", 107, ("#FFEBC2", 0.45, None), lambda s: (
        W(glaze_cap("hb_g", s, mats(("#F29A1E", 0.08, GLOSS)), base=44, drips=((60, 24), (200, 28))), 1.6, keep_all=True)
        + [(x, 0.5, i < 2) for i, x in enumerate(flowers("hb_fl", s, [(-15, 14), (110, 20), (240, 10)], mats(("#FFFFFF", 0.5)),
                                                          mats(("#FFC83D", 0.4))))]
        + [(disc("hb_comb", s.at(170, 4)[0] - s.at(170, 4)[1] * 0.05, s.at(170, 4)[1], 0.15, 0.11,
                 mats(("#F5A623", 0.25, GLOSS)), seg=6), 0.4, False)]
        + gems_at("hb_gold", s, [(300, 26)], "#F7BE2E", size=0.1))),
    "velvet_mocha": ("ridged", 108, ("#5E3422", 0.4, ("#E8B020", 11, 0.03)), lambda s: (
        W(glaze_cap("vm_g", s, mats(("#FFF0DC", 0.4)), base=48, drips=((30, 22), (190, 26))), 1.4, keep_all=True)
        + [(dollop("vm_whip", s.at(0, 90)[0] + Vector((0, 0, 0.0)), 0.32, 0.28, mats(("#FFF0DC", 0.5))), 0.8, False)]
        + W(beans("vm_b", s, [(-20, 10), (100, 16), (220, 6)], mats(("#2A140A", 0.25, GLOSS))), 0.4)
        + gems_at("vm_gold", s, [(160, 26), (290, 10)], "#F7BE2E"))),
    "sapphire_cream": ("smooth", 109, ("#F4F6FF", 0.45, ("#E8B020", 11, 0.03)), lambda s: (
        sauce_parts("sap_s", s, "rise", "#1E3FBF", width=0.11, rot=0)
        + gems_at("sap_gem", s, [(-25, 6), (120, 18), (230, 8)], "#2A4FE0", size=0.14)
        + W(berries("sap_b", s, [(40, 12), (300, 20)], 0.11, mats(("#2A2F8A", 0.3, {"specks": ("#9EB0FF", 16, 0.1)})), dimple=0.3), 0.5)
        + gems_at("sap_gold", s, [(180, 30)], "#F7BE2E", size=0.1))),
}

ROLLOUT = list(RECIPES)


def make_flavor(fid):
    form, seed, (colour, rough, specks), parts = RECIPES[fid]

    def flavor_fn(surf):
        extra = {"specks": specks} if specks else {}
        return {"form": form, "seed": seed, "body": material(f"P_{fid}", colour, rough, **extra), "toppings": parts(surf)}

    return flavor_fn


for _fid in RECIPES:
    globals()["flavor_" + _fid] = make_flavor(_fid)
    FORM_OF[_fid] = RECIPES[_fid][0]
    SEED_OF[_fid] = RECIPES[_fid][1]
