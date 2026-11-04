"""Floor textures for the map: one seamless tile per floor, small, so phones load and draw it cheaply.
Run in Blender (uses its numpy and image saving), any open file:
    ASSET_DIR = r"<repo>/assets/ArenaKit"
    exec(open(ASSET_DIR + "/make_floor_textures.py").read())

Writes ASSET_DIR/textures/<name>.png. In Roblox a floor picture is a MaterialVariant (ColorMap, StudsPerTile =
`studs_per_tile` below) on the walkable part, never a Texture or Decal on it (those are drawn pulled towards the
camera and swallow landing circles and loot just above the floor, studio_arena_floor.luau). The colours are the game colours (arenakit.GAME_COLOURS, warm against the
island's cool light), kept light so players, scoops and landing circles read on it.

    ArenaFloor_Tiles   arena floor: 2 x 2 cream plates with soft pink grout, each plate a little lighter in the
                       middle and a touch different in tone (512 px, 12 studs per tile: plates of 6 studs),
                       rbxassetid://84950832445484
    ArenaEmblem        the emblem round the Big Swirl, one picture for one disc (1024 px, transparent outside),
                       rbxassetid://96149400644272
    Wyspa_Pavers       strip and hub ring: rounded pink-cream paving stones in a running bond (512 px, 12 studs
                       per tile: stones of 4 x 3 studs), rbxassetid://135223614271030, tinted #F2C2CB in
                       the game (studio_wyspa_floor.luau)
    LandingCircle_Ring the dark outline on a landing circle: a white ring, tinted in the game (256 px; a Decal is
                       right here, it lies on top of the circle), rbxassetid://88345459876129

After a change: upload the PNG again (Studio MCP upload_image or the Asset Manager) and put the new id into
studio_arena_floor.luau.
"""

import os

import bpy
import numpy as np

OUT = os.path.join(globals().get("ASSET_DIR") or os.path.dirname(bpy.data.filepath), "textures")
os.makedirs(OUT, exist_ok=True)


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)])


TILES = {
    "ArenaFloor_Tiles": dict(
        size=512,
        plates=2,  # plates per side in one tile
        # a touch warmer and the grout a touch stronger than first tried: under the island's bright sun and bloom
        # #FFF1E2 with #F7D3DF read as plain white
        plate="#FBE8D4",
        grout="#F2BFD2",
        grout_px=12,  # grout width in pixels (about 0.28 studs at 12 studs per tile)
        corner_px=22,  # rounded plate corners
        edge_shade=0.05,  # plates a little darker towards their edges
        tone_jitter=0.018,  # each plate a slightly different tone
        studs_per_tile=12,
    ),
}


def plate_tile(size, plates, plate, grout, grout_px, corner_px, edge_shade, tone_jitter, seed=7, **_):
    rng = np.random.default_rng(seed)
    cell = size // plates
    img = np.zeros((size, size, 3))
    y, x = np.mgrid[0:cell, 0:cell] + 0.5
    half_g = grout_px / 2
    # distance inside the rounded plate (negative in the grout), from a rounded rectangle
    inner = cell / 2 - half_g - corner_px
    qx = np.abs(x - cell / 2) - inner
    qy = np.abs(y - cell / 2) - inner
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - corner_px
    inside = np.clip(-outside, 0, None)
    coverage = np.clip(-outside + 0.5, 0, 1)  # anti-aliased edge
    shade = 1 - edge_shade * np.exp(-inside / (cell * 0.12))
    p, g = hex_rgb(plate), hex_rgb(grout)
    for i in range(plates):
        for j in range(plates):
            tone = 1 + rng.uniform(-tone_jitter, tone_jitter)
            colour = np.clip(p[None, None, :] * tone * shade[..., None], 0, 1)
            block = colour * coverage[..., None] + g[None, None, :] * (1 - coverage[..., None])
            img[i * cell : (i + 1) * cell, j * cell : (j + 1) * cell] = block
    return img


def save(name, rgb):
    size = rgb.shape[0]
    image = bpy.data.images.get(name) or bpy.data.images.new(name, size, size, alpha=False)
    if image.size[0] != size:
        image.scale(size, size)
    rgba = np.concatenate([rgb, np.ones((size, size, 1))], axis=2)
    image.pixels.foreach_set(rgba[::-1].astype(np.float32).ravel())  # Blender stores rows bottom-up
    image.filepath_raw = os.path.join(OUT, name + ".png")
    image.file_format = "PNG"
    image.save()
    print("wrote", image.filepath_raw, f"{size} px")


for tile_name, spec in TILES.items():
    save(tile_name, plate_tile(**spec))

# The strip and the hub ring (Wyspa): rounded pink-cream paving stones like the plot paths (reference "Bonbon-Wege
# für Eiscremewelten"), laid in a running bond, calm so the decoration placed on them later reads. One stone is
# `stone_studs` wide and `row_studs` deep; every second row is shifted by half a stone. Seamless: `per_row` stones
# fill the tile across, `rows` rows down.
PAVERS = dict(
    size=512,
    per_row=3,
    rows=4,  # 3 x 4 stones in a 12-stud tile: stones of 4 x 3 studs
    stone="#F8DCD8",
    grout="#ECBCC6",
    grout_px=8,
    corner_px=26,
    edge_shade=0.07,
    tone_jitter=0.025,
    studs_per_tile=12,
)


def paver_tile(size, per_row, rows, stone, grout, grout_px, corner_px, edge_shade, tone_jitter, seed=3, **_):
    rng = np.random.default_rng(seed)
    w, h = size / per_row, size / rows
    y, x = np.mgrid[0:size, 0:size] + 0.5
    row = np.floor(y / h).astype(int)
    shift = np.where(row % 2 == 1, w / 2, 0.0)
    xs = (x + shift) % size
    col = np.floor(xs / w).astype(int)
    lx, ly = xs - col * w, y - row * h  # position inside the stone
    half_g = grout_px / 2
    qx = np.abs(lx - w / 2) - (w / 2 - half_g - corner_px)
    qy = np.abs(ly - h / 2) - (h / 2 - half_g - corner_px)
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - corner_px
    inside = np.clip(-outside, 0, None)
    coverage = np.clip(-outside + 0.5, 0, 1)
    shade = 1 - edge_shade * np.exp(-inside / (h * 0.14))
    tones = 1 + rng.uniform(-tone_jitter, tone_jitter, size=(rows, per_row))
    tone = tones[row, col % per_row]
    s, g = hex_rgb(stone), hex_rgb(grout)
    colour = np.clip(s[None, None, :] * (tone * shade)[..., None], 0, 1)
    return colour * coverage[..., None] + g[None, None, :] * (1 - coverage[..., None])


save("Wyspa_Pavers", paver_tile(**PAVERS))

# The arena emblem as one picture (a Decal on one disc round the Big Swirl): layered discs do not work on a textured
# floor, Roblox draws textures a little towards the camera, so thin layers above one vanish or swap order. Drawn for
# a disc of EMBLEM["radius"] studs: Gold ring, Waffle lattice, pink ice cream with rounded drips running outwards,
# as if looking down into a cone. Transparent outside the ring.
EMBLEM = dict(
    size=1024,
    radius=49.0,  # studs, the disc
    gold=2.0,  # ring width
    ice=34.0,  # radius of the ice cream
    drips=16,
    drip_lengths=(3.0, 6.0, 4.2, 7.0, 3.6, 5.2),
    drip_radius=2.4,
    lattice=5.0,  # studs per waffle diamond
    ridge=0.9,  # ridge width in studs
)


def emblem_picture(size, radius, gold, ice, drips, drip_lengths, drip_radius, lattice, ridge):
    px = size / (2 * radius)  # pixels per stud
    y, x = (np.mgrid[0:size, 0:size] + 0.5 - size / 2) / px  # studs from the centre
    r = np.hypot(x, y)
    a = np.arctan2(x, y)

    def mask(dist):  # anti-aliased inside test from a signed distance in studs
        return np.clip(0.5 - dist * px, 0, 1)

    # waffle: diagonal lattice, seamless over the disc
    d1 = np.abs(((x + y) / np.sqrt(2)) % lattice - lattice / 2)
    d2 = np.abs(((x - y) / np.sqrt(2)) % lattice - lattice / 2)
    on_ridge = mask(np.minimum(lattice / 2 - d1, lattice / 2 - d2) - ridge / 2)
    pocket_shade = 1 - 0.06 * np.clip(np.minimum(d1, d2) / (lattice / 4), 0, 1)
    waffle = hex_rgb(GAME["Waffle"])[None, None, :] * pocket_shade[..., None]
    waffle = waffle * (1 - on_ridge[..., None]) + hex_rgb(GAME["Gold"])[None, None, :] * on_ridge[..., None]
    rgb = waffle
    # the ice cream: a disc plus rounded drips (a lobe at the end, a neck towards the ice)
    ice_dist = r - ice
    step = 2 * np.pi / drips
    blend = 1.6  # studs over which a drip flows into the ice (smooth union), no knobs
    for i in range(drips):
        ang = (i + 0.5) * step
        length = drip_lengths[i % len(drip_lengths)]
        dx, dy = np.sin(ang), np.cos(ang)
        # a capsule from inside the ice out to the drip's round tip
        start, end = ice - 2.0, ice - 1.0 + length
        t = np.clip(x * dx + y * dy, start, end)
        capsule = np.hypot(x - dx * t, y - dy * t) - drip_radius
        ice_dist = -blend * np.log(np.exp(-ice_dist / blend) + np.exp(-capsule / blend))
    ice_mask = mask(ice_dist)
    pink = hex_rgb(GAME["Pink"])
    # a soft lighter rim inside the ice cream edge, for a glossy look
    gloss = np.clip(1 + 0.12 * np.exp(ice_dist / 0.9), 1, 1.12)
    rgb = rgb * (1 - ice_mask[..., None]) + np.clip(pink[None, None, :] * gloss[..., None], 0, 1) * ice_mask[..., None]
    # the gold ring and the outside
    ring = 1 - mask(r - (radius - gold))  # everything past the waffle's edge is gold; alpha ends it at `radius`
    rgb = rgb * (1 - ring[..., None]) + hex_rgb(GAME["Gold"])[None, None, :] * ring[..., None]
    alpha = mask(r - radius)
    return np.concatenate([rgb, alpha[..., None]], axis=2)


GAME = {"Waffle": "#E2782C", "Gold": "#F2A83C", "Pink": "#F06AAE"}  # arenakit.GAME_COLOURS


def save_rgba(name, rgba):
    size = rgba.shape[0]
    image = bpy.data.images.get(name) or bpy.data.images.new(name, size, size, alpha=True)
    if image.size[0] != size:
        image.scale(size, size)
    image.pixels.foreach_set(rgba[::-1].astype(np.float32).ravel())
    image.filepath_raw = os.path.join(OUT, name + ".png")
    image.file_format = "PNG"
    image.save()
    print("wrote", image.filepath_raw, f"{size} px")


save_rgba("ArenaEmblem", emblem_picture(**EMBLEM))


def ring_picture(size=256, inner=0.80):
    """A white ring with a transparent middle, filling the picture: the outline Decal on a landing circle (tinted
    through Decal.Color3, ShotRenderer). `inner` is the ring's inner edge as a share of its radius."""
    y, x = (np.mgrid[0:size, 0:size] + 0.5 - size / 2) / (size / 2)
    r = np.hypot(x, y)
    px = size / 2
    alpha = np.clip(0.5 - (r - 1) * px, 0, 1) * np.clip(0.5 + (r - inner) * px, 0, 1)
    return np.concatenate([np.ones((size, size, 3)), alpha[..., None]], axis=2)


save_rgba("LandingCircle_Ring", ring_picture())
