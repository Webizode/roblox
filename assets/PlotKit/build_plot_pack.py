"""The plot pack: every model on a player's plot island, in the order they were built. References in the vault
(C:\\Users\\Wobble\\Desktop\\claude gehirn\\Wobble Scoops, partly in "Wooble scoops Map assets"):
    SellCart        "3D-Eiswagen-Modellübersicht in Pink unerquicklich"
    WorkingStation  "Naschwerkstatt für Eiscreme-Handwerk" (room behind the counter for an NPC, not built)
    ScoopChest      "Glänzende Eistruhe mit bunten Eiskugeln" (the lid its own part, it opens later)
    PlotSign        "Bunte Eiscreme-Spielwelt_ Plot-Schild Varianten" (a free face for name and level, text by code)
    PathStraight, PathCurve, PathRound   "Bonbon-Wege für Eiscremewelten"
    FenceSection, FencePost              "Stilisierter Holzzaun mit rosa Akzenten"
The whole plot: "Eiscreme-Insel_ Spielerplot-Layout" (run_plotkit.py -- +layout).

Run through run_plotkit.py (background Blender). Studs, origin at the bottom centre, front -Y: the side a player
stands at. Nothing hangs out over the spot in front: a player's tower rises 1.5 studs behind them, 30 studs on a
starter cone, up to about 100.
"""

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

# per model: the simple collision for the Studio template (studs, in the model's frame, z up from its pivot) and where
# the preview figure stands
SPECS = {}


def disc(col, name, colour, radius, thickness, center, axis="Y", segments=16, bevel=0.1, bevel_segments=1):
    """A round block whose axis lies along X or Y (wheels, badges, scallops), centred at `center`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=radius,
                          depth=thickness)
    turn = Matrix.Rotation(math.pi / 2, 3, "X" if axis == "Y" else "Y")
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=turn, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    ob = _object(col, name, bm, colour, smooth_angle=40)
    if bevel:
        _bevel(ob, min(bevel, thickness / 2 - 1e-3), bevel_segments, angle=40)
    return ob


def ball(col, name, colour, radius, center, squash=1.0, segments=12):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=max(4, segments // 2), radius=radius)
    bmesh.ops.scale(bm, vec=Vector((1, 1, squash)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return _object(col, name, bm, colour, smooth_angle=80)


def wheel(col, name, radius, center, thickness=0.45, spokes=6, axis="Y"):
    """A cart wheel: Waffle rim, spokes, Pink hub."""
    x, y, z = center
    rim = 0.32
    # the rim as a ring: an outer disc with the middle cut out by building a torus-like ring of boxes is costly; a
    # short tube from a curve keeps it round and light
    pts = []
    for i in range(25):
        a = 2 * math.pi * i / 24
        if axis == "Y":
            pts.append((x + (radius - rim / 2) * math.cos(a), y, z + (radius - rim / 2) * math.sin(a)))
        else:
            pts.append((x, y + (radius - rim / 2) * math.cos(a), z + (radius - rim / 2) * math.sin(a)))
    _tube(col, name + "_Rim", "Waffle", [pts], rim * 1.6, sides=6)
    for k in range(spokes):
        a = math.pi * k / spokes
        r = radius - rim
        if axis == "Y":
            a0 = (x + r * math.cos(a), y, z + r * math.sin(a))
            a1 = (x - r * math.cos(a), y, z - r * math.sin(a))
        else:
            a0 = (x, y + r * math.cos(a), z + r * math.sin(a))
            a1 = (x, y - r * math.cos(a), z - r * math.sin(a))
        _tube(col, f"{name}_Spoke{k}", "Waffle", [[a0, a1]], 0.22, sides=4)
    disc(col, name + "_Hub", "Pink", radius * 0.28, thickness + 0.15, center, axis=axis, segments=12, bevel=0.08)


def lantern(col, name, center, bracket_to=None):
    """A hanging lantern: Waffle cap and foot, Gold glass (the light; a PointLight goes there in Studio), on a
    Waffle bracket from `bracket_to` (x, y, z of the post's face)."""
    x, y, z = center
    rounded_box(col, name + "_Cap", "Waffle", (0.9, 0.9, 0.3), (x, y, z + 0.6), radius=0.1, segments=1)
    cylinder(col, name + "_Top", "Waffle", 0.28, 0.35, z + 0.75, center=(x, y), segments=8, bevel=0.08,
             bevel_segments=1)
    rounded_box(col, name + "_Glass", "Gold", (0.7, 0.7, 0.85), (x, y, z), radius=0.12, segments=1)
    rounded_box(col, name + "_Foot", "Waffle", (0.8, 0.8, 0.25), (x, y, z - 0.55), radius=0.08, segments=1)
    if bracket_to:
        bx, by, bz = bracket_to
        _tube(col, name + "_Bracket", "Waffle", [[(bx, by, bz), (x, y, bz), (x, y, z + 0.9)]], 0.18, sides=4)


def awning(col, name, length, depth, back_z, front_z, stripes, center_y=0.0, scallops=True, colours=("Pink", "Cream"),
           ridge_z=None, ridge_at=0.35):
    """A striped awning from back_z (at +Y) to front_z (at -Y), `stripes` stripes along X in turn, with a scalloped
    valance on the front and back edge. With ridge_z it is a soft gable: up from both edges to a ridge `ridge_at` of
    the depth behind the front edge, so it reads domed like a candy canopy. Returns the front edge's y and z."""
    w = length / stripes
    y_front, y_back = center_y - depth / 2, center_y + depth / 2
    if ridge_z is None:
        slopes = [((y_front, front_z), (y_back, back_z))]
    else:
        y_ridge = y_front + depth * ridge_at
        slopes = [((y_front, front_z), (y_ridge, ridge_z)), ((y_ridge, ridge_z), (y_back, back_z))]
    for i in range(stripes):
        x = -length / 2 + w * (i + 0.5)
        for k, ((ya, za), (yb, zb)) in enumerate(slopes):
            run = math.hypot(yb - ya, zb - za) + (0.25 if len(slopes) > 1 else 0)
            ob = rounded_box(col, f"{name}_Stripe{i}_{k}", colours[i % 2], (w + 0.02, run, 0.32), (0, 0, 0),
                             radius=0.1, segments=2)
            ob.rotation_euler = (math.atan2(zb - za, yb - ya), 0, 0)
            ob.location = (x, (ya + yb) / 2, (za + zb) / 2)
        if scallops:
            for side, sy, sz in ((-1, center_y - depth / 2, front_z), (1, center_y + depth / 2, back_z)):
                disc(col, f"{name}_Scallop{i}{'F' if side < 0 else 'B'}", colours[i % 2], w * 0.5, 0.3,
                     (x, sy + side * 0.05, sz - 0.25), axis="Y", segments=14, bevel=0.1)
    return center_y - depth / 2, front_z


# --------------------------------------------------------------------------------------------------------------------
# Sell Cart: a pink ice cream cart with a striped awning, the cone badge on top, two lanterns, a register, a stack of
# cones and a tray of scoops on the counter, a big wheel on each long side. The customer side is the front (-Y),
# where the player stands to sell. The counter stays low (2.35, 3.5 once scaled by SCALE) while the cart is big, so a
# player and a seller behind it show above it from the waist up; the wheels are kept below it. The awning reaches only
# 0.8 past the body (1.2 scaled): a tower behind a player at the counter stays clear of it.
SC = dict(L=11.0, D=5.0, body_z0=0.55, counter=2.35, post=0.45, awning_back=8.9, awning_front=8.4, ridge=10.0)


def build_sell_cart():
    col = pk_collection("SellCart")
    L, D, z0, top = SC["L"], SC["D"], SC["body_z0"], SC["counter"]
    body_h = top - 0.5 - z0
    # the body: Pink panels in a Waffle frame
    rounded_box(col, "Body", "Pink", (L - 0.3, D - 0.3, body_h), (0, 0, z0 + body_h / 2), radius=0.3, segments=2)
    rounded_box(col, "Rail", "Waffle", (L + 0.2, D + 0.2, 0.5), (0, 0, z0 + 0.15), radius=0.18, segments=1)
    for sx in (-1, 1):
        for sy in (-1, 1):
            rounded_box(col, "Corner", "Waffle", (0.6, 0.6, body_h + 0.3), (sx * (L / 2 - 0.2), sy * (D / 2 - 0.2),
                        z0 + body_h / 2), radius=0.15, segments=1)
    # the counter: Cream icing with drips over the front and the back
    glaze(col, "Counter", length=L + 0.6, depth=D + 0.6, top=top, thickness=0.55, drips={
        "front": [(-L * 0.18, 1.6, 0.8), (L * 0.12, 1.3, 0.5), (L * 0.36, 1.5, 0.7)],
        "back": [(-L * 0.3, 1.4, 0.6), (L * 0.05, 1.6, 0.8)],
    }, drip_base=0.3, columns=24, seed=7)
    cone_emblem(col, "Emblem", (-L * 0.3, -(D / 2 - 0.12), z0 + body_h * 0.5), (0, -1, 0), width=1.7, height=2.1)
    # wheels: a big one at the right on both long sides, small ones at the left
    for sy in (-1, 1):
        wheel(col, f"Wheel{'F' if sy < 0 else 'B'}", 1.1, (L * 0.26, sy * (D / 2 + 0.3), 1.1))
        wheel(col, f"Small{'F' if sy < 0 else 'B'}", 0.5, (-L * 0.38, sy * (D / 2 - 0.1), 0.5), spokes=3)
    # the posts and the awning
    px, py = L / 2 - 0.45, D / 2 - 0.45
    post_top = SC["awning_front"] - 0.1
    for sx in (-1, 1):
        for sy in (-1, 1):
            rounded_box(col, "Post", "Waffle", (SC["post"], SC["post"], post_top - top + 0.1),
                        (sx * px, sy * py, (top + post_top) / 2), radius=0.12, segments=1)
    awning(col, "Awning", L + 1.0, D + 1.6, SC["awning_back"], SC["awning_front"], stripes=9, ridge_z=SC["ridge"])
    rounded_box(col, "Ridge", "Gold", (L + 1.2, 0.5, 0.45), (0, -(D + 1.6) / 2 + (D + 1.6) * 0.35, SC["ridge"] + 0.2),
                radius=0.18, segments=1)
    # the cone badge on the roof: a Cream disc in a Gold ring with the cone shield on it
    badge_z = SC["ridge"] + 1.9
    disc(col, "BadgeRing", "Gold", 2.15, 0.5, (0, 0.4, badge_z), axis="Y", segments=24, bevel=0.15)
    disc(col, "Badge", "Cream", 1.9, 0.6, (0, 0.35, badge_z), axis="Y", segments=24, bevel=0.15)
    cone_emblem(col, "BadgeCone", (0, 0.05, badge_z), (0, -1, 0), width=2.0, height=2.7)
    rounded_box(col, "BadgeFoot", "Gold", (1.2, 0.6, 1.0), (0, 0.4, SC["ridge"] + 0.3), radius=0.2,
                segments=1)
    # lanterns on the front posts, outside
    for sx in (-1, 1):
        lantern(col, f"Lantern{'L' if sx < 0 else 'R'}", (sx * (L / 2 + 0.55), -py, 6.6),
                bracket_to=(sx * (px + SC["post"] / 2), -py, 7.6))
    # on the counter: register, cones, a tray of scoops
    rounded_box(col, "Register", "Waffle", (1.7, 1.2, 0.9), (-L * 0.32, 0.2, top + 0.45), radius=0.15, segments=1)
    screen = rounded_box(col, "Screen", "SkyBlue", (1.3, 0.2, 0.8), (0, 0, 0), radius=0.08, segments=1)
    screen.rotation_euler = (math.radians(-20), 0, 0)
    screen.location = (-L * 0.32, 0.55, top + 1.25)
    rounded_box(col, "Keys", "Cream", (1.2, 0.5, 0.12), (-L * 0.32, -0.15, top + 0.93), radius=0.05, segments=1)
    for i in range(4):
        cylinder(col, f"Cone{i}", "Waffle", 0.42, 0.55, top + 0.05 + i * 0.32, center=(-L * 0.12, 0.6),
                 segments=10, bevel=0.06, bevel_segments=1, radius_top=0.55)
    rounded_box(col, "Tray", "Cream", (4.0, 2.2, 0.55), (L * 0.2, 0.35, top + 0.27), radius=0.2, segments=1)
    rounded_box(col, "TrayRim", "Pink", (4.2, 2.4, 0.3), (L * 0.2, 0.35, top + 0.12), radius=0.12, segments=1)
    colours = ("Pink", "Cream", "Gold", "SkyBlue", "Cherry", "Pink")
    for i in range(6):
        ball(col, f"Scoop{i}", colours[i], 0.55, (L * 0.2 - 1.35 + (i % 3) * 1.35, 0.35 - 0.5 + (i // 3) * 1.0,
             top + 0.75), squash=0.85, segments=10)
    SPECS["SellCart"] = dict(
        collision=[dict(kind="box", size=[L + 0.6, D + 1.2, top], center=[0, 0, top / 2])],
        figure=(-L * 0.42, -(D / 2 + 1.7)),
        note="customer side -Y; counter top 2.35 (3.5 scaled); awning edge 0.8 past the body",
    )
    return col


def gear(col, name, center, radius, teeth=10, thickness=0.6):
    """A Gold gear standing upright, facing -Y: a disc with teeth round it and a Cream face in the middle."""
    cx, cy, cz = center
    disc(col, name + "_Disc", "Gold", radius, thickness, center, axis="Y", segments=24, bevel=0.15)
    for k in range(teeth):
        a = 2 * math.pi * k / teeth
        t = rounded_box(col, f"{name}_Tooth{k}", "Gold", (0.95, thickness, 0.8), (0, 0, 0), radius=0.18, segments=1)
        t.rotation_euler = (0, -a, 0)
        t.location = (cx + (radius + 0.25) * math.cos(a), cy, cz + (radius + 0.25) * math.sin(a))
    disc(col, name + "_Face", "Cream", radius * 0.78, thickness + 0.1, (cx, cy - 0.05, cz), axis="Y", segments=24,
         bevel=0.15)


def tank(col, name, center, radius, height, gauge_side=-1):
    """A tall Cream tank with Gold bands, a Pink glaze cap with drips and a gauge on its front."""
    x, y = center
    cylinder(col, name + "_Body", "Cream", radius, height, 0.0, center=(x, y), segments=20, bevel=0.3)
    for z in (0.5, height * 0.42):
        cylinder(col, name + "_Band", "Gold", radius + 0.12, 0.55, z, center=(x, y), segments=20, bevel=0.15,
                 bevel_segments=1)
    cap_slab, cap_drips = round_glaze(col, name + "_Cap", radius + 0.15, height + 0.7, thickness=0.8, drips=7,
                                      drop=(0.5, 1.2), center=(x, y), seed=9, columns=28, segments=20,
                                      bevel_segments=1)
    for ob in (cap_slab, cap_drips):
        ob.data.materials[0] = material("Pink")
    cylinder(col, name + "_Lid", "Pink", radius * 0.55, 0.6, height + 0.6, center=(x, y), segments=16, bevel=0.2)
    gy = y + gauge_side * (radius + 0.1)
    gz = height * 0.68
    disc(col, name + "_GaugeRing", "Gold", 0.95, 0.3, (x, gy, gz), axis="Y", segments=16, bevel=0.1)
    disc(col, name + "_Gauge", "Cream", 0.75, 0.35, (x, gy + gauge_side * 0.04, gz), axis="Y", segments=16,
         bevel=0.08)
    needle = rounded_box(col, name + "_Needle", "Cherry", (0.12, 0.1, 0.6), (0, 0, 0), radius=0.04, segments=1)
    needle.rotation_euler = (0, math.radians(35), 0)
    needle.location = (x + 0.15, gy + gauge_side * 0.25, gz + 0.2)
    return height + 1.3


def waffle_box(col, name, size, center, emblem=False, brace=False):
    """A wooden crate in Waffle: the body, a raised Waffle frame round the front and back with Pink corner caps, and a
    cone emblem or a Gold X on the front (the reference's wooden crates)."""
    sx, sy, sz = size
    cx, cy, cz = center
    rounded_box(col, name + "_Body", "Waffle", (sx - 0.2, sy - 0.2, sz - 0.2), center, radius=0.2, segments=1)
    for side in (-1, 1):
        fy = cy + side * (sy / 2 - 0.1)
        for dz in (-1, 1):
            rounded_box(col, name + "_Frame", "Waffle", (sx, 0.4, 0.45), (cx, fy, cz + dz * (sz / 2 - 0.22)),
                        radius=0.14, segments=1)
        for dx in (-1, 1):
            rounded_box(col, name + "_Frame", "Waffle", (0.45, 0.4, sz), (cx + dx * (sx / 2 - 0.22), fy, cz),
                        radius=0.14, segments=1)
            for dz in (-1, 1):
                rounded_box(col, name + "_CornerCap", "Pink", (0.6, 0.5, 0.6),
                            (cx + dx * (sx / 2 - 0.22), fy, cz + dz * (sz / 2 - 0.22)), radius=0.18, segments=1)
    front = cy - sy / 2 - 0.25
    if emblem:
        cone_emblem(col, name + "_Emblem", (cx, front, cz), (0, -1, 0), width=1.5, height=1.9)
    if brace:
        for s in (-1, 1):
            b = rounded_box(col, f"{name}_Brace{s}", "Gold", (sx * 1.15, 0.2, 0.35), (0, 0, 0), radius=0.08,
                            segments=1)
            b.rotation_euler = (0, s * math.atan2(sz - 0.8, sx - 0.8), 0)
            b.location = (cx, front + 0.05, cz)


# --------------------------------------------------------------------------------------------------------------------
# Working Station: the crafting booth. Booth with a striped gable awning and the gear badge with the cone, a tank on
# either side (Pink glaze cap, gauge, a Gold pipe over to the roof), waffle crates in front of the tanks, a counter at
# the front with the tools emblem, a screen and two bottles, a mixing bowl at the back. Between counter and back wall
# a free floor 10 x 4 for the NPC (not built). The counter is low (2.35, 3.5 once scaled), so the NPC shows above it
# from the waist up. The player stands in front of the counter; the awning reaches 0.45 past it.
WS = dict(half=5.6, front=-2.6, back=3.2, counter=2.35, counter_depth=1.6, awning_front=8.6, ridge=10.6,
          awning_back=9.4, tank_x=9.3, tank_r=2.3, tank_h=8.0)


def build_working_station():
    col = pk_collection("WorkingStation")
    h, f, b, top = WS["half"], WS["front"], WS["back"], WS["counter"]
    # floor of the booth, back wall, posts
    rounded_box(col, "Floor", "Waffle", (2 * h + 0.6, b - f + 0.8, 0.3), (0, (f + b) / 2, 0.15), radius=0.12,
                segments=1)
    rounded_box(col, "Mat", "Pink", (4.0, 2.2, 0.08), (0.8, 1.0, 0.33), radius=0.04, segments=1)
    rounded_box(col, "Wall", "Pink", (2 * h, 0.5, WS["awning_back"] - 0.3), (0, b, (WS["awning_back"] - 0.3) / 2),
                radius=0.2, segments=1)
    for z in (1.2, 4.6):
        rounded_box(col, "WallRail", "Waffle", (2 * h + 0.2, 0.7, 0.45), (0, b - 0.05, z), radius=0.15, segments=1)
    for sx in (-1, 1):
        for y in (f, b - 0.1):
            rounded_box(col, "Post", "Waffle", (0.6, 0.6, WS["awning_front"] - 0.1),
                        (sx * h, y, (WS["awning_front"] - 0.1) / 2), radius=0.15, segments=1)
    # the counter at the front
    cf, cb = f - 0.2, f - 0.2 + WS["counter_depth"]
    body_h = top - 0.5
    rounded_box(col, "Counter", "Pink", (2 * h - 0.6, WS["counter_depth"] - 0.2, body_h), (0, (cf + cb) / 2,
                body_h / 2 + 0.2), radius=0.25, segments=2)
    glaze_slab, glaze_drips = glaze(col, "CounterTop", length=2 * h - 0.2, depth=WS["counter_depth"] + 0.3, top=top,
                                    thickness=0.5, drips={"front": [(-2.8, 1.4, 0.7), (0.6, 1.8, 0.9),
                                                                    (3.4, 1.2, 0.5)],
                                                          "back": [(0.0, 1.4, 0.4)]}, drip_base=0.3, columns=24,
                                    seed=11)
    for ob in (glaze_slab, glaze_drips):
        ob.location.y += (cf + cb) / 2
    # the tools emblem: a Cream plate with a Gold X of two tools
    rounded_box(col, "ToolPlate", "Cream", (2.4, 0.2, 1.4), (-2.6, cf - 0.08, (top - 0.3) / 2), radius=0.15,
                segments=1)
    for s in (-1, 1):
        tool = rounded_box(col, f"Tool{s}", "Gold", (1.7, 0.2, 0.3), (0, 0, 0), radius=0.08, segments=1)
        tool.rotation_euler = (0, s * math.radians(40), 0)
        tool.location = (-2.6, cf - 0.2, (top - 0.3) / 2)
        disc(col, f"ToolHead{s}", "Gold", 0.32, 0.22, (-2.6 + s * 0.6, cf - 0.2, (top - 0.3) / 2 + 0.5), axis="Y",
             segments=10, bevel=0.06)
    # on the counter: screen and two bottles
    rounded_box(col, "Device", "Waffle", (1.6, 1.0, 0.7), (-3.4, (cf + cb) / 2, top + 0.35), radius=0.12, segments=1)
    scr = rounded_box(col, "Screen", "SkyBlue", (1.3, 0.18, 0.95), (0, 0, 0), radius=0.08, segments=1)
    scr.rotation_euler = (math.radians(-15), 0, 0)
    scr.location = (-3.4, (cf + cb) / 2 + 0.3, top + 1.15)
    for i, (x, colour) in enumerate(((2.9, "SkyBlue"), (3.8, "Pink"))):
        cylinder(col, f"Bottle{i}", colour, 0.38, 0.8, top, center=(x, (cf + cb) / 2), segments=12, bevel=0.15)
        cylinder(col, f"BottleNeck{i}", "Cream", 0.16, 0.45, top + 0.8, center=(x, (cf + cb) / 2), segments=8,
                 bevel=0.05, bevel_segments=1)
    # the mixing bowl at the back left, under a Gold nozzle from the wall
    bx, by = -3.0, b - 1.3
    cylinder(col, "BowlStand", "Waffle", 0.6, 2.4, 0.3, center=(bx, by), segments=12, bevel=0.1)
    cylinder(col, "Bowl", "Cream", 1.0, 0.9, 2.7, center=(bx, by), segments=18, bevel=0.2, radius_top=1.5)
    cylinder(col, "BowlIce", "Pink", 1.35, 0.25, 3.35, center=(bx, by), segments=18, bevel=0.1)
    _tube(col, "Nozzle", "Gold", [[(bx, b - 0.2, 6.2), (bx, by, 6.2), (bx, by, 4.7)]], 0.45, sides=6)
    cylinder(col, "NozzleTip", "Gold", 0.35, 0.5, 4.3, center=(bx, by), segments=10, bevel=0.1, radius_top=0.2)
    # awning, ridge, gear badge
    depth = b - f + 1.6
    awning(col, "Awning", 2 * h + 1.4, depth, WS["awning_back"], WS["awning_front"], stripes=11,
           center_y=(f + b) / 2, ridge_z=WS["ridge"], ridge_at=0.4)
    ridge_y = (f + b) / 2 - depth / 2 + depth * 0.4
    rounded_box(col, "Ridge", "Gold", (2 * h + 1.6, 0.5, 0.45), (0, ridge_y, WS["ridge"] + 0.2), radius=0.18,
                segments=1)
    gz = WS["ridge"] + 3.1
    rounded_box(col, "GearFoot", "Gold", (1.4, 0.6, 1.4), (0, ridge_y + 0.5, WS["ridge"] + 0.6), radius=0.2,
                segments=1)
    gear(col, "Gear", (0, ridge_y + 0.5, gz), 2.5)
    cone_emblem(col, "GearCone", (0, ridge_y + 0.1, gz), (0, -1, 0), width=2.0, height=2.6)
    # lanterns on the front posts, inside
    for sx in (-1, 1):
        lantern(col, f"Lantern{'L' if sx < 0 else 'R'}", (sx * (h - 0.9), f, 6.4), bracket_to=(sx * (h - 0.3), f, 7.4))
    # tanks with pipes over to the roof, crates in front
    tx, tr, th = WS["tank_x"], WS["tank_r"], WS["tank_h"]
    for sx in (-1, 1):
        tank_top = tank(col, f"Tank{'L' if sx < 0 else 'R'}", (sx * tx, 1.2), tr, th)
        # a thick pipe with round elbows and collars, from the tank's lid over to the booth's roof
        pz = tank_top + 1.4
        side = "L" if sx < 0 else "R"
        _tube(col, f"Pipe{side}", "Gold", [[(sx * tx, 1.2, tank_top - 0.2), (sx * tx, 1.2, pz)],
                                          [(sx * tx, 1.2, pz), (sx * (h + 0.7), 1.2, pz)],
                                          [(sx * (h + 0.7), 1.2, pz), (sx * (h + 0.7), 1.2, WS["ridge"] - 0.8)]],
              1.05, sides=10)
        for at in ((sx * tx, 1.2, pz), (sx * (h + 0.7), 1.2, pz)):
            ball(col, f"PipeElbow{side}", "Gold", 0.62, at, segments=10)
        for at in ((sx * tx, 1.2, tank_top + 0.3), (sx * (h + 0.7), 1.2, WS["ridge"] - 0.5)):
            cylinder(col, f"PipeCollar{side}", "Waffle", 0.72, 0.4, at[2] - 0.2, center=(at[0], at[1]),
                     segments=12, bevel=0.12, bevel_segments=1)
        waffle_box(col, f"Crate{'L' if sx < 0 else 'R'}", (3.6, 3.0, 3.2), (sx * (h + 2.3), f + 0.9, 1.6),
                   emblem=sx < 0, brace=sx > 0)
    SPECS["WorkingStation"] = dict(
        collision=[
            dict(kind="box", name="Counter", size=[2 * h, WS["counter_depth"] + 0.3, top],
                 center=[0, (cf + cb) / 2, top / 2]),
            dict(kind="box", name="Wall", size=[2 * h + 0.6, 0.8, WS["awning_back"]], center=[0, b, WS["awning_back"] / 2]),
            dict(kind="box", name="SideL", size=[tx + tr - h + 0.3, b - f + 1.0, th + 1.3],
                 center=[-(h - 0.3 + tx + tr) / 2, (f + b) / 2 - 0.1, (th + 1.3) / 2]),
            dict(kind="box", name="SideR", size=[tx + tr - h + 0.3, b - f + 1.0, th + 1.3],
                 center=[(h - 0.3 + tx + tr) / 2, (f + b) / 2 - 0.1, (th + 1.3) / 2]),
        ],
        figure=(1.5, cf - 1.9),
        npc=dict(center=[0.8, 1.0, 0.3], size=[2 * h - 1.2, b - cb - 0.4]),
        note="customer side -Y; NPC floor between counter and wall: 10 x 3.7 at y 1.0, floor top 0.3",
    )
    return col


def lid(*objects):
    """Marks parts as the moving lid: exported as their own meshes <Model>_Lid_<Colour>."""
    for ob in objects:
        if isinstance(ob, (list, tuple)):
            lid(*ob)
        elif ob is not None:
            ob["part"] = "Lid"
    return objects


def _quarter(yc, zc, ry, rz, steps):
    """Points of a quarter ellipse from the front bottom (yc - ry, zc) up to the top (yc, zc + rz)."""
    return [(yc - ry * math.cos(a), zc + rz * math.sin(a)) for a in (math.pi / 2 * i / steps for i in range(steps + 1))]


# --------------------------------------------------------------------------------------------------------------------
# Scoop Chest: the display freezer for the best scoops. A Pink base with a Waffle lattice front, Cream icing with drips,
# the cone emblem and SkyBlue vents; inside two steps of four scoops in Gold cups; at the back a fixed frame with the
# cone badge. The curved glass hood is the lid (its own meshes, ScoopChest_Lid_<Colour>): it turns up round the hinge
# along X at the top of the frame (SPECS hinge).
CH = dict(L=9.0, D=5.0, base=2.7, glass_top=6.0, frame_t=0.7)


def build_scoop_chest():
    col = pk_collection("ScoopChest")
    L, D, base = CH["L"], CH["D"], CH["base"]
    rounded_box(col, "Plinth", "Waffle", (L + 0.3, D + 0.3, 0.45), (0, 0, 0.22), radius=0.16, segments=1)
    rounded_box(col, "Base", "Pink", (L - 0.2, D - 0.2, base - 0.4), (0, 0, 0.4 + (base - 0.4) / 2), radius=0.25,
                segments=2)
    waffle_panel(col, "Front", (L - 1.6, 0.3, base - 1.3), (0, -(D / 2 - 0.1), 0.45 + (base - 1.3) / 2 + 0.1),
                 spacing=0.8, ridge_width=0.3, ridge_height=0.12, faces=("front",))
    glaze(col, "Icing", length=L + 0.3, depth=D + 0.3, top=base + 0.35, thickness=0.55, drips={
        "front": [(-L * 0.32, 1.3, 0.8), (-L * 0.08, 1.1, 0.5), (L * 0.32, 1.3, 0.75)],
        "back": [(-L * 0.25, 1.4, 0.6), (L * 0.2, 1.2, 0.5)],
    }, drip_base=0.3, columns=24, seed=13)
    cone_emblem(col, "Emblem", (L * 0.12, -(D / 2 + 0.05), 1.3), (0, -1, 0), width=1.7, height=2.1)
    for sx in (-1, 1):
        rounded_box(col, "VentFrame", "Cream", (0.25, 1.8, 1.1), (sx * (L / 2 - 0.02), -0.6, 1.4), radius=0.08,
                    segments=1)
        for k in range(3):
            rounded_box(col, "Vent", "SkyBlue", (0.2, 1.4, 0.18), (sx * (L / 2 + 0.06), -0.6, 1.1 + k * 0.3),
                        radius=0.06, segments=1)
    # inside: a low front step and a higher back step, four scoops in Gold cups on each
    floor = base + 0.35
    yc = D / 2 - CH["frame_t"] - 0.1  # the hinge line's y, just in front of the frame
    rounded_box(col, "StepFront", "Cream", (L - 1.2, 1.6, 0.3), (0, -0.9, floor + 0.15), radius=0.1, segments=1)
    rounded_box(col, "StepBack", "Cream", (L - 1.2, 1.5, 1.1), (0, 0.55, floor + 0.55), radius=0.12, segments=1)
    flavours = ("Cream", "Pink", "Waffle", "Cherry", "SkyBlue", "Gold", "Pink", "Cream")
    for i, colour in enumerate(flavours):
        row, k = divmod(i, 4)
        x = -L * 0.33 + k * L * 0.22
        y, z = (0.55, floor + 1.1) if row == 0 else (-0.9, floor + 0.3)
        cylinder(col, f"Cup{i}", "Gold", 0.55, 0.3, z, center=(x, y), segments=12, bevel=0.08, bevel_segments=1,
                 radius_top=0.7)
        ball(col, f"Scoop{i}", colour, 0.72, (x, y, z + 0.75), squash=0.85, segments=12)
    # the fixed frame at the back with the badge
    ft = CH["frame_t"]
    rounded_box(col, "Frame", "Pink", (L, ft, CH["glass_top"] + 0.3 - floor), (0, D / 2 - ft / 2,
                (CH["glass_top"] + 0.3 + floor) / 2), radius=0.25, segments=2)
    rounded_box(col, "FrameTop", "Waffle", (L + 0.3, ft + 0.3, 0.45), (0, D / 2 - ft / 2, CH["glass_top"] + 0.4),
                radius=0.16, segments=1)
    disc(col, "BadgeBack", "Cream", 1.5, 0.5, (0, D / 2 - ft / 2, CH["glass_top"] + 1.6), axis="Y", segments=20)
    cone_emblem(col, "Badge", (0, D / 2 - ft - 0.05, CH["glass_top"] + 1.55), (0, -1, 0), width=2.0, height=2.6)
    # the lid: the curved glass and its Pink end frames and front rim, hinged at (yc, glass_top) along X
    zc, ry, rz = floor, yc - (-D / 2 + 0.35), CH["glass_top"] - floor
    profile = _quarter(yc, zc, ry, rz, 10)
    bm = bmesh.new()
    x0, x1 = -L / 2 + 0.45, L / 2 - 0.45
    left = [bm.verts.new((x0, y, z)) for y, z in profile]
    right = [bm.verts.new((x1, y, z)) for y, z in profile]
    for i in range(len(profile) - 1):
        f = bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    glass = _object(col, "LidGlass", bm, "Glass", smooth_angle=80, recalc=False)
    glass_material()
    solid = glass.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = 0.15
    solid.offset = -1.0
    lid(glass)
    for sx, xs in ((-1, x0 - 0.22), (1, x1 + 0.22)):
        bm = bmesh.new()
        outline = [(yc, zc)] + profile
        outline = [(y, z) for y, z in outline]
        # a little bigger than the glass so it frames it
        grown = [(yc + (y - yc) * 1.04, zc + (z - zc) * 1.04) for y, z in outline]
        _extruded(bm, [(y, z) for y, z in grown], lambda u, v, d, xs=xs: Vector((xs - 0.22 + d, u, v)), 0.44)
        end = _object(col, f"LidEnd{'L' if sx < 0 else 'R'}", bm, "Pink", smooth_angle=40)
        _bevel(end, 0.1, 1)
        lid(end)
    lid(_tube(col, "LidRim", "Pink", [[(x0 - 0.2, profile[0][0], zc + 0.1), (x1 + 0.2, profile[0][0], zc + 0.1)]],
              0.4, sides=6))
    lid(_tube(col, "LidHinge", "Gold", [[(x0 - 0.3, yc, CH["glass_top"] + 0.02), (x1 + 0.3, yc,
                                                                                   CH["glass_top"] + 0.02)]],
              0.45, sides=8))
    lid(rounded_box(col, "LidHandle", "Gold", (1.6, 0.3, 0.35), (0, profile[0][0] - 0.25, zc + 0.6), radius=0.1,
                    segments=1))
    SPECS["ScoopChest"] = dict(
        collision=[dict(kind="box", size=[L + 0.3, D + 0.3, CH["glass_top"] + 0.6],
                        center=[0, 0, (CH["glass_top"] + 0.6) / 2])],
        hinge=dict(axis="X", y=round(yc, 2), z=CH["glass_top"], opens="lid turns up about X, front edge first, 100 deg"),
        figure=(-L * 0.3, -(D / 2 + 1.7)),
        note="customer side -Y; the glass (Lid_Glass) SkyBlue and half transparent in Studio",
    )
    return col


def frosted_post(col, name, x, height, size=0.95, seed=1):
    """A square Waffle post with a Cream frosting cap (drips all round), two Cream rope rings low down."""
    rounded_box(col, name, "Waffle", (size, size, height), (x, 0, height / 2), radius=0.18, segments=1)
    _, drips = round_glaze(col, name + "_Cap", size * 0.82, height + 0.45, thickness=0.6, drips=5,
                           drop=(0.35, 0.75), center=(x, 0), seed=seed, columns=20, segments=14, bevel_segments=1)
    drips.data.materials[0] = material("Pink")  # Pink icing running out under the Cream frosting
    for z in (1.6, 1.95):
        cylinder(col, name + "_Rope", "Cream", size * 0.68, 0.32, z, center=(x, 0), segments=14, bevel=0.14,
                 bevel_segments=1)


# --------------------------------------------------------------------------------------------------------------------
# Plot Sign: the owner's name board. Two frosted Waffle posts, a board with a Waffle frame and Pink icing on top, the
# cone badge over the middle and a lantern on each post. The Cream face in the frame is its own part
# (PlotSign_Face_Cream) and stays empty: name and level come later through a SurfaceGui on its front.
PS = dict(width=8.6, post_h=6.4, board_z0=2.6, board_z1=6.4, face=(5.6, 2.5))


def build_plot_sign():
    col = pk_collection("PlotSign")
    w, z0, z1 = PS["width"], PS["board_z0"], PS["board_z1"]
    px = w / 2 - 0.5
    for i, sx in enumerate((-1, 1)):
        frosted_post(col, f"Post{'L' if sx < 0 else 'R'}", sx * px, PS["post_h"], seed=3 + i)
    zm = (z0 + z1) / 2
    rounded_box(col, "Board", "Waffle", (w - 1.6, 0.55, z1 - z0), (0, 0, zm), radius=0.25, segments=2)
    rounded_box(col, "BoardTrim", "Gold", (w - 1.9, 0.7, 0.3), (0, 0, z0 + 0.2), radius=0.12, segments=1)
    fw, fh = PS["face"]
    face = rounded_box(col, "Face", "Cream", (fw, 0.2, fh), (0, -0.3, zm - 0.05), radius=0.12, segments=2)
    face["part"] = "Face"
    # a raised Waffle frame round the face with Gold studs in its corners
    for dz in (-1, 1):
        rounded_box(col, "Frame", "Waffle", (fw + 0.9, 0.5, 0.45), (0, -0.4, zm - 0.05 + dz * (fh / 2 + 0.22)),
                    radius=0.16, segments=1)
    for dx in (-1, 1):
        rounded_box(col, "Frame", "Waffle", (0.45, 0.5, fh + 0.9), (dx * (fw / 2 + 0.22), -0.4, zm - 0.05),
                    radius=0.16, segments=1)
        for dz in (-1, 1):
            ball(col, "Stud", "Gold", 0.2, (dx * (fw / 2 + 0.22), -0.68, zm - 0.05 + dz * (fh / 2 + 0.22)),
                 segments=8)
    slab, drips = glaze(col, "Icing", length=w - 1.4, depth=0.9, top=z1 + 0.35, thickness=0.5, drips={
        "front": [(-2.2, 0.9, 0.5), (-0.6, 0.7, 0.3), (1.9, 0.9, 0.55)],
        "back": [(-1.5, 0.8, 0.35), (1.4, 0.8, 0.4)],
    }, drip_base=0.2, columns=20, seed=17)
    for ob in (slab, drips):
        ob.data.materials[0] = material("Pink")
    # the badge
    disc(col, "BadgeBack", "Cream", 1.45, 0.45, (0, 0.05, z1 + 1.55), axis="Y", segments=20)
    cone_emblem(col, "Badge", (0, -0.25, z1 + 1.5), (0, -1, 0), width=2.0, height=2.6)
    for sx in (-1, 1):
        lantern(col, f"Lantern{'L' if sx < 0 else 'R'}", (sx * (px + 1.15), 0, 4.6),
                bracket_to=(sx * (px + 0.45), 0, 5.6))
    SPECS["PlotSign"] = dict(
        collision=[dict(kind="box", size=[w, 1.2, PS["post_h"] + 0.5], center=[0, 0, (PS["post_h"] + 0.5) / 2])],
        face=dict(part="PlotSign_Face_Cream", size=[fw, fh], center=[0, -0.4, round(zm - 0.05, 2)],
                  surface="Front (-Z in Roblox)"),
        figure=(-w / 2 - 1.8, -1.6),
        note="name board; text on PlotSign_Face_Cream through a SurfaceGui (Face Front), 5.6 x 2.5 studs",
    )
    return col


def wedge(col, name, colour, r0, r1, a0, a1, z0, z1, segments=6, radius=0.12):
    """A ring sector round the origin from radius r0 to r1 and angle a0 to a1 (radians, from +X towards +Y), z0 to z1:
    one curved path stone."""
    bm = bmesh.new()
    rings = []
    for i in range(segments + 1):
        a = a0 + (a1 - a0) * i / segments
        c, s = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((r * c, r * s, z)) for r, z in ((r0, z0), (r1, z0), (r1, z1), (r0, z1))])
    for i in range(segments):
        for k in range(4):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % 4], rings[i + 1][(k + 1) % 4], rings[i + 1][k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    ob = _object(col, name, bm, colour, smooth_angle=30)
    _bevel(ob, min(radius, (z1 - z0) / 2 - 1e-3, (r1 - r0) / 2 - 1e-3), 1, angle=30)
    return ob


def stone_ring(col, name, r0, r1, a0, a1, count, z0=0.1, z1=0.32, gap=0.14):
    """`count` stones side by side in a ring from r0 to r1 between angles a0 and a1, `gap` studs apart."""
    step = (a1 - a0) / count
    for k in range(count):
        g = gap / ((r0 + r1) / 2) / 2
        wedge(col, f"{name}{k}", "Stone", r0, r1, a0 + k * step + g, a0 + (k + 1) * step - g, z0, z1,
              segments=max(2, round(step * r1 / 1.2)))


def recentre(col):
    """Moves every object of the model so its bounding box is centred on the origin in x and y (pivot bottom centre),
    returns the shift."""
    lo, hi = bounds(col.all_objects)
    shift = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, 0))
    for ob in col.all_objects:
        ob.location += shift
    return shift


# --------------------------------------------------------------------------------------------------------------------
# Path stones (reference "Bonbon-Wege"): rounded pale rose stones on a Cream bed, 0.32 high, so they lie in the grass
# like a candy path. A path is 6 wide. PathStraight is 4 long and tiles end to end; PathCurve turns 90 degrees (inner
# radius 4, outer 10); PathRound is the round plaza (14 across) with the cone emblem lying in its middle. Walkable
# decoration: no collision, set 0.2 into the grass so the feet do not float.
PATH_W = 6.0
STONE_Z = (0.1, 0.32)


def build_path_straight():
    col = pk_collection("PathStraight")
    length = 4.0
    rounded_box(col, "Bed", "Cream", (PATH_W, length, 0.16), (0, 0, 0.08), radius=0.06, segments=1)
    z = (STONE_Z[0] + STONE_Z[1]) / 2
    h = STONE_Z[1] - STONE_Z[0]
    gap = 0.14
    row_d = (length - gap) / 2
    for row in range(2):
        y = -length / 2 + gap / 2 + row_d * (row + 0.5)
        cuts = [-PATH_W / 2, -PATH_W / 6, PATH_W / 6, PATH_W / 2] if row == 0 else [-PATH_W / 2, -PATH_W / 3, 0.0,
                                                                                     PATH_W / 3, PATH_W / 2]
        for k in range(len(cuts) - 1):
            a, b = cuts[k] + gap / 2, cuts[k + 1] - gap / 2
            rounded_box(col, f"Stone{row}_{k}", "Stone", (b - a, row_d - gap, h), ((a + b) / 2, y, z), radius=0.12,
                        segments=1)
    SPECS["PathStraight"] = dict(collision=[], figure=(-PATH_W / 2 - 1.6, 0.0),
                                 note="6 wide x 4 long, tiles end to end along Y; no collision, pivot 0.2 under grass")
    return col


def build_path_curve():
    col = pk_collection("PathCurve")
    r0, r1 = 4.0, 4.0 + PATH_W
    wedge(col, "Bed", "Cream", r0, r1, 0, math.pi / 2, 0.0, 0.16, segments=16, radius=0.06)
    mid = (r0 + r1) / 2
    stone_ring(col, "Inner", r0 + 0.07, mid - 0.07, 0, math.pi / 2, 4, *STONE_Z)
    stone_ring(col, "Outer", mid + 0.07, r1 - 0.07, 0, math.pi / 2, 6, *STONE_Z)
    shift = recentre(col)
    SPECS["PathCurve"] = dict(
        collision=[], figure=(-6.5, -2.0),
        arc_centre=[round(shift.x, 2), round(shift.y, 2)],
        note=f"quarter turn, inner radius {r0:g}, outer {r1:g}; arc centre at ({shift.x:.1f}, {shift.y:.1f}) from the "
        "pivot; its ends are 6 wide like PathStraight; no collision, pivot 0.2 under grass",
    )
    return col


def build_path_round():
    col = pk_collection("PathRound")
    R = 7.0
    cylinder(col, "Bed", "Cream", R, 0.16, 0.0, segments=32, bevel=0.06, bevel_segments=1)
    cylinder(col, "Middle", "Cream", 2.4, STONE_Z[1] - 0.02, 0.02, segments=24, bevel=0.12, bevel_segments=1)
    cone_emblem(col, "Emblem", (0, -0.15, STONE_Z[1] - 0.2), (0, 0, 1), up=(0, 1, 0), width=2.5, height=3.2)
    stone_ring(col, "Inner", 2.55, 4.6, 0, 2 * math.pi, 10, *STONE_Z)
    stone_ring(col, "Outer", 4.74, R - 0.08, 0, 2 * math.pi, 16, *STONE_Z)
    SPECS["PathRound"] = dict(collision=[], figure=(-R - 1.6, -1.0),
                              note="round plaza, 14 across, cone emblem in the middle (its point to -Y); no collision")
    return col


# --------------------------------------------------------------------------------------------------------------------
# Fence (reference "Stilisierter Holzzaun mit rosa Akzenten"). One post for both pieces (fence_post): a square post in
# warm wood (Waffle) on a Cream foot with a Pink ring, a Pink icing cap with drips and a Cream ball. FencePost is that
# post alone; FenceSection is the same post at its left end (x -FENCE_STEP/2) and two thick Cream rails with four
# pickets over to where the next post stands. Sections in a row give a post every FENCE_STEP studs; a FencePost closes
# the last end. A section's pivot is in the middle of its step (bottom), the post's in its middle.
FENCE_STEP = 8.0
FENCE = dict(post_w=1.1, post_h=3.7, rail_low=1.2, rail_high=3.0, rail=(0.6, 0.75), picket=(0.75, 0.35))


def fence_post(col, prefix, x=0.0):
    w, h = FENCE["post_w"], FENCE["post_h"]
    rounded_box(col, prefix + "_Foot", "Cream", (w + 0.55, w + 0.55, 0.7), (x, 0, 0.35), radius=0.22, segments=2)
    rounded_box(col, prefix + "_Ring", "Pink", (w + 0.28, w + 0.28, 0.4), (x, 0, 0.9), radius=0.14, segments=1)
    rounded_box(col, prefix + "_Post", "Waffle", (w, w, h - 1.0), (x, 0, 1.0 + (h - 1.0) / 2), radius=0.16,
                segments=2)
    slab, drips = round_glaze(col, prefix + "_Cap", w * 0.8, h + 0.35, thickness=0.6, drips=6, drop=(0.3, 0.6),
                              center=(x, 0), seed=21, columns=24, segments=16, bevel_segments=1)
    for ob in (slab, drips):
        ob.data.materials[0] = material("Pink")
    ball(col, prefix + "_Knob", "Cream", 0.48, (x, 0, h + 0.72), segments=12)


def _fence_post_collision(x=0.0):
    w, h = FENCE["post_w"] + 0.55, FENCE["post_h"] + 0.35
    return dict(kind="box", name="Post", size=[w, w, h], center=[x, 0, h / 2])


def build_fence_post():
    col = pk_collection("FencePost")
    fence_post(col, "Post")
    SPECS["FencePost"] = dict(collision=[_fence_post_collision()], figure=(-2.4, -1.4),
                              note="the same post as in FenceSection; closes the end of a row of sections")
    return col


def build_fence_section():
    col = pk_collection("FenceSection")
    x0 = -FENCE_STEP / 2
    fence_post(col, "Post", x0)
    rd, rh = FENCE["rail"]
    # the rails run from the post's face over to the next post's place, where its post (or a FencePost) covers the end
    start, end = x0 + FENCE["post_w"] / 2 - 0.1, FENCE_STEP / 2
    for z in (FENCE["rail_low"], FENCE["rail_high"]):
        rounded_box(col, "Rail", "Cream", (end - start, rd, rh), ((start + end) / 2, 0, z), radius=0.18, segments=2)
    pickets = 4
    gap_start, gap_end = x0 + FENCE["post_w"] / 2 + 0.3, FENCE_STEP / 2 - FENCE["post_w"] / 2 - 0.3
    pw, pd = FENCE["picket"]
    for k in range(pickets):
        x = gap_start + (gap_end - gap_start) * (k + 0.5) / pickets
        rounded_box(col, "Picket", "Cream", (pw, pd, FENCE["rail_high"] - FENCE["rail_low"]),
                    (x, 0, (FENCE["rail_low"] + FENCE["rail_high"]) / 2), radius=0.1, segments=1)
    top = FENCE["rail_high"] + rh / 2
    SPECS["FenceSection"] = dict(
        collision=[_fence_post_collision(x0),
                   dict(kind="box", name="Rails", size=[end - start, rd, top], center=[(start + end) / 2, 0, top / 2])],
        figure=(-1.0, -2.2),
        note=f"its post at x -{FENCE_STEP / 2:g}, rails over to +{FENCE_STEP / 2:g}: in a row one post every "
        f"{FENCE_STEP:g} studs, a FencePost at the end; the rails' collision reaches the ground",
    )
    return col


BUILDERS = {
    "SellCart": build_sell_cart,
    "WorkingStation": build_working_station,
    "ScoopChest": build_scoop_chest,
    "PlotSign": build_plot_sign,
    "PathStraight": build_path_straight,
    "PathCurve": build_path_curve,
    "PathRound": build_path_round,
    "FencePost": build_fence_post,
    "FenceSection": build_fence_section,
}


def finish(name):
    spec = SPECS.get(name, {})
    stats = model_stats(name)
    path, meshes, tris = export_model(name)
    clear_preview()
    fx, fy = spec.get("figure", (0, -6))
    figure(fx, fy, facing=1, scoops=20)
    if "npc" in spec:
        # an R15 stand-in for the NPC on its floor behind the counter (preview only), to see it shows above the counter
        nx, ny, nz = spec["npc"]["center"]
        figure(nx, ny, facing=-1, scoops=0, name="NPC")
        for ob in list(preview_collection().all_objects):
            if ob.name.startswith("NPC_"):
                if ob.name == "NPC_Backpack":
                    bpy.data.objects.remove(ob, do_unlink=True)
                else:
                    ob.location.z += nz
    lo, hi = stats["min"], stats["max"]
    ground(size=(hi[0] - lo[0] + 14, hi[1] - lo[1] + 14), center=((hi[0] + lo[0]) / 2, (hi[1] + lo[1]) / 2))
    body = [ob for ob in preview_collection().all_objects if "Scoop" not in ob.name and ob.name != "Ground"]
    picture = render_preview([name], name, extra=body)
    stats.update(fbx=path, meshes=meshes, exported_triangles=tris, preview=picture)
    stats.update({k: v for k, v in spec.items() if k != "figure"})
    write_report(name, stats)
    print(name, stats["size"], stats["triangles"], "triangles")


# --------------------------------------------------------------------------------------------------------------------
# The whole plot (reference "Eiscreme-Insel_ Spielerplot-Layout", fitted to our island): 110 x 60, walkable 104 x 54,
# in the plot's own frame (Config/Map.plot, PlotLayout): x = u along the ring (right as seen from the bridge), y = v
# along the lane, the bridge meets the front edge (y -30) in the middle. Entrance path to the round plaza in the middle,
# the Working Station at the back, the Scoop Chest on the right, the Sell Cart in the middle at the bridgehead
# looking at the bridge (Config/Map.plot: a player at its counter stands at the ServePoint (0, -24)), the sign right of
# the forecourt (u 19: at signAt u 13 it would stand on the forecourt), a fence round it all with the gap for the
# bridge. Instances of the model collections,
# preview only (nothing of it is exported).
PLOT = dict(width=110, depth=60, walk=(104, 54), fence=(48, 24), gap=8)


def place(col, name, at, turn=0.0):
    """An instance of PK_<name> at (x, y) on the plot, turned `turn` degrees about Z (0: its front to -Y)."""
    ob = bpy.data.objects.new(f"{name}@{at[0]:g},{at[1]:g}", None)
    ob.instance_type = "COLLECTION"
    ob.instance_collection = bpy.data.collections["PK_" + name]
    ob.location = (at[0], at[1], 0)
    ob.rotation_euler = (0, 0, math.radians(turn))
    col.objects.link(ob)
    return ob


def build_layout():
    col = pk_collection("Layout")
    for ob in list(col.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    clear_preview()
    # the island: rim and grass
    island = _flat_material("PK_Island", "#FFC8DD")
    _preview_box(preview_collection(), "Island", island, (PLOT["width"], PLOT["depth"], 3.0), (0, 0, -1.55))
    grass = ground(size=PLOT["walk"], center=(0, 0), colour="#A6D48A", name="Grass")
    grass.location.z = 0.0
    bridge = _flat_material("PK_Bridge", "#E8DDF5")
    _preview_box(preview_collection(), "Bridge", bridge, (18, 34, 1.0), (0, -PLOT["depth"] / 2 - 17, -0.5))
    # paths: a forecourt in front of the Sell Cart at the bridgehead, a path up either side of the cart, joined to the
    # plaza in the middle; from there on to the station at the back and the chest on the right, a turn on the left
    plaza = (0, -1)
    place(col, "PathRound", plaza)
    for x in range(-14, 15, 4):  # forecourt, x -16..16, y -27..-21: the player serves here
        place(col, "PathStraight", (x, -24), turn=90)
    for sx in (-1, 1):
        for y in (-19, -15, -11, -7):  # up beside the cart (x 10..16) to y -5
            place(col, "PathStraight", (sx * 13, y))
        for x in (9, 13):
            place(col, "PathStraight", (sx * x, plaza[1]), turn=90)  # into the plaza's side, x 7..15
    for x in (17, 21):
        place(col, "PathStraight", (x, plaza[1]), turn=90)  # on to the chest, to x 23
    place(col, "PathStraight", (0, 8))  # to the station, y 6..10
    # the turn continues the left branch (its end at x -15, y -4..2) and bends towards the back: turned 180 degrees
    # its stones lie below and left of the arc centre, so the pivot is that centre plus the arc_centre offset
    ax, ay = SPECS.get("PathCurve", {}).get("arc_centre", [-5.0, -5.0])
    centre = (-15.0, plaza[1] - PATH_W / 2 + 10.0)  # its end runs from centre - 10 to centre - 4 in y
    place(col, "PathCurve", (centre[0] + ax, centre[1] + ay), turn=180)
    # the models: the Sell Cart in the middle at the bridgehead, looking at the bridge (a player at its counter stands
    # at the ServePoint (0, -24)); the sign right of the forecourt, the chest on the right, the station at the back
    place(col, "SellCart", (0, -17))
    place(col, "WorkingStation", (0, 16.5))
    place(col, "ScoopChest", (28, plaza[1]), turn=-90)
    place(col, "PlotSign", (24, -26))
    # the fence, once round from the right side of the bridge gap to its left side: every section has its post at its
    # start (seen in the direction of the round), so each corner gets one post; a FencePost closes the gap's left side
    fx, fy, gap = PLOT["fence"][0], PLOT["fence"][1], PLOT["gap"]
    loop = [(gap, -fy), (fx, -fy), (fx, fy), (-fx, fy), (-fx, -fy), (-gap, -fy)]
    for (ax0, ay0), (bx0, by0) in zip(loop, loop[1:]):
        length = math.hypot(bx0 - ax0, by0 - ay0)
        dx, dy = (bx0 - ax0) / length, (by0 - ay0) / length
        turn = math.degrees(math.atan2(dy, dx))
        for k in range(round(length / FENCE_STEP)):
            s = FENCE_STEP * (k + 0.5)
            place(col, "FenceSection", (ax0 + dx * s, ay0 + dy * s), turn=turn)
    place(col, "FencePost", loop[-1])
    # a player at the Sell Cart's counter (at the ServePoint) with a starter tower
    figure(-3.0, -22.4, facing=1, scoops=20, name="Seller")
    frame = [ob for ob in preview_collection().all_objects if ob.name in ("Island", "Bridge")]
    render_preview(["Layout"], "PlotLayout", extra=frame, views=("three_quarter", "top"), size=(1280, 820))
    # what a player sees walking in over the bridge: eye height 4.6, 26 studs before the island
    render_eye(["Layout"], "PlotLayout_Bridge", eye=(0, -56, 4.6), target=(0, 0, 3.0), lens=26, size=(1600, 900))


# Scaled after the build (05.11.2026, so they do not look lost on the 110 x 60 plot): every part, and the collision,
# hinge, face and NPC room with it. The awnings grow too, a player at the counter keeps his tower clear of them (README).
SCALE = {"SellCart": 1.5, "WorkingStation": 1.5, "ScoopChest": 1.5, "PlotSign": 1.3}


def scale_model(name, s):
    col = bpy.data.collections["PK_" + name]
    for ob in col.all_objects:
        ob.location = ob.location * s
        ob.scale = ob.scale * s
    spec = SPECS.get(name, {})
    for box in spec.get("collision", []):
        box["size"] = [round(v * s, 3) for v in box["size"]]
        box["center"] = [round(v * s, 3) for v in box["center"]]
    for key in ("face", "npc"):
        if key in spec:
            spec[key]["size"] = [round(v * s, 3) for v in spec[key]["size"]]
            spec[key]["center"] = [round(v * s, 3) for v in spec[key]["center"]]
    if "hinge" in spec:
        spec["hinge"]["y"] = round(spec["hinge"]["y"] * s, 3)
        spec["hinge"]["z"] = round(spec["hinge"]["z"] * s, 3)
    if "figure" in spec:
        fx, fy = spec["figure"]
        spec["figure"] = (fx * s, fy * s + 0.6)
    spec["scale"] = s


for _name in PACK or ([] if LAYOUT else list(BUILDERS)):
    BUILDERS[_name]()
    if _name in SCALE:
        scale_model(_name, SCALE[_name])
    finish(_name)
if LAYOUT:
    build_layout()
