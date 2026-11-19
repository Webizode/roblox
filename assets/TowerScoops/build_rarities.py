"""The uncommon, rare, epic and legendary tower scoops (18.11.2026): 41 flavors on the common scoops' base shape.

Run inside Blender (Blender MCP or the Text Editor):
    ASSET_DIR = r"<repo>/assets/TowerScoops"
    exec(open(ASSET_DIR + "/build_rarities.py").read())

Every flavor here has exactly the base shape (the same mesh as vanilla), so nothing is exported or imported: the
game takes the meshes from the vanilla template (studio_setup.luau with SHAPE = "vanilla") and lays the flavor's own
detail picture over its own colour. What a flavor is made of comes from the user's reference designs (vault:
Sorten-Katalog.md); toppings that make the flavor (a cherry, a lime slice, a flower) are painted into the picture
instead of modelled, so no flavor needs an import. This reuses the painting helpers of build_scoops.py (it is read
without building the commons again) and adds ribbons (the swirls), a glaze with drips from the top, sprinkles and a
few small painted toppings.

Writes textures/<flavor>_details.png (and <flavor>_roughness.png for a flavor with surface_roughness) and builds the
meshes in Blender for the previews (preview_scoops.py, PREVIEW_FLAVOR = "<flavor>").
"""

import math
import os

import numpy as np

ASSET_DIR = globals().get("ASSET_DIR")
_source = open(os.path.join(ASSET_DIR, "build_scoops.py"), encoding="utf-8").read()
_source = _source.replace("BUILT = {fid: build(fid) for fid in FLAVORS}", "BUILT = {}")
exec(_source)  # the helpers (blob, scatter, rim_band, build, ...) and the commons' FLAVORS, without building them

COMMONS = set(FLAVORS)

# How big the painted things are against the sizes written below (tuned on the previews, 18.11.2026): the toppings
# that name a flavor read from across the arena, the swirls run wide and steep like in the designs.
TOPPING = 3.0
RIBBON_WIDTH = 1.7
RIBBON_SWING = 1.5
CHUNK = 1.35


# ------------------------------------------------------------------------------------------------- new helpers ---


def scoop_grid(flavor):
    """Every pixel of the scoop's share of the picture: rows, columns, scoop V (0 bottom of the drips, 1 the top) and
    U (0..1 around, 0 at the front)."""
    rows = np.arange(0, int(flavor["uv_top"] * H))
    yy, xx = np.meshgrid(rows, np.arange(W), indexing="ij")
    v = (yy + 0.5) / (flavor["uv_top"] * H)
    u = (xx + 0.5) / W
    return yy, xx, v, u


def ribbon(img, flavor, centre, amplitude, width, color, waves=1, phase=0.0, alpha=0.95, shine=None, soft=1.6):
    """A swirl: a band running round the scoop whose middle goes up and down (`waves` times round, `amplitude` in
    scoop V), `width` its half width in scoop V; `shine` a lighter line along its upper edge (the gloss of a sauce)."""
    width, amplitude = width * RIBBON_WIDTH, amplitude * RIBBON_SWING
    yy, xx, v, u = scoop_grid(flavor)
    middle = centre + amplitude * np.sin(2 * math.pi * (waves * u + phase))
    px = flavor["uv_top"] * H  # pixels per scoop V
    d = np.abs(v - middle) * px
    a = np.clip((width * px - d) / soft + 0.5, 0, 1) * alpha
    blend(img, yy, xx, a, color)
    if shine:
        d2 = np.abs(v - (middle + width * 0.45)) * px
        a2 = np.clip((width * px * 0.22 - d2) / soft + 0.5, 0, 1) * 0.55
        blend(img, yy, xx, a2, shine)


def glaze(img, flavor, edge, color, drips=9, length=0.14, seed=0, alpha=1.0, shine=None):
    """A glaze over the top: everything above scoop V `edge` in `color`, with `drips` round drips hanging down by up
    to `length` (sauce, icing, honey); `shine` a lighter band just inside its lower edge."""
    rng = np.random.default_rng(seed)
    yy, xx, v, u = scoop_grid(flavor)
    low = np.zeros_like(u)
    for _ in range(drips):
        cu = rng.uniform(0, 1)
        half = rng.uniform(0.025, 0.05)
        drop = rng.uniform(0.45, 1.0) * length
        du = np.minimum(np.abs(u - cu), 1 - np.abs(u - cu)) / half
        low = np.maximum(low, drop * np.sqrt(np.clip(1 - du**2, 0, 1)))
    wave = 0.012 * np.sin(2 * math.pi * 5 * u + seed)
    line = edge - low + wave
    px = flavor["uv_top"] * H
    a = np.clip((v - line) * px / 1.4 + 0.5, 0, 1) * alpha
    blend(img, yy, xx, a, color)
    if shine:
        inner = np.clip(1 - np.abs(v - (line + 0.05)) * px / 3.0, 0, 1) * (v > line) * 0.45
        blend(img, yy, xx, inner, shine)


def sprinkles(img, flavor, rng, count, colors, vmin=0.4, vmax=0.88, size=1.5):
    """Little rod sprinkles in many colours, at all angles."""

    def one(u, v, i):
        blob(img, flavor, u, v, size, colors[i % len(colors)], 1.0, stretch=2.8, turn=rng.uniform(0, math.pi))

    scatter(img, flavor, rng, count, vmin, vmax, one)


def dots(img, flavor, rng, count, color, size=1.6, vmin=0.38, vmax=0.88, alpha=0.9, stretch=1.0):
    def one(u, v, i):
        blob(img, flavor, u, v, size * rng.uniform(0.8, 1.2), color, alpha, stretch, turn=rng.uniform(0, math.pi))

    scatter(img, flavor, rng, count, vmin, vmax, one)


def berry(img, flavor, u, v, size, color, light, stem=None):
    """A round fruit (berry, cherry, grape) with a shine; `stem` draws a short dark stalk on top."""
    size *= TOPPING
    blob(img, flavor, u, v, size, color, 1.0)
    blob(img, flavor, u - size * 0.28 / W, v + size * 0.3 / H, size * 0.3, light, 0.85)
    if stem:
        blob(img, flavor, u + size * 0.15 / W, v + size * 1.25 / H, size * 0.22, stem, 1.0, stretch=3.0, turn=0.3)


def cluster(img, flavor, u, v, size, color, light, count=7, seed=0):
    """A raspberry or a grape bunch: small round drupelets in a heap."""
    size *= TOPPING
    rng = np.random.default_rng(seed)
    for k in range(count):
        a = k / count * 2 * math.pi
        r = 0 if k == 0 else size * 0.9
        berry(img, flavor, u + math.cos(a) * r * ASPECT / W, v + math.sin(a) * r / H, size * 0.62 / TOPPING, color, light)


def slice_of(img, flavor, u, v, size, rind, flesh, white=None, segments=True):
    """A fruit slice standing on its cut edge: a half disc (flat at the bottom, round on top) with the rind round the
    curve, a pale pith line inside it (`white`) and the flesh in wedges (orange, lime, peach; coconut without wedges)."""
    size *= TOPPING
    radius = size * 0.8  # pixels up; across it is ASPECT times wider on the picture
    cx, cy = u * W, v * flavor["uv_top"] * H
    reach = int(radius * ASPECT) + 3
    rows = np.arange(max(0, int(cy) - 2), min(int(flavor["uv_top"] * H), int(cy + radius) + 3))
    cols = np.arange(int(cx) - reach, int(cx) + reach + 1)
    if len(rows) == 0:
        return
    yy, xx = np.meshgrid(rows, cols, indexing="ij")
    dx = (xx - cx) / ASPECT
    dy = yy - cy
    r = np.sqrt(dx**2 + dy**2) / radius
    up = np.clip(dy + 0.5, 0, 1)  # only the upper half, a soft cut edge
    inside = np.clip((1 - r) * radius, 0, 1) * up
    blend(img, yy, xx % W, inside, rind)
    if white:
        blend(img, yy, xx % W, np.clip((0.86 - r) * radius, 0, 1) * np.clip(dy - 0.5, 0, 1), white)
    core = np.clip((0.74 - r) * radius, 0, 1) * np.clip(dy - 1.0, 0, 1)
    if segments:
        angle = np.arctan2(dy, dx)
        core = core * (np.abs(np.sin(angle * 2.5)) > 0.16)  # five wedges with pale lines between them
    blend(img, yy, xx % W, core, flesh)


def flower(img, flavor, u, v, size, petal, middle):
    size *= TOPPING
    for k in range(5):
        a = k / 5 * 2 * math.pi + 0.3
        blob(img, flavor, u + math.cos(a) * size * 0.55 * ASPECT / W, v + math.sin(a) * size * 0.55 / H, size * 0.5,
             petal, 1.0)
    blob(img, flavor, u, v, size * 0.32, middle, 1.0)


def chunks(img, flavor, rng, count, color, light=None, size=(4.0, 6.0), vmin=0.38, vmax=0.86, square=True):
    """Cubes or blocks (brownie, caramel, chocolate, salt), a lighter top edge if `light`."""

    def one(u, v, i):
        s = rng.uniform(*size) * CHUNK
        turn = rng.uniform(-0.5, 0.5)
        blob(img, flavor, u, v, s, color, 1.0, square=square, turn=turn, wobble=0 if square else 0.3, seed=i)
        if light:
            blob(img, flavor, u, v + s * 0.5 / H, s * 0.55, light, 0.9, 0.45, square=square, turn=turn)

    scatter(img, flavor, rng, count, vmin, vmax, one)


def front(*places):
    """The toppings sit at the front (u near 0) and once more at the back, so a scoop shows one from both sides."""
    return places


def paint(flavor_id, steps, seed):
    flavor = FLAVORS[flavor_id]
    rng = np.random.default_rng(seed)
    img = canvas()
    for step in steps:
        step(img, flavor, rng)
    return img


# ------------------------------------------------------------------------------------------------- the flavors ---
# colour: the part's colour in the game (Config/Flavors) under the picture. Colours next to each other on the tower
# were pushed apart where two flavors read alike (see the report Stand Sorten 2026-11-18): e.g. blueberry periwinkle
# against grape violet against blue raspberry cyan; caramel orange against honey gold against maple cream.

R = {}  # flavor id -> (colour, roughness, steps, seed)


def flavor(fid, color, steps, roughness=None, seed=1):
    R[fid] = (color, roughness, steps, seed)


# --- uncommon ----------------------------------------------------------------------------------------------------
flavor("blueberry", "#8E92EE", [
    lambda i, f, r: ribbon(i, f, 0.6, 0.12, 0.05, "#4A4FC2", 1, 0.1, shine="#B9BCFF"),
    lambda i, f, r: dots(i, f, r, 30, "#3B3F9E", 1.3),
    lambda i, f, r: [berry(i, f, u, v, 6.5, "#2E2F7A", "#9EA6FF") for u, v in ((0.02, 0.55), (0.07, 0.68), (0.52, 0.6))],
], seed=101)
flavor("raspberry", "#E8557E", [
    lambda i, f, r: dots(i, f, r, 40, "#B8264E", 1.2, stretch=1.4),
    lambda i, f, r: [cluster(i, f, u, v, 4.2, "#C2185B", "#FF8FB5", seed=k) for k, (u, v) in
                     enumerate(((0.0, 0.6), (0.5, 0.55), (0.3, 0.72)))],
], seed=102)
flavor("peach", "#FFBE8A", [
    lambda i, f, r: dots(i, f, r, 26, "#F59A4A", 2.0, stretch=1.3),
    lambda i, f, r: [slice_of(i, f, u, v, 10, "#E8502A", "#FFD27A", segments=False) for u, v in ((0.0, 0.58), (0.5, 0.62))],
], seed=103)
flavor("grape", "#A65BE0", [
    lambda i, f, r: dots(i, f, r, 34, "#7B3CC0", 1.4),
    lambda i, f, r: [cluster(i, f, u, v, 4.6, "#5A1E9C", "#C79AF5", 6, k) for k, (u, v) in
                     enumerate(((0.02, 0.6), (0.5, 0.62)))],
], seed=104)
flavor("coconut", "#F3E6D6", [
    lambda i, f, r: dots(i, f, r, 34, "#6B4428", 2.2, stretch=0.45, alpha=0.95),
    lambda i, f, r: dots(i, f, r, 40, "#FFFFFF", 1.4, stretch=2.4),
    lambda i, f, r: [slice_of(i, f, u, v, 10, "#5A3820", "#FFFFFF", segments=False) for u, v in ((0.02, 0.6), (0.52, 0.58))],
], seed=105)
flavor("cherry", "#FAC6CE", [
    lambda i, f, r: ribbon(i, f, 0.55, 0.1, 0.06, "#D2203A", 1, 0.0, shine="#FF7A8C"),
    lambda i, f, r: ribbon(i, f, 0.78, 0.07, 0.035, "#D2203A", 1, 0.5),
    lambda i, f, r: dots(i, f, r, 22, "#D2203A", 1.2),
    lambda i, f, r: [berry(i, f, u, v, 7, "#C8102E", "#FF8A96", "#3E7A1E") for u, v in ((0.0, 0.62), (0.05, 0.6),
                                                                                         (0.5, 0.64))],
], seed=106)
flavor("pineapple", "#FFEAA0", [
    lambda i, f, r: chunks(i, f, r, 26, "#F5B01E", "#FFE36A", (3.5, 5.0)),
], seed=107)
flavor("orange", "#FF7F30", [
    lambda i, f, r: ribbon(i, f, 0.62, 0.11, 0.045, "#FFD7A3", 1, 0.25, shine="#FFF2DC"),
    lambda i, f, r: dots(i, f, r, 30, "#D9531A", 1.2, stretch=1.8),
    lambda i, f, r: [slice_of(i, f, u, v, 11, "#F05A0A", "#FFB347", "#FFF0D8") for u, v in ((0.0, 0.58), (0.5, 0.6))],
], seed=108)
flavor("lime", "#A9DE3E", [
    lambda i, f, r: ribbon(i, f, 0.6, 0.12, 0.04, "#4C9A22", 2, 0.1, shine="#CFF27A"),
    lambda i, f, r: dots(i, f, r, 26, "#5FA82A", 1.3, stretch=1.6),
    lambda i, f, r: [slice_of(i, f, u, v, 11, "#3E8E1E", "#D8F28A", "#F2FFD8") for u, v in ((0.0, 0.6), (0.5, 0.58))],
], seed=109)
flavor("caramel", "#E8933C", [
    lambda i, f, r: ribbon(i, f, 0.62, 0.1, 0.045, "#A85316", 1, 0.3, shine="#F5B56A"),
    lambda i, f, r: chunks(i, f, r, 14, "#C9762A", "#F3B66A", (4.0, 5.5)),
], roughness=0.25, seed=110)
flavor("blue_raspberry", "#33B5F2", [
    lambda i, f, r: ribbon(i, f, 0.6, 0.12, 0.05, "#1D4FC8", 1, 0.6, shine="#7FD4FF"),
    lambda i, f, r: [cluster(i, f, u, v, 4.4, "#1E3FA8", "#7FB2FF", seed=k) for k, (u, v) in
                     enumerate(((0.02, 0.6), (0.52, 0.62)))],
], seed=111)

# --- rare --------------------------------------------------------------------------------------------------------
flavor("cotton_candy", "#96D6FF", [
    lambda i, f, r: ribbon(i, f, 0.55, 0.12, 0.06, "#FF86CF", 1, 0.0, shine="#FFC6EA"),
    lambda i, f, r: ribbon(i, f, 0.8, 0.06, 0.04, "#FF86CF", 2, 0.4),
    lambda i, f, r: sprinkles(i, f, r, 18, ["#B57BFF", "#FF5FB0", "#FFFFFF"], size=1.4),
], seed=201)
flavor("red_velvet", "#B0243E", [
    lambda i, f, r: ribbon(i, f, 0.58, 0.12, 0.06, "#FFF0E4", 1, 0.15, shine="#FFFFFF"),
    lambda i, f, r: dots(i, f, r, 30, "#FFE2D2", 1.6),
], seed=202)
flavor("birthday_cake", "#FFF3DE", [
    lambda i, f, r: ribbon(i, f, 0.6, 0.11, 0.045, "#FF6FB5", 1, 0.0),
    lambda i, f, r: ribbon(i, f, 0.5, 0.1, 0.03, "#5BC0F0", 1, 0.0),
    lambda i, f, r: sprinkles(i, f, r, 46, ["#FF4F7B", "#FFC83D", "#3EC1F0", "#6BD66B", "#B57BFF"], size=1.5),
], seed=203)
flavor("brownie", "#A3744E", [
    lambda i, f, r: ribbon(i, f, 0.66, 0.1, 0.045, "#4A2817", 1, 0.2, shine="#7A4A30"),
    lambda i, f, r: chunks(i, f, r, 14, "#3C2214", "#6A4028", (5.0, 7.0)),
], seed=204)
flavor("cookies_cream", "#EEE8E1", [
    lambda i, f, r: ribbon(i, f, 0.68, 0.1, 0.025, "#3A2A24", 1, 0.4),
    lambda i, f, r: chunks(i, f, r, 24, "#2A2422", None, (3.5, 6.0), square=False),
    lambda i, f, r: dots(i, f, r, 30, "#4A3A34", 1.0),
], seed=205)
flavor("coffee", "#D6B089", [
    lambda i, f, r: ribbon(i, f, 0.62, 0.12, 0.05, "#5A3520", 1, 0.1, shine="#8A5A3A"),
    lambda i, f, r: scatter(i, f, r, 12, 0.4, 0.86, lambda u, v, k: (
        blob(i, f, u, v, 4.5, "#4E2C16", 1.0, stretch=1.4, turn=0.4),
        blob(i, f, u, v, 2.6, "#8A5A34", 0.9, stretch=0.18, turn=0.4))),
], seed=206)
flavor("dragon_fruit", "#E62E9E", [
    lambda i, f, r: dots(i, f, r, 60, "#1A1A1A", 0.9),
    lambda i, f, r: scatter(i, f, r, 9, 0.42, 0.82, lambda u, v, k: (
        blob(i, f, u, v, 6.0, "#FFF5FA", 1.0, square=True, turn=0.3),
        blob(i, f, u + 1.5 / W, v + 1.0 / H, 0.9, "#1A1A1A", 1.0),
        blob(i, f, u - 2.0 / W, v - 1.5 / H, 0.9, "#1A1A1A", 1.0))),
], seed=207)
flavor("pomegranate", "#E86F90", [
    lambda i, f, r: ribbon(i, f, 0.7, 0.08, 0.02, "#A3122E", 2, 0.2),
    lambda i, f, r: scatter(i, f, r, 34, 0.4, 0.86, lambda u, v, k: berry(i, f, u, v, 2.4, "#C0102E", "#FF8A9A")),
], roughness=0.25, seed=208)
flavor("honey", "#FFCC66", [
    lambda i, f, r: glaze(i, f, 0.8, "#E89412", 10, 0.2, seed=9, shine="#FFD77A"),
    lambda i, f, r: chunks(i, f, r, 10, "#F5A623", "#FFE08A", (3.0, 4.0), vmax=0.66),
], roughness=0.15, seed=209)
flavor("maple_syrup", "#F5D5A2", [
    lambda i, f, r: ribbon(i, f, 0.55, 0.1, 0.035, "#B8471A", 1, 0.2),
    lambda i, f, r: glaze(i, f, 0.84, "#C2501A", 9, 0.16, seed=10, shine="#E8854A"),
    lambda i, f, r: dots(i, f, r, 10, "#D13A1A", 2.6, vmax=0.7),
], roughness=0.2, seed=210)

# --- epic --------------------------------------------------------------------------------------------------------
flavor("tiramisu", "#E8CCA4", [
    lambda i, f, r: ribbon(i, f, 0.62, 0.1, 0.04, "#4A2817", 1, 0.3, shine="#7A4A30"),
    lambda i, f, r: glaze(i, f, 0.84, "#7A4A2A", 9, 0.1, seed=25, alpha=0.7),  # the cocoa dusting on top
    lambda i, f, r: dots(i, f, r, 220, "#6B4022", 1.1, vmin=0.36, vmax=0.95, alpha=0.85),
    lambda i, f, r: chunks(i, f, r, 6, "#F2D6A0", "#FFF0CF", (5.0, 6.0), vmax=0.6),
], seed=301)
flavor("white_chocolate", "#FFF3D8", [
    lambda i, f, r: ribbon(i, f, 0.6, 0.1, 0.025, "#EAD3A4", 1, 0.2),
    lambda i, f, r: chunks(i, f, r, 16, "#E9D4A6", "#FFFBF0", (5.0, 7.0)),
], roughness=0.2, seed=302)
flavor("black_cherry", "#B83D6A", [
    lambda i, f, r: ribbon(i, f, 0.6, 0.12, 0.055, "#3D0A1F", 1, 0.0, shine="#7A2042"),
    lambda i, f, r: ribbon(i, f, 0.8, 0.06, 0.03, "#3D0A1F", 2, 0.4),
    lambda i, f, r: [berry(i, f, u, v, 7, "#4A0A1E", "#C25A80", "#3E7A1E") for u, v in ((0.0, 0.58), (0.06, 0.62),
                                                                                         (0.52, 0.6))],
], seed=303)
flavor("pistachio_cream", "#D2E69A", [
    lambda i, f, r: ribbon(i, f, 0.55, 0.1, 0.035, "#8DB34A", 1, 0.3),
    lambda i, f, r: glaze(i, f, 0.8, "#FFF6DC", 9, 0.16, seed=11),
    lambda i, f, r: dots(i, f, r, 26, "#6E9638", 2.0, vmax=0.7),
], seed=304)
flavor("salted_caramel", "#F3C58E", [
    lambda i, f, r: glaze(i, f, 0.78, "#B8601A", 10, 0.2, seed=12, shine="#E0904A"),
    lambda i, f, r: chunks(i, f, r, 10, "#D9852E", "#F5BB72", (4.0, 5.0), vmax=0.62),
    lambda i, f, r: dots(i, f, r, 40, "#FFFFFF", 1.0, vmin=0.4, vmax=0.95),
], roughness=0.2, seed=305)
flavor("marzipan", "#F2CBB2", [
    lambda i, f, r: ribbon(i, f, 0.55, 0.1, 0.04, "#5A3420", 1, 0.25, shine="#8A5A3A"),
    lambda i, f, r: glaze(i, f, 0.84, "#FFF4E4", 8, 0.12, seed=13),
    lambda i, f, r: dots(i, f, r, 14, "#C68A55", 3.0, stretch=1.5, vmax=0.72),
], seed=306)
flavor("cinnamon_roll", "#E8B87C", [
    lambda i, f, r: glaze(i, f, 0.82, "#FFF6EA", 9, 0.15, seed=14),
    lambda i, f, r: [blob(i, f, (cu + 0.045 * t * math.cos(t * 2.2)) % 1.0, cv + 0.09 * t * math.sin(t * 2.2) / 2.0,
                          2.4, "#8A4A1E", 1.0) for cu, cv in ((0.0, 0.58), (0.25, 0.6), (0.5, 0.56), (0.75, 0.6))
                     for t in np.linspace(0.2, 3.0, 22)],
], seed=307)
flavor("cheesecake", "#FFF0C6", [
    lambda i, f, r: rim_band(i, f, RIM_V + 0.05, "#C9954A", 1.0, wave=1.5),
    lambda i, f, r: dots(i, f, r, 30, "#9A6A2E", 1.4, vmin=0.05, vmax=0.38),
    lambda i, f, r: ribbon(i, f, 0.66, 0.1, 0.04, "#C2183A", 1, 0.1, shine="#F0607A"),
], seed=308)
flavor("mocha", "#9A6A4C", [
    lambda i, f, r: glaze(i, f, 0.8, "#FFF0DC", 9, 0.16, seed=15),
    lambda i, f, r: ribbon(i, f, 0.55, 0.08, 0.035, "#4A2817", 1, 0.3),
    lambda i, f, r: chunks(i, f, r, 10, "#3E2214", "#6A4028", (3.5, 5.0), vmax=0.65),
], seed=309)
flavor("passion_fruit", "#FFB830", [
    lambda i, f, r: ribbon(i, f, 0.52, 0.1, 0.03, "#7A2E6E", 1, 0.15),
    lambda i, f, r: glaze(i, f, 0.82, "#F07A10", 9, 0.16, seed=16, shine="#FFB04A"),
    lambda i, f, r: dots(i, f, r, 46, "#1E1A14", 1.3, stretch=1.3, vmin=0.4, vmax=0.95),
], roughness=0.2, seed=310)

# --- legendary ---------------------------------------------------------------------------------------------------
flavor("royal_cream", "#F6DFB8", [
    lambda i, f, r: ribbon(i, f, 0.56, 0.11, 0.055, "#7B2FBE", 1, 0.2, shine="#B57BFF"),
    lambda i, f, r: glaze(i, f, 0.84, "#E8B020", 9, 0.12, seed=17, shine="#FFE27A"),
    lambda i, f, r: dots(i, f, r, 24, "#FFD54A", 1.2, vmax=0.7),
], roughness=0.2, seed=401)
flavor("midnight_berry", "#6A2FA0", [
    lambda i, f, r: ribbon(i, f, 0.58, 0.12, 0.045, "#D63FA8", 1, 0.0, shine="#FF8AD8"),
    lambda i, f, r: glaze(i, f, 0.86, "#3E1478", 8, 0.12, seed=18, shine="#8A5AD0"),
    lambda i, f, r: [berry(i, f, u, v, 5.5, c, "#9EA6FF") for u, v, c in ((0.0, 0.56, "#2A1050"), (0.05, 0.6, "#3A3AA8"),
                                                                           (0.5, 0.58, "#2A1050"))],
    lambda i, f, r: cluster(i, f, 0.28, 0.6, 3.6, "#C2185B", "#FF8FB5", seed=4),
], roughness=0.2, seed=402)
flavor("frosted_melon", "#FFA766", [
    lambda i, f, r: ribbon(i, f, 0.56, 0.12, 0.05, "#9BD36A", 1, 0.35, shine="#D8F5B0"),
    lambda i, f, r: glaze(i, f, 0.84, "#EAFBFF", 9, 0.13, seed=19),
    lambda i, f, r: chunks(i, f, r, 10, "#BFEFFF", "#FFFFFF", (2.5, 3.5), vmin=0.4, vmax=0.75),
], seed=403)
flavor("velvet_dream", "#C23A64", [
    lambda i, f, r: ribbon(i, f, 0.56, 0.12, 0.05, "#F08AA8", 1, 0.1, shine="#FFD0DC"),
    lambda i, f, r: glaze(i, f, 0.82, "#FFF2EC", 10, 0.15, seed=20),
    lambda i, f, r: dots(i, f, r, 20, "#7E1630", 1.8, vmax=0.7),
], seed=404)
flavor("mystic_plum", "#C25AB8", [
    lambda i, f, r: ribbon(i, f, 0.58, 0.12, 0.05, "#E6B8F2", 1, 0.2, shine="#FFFFFF"),
    lambda i, f, r: glaze(i, f, 0.86, "#8A2A90", 8, 0.12, seed=21),
    lambda i, f, r: scatter(i, f, r, 8, 0.4, 0.75, lambda u, v, k: (
        blob(i, f, u, v, 3.4, "#FFD24A", 1.0), blob(i, f, u + 1.6 / W, v + 1.0 / H, 3.0, "#C25AB8", 1.0))),
    lambda i, f, r: [blob(i, f, u, v, 6.5, "#5A1A60", 1.0) for u, v in ((0.02, 0.56), (0.52, 0.58))],
], roughness=0.25, seed=405)
flavor("arctic_coconut", "#F0F7FF", [
    lambda i, f, r: ribbon(i, f, 0.58, 0.11, 0.045, "#5EC8F2", 1, 0.3, shine="#C8F0FF"),
    lambda i, f, r: chunks(i, f, r, 12, "#CFF2FF", "#FFFFFF", (2.5, 3.5), vmin=0.6, vmax=0.9),
    lambda i, f, r: dots(i, f, r, 26, "#7A5030", 2.0, stretch=0.45, vmax=0.6),
], seed=406)
flavor("crimson_velvet", "#7E0F24", [
    lambda i, f, r: ribbon(i, f, 0.55, 0.1, 0.03, "#F6E2CF", 1, 0.0),
    lambda i, f, r: glaze(i, f, 0.82, "#C0182E", 9, 0.16, seed=22, shine="#F05A6A"),
    lambda i, f, r: dots(i, f, r, 26, "#E8B020", 1.0),
], roughness=0.18, seed=407)
flavor("honey_blossom", "#FFEBC2", [
    lambda i, f, r: ribbon(i, f, 0.55, 0.1, 0.035, "#F5B030", 1, 0.25),
    lambda i, f, r: glaze(i, f, 0.84, "#F29A1E", 9, 0.14, seed=23, shine="#FFD07A"),
    lambda i, f, r: [flower(i, f, u, v, 8, "#FFFFFF", "#FFC83D") for u, v in ((0.0, 0.6), (0.33, 0.62), (0.66, 0.6))],
], roughness=0.2, seed=408)
flavor("velvet_mocha", "#5E3422", [
    lambda i, f, r: ribbon(i, f, 0.58, 0.12, 0.05, "#F2DCC0", 1, 0.1, shine="#FFFFFF"),
    lambda i, f, r: glaze(i, f, 0.86, "#FFF0DC", 8, 0.1, seed=24),
    lambda i, f, r: chunks(i, f, r, 10, "#2A140A", "#4A2817", (3.5, 5.0), vmax=0.62),
], roughness=0.18, seed=409)
flavor("sapphire_cream", "#F4F6FF", [
    lambda i, f, r: ribbon(i, f, 0.6, 0.12, 0.06, "#1E3FBF", 1, 0.0, shine="#6E8CFF"),
    lambda i, f, r: ribbon(i, f, 0.84, 0.05, 0.03, "#1E3FBF", 2, 0.4),
    lambda i, f, r: dots(i, f, r, 22, "#E8B020", 1.0),
    lambda i, f, r: [berry(i, f, u, v, 6, "#2A2F8A", "#9EB0FF") for u, v in ((0.02, 0.5), (0.5, 0.52))],
], roughness=0.15, seed=410)

ORDER = list(R)  # in rarity order, as above


def make_details(fid):
    color, roughness, steps, seed = R[fid]
    return lambda: paint(fid, steps, seed)


for fid, (color, roughness, steps, seed) in R.items():
    spec = {**BASE, "color": color}
    if roughness is not None:
        spec["roughness"] = roughness
        spec["surface_roughness"] = roughness
    FLAVORS[fid] = spec
    globals()["details_" + fid] = make_details(fid)

ONLY = globals().get("ONLY") or ORDER
BUILT = {fid: build(fid) for fid in ONLY if fid not in COMMONS}
print("built", len(BUILT), "flavors")
