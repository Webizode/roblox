"""The hub kit: the decoration of the hub ring (trees, bushes, rocks, lanterns, planters, benches, picnic table, bins,
signpost, fountain, barrels and crates, the locked harbour gate), built from the arena kit's blocks and palette
(assets/ArenaKit/arenakit.py) like the plot kit, so hub, plots and arena read as one world: glossy candy, rounded
edges, few triangles, colour as the variant, no textures. Derived from assets/PlotKit/plotkit.py (same figure, preview
and export), with collections HK_<Model> and FBX HubKit_<Model>.fbx in assets/HubKit/fbx.

Run through run_hubkit.py (background Blender):
    blender -b --factory-startup --python assets/HubKit/run_hubkit.py -- IceTree Lantern

1 Blender unit = 1 stud, Z up (the FBX export turns it into Roblox's Y up), front -Y, length along X. Origin at the
bottom centre (0, 0, 0), the Roblox model's pivot. Parts that Studio treats on their own carry the custom property
part (Crown, Body, Frame, Panel: recoloured per variant; Arrow1..3: text faces) and export as <Model>_<Part>_<Colour>.
"""

import json
import math
import os

import bmesh
import bpy
from mathutils import Vector

HUB_DIR = globals().get("HUB_DIR") or os.path.dirname(os.path.abspath(bpy.data.filepath))
KIT_DIR = os.path.join(os.path.dirname(HUB_DIR), "ArenaKit")
ASSET_DIR = KIT_DIR
exec(open(os.path.join(KIT_DIR, "arenakit.py"), encoding="utf-8").read(), globals())

# colours beyond the arena kit (hub kit, 06.11.2026), each one material WS_<name> and one Roblox colour:
#   Glass, Stone  as in the plot kit (Stone: the rose paving tiles under lanterns, bins, planters, fountain)
#   Leaf, LeafDark  the glossy greens of bushes, leaves, moss and grass (references Blumenbusch, Felsformation)
#   Rock          the lavender grey of the rocks
#   Choco         the chocolate tree variant, the bin's opening, the padlock's keyhole
#   Wood          warm planks (bench, picnic table, barrels, crates, gate); Waffle stays the waffle
#   Lamp          the lantern glass: glows in the preview, Neon with a PointLight in Studio
#   Water         the fountain water: see-through in the preview, Transparency WATER_TRANSPARENCY in Studio
#   Caramel       the bridge posts and side beams (07.11.2026), the colour of the walkway curbs
PALETTE["Glass"] = PALETTE["SkyBlue"]
GAME_COLOURS["Glass"] = GAME_COLOURS["SkyBlue"]
PALETTE["Stone"] = "#E2A4B4"
GAME_COLOURS["Stone"] = "#E2A4B4"
for _name, _hex in {
    "Leaf": "#86C94B",
    "LeafDark": "#55A13C",
    "Rock": "#A99CC0",
    "Choco": "#7A4528",
    "Wood": "#C9783C",
    "Lamp": "#FFD66E",
    "Water": "#86DDF7",
    "Caramel": "#C98A4F",  # bridge posts and side beams, as the walkway curbs and the hub fence caps
}.items():
    PALETTE[_name] = _hex
    GAME_COLOURS[_name] = _hex


def _blend(m, alpha):
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Alpha"].default_value = alpha
    for attr, value in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
        if hasattr(m, attr):
            try:
                setattr(m, attr, value)
            except TypeError:
                pass
    return bsdf


def special_materials():
    """Glass and Water see-through, Lamp glowing (preview only; Studio sets them in the template script)."""
    if "WS_Water" in bpy.data.materials:
        _blend(material("Water"), 0.5).inputs["Roughness"].default_value = 0.05
    if "WS_Glass" in bpy.data.materials:
        _blend(material("Glass"), 0.28)
    if "WS_Lamp" in bpy.data.materials:
        bsdf = next(n for n in material("Lamp").node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        for key, value in (("Emission Color", srgb_to_linear(PALETTE["Lamp"])), ("Emission Strength", 4.0)):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = value


OUT_DIR = os.path.join(HUB_DIR, "fbx")
PREVIEW_DIR = os.path.join(HUB_DIR, "previews")
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(PREVIEW_DIR, exist_ok=True)

# R15 at default scale: legs 2, torso 2, head 1.2 high; the root (HumanoidRootPart) at 3. The tower stands in the
# waffle backpack on the back; one scoop every 1.5 studs (Config/Tower.scoopSpacing). A full starter cone holds 20
# (Config/Economy capacity level 0, 30 studs), the biggest 65: nothing may hang over the spot in front of a model
# where a player stands.
R15_HEIGHT = 5.2
TOWER_BACK = 1.5  # studs behind the root where the tower's axis rises
TOWER_BASE = 4.3
SCOOP_SPACING = 1.5


def hk_collection(name):
    """An empty collection HK_<name> for one model (rebuilt from scratch every run)."""
    col_name = "HK_" + name
    col = bpy.data.collections.get(col_name)
    if col:
        for ob in list(col.all_objects):
            bpy.data.objects.remove(ob, do_unlink=True)
    else:
        col = bpy.data.collections.new(col_name)
    if col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(col)
    return col


def preview_collection():
    col = bpy.data.collections.get("HK_Preview") or bpy.data.collections.new("HK_Preview")
    if col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(col)
    return col


def clear_preview():
    col = preview_collection()
    for ob in list(col.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    return col


def _flat_material(name, hex_colour, roughness=0.6):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = srgb_to_linear(hex_colour)
    bsdf.inputs["Roughness"].default_value = roughness
    m.diffuse_color = srgb_to_linear(hex_colour)
    return m


def _preview_box(col, name, mat, size, center):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    me.materials.append(mat)
    mod = ob.modifiers.new("Bevel", "BEVEL")
    mod.width = 0.12
    mod.segments = 2
    return ob


def figure(x, y, facing=1, scoops=20, name="Figure"):
    """An R15-sized blocky figure standing at (x, y) and looking along +Y (facing 1) or -Y (-1), with the waffle
    backpack and `scoops` tower scoops on its back. Preview only (collection HK_Preview, never exported)."""
    col = preview_collection()
    body = _flat_material("HK_Figure", "#7F8FB0")
    skin = _flat_material("HK_FigureSkin", "#F3CFA2")
    legs = _flat_material("HK_FigureLegs", "#4E5D7E")
    _preview_box(col, name + "_LegL", legs, (0.95, 0.95, 2.0), (x - 0.5, y, 1.0))
    _preview_box(col, name + "_LegR", legs, (0.95, 0.95, 2.0), (x + 0.5, y, 1.0))
    _preview_box(col, name + "_Torso", body, (2.0, 1.0, 2.0), (x, y, 3.0))
    _preview_box(col, name + "_ArmL", skin, (0.95, 0.95, 2.0), (x - 1.5, y, 3.0))
    _preview_box(col, name + "_ArmR", skin, (0.95, 0.95, 2.0), (x + 1.5, y, 3.0))
    _preview_box(col, name + "_Head", skin, (1.2, 1.2, 1.2), (x, y, 4.6))
    # the backpack waffle and the tower behind the figure
    back = y - facing * TOWER_BACK
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.15, radius2=0.85, depth=2.0)
    bmesh.ops.translate(bm, vec=Vector((x, back, TOWER_BASE - 1.0)), verts=bm.verts)
    me = bpy.data.meshes.new(name + "_Backpack")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name + "_Backpack", me)
    col.objects.link(ob)
    me.materials.append(material("Waffle"))
    colours = ("Pink", "Cream", "SkyBlue", "Gold")
    for i in range(scoops):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=0.72)
        bmesh.ops.scale(bm, vec=Vector((1, 1, 0.85)), verts=bm.verts)
        bmesh.ops.translate(bm, vec=Vector((x, back, TOWER_BASE + 0.5 + i * SCOOP_SPACING)), verts=bm.verts)
        me = bpy.data.meshes.new(f"{name}_Scoop{i}")
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(f"{name}_Scoop{i}", me)
        col.objects.link(ob)
        me.materials.append(material(colours[i % len(colours)]))
        me.shade_smooth()
    return col


def ground(size=(40, 30), center=(0, 0), colour="#AEDB93", name="Ground"):
    """A grass-coloured floor under the preview (HK_Preview)."""
    col = preview_collection()
    mat = _flat_material("HK_Grass", colour, roughness=0.85)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
    bmesh.ops.scale(bm, vec=Vector((size[0], size[1], 1)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((center[0], center[1], -0.01)), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    me.materials.append(mat)
    return ob


def bounds(objects):
    """World bounding box (min, max) of the evaluated objects."""
    deps = bpy.context.evaluated_depsgraph_get()
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for ob in objects:
        if ob.type != "MESH":
            continue
        ev = ob.evaluated_get(deps)
        me = ev.to_mesh()
        for v in me.vertices:
            p = ev.matrix_world @ v.co
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
        ev.to_mesh_clear()
    return lo, hi


def model_stats(name):
    col = bpy.data.collections["HK_" + name]
    lo, hi = bounds(col.all_objects)
    return {
        "size": [round(hi.x - lo.x, 2), round(hi.y - lo.y, 2), round(hi.z - lo.z, 2)],
        "min": [round(v, 2) for v in lo],
        "max": [round(v, 2) for v in hi],
        "triangles": triangles(col),
    }


def _setup_render(width, height):
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    if scene.render.engine.startswith("BLENDER_EEVEE"):
        ee = scene.eevee
        if hasattr(ee, "taa_render_samples"):
            ee.taa_render_samples = 24
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    world = scene.world or bpy.data.worlds.new("HK_World")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = srgb_to_linear("#D8D0EE")
    bg.inputs["Strength"].default_value = 0.7
    sun = bpy.data.objects.get("HK_Sun")
    if not sun:
        light = bpy.data.lights.new("HK_Sun", "SUN")
        sun = bpy.data.objects.new("HK_Sun", light)
        scene.collection.objects.link(sun)
    sun.data.energy = 3.6
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))


def _camera():
    cam = bpy.data.objects.get("HK_Camera")
    if not cam:
        cam = bpy.data.objects.new("HK_Camera", bpy.data.cameras.new("HK_Camera"))
        bpy.context.scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.clip_end = 2000
    bpy.context.scene.camera = cam
    return cam


VIEWS = {
    "front": Vector((0, -1, 0.12)),
    "three_quarter": Vector((-0.75, -1, 0.7)),
    "top": Vector((0, -0.02, 1)),
}


def _frame(cam, lo, hi, direction, aspect):
    centre = (lo + hi) / 2
    d = direction.normalized()
    cam.location = centre + d * 400
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    # the box's extent across the view
    right = d.cross(Vector((0, 0, 1)))
    if right.length < 1e-6:
        right = Vector((1, 0, 0))
    right.normalize()
    up = right.cross(d).normalized()
    corners = [Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    w = max(abs((c - centre).dot(right)) for c in corners) * 2
    h = max(abs((c - centre).dot(up)) for c in corners) * 2
    cam.data.ortho_scale = max(w, h * aspect) * 1.12


def render_preview(names, out_name, extra=(), views=("front", "three_quarter", "top"), size=(720, 560)):
    """Renders the collections HK_<name> for names, plus HK_Preview, from each view (orthographic, framed on the models,
    the figures and `extra` objects) and puts the pictures side by side into PREVIEW_DIR/<out_name>.png."""
    import numpy as np

    keep = {"HK_" + n for n in names} | {"HK_Preview"}
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = lc.name not in keep
    _setup_render(*size)
    cam = _camera()
    framed = [ob for n in names for ob in bpy.data.collections["HK_" + n].all_objects] + list(extra)
    lo, hi = bounds(framed)
    aspect = size[0] / size[1]
    strips = []
    for view in views:
        _frame(cam, lo, hi, VIEWS[view] if isinstance(view, str) else Vector(view), aspect)
        path = os.path.join(PREVIEW_DIR, f"_{out_name}_{view}.png")
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(path, check_existing=False)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(size[1], size[0], 4)
        strips.append(px)
        bpy.data.images.remove(img)
        os.remove(path)
    gap = np.ones((size[1], 8, 4), dtype=np.float32)
    joined = strips[0]
    for s in strips[1:]:
        joined = np.concatenate([joined, gap, s], axis=1)
    out = bpy.data.images.new(out_name, joined.shape[1], joined.shape[0], alpha=False)
    out.pixels.foreach_set(joined.ravel())
    out.filepath_raw = os.path.join(PREVIEW_DIR, out_name + ".png")
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = False
    print("preview", os.path.join(PREVIEW_DIR, out_name + ".png"))
    return os.path.join(PREVIEW_DIR, out_name + ".png")


def render_eye(names, out_name, eye, target, lens=24, size=(1600, 900)):
    """One perspective picture of HK_<names> and HK_Preview from `eye` towards `target` (a player's view), into
    PREVIEW_DIR/<out_name>.png."""
    keep = {"HK_" + n for n in names} | {"HK_Preview"}
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = lc.name not in keep
    _setup_render(*size)
    cam = _camera()
    cam.data.type = "PERSP"
    cam.data.lens = lens
    cam.location = Vector(eye)
    cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
    path = os.path.join(PREVIEW_DIR, out_name + ".png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    cam.data.type = "ORTHO"
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = False
    print("preview", path)
    return path


FBX = dict(
    use_selection=True,
    object_types={"MESH"},
    global_scale=1.0,
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_UNITS",
    axis_forward="-Z",
    axis_up="Y",
    use_mesh_modifiers=True,
    mesh_smooth_type="FACE",
    path_mode="AUTO",
    embed_textures=False,
    bake_anim=False,
)


def export_model(model):
    """HubKit_<model>.fbx in OUT_DIR: one mesh per colour (<Model>_<Colour>), moving parts on their own
    (<Model>_Lid_<Colour>). Origin at the bottom centre. The .blend is left as it was."""
    scene = bpy.context.scene
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = False
    source = bpy.data.collections["HK_" + model]
    tmp = bpy.data.collections.new("HK_Export")
    scene.collection.children.link(tmp)
    deps = bpy.context.evaluated_depsgraph_get()
    groups = {}
    for ob in source.all_objects:
        if ob.type == "MESH" and ob.data.materials:
            colour = ob.data.materials[0].name.removeprefix("WS_")
            part = ob.get("part")
            key = f"{model}_{part}_{colour}" if part else f"{model}_{colour}"
            me = bpy.data.meshes.new_from_object(ob.evaluated_get(deps), preserve_all_data_layers=True, depsgraph=deps)
            me.transform(ob.matrix_world)
            copy = bpy.data.objects.new(ob.name + "_x", me)
            tmp.objects.link(copy)
            groups.setdefault(key, []).append(copy)
    parts = []
    for key, objects in sorted(groups.items()):
        bpy.ops.object.select_all(action="DESELECT")
        for o in objects:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        if len(objects) > 1:
            bpy.ops.object.join()
        merged = bpy.context.view_layer.objects.active
        merged.name = merged.data.name = key
        parts.append(merged)
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    path = os.path.join(OUT_DIR, f"HubKit_{model}.fbx")
    bpy.ops.export_scene.fbx(filepath=path, **FBX)
    tris = 0
    for p in parts:
        p.data.calc_loop_triangles()
        tris += len(p.data.loop_triangles)
    names = [p.name for p in parts]
    for ob in list(tmp.objects):
        me = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.meshes.remove(me)
    bpy.data.collections.remove(tmp)
    print(f"{path}: {len(names)} meshes ({', '.join(names)}), {tris} triangles")
    return path, names, tris


def write_report(name, data):
    """Keeps what README and the Studio template script need per model in HUB_DIR/hubkit_models.json."""
    path = os.path.join(HUB_DIR, "hubkit_models.json")
    report = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            report = json.load(f)
    report[name] = data
    with open(path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, ensure_ascii=False, sort_keys=True)
