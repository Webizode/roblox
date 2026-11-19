"""Preview renders of prototype 2 (build_proto.py), not part of the export. Run after build() in the same Blender:
    ASSET_DIR = r"<repo>/assets/TowerScoops"
    exec(open(ASSET_DIR + "/preview_proto.py").read())   # execs build_proto.py too
    preview_close("cherry"); preview_tower()

The baked LOD meshes with the game's maps, in the golden-hour light of preview_scoops.py. Each close-up sheet: LOD0
front, LOD0 back, LOD1, and the reference picture (the commons have none: the scoop as it is in the game now).
"""

import math
import os
import random

exec(open(os.path.join(ASSET_DIR, "build_proto.py")).read())

RENDERS = os.path.join(OUT, "renders")
REFS = {
    "cherry": "Pasted image 20261117210013.png",
    "cookies_cream": "Pasted image 20261117211226.png",
    "royal_cream": "Pasted image 20261118170202.png",
}
# the rollout (build_rollout.py): the vault's pictures, in Sorten-Katalog order (epic and legendary were pasted in the
# catalog's order, 18.11.2026); the commons have none
_PASTED = {
    "blueberry": "20261117210644", "raspberry": "20261117205542", "peach": "20261117205636", "grape": "20261117205719",
    "coconut": "20261117205815", "pineapple": "20261117210113", "orange": "20261117210211", "lime": "20261117210255",
    "caramel": "20261117210742", "blue_raspberry": "20261117211033", "cotton_candy": "20261117211138",
    "red_velvet": "20261118160634", "birthday_cake": "20261117211540", "brownie": "20261117211734",
    "coffee": "20261117212045", "dragon_fruit": "20261117212219", "pomegranate": "20261117212322",
    "honey": "20261117212421", "maple_syrup": "20261117212540",
    "tiramisu": "20261118162940", "white_chocolate": "20261118162943", "black_cherry": "20261118162947",
    "pistachio_cream": "20261118163408", "salted_caramel": "20261118163517", "marzipan": "20261118163609",
    "cinnamon_roll": "20261118163703", "cheesecake": "20261118163758", "mocha": "20261118163936",
    "passion_fruit": "20261118164133",
    "midnight_berry": "20261118170206", "frosted_melon": "20261118170209", "velvet_dream": "20261118170212",
    "mystic_plum": "20261118170216", "arctic_coconut": "20261118170220", "crimson_velvet": "20261118170224",
    "honey_blossom": "20261118170229", "velvet_mocha": "20261118170328", "sapphire_cream": "20261118170503",
}
REFS.update({fid: f"Pasted image {stamp}.png" for fid, stamp in _PASTED.items()})
VAULT = os.path.join(os.path.expanduser("~"), "Desktop", "claude gehirn", "Wobble Scoops")
OLD_RENDERS = os.path.join(ASSET_DIR, "renders")


def look_setup(sc):
    set_engine(sc, "BLENDER_EEVEE")
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.film_transparent = False
    try:
        sc.eevee.taa_render_samples = 64
    except AttributeError:
        pass
    world = bpy.data.worlds.get("P2_World") or bpy.data.worlds.new("P2_World")
    sc.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.75, 0.85, 1.0, 1)
    bg.inputs["Strength"].default_value = 0.45
    col = collection("P2_Stage")
    data = bpy.data.lights.get("P2_Sun") or bpy.data.lights.new("P2_Sun", "SUN")
    data.energy = 4.2
    data.color = (1.0, 0.88, 0.72)
    data.angle = math.radians(8)
    sun = bpy.data.objects.new("P2_Sun", data)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    col.objects.link(sun)
    bpy.ops.mesh.primitive_plane_add(size=400)
    ground = bpy.context.active_object
    for c in ground.users_collection:
        c.objects.unlink(ground)
    col.objects.link(ground)
    ground.name = "P2_Ground"
    ground.data.materials.append(material("P2_Deck", "#9E6B40", 0.8))
    ground.location.z = -0.86
    return col


def cam(col, location, target, fov=80, lens=None):
    data = bpy.data.cameras.new("P2_Cam")
    data.sensor_fit = "VERTICAL"
    if lens:
        data.lens = lens
    else:
        data.angle_y = math.radians(fov)
    data.clip_start = 0.05
    ob = bpy.data.objects.new("P2_Cam", data)
    col.objects.link(ob)
    ob.location = location
    ob.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = ob
    return ob


def render_to(path, w, h):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def placed(col, fid, lod, location, yaw=0.0, tilt=(0.0, 0.0), scale=1.0):
    src = bpy.data.objects[f"P2_{fid}_{lod}"]
    ob = bpy.data.objects.new(f"{src.name}_view", src.data)
    ob.location = location
    ob.rotation_euler = (tilt[0], tilt[1], yaw)
    ob.scale = (scale, scale, scale)
    col.objects.link(ob)
    return ob


def show_only(names):
    for c in bpy.context.scene.collection.children:
        c.hide_render = c.name not in names


def clear(col):
    for ob in list(col.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def load_pixels(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)


def resize(px, height):
    h, w = px.shape[:2]
    width = int(w * height / h)
    ys = (np.arange(height) * h / height).astype(int)
    xs = (np.arange(width) * w / width).astype(int)
    return px[ys][:, xs]


def save_pixels(px, path):
    h, w = px.shape[:2]
    img = bpy.data.images.new("P2_sheet", w, h, alpha=False)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def side_by_side(paths, out, height=720):
    tiles = [resize(load_pixels(p), height) for p in paths]
    gap = np.ones((height, 16, 4), dtype=np.float32)
    row = [tiles[0]]
    for t in tiles[1:]:
        row += [gap, t]
    save_pixels(np.concatenate(row, axis=1), out)
    return out


def preview_close(fid):
    os.makedirs(RENDERS, exist_ok=True)
    sc = scene()
    look_setup(sc)
    col = collection("P2_View")
    show_only({"P2_View", "P2_Stage"})
    shots = []
    for name, lod, yaw in (("front", "LOD0", 0), ("back", "LOD0", 180), ("LOD1", "LOD1", 0)):
        clear(col)
        placed(col, fid, lod, (0, 0, 0), yaw=math.radians(yaw))
        cam(col, (0, -4.8, 1.9), (0, 0, 0.3), lens=42)
        shots.append(render_to(os.path.join(RENDERS, f"{fid}_{name}.png"), 900, 900))
    ref = os.path.join(VAULT, REFS[fid]) if fid in REFS else os.path.join(OLD_RENDERS, f"{fid}_close.png")
    if os.path.exists(ref):
        shots.append(ref)
    return side_by_side(shots, os.path.join(RENDERS, f"{fid}_vergleich.png"))


def stack_pose(index, seed=7):
    """Stand-in for the game's tower pose (TowerVisual): random yaw, a slight tilt, a size of 0.95 to 1.05."""
    rng = random.Random(index * 7919 + seed)
    tilt = (math.radians(rng.uniform(-3, 3)), math.radians(rng.uniform(-3, 3)))
    return rng.uniform(0, 2 * math.pi), tilt, rng.uniform(0.95, 1.05)


def tower(col, order, lod="LOD0"):
    for i, fid in enumerate(order):
        yaw, tilt, scale = stack_pose(i + 1)
        placed(col, fid, lod, (0, 0, i * SPACING), yaw=yaw, tilt=tilt, scale=scale)
    cone = bpy.data.objects.get("P2_Cone")
    if not cone:
        bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=0.15, radius2=0.95, depth=2.4)
        cone = bpy.context.active_object
        for c in cone.users_collection:
            c.objects.unlink(cone)
        cone.name = "P2_Cone"
        cone.data.materials.append(material("P2_Waffle", "#D9A15B", 0.7, specks=("#A8702F", 12, 0.25)))
    view = bpy.data.objects.new("P2_Cone_view", cone.data)
    view.location = (0, 0, -1.45)
    col.objects.link(view)


TOWER_ORDER = ["vanilla", "cherry", "cookie", "royal_cream", "cookies_cream", "vanilla", "cherry", "cookie"]


def preview_tower():
    sc = scene()
    look_setup(sc)
    bpy.data.objects["P2_Ground"].location.z = -2.7
    col = collection("P2_View")
    show_only({"P2_View", "P2_Stage"})
    mid = (len(TOWER_ORDER) - 1) * SPACING / 2
    out = []
    tower(col, TOWER_ORDER, "LOD0")
    cam(col, (0, -9.0, mid + 1.0), (0, 0, mid), fov=80)
    out.append(render_to(os.path.join(RENDERS, "tower8_front.png"), 900, 1280))
    cam(col, (6.5, -6.5, mid + 2.0), (0, 0, mid), fov=80)
    out.append(render_to(os.path.join(RENDERS, "tower8_side.png"), 900, 1280))
    for lod in ("LOD0", "LOD1"):
        clear(col)
        tower(col, TOWER_ORDER, lod)
        cam(col, (0, -30, mid + 4), (0, 0, mid), fov=80)
        out.append(render_to(os.path.join(RENDERS, f"tower8_30studs_{lod}.png"), 1280, 720))
        cam(col, (0, -30, mid + 4), (0, 0, mid), fov=20)
        out.append(render_to(os.path.join(RENDERS, f"tower8_30studs_{lod}_zoom4x.png"), 900, 1280))
    return out
