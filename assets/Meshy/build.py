"""The Meshy models (assets/Meshy/source/*.glb, 1.8 to 2.4 million triangles each) made game-ready:
reduced to a triangle budget, new UVs, colour and normal map baked from the original, pivot at the bottom centre,
front towards -Y (Roblox -Z after the import), scaled to fit the footprint of the building they replace.
The Scoop Chest's lid is cut off as its own mesh and shut (its hinge is written to the JSON), and the six cups' tops
are measured for the equipped scoops' attachments.

Run headless (all models, or the ones named):
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup ^
        --python assets/Meshy/build.py -- [ScoopChest UpgradeShop ...]

Writes assets/Meshy/export/<Name>.glb (meshes with embedded maps, 1 Blender unit = 1 stud), <Name>.json (size,
triangles, collision box, chest hinge and cups) and the maps as PNG next to them.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "source")
OUT = os.path.join(HERE, "export")
# "keep": bake onto the original's UVs carried through the decimation; "smart": new UVs by Smart UV Project (on a mesh
# this reduced it falls into thousands of islands a few pixels big: seams and blur, 27.11.2026)
UV_MODE = os.environ.get("MESHY_UV", "keep")

# footprint: the replaced building's width (X) and depth (Y) in studs; the model is scaled evenly to fit inside both.
# tris: the budget of each piece. tex: the baked maps' size. collide: the collision box's height as a share of the
# model's height (the box covers the footprint of everything below that height)
MODELS = {
    "ScoopChest": {"footprint": (14.0, 8.8), "tris": {"Body": 4200, "Lid": 1600}, "tex": 1024, "collide": 0.5},
    "SellCart": {"footprint": (19.5, 10.5), "tris": {"Body": 10000}, "tex": 1024, "collide": 0.45},
    "CraftingStation": {"footprint": (36.0, 12.0), "tris": {"Body": 12000}, "tex": 1024, "collide": 0.42},
    "UpgradeShop": {"footprint": (25.0, 18.9), "tris": {"Body": 14000}, "tex": 2048, "collide": 0.75},
    "CosmeticShop": {"footprint": (25.3, 18.9), "tris": {"Body": 14000}, "tex": 2048, "collide": 0.75},
    # v2 only (build_v2.py; there is no Meshy source for build.py): the Shop Kit's QuestHub, 25.0 x 18.9 footprint
    "QuestHub": {"footprint": (25.0, 18.9), "tris": {"Body": 14000}, "tex": 2048, "collide": 0.75},
}

# The chest's lid in the source's own coordinates (metres, centred; measured from a side view, 27.11.2026): the hinge
# runs along X at the lid's back bottom corner, y +0.21, z -0.09 (the bolt further up holds a stay, not the lid); the
# lid is everything above the box's rim (z > 0) that is not one of the cups
# (in front of y 0.02 and below z 0.08; six of them, their middles at `x`, from a front view).
CHEST = {
    "hinge": (0.21, -0.09),
    "rim": 0.0,
    # the lid stands this far open in the model (its far edge 50 degrees above the front, side view): turned back by
    # this about the hinge it lies shut
    "shut": 53,
    "cups": {"y": (-0.27, 0.02), "z": (-0.16, 0.08), "x": (-0.61, -0.364, -0.12, 0.13, 0.38, 0.62)},
}


def log(*args):
    print("[meshy]", *args, flush=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_source(name):
    bpy.ops.import_scene.gltf(filepath=os.path.join(SOURCE, name + ".glb"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    high = bpy.context.view_layer.objects.active
    # bake the import's transform into the vertices (the glTF importer adds a Y-up to Z-up turn on the object)
    high.data.transform(high.matrix_world)
    high.matrix_world = Matrix.Identity(4)
    high.name = name + "_High"
    return high


def bounds(obs):
    pts = [o.matrix_world @ v.co for o in obs for v in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def split_lid(high):
    """Cuts the chest's lid off the high mesh (faces whose middle is above the rim and not a cup)."""
    hy, hz = CHEST["hinge"]
    cy, cz = CHEST["cups"]["y"], CHEST["cups"]["z"]
    bm = bmesh.new()
    bm.from_mesh(high.data)
    lid_faces = []
    for f in bm.faces:
        c = f.calc_center_median()
        if c.z <= CHEST["rim"]:
            continue
        if cy[0] <= c.y <= cy[1] and cz[0] <= c.z <= cz[1]:
            continue
        lid_faces.append(f)
    for f in bm.faces:
        f.select = False
    for f in lid_faces:
        f.select = True
    bm.to_mesh(high.data)
    bm.free()
    bpy.context.view_layer.objects.active = high
    high.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    lid = next(o for o in bpy.context.selected_objects if o is not high)
    lid.name = "ScoopChest_HighLid"
    log("lid faces", len(lid_faces))
    return lid




def cups(high):
    """The six cups' top centres (source coordinates): vertices in the cups' band, grouped by x."""
    cy, cz = CHEST["cups"]["y"], CHEST["cups"]["z"]
    pts = [v.co.copy() for v in high.data.vertices if cy[0] <= v.co.y <= cy[1] and cz[0] <= v.co.z <= cz[1]]
    groups = [[p for p in pts if abs(p.x - x) < 0.09] for x in CHEST["cups"]["x"]]
    found = []
    for g in groups:
        top = max(p.z for p in g)
        crown = [p for p in g if p.z > top - 0.04]
        found.append(
            Vector((sum(p.x for p in crown) / len(crown), sum(p.y for p in crown) / len(crown), top))
        )
    log("cups found", len(found), [tuple(round(c, 3) for c in f) for f in found])
    return found


def decimate(high, tris, name):
    low = high.copy()
    low.data = high.data.copy()
    low.name = name
    bpy.context.scene.collection.objects.link(low)
    count = sum(len(p.vertices) - 2 for p in low.data.polygons)
    mod = low.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = min(1.0, tris / max(1, count))
    mod.use_collapse_triangulate = True
    for o in bpy.context.scene.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = low
    low.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    low.data.materials.clear()
    if UV_MODE == "keep":
        # the original's UVs (Meshy's atlas, large connected charts), carried through the decimation
        for layer in list(low.data.uv_layers)[1:]:
            low.data.uv_layers.remove(layer)
        low.data.uv_layers[0].name = "UVMap"
    else:
        for layer in list(low.data.uv_layers):
            low.data.uv_layers.remove(layer)
        low.data.uv_layers.new(name="UVMap")
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0)
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_smooth()
    log(name, "triangles", sum(len(p.vertices) - 2 for p in low.data.polygons))
    return low


def bake(high, low, size, stem, extrusion):
    """Bakes the high mesh's colour and normals onto `low`'s UVs; gives `low` a material with both maps."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = extrusion
    scene.render.bake.max_ray_distance = extrusion * 6
    scene.render.bake.margin = 8

    mat = bpy.data.materials.new(low.name + "_Mat")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.55
    low.data.materials.append(mat)

    def image(kind, non_color):
        img = bpy.data.images.new(f"{stem}_{kind}", size, size, alpha=False)
        if non_color:
            img.colorspace_settings.name = "Non-Color"
        node = nodes.new("ShaderNodeTexImage")
        node.image = img
        return img, node

    for o in bpy.context.scene.objects:
        o.select_set(False)
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low

    color, color_node = image("color", False)
    nodes.active = color_node
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    bpy.ops.object.bake(type="DIFFUSE")
    color.filepath_raw = os.path.join(OUT, f"{stem}_color.png")
    color.file_format = "PNG"
    color.save()

    normal, normal_node = image("normal", True)
    nodes.active = normal_node
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
    normal.filepath_raw = os.path.join(OUT, f"{stem}_normal.png")
    normal.file_format = "PNG"
    normal.save()

    rough, rough_node = image("rough", True)
    nodes.active = rough_node
    bpy.ops.object.bake(type="ROUGHNESS")
    rough.filepath_raw = os.path.join(OUT, f"{stem}_rough.png")
    rough.file_format = "PNG"
    rough.save()

    # metalness has no bake pass: the high mesh's metallic input shows as emission for one EMIT bake (the gold)
    metal, metal_node = image("metal", True)
    nodes.active = metal_node
    restore = []
    for slot in high.material_slots:
        hm = slot.material
        if not hm or not hm.use_nodes:
            continue
        hn, hl = hm.node_tree.nodes, hm.node_tree.links
        hb = next(n for n in hn if n.type == "BSDF_PRINCIPLED")
        out = next(n for n in hn if n.type == "OUTPUT_MATERIAL")
        emit = hn.new("ShaderNodeEmission")
        src = hb.inputs["Metallic"]
        if src.is_linked:
            hl.new(src.links[0].from_socket, emit.inputs["Color"])
        else:
            v = src.default_value
            emit.inputs["Color"].default_value = (v, v, v, 1)
        old = out.inputs["Surface"].links[0].from_socket
        hl.new(emit.outputs["Emission"], out.inputs["Surface"])
        restore.append((hl, old, out, emit, hn))
    bpy.ops.object.bake(type="EMIT")
    for hl, old, out, emit, hn in restore:
        hl.new(old, out.inputs["Surface"])
        hn.remove(emit)
    metal.filepath_raw = os.path.join(OUT, f"{stem}_metal.png")
    metal.file_format = "PNG"
    metal.save()

    links.new(color_node.outputs["Color"], bsdf.inputs["Base Color"])
    nmap = nodes.new("ShaderNodeNormalMap")
    links.new(normal_node.outputs["Color"], nmap.inputs["Color"])
    links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    log(stem, "baked", size)


def build(name):
    cfg = MODELS[name]
    reset()
    os.makedirs(OUT, exist_ok=True)
    high = import_source(name)
    info = {"name": name}

    highs = {"Body": high}
    chest = name == "ScoopChest"
    if chest:
        cup_tops = cups(high)
        highs["Lid"] = split_lid(high)
        angle = CHEST["shut"]
        log("lid shut by", angle, "degrees")
        hy, hz = CHEST["hinge"]
        turn = Matrix.Translation((0, hy, hz)) @ Matrix.Rotation(math.radians(angle), 4, "X") @ Matrix.Translation(
            (0, -hy, -hz)
        )
        highs["Lid"].data.transform(turn)
        info["lidShutDegrees"] = angle

    # scale and place: bottom centre at the origin, evenly scaled to fit the footprint
    lo, hi = bounds(list(highs.values()))
    size = hi - lo
    scale = min(cfg["footprint"][0] / size.x, cfg["footprint"][1] / size.y)
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    place = Matrix.Scale(scale, 4) @ Matrix.Translation(-centre)
    for o in highs.values():
        o.data.transform(place)
    info["scale"] = scale
    info["size"] = [size.x * scale, size.y * scale, size.z * scale]
    log(name, "size in studs", [round(v, 2) for v in info["size"]])

    if chest:
        hy, hz = CHEST["hinge"]
        hinge = place @ Vector((0, hy, hz))
        info["hinge"] = [0.0, hinge.y, hinge.z]
        info["cups"] = [list(place @ c) for c in cup_tops]

    lows = []
    for piece, target in cfg["tris"].items():
        low = decimate(highs[piece], target, f"{name}_{piece}")
        bake(highs[piece], low, cfg["tex"], f"{name}_{piece}", extrusion=0.03 * max(info["size"]))
        lows.append(low)
    info["triangles"] = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in lows}

    # the collision box: the footprint of everything below `collide` of the height
    cut = info["size"][2] * cfg["collide"]
    pts = [v.co for o in lows for v in o.data.vertices if v.co.z <= cut]
    info["collision"] = {
        "min": [min(p.x for p in pts), min(p.y for p in pts), 0.0],
        "max": [max(p.x for p in pts), max(p.y for p in pts), cut],
    }

    for o in list(bpy.context.scene.objects):
        if o not in lows:
            bpy.data.objects.remove(o, do_unlink=True)
    for o in bpy.context.scene.objects:
        o.select_set(o in lows)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_image_format="JPEG",
        export_jpeg_quality=92,
        export_cameras=False,
        export_lights=False,
    )
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(info, f, indent=1)
    blend = os.path.join(OUT, name + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    log(name, "exported", path, round(os.path.getsize(path) / 1e6, 2), "MB")


if __name__ == "__main__":
    names = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    for model in names or list(MODELS):
        build(model)
