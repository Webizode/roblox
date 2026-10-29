"""Builds the tower scoops (the ones stacked on the back, not the attack scoops) in Blender from scratch.

Run inside Blender (Blender MCP or the Text Editor):
    ASSET_DIR = r"<repo>/assets/TowerScoops"
    exec(open(ASSET_DIR + "/build_scoops.py").read())

1 Blender unit = 1 stud, Z is up, front is -Y; the FBX export turns it into Roblox's Y up. The origin is the scoop's
centre, the point the game places (TowerShape.offset), so a stack is simply one scoop every SPACING studs.

Every flavor shares one base shape (base_profile): a dome, a thick rim with round lobes (the drip crown from
docs/art-bible.md, concept A) and a hollow underside that sits over the dome of the scoop below. A flavor only
changes the parameters in FLAVORS (lobe count and lengths, dome size, colour, gloss) and adds its own details
(details_<id>, e.g. the vanilla specks), so the other nine flavors and Golden build on the same mesh rules.

Two meshes per flavor: LOD0 (about 450 triangles, close up) and LOD1 (about 100, from about 40 studs on; the client
swaps them).
"""

import math
import os

import bmesh
import bpy
import numpy as np

ASSET_DIR = globals().get("ASSET_DIR") or os.path.dirname(bpy.data.filepath)

# The real sizes from the code: Config/Launcher catchRadius (scoop radius 1, stack radius 1.05), Config/Tower
# scoopSpacing 1.5, TowerVisual SCOOP_SIZE 2.1 (the drawn width).
RADIUS = 1.0
WIDTH = 2.1  # across the rim, lobes included
SPACING = 1.5

OUTLINE = "#5A2E1A"  # the Big Swirl's outline (its Highlight in the place)

BASE = {
    "dome": 1.0,  # height of the dome top above the centre (the dome is a sphere of dome_radius under it)
    "dome_radius": 0.92,
    # 7 lobes, one centred at the front, left-right symmetric; drip length per lobe below the rim, from the front
    # around to the left: front long, front-side short, side long, back medium (art bible)
    "lobes": [0.26, 0.15, 0.23, 0.19, 0.19, 0.23, 0.15],
    "roughness": 0.35,  # the preview's gloss; with surface_roughness the game gets it too (a RoughnessMap)
    "uv_top": 1.0,  # the share of the picture's height the scoop uses; an extra part takes the rest
    "extra": None,  # a small extra part on top (extra_<name> below), in the same mesh
}

# Every flavor is the base shape plus its own colour (Config/Flavors) and its details (details_<id>). The colours
# must match Config/Flavors, the part's colour in the game; the details picture lies over it.
FLAVORS = {
    "vanilla": {**BASE, "color": "#F9DCA8"},  # warmer than Palette.vanilla, which reads almost white in the game
    "lemon": {**BASE, "color": "#FFD84A", "extra": "lemon_slice", "uv_top": 0.8},
    "pistachio": {**BASE, "color": "#B9D98C", "roughness": 0.75, "surface_roughness": 0.75},
    "watermelon": {**BASE, "color": "#F2545B"},
    "chocolate": {**BASE, "color": "#6A3F2A", "roughness": 0.15, "surface_roughness": 0.15},
    "strawberry": {**BASE, "color": "#FF8FA3"},
    "mint": {**BASE, "color": "#9DE0C4"},
    "bubblegum": {**BASE, "color": "#FF8AD8"},
    "cookie": {**BASE, "color": "#C9976A"},
    "mango": {**BASE, "color": "#FFA53D"},
    "stracciatella": {**BASE, "color": "#FFF6E8"},
}

LODS = {
    # segments per lobe around the rim; polar angles of the dome rings in degrees; how many of the rim's points the
    # dome rings get (the dome has no lobes: half as many points round it buys more rings, so a round top);
    # a crease between the dome and the roll
    "LOD0": {"segments": 4, "dome_rings": [20, 40, 60, 80], "dome_share": 1, "crease": True},
    "LOD1": {"segments": 2, "dome_rings": [60], "dome_share": 1, "crease": False},
}


def srgb(hexstr):
    h = hexstr.lstrip("#")
    c = [int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def lobe_shape(theta, count):
    """1 at a lobe's middle, 0 in the notch between two lobes; lobe 1 sits at the front (-Y). Round lobes with narrow
    notches between them, like the drips in the reference."""
    phase = (theta / (2 * math.pi)) * count
    frac = phase - math.floor(phase + 0.5)  # -0.5..0.5 around the nearest lobe middle
    return math.cos(frac * math.pi) ** 0.35, int(math.floor(phase + 0.5)) % count


def base_profile(flavor, lod):
    """Rings of (radius, z) per angle, each a function of the lobe shape L (0 notch, 1 lobe middle) and the lobe's
    drip length d: the dome, the thick rim with its lobes, then the hollow underside. Returns the rings, the top pole
    and the apex of the hollow.

    The hollow clears the dome of the scoop below (its top is SPACING lower: dome - SPACING = -0.5 here, the apex
    sits just above), so a stack nests: the lobes hang over the lower scoop's dome, nothing cuts into it."""
    dome, dr = flavor["dome"], flavor["dome_radius"]
    half = WIDTH / 2
    rings = []  # (profile, on the dome: fewer points round it)
    for deg in lod["dome_rings"]:
        phi = math.radians(deg)
        rings.append((lambda L, d, phi=phi: (dr * math.sin(phi), dome - dr + dr * math.cos(phi)), True))
    if lod["crease"]:
        crease = math.radians(100)
        rings.append((lambda L, d: (dr * math.sin(crease) - 0.04, dome - dr + dr * math.cos(crease)), False))  # tucks in
    rings.append((lambda L, d: (half - 0.10 + 0.10 * L, -0.36 - 0.35 * d * L), False))  # the roll, tucked in at a notch
    # the round end of the drip, tucked back in; the notches between the lobes stay shallow, so round lobes, no teeth
    rings.append((lambda L, d: (0.74 + 0.12 * L, -0.60 - d * (0.4 + 0.6 * L)), False))
    rings.append((lambda L, d: (0.60, -0.62 - 0.1 * d * L), False))  # the hollow
    return rings, (0.0, dome), (0.0, dome - SPACING + 0.05)


def band(bm, upper, lower):
    """Faces between two rings; a ring may have half the points of the next one (the dome above the rim)."""
    n, m = len(upper), len(lower)
    if n == m:
        for s in range(n):
            t = (s + 1) % n
            bm.faces.new((upper[s], upper[t], lower[t], lower[s]))
        return
    assert m == 2 * n
    for s in range(n):
        t = (s + 1) % n
        a, b, c = lower[2 * s], lower[2 * s + 1], lower[(2 * s + 2) % m]
        bm.faces.new((upper[s], a, b))
        bm.faces.new((upper[s], b, upper[t]))
        bm.faces.new((upper[t], b, c))


def build_mesh(name, flavor, lod):
    count = len(flavor["lobes"])
    segments = count * lod["segments"]
    rings, top, apex = base_profile(flavor, lod)
    bm = bmesh.new()
    grid = []
    for ring, on_dome in rings:
        points = segments // lod["dome_share"] if on_dome else segments
        row = []
        for s in range(points):
            theta = 2 * math.pi * s / points
            L, lobe = lobe_shape(theta, count)
            r, z = ring(L, flavor["lobes"][lobe])
            # theta 0 at the front (-Y), going round to +X
            row.append(bm.verts.new((r * math.sin(theta), -r * math.cos(theta), z)))
        grid.append(row)
    pole = bm.verts.new((top[0], 0, top[1]))
    under = bm.verts.new((apex[0], 0, apex[1]))
    for ring_points, tip in ((grid[0], pole), (grid[-1], under)):
        for s in range(len(ring_points)):
            bm.faces.new((tip, ring_points[s], ring_points[(s + 1) % len(ring_points)]))
    for i in range(len(grid) - 1):
        band(bm, grid[i], grid[i + 1])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    # spherical UVs for the flavor's detail picture (specks, chips, ...): U around, V from the bottom up, scaled into
    # the scoop's share of the picture (uv_top)
    # (the picture repeats, so a face across the seam at the back gets U past 1 instead of running back over it;
    # a point on the axis takes the U of its face)
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        poly.use_smooth = True
        coords = []
        for li in poly.loop_indices:
            x, y, z = mesh.vertices[mesh.loops[li].vertex_index].co
            u = (math.atan2(x, -y) / (2 * math.pi)) % 1.0 if x * x + y * y > 1e-8 else None
            v = 0.5 + 0.5 * max(-1.0, min(1.0, z / flavor["dome"]))
            coords.append((li, u, v * flavor["uv_top"]))
        us = [u for _, u, _ in coords if u is not None]
        wrap = max(us) - min(us) > 0.5
        us = [u + 1 if wrap and u < 0.5 else u for u in us]
        mid = sum(us) / len(us)
        for li, u, v in coords:
            u = mid if u is None else (u + 1 if wrap and u < 0.5 else u)
            uv.data[li].uv = (u, v)
    if flavor["extra"]:
        mesh = with_extra(mesh, globals()["extra_" + flavor["extra"]](name + "_extra", flavor, lod))
    return mesh


def with_extra(mesh, extra):
    """The scoop mesh with an extra part's mesh added to it (both with their own UVs): one MeshPart in the game."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.from_mesh(extra)
    name = mesh.name
    bpy.data.meshes.remove(mesh)
    bpy.data.meshes.remove(extra)
    out = bpy.data.meshes.new(name)
    bm.to_mesh(out)
    bm.free()
    return out


# where an extra part's own picture sits in the details picture: a square above the scoop's share (uv_top), at the
# left edge (u from 0 to EXTRA_U, v from uv_top to 1)
EXTRA_U = 0.1


def extra_lemon_slice(name, flavor, lod):
    """A thin lemon slice lying a little tilted on the dome, sunk into it a bit. Its top shows the slice picture
    (details_lemon draws it), its rind edge the rind."""
    segments = 12 if lod["crease"] else 7
    radius, thick = 0.4, 0.08
    tilt = math.radians(14)
    centre = (0.12, 0.05, flavor["dome"] - 0.04)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    v0, v1 = flavor["uv_top"], 1.0
    cu, cv = EXTRA_U / 2, (v0 + v1) / 2
    half_u, half_v = EXTRA_U / 2 * 0.92, (v1 - v0) / 2 * 0.92

    def place(x, y, z):
        # tilt about X, then move onto the dome
        y2 = y * math.cos(tilt) - z * math.sin(tilt)
        z2 = y * math.sin(tilt) + z * math.cos(tilt)
        return bm.verts.new((centre[0] + x, centre[1] + y2, centre[2] + z2))

    top, bottom, ring_top, ring_bottom = [], [], [], []
    for s in range(segments):
        a = 2 * math.pi * s / segments
        x, y = radius * math.cos(a), radius * math.sin(a)
        ring_top.append((place(x, y, thick / 2), math.cos(a), math.sin(a)))
        ring_bottom.append((place(x, y, -thick / 2), math.cos(a), math.sin(a)))
    centre_top = place(0, 0, thick / 2)
    centre_bottom = place(0, 0, -thick / 2)

    def set_uv(face, points):
        for loop, (px, py) in zip(face.loops, points):
            loop[uv_layer].uv = (cu + px * half_u, cv + py * half_v)

    for s in range(segments):
        n = (s + 1) % segments
        (a, ax, ay), (b, bx, by) = ring_top[s], ring_top[n]
        set_uv(bm.faces.new((centre_top, a, b)), [(0, 0), (ax, ay), (bx, by)])
        (c, cx_, cy_), (d, dx, dy) = ring_bottom[s], ring_bottom[n]
        set_uv(bm.faces.new((centre_bottom, d, c)), [(0, 0), (dx, dy), (cx_, cy_)])
        # the rind edge: the outer ring of the slice picture
        set_uv(bm.faces.new((a, c, d, b)), [(ax, ay), (ax * 0.98, ay * 0.98), (dx * 0.98, dy * 0.98), (bx, by)])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for face in bm.faces:
        face.smooth = False  # a slice has flat faces
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def details_vanilla(width=512, height=256, seed=7):
    """Fine vanilla-bean specks on a transparent picture: the scoop's own colour shows through (in Roblox a
    SurfaceAppearance in Overlay mode over the MeshPart's colour). U runs around the scoop (about twice as far as V
    from bottom to top), hence the 2:1 picture; no specks near the top pole, where the mapping squeezes."""
    rng = np.random.default_rng(seed)
    img = np.zeros((height, width, 4), dtype=np.float32)
    speck = np.array(srgb("#8A5632"))
    yy, xx = np.mgrid[0:height, 0:width]
    for _ in range(40):
        cx, cy = rng.uniform(0, width), rng.uniform(height * 0.15, height * 0.85)
        rad = rng.uniform(1.0, 1.7)
        dx = np.minimum(np.abs(xx - cx), width - np.abs(xx - cx)) / 1.4  # a little longer around than up
        d = np.sqrt(dx**2 + (yy - cy) ** 2)
        a = np.clip(1.5 - d / rad, 0, 1) * rng.uniform(0.35, 0.6)
        img[..., :3] = img[..., :3] * (1 - a[..., None]) + speck * a[..., None]
        img[..., 3] = np.maximum(img[..., 3], a)
    return img


# Painting the details pictures. A picture is W x H pixels (2:1, U around the scoop is about twice as far as V from
# bottom to top), transparent where the scoop's own colour shows. Positions are in "scoop V" (0 the bottom of the
# drips, 1 the top of the dome); paint() puts them into the scoop's share of the picture (uv_top).
W, H = 512, 256
ASPECT = 1.3  # a pixel across is this much shorter on the scoop than a pixel up, so round things are drawn wider


def canvas():
    return np.zeros((H, W, 4), dtype=np.float32)


def blend(img, rows, cols, alpha, color):
    a = alpha[..., None]
    img[rows, cols, :3] = img[rows, cols, :3] * (1 - a) + np.array(srgb(color)) * a
    img[rows, cols, 3] = np.maximum(img[rows, cols, 3], alpha)


def blob(img, flavor, u, v, size, color, alpha=1.0, stretch=1.0, wobble=0.0, square=False, turn=0.0, seed=0):
    """One small thing on the scoop at (u, scoop v): `size` pixels high, `stretch` times as long up as across;
    `wobble` makes the outline irregular (nut bits, crumbs), `square` makes it a little cube seen from the side;
    soft at the edge. Wraps around the seam."""
    cx, cy = u * W, v * flavor["uv_top"] * H
    reach = int(size * max(stretch, 1) * ASPECT * 1.6) + 2
    rows = np.arange(int(cy) - reach, int(cy) + reach + 1)
    rows = rows[(rows >= 0) & (rows < int(flavor["uv_top"] * H))]
    cols = np.arange(int(cx) - reach, int(cx) + reach + 1)
    if len(rows) == 0:
        return
    yy, xx = np.meshgrid(rows, cols, indexing="ij")
    dx = (xx - cx) / ASPECT
    dy = (yy - cy) / stretch
    c, s = math.cos(turn), math.sin(turn)
    dx, dy = dx * c - dy * s, dx * s + dy * c
    if square:
        d = np.maximum(np.abs(dx), np.abs(dy)) / size
    else:
        d = np.sqrt(dx**2 + dy**2) / size
        if wobble:
            angle = np.arctan2(dy, dx)
            d = d / (1 + wobble * (np.sin(3 * angle + seed) * 0.6 + np.sin(5 * angle + 2 * seed) * 0.4))
    a = np.clip((1 - d) * size, 0, 1) * alpha  # about a pixel of soft edge
    blend(img, yy, xx % W, a, color)


def scatter(img, flavor, rng, count, vmin, vmax, draw):
    """`count` things spread evenly-ish over the scoop between scoop V vmin and vmax (jittered grid, so they do not
    clump), each drawn by draw(u, v, i)."""
    cols = max(1, int(round(math.sqrt(count * 2))))
    rows = max(1, int(math.ceil(count / cols)))
    i = 0
    for r in range(rows):
        for c in range(cols):
            if i >= count:
                return
            u = (c + rng.uniform(0.15, 0.85) + (0.5 if r % 2 else 0)) / cols
            v = vmin + (r + rng.uniform(0.15, 0.85)) / rows * (vmax - vmin)
            draw(u % 1.0, v, i)
            i += 1


# where the rim and its drips start, in scoop V: everything below is the rim, the drips and the hollow underside
RIM_V = 0.35


def rim_band(img, flavor, v_top, color, alpha=1.0, soft=2.0, wave=0.0):
    """Colours the scoop below scoop V v_top (the rim and drips: RIM_V), soft at the edge; `wave` (pixels) makes the
    edge go up and down with the 7 lobes."""
    top = v_top * flavor["uv_top"] * H
    rows = np.arange(0, int(flavor["uv_top"] * H))
    yy, xx = np.meshgrid(rows, np.arange(W), indexing="ij")
    edge = top - wave * np.cos(xx / W * 2 * math.pi * len(flavor["lobes"]))
    a = np.clip((edge - yy) / soft + 0.5, 0, 1) * alpha
    blend(img, yy, xx, a, color)


def details_lemon(seed=3):
    """Tiny zest dots, and the lemon slice's own picture (rind, pith, eight segments) for the slice on top."""
    flavor = FLAVORS["lemon"]
    rng = np.random.default_rng(seed)
    img = canvas()
    # short curls of zest on the sides, so a lemon reads as lemon in a tower too, where the slice is covered
    scatter(
        img,
        flavor,
        rng,
        34,
        RIM_V + 0.05,
        0.86,
        lambda u, v, i: blob(img, flavor, u, v, 1.3, "#E8A817", 0.85, stretch=3.2, turn=rng.uniform(0.9, 2.2)),
    )
    # the slice, in its square above the scoop's share
    x0, x1 = 0, int(EXTRA_U * W)
    y0, y1 = int(flavor["uv_top"] * H), H
    yy, xx = np.meshgrid(np.arange(y0, y1), np.arange(x0, x1), indexing="ij")
    px = (xx + 0.5 - (x0 + x1) / 2) / ((x1 - x0) / 2 * 0.92)
    py = (yy + 0.5 - (y0 + y1) / 2) / ((y1 - y0) / 2 * 0.92)
    r = np.sqrt(px**2 + py**2)
    angle = np.arctan2(py, px)
    rgb = np.zeros(r.shape + (3,), dtype=np.float32)
    flesh = np.array(srgb("#FFEB7A"))
    white = np.array(srgb("#FFF8DC"))
    rind = np.array(srgb("#F7D02C"))
    separator = (np.abs(np.sin(angle * 4)) < 0.12) & (r > 0.12)
    rgb[:] = flesh
    rgb[separator | (r < 0.12) | ((r > 0.78) & (r <= 0.88))] = white
    rgb[r > 0.88] = rind
    img[y0:y1, x0:x1, :3] = rgb
    img[y0:y1, x0:x1, 3] = 1
    return img


def details_pistachio(seed=11):
    """Green nut bits in two greens, a few with their brown skin; the scoop itself is a little rough
    (surface_roughness)."""
    flavor = FLAVORS["pistachio"]
    rng = np.random.default_rng(seed)
    img = canvas()
    colors = ["#5F8530", "#6E9638", "#E4F2C2", "#9A6B44"]  # dark and mid green, pale kernel, brown skin

    def nut(u, v, i):
        blob(img, flavor, u, v, rng.uniform(3.6, 5.4), colors[i % 4], 0.95, rng.uniform(0.8, 1.3), 0.35, seed=i)

    scatter(img, flavor, rng, 40, 0.12, 0.88, nut)
    return img


def details_watermelon(seed=5):
    """Black teardrop seeds on the red, and a green rind on the rim and drips with a pale line above it."""
    flavor = FLAVORS["watermelon"]
    rng = np.random.default_rng(seed)
    img = canvas()
    rim_band(img, flavor, RIM_V + 0.035, "#F4F9DE", 0.95, wave=1.5)  # the pale layer between red and green
    rim_band(img, flavor, RIM_V, "#4FAE45", 1.0, wave=1.5)

    def seed_at(u, v, i):
        blob(img, flavor, u, v, 1.7, "#2B2D42", 0.95, stretch=1.6, turn=rng.uniform(-0.4, 0.4))

    scatter(img, flavor, rng, 28, RIM_V + 0.1, 0.86, seed_at)
    return img


def details_chocolate(seed=17):
    """A darker rim and drips, like melted chocolate; extra glossy (surface_roughness)."""
    flavor = FLAVORS["chocolate"]
    img = canvas()
    rim_band(img, flavor, RIM_V + 0.02, "#4A2817", 0.9, soft=3.0, wave=2.5)
    return img


def details_strawberry(seed=19):
    """Red strawberry pieces, some darker, irregular."""
    flavor = FLAVORS["strawberry"]
    rng = np.random.default_rng(seed)
    img = canvas()
    colors = ["#D9344A", "#D9344A", "#B0213A"]

    def piece(u, v, i):
        blob(img, flavor, u, v, rng.uniform(5.0, 7.5), colors[i % 3], 0.95, rng.uniform(0.8, 1.2), 0.3, seed=i)

    scatter(img, flavor, rng, 26, 0.12, 0.88, piece)
    return img


def details_mint(seed=23):
    """Dark chocolate chips: small sharp shards at all angles."""
    flavor = FLAVORS["mint"]
    rng = np.random.default_rng(seed)
    img = canvas()

    def chip(u, v, i):
        blob(img, flavor, u, v, rng.uniform(1.6, 2.6), "#3B2416", 0.95, rng.uniform(0.6, 1.5), square=True,
             turn=rng.uniform(0, math.pi))

    scatter(img, flavor, rng, 48, 0.12, 0.88, chip)
    return img


def details_bubblegum(seed=29):
    """Colourful round gum balls, each with a small shine."""
    flavor = FLAVORS["bubblegum"]
    rng = np.random.default_rng(seed)
    img = canvas()
    colors = ["#4FB6F0", "#FFE34D", "#8FD14F", "#8A6CFF", "#FFFFFF"]

    def ball(u, v, i):
        size = rng.uniform(7.0, 9.0)
        blob(img, flavor, u, v, size, colors[i % len(colors)], 1.0)
        blob(img, flavor, u - size * 0.3 / W, v + size * 0.35 / H / flavor["uv_top"], size * 0.32, "#FFFFFF", 0.9)

    scatter(img, flavor, rng, 18, 0.12, 0.88, ball)
    return img


def details_cookie(seed=31):
    """Angular dark cookie pieces and a few crumbs; set apart from cookie dough (pale dough, round lumps and chips)
    by the darker base and the hard edges."""
    flavor = FLAVORS["cookie"]
    rng = np.random.default_rng(seed)
    img = canvas()

    def piece(u, v, i):
        if i % 3 == 2:
            blob(img, flavor, u, v, rng.uniform(1.0, 1.5), "#7A5236", 0.9)  # crumb
        else:
            blob(img, flavor, u, v, rng.uniform(4.0, 6.0), "#4E321F", 0.95, rng.uniform(0.7, 1.2), square=True,
                 turn=rng.uniform(0, math.pi))

    scatter(img, flavor, rng, 45, 0.12, 0.88, piece)
    return img


def details_mango(seed=37):
    """Small mango cubes, a deeper orange with a light top edge, so mango differs from lemon also without colour
    (cubes against curls and the slice)."""
    flavor = FLAVORS["mango"]
    rng = np.random.default_rng(seed)
    img = canvas()

    def cube(u, v, i):
        size = rng.uniform(5.5, 6.8)
        turn = rng.uniform(-0.3, 0.3)
        blob(img, flavor, u, v, size, "#D9650A", 1.0, square=True, turn=turn)
        blob(img, flavor, u, v + size * 0.55 / H / flavor["uv_top"], size * 0.55, "#FFE6A8", 0.95, 0.45, square=True,
             turn=turn)

    scatter(img, flavor, rng, 20, 0.12, 0.88, cube)
    return img


def details_stracciatella(seed=41):
    """Fine chocolate streaks running round the scoop, thin and long (vanilla has dots, this has lines)."""
    flavor = FLAVORS["stracciatella"]
    rng = np.random.default_rng(seed)
    img = canvas()

    def streak(u, v, i):
        blob(img, flavor, u, v, rng.uniform(3.5, 6.0), "#3B2416", 0.9, stretch=0.22, turn=rng.uniform(-0.35, 0.35))

    scatter(img, flavor, rng, 60, 0.1, 0.9, streak)
    return img


def roughness_image(flavor_id, flavor):
    """A plain picture of the flavor's surface_roughness (white = rough), for the SurfaceAppearance's RoughnessMap."""
    value = flavor.get("surface_roughness")
    if value is None:
        return None
    name = f"TS_{flavor_id}_roughness"
    img = bpy.data.images.get(name) or bpy.data.images.new(name, 8, 8, alpha=False)
    img.pixels.foreach_set(np.tile(np.array([value, value, value, 1.0], dtype=np.float32), 64))
    img.filepath_raw = os.path.join(ASSET_DIR, "textures", f"{flavor_id}_roughness.png")
    img.file_format = "PNG"
    img.save()
    return img


def detail_image(flavor_id):
    maker = globals().get("details_" + flavor_id)
    if not maker:
        return None
    pixels = maker()
    name = f"TS_{flavor_id}_details"
    img = bpy.data.images.get(name)
    if img and (img.size[0], img.size[1]) != (pixels.shape[1], pixels.shape[0]):
        bpy.data.images.remove(img)
        img = None
    img = img or bpy.data.images.new(name, pixels.shape[1], pixels.shape[0], alpha=True)
    img.pixels.foreach_set(pixels.ravel())
    os.makedirs(os.path.join(ASSET_DIR, "textures"), exist_ok=True)
    img.filepath_raw = os.path.join(ASSET_DIR, "textures", f"{flavor_id}_details.png")
    img.file_format = "PNG"
    img.save()
    return img


def flavor_material(flavor_id, flavor):
    name = f"TS_{flavor_id}"
    old = bpy.data.materials.get(name)
    if old:
        bpy.data.materials.remove(old)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    b = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    base = srgb(flavor["color"]) + [1.0]
    b.inputs["Roughness"].default_value = flavor["roughness"]
    b.inputs["Specular IOR Level"].default_value = 0.35  # a candy gloss without mirroring the whole sky
    roughness_image(flavor_id, flavor)
    img = detail_image(flavor_id)
    if img:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = img
        mix = nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        # the Mix node has a socket of each type under the same name; pick the colour ones by identifier
        socket = {s.identifier: s for s in mix.inputs}
        result = next(s for s in mix.outputs if s.identifier == "Result_Color")
        socket["A_Color"].default_value = base
        links.new(tex.outputs["Alpha"], socket["Factor_Float"])
        links.new(tex.outputs["Color"], socket["B_Color"])
        links.new(result, b.inputs["Base Color"])
    else:
        b.inputs["Base Color"].default_value = base
    return m


def outline_material():
    """Preview only: an inverted hull in the Big Swirl's outline colour. In the game the outline is a Highlight."""
    m = bpy.data.materials.get("TS_Outline") or bpy.data.materials.new("TS_Outline")
    m.use_nodes = True
    nodes = m.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = srgb(OUTLINE) + [1.0]
    # the hull wraps the whole scoop: it must not shade it, so shadow rays pass through
    clear = nodes.new("ShaderNodeBsdfTransparent")
    path = nodes.new("ShaderNodeLightPath")
    mix = nodes.new("ShaderNodeMixShader")
    links = m.node_tree.links
    links.new(path.outputs["Is Shadow Ray"], mix.inputs["Fac"])
    links.new(em.outputs["Emission"], mix.inputs[1])
    links.new(clear.outputs["BSDF"], mix.inputs[2])
    links.new(mix.outputs["Shader"], out.inputs["Surface"])
    m.use_backface_culling = True
    m.use_backface_culling_shadow = True
    return m


def collection(name):
    col = bpy.data.collections.get(name)
    if col:
        for ob in list(col.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
    else:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col


def build(flavor_id):
    flavor = FLAVORS[flavor_id]
    col = collection(f"TowerScoop_{flavor_id}")
    mat = flavor_material(flavor_id, flavor)
    made = {}
    for lod_name, lod in LODS.items():
        name = f"TS_{flavor_id.capitalize()}_{lod_name}"
        old = bpy.data.meshes.get(name)
        if old:
            bpy.data.meshes.remove(old)
        ob = bpy.data.objects.new(name, build_mesh(name, flavor, lod))
        ob.data.materials.append(mat)
        col.objects.link(ob)
        made[lod_name] = ob
        print(name, len(ob.data.polygons), "triangles")
    return made


def add_outline(ob, thickness=0.035):
    """Preview only (not exported)."""
    ob.data.materials.append(outline_material())
    mod = ob.modifiers.new("PreviewOutline", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 1
    mod.use_flip_normals = True
    mod.use_rim = False
    mod.material_offset = len(ob.data.materials) - 1


BUILT = {fid: build(fid) for fid in FLAVORS}
