"""Preview renders of a tower scoop (not part of the export): close up, from 30 studs and as a tower of 10.

Run after build_scoops.py in the same Blender:
    PREVIEW_FLAVOR = "vanilla"
    exec(open(ASSET_DIR + "/preview_scoops.py").read())

The camera uses the game's field of view (Config/Settings: 80 degrees vertical by default). Light: golden hour on
the pier, a warm sun and a sky fill. The outline is an inverted hull in the Big Swirl's outline colour, standing in
for the Highlight the game draws.
"""

import math
import os

import bpy
import numpy as np
from mathutils import Vector

FLAVOR = globals().get("PREVIEW_FLAVOR", "vanilla")
OUT = os.path.join(ASSET_DIR, "renders")
os.makedirs(OUT, exist_ok=True)
scene = bpy.context.scene

PREVIEW = "TowerScoop_Preview"


def preview_collection():
    col = bpy.data.collections.get(PREVIEW)
    if col:
        for ob in list(col.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
    else:
        col = bpy.data.collections.new(PREVIEW)
        scene.collection.children.link(col)
    return col


def setup_look():
    try:
        scene.render.engine = "BLENDER_EEVEE"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.film_transparent = False
    scene.eevee.taa_render_samples = 64
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.75, 0.85, 1.0, 1)
    bg.inputs["Strength"].default_value = 0.35
    for ob in list(scene.objects):
        if ob.type == "LIGHT" and ob.name != "TS_Sun":
            ob.hide_render = True
            ob.hide_viewport = True


def add(col, ob):
    col.objects.link(ob)
    return ob


def sun(col):
    data = bpy.data.lights.get("TS_Sun") or bpy.data.lights.new("TS_Sun", "SUN")
    data.energy = 4.5
    data.color = (1.0, 0.86, 0.68)
    data.angle = math.radians(8)
    ob = add(col, bpy.data.objects.new("TS_Sun", data))
    ob.rotation_euler = (math.radians(50), 0, math.radians(-35))


def ground(col):
    bpy.ops.mesh.primitive_plane_add(size=400)
    ob = bpy.context.active_object
    for c in ob.users_collection:
        c.objects.unlink(ob)
    col.objects.link(ob)
    ob.name = "TS_Ground"
    m = bpy.data.materials.get("TS_Deck") or bpy.data.materials.new("TS_Deck")
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (0.62, 0.42, 0.25, 1)  # pier planks, plain
    b.inputs["Roughness"].default_value = 0.8
    ob.data.materials.append(m)
    return ob


def scoop_copy(col, source, location, outline=True, rotation=0.0):
    ob = add(col, bpy.data.objects.new(source.name + "_view", source.data.copy()))
    ob.location = location
    ob.rotation_euler = (0, 0, rotation)
    if outline:
        add_outline(ob)
    return ob


def camera(col, location, target, lens_fov=80):
    data = bpy.data.cameras.new("TS_Cam")
    data.sensor_fit = "VERTICAL"
    data.angle_y = math.radians(lens_fov)
    data.clip_start = 0.05
    ob = add(col, bpy.data.objects.new("TS_Cam", data))
    ob.location = location
    direction = Vector(target) - Vector(location)
    ob.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = ob
    return ob


def render(name, w=1280, h=720):
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.resolution_percentage = 100
    scene.render.filepath = os.path.join(OUT, f"{FLAVOR}_{name}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", scene.render.filepath)


def hide_sources(hidden=True):
    for flavor_id in BUILT:
        for ob in bpy.data.collections[f"TowerScoop_{flavor_id}"].objects:
            ob.hide_render = hidden
            ob.hide_viewport = hidden


setup_look()
hide_sources(True)
lods = BUILT[FLAVOR]
ROOM = 1.0  # the deck sits this far below the lowest scoop's centre in the previews


def shot_close():
    col = preview_collection()
    sun(col)
    ground(col).location = (0, 0, -ROOM)
    # near (LOD0) from the front-side, and a second one turned over, to show the hollow underside
    scoop_copy(col, lods["LOD0"], (0, 0, 0))
    flipped = scoop_copy(col, lods["LOD0"], (2.6, 1.0, 0.25))
    flipped.rotation_euler = (math.radians(-115), 0, math.radians(-20))  # the hollow underside towards the camera
    far = scoop_copy(col, lods["LOD1"], (-2.6, 1.0, 0))
    far.name = "LOD1_view"
    camera(col, (0.6, -5.2, 1.6), (0.2, 0.4, 0.0), lens_fov=40)
    render("close")


def shot_far():
    col = preview_collection()
    sun(col)
    ground(col).location = (0, 0, -ROOM)
    # at 30 studs the game would show LOD1; LOD0 next to it for comparison (left LOD0, right LOD1)
    scoop_copy(col, lods["LOD0"], (-1.6, 0, 0))
    scoop_copy(col, lods["LOD1"], (1.6, 0, 0))
    camera(col, (0, -30 * math.cos(math.radians(12)), 30 * math.sin(math.radians(12))), (0, 0, 0))
    render("30studs")
    # the middle of the same picture at its real pixels, blown up 4x without smoothing, to judge what is readable
    r = scene.render
    r.use_border, r.use_crop_to_border = True, True
    r.border_min_x, r.border_max_x, r.border_min_y, r.border_max_y = 0.4375, 0.5625, 0.4375, 0.5625
    render("30studs_crop")
    r.use_border = r.use_crop_to_border = False
    img = bpy.data.images.load(os.path.join(OUT, f"{FLAVOR}_30studs_crop.png"), check_existing=False)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    big = px.repeat(4, axis=0).repeat(4, axis=1)
    out = bpy.data.images.new("TS_zoom", w * 4, h * 4, alpha=True)
    out.pixels.foreach_set(big.ravel())
    out.filepath_raw = os.path.join(OUT, f"{FLAVOR}_30studs_zoom4x.png")
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(img)
    bpy.data.images.remove(out)
    os.remove(os.path.join(OUT, f"{FLAVOR}_30studs_crop.png"))


def shot_tower(count=10):
    col = preview_collection()
    sun(col)
    ground(col).location = (0, 0, -ROOM - 1.4)
    # a plain waffle cone stand-in under the stack (the real one is the backpack waffle)
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.95, radius2=0.12, depth=1.8, location=(0, 0, -1.45))
    cone = bpy.context.active_object
    cone.rotation_euler = (math.pi, 0, 0)
    for c in cone.users_collection:
        c.objects.unlink(cone)
    col.objects.link(cone)
    m = bpy.data.materials.get("TS_Waffle") or bpy.data.materials.new("TS_Waffle")
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = srgb("#E2AE62") + [1.0]
    cone.data.materials.append(m)
    for i in range(count):
        scoop_copy(col, lods["LOD0"], (0, 0, i * SPACING), rotation=math.radians(i * 37))
    top = (count - 1) * SPACING
    camera(col, (4.5, -13.0, top * 0.55 + 1.5), (0, 0, top * 0.45), lens_fov=80)
    render("tower10", 720, 1080)


def shot_compare(names):
    """Close-up meshes side by side, same light and camera: two views of each (from the side, from above as in the
    game, where the camera looks down on the tower)."""
    col = preview_collection()
    sun(col)
    ground(col).location = (0, 0, -ROOM)
    for i, name in enumerate(names):
        x = (i - (len(names) - 1) / 2) * 2.6
        scoop_copy(col, bpy.data.objects[name], (x, 0, 0))
        scoop_copy(col, bpy.data.objects[name], (x, 3.2, 0), rotation=math.radians(25))
    camera(col, (0, -5.6, 3.2), (0, 1.2, -0.1), lens_fov=48)
    render("compare", 1280, 960)


def shot_mix(flavor_ids, count=10):
    """Several flavors: one of each in a row close up (LOD0), and a tower of `count` going through them."""
    col = preview_collection()
    sun(col)
    ground(col).location = (0, 0, -ROOM - 1.4)
    for i, flavor_id in enumerate(flavor_ids):
        x = (i - (len(flavor_ids) - 1) / 2) * 2.5
        scoop_copy(col, BUILT[flavor_id]["LOD0"], (x, -3.5, -1.4), rotation=math.radians(-20 + 15 * i))
    for i in range(count):
        flavor_id = flavor_ids[i % len(flavor_ids)]
        scoop_copy(col, BUILT[flavor_id]["LOD0"], (0, 2.5, i * SPACING - 0.6), rotation=math.radians(i * 37))
    camera(col, (2.5, -13.5, 6.0), (0, 0.5, 4.2), lens_fov=60)
    render("mix", 1080, 1080)


SHOTS = {"close": shot_close, "far": shot_far, "tower": shot_tower}
for shot in globals().get("PREVIEW_SHOTS", ["close", "far", "tower"]):
    if isinstance(shot, str):
        SHOTS[shot]()
    elif shot and shot[0] == "mix":
        shot_mix(shot[1])
    else:
        shot_compare(shot)
hide_sources(False)
