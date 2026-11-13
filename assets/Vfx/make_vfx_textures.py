"""The particle pictures of the game's effects (src/client/Vfx, ids in src/shared/Config/Vfx.luau). Run in a
background Blender, without touching an open session:
    blender -b --factory-startup --python assets/Vfx/make_vfx_textures.py -- [--preview <folder>] [--only <names>]
Writes assets/Vfx/textures/<name>.png and saves the splat scene as assets/Vfx/Vfx.blend. With --preview it also writes
a contact sheet (Texturen.png, every picture tinted on the arena floor colour) into that folder (the vault's
"VFX Vorschau"; previews do not go into the repo).

Every picture is white with a dark outline and a light gloss, so the ParticleEmitter's Color tints it: the outline
stays dark, the body takes the colour. Small on purpose (256 px, the flipbook 512 px).

    Vfx_Sprinkle   a sprinkle: a short rounded stick
    Vfx_Blob       a blob of cream
    Vfx_Drop       a drop of glaze, tip up
    Vfx_Star       a small rounded star
    Vfx_Cloud      a soft puff, no outline
    Vfx_Ring       a soft ring (shock wave), no outline
    Vfx_Flash      a short bright flash: a soft core with four rays, no outline
    Vfx_Splat      a splash of cream as a flipbook, 4 x 4 frames of 128 px, rendered from metaballs (the one picture
                   that needs Blender's 3D: the cream bursts, strings out and thins away)
    Vfx_Coin       a spinning coin as a flipbook, 4 x 4 frames of 128 px: the HUD's coin (lemon disc, waffle rim, inner
                   ring) squeezed sideways frame by frame, one full turn

After a change: upload the PNGs again (`lune run scripts/vfx-serve`, then Studio MCP upload_image) and put the new
ids into Config/Vfx.textures.
"""

import math
import os
import random
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "textures")
os.makedirs(OUT, exist_ok=True)
ARGS = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
PREVIEW = ARGS[ARGS.index("--preview") + 1] if "--preview" in ARGS else None

OUTLINE = np.array([0.30, 0.16, 0.10])  # the UI's chocolate outline, darkened by the tint in the game
BODY = 0.9  # the body's grey: the gloss (1.0) still shows on it after tinting
SIZE = 256


def grid(size):
    """Pixel centres in -1..1, y up."""
    axis = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(axis, -axis)
    return x, y


def smooth(edge0, edge1, value):
    t = np.clip((value - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


def circle(x, y, cx, cy, r):
    return np.hypot(x - cx, y - cy) - r


def capsule(x, y, ax, ay, bx, by, r):
    pax, pay, bax, bay = x - ax, y - ay, bx - ax, by - ay
    h = np.clip((pax * bax + pay * bay) / (bax * bax + bay * bay), 0, 1)
    return np.hypot(pax - bax * h, pay - bay * h) - r


def star(x, y, r_out, r_in, points=5):
    """Distance to a star, by its nearest edge (good enough for a rounded outline)."""
    angle = np.arctan2(x, y)
    step = math.pi / points
    local = np.abs((angle + step) % (2 * step) - step)  # 0 at a tip, step at a notch
    radius = np.hypot(x, y)
    px, py = radius * np.cos(local), radius * np.sin(local)
    ax, ay = r_out, 0.0
    bx, by = r_in * math.cos(step), r_in * math.sin(step)
    ex, ey = bx - ax, by - ay
    h = np.clip(((px - ax) * ex + (py - ay) * ey) / (ex * ex + ey * ey), 0, 1)
    distance = np.hypot(px - ax - ex * h, py - ay - ey * h)
    inside = (px - ax) * ey - (py - ay) * ex > 0
    return np.where(inside, distance, -distance)


def candy(sdf, x, y, outline=0.11, gloss=(-0.28, 0.34, 0.2, 0.11)):
    """White candy body with a dark outline and a gloss spot from a distance field (negative inside)."""
    pixel = 2 / sdf.shape[0]
    alpha = 1 - smooth(-pixel, pixel, sdf)
    body = 1 - smooth(-outline - pixel, -outline + pixel, sdf)
    shade = BODY - 0.1 * smooth(-0.2, 0.9, -y + 0.3 * x)  # a little darker to the bottom right
    gx, gy, gw, gh = gloss
    spot = 1 - smooth(0.7, 1.0, np.hypot((x - gx) / gw, (y - gy) / gh))
    spot *= body
    value = np.clip(shade + (1 - shade) * spot, 0, 1)
    rgb = OUTLINE[None, None, :] * (1 - body[..., None]) + value[..., None] * body[..., None]
    return np.dstack([rgb, alpha])


def soft(alpha):
    """Plain white with a soft alpha: tinted and faded by the emitter."""
    return np.dstack([np.ones(alpha.shape + (3,)), np.clip(alpha, 0, 1)])


def sprinkle():
    x, y = grid(SIZE)
    return candy(capsule(x, y, -0.42, -0.2, 0.42, 0.2, 0.3), x, y, outline=0.12, gloss=(-0.2, 0.12, 0.26, 0.08))


def blob():
    x, y = grid(SIZE)
    sdf = circle(x, y, -0.05, -0.02, 0.5)
    for cx, cy, r in [(0.42, 0.26, 0.26), (-0.46, 0.3, 0.2), (0.3, -0.44, 0.24), (-0.4, -0.42, 0.18), (0.08, 0.46, 0.22)]:
        sdf = smin(sdf, circle(x, y, cx, cy, r), 0.22)
    return candy(sdf, x, y, gloss=(-0.22, 0.2, 0.2, 0.12))


def drop():
    x, y = grid(SIZE)
    sdf = circle(x, y, 0, -0.3, 0.46)
    for step in range(1, 9):
        t = step / 8
        sdf = smin(sdf, circle(x, y, 0, -0.3 + 1.02 * t, 0.46 * (1 - t) ** 1.25 + 0.03), 0.12)
    return candy(sdf, x, y, gloss=(-0.17, -0.2, 0.13, 0.17))


def star_sprite():
    x, y = grid(SIZE)
    return candy(star(x, y, 0.78, 0.4) - 0.12, x, y, outline=0.12, gloss=(-0.16, 0.2, 0.16, 0.1))


def cloud():
    x, y = grid(SIZE)
    sdf = circle(x, y, 0, -0.05, 0.42)
    for cx, cy, r in [(-0.4, -0.12, 0.3), (0.4, -0.1, 0.32), (0.16, 0.3, 0.3), (-0.2, 0.26, 0.26)]:
        sdf = smin(sdf, circle(x, y, cx, cy, r), 0.18)
    return soft(1 - smooth(-0.13, 0.05, sdf))  # a full body with a soft edge: it has to read on the cream floor


def ring():
    x, y = grid(SIZE)
    distance = np.abs(np.hypot(x, y) - 0.78) - 0.07
    return soft(1 - smooth(-0.05, 0.1, distance))


def flash():
    x, y = grid(SIZE)
    radius = np.hypot(x, y)
    core = np.exp(-((radius / 0.3) ** 2))
    rays = np.exp(-((np.abs(x * y) / 0.012))) * np.exp(-((radius / 0.6) ** 2))
    return soft((core + rays) * (1 - smooth(0.85, 1.0, radius)))


def save(name, rgba):
    height, width = rgba.shape[:2]
    image = bpy.data.images.new(name, width, height, alpha=True)
    image.alpha_mode = "STRAIGHT"
    image.pixels.foreach_set(np.flipud(rgba).astype(np.float32).ravel())
    image.filepath_raw = os.path.join(OUT, name + ".png")
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    print("wrote", name, f"{width}x{height}")


# --- the splash flipbook ---------------------------------------------------------------------------------------------

FRAMES, CELL = 16, 128


def splat_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_WORKBENCH"
    except TypeError as problem:
        raise SystemExit(f"no Workbench engine: {problem}")
    scene.render.resolution_x = scene.render.resolution_y = CELL
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "SINGLE"
    shading.single_color = (BODY, BODY, BODY)
    shading.show_specular_highlight = True
    shading.show_shadows = False
    shading.show_cavity = False
    shading.show_object_outline = False  # the outline is drawn afterwards, as thick as on the other pictures

    mball = bpy.data.metaballs.new("VFX_Splat")
    mball.resolution = 0.05
    mball.render_resolution = 0.035
    mball.threshold = 0.45
    ob = bpy.data.objects.new("VFX_Splat", mball)
    scene.collection.objects.link(ob)

    camera_data = bpy.data.cameras.new("VFX_Camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 4.3
    camera = bpy.data.objects.new("VFX_Camera", camera_data)
    camera.location = (0, -10, 0)
    camera.rotation_euler = (math.pi / 2, 0, 0)
    scene.collection.objects.link(camera)
    scene.camera = camera

    rng = random.Random(7)
    drops = []
    count = 9
    for index in range(count):
        angle = index / count * 2 * math.pi + rng.uniform(-0.2, 0.2)
        drops.append(dict(angle=angle, speed=rng.uniform(1.15, 1.6), radius=rng.uniform(0.85, 1.25), lag=rng.uniform(0, 0.12)))
    core = mball.elements.new()
    elements = [mball.elements.new() for _ in drops]
    # two smaller balls behind each drop: the string of cream it pulls out of the middle
    tails = [(mball.elements.new(), mball.elements.new()) for _ in drops]
    return scene, mball, core, elements, tails, drops


def splat_pose(t, core, elements, tails, drops):
    """The splash at t in 0..1: the core swells and thins away, the drops fly out, sag and shrink."""
    swell = min(t / 0.07, 1) ** 0.5
    core.co = (0, 0, 0)
    core.radius = max(0.02, 2.0 * swell * (1 - t) ** 2.4)
    for element, tail, drop in zip(elements, tails, drops):
        local = max(0.0, min(1.0, (t - drop["lag"]) / (1 - drop["lag"])))
        out = 1 - (1 - local) ** 3.2
        reach = drop["speed"] * out
        sag = -0.3 * local * local
        cx, cz = math.sin(drop["angle"]), math.cos(drop["angle"])
        element.co = (cx * reach, 0, cz * reach + sag)
        element.radius = max(0.02, drop["radius"] * (1 - local**2.6))
        for part, share in zip(tail, (0.72, 0.42)):
            part.co = (cx * reach * share, 0, cz * reach * share + sag * share)
            part.radius = max(0.02, drop["radius"] * (0.55 + 0.4 * (1 - share)) * (1 - local) ** (0.9 + 1.6 * share))


def outlined(rgba, pixels=2):
    """A dark outline round a rendered frame: the alpha grown by `pixels`, the frame laid over it."""
    alpha = rgba[..., 3]
    # the render's grey shading, lifted to the other pictures' light body so the tint stays clean
    light = rgba[..., :3].mean(axis=2)
    top = max(light[alpha > 0.5].max(), 1e-3) if (alpha > 0.5).any() else 1.0
    lifted = np.clip(0.7 + 0.3 * (light / top) ** 1.5, 0, 1)
    rgba = np.dstack([lifted, lifted, lifted, alpha])
    grown = alpha.copy()
    for dx in range(-pixels, pixels + 1):
        for dy in range(-pixels, pixels + 1):
            if dx * dx + dy * dy <= pixels * pixels:
                grown = np.maximum(grown, np.roll(np.roll(alpha, dx, axis=1), dy, axis=0))
    rgb = OUTLINE[None, None, :] * (1 - alpha[..., None]) + rgba[..., :3] * alpha[..., None]
    return np.dstack([rgb, grown])


def splat():
    scene, mball, core, elements, tails, drops = splat_scene()
    sheet = np.zeros((CELL * 4, CELL * 4, 4))
    temp = os.path.join(bpy.app.tempdir, "vfx_splat_frame.png")
    for frame in range(FRAMES):
        # the burst comes first: the early frames move fast, the thinning out takes the rest
        splat_pose(0.1 + 0.9 * (frame / (FRAMES - 1)) ** 0.75, core, elements, tails, drops)
        mball.update_tag()
        bpy.context.view_layer.update()
        scene.render.filepath = temp
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(temp)
        pixels = np.empty(CELL * CELL * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        bpy.data.images.remove(image)
        cell = np.flipud(pixels.reshape(CELL, CELL, 4)).astype(np.float64)
        if frame == FRAMES - 1:
            cell[...] = 0  # the last frame is empty: the splash is gone when the particle ends
        else:
            cell = outlined(cell)
            cell[:3] = cell[-3:] = 0  # nothing bleeds into the neighbouring frames
            cell[:, :3] = cell[:, -3:] = 0
        row, column = divmod(frame, 4)
        sheet[row * CELL : (row + 1) * CELL, column * CELL : (column + 1) * CELL] = cell
    splat_pose(0.35, core, elements, tails, drops)  # the saved scene shows the splash mid-burst
    return sheet




def coin_frame(size, turn):
    """The coin seen at `turn` (0..1 of a full spin round its upright axis): a lemon disc with a waffle rim and an
    inner ring like the HUD's coin (Ui.coinIcon), squeezed sideways as it turns."""
    x, y = grid(size)
    squeeze = max(abs(math.cos(turn * 2 * math.pi)), 0.14)
    radius = 0.78
    distance = np.hypot(x / squeeze, y)
    sdf = (distance - radius) * squeeze  # roughly a distance in pixels' terms, so the outline keeps its width
    rgba = candy(sdf, x, y, outline=0.1, gloss=(-0.24 * squeeze, 0.3, 0.16 * squeeze + 0.03, 0.1))
    # the inner ring, half the coin across, drawn in the outline's colour at half strength
    inner = np.abs(distance - radius * 0.55) * squeeze - 0.035
    line = (1 - smooth(-0.012, 0.012, inner)) * 0.55 * (sdf < -0.1)
    rgba[..., :3] = rgba[..., :3] * (1 - line[..., None]) + OUTLINE[None, None, :] * line[..., None]
    return rgba


def coin():
    """Vfx_Coin: a spinning coin as a flipbook, 4 x 4 frames of 128 px, one full turn."""
    sheet = np.zeros((CELL * 4, CELL * 4, 4))
    for frame in range(FRAMES):
        cell = coin_frame(CELL, frame / FRAMES)
        cell[:2] = cell[-2:] = 0
        cell[:, :2] = cell[:, -2:] = 0
        row, column = divmod(frame, 4)
        sheet[row * CELL : (row + 1) * CELL, column * CELL : (column + 1) * CELL] = cell
    return sheet


def contact_sheet(pictures):
    """Every picture tinted in a game colour on the arena floor's cream, to judge them at a glance."""
    tints = {
        "Vfx_Sprinkle": "#FF8FA3",
        "Vfx_Blob": "#F9DCA8",
        "Vfx_Drop": "#9DE0C4",
        "Vfx_Star": "#FFD23F",
        "Vfx_Cloud": "#FFFFFF",
        "Vfx_Ring": "#FFFFFF",
        "Vfx_Flash": "#FFFFFF",
    }
    floor = np.array([0xFB, 0xE8, 0xD4]) / 255 * 0.82  # a little darker than the floor, so the white ones read
    width = SIZE * 4
    height = SIZE * 2 + CELL * 4
    sheet = np.ones((height, width, 4))
    sheet[..., :3] = floor
    for index, name in enumerate(tints):
        rgba = pictures[name]
        h = tints[name].lstrip("#")
        tint = np.array([int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)])
        row, column = divmod(index, 4)
        area = sheet[row * SIZE : (row + 1) * SIZE, column * SIZE : (column + 1) * SIZE]
        alpha = rgba[..., 3:4]
        area[..., :3] = area[..., :3] * (1 - alpha) + rgba[..., :3] * tint * alpha
    flip = pictures["Vfx_Splat"]
    tint = np.array([0xF9, 0xDC, 0xA8]) / 255
    area = sheet[SIZE * 2 :, : CELL * 4]
    alpha = flip[..., 3:4]
    area[..., :3] = area[..., :3] * (1 - alpha) + flip[..., :3] * tint * alpha
    os.makedirs(PREVIEW, exist_ok=True)
    image = bpy.data.images.new("Texturen", width, height, alpha=True)
    image.pixels.foreach_set(np.flipud(sheet).astype(np.float32).ravel())
    image.filepath_raw = os.path.join(PREVIEW, "Texturen.png")
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    print("wrote the contact sheet to", PREVIEW)


# every picture is built lazily, so --only <name>[,<name>] renders just those (the splat's render takes a while, and
# pictures that did not change keep their uploaded ids)
BUILDERS = {
    "Vfx_Sprinkle": sprinkle,
    "Vfx_Blob": blob,
    "Vfx_Drop": drop,
    "Vfx_Star": star_sprite,
    "Vfx_Cloud": cloud,
    "Vfx_Ring": ring,
    "Vfx_Flash": flash,
    "Vfx_Splat": splat,
    "Vfx_Coin": coin,
}
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else list(BUILDERS)
PICTURES = {name: BUILDERS[name]() for name in ONLY}
for picture_name, picture in PICTURES.items():
    save(picture_name, picture)
if PREVIEW and len(PICTURES) == len(BUILDERS):
    contact_sheet(PICTURES)
if "Vfx_Splat" in PICTURES:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "Vfx.blend"), compress=True)
    print("saved", os.path.join(HERE, "Vfx.blend"))
