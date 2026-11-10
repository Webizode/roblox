"""The shop pack (10.11.2026): the three shop buildings of the hub, Upgrade Shop, Cosmetic Shop and Quest Hub. The
references (vault, Wobble Scoops/Wooble scoops Map assets 1) show one booth in three dressings:
    UpgradeShop    "Pastellfarbener Upgrade-Eisladen mit zwei Ansichten"  mint, gear and cone, anvil, tools, chart board
    CosmeticShop   "Glitzernder Eiscreme-Kosmetikshop"                    pink and lavender, sparkles, hats, mirror, gift
    QuestHub       "Quest-Hub als Eiscreme-Bude"                          blue, scroll with "!", notice board, mailbox,
                                                                          crates
So one builder makes the booth (plinth with stripes, wooden corner posts, cream side walls with a waffle band and a
window, a dark wooden back wall with a shelf, a waffle counter with a cloth, the striped awning with scallops, a waffle
frieze, a cream glaze roof with drips and sprinkles, a soft scoop with a cherry on top, leaves, lanterns and banners)
and each shop adds its accent colour, the emblem on the sign and its props.

60/30/10: cream, waffle and wood carry the building; the accent colour only on the awning, the sign, the banners, the
window frames, the counter cloth and the plinth stripes.

Run through run_shopkit.py. Studs, origin at the bottom centre, front -Y. The footprint (about 24 x 17) fits the hub's
shop squares (44 x 30, Dekoracje.Hub.Platzhalter), with room for a forecourt in front.
Invisible parts made by the template script (studio_shopkit_templates.luau): NameField on the sign's name field, its
Front to the front, for a SurfaceGui with the shop's name (no text in the model); NpcSpot on the free floor behind
the counter, where a shopkeeper NPC will stand later (a rug marks it, as at the Working Station).
"""

import math
import random

from mathutils import Vector

for _name, _hex in {"Mint": "#7FE0B8", "Lavender": "#BB9CF0", "Blue": "#5FA8E8", "Steel": "#9AA4B4"}.items():
    PALETTE[_name] = _hex
    GAME_COLOURS[_name] = _hex

B = dict(w=22.0, d=14.0, plinth=0.8, wall=13.0, post=1.15, frieze=3.0, roof=1.6, counter=3.5)
FRONT = Vector((0, -1, 0))


def _x(v):
    return Vector(v)


def booth(name, accent, accent2):
    """The shared building. Returns (collection, key heights) for the props."""
    col = hk_collection(name)
    w, d, p = B["w"], B["d"], B["plinth"]
    hw, hd = w / 2, d / 2
    top = p + B["wall"]  # top of walls and posts
    # plinth: cream slab, accent stripes standing proud of its front and sides (no shared faces)
    rounded_box(col, "Plinth", "Cream", (w + 2.0, d + 2.0, p), (0, 0, p / 2), radius=0.3, segments=2)
    n = 9
    seg = (w + 2.0) / n
    for i in range(n):
        if i % 2 == 0:
            x = -(w + 2.0) / 2 + seg * (i + 0.5)
            rounded_box(col, f"Stripe{i}", accent, (seg, 0.3, p * 0.7), (x, -hd - 1.0 - 0.1, p * 0.45), radius=0.12,
                        segments=1)
    # floor inside, wooden
    rounded_box(col, "Floor", "Wood", (w - 1.2, d - 1.2, 0.2), (0, 0, p + 0.13), radius=0.05, segments=1)
    # corner posts with a cream foot
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * (hw - B["post"]), sy * (hd - B["post"])
            cylinder(col, f"Post{sx}{sy}", "Wood", B["post"], B["wall"], p, center=(cx, cy), segments=14, bevel=0.15)
            cylinder(col, f"PostFoot{sx}{sy}", "Cream", B["post"] + 0.35, 1.2, p + 0.04, center=(cx, cy), segments=14,
                     bevel=0.25)
    # side walls: cream plaster above a waffle band, a window with an accent frame (outward faces only)
    for sx in (-1, 1):
        x = sx * (hw - 0.6)
        rounded_box(col, f"Wall{sx}", "Cream", (0.8, d - 2 * B["post"] - 0.2, B["wall"] - 0.2),
                    (x, 0, p + B["wall"] / 2), radius=0.2, segments=1)
        body, ridges = waffle_panel(col, f"WallWaffle{sx}", (d - 2 * B["post"] - 0.6, 0.5, 4.2),
                                    (0, 0, 0), faces=("front",))
        for ob in (body, ridges):
            ob.rotation_euler = (0, 0, -sx * math.pi / 2)
            ob.location = (x + sx * 0.55, 0, p + 2.4)
        n_out = Vector((sx, 0, 0))
        plate(col, f"WindowFrame{sx}", accent, stadium(3.6, 4.4, 8) if False else circle(1.9, 20), (x + sx * 0.4, 1.0, p + 8.2),
              n_out, 0.35, bevel=0.1)
        plate(col, f"WindowGlass{sx}", "SkyBlue", circle(1.45, 20), (x + sx * 0.5, 1.0, p + 8.2), n_out, 0.35,
              bevel=0.06)
    # back wall (dark wood inside, cream outside) with a shelf
    rounded_box(col, "BackWall", "Choco", (w - 2 * B["post"], 0.8, B["wall"] - 0.2), (0, hd - 0.6, p + B["wall"] / 2),
                radius=0.15, segments=1)
    shelf_z = p + 7.4
    rounded_box(col, "Shelf", "Wood", (w * 0.55, 1.6, 0.35), (-1.5, hd - 1.8, shelf_z), radius=0.1, segments=1)
    # counter: a waffle front, a cream top, the accent cloth; it closes the booth (the NPC stands behind it)
    cy = -hd + 2.0
    body, ridges = waffle_panel(col, "Counter", (w - 2 * B["post"] - 0.4, 1.6, B["counter"] - 0.5),
                                (0, cy, p + (B["counter"] - 0.5) / 2), faces=("front",))
    rounded_box(col, "CounterTop", "Cream", (w - 2 * B["post"] - 0.1, 2.4, 0.5), (0, cy + 0.2, p + B["counter"] - 0.25),
                radius=0.2, segments=2)
    rounded_box(col, "Cloth", accent, (w * 0.32, 2.5, 0.12), (0, cy + 0.2, p + B["counter"] + 0.06), radius=0.05,
                segments=1)
    rounded_box(col, "ClothDrop", accent, (w * 0.32, 0.12, 1.2), (0, cy - 1.0, p + B["counter"] - 0.45), radius=0.05,
                segments=1)
    # the NPC's place: a rug on the floor between counter and back wall
    npc_y = (cy + 1.4 + hd - 1.2) / 2
    rounded_box(col, "Rug", accent2, (w * 0.4, 3.0, 0.08), (2.0, npc_y, p + 0.24), radius=0.04, segments=1)
    # frieze above the opening: waffle band all round the front, a caramel beam under it
    fz = top + B["frieze"] / 2
    waffle_panel(col, "Frieze", (w + 0.4, 1.0, B["frieze"]), (0, -hd + 0.5, fz), faces=("front",))
    rounded_box(col, "FriezeBack", "Waffle", (w + 0.4, d - 1.0, B["frieze"]), (0, 0.5, fz), radius=0.1, segments=1)
    rounded_box(col, "Beam", "Caramel", (w + 0.6, 1.3, 0.7), (0, -hd + 0.4, top - 0.1), radius=0.2, segments=1)
    # awning: stripes hanging from under the beam and sloping down and out over the counter (front edge lower),
    # small scallops along that edge
    stripes, aw_w, aw_d, tilt = 9, w - 2.4, 4.0, math.radians(30)
    hinge = Vector((0, -hd - 0.1, top - 0.7))  # the back edge, under the beam
    centre = hinge + Vector((0, -math.cos(tilt), -math.sin(tilt))) * aw_d / 2
    edge = hinge + Vector((0, -math.cos(tilt), -math.sin(tilt))) * aw_d
    for i in range(stripes):
        x = -aw_w / 2 + aw_w * (i + 0.5) / stripes
        colour = accent if i % 2 == 0 else "Cream"
        if accent2 != accent and i % 4 == 2:
            colour = accent2
        s = rounded_box(col, f"Awning{i}", colour, (aw_w / stripes, aw_d, 0.3), (0, 0, 0), radius=0.08, segments=1)
        s.rotation_euler = (tilt, 0, 0)  # turning +X lowers the -Y (front) half
        s.location = (x, centre.y, centre.z)
        disc_n(col, f"Scallop{i}", colour, aw_w / stripes * 0.34, 0.28, (x, edge.y - 0.05, edge.z - 0.25), (0, -1, 0),
               segments=12, bevel=0.08)
    # roof: a cream glaze slab with drips hanging over every edge, sprinkles on it
    rz = top + B["frieze"] + B["roof"] / 2
    rounded_box(col, "Roof", "Cream", (w + 2.2, d + 2.2, B["roof"]), (0, 0, rz), radius=0.7, segments=2)
    rng = random.Random(5)
    drips = []
    for i in range(12):
        x = -(w + 1.6) / 2 + (w + 1.6) * (i + 0.5) / 12
        drips.append((x, -(d + 2.2) / 2 + 0.25, rng.uniform(0.6, 1.3)))
    for i in range(8):
        y = -(d + 1.6) / 2 + (d + 1.6) * (i + 0.5) / 8
        drips.append(((w + 2.2) / 2 - 0.25, y, rng.uniform(0.5, 1.1)))
        drips.append((-(w + 2.2) / 2 + 0.25, y, rng.uniform(0.5, 1.1)))
    for k, (x, y, length) in enumerate(drips):
        ball(col, f"Drip{k}", "Cream", 0.55, (x, y, rz - B["roof"] / 2 - length * 0.35), scale=(1, 1, 1 + length),
             segments=10)
    spots = [((rng.uniform(-w / 2, w / 2), rng.uniform(-d / 2, d / 2), rz + B["roof"] / 2), (0, 0, 1))
             for _ in range(22)]
    surface_sprinkles(col, "RoofSprinkles", spots, seed=9)
    # on top: leaves either side and a big soft scoop with a cherry
    roof_top = rz + B["roof"] / 2
    for sx in (-1, 1):
        leaves(col, f"Leaves{sx}", "Leaf", [((sx * 6.5, 1.5, roof_top), sx * 0.0 + (0 if sx > 0 else math.pi) + a, 0.6,
                                             3.4, 1.7) for a in (-0.5, 0.0, 0.5)])
    iced_dome(col, "TopScoop", "Cream", 4.6, roof_top - 0.5, roof_top + 1.0, roof_top + 5.6, drips=10,
              drop=(0.6, 1.4), width=(0.9, 1.5), thickness=0.3, seed=21, center=(0, 2.0), segments=24, sprinkles=12)
    cherry(col, "Cherry", (0, 2.0, roof_top + 5.3), 1.0)
    # lanterns on the front posts and banners hanging under the beam
    for sx in (-1, 1):
        px = sx * (hw - B["post"])
        lx = px + sx * 1.9
        rounded_box(col, f"LanternArm{sx}", "Gold", (1.9, 0.3, 0.3), (px + sx * 1.0, -hd + B["post"], top - 2.2),
                    radius=0.1, segments=1)
        ball(col, f"LanternKnob{sx}", "Gold", 0.4, (px + sx * 2.0, -hd + B["post"], top - 2.2), segments=10)
        cylinder(col, f"LanternCap{sx}", "Choco", 0.75, 0.5, top - 3.3, center=(lx, -hd + B["post"]), segments=10,
                 bevel=0.1, radius_top=0.3)
        cylinder(col, f"LanternGlass{sx}", "Lamp", 0.55, 1.3, top - 4.6, center=(lx, -hd + B["post"]), segments=10,
                 bevel=0.1)
        cylinder(col, f"LanternFoot{sx}", "Choco", 0.65, 0.3, top - 4.9, center=(lx, -hd + B["post"]), segments=10,
                 bevel=0.08)
        # the banner hangs on the post's front, under the awning's edge
        bx, by, bz = px, -hd + B["post"] - B["post"] - 0.15, top - 4.0
        rounded_box(col, f"BannerRod{sx}", "Gold", (2.0, 0.25, 0.25), (bx, by, bz + 0.1), radius=0.08, segments=1)
        plate(col, f"Banner{sx}", accent, [(-0.8, 0), (0.8, 0), (0.8, -3.0), (0, -2.4), (-0.8, -3.0)],
              (bx, by - 0.15, bz), (0, -1, 0), 0.18, bevel=0.05)
        scoop_icon(col, f"BannerIcon{sx}", (bx, by - 0.35, bz - 1.1), (0, -1, 0), 1.2, "Cream")
    # the sign: a gold-rimmed accent cloud over the frieze, an emblem on the left, a cream name field on the right
    sz = top + B["frieze"] + 1.2
    sy = -hd - 0.6
    plate(col, "SignRim", "Gold", stadium(13.0, 5.0, 10), (0, sy + 0.25, sz), (0, -1, 0), 0.4, bevel=0.12)
    for bxx, r in ((-3.2, 2.2), (0.6, 2.6), (4.0, 2.0)):
        disc_n(col, f"SignBump{bxx}", "Gold", r + 0.25, 0.4, (bxx, sy + 0.45, sz + 1.6), (0, -1, 0), segments=18)
        disc_n(col, f"SignBumpFill{bxx}", accent, r, 0.4, (bxx, sy + 0.2, sz + 1.6), (0, -1, 0), segments=18)
    plate(col, "Sign", accent, stadium(12.2, 4.3, 10), (0, sy, sz), (0, -1, 0), 0.4, bevel=0.1)
    plate(col, "NameField", "Cream", stadium(7.4, 2.6, 8), (1.9, sy - 0.4, sz - 0.2), (0, -1, 0), 0.15, bevel=0.06)
    return col, dict(top=top, counter=p + B["counter"], shelf=shelf_z, sign=(sy - 0.55, sz), cy=cy, npc_y=npc_y,
                     emblem=(-4.1, sy - 0.4, sz), hd=hd, hw=hw, p=p)


def _common_spec(name, k, props):
    w, d = B["w"], B["d"]
    total_h = k["top"] + B["frieze"] + B["roof"]
    collision = [
        box((w + 2.0, d + 2.0, B["plinth"]), (0, 0, B["plinth"] / 2), name="Plinth"),
        box((w, d, total_h), (0, 0, total_h / 2), name="Building"),
    ] + props
    sx, sz = k["sign"]
    SPECS[name] = dict(
        collision=collision,
        name_field=dict(size=[7.0, 2.2], center=[1.9, sx - 0.12, sz - 0.2]),
        npc=dict(size=[3.0, 3.0], center=[2.0, k["npc_y"], k["p"] + 0.3]),
        figure=(-14.5, -10.5),
    )


def _jar(col, name, x, y, z, fill):
    cylinder(col, name, "SkyBlue", 0.5, 0.9, z, center=(x, y), segments=10, bevel=0.12)
    cylinder(col, name + "Fill", fill, 0.38, 0.55, z + 0.08, center=(x, y - 0.0), segments=10, bevel=0.08)
    cylinder(col, name + "Lid", "Choco", 0.52, 0.2, z + 0.9, center=(x, y), segments=10, bevel=0.06)


def build_upgrade_shop():
    col, k = booth("UpgradeShop", "Mint", "Mint")
    sx, sz = k["sign"]
    ex, ey, ez = k["emblem"]
    # emblem: a cream gear and a mint scoop on a cone
    disc_n(col, "Gear", "Cream", 1.0, 0.25, (ex - 0.5, ey, ez), (0, -1, 0), segments=16)
    for i in range(8):
        a = 2 * math.pi * i / 8
        t = rounded_box(col, f"GearTooth{i}", "Cream", (0.5, 0.25, 0.5), (0, 0, 0), radius=0.08, segments=1)
        t.rotation_euler = (0, a, 0)
        t.location = (ex - 0.5 + 1.15 * math.cos(a), ey, ez + 1.15 * math.sin(a))
    disc_n(col, "GearHole", "Mint", 0.38, 0.3, (ex - 0.5, ey - 0.07, ez), (0, -1, 0), segments=12)
    scoop_icon(col, "SignCone", (ex + 1.2, ey - 0.05, ez - 0.1), (0, -1, 0), 1.9, "Mint")
    # props: jars on the shelf, wrenches on the back wall, an anvil on the counter, a chart board in front
    for i, (x, fill) in enumerate(((-6.5, "Pink"), (-5.0, "Mint"), (-3.5, "Gold"), (-2.0, "Mint"), (-0.5, "Pink"))):
        _jar(col, f"Jar{i}", x, B["d"] / 2 - 1.8, k["shelf"] + 0.18, fill)
    for i, x in enumerate((5.0, 6.3)):
        rounded_box(col, f"Wrench{i}", "Steel", (0.35, 0.2, 2.4), (x, B["d"] / 2 - 1.1, k["shelf"] - 0.3), radius=0.08,
                    segments=1)
        disc_n(col, f"WrenchHead{i}", "Steel", 0.45, 0.2, (x, B["d"] / 2 - 1.15, k["shelf"] + 1.0), (0, -1, 0),
               segments=10)
    c = k["counter"]
    rounded_box(col, "AnvilFoot", "Steel", (1.2, 1.0, 0.6), (5.0, k["cy"] + 0.2, c + 0.3), radius=0.1, segments=1)
    rounded_box(col, "AnvilTop", "Steel", (2.6, 1.1, 0.6), (5.2, k["cy"] + 0.2, c + 0.9), radius=0.15, segments=1)
    _jar(col, "CounterJarA", -5.5, k["cy"] + 0.3, c, "Pink")
    _jar(col, "CounterJarB", -4.2, k["cy"] + 0.3, c, "Mint")
    bx, by = -B["w"] / 2 - 0.2, -B["d"] / 2 - 2.2
    for s in (-1, 1):
        t = rounded_box(col, f"BoardLeg{s}", "Wood", (0.3, 0.3, 4.2), (0, 0, 0), radius=0.08, segments=1)
        t.rotation_euler = (math.radians(12 * s), 0, 0)
        t.location = (bx, by + s * 0.45, 2.0)
    rounded_box(col, "BoardFrame", "Gold", (2.8, 0.3, 3.4), (bx, by - 0.3, 2.6), radius=0.15, segments=1)
    rounded_box(col, "Board", "Choco", (2.3, 0.3, 2.9), (bx, by - 0.38, 2.6), radius=0.1, segments=1)
    for i, h in enumerate((0.7, 1.1, 1.6)):
        rounded_box(col, f"Bar{i}", "Mint", (0.45, 0.1, h), (bx - 0.7 + i * 0.7, by - 0.58, 1.55 + h / 2), radius=0.05,
                    segments=1)
    _common_spec("UpgradeShop", k, [box((2.8, 1.4, 3.6), (bx, by, 1.8), name="Board")])


def build_cosmetic_shop():
    col, k = booth("CosmeticShop", "Pink", "Lavender")
    ex, ey, ez = k["emblem"]
    star = []
    for i in range(8):
        a = math.pi / 2 + i * math.pi / 4
        r = 1.6 if i % 2 == 0 else 0.55
        star.append((r * math.cos(a), r * math.sin(a)))
    plate(col, "Star", "Gold", star, (ex, ey, ez), (0, -1, 0), 0.25, bevel=0.06)
    for i, (dx, dz, s) in enumerate(((1.5, 1.0, 0.45), (1.7, -0.9, 0.35))):
        small = [(p[0] * s, p[1] * s) for p in star]
        plate(col, f"Sparkle{i}", "Gold", small, (ex + dx, ey, ez + dz), (0, -1, 0), 0.2, bevel=0.04)
    # heads with a crown, bunny ears and a hat on the shelf
    y = B["d"] / 2 - 1.8
    for i, x in enumerate((-5.5, -2.0, 1.5)):
        cylinder(col, f"Stand{i}", "Cream", 0.45, 0.5, k["shelf"] + 0.18, center=(x, y), segments=10, bevel=0.1)
        ball(col, f"Head{i}", "Cream", 0.85, (x, y, k["shelf"] + 1.4), segments=12)
    hz = k["shelf"] + 2.1
    cylinder(col, "Crown", "Gold", 0.75, 0.6, hz, center=(-5.5, y), segments=10, bevel=0.08)
    for i in range(5):
        a = 2 * math.pi * i / 5
        ball(col, f"CrownTip{i}", "Gold", 0.18, (-5.5 + 0.7 * math.cos(a), y + 0.7 * math.sin(a), hz + 0.75),
             segments=8)
    for s in (-1, 1):
        leaves(col, f"Ear{s}", "Cream", [((-2.0 + s * 0.35, y, hz - 0.2), math.pi / 2, 1.35, 1.6, 0.6)])
    cylinder(col, "HatBrim", "Choco", 1.05, 0.15, hz - 0.15, center=(1.5, y), segments=14, bevel=0.05)
    cylinder(col, "Hat", "Choco", 0.7, 0.8, hz - 0.05, center=(1.5, y), segments=14, bevel=0.15)
    # a gift and three cones on the counter, a standing mirror in front
    c = k["counter"]
    rounded_box(col, "Gift", "Lavender", (1.6, 1.4, 1.3), (-5.5, k["cy"] + 0.3, c + 0.65), radius=0.12, segments=1)
    rounded_box(col, "GiftRibbon", "Gold", (0.3, 1.5, 1.4), (-5.5, k["cy"] + 0.3, c + 0.65), radius=0.05, segments=1)
    for i, (x, scoop) in enumerate(((4.4, "Pink"), (5.4, "SkyBlue"), (6.4, "Choco"))):
        cylinder(col, f"Cone{i}", "Waffle", 0.18, 1.1, c + 0.1, center=(x, k["cy"] + 0.4), segments=8, bevel=0.0,
                 radius_top=0.4)
        ball(col, f"ConeScoop{i}", scoop, 0.45, (x, k["cy"] + 0.4, c + 1.4), segments=10)
    mx, my = -B["w"] / 2 - 0.4, -B["d"] / 2 - 2.0
    rounded_box(col, "MirrorFoot", "Gold", (2.2, 1.2, 0.3), (mx, my, 0.15), radius=0.1, segments=1)
    plate(col, "MirrorFrame", "Gold", circle(1.5, 20), (mx, my + 0.15, 2.8), (0, -1, 0), 0.3, bevel=0.1)
    plate(col, "MirrorGlass", "SkyBlue", circle(1.2, 20), (mx, my - 0.05, 2.8), (0, -1, 0), 0.25, bevel=0.05)
    for s in (-1, 1):
        rounded_box(col, f"MirrorPost{s}", "Gold", (0.25, 0.25, 2.0), (mx + s * 1.0, my + 0.1, 1.1), radius=0.08,
                    segments=1)
    _common_spec("CosmeticShop", k, [box((3.0, 1.4, 4.4), (mx, my, 2.2), name="Mirror")])


def build_quest_hub():
    col, k = booth("QuestHub", "Blue", "Blue")
    ex, ey, ez = k["emblem"]
    # emblem: a cream scroll with a red exclamation mark
    plate(col, "Scroll", "Cream", [(-1.0, -1.3), (1.0, -1.3), (1.0, 1.3), (-1.0, 1.3)], (ex, ey, ez), (0, -1, 0), 0.25,
          bevel=0.08)
    for s in (-1, 1):
        t = cylinder(col, f"ScrollRoll{s}", "Cream", 0.32, 2.4, 0, segments=10, bevel=0.08)
        t.rotation_euler = (0, math.pi / 2, 0)
        t.location = (ex - 1.2, ey - 0.25, ez + s * 1.3)
    rounded_box(col, "Mark", "Cherry", (0.35, 0.15, 1.2), (ex, ey - 0.3, ez + 0.25), radius=0.1, segments=1)
    ball(col, "MarkDot", "Cherry", 0.22, (ex, ey - 0.3, ez - 0.75), segments=8)
    # scrolls and books on the shelf, a notice board on the back wall, a book and a quill on the counter
    y = B["d"] / 2 - 1.8
    for i in range(3):
        t = cylinder(col, f"ShelfScroll{i}", "Cream", 0.35, 2.0, 0, segments=10, bevel=0.08)
        t.rotation_euler = (0, math.pi / 2, 0)
        t.location = (-7.0, y - 0.3 + i * 0.4, k["shelf"] + 0.55 + (0.5 if i == 1 else 0))
    for i, (colour, h) in enumerate((("Blue", 1.6), ("Cherry", 1.8), ("Gold", 1.5), ("Mint", 1.7))):
        rounded_box(col, f"Book{i}", colour, (0.45, 1.3, h), (-3.6 + i * 0.5, y, k["shelf"] + 0.18 + h / 2),
                    radius=0.06, segments=1)
    nb_x = 5.2
    rounded_box(col, "NoticeFrame", "Caramel", (5.0, 0.4, 4.4), (nb_x, B["d"] / 2 - 1.1, k["shelf"] - 0.6),
                radius=0.15, segments=1)
    rounded_box(col, "NoticeCork", "Wood", (4.3, 0.4, 3.7), (nb_x, B["d"] / 2 - 1.2, k["shelf"] - 0.6), radius=0.1,
                segments=1)
    for i, (dx, dz) in enumerate(((-1.1, 0.8), (1.0, 0.9), (-0.2, -0.9))):
        rounded_box(col, f"Note{i}", "Cream", (1.4, 0.12, 1.2), (nb_x + dx, B["d"] / 2 - 1.45, k["shelf"] - 0.6 + dz),
                    radius=0.04, segments=1)
        ball(col, f"Pin{i}", "Cherry", 0.14, (nb_x + dx, B["d"] / 2 - 1.55, k["shelf"] - 0.1 + dz), segments=8)
    c = k["counter"]
    rounded_box(col, "CounterBookA", "Blue", (2.0, 1.4, 0.35), (4.6, k["cy"] + 0.3, c + 0.18), radius=0.06, segments=1)
    rounded_box(col, "CounterBookB", "Cherry", (1.9, 1.3, 0.35), (4.6, k["cy"] + 0.3, c + 0.53), radius=0.06,
                segments=1)
    cylinder(col, "Ink", "Choco", 0.35, 0.5, c, center=(-4.8, k["cy"] + 0.3), segments=10, bevel=0.08)
    leaves(col, "Quill", "Cream", [((-4.8, k["cy"] + 0.3, c + 0.4), 0.3, 1.2, 1.6, 0.45)])
    # a mailbox in front left, crates in front right
    mx, my = -B["w"] / 2 - 0.4, -B["d"] / 2 - 2.0
    cylinder(col, "MailPost", "Wood", 0.25, 2.6, 0, center=(mx, my), segments=8, bevel=0.06)
    rounded_box(col, "MailBox", "Blue", (1.6, 2.2, 1.4), (mx, my, 3.2), radius=0.5, segments=2)
    plate(col, "Letter", "Cream", [(-0.5, -0.32), (0.5, -0.32), (0.5, 0.32), (-0.5, 0.32)], (mx, my - 1.1, 3.1),
          (0, -1, 0), 0.08, bevel=0.02)
    rounded_box(col, "MailFlag", "Cherry", (0.15, 0.6, 0.9), (mx + 0.85, my + 0.3, 3.7), radius=0.04, segments=1)
    cx, cyy = B["w"] / 2 + 0.6, -B["d"] / 2 - 1.8
    for i, (dx, dy, dz, s) in enumerate(((0, 0, 0, 1.8), (0.2, 0.1, 1.8, 1.5), (-1.9, 0.4, 0, 1.5))):
        rounded_box(col, f"Crate{i}", "Waffle", (s, s, s), (cx + dx, cyy + dy, dz + s / 2), radius=0.15, segments=1)
        for sgn in (-1, 1):
            t = rounded_box(col, f"CrateX{i}{sgn}", "Wood", (s * 1.25, 0.12, 0.22), (0, 0, 0), radius=0.05, segments=1)
            t.rotation_euler = (0, sgn * math.pi / 4, 0)
            t.location = (cx + dx, cyy + dy - s / 2 - 0.07, dz + s / 2)
    _common_spec("QuestHub", k, [box((1.8, 2.4, 4.0), (mx, my, 2.0), name="Mailbox"),
                                 box((3.8, 2.0, 3.4), (cx - 0.9, cyy + 0.2, 1.7), name="Crates")])


BUILDERS = {
    "UpgradeShop": build_upgrade_shop,
    "CosmeticShop": build_cosmetic_shop,
    "QuestHub": build_quest_hub,
}

for _name in PACK or list(BUILDERS):
    BUILDERS[_name]()
    finish(_name)


# --------------------------------------------------------------------------------------------------------------------
# the Studio template script (the hub kit's, written from shopkit_models.json), plus the invisible parts NameField
# (Front to the front, for the name's SurfaceGui) and NpcSpot (the free floor behind the counter)


def write_shop_studio_script():
    import json
    import os

    write_studio_script()
    path = os.path.join(HUB_DIR, "studio_shopkit_templates.luau")
    with open(os.path.join(HUB_DIR, "shopkit_models.json"), encoding="utf-8") as f:
        report = json.load(f)
    lines = ["", "-- invisible parts: NameField (the sign's name field, Front to the model's front) and NpcSpot",
             "local FACES = {"]
    for name in sorted(report):
        entries = [(label, report[name][key]) for key, label in (("name_field", "NameField"), ("npc", "NpcSpot"))
                   if report[name].get(key)]
        if entries:
            lines.append(f"\t{name} = {{")
            for label, spec in entries:
                w, h = spec["size"]
                size = f"Vector3.new({w:g}, {h:g}, 0.05)" if label == "NameField" else f"Vector3.new({w:g}, 0.2, {h:g})"
                lines.append(f'\t\t{{ name = "{label}", size = {size}, centre = {_v3(_rb(spec["center"]))} }},')
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
			if spec.name == "NameField" then
				p:SetAttribute("TextFace", "Front")
			end
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


write_shop_studio_script()
