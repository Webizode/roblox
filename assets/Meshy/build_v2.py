"""v2 of the Meshy models: Meshy's own remesh (made in the Meshy web app) taken as it is. Nothing is reduced and nothing
is baked: the remesh's mesh, UVs, colour and normal map stay Meshy's. Only:
- the chest's lid is cut off and shut (same cut, hinge and angle as build.py; the remesh lies in the source's frame),
- every piece stays under Roblox's triangle limit per MeshPart (the body is cut in X slices if needed),
- no metalness (0), one even, high roughness (ROUGHNESS) for a creamy matte look,
- pivot at the bottom middle, front to -Y, scaled to the same footprint as build.py.

Run headless:
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup ^
        --python assets/Meshy/build_v2.py -- ScoopChest

Writes export/<Name>_v2.glb (maps embedded unchanged), <Name>_v2.json, <Name>_v2_color.png / _normal.png (Meshy's own
files, byte for byte), <Name>_v2_rough.png (flat) and <Name>_v2.blend.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build import CHEST, MODELS, bounds, cups, log, reset, split_lid  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "export")
REMESH = {
    "ScoopChest": r"C:\Users\Wobble\Desktop\meshy modelle\Meshy_AI_Enchanted_Ice_Cream_Chest_20261127_texture_remesh_tri.glb",
    "SellCart": r"C:\Users\Wobble\Desktop\meshy modelle\Meshy_AI_Sprinkle_Sundae_Cart_20261127_texture_remesh_tri.glb",
    "CraftingStation": r"C:\Users\Wobble\Desktop\meshy modelle\Meshy_AI_Sweet_Spell_Workshop_20261127_texture_remesh_tri.glb",
    "UpgradeShop": r"C:\Users\Wobble\Desktop\meshy modelle\Meshy_AI_Sweet_Upgrade_Shop_20261127_texture_remesh_tri.glb",
    "CosmeticShop": r"C:\Users\Wobble\Desktop\meshy modelle\Meshy_AI_Sugar_Scoop_Boutique_20261127_texture_remesh_tri.glb",
    "QuestHub": r"C:\Users\Wobble\Desktop\meshy modelle\Meshy_AI_Sundae_Scrolls_Kiosk_20261127_texture_remesh_tri.glb",
}
# Roblox: at most 20,000 triangles per MeshPart; a little room below it
LIMIT = 19500
ROUGHNESS = 0.8


def import_remesh(name):
    bpy.ops.import_scene.gltf(filepath=REMESH[name])
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in bpy.context.scene.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    obj.name = name + "_High"
    return obj


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def slice_x(obj, parts):
    """Cuts obj into `parts` pieces along X, each with about the same number of triangles (whole faces only)."""
    centres = sorted(p.center.x for p in obj.data.polygons)
    cuts = [centres[len(centres) * k // parts] for k in range(1, parts)]
    pieces = [obj]
    for cut in reversed(cuts):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        for f in bm.faces:
            f.select = f.calc_center_median().x >= cut
        bm.to_mesh(obj.data)
        bm.free()
        for o in bpy.context.scene.objects:
            o.select_set(o is obj)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        pieces.insert(1, next(o for o in bpy.context.selected_objects if o is not obj))
    return pieces


def matte_material(src_mat, stem):
    """Meshy's colour and normal images in a new material: metalness 0, flat roughness. Writes the images out."""
    nodes_src = src_mat.node_tree.nodes
    bsdf_src = next(n for n in nodes_src if n.type == "BSDF_PRINCIPLED")

    def source_image(socket):
        stack = [socket]
        while stack:
            s = stack.pop()
            for link in s.links:
                node = link.from_node
                if node.type == "TEX_IMAGE":
                    return node.image
                stack.extend(i for i in node.inputs if i.is_linked)
        return None

    color = source_image(bsdf_src.inputs["Base Color"])
    normal = source_image(bsdf_src.inputs["Normal"])
    files = {}
    for kind, img in (("color", color), ("normal", normal)):
        ext = ".jpg" if img.packed_file and img.packed_file.data[:2] == b"\xff\xd8" else ".png"
        path = os.path.join(OUT, f"{stem}_{kind}{ext}")
        with open(path, "wb") as f:
            f.write(img.packed_file.data)
        files[kind] = path
        log(kind, img.name, tuple(img.size), "->", os.path.basename(path))

    rough = bpy.data.images.new(f"{stem}_rough", 64, 64, alpha=False)
    rough.colorspace_settings.name = "Non-Color"
    rough.pixels.foreach_set([ROUGHNESS, ROUGHNESS, ROUGHNESS, 1.0] * (64 * 64))
    rough.filepath_raw = os.path.join(OUT, f"{stem}_rough.png")
    rough.file_format = "PNG"
    rough.save()
    files["rough"] = rough.filepath_raw

    mat = bpy.data.materials.new(stem)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = ROUGHNESS
    c = nodes.new("ShaderNodeTexImage")
    c.image = color
    links.new(c.outputs["Color"], bsdf.inputs["Base Color"])
    n = nodes.new("ShaderNodeTexImage")
    n.image = normal
    nmap = nodes.new("ShaderNodeNormalMap")
    links.new(n.outputs["Color"], nmap.inputs["Color"])
    links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat, files


def build(name):
    cfg = MODELS[name]
    reset()
    high = import_remesh(name)
    stem = name + "_v2"
    info = {"name": name, "source": os.path.basename(REMESH[name]), "sourceTriangles": tris(high)}
    mat, files = matte_material(high.data.materials[0], stem)
    info["maps"] = {k: os.path.basename(v) for k, v in files.items()}
    info["roughness"] = ROUGHNESS
    info["metalness"] = 0

    pieces = {"Body": high}
    chest = name == "ScoopChest"
    if chest:
        cup_tops = cups(high)
        pieces["Lid"] = split_lid(high)
        hy, hz = CHEST["hinge"]
        turn = (
            Matrix.Translation((0, hy, hz))
            @ Matrix.Rotation(math.radians(CHEST["shut"]), 4, "X")
            @ Matrix.Translation((0, -hy, -hz))
        )
        pieces["Lid"].data.transform(turn)
        info["lidShutDegrees"] = CHEST["shut"]

    lo, hi = bounds(list(pieces.values()))
    size = hi - lo
    scale = min(cfg["footprint"][0] / size.x, cfg["footprint"][1] / size.y)
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    place = Matrix.Scale(scale, 4) @ Matrix.Translation(-centre)
    for o in pieces.values():
        o.data.transform(place)
    info["scale"] = scale
    info["size"] = [size.x * scale, size.y * scale, size.z * scale]
    log(name, "size in studs", [round(v, 2) for v in info["size"]])
    if chest:
        hinge = place @ Vector((0, hy, hz))
        info["hinge"] = [0.0, hinge.y, hinge.z]
        info["cups"] = [list(place @ c) for c in cup_tops]

    # every piece under the limit: a piece over it is cut in X slices
    final = []
    for piece, obj in pieces.items():
        count = math.ceil(tris(obj) / LIMIT)
        parts = slice_x(obj, count) if count > 1 else [obj]
        for i, o in enumerate(parts):
            o.name = f"{name}_{piece}" + (str(i + 1) if i else "")
            o.data.name = o.name
            o.data.materials.clear()
            o.data.materials.append(mat)
            final.append(o)
    info["triangles"] = {o.name: tris(o) for o in final}
    log("triangles", info["triangles"])
    assert all(t <= 20000 for t in info["triangles"].values())

    cut = info["size"][2] * cfg["collide"]
    pts = [v.co for o in final for v in o.data.vertices if v.co.z <= cut]
    info["collision"] = {
        "min": [min(p.x for p in pts), min(p.y for p in pts), 0.0],
        "max": [max(p.x for p in pts), max(p.y for p in pts), cut],
    }

    for o in list(bpy.context.scene.objects):
        if o not in final:
            bpy.data.objects.remove(o, do_unlink=True)
    for o in bpy.context.scene.objects:
        o.select_set(True)
    path = os.path.join(OUT, stem + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_image_format="AUTO",
        export_cameras=False,
        export_lights=False,
    )
    with open(os.path.join(OUT, stem + ".json"), "w") as f:
        json.dump(info, f, indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, stem + ".blend"), compress=True)
    log(name, "exported", path, round(os.path.getsize(path) / 1e6, 2), "MB")


for model in sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else list(REMESH):
    build(model)
