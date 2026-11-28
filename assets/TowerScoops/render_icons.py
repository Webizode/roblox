"""The scoop icons of the UI (chest cards, later the index): one picture per flavor, rendered from the flavor's own
tower-scoop model, seen at an angle from the front and a little above, in soft light, on a transparent background.
Every scoop is framed alike (same size, same place in the picture), so the cards line up.

Run headless, no open Blender needed (all flavors, or only the ones named after "--"):
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --factory-startup ^
        --python assets/TowerScoops/render_icons.py -- [flavor_id ...]

Reads the Meshy LOD0 models (build_meshy.py, since 28.11.2026): Desktop/roblox-assets/TowerScoops/meshy_scoops/
<round>/<flavor>_LOD0.fbx, the latest round that has the flavor (ROUNDS), and their maps (assets/TowerScoops/meshy/
textures/<flavor>_{color,normal,rough}.png). A flavor with a show version (SHOW: the Meshy scoop with its big toppings,
kept apart since the tower's scoops have nothing on top) is drawn from that one: it looks best on its own.
Writes assets/TowerScoops/icons/<flavor>.png (SIZE x SIZE). A flavor without a model is listed at the end and left
out; the game draws the generic tinted scoop for it.

Then upload the pictures through the Studio MCP (upload_image, served with `lune run scripts/serve-images
assets/TowerScoops/icons 8766`) and put the ids into src/shared/Config/ScoopIcons.luau.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
FBX_ROOT = os.path.join(os.path.expanduser("~"), "Desktop", "roblox-assets", "TowerScoops", "meshy_scoops")
TEX_DIR = os.path.join(HERE, "meshy", "textures")
# the rounds in the order they were built: a later one replaces an earlier one's model of the same flavor
ROUNDS = ["legendary_epic", "fix_18", "neu_8", "rare", "uncommon", "common"]
# flavor: (round, texture name, boost): the show versions with their big toppings (the tower's own had them taken off
# on 28.11.2026). Their maps were saved before build_meshy.py strengthened the colours, so `boost` does it here alike.
# The first royal_cream with its crown is in the scene MeshyScoops only, exported to meshy_scoops/show.
SHOW = {
    "tiramisu": ("legendary_epic", "tiramisu_beiwerk", True),
    "cinnamon_roll": ("legendary_epic", "cinnamon_roll_beiwerk", True),
    "mocha": ("legendary_epic", "mocha_beiwerk", True),
    "cheesecake": ("legendary_epic", "cheesecake_beiwerk", True),
    "crimson_velvet": ("legendary_epic", "crimson_velvet_beiwerk", True),
    "velvet_mocha": ("legendary_epic", "velvet_mocha_beiwerk", True),
    "royal_cream": ("show", "royal_cream_crown", True),
}
COLOR_SAT, COLOR_CONTRAST = 1.2, 1.08  # build_meshy.py's colour boost
OUT_DIR = os.path.join(HERE, "icons")

SIZE = 256  # pixels of an icon
FILL = 0.92  # the scoop's outline takes about this share of the picture
TURN = math.radians(-18)  # the scoop turned a little, so its front and one side show
ELEVATION = math.radians(24)  # the camera this far above the scoop's middle
LENS = 85  # a long lens: hardly any perspective, every scoop drawn alike


def flavors():
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if args:
        return args
    found = set()
    for name in ROUNDS:
        folder = os.path.join(FBX_ROOT, name)
        found |= {f[: -len("_LOD0.fbx")] for f in os.listdir(folder) if f.endswith("_LOD0.fbx")}
    return sorted(found)


def source(fid):
    """(fbx path, texture name, boost) of the flavor's icon model, or None."""
    if fid in SHOW:
        name, tex, boost = SHOW[fid]
        return os.path.join(FBX_ROOT, name, f"{fid}_LOD0.fbx"), tex, boost
    for name in reversed(ROUNDS):
        path = os.path.join(FBX_ROOT, name, f"{fid}_LOD0.fbx")
        if os.path.exists(path):
            return path, fid, False
    return None


def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.lights, bpy.data.cameras):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def setup_scene():
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    try:
        scene.eevee.taa_render_samples = 64
    except AttributeError:
        pass
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (1.0, 0.97, 0.95, 1.0)  # a soft, slightly warm fill from everywhere
    bg.inputs[1].default_value = 0.45
    return scene


def area_light(name, location, energy, size, color=(1, 1, 1)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.size = size
    data.color = color
    ob = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = location
    direction = Vector((0, 0, 0)) - Vector(location)
    ob.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return ob


def material(fid, tex, boost):
    mat = bpy.data.materials.new(f"Icon_{fid}")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")

    def texture(kind, non_color):
        path = os.path.join(TEX_DIR, f"{tex}_{kind}.png")
        if not os.path.exists(path):
            return None
        node = nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(path, check_existing=True)
        if non_color:
            node.image.colorspace_settings.name = "Non-Color"
        return node

    color = texture("color", False)
    if color and boost:
        import numpy as np

        im = color.image
        w, h = im.size
        px = np.array(im.pixels[:], np.float32).reshape(h, w, 4)
        rgb = px[..., :3]
        grey = (rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
        rgb = 0.5 + (grey + (rgb - grey) * COLOR_SAT - 0.5) * COLOR_CONTRAST
        px[..., :3] = np.clip(rgb, 0, 1)
        boosted = bpy.data.images.new(f"{tex}_boosted", w, h, alpha=True)
        boosted.pixels[:] = px.ravel()
        color.image = boosted
    if color:
        links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
    rough = texture("rough", True)
    if rough:
        links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    normal = texture("normal", True)
    if normal:
        node = nodes.new("ShaderNodeNormalMap")
        links.new(normal.outputs["Color"], node.inputs["Color"])
        links.new(node.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def import_scoop(fid):
    path, tex, boost = source(fid)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path, axis_forward="-Z", axis_up="Y", global_scale=1.0)
    meshes = [ob for ob in set(bpy.data.objects) - before if ob.type == "MESH"]
    mat = material(fid, tex, boost)
    for ob in meshes:
        ob.data.materials.clear()
        ob.data.materials.append(mat)
        ob.rotation_euler.z += TURN
    bpy.context.view_layer.update()
    return meshes


def bounds(meshes):
    points = [ob.matrix_world @ Vector(c) for ob in meshes for c in ob.bound_box]
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high


def place_camera(meshes):
    low, high = bounds(meshes)
    centre = (low + high) / 2
    size = high - low
    radius = max(size.x, size.y, size.z) / 2 * 1.12  # about the scoop's outline seen at an angle
    data = bpy.data.cameras.new("IconCamera")
    data.lens = LENS
    cam = bpy.data.objects.new("IconCamera", data)
    bpy.context.scene.collection.objects.link(cam)
    # the bounding sphere fills FILL of the picture: same framing for every scoop, whatever its toppings
    half_fov = data.angle / 2
    distance = radius / (math.sin(half_fov) * FILL)
    direction = Vector((0, -math.cos(ELEVATION), math.sin(ELEVATION)))
    cam.location = centre + direction * distance
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def render(fid):
    clear_scene()
    meshes = import_scoop(fid)
    if not meshes:
        return False
    place_camera(meshes)
    # soft light: a big key from the front left above, a fill from the right, a rim from behind
    area_light("Key", (-4, -5, 6), 340, 6, (1.0, 0.97, 0.92))
    area_light("Fill", (5, -3, 2), 110, 6, (0.95, 0.97, 1.0))
    area_light("Rim", (0, 6, 5), 160, 4)
    scene = bpy.context.scene
    scene.render.filepath = os.path.join(OUT_DIR, f"{fid}.png")
    bpy.ops.render.render(write_still=True)
    return True


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    setup_scene()
    done, missing = [], []
    for fid in flavors():
        if not source(fid):
            missing.append(fid)
            continue
        if render(fid):
            done.append(fid)
            print("icon", fid)
    print(f"rendered {len(done)} icons to {OUT_DIR}")
    if missing:
        print("no model:", " ".join(missing))


main()
