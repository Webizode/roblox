"""The arena pack: Waffle Crate, Ice Cream Pillar, the arena rim (wall and pillar, model 33) and the entrance arch
(model 34). References in the vault ("Wooble scoops Map assets"): "Neon-Waffelkisten im Arena-Showcase",
"Eissäulen-Hindernis_ Arena-Varianten und Details", "Wobble Scoops Arena-Barrieren Schauplan",
"Modell 34_ Arena-Eingänge geschniegelt".

Run inside Blender after arenakit.py, in the same session:
    ASSET_DIR = r"<repo>/assets/ArenaKit"
    exec(open(ASSET_DIR + "/arenakit.py").read())
    exec(open(ASSET_DIR + "/build_arena_pack.py").read())

Sizes in studs, origin at the bottom centre, front -Y (towards the arena centre for the rim and the entrance).
    WaffleCrate     two stacked crates, 8 x 5 below, 5.4 x 3.8 on top, 7.6 high: hides a standing player and his
                    tower's first scoops from every side. Cover: one Collision box from its bounding box.
    IcePillar       a waffle-cone pillar, 5.1 across its foot, about 10.5 high to the cherry: full cover and a
                    sight block. Cover like the crate.
    ArenaRim        one wall piece of the rim on the strip (top y 9), bent round the arena centre: its arc radius
                    RIM_R (the middle of the wall), RIM_SPAN degrees long, 3.4 high, 2.6 deep. Two of them fill the
                    gap between the rim pillars beside two ramps.
    ArenaRimPillar  the rim's pillar, stands beside each ramp (8 studs off the ramp's line, at RIM_R): 3.8 across,
                    about 7.5 high.
    ArenaEntrance   the arch over a ramp's top edge (r 159): two big cone pillars 17.2 apart (centres), a Pink arch
                    with Cream glaze and the cone shield on both sides, 13 clear between the pillars and about 11
                    clear under the arch.
"""

# the rim: wall middle on the strip at r 137.5 (the strip starts at r 135); a ramp and its rim pillars take
# 2 x 8 studs of the arc, the rest of the 30 degrees between two ramp lines is two wall pieces
RIM_R = 137.5
RIM_PILLAR_OFF = 8.0  # studs from the ramp's line along the arc to a rim pillar's centre
RIM_PILLAR_R = 1.9
RIM_SPAN = (30 - 2 * math.degrees((RIM_PILLAR_OFF + RIM_PILLAR_R * 0.6) / RIM_R)) / 2


def crate(col, prefix, L, D, H, z0, strap_colour, strap_x, emblem_x=None, seed=1):
    """One waffle crate from z0: Waffle lattice on all four sides, Cream frame, Pink corner caps with Gold rivets,
    a strap over it and a Cream lid with drips. Returns the top of its lid."""
    mid = z0 + 0.6 + (H - 1.1) / 2
    waffle_panel(col, prefix + "_WaffleFB", (L - 1.0, D - 0.5, H - 1.1), (0, 0, mid))
    side = waffle_panel(col, prefix + "_WaffleLR", (D - 1.0, L - 0.5, H - 1.1), (0, 0, mid))
    for ob in side:
        ob.rotation_euler = (0, 0, math.pi / 2)
    rounded_box(col, prefix + "_BandLow", "Cream", (L, D, 0.6), (0, 0, z0 + 0.3), radius=0.2, segments=1)
    rounded_box(col, prefix + "_BandTop", "Cream", (L, D, 0.5), (0, 0, z0 + H - 0.45), radius=0.18, segments=1)
    cx, cy = L / 2 - 0.38, D / 2 - 0.38
    for sx in (-1, 1):
        for sy in (-1, 1):
            rounded_box(col, f"{prefix}_Post", "Cream", (0.75, 0.75, H - 0.6), (sx * cx, sy * cy, z0 + H / 2),
                        radius=0.18, segments=1)
            for z in (z0 + 0.5, z0 + H - 0.25):
                rounded_box(col, f"{prefix}_Cap", "Pink", (1.05, 1.05, 1.0), (sx * (L / 2 - 0.4),
                            sy * (D / 2 - 0.4), z), radius=0.26, segments=1)
                bm = bmesh.new()
                for at in ((sx * (L / 2 - 0.4), sy * (D / 2 + 0.06), z), (sx * (L / 2 + 0.06), sy * (D / 2 - 0.4), z)):
                    made = bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=3, radius=0.17)
                    bmesh.ops.translate(bm, vec=Vector(at), verts=made["verts"])
                _object(col, f"{prefix}_Rivets", bm, "Gold", smooth_angle=80)
    lid_top = z0 + H + 0.35
    glaze(col, prefix + "_Lid", length=L - 0.1, depth=D - 0.1, top=lid_top, thickness=0.55,
          drips={
              "front": [(-L * 0.28, 1.4, 0.7), (L * 0.05, 1.2, 0.45), (L * 0.33, 1.3, 0.6)],
              "back": [(-L * 0.3, 1.3, 0.55), (L * 0.02, 1.4, 0.7), (L * 0.3, 1.2, 0.4)],
          }, drip_base=0.3, columns=18, seed=seed)
    # the strap over front, lid and back, with a Gold buckle on the front
    rounded_box(col, prefix + "_Strap", strap_colour, (0.85, D + 0.16, H + 0.5),
                (strap_x, 0, z0 + (H + 0.5) / 2 + 0.02), radius=0.12, segments=1)
    rounded_box(col, prefix + "_Buckle", "Gold", (1.3, 0.24, 1.05), (strap_x, -(D / 2 + 0.17), z0 + H * 0.5),
                radius=0.1, segments=1)
    rounded_box(col, prefix + "_BuckleIn", strap_colour, (0.7, 0.24, 0.55), (strap_x, -(D / 2 + 0.24),
                z0 + H * 0.5), radius=0.08, segments=1)
    if emblem_x is not None:
        cone_emblem(col, prefix + "_Emblem", (emblem_x, -(D / 2 - 0.02), z0 + H * 0.52), (0, -1, 0),
                    width=1.7, height=2.3)
    return lid_top


def build_waffle_crate():
    col = model_collection("WaffleCrate")
    top = crate(col, "Low", 8.0, 5.0, 4.0, 0.0, "SkyBlue", -1.3, emblem_x=2.0, seed=1)
    top2 = crate(col, "High", 5.4, 3.8, 2.9, top, "Pink", 0.9, seed=2)
    sprinkles(col, "Sprinkles", [(-3.3, -1.6, top), (3.2, 1.5, top), (3.4, -1.7, top), (-3.2, 1.7, top),
                                 (-1.6, -0.6, top2), (0.0, 0.8, top2), (1.9, -0.5, top2)], seed=5)
    print(f"WaffleCrate: {len(col.objects)} objects, {triangles(col)} triangles, top {top2:.2f}")
    return col


def build_ice_pillar():
    col = model_collection("IcePillar")
    tip = cone_pillar(col, "Pillar", radius=2.0, body_height=4.4)
    print(f"IcePillar: {len(col.objects)} objects, {triangles(col)} triangles, top {tip:.2f}")
    return col


def build_arena_rim():
    """One wall piece: Cream plinth, Pink wall, a Gold window on both faces, Cream glaze with drips on both faces,
    a few sprinkles. Bent round the arena centre (at (0, -RIM_R)), the inner face towards it (-Y)."""
    col = model_collection("ArenaRim")
    R, span = RIM_R, RIM_SPAN
    arc_box(col, "Plinth", "Cream", R, R - 1.5, R + 1.5, 0.0, 0.6, span, radius=0.2)
    arc_box(col, "Wall", "Pink", R, R - 1.2, R + 1.2, 0.55, 2.9, span, radius=0.15)
    for side, r0, r1 in (("In", R - 1.32, R - 1.15), ("Out", R + 1.15, R + 1.32)):
        arc_box(col, f"Window_{side}", "Gold", R, r0, r1, 1.15, 2.25, span * 0.42, segments=5, radius=0.06)
    arc_box(col, "Glaze", "Cream", R, R - 1.42, R + 1.42, 2.8, 3.4, span, radius=0.22)
    half = math.radians(span) / 2
    length = 2 * half * R
    for side, r, out_sign, seed in (("In", R - 1.38, -1, 3), ("Out", R + 1.38, 1, 4)):
        rng = random.Random(seed)
        drips = [(length * f + rng.uniform(-1, 1), rng.uniform(1.6, 2.4), rng.uniform(0.5, 1.1))
                 for f in (0.12, 0.33, 0.55, 0.78, 0.93)]
        hang = drip_profile(length, drips, base=0.3, seed=seed)
        tops, hangs, out = [], [], []
        columns = 40
        for i in range(columns + 1):
            phi = -half + 2 * half * i / columns
            tops.append(_arc_point(R, r, phi, 3.05))
            hangs.append(hang(length * i / columns))
            out.append((out_sign * math.sin(phi), out_sign * math.cos(phi), 0))
        drip_curtain(col, f"Drips_{side}", tops, hangs, out, thickness=0.26)
    spots = []
    rng = random.Random(7)
    for i in range(6):
        phi = -half + 2 * half * (i + 0.5) / 6 + rng.uniform(-0.01, 0.01)
        spots.append(_arc_point(R, R + rng.uniform(-0.6, 0.6), phi, 3.4))
    sprinkles(col, "Sprinkles", spots, seed=8)
    print(f"ArenaRim: {span:.2f} degrees ({length:.1f} studs at r {R}), {len(col.objects)} objects, "
          f"{triangles(col)} triangles")
    return col


def build_arena_rim_pillar():
    col = model_collection("ArenaRimPillar")
    tip = cone_pillar(col, "RimPillar", radius=RIM_PILLAR_R, body_height=2.9, base=0.6, cherry=False, seed=6)
    print(f"ArenaRimPillar: {len(col.objects)} objects, {triangles(col)} triangles, top {tip:.2f}")
    return col


ENTRANCE = dict(half_width=9.4, pillar_r=2.3, body=8.5, spring=9.0, rise=6.5, band=1.5, depth=2.2)


def _arch_ring(bm, a, b, spring, inner, outer, depth, t):
    """One ring of four vertices across the arch band at parameter t (0 right foot, pi left foot)."""
    p = Vector((a * math.cos(t), 0, spring + b * math.sin(t)))
    n = Vector((b * math.cos(t), 0, a * math.sin(t))).normalized()
    return [bm.verts.new(p + n * dr + Vector((0, dy, 0))) for dr, dy in
            ((inner, -depth / 2), (outer, -depth / 2), (outer, depth / 2), (inner, depth / 2))]


def arch_band(col, name, colour, a, b, spring, inner, outer, depth, t0=0.0, t1=math.pi, segments=20):
    bm = bmesh.new()
    rings = [_arch_ring(bm, a, b, spring, inner, outer, depth, t0 + (t1 - t0) * i / segments)
             for i in range(segments + 1)]
    for i in range(segments):
        for k in range(4):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % 4], rings[i + 1][(k + 1) % 4], rings[i + 1][k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    ob = _object(col, name, bm, colour, smooth_angle=30)
    _bevel(ob, 0.18, 2, angle=30)
    return ob


def build_arena_entrance():
    """The arch over a ramp's top edge. Pillars at x = +-half_width (their feet clear the 12 wide ramp), banners on
    both faces, the Pink arch springing from inside the pillar caps, Cream glaze with drips on its crown, the cone
    shield at the crown on the arena side (-Y) and the hub side (+Y)."""
    col = model_collection("ArenaEntrance")
    e = ENTRANCE
    for side, x in (("L", -e["half_width"]), ("R", e["half_width"])):
        tip = cone_pillar(col, f"Pillar_{side}", e["pillar_r"], e["body"], base=0.8, banners=(-1, 1), lean=True,
                          seed=9 if side == "L" else 10, center=(x, 0))
    a, b, s = e["half_width"], e["rise"], e["spring"]
    arch_band(col, "Arch", "Pink", a, b, s, -e["band"] / 2, e["band"] / 2, e["depth"])
    arch_band(col, "ArchGlaze", "Cream", a, b, s, e["band"] / 2 - 0.1, e["band"] / 2 + 0.3, e["depth"] + 0.3,
              t0=0.6, t1=math.pi - 0.6, segments=14)
    for face, y in (("F", -1), ("B", 1)):
        tops, hangs, out = [], [], []
        rng = random.Random(11 if face == "F" else 12)
        columns = 24
        t0, t1 = 0.66, math.pi - 0.66
        drips = {round(columns * f): rng.uniform(0.5, 1.2) for f in (0.12, 0.3, 0.5, 0.7, 0.88)}
        for i in range(columns + 1):
            t = t0 + (t1 - t0) * i / columns
            p = Vector((a * math.cos(t), 0, s + b * math.sin(t)))
            n = Vector((b * math.cos(t), 0, a * math.sin(t))).normalized()
            top = p + n * (e["band"] / 2 + 0.05)
            tops.append((top.x, y * (e["depth"] / 2 + 0.12), top.z))
            bump = max((v * max(0.0, 1 - abs(i - k) / 2.2) ** 0.7 for k, v in drips.items()), default=0)
            hangs.append(0.45 + bump)
            out.append((0, y, 0))
        drip_curtain(col, f"ArchDrips_{face}", tops, hangs, out, thickness=0.22)
        crown = s + b + e["band"] / 2 + 0.2
        cone_emblem(col, f"Shield_{face}", (0, y * (e["depth"] / 2 + 0.22), crown), (0, y, 0), width=2.8,
                    height=3.4)
    print(f"ArenaEntrance: {len(col.objects)} objects, {triangles(col)} triangles, pillar tops {tip:.2f}, "
          f"clear width {2 * (e['half_width'] - e['pillar_r'] * 1.28):.1f}, "
          f"clear under the crown {s + b - e['band'] / 2:.1f}")
    return col


BUILDERS = {
    "WaffleCrate": build_waffle_crate,
    "IcePillar": build_ice_pillar,
    "ArenaRim": build_arena_rim,
    "ArenaRimPillar": build_arena_rim_pillar,
    "ArenaEntrance": build_arena_entrance,
}
for _name in globals().get("PACK") or list(BUILDERS):
    BUILDERS[_name]()
