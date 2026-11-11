"""The deco pack (Deko Runde 2, 09.11.2026): bushes, trees, palms, rocks and the leaderboard sign for the hub ring and
the plot islands. References in the vault (Wobble Scoops/Wooble scoops Map assets 1):
    BushRound, BushFlower, Hedge, BushSmall   "Stilisierte Hecken und Blütenbüsche" (left to right)
    RockRound, RockFlat, RockGroup            "Stilisierte Felsen mit grünen Blättern" (left to right)
    PalmStraight, PalmBent                    "Zwei Palmen mit Eiscreme-Kokosnüssen"
    IceTreeUpright                            "Glänzender blauer Eiskrembaum" (upright: two scoops stacked)
    Leaderboard                               "Eiscreme-Leaderboard mit Waffelrahmen"
    TreeRound, TreeTall, LollipopTree         no reference (user, 09.11.2026): free, in the kit's style

Run through run_decokit.py. Studs, origin at the bottom centre, front -Y. Sizes against an R15 figure (5.2 studs).
Collision: none for bushes and rocks; one box round the trunk for trees and palms; the sign's posts and board. The
Leaderboard's display has an invisible part Display (Front to the front) for a SurfaceGui, made by the template script.
"""

import math
import random

from mathutils import Vector

# colours beyond the hub kit: the flavour colours of the map sectors (assets/MapColors) for the tree variants
for _name, _hex in {"Mint": "#7FE0B8", "Lavender": "#BB9CF0"}.items():
    PALETTE[_name] = _hex
    GAME_COLOURS[_name] = _hex

# --------------------------------------------------------------------------------------------------------------------
# bushes: glossy green balls with pointed leaves, like the reference: round, round with flowers, a hedge, a small one


def _leafy_mound(col, name, rx, ry, height, seed, rows=4):
    """A bush like the reference: a soft green dome (rx, ry: half width and depth) covered in big glossy leaves that
    lie on it like shingles, row over row, their tips hanging out and down, and a small tuft of leaves on top.
    Returns spots on the dome (point, normal) for flowers."""
    rng = random.Random(seed)
    dome = blob(col, name + "Dome", "LeafDark", 1.0, None, 0.0, height * 0.92, segments=16)
    dome.scale = (rx * 0.92, ry * 0.92, 1.0)
    tips, spots = [], []
    for k in range(rows):
        f = 0.15 + 0.68 * k / (rows - 1)  # height of the row as a fraction of the dome
        z = height * 0.92 * f
        ring = math.sqrt(max(0.0, 1 - f * f))
        n = max(5, round(11 * ring + 2))
        for i in range(n):
            a = 2 * math.pi * (i + 0.5 * k) / n + rng.uniform(-0.12, 0.12)
            base = (rx * 0.82 * ring * math.cos(a), ry * 0.82 * ring * math.sin(a), z + 0.25)
            size = (0.62 - 0.12 * k / rows) * min(rx, ry)
            tips.append((base, a, -0.35 - 0.35 * (1 - f) + rng.uniform(-0.08, 0.08), size * 1.25, size * 0.95))
            spots.append((Vector(base) + Vector((math.cos(a), math.sin(a), 0.4)) * size * 0.7,
                          Vector((math.cos(a), math.sin(a), 0.8)).normalized()))
    for i in range(4):
        a = 2 * math.pi * i / 4 + 0.4
        tips.append(((0, 0, height * 0.9), a, 0.75, 0.42 * min(rx, ry), 0.3 * min(rx, ry)))
    leaves(col, name + "Leaves", "Leaf", tips)
    return spots


def build_bush_round():
    col = hk_collection("BushRound")
    _leafy_mound(col, "", 2.6, 2.4, 4.2, seed=3)
    SPECS["BushRound"] = dict(collision=[], figure=(-4.6, -2.6))


def build_bush_flower():
    col = hk_collection("BushFlower")
    spots = _leafy_mound(col, "", 2.6, 2.4, 4.2, seed=7)
    pink, cream = [], []
    for k, idx in enumerate((12, 15, 19, 22, 26)):
        c, d = spots[idx % len(spots)]
        (pink if k % 2 == 0 else cream).append((c, d, 1.3))
    flowers(col, "FlowerPink", "Pink", pink, seed=3)
    flowers(col, "FlowerCream", "Cream", cream, seed=4)
    SPECS["BushFlower"] = dict(collision=[], figure=(-4.6, -2.6))


def build_hedge():
    col = hk_collection("Hedge")
    rng = random.Random(12)
    length, depth, height = 10.0, 3.2, 3.6
    rounded_box(col, "Body", "LeafDark", (length, depth, height * 0.85), (0, 0, height * 0.425), radius=1.1,
                segments=3)
    tips = []
    for row, z in enumerate((0.75, 1.75, 2.75)):
        n = 7 - (row == 2)
        for i in range(n):
            x = -length / 2 + 0.9 + (i + 0.5 * (row % 2)) * (length - 1.8) / 6
            for side in (-1, 1):
                tips.append(((x + rng.uniform(-0.2, 0.2), side * depth * 0.38, z + 0.3), side * math.pi / 2,
                             -0.55 + rng.uniform(-0.1, 0.1), 1.5, 1.2))
    for i in range(8):
        x = -length / 2 + 0.8 + i * (length - 1.6) / 7
        for side in (-1, 1):
            tips.append(((x, side * 0.5, height * 0.86), side * math.pi / 2 + rng.uniform(-0.3, 0.3), -0.15, 1.5,
                         1.25))
    leaves(col, "Leaves", "Leaf", tips)
    # one box inside the leaves, so nobody walks through (Map Check 2026-11-11)
    SPECS["Hedge"] = dict(collision=[box((9.4, 3.0, 3.0), (0, 0, 1.5), name="Body")], figure=(-6.8, -2.6))


def build_bush_small():
    col = hk_collection("BushSmall")
    ball(col, "Heart", "LeafDark", 0.9, (0, 0, 0.45), squash=0.7, segments=12)
    tips = []
    for k in range(7):
        a = 2 * math.pi * k / 7
        tips.append(((0.3 * math.cos(a), 0.3 * math.sin(a), 0.35), a, 0.18, 1.7, 0.85))
    for k in range(5):
        a = 2 * math.pi * k / 5 + 0.4
        tips.append(((0.15 * math.cos(a), 0.15 * math.sin(a), 0.6), a, 0.75, 1.3, 0.7))
    leaves(col, "Leaves", "Leaf", tips)
    SPECS["BushSmall"] = dict(collision=[], figure=(-3.2, -1.6))


# --------------------------------------------------------------------------------------------------------------------
# trees. Collision: one box round the trunk, as high as the trunk.


def _trunk_box(radius, height, at=(0, 0), name="Trunk"):
    return box((radius * 1.6, radius * 1.6, height), (at[0], at[1], height / 2), name=name)


def build_tree_round():
    """A round green tree: a warm wooden trunk and a crown of glossy leaf balls. 13 high, crown 9 wide."""
    col = hk_collection("TreeRound")
    rng = random.Random(21)
    cylinder(col, "Trunk", "Wood", 0.95, 7.2, 0, segments=12, bevel=0.1, radius_top=0.7)
    cylinder(col, "Root", "Wood", 1.35, 0.6, 0, segments=12, bevel=0.2, radius_top=0.95)
    crown = [((0, 0, 10.0), 3.2, "Leaf"), ((2.2, 0.6, 8.6), 2.4, "LeafDark"), ((-2.1, 0.4, 8.7), 2.4, "LeafDark"),
             ((0.3, -2.0, 8.5), 2.3, "LeafDark"), ((0.2, 2.1, 8.9), 2.3, "LeafDark"), ((1.1, -0.9, 11.4), 1.9, "Leaf"),
             ((-1.2, 0.9, 11.5), 1.8, "Leaf")]
    for i, (c, r, colour) in enumerate(crown):
        ball(col, f"Crown{i}", colour, r * rng.uniform(0.96, 1.04), c, squash=0.9, segments=14)
    tips = [((0, 0, 12.6), 2 * math.pi * k / 5, 0.6, 1.6, 0.8) for k in range(5)]
    leaves(col, "Leaves", "Leaf", tips)
    SPECS["TreeRound"] = dict(collision=[_trunk_box(0.95, 7.2)], figure=(-6.0, -3.5))


def build_tree_tall():
    """A tall slim tree (cypress): a short trunk and a column of leaf balls getting smaller upwards. 15 high, 5 wide."""
    col = hk_collection("TreeTall")
    cylinder(col, "Trunk", "Wood", 0.6, 3.2, 0, segments=10, bevel=0.08, radius_top=0.48)
    z = 3.4
    for i, r in enumerate((2.3, 2.15, 1.9, 1.55, 1.1)):
        ball(col, f"Crown{i}", "LeafDark" if i % 2 == 0 else "Leaf", r, (0, 0, z + r * 0.9), squash=1.05,
             segments=14)
        z += r * 1.55
    leaves(col, "Leaves", "Leaf", [((0, 0, z + 0.6), 2 * math.pi * k / 4, 0.9, 1.1, 0.55) for k in range(4)])
    SPECS["TreeTall"] = dict(collision=[_trunk_box(0.6, 3.2)], figure=(-3.6, -2.0))


def build_lollipop_tree():
    """A lollipop tree: a cream stick with pink stripes and a big round candy (Pink, a Cream swirl on both faces),
    a ribbon bow under it. 12 high, the candy 7 wide."""
    col = hk_collection("LollipopTree")
    stick_h = 7.6
    cylinder(col, "Stick", "Cream", 0.45, stick_h - 0.05, 0.05, segments=12, bevel=0.1)
    cylinder(col, "Foot", "Waffle", 1.4, 0.5, 0, segments=16, bevel=0.15, radius_top=1.0)
    stripes = []
    for k in range(4):
        pts = []
        for i in range(25):
            t = i / 24
            a = 2 * math.pi * (t * 3 + k / 4)
            pts.append((0.47 * math.cos(a), 0.47 * math.sin(a), 0.6 + t * (stick_h - 1.0)))
        stripes.append(pts)
    _tube(col, "Stripes", "Pink", stripes, 0.18, sides=4)
    cz = stick_h + 3.0
    disc_n(col, "Candy", "Pink", 3.5, 1.1, (0, 0, cz), (0, -1, 0), segments=28, bevel=0.35)
    for face, name in ((-1, "SwirlFront"), (1, "SwirlBack")):
        pts = []
        for i in range(60):
            t = i / 59
            a = t * 2.6 * 2 * math.pi
            r = 0.3 + t * 2.75
            pts.append((r * math.cos(a), face * 0.58, cz + r * math.sin(a)))
        _tube(col, name, "Cream", [pts], 0.42, sides=6)
    for side in (-1, 1):
        leaves(col, f"Bow{'L' if side < 0 else 'R'}", "SkyBlue",
               [((0, -0.5, cz - 3.6), math.pi / 2 - side * math.pi / 2, 0.25, 1.6, 1.0)])
    ball(col, "Knot", "SkyBlue", 0.45, (0, -0.5, cz - 3.6), segments=10)
    SPECS["LollipopTree"] = dict(collision=[_trunk_box(0.45, stick_h)], figure=(-4.8, -2.4))


def build_ice_tree_upright():
    """An upright ice cream tree: a straight waffle trunk and two glazed scoops stacked on top, drips, sprinkles and a
    cherry. 17 high, 7.6 wide. The lower scoop is the part Crown, the upper one Crown2: SkyBlue and Pink in the FBX,
    variants in Studio."""
    col = hk_collection("IceTreeUpright")
    cylinder(col, "Foot", "Waffle", 1.9, 0.45, 0, radius_top=1.6, segments=20, bevel=0.15)
    trunk = 8.4
    waffle_cone(col, "Trunk", 1.45, 1.15, trunk, 0.3, spacing=1.45, ridge=0.38, segments=18)
    z = 0.3 + trunk + 1.2
    iced_dome(col, "Lower", "SkyBlue", 3.8, z - 1.5, z, z + 2.6, drips=9, drop=(1.2, 2.6), width=(1.3, 1.9),
              thickness=0.38, seed=31, segments=24, part="Crown", sprinkles=10)
    z2 = z + 2.9
    iced_dome(col, "Upper", "Pink", 2.9, z2 - 1.1, z2, z2 + 2.3, drips=7, drop=(0.9, 1.9), width=(1.1, 1.6),
              thickness=0.34, seed=37, segments=22, part="Crown2", sprinkles=7)
    cherry(col, "Cherry", (0, 0, z2 + 2.1), 0.55)
    SPECS["IceTreeUpright"] = dict(
        collision=[_trunk_box(1.45, 0.3 + trunk)],
        variants={"Mint": {"Crown": "Mint", "Crown2": "Cream"}, "Lemon": {"Crown": "Gold", "Crown2": "Pink"}},
        figure=(-5.8, -3.2),
    )


# --------------------------------------------------------------------------------------------------------------------
# palms: a trunk of stacked caramel rings, drooping fronds, two ice cream "coconuts" (a waffle cup with a glazed scoop),
# rocks and leaves at the foot. Straight and bent (the bent one leans to +X). Collision: the trunk only.


def _coconut(col, name, at, colour):
    x, y, z = at
    cylinder(col, name + "Cup", "Waffle", 0.55, 0.9, z - 0.9, center=(x, y), segments=10, bevel=0.08,
             radius_top=0.85)
    iced_dome(col, name, colour, 0.95, z - 0.25, z, z + 0.85, drips=5, drop=(0.25, 0.55), width=(0.35, 0.55),
              thickness=0.16, seed=hash(name) % 97, center=(x, y), segments=14, sprinkles=4,
              sprinkle_size=(0.38, 0.13, 0.1))


def _palm(name, bend):
    col = hk_collection(name)
    rng = random.Random(41 if bend else 43)
    seg_h, n = 1.55, 7
    base = Vector((0, 0, 0.1))
    angle = 0.0
    for i in range(n):
        r0 = 0.95 - 0.045 * i
        ob = cylinder(col, f"Ring{i}", "Caramel", r0 * 0.86, seg_h, 0, segments=12, bevel=0.12, radius_top=r0)
        ob.rotation_euler = (0, angle, 0)
        ob.location = base
        base = base + Vector((math.sin(angle), 0, math.cos(angle))) * seg_h * 0.97
        angle += bend
    top = base
    fronds = []
    for k in range(7):
        a = 2 * math.pi * k / 7 + 0.2
        # an arching frond: a short inner piece rising, a long outer piece hanging from its tip
        rise, droop = 2.2, 4.6
        inner = Vector((math.cos(a), math.sin(a), 0)) * rise * math.cos(0.35)
        fronds.append(((top.x, top.y, top.z + 0.2), a, 0.35, rise, 2.2))
        fronds.append(((top.x + inner.x, top.y + inner.y, top.z + 0.2 + rise * math.sin(0.35)), a,
                       -0.55 + rng.uniform(-0.1, 0.1), droop, 2.5))
    for a in (0.6, 2.7, 4.6):
        fronds.append(((top.x, top.y, top.z + 0.3), a, 1.0, 3.0, 1.5))
    leaves(col, "Fronds", "Leaf", fronds)
    ball(col, "Heart", "LeafDark", 0.75, (top.x, top.y, top.z + 0.15), segments=10)
    _coconut(col, "NutCream", (top.x - 0.75, top.y - 0.95, top.z - 1.0), "Cream")
    _coconut(col, "NutPink", (top.x + 0.8, top.y - 0.85, top.z - 1.2), "Pink")
    for i, (size, at) in enumerate((((2.0, 1.7, 1.0), (-1.3, -0.9)), ((1.8, 1.6, 0.9), (1.3, -1.0)),
                                    ((1.9, 1.6, 0.95), (0.3, 1.4)))):
        _rock(col, f"Pebble{i}", size, at, seed=60 + i)
    leaves(col, "FootLeaves", "Leaf", [((1.2 * math.cos(a), 1.2 * math.sin(a), 0.1), a, 0.7, 2.0, 0.9)
                                       for a in (0.3, 1.9, 3.4, 4.8)])
    # the trunk's box: upright round the lower trunk only (a bent palm's top leans out of it, players pass under)
    SPECS[name] = dict(collision=[box((1.7, 1.7, seg_h * 4), (0.25 * (bend > 0), 0, seg_h * 2), name="Trunk")],
                       figure=(-5.6, -3.2))


def build_palm_straight():
    _palm("PalmStraight", 0.0)


def build_palm_bent():
    _palm("PalmBent", 0.075)


# --------------------------------------------------------------------------------------------------------------------
# rocks, as the reference: a round boulder with a smaller one and a pebble, a flat slab with a crack, a small group;
# lavender grey, chunky facets, a few leaves. No collision.


def _rock(col, name, size, at, seed):
    """The hub kit's rock, rounder: wider bevels with two segments, so it reads as a smooth boulder like the reference
    and not as a crystal."""
    ob, top = rock(col, name, size, at, seed)
    bevel = ob.modifiers["Bevel"]
    bevel.width = 0.09 * min(size)
    bevel.segments = 2
    return ob, top


def _blades(col, name, spots):
    leaves(col, name, "Leaf", [((x, y, 0.05), a, 1.0, h * 1.5, h * 0.45) for x, y, a, h in spots])


def build_rock_round():
    col = hk_collection("RockRound")
    _rock(col, "Big", (3.6, 3.0, 3.9), (-0.4, 0.3), seed=101)
    _rock(col, "Mid", (2.6, 2.3, 2.1), (1.5, -0.8), seed=102)
    _rock(col, "Pebble", (1.0, 0.9, 0.6), (-2.2, -1.2), seed=103)
    _blades(col, "Blades", [(-2.4, -0.2, 0.2, 1.3), (-2.2, 0.2, -0.4, 1.1), (2.6, 0.6, 0.6, 1.2), (2.9, 0.3, -0.2, 1.0)])
    # one box inside the two big rocks, so nobody walks through (Map Check 2026-11-11)
    SPECS["RockRound"] = dict(collision=[box((4.1, 2.7, 3.6), (0, 0, 1.8), name="Rock")], figure=(-4.6, -2.4))


def build_rock_flat():
    col = hk_collection("RockFlat")
    _rock(col, "SlabL", (2.9, 3.4, 1.15), (-1.15, 0.0), seed=111)
    _rock(col, "SlabR", (3.1, 3.2, 1.0), (1.4, 0.15), seed=112)  # the gap between the two halves is the crack
    _rock(col, "Pebble", (1.2, 1.0, 0.65), (1.4, -1.9), seed=113)
    _blades(col, "Blades", [(2.7, 1.4, 0.3, 1.2), (3.0, 1.1, -0.3, 1.0)])
    SPECS["RockFlat"] = dict(collision=[], figure=(-4.6, -2.4))


def build_rock_group():
    col = hk_collection("RockGroup")
    _rock(col, "A", (1.9, 1.7, 1.8), (0.0, 0.4), seed=121)
    _rock(col, "B", (1.4, 1.3, 1.0), (-1.0, -0.6), seed=122)
    _rock(col, "C", (1.5, 1.3, 1.2), (1.2, -0.3), seed=123)
    _blades(col, "Blades", [(-1.9, -0.3, 0.3, 1.0), (-1.7, 0.1, -0.3, 0.9), (1.9, 0.5, 0.4, 1.0)])
    SPECS["RockGroup"] = dict(collision=[], figure=(-3.2, -1.8))


# --------------------------------------------------------------------------------------------------------------------
# Leaderboard sign (reference "Eiscreme-Leaderboard mit Waffelrahmen"): two caramel posts on waffle feet with cream
# rope rings, a waffle frame with a gold rim round a dark chocolate board, a caramel header plank (its front gets the
# word LEADERBOARD in Studio), cream glaze with drips on top, three scoops (Pink, Cream with a cherry, Choco) and
# leaves, two hanging SkyBlue banners with the cone. The board's front is the invisible part Display (Studio).
# 11.6 wide, 15.4 high; the board 8.6 x 7.0, its middle 6.6 above the ground.

LB = dict(width=11.6, post=0.75, board_w=8.6, board_h=7.0, board_z=6.6, depth=0.9)


def build_leaderboard():
    col = hk_collection("Leaderboard")
    w, p, d = LB["width"], LB["post"], LB["depth"]
    px = w / 2 - p
    top = LB["board_z"] + LB["board_h"] / 2 + 1.0
    for s in (-1, 1):
        cylinder(col, f"Post{s}", "Caramel", p, top + 0.55, 0.05, center=(s * px, 0), segments=14, bevel=0.15)
        cylinder(col, f"Foot{s}", "Waffle", 1.25, 1.2, 0, center=(s * px, 0), segments=4, bevel=0.15,
                 radius_top=0.95)
        cylinder(col, f"FootCap{s}", "Cream", 1.05, 0.35, 1.2, center=(s * px, 0), segments=14, bevel=0.12)
        for k, z in enumerate((2.2, 2.6)):
            cylinder(col, f"Rope{s}_{k}", "Cream", p + 0.18, 0.3, z, center=(s * px, 0), segments=14, bevel=0.13)
        ball(col, f"PostCap{s}", "Gold", p * 0.95, (s * px, 0, top + 0.6), squash=0.6, segments=12)
        banner(col, f"Banner{s}", (s * (px + 1.35), -0.2, top - 1.9), (0, -1, 0), width=1.6, height=2.2)
    fw, fh = LB["board_w"] + 1.4, LB["board_h"] + 1.4
    # the lattice on the back only: on the front it would lie over the board
    waffle_panel(col, "Frame", (fw, d, fh), (0, 0, LB["board_z"]), faces=("back",))
    rounded_box(col, "Rim", "Gold", (LB["board_w"] + 0.5, d + 0.12, LB["board_h"] + 0.5), (0, 0, LB["board_z"]),
                radius=0.2, segments=2)
    # the board stands 0.08 proud of the rim's front, so nothing lies flush with it (no z-fighting)
    rounded_box(col, "Board", "Choco", (LB["board_w"], d + 0.28, LB["board_h"]), (0, 0, LB["board_z"]), radius=0.15,
                segments=1)
    hz = LB["board_z"] + fh / 2 + 0.55
    rounded_box(col, "Header", "Caramel", (fw - 0.6, d + 0.5, 1.5), (0, 0, hz), radius=0.45, segments=2)
    glaze_z = hz + 0.75
    rounded_box(col, "Glaze", "Cream", (fw + 0.4, d + 0.7, 0.55), (0, 0, glaze_z), radius=0.25, segments=2)
    for i, x in enumerate((-4.6, -3.2, 3.3, 4.7)):
        ball(col, f"Drip{i}", "Cream", 0.4, (x, -(d + 0.7) / 2 + 0.1, glaze_z - 0.45), scale=(1, 0.7, 1.5),
             segments=10)
    sz = glaze_z + 0.25
    for name, x, r, colour in (("ScoopPink", -1.4, 1.15, "Pink"), ("ScoopChoco", 1.45, 1.05, "Choco")):
        blob(col, name, colour, r, None, sz, sz + 1.5 * r, center=(x, 0.1), segments=18)
    iced_dome(col, "ScoopTop", "Cream", 1.25, sz + 0.2, sz + 0.9, sz + 2.2, drips=6, drop=(0.3, 0.7),
              width=(0.4, 0.6), thickness=0.2, seed=71, center=(0, -0.1), segments=18, sprinkles=6,
              sprinkle_size=(0.42, 0.14, 0.11))
    cherry(col, "Cherry", (0, -0.1, sz + 2.1), 0.42)
    leaves(col, "Leaves", "Leaf", [((s * 2.4, 0.1, sz + 0.2), (0 if s > 0 else math.pi), 0.45, 1.8, 0.9)
                                   for s in (-1, 1)])
    front = -(d + 0.28) / 2  # the board's front face (y)
    SPECS["Leaderboard"] = dict(
        collision=[box((w - 0.4, 1.4, top + 0.6), (0, 0, (top + 0.6) / 2), name="Sign")],
        display=dict(size=[LB["board_w"] - 0.3, LB["board_h"] - 0.3], center=[0, front - 0.03, LB["board_z"]]),
        header=dict(size=[fw - 1.2, 1.2], center=[0, -(d + 0.5) / 2 - 0.03, hz]),
        figure=(-8.0, -2.5),
    )


BUILDERS = {
    "BushRound": build_bush_round,
    "BushFlower": build_bush_flower,
    "Hedge": build_hedge,
    "BushSmall": build_bush_small,
    "TreeRound": build_tree_round,
    "TreeTall": build_tree_tall,
    "LollipopTree": build_lollipop_tree,
    "IceTreeUpright": build_ice_tree_upright,
    "PalmStraight": build_palm_straight,
    "PalmBent": build_palm_bent,
    "RockRound": build_rock_round,
    "RockFlat": build_rock_flat,
    "RockGroup": build_rock_group,
    "Leaderboard": build_leaderboard,
}

for _name in PACK or list(BUILDERS):
    BUILDERS[_name]()
    finish(_name)


# --------------------------------------------------------------------------------------------------------------------
# the Studio template script (the hub kit's, written from decokit_models.json), plus the invisible text parts: a
# thin Part per entry of a model's display/header, its Front (-Z, the model's front) facing out, for a SurfaceGui


def write_deco_studio_script():
    import json
    import os

    write_studio_script()
    path = os.path.join(HUB_DIR, "studio_decokit_templates.luau")
    with open(os.path.join(HUB_DIR, "decokit_models.json"), encoding="utf-8") as f:
        report = json.load(f)
    lines = ["", "-- invisible text faces: Display (the board) and Header (the plank), Front facing the model's front",
             "local FACES = {"]
    for name in sorted(report):
        entries = [(k, report[name][k]) for k in ("display", "header") if report[name].get(k)]
        if entries:
            lines.append(f"\t{name} = {{")
            for key, spec in entries:
                w, h = spec["size"]
                lines.append(f'\t\t{{ name = "{key.capitalize()}", size = Vector3.new({w:g}, {h:g}, 0.05), '
                             f"centre = {_v3(_rb(spec['center']))} }},")
            lines.append("\t},")
    lines += ["}", """for name, faces in FACES do
	local model = folder:FindFirstChild(name)
	if model then
		for _, spec in faces do
			local old = model:FindFirstChild(spec.name)
			if old then
				old:Destroy()
			end
			local p = Instance.new("Part")
			p.Name = spec.name
			p.Size = spec.size
			p.CFrame = model:GetPivot() * CFrame.new(spec.centre)
			p.Transparency = 1
			p.Anchored = true
			p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
			p.CastShadow = false
			p:SetAttribute("TextFace", "Front")
			p.Parent = model
		end
	end
end
"""]
    with open(path, encoding="utf-8") as f:
        text = f.read()
    marker = "return #report > 0"
    text = text.replace(marker, "\n".join(lines) + marker, 1)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("wrote", path)


write_deco_studio_script()
