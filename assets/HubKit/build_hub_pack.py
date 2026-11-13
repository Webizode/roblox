"""The hub pack: the decoration of the hub ring. References in the vault
(C:\\Users\\Wobble\\Desktop\\claude gehirn\\Wobble Scoops\\Wooble scoops Map assets):
    IceTree       "Erdbeer-Eisbaum – Konzeptübersicht" (variants pink, blue, choco: the crown is its own part)
    FlowerBush    "Wobble Scoops Blumenbusch Asset-Sheet"
    Rock          "Stilisierte Felsformation mit Gras und Blumen"
    Lantern       "Glänzende Eiscreme-Straßenlaterne" (the glass its own colour Lamp: Neon and a PointLight in Studio)
    WafflePlanter "Glänzender Waffelblumen-Übertopf"
    ParkBench     "Wobble Scoops Parkbank – Asset-Übersicht"
    PicnicTable   "Pastellfarbener Park mit Bank und Picknicktisch"
    TrashBin      "Verspielter Eiscreme-Mülleimer"
    Signpost      "Verspielter Eiscreme-Wegweiser im Cartoon-Stil" (three arrows, each its own part with a free face)
    Fountain      "Verspielter Eiscreme-Brunnen mit Wasserfontänen"
    Barrel, Crate "Verspielte Eiscreme-Fässer und Kisten" (variants wood, pink, blue)
    HarborGate    "Wobble Scoops_ Gesperrter Süßigkeitenhafen" (locked, "COMING SOON")

Run through run_hubkit.py. Studs, origin at the bottom centre, front -Y. Sizes against an R15 figure (5.2 studs).
"""

import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

SPECS = {}
Z_UP = Vector((0, 0, 1))
SPRINKLE = ("Gold", "SkyBlue", "Cream", "Cherry")


# --------------------------------------------------------------------------------------------------------------------
# building blocks on top of the arena kit


def _to(bm, verts, normal, at):
    """Turns verts built round the origin with +Z as 'out' so +Z points along normal, then moves them to at."""
    n = Vector(normal).normalized()
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Z_UP.rotation_difference(n).to_matrix(), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(at), verts=verts)


def tag(ob, part):
    if part:
        ob["part"] = part
    return ob


def ball(col, name, colour, radius, center, squash=1.0, segments=12, scale=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=max(4, segments // 2), radius=radius)
    bmesh.ops.scale(bm, vec=Vector(scale or (1, 1, squash)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return _object(col, name, bm, colour, smooth_angle=80)


def disc_n(col, name, colour, radius, thickness, center, normal, segments=16, bevel=0.08):
    """A round plate facing `normal` (medallions, keyholes)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=radius,
                          depth=thickness)
    _to(bm, bm.verts, normal, center)
    ob = _object(col, name, bm, colour, smooth_angle=40)
    if bevel:
        _bevel(ob, min(bevel, thickness / 2 - 1e-3), 1, angle=40)
    return ob


def lathe(col, name, colour, profile, segments=24, center=(0, 0), smooth=50, part=None, closed=False):
    """A round body turned from a profile of (radius, z), bottom to top. A radius of 0 closes it to a point; closed
    joins the last ring to the first (rings, rims)."""
    bm = bmesh.new()
    cx, cy = center
    rings = []
    for r, z in profile:
        if r < 1e-4:
            rings.append([bm.verts.new((cx, cy, z))])
        else:
            rings.append([bm.verts.new((cx + r * math.cos(2 * math.pi * i / segments),
                                        cy + r * math.sin(2 * math.pi * i / segments), z)) for i in range(segments)])
    pairs = list(zip(rings, rings[1:])) + ([(rings[-1], rings[0])] if closed else [])
    for a, b in pairs:
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(segments):
            j = (i + 1) % segments
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    return tag(_object(col, name, bm, colour, smooth_angle=smooth), part)


def blob(col, name, colour, r, z_bottom, z_mid, z_top, center=(0, 0), segments=24, steps=5, part=None):
    """A soft ellipsoid of radius r, widest at z_mid, from z_bottom (None: flat bottom at z_mid) to z_top: scoops,
    domes, crowns, mounds."""
    profile = []
    if z_bottom is None:
        profile.append((0.0, z_mid))
    else:
        for i in range(steps):
            t = -math.pi / 2 + (math.pi / 2) * i / steps
            profile.append((r * math.cos(t), z_mid + (z_mid - z_bottom) * math.sin(t)))
    for i in range(steps + 1):
        t = (math.pi / 2) * i / steps
        profile.append((r * math.cos(t), z_mid + (z_top - z_mid) * math.sin(t)))
    return lathe(col, name, colour, profile, segments, center, smooth=70, part=part)


def drip_skirt(col, name, colour, radius, z, drips=8, drop=(0.5, 1.2), width=(1.0, 1.6), thickness=0.3, seed=1,
               center=(0, 0), columns=32, base=0.25, part=None):
    """Glaze drips hanging all round from a ring (radius, z): the drip curtain of the arena kit in any colour."""
    rng = random.Random(seed)
    circ = 2 * math.pi * radius
    spots = [(circ * (i + rng.uniform(-0.2, 0.2)) / drips, rng.uniform(*width), rng.uniform(*drop))
             for i in range(drips)]
    wrapped = [(s + k * circ, w, d) for s, w, d in spots for k in (-1, 0, 1)]
    hang = drip_profile(circ, wrapped, base=base, wobble=0.0, seed=seed)
    tops, hangs, out = [], [], []
    for i in range(columns + 1):
        a = 2 * math.pi * i / columns
        tops.append((center[0] + radius * math.cos(a), center[1] + radius * math.sin(a), z))
        hangs.append(hang(circ * i / columns))
        out.append((math.cos(a), math.sin(a), 0))
    curtain = drip_curtain(col, name, tops, hangs, out, thickness=thickness)
    curtain.data.materials[0] = material(colour)
    return tag(curtain, part)


def iced_dome(col, name, colour, r, z_bottom, z_mid, z_top, drips, drop, width, thickness, seed, center=(0, 0),
              segments=24, part=None, sprinkles=0, sprinkle_size=(0.9, 0.3, 0.24)):
    """A glazed scoop: the dome, drips hanging from its widest ring and a few sprinkles on top."""
    blob(col, name, colour, r, z_bottom, z_mid, z_top, center, segments, part=part)
    drip_skirt(col, name + "_Drips", colour, r - 0.05, z_mid, drips, drop, width, thickness, seed, center,
               columns=max(16, segments + 8), part=part)
    if sprinkles:
        dome_sprinkles(col, name + "_Sprinkles", r, z_mid, z_top, sprinkles, center, seed=seed + 50,
                       size=sprinkle_size)


def surface_sprinkles(col, name, spots, colours=SPRINKLE, size=(0.9, 0.3, 0.24), seed=3):
    """Pill sprinkles lying on a surface: spots are (point, normal). One mesh per colour."""
    rng = random.Random(seed)
    meshes = {c: bmesh.new() for c in colours}
    for i, (p, n) in enumerate(spots):
        bm = meshes[colours[i % len(colours)]]
        made = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=4, radius=0.5)
        verts = made["verts"]
        bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(rng.uniform(0, math.pi), 3, "Z"), verts=verts)
        n = Vector(n).normalized()
        _to(bm, verts, n, Vector(p) + n * size[2] * 0.15)
    return [_object(col, f"{name}_{c}", bm, c, smooth_angle=80) for c, bm in meshes.items() if bm.verts]


def dome_sprinkles(col, name, r, z_mid, z_top, count, center=(0, 0), seed=5, t_range=(0.2, 1.1),
                   size=(0.9, 0.3, 0.24), colours=SPRINKLE):
    rng = random.Random(seed)
    h = z_top - z_mid
    spots = []
    for i in range(count):
        phi = i * 2.39996 + rng.uniform(-0.3, 0.3)
        t = rng.uniform(*t_range)
        p = (center[0] + r * math.cos(t) * math.cos(phi), center[1] + r * math.cos(t) * math.sin(phi),
             z_mid + h * math.sin(t))
        n = (math.cos(t) * math.cos(phi) / r, math.cos(t) * math.sin(phi) / r, math.sin(t) / h)
        spots.append((p, n))
    return surface_sprinkles(col, name, spots, colours, size, seed)


def waffle_cone(col, name, r0, r1, height, z0, center=(0, 0), spacing=1.45, ridge=0.42, segments=24, step_len=0.7):
    """A tapered Waffle body (radius r0 at the bottom, r1 at the top) with the Gold lattice wound round it."""
    body = cylinder(col, name + "_Body", "Waffle", r0, height, z0, center, segments, bevel=0.06, radius_top=r1,
                    bevel_segments=1)
    mean = (r0 + r1) / 2
    count = max(3, round(2 * math.pi * mean / (spacing * math.sqrt(2))))
    lines = []
    steps = max(6, int(height / step_len))
    for direction in (1, -1):
        for k in range(count):
            a0 = 2 * math.pi * k / count + (math.pi / count if direction < 0 else 0)
            pts = []
            for i in range(steps + 1):
                z = height * i / steps
                r = r0 + (r1 - r0) * z / height + ridge * 0.12
                a = a0 + direction * z / mean
                pts.append((center[0] + r * math.cos(a), center[1] + r * math.sin(a), z0 + z))
            lines.append(pts)
    ridges = _tube(col, name + "_Ridges", "Gold", lines, ridge)
    return body, ridges


def leaves(col, name, colour, specs):
    """Glossy pointed leaves in one mesh: specs are (base, yaw, pitch, length, width); pitch > 0 lifts the tip."""
    bm = bmesh.new()
    for base, yaw, pitch, length, width in specs:
        made = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=4, radius=0.5)
        verts = made["verts"]
        for v in verts:
            if v.co.x > 0:
                v.co.y *= 1 - 0.75 * (v.co.x / 0.5) ** 1.5
        bmesh.ops.scale(bm, vec=Vector((length, width, width * 0.28)), verts=verts)
        bmesh.ops.translate(bm, vec=Vector((length * 0.45, 0, 0)), verts=verts)
        rot = Matrix.Rotation(yaw, 3, "Z") @ Matrix.Rotation(-pitch, 3, "Y")
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=verts)
        bmesh.ops.translate(bm, vec=Vector(base), verts=verts)
    return _object(col, name, bm, colour, smooth_angle=80)


def flowers(col, name, colour, specs, petals=5, seed=0, centre="Gold"):
    """Five-petal flowers: specs are (center, normal, size). Petals in `colour`, a Gold centre."""
    rng = random.Random(seed)
    bm_p, bm_c = bmesh.new(), bmesh.new()
    for center, normal, size in specs:
        spin = rng.uniform(0, math.pi)
        verts = []
        for k in range(petals):
            made = bmesh.ops.create_uvsphere(bm_p, u_segments=8, v_segments=4, radius=0.5)
            v = made["verts"]
            bmesh.ops.scale(bm_p, vec=Vector((0.62 * size, 0.44 * size, 0.15 * size)), verts=v)
            bmesh.ops.translate(bm_p, vec=Vector((0.33 * size, 0, 0.03 * size)), verts=v)
            bmesh.ops.rotate(bm_p, cent=(0, 0, 0), matrix=Matrix.Rotation(spin + 2 * math.pi * k / petals, 3, "Z"),
                             verts=v)
            verts += v
        _to(bm_p, verts, normal, center)
        made = bmesh.ops.create_uvsphere(bm_c, u_segments=8, v_segments=4, radius=0.17 * size)
        v = made["verts"]
        bmesh.ops.scale(bm_c, vec=Vector((1, 1, 0.75)), verts=v)
        bmesh.ops.translate(bm_c, vec=Vector((0, 0, 0.1 * size)), verts=v)
        _to(bm_c, v, normal, center)
    return (_object(col, name + "_Petals", bm_p, colour, smooth_angle=80),
            _object(col, name + "_Centres", bm_c, centre, smooth_angle=80))


def grass(col, name, spots, seed=9, height=(0.6, 1.0), colour="Leaf"):
    """Tufts of a few blades (three-sided cones) at each spot."""
    rng = random.Random(seed)
    bm = bmesh.new()
    for x, y, z in spots:
        for _ in range(5):
            h = rng.uniform(*height)
            made = bmesh.ops.create_cone(bm, cap_ends=True, segments=3, radius1=0.13, radius2=0.0, depth=h)
            v = made["verts"]
            bmesh.ops.translate(bm, vec=Vector((0, 0, h / 2)), verts=v)
            tilt = Matrix.Rotation(rng.uniform(0, 2 * math.pi), 3, "Z") @ Matrix.Rotation(rng.uniform(0.1, 0.5), 3,
                                                                                         "X")
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=tilt, verts=v)
            bmesh.ops.translate(bm, vec=Vector((x + rng.uniform(-0.2, 0.2), y + rng.uniform(-0.2, 0.2), z)), verts=v)
    return _object(col, name, bm, colour, smooth_angle=30)


def rock(col, name, size, at, seed, colour="Rock", z0=0.0):
    """A chunky faceted rock (a jittered icosahedron with rounded edges), its bottom flat at z0. Returns the object
    and its highest point."""
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.5)
    turn = Matrix.Rotation(rng.uniform(0, 6.28), 3, "Z") @ Matrix.Rotation(rng.uniform(-0.4, 0.4), 3, "X")
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=turn, verts=bm.verts)
    for v in bm.verts:
        v.co *= 1 + rng.uniform(-0.1, 0.1)
        v.co.z = max(v.co.z, -0.3)
    # the flat bottom cuts the height: stretch back so the rock is size[2] high
    z_lo, z_hi = min(v.co.z for v in bm.verts), max(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z = (v.co.z - z_lo) / (z_hi - z_lo)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((at[0], at[1], z0)), verts=bm.verts)
    top = max(bm.verts, key=lambda v: v.co.z).co.copy()
    ob = _object(col, name, bm, colour, smooth_angle=22)
    _bevel(ob, 0.07 * min(size), 1, angle=22)
    return ob, top


def tile_ring(col, name, radius, count, depth, height, z0, colours=("Stone",), center=(0, 0), phase=0.0, gap=0.1,
              bevel=0.14):
    """A ring of rounded tiles (paving under lanterns, bins, planters; the fountain's wall and cap)."""
    length = 2 * math.pi * (radius + depth / 2) / count - gap
    for i in range(count):
        a = phase + 2 * math.pi * i / count
        ob = rounded_box(col, f"{name}{i}", colours[i % len(colours)], (length, depth, height), (0, 0, height / 2),
                         radius=bevel, segments=1)
        ob.rotation_euler = (0, 0, a + math.pi / 2)
        ob.location = (center[0] + radius * math.cos(a), center[1] + radius * math.sin(a), z0)


def _axes(normal, up=(0, 0, 1)):
    n = Vector(normal).normalized()
    v = Vector(up).normalized()
    return v.cross(n).normalized(), v, n


def plate(col, name, colour, outline, center, normal, thickness, up=(0, 0, 1), bevel=0.08, part=None):
    """A flat plate from a (u, v) outline, its back on the plane through center, `thickness` out along normal."""
    u_axis, v_axis, n = _axes(normal, up)
    c = Vector(center)
    bm = bmesh.new()
    _extruded(bm, outline, lambda u, v, d: c + u_axis * u + v_axis * v + n * d, thickness)
    ob = _object(col, name, bm, colour, smooth_angle=50)
    if bevel:
        _bevel(ob, bevel, 2, angle=50)
    return tag(ob, part)


def circle(r, n=16, cx=0.0, cy=0.0, a0=0.0):
    return [(cx + r * math.cos(a0 + 2 * math.pi * i / n), cy + r * math.sin(a0 + 2 * math.pi * i / n)) for i in range(n)]


def stadium(w, h, n=8):
    """A rounded bar outline (w wide, h high, round ends)."""
    r = h / 2
    pts = [(w / 2 - r + r * math.cos(-math.pi / 2 + math.pi * i / n), r * math.sin(-math.pi / 2 + math.pi * i / n))
           for i in range(n + 1)]
    return pts + [(-x, -y) for x, y in pts]


def scoop_icon(col, name, center, normal, size, scoop="Pink", up=(0, 0, 1)):
    """The ice cream icon: a Waffle cone and a round scoop on top, flat on a face."""
    s = size
    plate(col, name + "_Cone", "Waffle", [(-0.34 * s, 0.08 * s), (0.34 * s, 0.08 * s), (0, -0.7 * s)], center, normal,
          0.1, up, bevel=0.03)
    outline = [(u, max(v, 0.02 * s)) for u, v in circle(0.4 * s, 16, 0, 0.32 * s)]
    u_axis, v_axis, n = _axes(normal, up)
    plate(col, name + "_Scoop", scoop, outline, Vector(center) + n * 0.05, normal, 0.12, up, bevel=0.04)


def medallion(col, name, center, normal, radius, scoop="Pink"):
    """A Gold-rimmed Cream disc with the ice cream icon (bench back, barrel, gate badge)."""
    n = Vector(normal).normalized()
    disc_n(col, name + "_Rim", "Gold", radius, 0.22, center, n, segments=20)
    disc_n(col, name + "_Field", "Cream", radius * 0.8, 0.22, Vector(center) + n * 0.07, n, segments=20)
    scoop_icon(col, name + "_Icon", Vector(center) + n * 0.17, n, radius * 0.95, scoop)


def strawberry(col, name, at, size=1.0):
    x, y, z = at
    s = size
    lathe(col, name, "Cherry", [(0, z), (0.3 * s, z + 0.06 * s), (0.6 * s, z + 0.38 * s), (0.68 * s, z + 0.8 * s),
                                 (0.56 * s, z + 1.15 * s), (0.3 * s, z + 1.3 * s), (0, z + 1.33 * s)],
          segments=14, center=(x, y), smooth=80)
    top = (x, y, z + 1.25 * s)
    leaves(col, name + "_Leaves", "Leaf",
           [(top, 2 * math.pi * k / 5 + 0.3, -0.25, 0.75 * s, 0.38 * s) for k in range(5)])
    _tube(col, name + "_Stem", "LeafDark", [[top, (x + 0.05, y, z + 1.65 * s)]], 0.14 * s, sides=4)


def cherry(col, name, at, r=0.45):
    x, y, z = at
    ball(col, name, "Cherry", r, (x, y, z + r * 0.8), segments=12)
    _tube(col, name + "_Stem", "Cherry",
          [[(x, y, z + r * 1.6), (x + r * 0.35, y, z + r * 2.4), (x + r * 1.0, y, z + r * 2.9)]], r * 0.28)


def arc_points(a, b, bulge, n=8):
    """Points from a to b along a parabola that rises `bulge` above the straight line."""
    a, b = Vector(a), Vector(b)
    return [tuple(a + (b - a) * (i / n) + Vector((0, 0, bulge * 4 * (i / n) * (1 - i / n)))) for i in range(n + 1)]


# collisions, in the model's frame (Blender studs, z up); the luau script turns them into Roblox
def box(size, center, name=None):
    d = dict(kind="box", size=[round(v, 3) for v in size], center=[round(v, 3) for v in center])
    if name:
        d["name"] = name
    return d


def cyl(radius, height, center=(0, 0), z0=0.0, name=None):
    d = dict(kind="cylinder", radius=round(radius, 3), height=round(height, 3),
             center=[round(center[0], 3), round(center[1], 3), round(z0 + height / 2, 3)])
    if name:
        d["name"] = name
    return d


# --------------------------------------------------------------------------------------------------------------------
# Ice Tree: a long tapered waffle trunk under a crown of three overlapping glazed scoops with drips and sprinkles, a
# cream swirl and a strawberry in the middle on top. The crown (the three scoops with their drips) is the part Crown:
# Pink in the FBX, SkyBlue and Choco as variants in Studio. Change of 06.11.2026 (user): trunk about twice as long, the
# crown three drip balls as in the reference, so it reads as a tree and not as a cone; about 20 high, crown 13 wide.

TREE = dict(trunk=11.6, ring=2.4, r=4.0, below=2.0, above=3.4)
# improvement 1: the three scoops differ in size and height (front two lower, the back one higher), so the crown shows
# three balls from the front and not one flat cap; longer drips
SCOOPS = [(-math.pi / 6, 4.1, -0.5), (math.pi + math.pi / 6, 3.9, -0.3), (math.pi / 2, 3.7, 1.1)]


def build_ice_tree():
    col = hk_collection("IceTree")
    t = TREE
    cylinder(col, "Foot", "Waffle", 2.15, 0.5, 0, radius_top=1.8, segments=20, bevel=0.15)
    # improvement 1: wide at the root and slimmer up to the crown, like the reference, so it no longer reads as a cone
    waffle_cone(col, "Trunk", 2.0, 1.35, t["trunk"], 0.35, spacing=1.45, ridge=0.42, segments=20)
    z_mid = 0.35 + t["trunk"] + 0.3
    for k, (a, r, dz) in enumerate(SCOOPS):
        c = (t["ring"] * math.cos(a), t["ring"] * math.sin(a))
        m = z_mid + dz
        iced_dome(col, f"Crown{k + 1}", "Pink", r, m - t["below"], m, m + t["above"] * r / t["r"], drips=9,
                  drop=(1.5, 3.2), width=(1.4, 2.1), thickness=0.4, seed=11 + k, center=c, segments=26, part="Crown",
                  sprinkles=11)
    # the three scoops meet over the trunk at z_mid + above * sqrt(1 - (ring / r)^2): the swirl sits in that dip
    dip = z_mid + t["above"] * math.sqrt(1 - (t["ring"] / t["r"]) ** 2)
    parts, top = soft_serve(col, "Cream", "Cream", 1.55, dip - 0.3, tiers=2, cherry=False)
    strawberry(col, "Berry", (0, 0, top - 0.4), 1.45)
    SPECS["IceTree"] = dict(
        collision=[cyl(2.0, 0.35 + t["trunk"], name="Trunk")],
        variants={"Blue": {"Crown": "SkyBlue"}, "Choco": {"Crown": "Choco"}},
        figure=(-7.5, -7.5),
        note="crown (three scoops and drips) is the part Crown: IceTree_Crown_Pink; variants IceTree_Blue, "
        "IceTree_Choco",
    )


# Flower Bush: glossy green balls in a dome, leaves sticking out, pink and white flowers, two pebbles. 7 wide, 4.8 high.


def build_flower_bush():
    col = hk_collection("FlowerBush")
    rng = random.Random(31)
    blobs = []
    for ring, (rr, z, r, n, colour) in enumerate(((2.3, 1.05, 1.25, 9, "LeafDark"), (1.55, 2.25, 1.25, 7, "Leaf"),
                                                  (0.55, 3.2, 1.15, 3, "Leaf"))):
        for i in range(n):
            a = 2 * math.pi * (i + 0.5 * ring) / n + rng.uniform(-0.15, 0.15)
            c = Vector((rr * 1.15 * math.cos(a), rr * 0.85 * math.sin(a), z))
            rad = r * rng.uniform(0.9, 1.1)
            ball(col, f"Blob{ring}_{i}", colour, rad, c, squash=0.88, segments=12)
            blobs.append((c, rad, a))
    tips = []
    for k in range(9):
        a = 2 * math.pi * k / 9 + 0.2
        tips.append(((0.9 * math.cos(a), 0.7 * math.sin(a), 3.7), a, 0.9, 1.3, 0.55))
    for k in range(8):
        a = 2 * math.pi * k / 8
        tips.append(((2.9 * math.cos(a), 2.2 * math.sin(a), 0.5), a, 0.5, 1.2, 0.5))
    leaves(col, "Leaves", "Leaf", tips)
    pink, cream = [], []
    # improvement 1: the flowers half as big again, like the reference's
    picks = [(9, 1.4), (11, 1.65), (13, 1.3), (2, 1.5), (16, 1.35), (17, 1.55), (6, 1.3)]
    for k, (idx, size) in enumerate(picks):
        c, rad, a = blobs[idx]
        d = (c - Vector((0, 0, 1.2))).normalized()
        (pink if k % 3 != 1 else cream).append((c + d * rad * 0.9, d, size))
    flowers(col, "FlowerPink", "Pink", pink, seed=3)
    flowers(col, "FlowerCream", "Cream", cream, seed=4)
    rock(col, "PebbleL", (1.1, 0.9, 0.7), (-1.9, -2.3), seed=5)
    rock(col, "PebbleR", (1.3, 1.0, 0.8), (2.4, -1.9), seed=6)
    SPECS["FlowerBush"] = dict(collision="auto", figure=(-5.4, -3.5))


# Rock: a cluster of five faceted lavender rocks, moss on two, grass tufts and two daisies. 8.5 wide, 5.6 high.


def build_rock():
    col = hk_collection("Rock")
    big = [((3.6, 3.0, 5.6), (1.0, 0.9), 1, False), ((3.4, 2.8, 3.9), (-1.7, 0.3), 2, True),
           ((3.8, 2.8, 2.7), (2.3, -0.9), 3, True), ((2.4, 2.2, 2.3), (-3.7, -0.4), 4, False),
           ((2.8, 2.0, 1.7), (-0.5, -1.7), 5, False)]
    boxes = []
    for i, (size, at, seed, moss) in enumerate(big):
        ob, top = rock(col, f"Rock{i}", size, at, seed)
        boxes.append(box((size[0] * 0.78, size[1] * 0.78, size[2] * 0.85), (at[0], at[1], size[2] * 0.425),
                         name=f"Rock{i}"))
        if moss:
            r = min(size[0], size[1]) * 0.42  # improvement 2: flatter and wider, it read as a lid
            iced_dome(col, f"Moss{i}", "Leaf", r, top.z - 0.55, top.z - 0.42, top.z - 0.08, drips=8,
                      drop=(0.35, 1.0), width=(0.4, 0.8), thickness=0.18, seed=20 + i, center=(top.x, top.y),
                      segments=16)
    for i, (size, at) in enumerate((((0.9, 0.8, 0.5), (-2.6, -1.9)), ((1.2, 1.0, 0.6), (4.4, -0.5)),
                                    ((0.7, 0.6, 0.4), (0.9, -2.6)))):
        rock(col, f"Pebble{i}", size, at, seed=40 + i)
    grass(col, "Grass", [(-4.6, -0.9, 0), (-2.1, -1.6, 0), (1.1, -2.2, 0), (3.9, -1.6, 0), (-0.4, 1.8, 0),
                         (3.0, 1.4, 0)])
    flowers(col, "Daisy", "Cream", [((-1.6, -1.95, 0.55), (-0.2, -0.6, 0.8), 0.9),
                                    ((3.5, -2.05, 0.5), (0.2, -0.6, 0.8), 0.85)], seed=8)
    SPECS["Rock"] = dict(collision=boxes, figure=(-6.8, -3.4))


# Lantern: a pink-glazed cream scoop on paving, a waffle pole with pink and gold rings, a scoop on a waffle cup on top,
# a gold arm curling out to +X and the lantern hanging from it: pink glazed cap, glowing glass (colour Lamp, Neon and
# a PointLight in Studio), gold bars and foot. 12.6 high, the lamp 2.75 out from the pole, its foot at 6.4.

LAMP_AT = (2.75, 0.0)


def build_lantern():
    col = hk_collection("Lantern")
    tile_ring(col, "Tile", radius=1.6, count=9, depth=0.95, height=0.55, z0=0)
    cylinder(col, "TileCore", "Stone", 1.2, 0.5, 0, segments=14, bevel=0.1)
    blob(col, "BaseScoop", "Cream", 1.55, 0.35, 1.05, 2.1, segments=20)
    iced_dome(col, "BaseGlaze", "Pink", 1.48, 1.5, 1.75, 2.3, drips=6, drop=(0.25, 0.6), width=(0.6, 0.9),
              thickness=0.22, seed=3, segments=20, sprinkles=8, sprinkle_size=(0.5, 0.17, 0.14))
    cylinder(col, "RingLow", "Gold", 0.74, 0.35, 2.15, segments=16, bevel=0.1)
    waffle_cylinder(col, "Pole", 0.42, 7.2, 2.4, spacing=1.1, ridge=0.3, segments=16)
    cylinder(col, "RingMid", "Pink", 0.64, 0.5, 5.3, segments=16, bevel=0.18)
    cylinder(col, "RingTop", "Gold", 0.64, 0.3, 9.4, segments=16, bevel=0.1)
    cylinder(col, "RingTop2", "Pink", 0.6, 0.4, 9.7, segments=16, bevel=0.15)
    waffle_cone(col, "Cup", 0.5, 1.05, 1.0, 10.05, spacing=1.0, ridge=0.28, segments=16)
    blob(col, "TopScoop", "Cream", 1.2, 10.8, 11.4, 12.4, segments=20)
    iced_dome(col, "TopGlaze", "Pink", 1.16, 11.3, 11.75, 12.6, drips=5, drop=(0.3, 0.9), width=(0.5, 0.8),
              thickness=0.2, seed=5, segments=20, sprinkles=7, sprinkle_size=(0.45, 0.15, 0.13))
    hx, hy = LAMP_AT
    _tube(col, "Arm", "Gold", [[(0.3, 0, 10.2), (1.0, 0, 10.75), (1.9, 0, 10.95), (2.6, 0, 10.7), (2.95, 0, 10.2),
                                (2.85, 0, 9.75), (2.6, 0, 9.65)]], 0.34, sides=6)
    _tube(col, "Hook", "Gold", [[(hx + 0.2 * math.cos(a), hy, 9.42 + 0.2 * math.sin(a))
                                 for a in [2 * math.pi * i / 10 for i in range(11)]]], 0.1, sides=4)
    cylinder(col, "LampTop", "Gold", 0.3, 0.25, 9.0, center=LAMP_AT, segments=12, bevel=0.08)
    iced_dome(col, "LampCap", "Pink", 0.95, 8.35, 8.55, 9.2, drips=5, drop=(0.2, 0.5), width=(0.4, 0.7),
              thickness=0.18, seed=6, center=LAMP_AT, segments=16, sprinkles=5, sprinkle_size=(0.4, 0.14, 0.12))
    cylinder(col, "LampRim", "Gold", 0.86, 0.2, 8.25, center=LAMP_AT, segments=12, bevel=0.06)
    lathe(col, "Glass", "Lamp", [(0, 7.0), (0.58, 7.0), (0.78, 8.3), (0, 8.3)], segments=6, center=LAMP_AT, smooth=30)
    bars = []
    for k in range(6):
        a = 2 * math.pi * k / 6
        bars.append([(hx + 0.63 * math.cos(a), hy + 0.63 * math.sin(a), 7.0),
                     (hx + 0.83 * math.cos(a), hy + 0.83 * math.sin(a), 8.3)])
    _tube(col, "Bars", "Gold", bars, 0.12, sides=4)
    lathe(col, "LampFoot", "Gold", [(0, 6.55), (0.25, 6.55), (0.72, 6.85), (0.72, 7.05), (0, 7.05)], segments=12,
          center=LAMP_AT)
    ball(col, "Finial", "Gold", 0.18, (hx, hy, 6.45), segments=8)
    SPECS["Lantern"] = dict(
        collision=[cyl(1.6, 2.3, name="Base"), cyl(0.65, 10.2, z0=2.3, name="Pole")],
        light=[hx, hy, 7.65],
        figure=(-3.6, -2.6),
        note="glass Lantern_Lamp: Neon and a PointLight in Studio; the arm reaches 2.75 + 0.85 out along +X "
        "(Roblox -X), the lamp's foot at 6.4",
    )


# Waffle Planter: a waffle pot on rose paving, a pink glazed rim with drips and sprinkles, a green mound with leaves,
# a big pink and a blue flower and three daisies. 4.6 wide, 4.6 high.


def build_waffle_planter():
    col = hk_collection("WafflePlanter")
    tile_ring(col, "Tile", radius=1.95, count=10, depth=0.95, height=0.6, z0=0)
    cylinder(col, "TileCore", "Stone", 1.5, 0.5, 0, segments=16, bevel=0.1)
    waffle_cone(col, "Pot", 1.55, 2.05, 2.1, 0.45, spacing=1.2, ridge=0.34, segments=20)
    lathe(col, "Rim", "Pink", [(1.7, 2.35), (2.25, 2.35), (2.32, 2.62), (2.22, 2.9), (1.7, 2.9)], segments=24,
          closed=True, smooth=70)
    drip_skirt(col, "RimDrips", "Pink", 2.22, 2.62, drips=7, drop=(0.35, 1.1), width=(0.6, 1.0), thickness=0.25,
               seed=8)
    surface_sprinkles(col, "Sprinkles", [((2.0 * math.cos(a), 2.0 * math.sin(a), 2.86), (0, 0, 1))
                                         for a in [2 * math.pi * k / 9 + 0.3 for k in range(9)]],
                      size=(0.55, 0.18, 0.14), seed=9)
    blob(col, "Mound", "LeafDark", 1.95, None, 2.6, 3.6, segments=20)
    specs_a, specs_b = [], []
    for k in range(12):
        a = 2 * math.pi * k / 12
        r = 1.35 if k % 2 else 0.9
        (specs_a if k % 2 else specs_b).append(((r * math.cos(a), r * math.sin(a), 3.2), a, 0.55 + 0.25 * (k % 3),
                                                1.5, 0.62))
    leaves(col, "Leaves", "Leaf", specs_a)
    leaves(col, "LeavesDark", "LeafDark", specs_b)
    flowers(col, "Hibiscus", "Pink", [((-0.5, -0.6, 3.95), (-0.2, -0.6, 0.8), 1.7),
                                      ((0.5, 1.0, 3.75), (0.1, 0.5, 0.85), 1.2)], seed=11)
    flowers(col, "BlueFlower", "SkyBlue", [((0.95, -0.45, 3.75), (0.35, -0.6, 0.75), 1.35)], seed=12)
    flowers(col, "Daisy", "Cream", [((-1.55, -0.85, 3.3), (-0.5, -0.5, 0.7), 0.75),
                                    ((0.15, -1.4, 3.35), (0, -0.7, 0.7), 0.7),
                                    ((1.65, -0.7, 3.3), (0.5, -0.5, 0.7), 0.75)], seed=13)
    SPECS["WafflePlanter"] = dict(collision=[cyl(2.25, 2.9, name="Pot")], figure=(-4.2, -2.6))


# Park Bench: waffle legs with icing on the arms, three wooden seat slats (top at 1.9), a slatted back between waffle
# posts and the scoop medallion on top. 8.6 wide, 6 high (reference: 8 to 10 wide, 5 to 6 high). Two seats.


def build_park_bench():
    col = hk_collection("ParkBench")
    for side, sx in (("L", -1), ("R", 1)):
        x = sx * 3.55
        body, ridges = waffle_panel(col, "Leg" + side, (1.2, 2.4, 2.5), (x, 0, 1.25), spacing=0.9,
                                    ridge_width=0.3, ridge_height=0.12)
        rounded_box(col, "Foot" + side, "Waffle", (1.45, 2.65, 0.3), (x, 0, 0.15), radius=0.12, segments=1)
        slab, drips = glaze(col, "Arm" + side, 1.55, 2.75, 3.1, thickness=0.6,
                            drips={"front": [(0.0, 0.9, 0.7)], "back": [(0.15, 0.8, 0.45)]}, drip_base=0.25,
                            columns=8, seed=3 if sx < 0 else 4)
        for ob in (slab, drips):
            ob.location.x = x
        sprinkles(col, "ArmSprinkles" + side, [(x - 0.35, -0.6, 3.1), (x + 0.3, 0.1, 3.1), (x - 0.1, 0.8, 3.1)],
                  size=(0.55, 0.18, 0.14), seed=5 if sx < 0 else 6)
        rounded_box(col, "BackPost" + side, "Waffle", (0.5, 0.5, 2.6), (sx * 3.3, 0.95, 3.75), radius=0.15,
                    segments=1)
    for y in (-0.72, -0.05, 0.62):
        rounded_box(col, "Seat", "Wood", (7.3, 0.62, 0.28), (0, y, 1.76), radius=0.1, segments=2)
    rounded_box(col, "SeatBeam", "Waffle", (6.0, 0.5, 0.4), (0, -0.05, 1.4), radius=0.1, segments=1)
    for i, z in enumerate((2.55, 3.25, 3.95)):
        ob = rounded_box(col, f"Back{i}", "Wood", (6.4, 0.3, 0.55), (0, 0, 0), radius=0.1, segments=2)
        ob.rotation_euler = (math.radians(-8), 0, 0)
        ob.location = (0, 0.95 + (z - 2.55) * 0.14, z)
    rounded_box(col, "BackTop", "Wood", (7.1, 0.42, 0.6), (0, 1.12, 4.65), radius=0.14, segments=2)
    disc_n(col, "BadgeBack", "Wood", 1.2, 0.42, (0, 1.12, 4.95), (0, -1, 0), segments=20, bevel=0.12)
    medallion(col, "Badge", (0, 0.86, 4.95), (0, -1, 0), 0.95)
    SPECS["ParkBench"] = dict(
        collision=[box((8.6, 2.6, 1.9), (0, 0, 0.95), "Seat"), box((7.0, 0.7, 3.3), (0, 1.05, 3.55), "Back"),
                   box((1.5, 2.7, 3.1), (-3.55, 0, 1.55), "ArmL"), box((1.5, 2.7, 3.1), (3.55, 0, 1.55), "ArmR")],
        seats=[dict(at=[-1.6, -0.05, 1.9], look=[-1.6, -1.05, 1.9]), dict(at=[1.6, -0.05, 1.9], look=[1.6, -1.05, 1.9])],
        figure=(-6.2, -2.8),
    )


# Picnic Table: a round wooden top (2.7 high) on a cream pedestal, a striped pink and cream umbrella (edge at 7.4,
# 8.8 wide) with a pink knob, three stools with pink cushions (1.95 high). Three seats facing the table.


def canopy(col, name, radius, apex, edge, panels=8, colours=("Pink", "Cream"), rings=6, cols=6, droop=0.35,
           thickness=0.16):
    for p in range(panels):
        bm = bmesh.new()
        a0, a1 = 2 * math.pi * p / panels, 2 * math.pi * (p + 1) / panels
        grid = []
        for i in range(rings + 1):
            s = i / rings
            r = 0.2 + (radius - 0.2) * s
            row = []
            for j in range(cols + 1):
                t = j / cols
                a = a0 + (a1 - a0) * t
                z = edge + (apex - edge) * (1 - s * s) + 0.18 * math.sin(math.pi * t) * s - droop * math.sin(
                    math.pi * t) * s ** 6
                row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
            grid.append(row)
        for i in range(rings):
            for j in range(cols):
                f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
                f.normal_update()
                if f.normal.z < 0:
                    f.normal_flip()
        ob = _object(col, f"{name}{p}", bm, colours[p % len(colours)], smooth_angle=60, recalc=False)
        solid = ob.modifiers.new("Solidify", "SOLIDIFY")
        solid.thickness = thickness
        solid.offset = -1.0
        solid.use_even_offset = True


STOOLS = [math.radians(a) for a in (-90, 30, 150)]
STOOL_R = 4.3


def build_picnic_table():
    col = hk_collection("PicnicTable")
    lathe(col, "Pedestal", "Cream", [(0, 0), (1.2, 0), (1.25, 0.25), (0.9, 0.5), (0.45, 0.9), (0.4, 2.2), (0.7, 2.35),
                                     (0, 2.35)], segments=20)
    cylinder(col, "Top", "Wood", 3.0, 0.38, 2.32, segments=28, bevel=0.14)
    cylinder(col, "Collar", "Cream", 0.42, 0.3, 2.68, segments=12, bevel=0.1)
    cylinder(col, "Pole", "Wood", 0.17, 6.1, 2.7, segments=10, bevel=0.05)
    canopy(col, "Canopy", 4.4, 8.9, 7.4)
    ball(col, "Knob", "Pink", 0.42, (0, 0, 9.0), squash=0.8)
    collision = [cyl(3.0, 2.7, name="Table")]
    seats = []
    for k, a in enumerate(STOOLS):
        c = (STOOL_R * math.cos(a), STOOL_R * math.sin(a))
        lathe(col, f"Stool{k}", "Cream", [(0, 0), (0.8, 0), (0.82, 0.15), (0.6, 1.45), (0, 1.45)], segments=16,
              center=c)
        cylinder(col, f"Cushion{k}", "Pink", 0.9, 0.5, 1.45, center=c, segments=18, bevel=0.22)
        collision.append(cyl(0.9, 1.95, c, name=f"Stool{k}"))
        seats.append(dict(at=[round(c[0], 3), round(c[1], 3), 1.95], look=[0, 0, 1.95]))
    SPECS["PicnicTable"] = dict(collision=collision, seats=seats, figure=(-6.8, -5.2),
                                note="umbrella edge at 7.4: a seated player's tower goes through it")


# Trash Bin: a waffle cone on rose paving, a pink glazed collar with drips and sprinkles, a cream lid with a dark
# opening at the front and a cherry, a pink badge with a bin icon, leaves and daisies at the foot. 5.4 high.


def build_trash_bin():
    col = hk_collection("TrashBin")
    tile_ring(col, "Tile", radius=1.6, count=9, depth=0.9, height=0.6, z0=0)
    cylinder(col, "TileCore", "Stone", 1.2, 0.5, 0, segments=14, bevel=0.1)
    cylinder(col, "Ring", "Gold", 1.42, 0.28, 0.55, segments=20, bevel=0.1)
    waffle_cone(col, "Body", 1.25, 1.58, 2.7, 0.75, spacing=1.15, ridge=0.32, segments=20)
    cylinder(col, "Collar", "Pink", 1.8, 0.6, 3.25, segments=24, bevel=0.22)
    drip_skirt(col, "CollarDrips", "Pink", 1.76, 3.5, drips=6, drop=(0.35, 1.0), width=(0.6, 1.0), thickness=0.26,
               seed=13)
    surface_sprinkles(col, "Sprinkles", [((1.84 * math.cos(a), 1.84 * math.sin(a), 3.62), (math.cos(a), math.sin(a), 0))
                                         for a in [math.radians(d) for d in range(-160, 200, 40)]],
                      size=(0.55, 0.18, 0.14), seed=14)
    blob(col, "Lid", "Cream", 1.55, 3.7, 3.85, 5.15, segments=24)
    ball(col, "Opening", "Choco", 1.0, (0, -1.33, 4.3), scale=(0.8, 0.24, 0.42), segments=16)
    cherry(col, "Cherry", (0, 0, 5.0), 0.42)
    rounded_box(col, "BadgeRim", "Cherry", (1.5, 0.2, 1.55), (0, -1.47, 2.1), radius=0.08, segments=1)
    rounded_box(col, "Badge", "Pink", (1.25, 0.2, 1.3), (0, -1.57, 2.1), radius=0.08, segments=1)
    rounded_box(col, "IconBody", "Cream", (0.55, 0.12, 0.6), (0, -1.7, 1.95), radius=0.05, segments=1)
    rounded_box(col, "IconLid", "Cream", (0.75, 0.12, 0.13), (0, -1.7, 2.34), radius=0.04, segments=1)
    rounded_box(col, "IconHandle", "Cream", (0.26, 0.12, 0.12), (0, -1.7, 2.46), radius=0.04, segments=1)
    for x in (-0.13, 0.13):
        rounded_box(col, "IconSlot", "Pink", (0.08, 0.1, 0.4), (x, -1.77, 1.95), radius=0.03, segments=1)
    leaves(col, "Leaves", "LeafDark", [((sx * 1.4, -0.5, 0.6), math.atan2(-0.5, sx * 1.4) + d, 0.45, 1.1, 0.5)
                                        for sx in (-1, 1) for d in (-0.4, 0.3)])
    flowers(col, "Daisy", "Cream", [((sx * 1.45, -0.95, 0.8), (sx * 0.5, -0.7, 0.5), 0.65) for sx in (-1, 1)], seed=15)
    SPECS["TrashBin"] = dict(collision=[cyl(1.8, 5.2, name="Bin")], figure=(-3.6, -2.4))


# Signpost: a grass mound with rocks and daisies, a waffle base with a pink glazed collar, a waffle pole, a glazed
# scoop on a waffle cup on top and three arrow boards (pink, blue, gold) pointing +X, each its own part Arrow1..3 with a
# free front face for a SurfaceGui (the words come by code). 13 high, the boards 6.4 long.

ARROWS = [(9.1, "Pink"), (7.3, "SkyBlue"), (5.5, "Gold")]
ARROW = dict(x0=-2.0, x1=4.4, head=1.0, h=1.5, y=-0.5, t=0.42)
# the text field on each arrow (Blender x along the board, z from the board's middle) and its words, top to bottom
SIGN_TEXT = dict(x0=-0.5, x1=3.5, z0=-0.22, z1=0.62, labels=["SHOP", "UPGRADES", "ISLANDS"])


def sign_area():
    """The text field as fractions of the arrow's front (a SurfaceGui on Face Front): left, right, top, bottom. Seen
    from the front, Blender +x is to the right and Roblox Front is Blender -Y."""
    a, s = ARROW, SIGN_TEXT
    w = a["x1"] - a["x0"]
    return [round((s["x0"] - a["x0"]) / w, 4), round((s["x1"] - a["x0"]) / w, 4),
            round((a["h"] / 2 - s["z1"]) / a["h"], 4), round((a["h"] / 2 - s["z0"]) / a["h"], 4)]


def build_signpost():
    col = hk_collection("Signpost")
    blob(col, "Mound", "Leaf", 2.6, None, 0.0, 0.55, segments=20)
    rock(col, "RockL", (1.3, 1.1, 0.9), (-1.5, -1.2), seed=3, z0=0.15)
    rock(col, "RockB", (0.9, 0.8, 0.6), (-0.4, -1.95), seed=4, z0=0.05)
    grass(col, "Grass", [(1.9, -0.9, 0.2), (-2.0, 0.6, 0.2), (0.9, 1.7, 0.2), (2.0, 0.9, 0.2)], seed=4)
    flowers(col, "Daisy", "Cream", [((-0.6, -1.25, 0.55), (-0.1, -0.6, 0.8), 0.75),
                                    ((1.25, -1.35, 0.5), (0.3, -0.6, 0.75), 0.8)], seed=5)
    leaves(col, "Leaves", "LeafDark", [((0.7 * math.cos(a), 0.7 * math.sin(a), 0.45), a, 0.5, 1.1, 0.5)
                                        for a in [2 * math.pi * k / 6 + 0.4 for k in range(6)]])
    waffle_cone(col, "Base", 0.95, 0.62, 1.6, 0.3, spacing=1.0, ridge=0.3, segments=16)
    cylinder(col, "Collar", "Pink", 0.8, 0.45, 1.7, segments=16, bevel=0.15)
    drip_skirt(col, "CollarDrips", "Pink", 0.76, 1.93, drips=5, drop=(0.25, 0.7), width=(0.45, 0.7), thickness=0.2,
               seed=6, columns=24)
    waffle_cylinder(col, "Pole", 0.5, 8.4, 2.0, spacing=1.1, ridge=0.3, segments=16)
    cylinder(col, "Ring", "Gold", 0.66, 0.35, 10.25, segments=16, bevel=0.1)
    waffle_cone(col, "Cup", 0.55, 1.05, 1.0, 10.55, spacing=1.0, ridge=0.28, segments=16)
    iced_dome(col, "Scoop", "Pink", 1.2, 11.2, 11.85, 13.0, drips=5, drop=(0.3, 0.9), width=(0.5, 0.8),
              thickness=0.22, seed=7, segments=20, sprinkles=8, sprinkle_size=(0.45, 0.15, 0.13))
    a = ARROW
    h = a["h"]
    outline = [(a["x0"], -h / 2), (a["x1"] - a["head"], -h / 2), (a["x1"], 0), (a["x1"] - a["head"], h / 2),
               (a["x0"], h / 2)]
    front = a["y"] - a["t"]
    for k, (z, colour) in enumerate(ARROWS, start=1):
        plate(col, f"Arrow{k}", colour, [(u, v + z) for u, v in outline], (0, a["y"], 0), (0, -1, 0), a["t"],
              bevel=0.12, part=f"Arrow{k}")
        rounded_box(col, f"Icing{k}", "Cream", (1.65, a["t"] + 0.2, 0.36), (a["x0"] + 0.75, a["y"] - a["t"] / 2,
                                                                          z + h / 2 + 0.02), radius=0.15, segments=2)
        hang = drip_profile(1.6, [(0.35, 0.5, 0.55), (1.1, 0.45, 0.35)], base=0.15, seed=k)
        xs = [a["x0"] - 0.05 + 1.6 * i / 10 for i in range(11)]
        drip_curtain(col, f"IcingDrips{k}", [(x, front - 0.08, z + h / 2 - 0.05) for x in xs],
                     [hang(x - a["x0"]) for x in xs], [(0, -1, 0)] * len(xs), thickness=0.16)
        ball(col, f"Rivet{k}", "Gold", 0.16, (0, front - 0.02, z - 0.42), segments=8)
    SPECS["Signpost"] = dict(
        collision=[cyl(0.9, 13.0, name="Pole")],
        figure=(-4.6, -3.0),
        face=dict(size=[SIGN_TEXT["x1"] - SIGN_TEXT["x0"], SIGN_TEXT["z1"] - SIGN_TEXT["z0"]],
                  area=sign_area(), labels=SIGN_TEXT["labels"],
                  note="free front of each arrow between the icing and the rivet: x -0.5..3.5, z -0.22..0.62 from the "
                  "board's middle (Blender); boards at z 9.1, 7.3, 5.5"),
        note="Signpost_Arrow1_Pink, _Arrow2_SkyBlue, _Arrow3_Gold carry TextFace Front and a SurfaceGui Sign with the "
        "words SHOP, UPGRADES, ISLANDS (template script); turn an arrow about the pole (the model's Y axis in Roblox) "
        "to point it elsewhere",
    )


# Fountain: a cream step, a ring of cream wall tiles with pink and cream cap tiles, water in the basin, a plaque with
# the ice cream icon at the front, a cream pedestal and bowl with a pink glazed rim and water, a waffle cone with a
# glazed pink scoop and a cherry on top, two rings of water arcs with foam. 16.2 wide, 9.4 high.


def build_fountain():
    col = hk_collection("Fountain")
    cylinder(col, "Step", "Cream", 8.1, 0.45, 0, segments=32, bevel=0.15)
    tile_ring(col, "Wall", radius=7.0, count=16, depth=1.1, height=1.55, z0=0.45, colours=("Cream",), bevel=0.16)
    tile_ring(col, "Cap", radius=7.0, count=16, depth=1.35, height=0.42, z0=1.98, colours=("Pink", "Cream"),
              bevel=0.14)
    cylinder(col, "Floor", "Cream", 6.7, 0.6, 0.4, segments=32, bevel=0.0)
    cylinder(col, "Pool", "Water", 6.68, 0.45, 1.15, segments=32, bevel=0.08)
    rounded_box(col, "Plaque", "Cream", (2.7, 0.55, 1.9), (0, -7.62, 1.42), radius=0.18, segments=2)
    disc_n(col, "PlaqueTop", "Cream", 1.35, 0.55, (0, -7.62, 2.35), (0, -1, 0), segments=20, bevel=0.15)
    scoop_icon(col, "Icon", (0, -7.9, 1.75), (0, -1, 0), 1.35)
    lathe(col, "Pedestal", "Cream", [(0, 1.0), (1.5, 1.0), (1.5, 1.4), (1.0, 1.6), (0.75, 2.2), (0.75, 3.0),
                                     (1.1, 3.2), (0, 3.2)], segments=20)
    lathe(col, "Bowl", "Cream", [(0, 3.0), (1.0, 3.0), (2.2, 3.4), (3.3, 4.1), (3.4, 4.4), (0, 4.4)], segments=28)
    lathe(col, "Rim", "Pink", [(3.05, 4.15), (3.6, 4.15), (3.67, 4.38), (3.56, 4.6), (3.05, 4.6)], segments=28,
          closed=True, smooth=70)
    drip_skirt(col, "RimDrips", "Pink", 3.55, 4.36, drips=9, drop=(0.3, 0.9), width=(0.6, 1.1), thickness=0.26,
               seed=21)
    cylinder(col, "BowlWater", "Water", 3.1, 0.2, 4.3, segments=24, bevel=0.05)
    waffle_cone(col, "Cone", 0.55, 1.25, 1.9, 4.4, spacing=1.1, ridge=0.32, segments=20)
    iced_dome(col, "Scoop", "Pink", 1.6, 6.0, 6.6, 7.9, drips=6, drop=(0.3, 0.8), width=(0.5, 0.9), thickness=0.24,
              seed=22, segments=24, sprinkles=10, sprinkle_size=(0.55, 0.18, 0.15))
    cherry(col, "Cherry", (0, 0, 7.75), 0.45)
    upper, lower, foam = [], [], []
    for k in range(6):
        a = 2 * math.pi * k / 6
        c, s = math.cos(a), math.sin(a)
        upper.append(arc_points((1.5 * c, 1.5 * s, 6.45), (2.85 * c, 2.85 * s, 4.45), 0.45))
        foam.append(((2.85 * c, 2.85 * s, 4.5), 0.22))
        b = a - math.pi / 2
        c, s = math.cos(b), math.sin(b)
        lower.append(arc_points((3.65 * c, 3.65 * s, 4.35), (5.4 * c, 5.4 * s, 1.55), 0.55))
        for d, r in ((0, 0.34), (0.35, 0.24), (-0.35, 0.26)):
            foam.append(((5.4 * c - d * s, 5.4 * s + d * c, 1.62), r))
    _tube(col, "StreamsUpper", "Water", upper, 0.34, sides=6)
    _tube(col, "StreamsLower", "Water", lower, 0.46, sides=6)
    for i, (p, r) in enumerate(foam):
        ball(col, f"Foam{i}", "Cream", r, p, squash=0.7, segments=8)
    SPECS["Fountain"] = dict(
        collision=[cyl(7.6, 2.4, name="Basin"), cyl(3.6, 4.6, name="Bowl"), cyl(1.3, 9.0, name="Top")],
        figure=(-10.0, -6.0),
    )


# Barrel: a bulged faceted wooden barrel (16 staves) with two cream bands and the scoop medallion. The body is the part
# Body: Wood in the FBX, Pink and SkyBlue as variants. 2.9 wide, 3.3 high.


def build_barrel():
    col = hk_collection("Barrel")
    # improvement 1: a rounder belly and narrower ends (it read as a bucket)
    prof = [(0, 0), (0.98, 0), (1.07, 0.12), (1.3, 0.6), (1.46, 1.2), (1.51, 1.65), (1.46, 2.1), (1.3, 2.7),
            (1.07, 3.18), (0.98, 3.3), (0.86, 3.3), (0.86, 3.12), (0, 3.12)]
    lathe(col, "Body", "Wood", prof, segments=16, smooth=20, part="Body")
    for i, (z, rb) in enumerate(((0.6, 1.3), (2.7, 1.3))):
        lathe(col, f"Band{i}", "Cream", [(rb - 0.06, z - 0.2), (rb + 0.08, z - 0.2), (rb + 0.13, z), (rb + 0.08, z + 0.2),
                                         (rb - 0.06, z + 0.2)], segments=16, closed=True, smooth=20)
    medallion(col, "Badge", (0, -1.47, 1.65), (0, -1, 0), 0.62)
    SPECS["Barrel"] = dict(collision=[cyl(1.45, 3.3, name="Barrel")],
                           variants={"Pink": {"Body": "Pink"}, "Blue": {"Body": "SkyBlue"}}, figure=(-3.4, -2.2))


# Crate: a wooden frame with X braces on the sides and the top and gold rivets, the panels behind it. Frame and braces
# are the part Frame, the panels the part Panel: Wood and Waffle in the FBX; Pink and SkyBlue frames as variants, the
# panels stay Waffle (06.11.2026: on Cream panels the variants looked hollow, only the frame showed). 3 x 3 x 3.

CRATE = 3.0


def build_crate():
    col = hk_collection("Crate")
    S, b = CRATE, 0.5  # improvement 1: frame 0.5 (was 0.42), braces 0.6 wide (were 0.36): they read thin
    h = S / 2
    tag(rounded_box(col, "Panel", "Waffle", (S - 0.3, S - 0.3, S - 0.3), (0, 0, h), radius=0.1, segments=1), "Panel")
    e = h - b / 2
    for sx in (-1, 1):
        for sy in (-1, 1):
            tag(rounded_box(col, "EdgeV", "Wood", (b, b, S), (sx * e, sy * e, h), radius=0.1, segments=1), "Frame")
    for z in (b / 2, S - b / 2):
        for s in (-1, 1):
            tag(rounded_box(col, "EdgeX", "Wood", (S, b, b), (0, s * e, z), radius=0.1, segments=1), "Frame")
            tag(rounded_box(col, "EdgeY", "Wood", (b, S, b), (s * e, 0, z), radius=0.1, segments=1), "Frame")
    length = math.sqrt(2) * (S - 2 * b) + 0.1
    inset = h - 0.14
    for k in (-1, 1):
        for s in (-1, 1):
            ob = tag(rounded_box(col, "BraceXZ", "Wood", (length, 0.22, 0.6), (0, 0, 0), radius=0.06, segments=1),
                     "Frame")
            ob.rotation_euler = (0, k * math.pi / 4, 0)
            ob.location = (0, s * inset, h)
            ob = tag(rounded_box(col, "BraceYZ", "Wood", (0.22, length, 0.6), (0, 0, 0), radius=0.06, segments=1),
                     "Frame")
            ob.rotation_euler = (k * math.pi / 4, 0, 0)
            ob.location = (s * inset, 0, h)
        ob = tag(rounded_box(col, "BraceTop", "Wood", (length, 0.6, 0.22), (0, 0, 0), radius=0.06, segments=1),
                 "Frame")
        ob.rotation_euler = (0, 0, k * math.pi / 4)
        ob.location = (0, 0, S - 0.14)
    n = 0
    for sx in (-1, 1):
        for z in (b / 2, S - b / 2):
            for sy in (-1, 1):
                ball(col, f"RivetF{n}", "Gold", 0.13, (sx * e, sy * (h + 0.02), z), segments=8)
                ball(col, f"RivetS{n}", "Gold", 0.13, (sx * (h + 0.02), sy * e, z), segments=8)
                n += 1
    SPECS["Crate"] = dict(collision=[box((S, S, S), (0, 0, h), "Crate")],
                          variants={"Pink": {"Frame": "Pink"}, "Blue": {"Frame": "SkyBlue"}},
                          figure=(-3.4, -2.4))


# Harbor Gate: the locked gate to the candy harbour. Two wooden posts with pink bands and cream balls, two arched plank
# doors with a cream frame, pink bands and a gold padlock, above them the pink "COMING SOON" sign on two stubs with the
# scoop badge on top, flag poles with pink pennants and low rope fences out to short posts. 26.6 wide, 14.4 high, the
# doors 12.8 wide and 7.8 high in the middle. The collision closes it all.

GATE = dict(half=6.4, post_x=7.4, spring=6.0, rise=1.8, side_x=12.6, flag_x=9.9)


def door_top(x):
    g = GATE
    return g["spring"] + g["rise"] * math.sqrt(max(0.0, 1 - (x / g["half"]) ** 2))


def text_mesh(col, name, colour, body, size, center, extrude=0.07):
    """Lettering as a mesh, facing -Y, centred at center (built-in font, made bolder)."""
    curve = bpy.data.curves.new(name + "_text", "FONT")
    curve.body = body
    curve.size = size
    curve.extrude = extrude
    curve.offset = 0.035
    curve.bevel_depth = 0.02
    curve.bevel_resolution = 0
    curve.resolution_u = 4
    curve.space_line = 0.9
    for attr, value in (("align_x", "CENTER"), ("align_y", "CENTER")):
        try:
            setattr(curve, attr, value)
        except TypeError:
            pass
    tmp = bpy.data.objects.new(name + "_tmp", curve)
    col.objects.link(tmp)
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(deps), depsgraph=deps)
    bpy.data.objects.remove(tmp, do_unlink=True)
    bpy.data.curves.remove(curve)
    me.transform(Matrix.Translation(Vector(center)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    me.name = name
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    me.materials.clear()
    me.materials.append(material(colour))
    return ob


def build_harbor_gate():
    col = hk_collection("HarborGate")
    g = GATE
    # the doors: eight planks under one arch, a cream frame, pink bands, the padlock
    planks = 8
    w = 2 * g["half"] / planks
    for i in range(planks):
        x0, x1 = -g["half"] + i * w + 0.04, -g["half"] + (i + 1) * w - 0.04
        top = [(x1 - (x1 - x0) * t / 3, door_top(x1 - (x1 - x0) * t / 3) - 0.1) for t in range(4)]
        plate(col, f"Plank{i}", "Wood", [(x0, 0.2), (x1, 0.2)] + top, (0, 0.25, 0), (0, -1, 0), 0.5, bevel=0.07)
    xs = [-g["half"] - 0.1 + (2 * g["half"] + 0.2) * i / 24 for i in range(25)]
    _tube(col, "Arch", "Cream", [[(x, -0.32, door_top(max(-g["half"], min(g["half"], x))) - 0.05) for x in xs]], 0.5,
          sides=6)
    for sx in (-1, 1):
        rounded_box(col, "Stile", "Cream", (0.55, 0.75, 6.1), (sx * 6.55, -0.05, 3.05), radius=0.15, segments=1)
    rounded_box(col, "Seam", "Cream", (0.38, 0.62, 7.55), (0, -0.05, 3.9), radius=0.12, segments=1)
    rounded_box(col, "Sill", "Stone", (13.4, 1.6, 0.25), (0, 0, 0.12), radius=0.1, segments=1)
    for z in (1.4, 3.6):
        rounded_box(col, "Band", "Pink", (12.9, 0.3, 0.55), (0, -0.42, z), radius=0.12, segments=2)
    rounded_box(col, "Lock", "Gold", (1.2, 0.55, 1.05), (0, -0.85, 3.4), radius=0.18, segments=2)
    shackle = [(0.38 * math.cos(a), -0.85, 3.9 + 0.38 * math.sin(a)) for a in [math.pi * i / 10 for i in range(11)]]
    _tube(col, "Shackle", "Gold", [[(0.38, -0.85, 3.75)] + shackle + [(-0.38, -0.85, 3.75)]], 0.2, sides=6)
    disc_n(col, "Keyhole", "Choco", 0.14, 0.1, (0, -1.13, 3.5), (0, -1, 0), segments=10, bevel=0.0)
    rounded_box(col, "KeySlot", "Choco", (0.1, 0.08, 0.26), (0, -1.15, 3.32), radius=0.03, segments=1)
    # the posts
    for sx in (-1, 1):
        x = sx * g["post_x"]
        rounded_box(col, "PostFoot", "Cream", (2.2, 2.2, 0.7), (x, 0, 0.35), radius=0.22, segments=2)
        rounded_box(col, "Post", "Wood", (1.6, 1.6, 8.0), (x, 0, 4.7), radius=0.2, segments=2)
        for z in (1.5, 7.6):
            rounded_box(col, "PostBand", "Pink", (1.85, 1.85, 0.45), (x, 0, z), radius=0.15, segments=1)
        rounded_box(col, "PostCap", "Cream", (2.05, 2.05, 0.5), (x, 0, 8.95), radius=0.18, segments=2)
        ball(col, "PostBall", "Cream", 0.85, (x, 0, 9.95), segments=14)
    # the sign on two stubs, the badge on top
    for sx in (-1, 1):
        rounded_box(col, "Stub", "Wood", (0.45, 0.45, 2.1), (sx * 2.6, 0.0, 8.35), radius=0.1, segments=1)
    plate(col, "SignBack", "Cream", stadium(9.1, 3.9, 10), (0, 0.15, 10.6), (0, -1, 0), 0.35, bevel=0.1)
    plate(col, "Sign", "Pink", stadium(8.6, 3.4, 10), (0, -0.15, 10.6), (0, -1, 0), 0.25, bevel=0.08)
    text_mesh(col, "Text", "Cream", "COMING\nSOON", 1.3, (0, -0.42, 10.6))
    medallion(col, "Badge", (0, -0.45, 13.2), (0, -1, 0), 1.25)  # improvement 1: in front of the sign
    # flags and rope fences
    for sx in (-1, 1):
        x = sx * g["flag_x"]
        cylinder(col, "FlagFoot", "Cream", 0.55, 0.4, 0, center=(x, 0.8), segments=12, bevel=0.12)
        cylinder(col, "FlagPole", "Wood", 0.22, 13.6, 0.3, center=(x, 0.8), segments=10, bevel=0.06)
        cylinder(col, "FlagBand", "Pink", 0.3, 0.35, 3.0, center=(x, 0.8), segments=10, bevel=0.1)
        ball(col, "FlagBall", "Gold", 0.45, (x, 0.8, 14.0), segments=12)
        plate(col, "Flag", "Pink", [(sx * 0.15, -1.1), (sx * 3.3, 0.0), (sx * 0.15, 1.1)], (x, 0.88, 12.2),
              (0, -1, 0), 0.16, bevel=0.05)
        scoop_icon(col, "FlagIcon", (x + sx * 1.15, 0.7, 12.25), (0, -1, 0), 0.75, scoop="Cream")
        xs_ = sx * g["side_x"]
        rounded_box(col, "SideFoot", "Cream", (1.5, 1.5, 0.5), (xs_, 0, 0.25), radius=0.15, segments=1)
        rounded_box(col, "SidePost", "Wood", (1.0, 1.0, 4.2), (xs_, 0, 2.55), radius=0.15, segments=1)
        rounded_box(col, "SideBand", "Pink", (1.2, 1.2, 0.35), (xs_, 0, 3.6), radius=0.1, segments=1)
        rounded_box(col, "SideCap", "Cream", (1.3, 1.3, 0.4), (xs_, 0, 4.85), radius=0.12, segments=1)
        ball(col, "SideBall", "Cream", 0.55, (xs_, 0, 5.5), segments=12)
        ropes = [arc_points((sx * 8.2, 0, 5.6), (sx * 12.1, 0, 4.4), -0.6),
                 arc_points((sx * 8.2, 0, 2.8), (sx * 12.1, 0, 2.4), -0.4)]
        _tube(col, "Rope", "Cream", ropes, 0.32, sides=6)
    SPECS["HarborGate"] = dict(
        collision=[box((17.0, 1.6, 9.0), (0, 0, 4.5), "Gate"),
                   box((4.85, 1.6, 5.0), (-10.925, 0.3, 2.5), "FenceL"),
                   box((4.85, 1.6, 5.0), (10.925, 0.3, 2.5), "FenceR")],
        figure=(-4.0, -4.5),
        note="locked: the collision closes doors, posts and rope fences; the lettering is geometry "
        "(HarborGate_Cream holds it), no SurfaceGui needed",
    )




# --------------------------------------------------------------------------------------------------------------------
# Filler buildings (06.11.2026, preview only, not placed yet): small houses in the same candy style between the
# decoration. The big shops (upgrade, cosmetic, quest) get their own references later.
# Colours after 60/30/10 (user, 06.11.2026): walls Cream, roof and plinth muted (Stone, Wood), strong colour only on
# the awning, the sign and small accents (cushions, the swirl). Pink is used for those accents only, so Studio can give
# the MeshPart <Model>_Pink the flavour of the sector it stands in.


def stripe_awning(col, name, length, depth, back_z, front_z, stripes, center_y=0.0, colours=("Pink", "Cream")):
    """A striped awning from back_z (at +Y) to front_z (at -Y), `stripes` stripes along X in turn, with a scalloped
    valance on the front edge (like the plot kit awning, with disc_n)."""
    w = length / stripes
    ya, yb = center_y - depth / 2, center_y + depth / 2
    run = math.hypot(yb - ya, back_z - front_z)
    for i in range(stripes):
        x = -length / 2 + w * (i + 0.5)
        ob = rounded_box(col, f"{name}_Stripe{i}", colours[i % 2], (w + 0.02, run, 0.3), (0, 0, 0), radius=0.1,
                         segments=2)
        ob.rotation_euler = (math.atan2(back_z - front_z, yb - ya), 0, 0)
        ob.location = (x, (ya + yb) / 2, (front_z + back_z) / 2)
        disc_n(col, f"{name}_Scallop{i}", colours[i % 2], w * 0.5, 0.28, (x, ya - 0.05, front_z - 0.25), (0, -1, 0),
               segments=14, bevel=0.1)


def iced_roof(col, name, length, depth, top, colour="Pink", seed=1):
    """A flat roof: a rounded slab in `colour` with the cream glaze and its drips on top (top at `top`)."""
    rounded_box(col, name + "_Slab", colour, (length, depth, 0.7), (0, 0, top - 0.75), radius=0.3, segments=2)
    glaze(col, name + "_Glaze", length - 0.2, depth - 0.2, top, thickness=0.45, seed=seed)


# Ice Kiosk: a small cream booth on a pink plinth, a serving window with a waffle counter (3.0 high, a figure looks
# over it from the chest up) under a striped awning, a glazed pink roof and a giant soft serve on a waffle cone on
# top. 7 x 6, about 13.5 high.


def build_ice_kiosk():
    col = hk_collection("IceKiosk")
    rounded_box(col, "Plinth", "Wood", (7.0, 6.0, 0.45), (0, 0, 0.225), radius=0.18, segments=2)
    rounded_box(col, "Body", "Cream", (6.4, 5.4, 6.1), (0, 0, 0.45 + 3.05), radius=0.35, segments=2)
    waffle_panel(col, "Front", (6.0, 0.3, 2.4), (0, -2.75, 1.65), spacing=1.2, ridge_width=0.4, faces=("front",))
    rounded_box(col, "Counter", "Waffle", (6.8, 1.3, 0.45), (0, -3.1, 3.0), radius=0.15, segments=2)
    rounded_box(col, "Window", "Choco", (5.2, 0.12, 2.2), (0, -2.72, 4.45), radius=0.05, segments=1)
    for k, x in enumerate((-1.6, 0, 1.6)):
        ball(col, f"Scoop{k}", ("Pink", "SkyBlue", "Cream")[k], 0.45, (x, -3.1, 3.6), segments=12)
    stripe_awning(col, "Awning", 7.0, 2.2, 6.75, 6.1, 6, center_y=-3.4)
    iced_roof(col, "Roof", 7.2, 6.2, 7.3, colour="Stone", seed=4)
    waffle_cone(col, "Cone", 0.7, 1.7, 2.5, 7.3, spacing=1.1, ridge=0.34, segments=20)
    soft_serve(col, "Swirl", "Pink", 2.0, 9.6, tiers=3)
    for sx in (-1, 1):
        cone_emblem(col, f"Emblem{sx}", (sx * 3.22, 0, 3.9), (sx, 0, 0), width=1.8, height=2.4)
    SPECS["IceKiosk"] = dict(collision=[box((7.0, 6.0, 7.3), (0, 0, 3.65), "Kiosk")], figure=(-5.6, -5.0),
                             note="serving window at the front (-Z in Roblox), counter top 3.0")


# Cafe: a cream house with a pink plinth, two big windows (Glass) and a door, a striped awning over the terrace, a
# glazed pink roof with the sign "CAFE" on top; in front two small round tables with two stools each (seats).
# 12 wide, 11 deep with the terrace, about 10.5 high.

CAFE_TABLES = [(-3.2, -6.4), (3.2, -6.4)]


def build_cafe():
    col = hk_collection("Cafe")
    rounded_box(col, "Plinth", "Wood", (12.0, 7.0, 0.5), (0, 0, 0.25), radius=0.2, segments=2)
    rounded_box(col, "Body", "Cream", (11.4, 6.4, 6.6), (0, 0, 0.5 + 3.3), radius=0.35, segments=2)
    waffle_panel(col, "Base", (11.0, 0.3, 1.4), (0, -3.25, 1.2), spacing=1.2, ridge_width=0.4, faces=("front",))
    for x in (-3.4, 3.4):
        rounded_box(col, f"Frame{x}", "Waffle", (3.6, 0.3, 2.9), (x, -3.22, 3.75), radius=0.12, segments=1)
        rounded_box(col, f"Glass{x}", "Glass", (3.0, 0.2, 2.3), (x, -3.32, 3.75), radius=0.05, segments=1)
    rounded_box(col, "Door", "Choco", (1.9, 0.22, 3.9), (0, -3.28, 2.45), radius=0.12, segments=1)
    ball(col, "Knob", "Gold", 0.15, (0.6, -3.42, 2.5), segments=8)
    stripe_awning(col, "Awning", 11.6, 2.6, 6.6, 5.8, 8, center_y=-4.4)
    iced_roof(col, "Roof", 12.0, 7.0, 7.9, colour="Stone", seed=7)
    plate(col, "Sign", "Pink", stadium(6.4, 1.9), (0, -1.0, 9.15), (0, -1, 0), 0.35, bevel=0.12)
    text_mesh(col, "SignText", "Cream", "CAFE", 1.3, (0, -1.4, 9.15))
    for sx in (-2.6, 2.6):
        rounded_box(col, f"SignLeg{sx}", "Waffle", (0.35, 0.35, 1.3), (sx, -0.8, 8.25), radius=0.1, segments=1)
    seats, collision = [], [box((12.0, 7.0, 7.9), (0, 0, 3.95), "House")]
    for t, (x, y) in enumerate(CAFE_TABLES):
        cylinder(col, f"TableFoot{t}", "Cream", 0.5, 2.3, 0, center=(x, y), segments=16, radius_top=0.3)
        cylinder(col, f"Table{t}", "Wood", 1.3, 0.3, 2.3, center=(x, y), segments=24, bevel=0.1)
        cylinder(col, f"TableRim{t}", "Pink", 1.35, 0.12, 2.25, center=(x, y), segments=24, bevel=0.04)
        collision.append(cyl(1.3, 2.6, (x, y), name=f"Table{t}"))
        for s, sx in enumerate((-1, 1)):
            cx = x + sx * 2.1
            cylinder(col, f"Stool{t}{s}", "Cream", 0.5, 1.6, 0, center=(cx, y), segments=14, radius_top=0.4)
            cylinder(col, f"Cushion{t}{s}", "Pink", 0.62, 0.35, 1.6, center=(cx, y), segments=16, bevel=0.15)
            collision.append(cyl(0.6, 1.95, (cx, y), name=f"Stool{t}{s}"))
            seats.append(dict(at=[cx, y, 1.95], look=[x, y, 1.95]))
    SPECS["Cafe"] = dict(collision=collision, seats=seats, figure=(-8.0, -8.0),
                         note="two tables with two stools each on the terrace in front (-Z in Roblox)")


# Pavilion: a round open gazebo, a cream floor with a pink rim (one low step), six waffle columns, a striped pink and
# cream dome with a gold ball and a cherry on top, a round bench in the middle. 11.6 wide, about 10.5 high.


def build_pavilion():
    col = hk_collection("Pavilion")
    cylinder(col, "Rim", "Wood", 5.5, 0.3, 0, segments=36, bevel=0.1)
    cylinder(col, "Floor", "Cream", 5.2, 0.45, 0, segments=36, bevel=0.12)
    collision = [cyl(5.5, 0.45, name="Floor")]
    for k in range(6):
        a = 2 * math.pi * k / 6 + math.pi / 6
        c = (4.4 * math.cos(a), 4.4 * math.sin(a))
        waffle_cylinder(col, f"Column{k}", 0.42, 5.6, 0.45, center=c, spacing=1.0, ridge=0.28, segments=14)
        cylinder(col, f"Cap{k}", "Gold", 0.6, 0.35, 6.05, center=c, segments=14, bevel=0.1)
        collision.append(cyl(0.5, 6.4, c, name=f"Column{k}"))
    cylinder(col, "Beam", "Cream", 5.0, 0.45, 6.35, segments=36, bevel=0.15)
    drip_skirt(col, "BeamDrips", "Cream", 4.95, 6.5, drips=12, drop=(0.3, 0.8), width=(0.5, 0.9), thickness=0.22,
               seed=21)
    canopy(col, "Roof", 5.8, 9.4, 6.6, panels=12, colours=("Stone", "Cream"))
    ball(col, "Finial", "Gold", 0.45, (0, 0, 9.6), segments=12)
    cherry(col, "Cherry", (0, 0, 10.05), r=0.4)
    cylinder(col, "Bench", "Wood", 1.6, 1.4, 0.45, segments=24, bevel=0.15)
    cylinder(col, "BenchTop", "Pink", 1.75, 0.3, 1.8, segments=24, bevel=0.12)
    collision.append(cyl(1.75, 2.1, name="Bench"))
    seats = [dict(at=[1.9 * math.cos(a), 1.9 * math.sin(a), 2.1], look=[3.0 * math.cos(a), 3.0 * math.sin(a), 2.1])
             for a in (math.pi / 2, math.pi * 3 / 2)]
    SPECS["Pavilion"] = dict(collision=collision, seats=seats, figure=(-8.0, -6.0),
                             note="open all round between the columns; the floor is one 0.45 step")


# Cart Garage: where the ice cream carts sleep. A waffle-walled garage with a big pink and cream roll door (8 wide,
# 5.5 high), a cream frame, a glazed pink roof with a cone sign and a soft serve, a pink step. 12 x 9, about 11 high.


def build_cart_garage():
    col = hk_collection("CartGarage")
    rounded_box(col, "Plinth", "Wood", (12.0, 9.0, 0.4), (0, 0, 0.2), radius=0.18, segments=2)
    for sx in (-1, 1):
        # built facing -Y, then turned so the lattice faces out to the side
        for ob in waffle_panel(col, f"Wall{sx}", (8.4, 0.6, 6.6), (0, 0, 0.4 + 3.3), spacing=1.4, ridge_width=0.45,
                               faces=("front", "back")):
            ob.rotation_euler = (0, 0, math.pi / 2)
            ob.location = (sx * 5.6, 0, 0)
    rounded_box(col, "Back", "Cream", (11.2, 0.6, 6.6), (0, 4.0, 3.7), radius=0.25, segments=2)
    rounded_box(col, "Lintel", "Cream", (11.8, 0.9, 1.3), (0, -4.0, 6.4), radius=0.3, segments=2)
    for sx in (-1, 1):
        rounded_box(col, f"Jamb{sx}", "Cream", (1.4, 0.9, 5.7), (sx * 4.8, -4.0, 0.4 + 2.85), radius=0.25, segments=2)
    for i in range(10):
        rounded_box(col, f"Slat{i}", ("Stone", "Cream")[i % 2], (8.2, 0.3, 0.55), (0, -3.85, 0.7 + 0.55 * i),
                    radius=0.12, segments=1)
    rounded_box(col, "Handle", "Gold", (1.6, 0.25, 0.25), (0, -4.08, 1.3), radius=0.1, segments=1)
    iced_roof(col, "Roof", 12.2, 9.2, 7.9, colour="Stone", seed=9)
    # improvement 1: on the roll door, bigger; over the door the roof drips hid it
    cone_emblem(col, "Emblem", (0, -4.05, 3.9), (0, -1, 0), width=1.9, height=2.5)
    waffle_cone(col, "Cone", 0.55, 1.35, 2.0, 7.9, spacing=1.0, ridge=0.3, segments=18)
    soft_serve(col, "Swirl", "SkyBlue", 1.6, 9.75, tiers=3)
    SPECS["CartGarage"] = dict(collision=[box((12.0, 9.0, 7.9), (0, 0, 3.95), "Garage")], figure=(-8.0, -6.5),
                               note="the roll door is closed (no inside); front -Z in Roblox")



# Bridge (07.11.2026, reference "Verspielte Eiscreme-Inselbrücke"): two modules for the 12 bridges, 18 wide. An end
# piece (9 long, its first 3 lie on the land, its front -Y faces the land) with the big post at the water's edge, and a
# middle piece (12 long) with a small post in its middle: end + 4 x middle + end (turned round) = 66, as Mosty
# (r 229-295). Wooden planks, Cream rail and balusters, Caramel posts and side beams, Choco piles down into the water;
# the flavour only on the post caps (the part Cap, Pink in the FBX, recoloured per bridge in Studio). The deck is flat
# (the user allowed a slight arch at most): the modules repeat and the walking collision Pomost_Kolizja stays flat and
# unchanged. Origin: the middle of the deck top (z 0 is the walking surface, y 9.02 in the place). The posts stand 12
# apart all along the bridge. Collision only on the railings (the deck is Pomost_Kolizja).

BRIDGE = dict(width=18.0, mid=12.0, end=9.0, land=3.0, pitch=1.5, rail_x=8.35, rail_top=3.5, pile_bottom=-19.0,
              collision_top=4.4)


def bridge_deck(col, y0, y1):
    """Planks across the bridge from y0 to y1 (tops at z 0) on two Caramel side beams."""
    n = round((y1 - y0) / BRIDGE["pitch"])
    p = (y1 - y0) / n
    for i in range(n):
        off = (0.1, -0.08, 0.04, -0.12)[i % 4]  # the plank ends do not line up exactly
        rounded_box(col, f"Plank{i}", "Wood", (17.7, p - 0.16, 0.5), (off, y0 + p * (i + 0.5), -0.25), radius=0.12,
                    segments=1)
    for sx in (-1, 1):
        rounded_box(col, f"Beam{sx}", "Caramel", (1.0, y1 - y0, 1.4), (sx * 8.4, (y0 + y1) / 2, -1.1), radius=0.2,
                    segments=1)


def bridge_post(col, name, y, big):
    """A Caramel post on each side with its flavour cap; the big ones (at the water's edge) carry a Cream ball."""
    s, h = (1.7, 4.3) if big else (1.15, 3.75)
    rx = BRIDGE["rail_x"] - (0.1 if big else 0)
    for sx in (-1, 1):
        rounded_box(col, f"{name}{sx}", "Caramel", (s, s, h), (sx * rx, y, h / 2), radius=0.18, segments=2)
        tag(rounded_box(col, f"{name}Cap{sx}", "Pink", (s + 0.4, s + 0.4, 0.55), (sx * rx, y, h + 0.2), radius=0.2,
                        segments=2), "Cap")
        if big:
            ball(col, f"{name}Ball{sx}", "Cream", 0.72, (sx * rx, y, h + 1.15), segments=16)


def bridge_rail(col, y0, y1, balusters):
    top = BRIDGE["rail_top"]
    for sx in (-1, 1):
        x = sx * BRIDGE["rail_x"]
        rounded_box(col, f"Rail{sx}", "Cream", (0.75, y1 - y0, 0.55), (x, (y0 + y1) / 2, top - 0.275), radius=0.25,
                    segments=2)
        for i, y in enumerate(balusters):
            rounded_box(col, f"Baluster{sx}_{i}", "Cream", (0.42, 0.42, top - 0.3), (x, y, (top - 0.3) / 2),
                        radius=0.12, segments=1)


def bridge_piles(col, y):
    """Two Choco piles under the posts at y, from under the deck into the water, with a cross beam."""
    z0, z1 = BRIDGE["pile_bottom"], -1.8
    for sx in (-1, 1):
        cylinder(col, f"Pile{sx}", "Choco", 0.6, z1 - z0, z0, center=(sx * 7.6, y), segments=12, bevel=0.1)
    rounded_box(col, "CrossBeam", "Choco", (16.4, 0.8, 0.8), (0, y, -2.2), radius=0.2, segments=1)


def bridge_rail_collision(y0, y1):
    h = BRIDGE["collision_top"]
    return [box((1.8, y1 - y0, h), (sx * BRIDGE["rail_x"], (y0 + y1) / 2, h / 2), f"Rail{'L' if sx < 0 else 'R'}")
            for sx in (-1, 1)]


def build_bridge_mid():
    col = hk_collection("BridgeMid")
    half = BRIDGE["mid"] / 2
    bridge_deck(col, -half, half)
    bridge_post(col, "Post", 0, big=False)
    bridge_rail(col, -half, half, (-5.25, -3.75, -2.25, 2.25, 3.75, 5.25))
    bridge_piles(col, 0)
    SPECS["BridgeMid"] = dict(collision=bridge_rail_collision(-half, half), figure=(0, -3.0),
                              note="12 long; the origin is the middle of the deck top; flavour on the part Cap")


def build_bridge_end():
    col = hk_collection("BridgeEnd")
    half = BRIDGE["end"] / 2
    edge = -half + BRIDGE["land"]  # the water's edge: the land lies at -Y
    post_y = edge + 0.75
    bridge_deck(col, -half, half)
    bridge_post(col, "Post", post_y, big=True)
    bridge_rail(col, post_y, half, (post_y + 1.5, post_y + 3.0, post_y + 4.5))
    bridge_piles(col, post_y)
    SPECS["BridgeEnd"] = dict(collision=bridge_rail_collision(post_y - 0.9, half), figure=(0, -3.6),
                              note="9 long, the first 3 (at -Z in Roblox) lie on the land; origin the middle of the "
                                   "deck top; flavour on the part Cap")


def bridge_preview():
    """The whole bridge (end, 4 middles, end turned round) between two pieces of land over water, with figures:
    previews/Bridge.png (front, three quarter, top) and Bridge_Eye.png (a player's view from the ring)."""
    clear_preview()
    pc = preview_collection()
    made = []
    end, mid = BRIDGE["end"], BRIDGE["mid"]
    pieces = [("BridgeEnd", end / 2, 0)] + [("BridgeMid", end + mid * (i + 0.5), 0) for i in range(4)]
    pieces.append(("BridgeEnd", end + 4 * mid + end / 2, math.pi))
    for name, y, turn in pieces:
        for ob in bpy.data.collections["HK_" + name].all_objects:
            if ob.type != "MESH":
                continue
            c = ob.copy()
            c.data = ob.data.copy()
            c.matrix_world = Matrix.Translation((0, y, 0)) @ Matrix.Rotation(turn, 4, "Z") @ ob.matrix_world
            if ob.get("part") == "Cap":
                c.data.materials[0] = material("Leaf")  # a flavour (Mint-ish) instead of the FBX Pink
            pc.objects.link(c)
            made.append(c)
    total = 2 * end + 4 * mid
    land = _flat_material("HK_Land", "#FFE9D0", roughness=0.7)
    water = _flat_material("HK_Water", "#4CC3F0", roughness=0.2)
    made.append(_preview_box(pc, "Ring", land, (40, 14, 15), (0, -14 / 2 + BRIDGE["land"], -7.5)))
    made.append(_preview_box(pc, "Island", land, (40, 14, 15), (0, total + 14 / 2 - BRIDGE["land"], -7.5)))
    _preview_box(pc, "Water", water, (60, total + 40, 0.2), (0, total / 2, -15.1))
    figure(-3.0, 20.0, facing=1, scoops=20)
    figure(3.5, 41.0, facing=-1, scoops=8, name="Figure2")
    special_materials()
    render_preview([], "Bridge", extra=made)
    render_eye([], "Bridge_Eye", eye=(-4.0, -9.0, 5.2), target=(1.0, 30.0, 2.0), lens=22)
    clear_preview()


BUILDERS = {
    "IceTree": build_ice_tree,
    "FlowerBush": build_flower_bush,
    "Rock": build_rock,
    "Lantern": build_lantern,
    "WafflePlanter": build_waffle_planter,
    "ParkBench": build_park_bench,
    "PicnicTable": build_picnic_table,
    "TrashBin": build_trash_bin,
    "Signpost": build_signpost,
    "Fountain": build_fountain,
    "Barrel": build_barrel,
    "Crate": build_crate,
    "HarborGate": build_harbor_gate,
    "IceKiosk": build_ice_kiosk,
    "Cafe": build_cafe,
    "Pavilion": build_pavilion,
    "CartGarage": build_cart_garage,
    "BridgeEnd": build_bridge_end,
    "BridgeMid": build_bridge_mid,
}


# --------------------------------------------------------------------------------------------------------------------
# preview, export, report


def preview_variants(name, variants, step):
    """Copies of the model next to it (preview only), each variant's parts in its colours."""
    src = bpy.data.collections["HK_" + name]
    pc = preview_collection()
    made = []
    for k, (vname, recolour) in enumerate(variants.items(), start=1):
        for ob in src.all_objects:
            if ob.type != "MESH":
                continue
            c = ob.copy()
            c.data = ob.data.copy()
            c.location.x += step * k
            if ob.get("part") in recolour:
                c.data.materials[0] = material(recolour[ob["part"]])
            pc.objects.link(c)
            made.append(c)
    return made


def finish(name):
    spec = SPECS.get(name, {})
    stats = model_stats(name)
    lo, hi = stats["min"], stats["max"]
    if spec.get("collision") == "auto":
        sx, sy, sz = (hi[0] - lo[0]) * 0.85, (hi[1] - lo[1]) * 0.85, (hi[2] - lo[2]) * 0.9
        spec["collision"] = [box((sx, sy, sz), ((hi[0] + lo[0]) / 2, (hi[1] + lo[1]) / 2, sz / 2), name=name)]
    path, meshes, tris = export_model(name)
    clear_preview()
    if "variants" in spec:
        step = hi[0] - lo[0] + 2.0
        preview_variants(name, spec["variants"], step)
        hi = [lo[0] + step * (len(spec["variants"]) + 1) - 2.0, hi[1], hi[2]]
    fx, fy = spec.get("figure", (lo[0] - 2.2, lo[1] - 1.0))
    figure(fx, fy, facing=1, scoops=20)
    ground(size=(hi[0] - lo[0] + 14, hi[1] - lo[1] + 14), center=((hi[0] + lo[0]) / 2, (hi[1] + lo[1]) / 2))
    special_materials()
    body = [ob for ob in preview_collection().all_objects if "Scoop" not in ob.name and ob.name != "Ground"]
    picture = render_preview([name], name, extra=body)
    stats.update(fbx=path, meshes=meshes, exported_triangles=tris, preview=picture)
    stats.update({k: v for k, v in spec.items() if k != "figure"})
    write_report(name, stats)
    print(name, stats["size"], stats["triangles"], "triangles")


# --------------------------------------------------------------------------------------------------------------------
# the Studio template script, written from hubkit_models.json: Blender (x, y, z) is Roblox (-x, z, y), measured on
# the plot kit's import (assets/PlotKit/studio_plotkit_templates.luau)


def _rb(v):
    return (-v[0], v[2], v[1])


def _v3(v):
    return "Vector3.new({})".format(", ".join(f"{round(c, 3) + 0:g}" for c in v))


LUAU_HEAD = """--!nocheck
-- Turns imported hub kit models into templates (Edit mode, command bar or Studio MCP): every Model in Workspace named
-- HubKit_<Model> (as the 3D importer names HubKit_<Model>.fbx from assets/HubKit/fbx, assets/HubKit/README.md).
--   * each MeshPart <Model>_<Colour> (and <Model>_<Part>_<Colour>) gets its game colour, the attribute Colour,
--     SmoothPlastic, Anchored, and neither collides nor takes queries or touches. Lamp glass is Neon with a
--     PointLight, Water and Glass are see-through. Signpost arrows (_Arrow) get the attribute TextFace = "Front" and a SurfaceGui Sign with
--     their word (SIGNS).
--   * the model gets the simple collision of COLLISION: invisible Parts `Collision` (the first, the PrimaryPart) and
--     `Collision_<Name>`; benches and stools get invisible Seats (SEATS). The pivot stays at the bottom centre.
--   * the import moves to ServerStorage.HubKit.<Model>; VARIANTS add recoloured copies <Model>_<Variant> (a template
--     there is replaced). Safe to repeat after a fresh import.
-- GENERATED by assets/HubKit/build_hub_pack.py from hubkit_models.json: change the Blender build, not this file.
-- Coordinates are Roblox studs in the model's frame (x right, y up, the front at -Z), from the pivot.
"""

LUAU_BODY = """
local SS = game:GetService("ServerStorage")
local folder = SS:FindFirstChild("HubKit") or Instance.new("Folder")
folder.Name = "HubKit"
folder.Parent = SS

local function invisible(name, cframe, size, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cframe
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local UP = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis (X) pointing up

-- a SurfaceGui "Sign" on the part's Front face with one word in the field (fractions of the face)
local function makeSign(part, area, word)
	local old = part:FindFirstChild("Sign")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.6
	local label = Instance.new("TextLabel")
	label.Name = "Word"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(area[1], area[3])
	label.Size = UDim2.fromScale(area[2] - area[1], area[4] - area[3])
	label.FontFace = Font.fromEnum((Enum.Font :: any)[require(game:GetService("ReplicatedStorage").Shared.Config.Ui).fonts.main]) -- the main font (Config/Ui.fonts)
	label.Text = word
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex(GAME_COLOURS.Choco)
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = part
end

local function recolour(model, partName, colour)
	for _, part in model:GetDescendants() do
		if part:IsA("MeshPart") and part.Name:find("_" .. partName .. "_", 1, true) then
			part.Color = Color3.fromHex(GAME_COLOURS[colour])
			part:SetAttribute("Colour", colour)
		end
	end
end

local report = {}
for _, model in workspace:GetChildren() do
	if not (model:IsA("Model") and model.Name:sub(1, 7) == "HubKit_") then
		continue
	end
	local name = model.Name:sub(8)
	local pivot = model:GetPivot()
	local coloured, lights, signs, unknown = 0, 0, 0, {}
	for _, part in model:GetDescendants() do
		if part:IsA("MeshPart") then
			local colour = part.Name:match("_(%a+)$")
			local hex = colour and GAME_COLOURS[colour]
			if hex then
				part.Color = Color3.fromHex(hex)
				part:SetAttribute("Colour", colour)
				coloured += 1
			else
				table.insert(unknown, part.Name)
			end
			part.Material = if colour == "Lamp" then Enum.Material.Neon else Enum.Material.SmoothPlastic
			part.Transparency = if colour == "Water"
				then WATER_TRANSPARENCY
				elseif colour == "Glass" then GLASS_TRANSPARENCY
				else 0
			part.CastShadow = colour ~= "Lamp" and colour ~= "Water"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			if colour == "Lamp" and not part:FindFirstChildOfClass("PointLight") then
				local light = Instance.new("PointLight")
				light.Color = LIGHT.colour
				light.Brightness = LIGHT.brightness
				light.Range = LIGHT.range
				light.Enabled = LIGHT.enabled
				light.Shadows = false
				light.Parent = part
				lights += 1
			end
			if part.Name:find("_Arrow", 1, true) then
				part:SetAttribute("TextFace", "Front")
				local index = tonumber(part.Name:match("_Arrow(%d+)_"))
				local sign = SIGNS[name]
				if sign and index and sign.labels[index] then
					makeSign(part, sign.area, sign.labels[index])
					signs += 1
				end
			end
		end
	end
	for _, old in model:GetChildren() do
		if old:IsA("BasePart") and (old.Name:sub(1, 9) == "Collision" or old:IsA("Seat")) then
			old:Destroy()
		end
	end
	local primary
	for i, spec in COLLISION[name] or {} do
		local at = pivot * CFrame.new(spec.centre)
		local part
		if spec.kind == "cylinder" then
			part = invisible("Collision", at * UP, spec.size, Enum.PartType.Cylinder)
		else
			part = invisible("Collision", at, spec.size)
		end
		if i > 1 then
			part.Name = "Collision_" .. (spec.name or tostring(i))
		end
		part.Parent = model
		primary = primary or part
	end
	for i, s in SEATS[name] or {} do
		local seat = Instance.new("Seat")
		seat.Name = "Seat" .. i
		seat.Size = Vector3.new(2, 0.2, 2)
		local at = (pivot * CFrame.new(s.at)).Position
		local look = (pivot * CFrame.new(s.look)).Position
		seat.CFrame = CFrame.lookAt(at, look) * CFrame.new(0, -0.1, 0)
		seat.Transparency = 1
		seat.Anchored = true
		seat.CanCollide = false
		seat.CanQuery = false
		seat.CanTouch = true
		seat.Parent = model
	end
	if primary then
		model.PrimaryPart = primary
		primary.PivotOffset = primary.CFrame:ToObjectSpace(pivot)
	else
		model.WorldPivot = pivot
	end
	local old = folder:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	model:PivotTo(CFrame.new()) -- the template stands at the origin, upright, its front to -Z
	model.Name = name
	model.Parent = folder
	local variants = {}
	for variant, parts in VARIANTS[name] or {} do
		local copyName = name .. "_" .. variant
		local previous = folder:FindFirstChild(copyName)
		if previous then
			previous:Destroy()
		end
		local copy = model:Clone()
		copy.Name = copyName
		for partName, colour in parts do
			recolour(copy, partName, colour)
		end
		copy.Parent = folder
		table.insert(variants, copyName)
	end
	table.insert(
		report,
		`{name}: {coloured} meshes coloured{#unknown > 0 and " (no colour: " .. table.concat(unknown, ", ") .. ")" or ""}, {#(COLLISION[name] or {})} collision parts, {#(SEATS[name] or {})} seats, {lights} lights, {signs} signs{#variants > 0 and ", variants " .. table.concat(variants, ", ") or ""}`
	)
end
return #report > 0 and table.concat(report, "\\n") or "no HubKit_* model in Workspace"
"""


def write_studio_script():
    with open(os.path.join(HUB_DIR, "hubkit_models.json"), encoding="utf-8") as f:
        report = json.load(f)
    out = [LUAU_HEAD, "local GAME_COLOURS = {"]
    for k in sorted(GAME_COLOURS):
        out.append(f'\t{k} = "{GAME_COLOURS[k]}",')
    out.append("}")
    out.append("local GLASS_TRANSPARENCY = 0.55")
    out.append("local WATER_TRANSPARENCY = 0.35")
    # off by default (06.11.2026): in the daylight of the map the light washed the island edge, the bridge heads and
    # the lantern feet out to white; the Neon glass glows without it. enabled = true for a night scene
    out.append("local LIGHT = { colour = Color3.fromRGB(255, 214, 140), brightness = 2, range = 18, enabled = false }")
    out.append("")
    out.append("-- per model: boxes { size = Vector3, centre } or upright cylinders { size = (height, diameter, diameter) }")
    out.append("local COLLISION = {")
    for name in sorted(report):
        out.append(f"\t{name} = {{")
        for c in report[name].get("collision", []):
            label = f', name = "{c["name"]}"' if c.get("name") else ""
            if c["kind"] == "cylinder":
                size = (c["height"], 2 * c["radius"], 2 * c["radius"])
            else:
                size = (c["size"][0], c["size"][2], c["size"][1])
            out.append(f'\t\t{{ kind = "{c["kind"]}"{label}, size = {_v3(size)}, centre = {_v3(_rb(c["center"]))} }},')
        out.append("\t},")
    out.append("}")
    out.append("-- seats: where the seat's top is and the point it looks at")
    out.append("local SEATS = {")
    for name in sorted(report):
        seats = report[name].get("seats")
        if seats:
            out.append(f"\t{name} = {{")
            for s in seats:
                out.append(f"\t\t{{ at = {_v3(_rb(s['at']))}, look = {_v3(_rb(s['look']))} }},")
            out.append("\t},")
    out.append("}")
    out.append("-- words on parts _Arrow<n>_: the field is left, right, top, bottom as fractions of the part's Front face")
    out.append("local SIGNS = {")
    for name in sorted(report):
        face = report[name].get("face") or {}
        if face.get("labels"):
            area = ", ".join(f"{v:g}" for v in face["area"])
            labels = ", ".join(f'"{w}"' for w in face["labels"])
            out.append(f"	{name} = {{ area = {{ {area} }}, labels = {{ {labels} }} }},")
    out.append("}")
    out.append("-- recoloured copies: variant = { part = colour }")
    out.append("local VARIANTS = {")
    for name in sorted(report):
        variants = report[name].get("variants")
        if variants:
            inner = ", ".join(
                f"{v} = {{ " + ", ".join(f'{p} = "{c}"' for p, c in parts.items()) + " }" for v, parts in variants.items()
            )
            out.append(f"\t{name} = {{ {inner} }},")
    out.append("}")
    path = os.path.join(HUB_DIR, "studio_hubkit_templates.luau")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n" + LUAU_BODY)
    print("wrote", path)


for _name in PACK or list(BUILDERS):
    BUILDERS[_name]()
    finish(_name)
if all(f"HK_{n}" in bpy.data.collections for n in ("BridgeEnd", "BridgeMid")) and (
    PACK is None or {"BridgeEnd", "BridgeMid"} & set(PACK)
):
    bridge_preview()
write_studio_script()
