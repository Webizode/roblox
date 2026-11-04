"""Exports arena kit models as FBX for Roblox, one file per model, in the same Blender session after the build:
    MODELS = ["CoverBlock"]   # optional, default: every AK_* collection
    exec(open(ASSET_DIR + "/export_arenakit.py").read())

Writes Desktop\\roblox-assets\\ArenaKit_<Model>.fbx. Every model is merged into one mesh per colour, named
<Model>_<Colour> (CoverBlock_Cream, CoverBlock_Pink, ...), each with its one WS_<Colour> material, so Roblox gets a
handful of MeshParts and a colour variant only changes MeshPart.Color. The origin stays at the model's bottom centre
(0, 0, 0). Same FBX settings as the Big Swirl: 1 Blender unit = 1 stud, -Z forward, Y up, modifiers applied, no
textures. The .blend is left as it was: the merged copies live in a temporary collection and are removed again.
"""

import os

import bpy

OUT_DIR = os.path.join(os.path.expanduser("~"), "Desktop", "roblox-assets")
os.makedirs(OUT_DIR, exist_ok=True)
scene = bpy.context.scene
if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")

wanted = globals().get("MODELS") or [c.name[3:] for c in bpy.data.collections if c.name.startswith("AK_")]

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


def baked_copy(ob, into):
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(deps), preserve_all_data_layers=True, depsgraph=deps)
    me.transform(ob.matrix_world)
    copy = bpy.data.objects.new(ob.name + "_x", me)
    into.objects.link(copy)
    return copy


for model in wanted:
    source = bpy.data.collections["AK_" + model]
    tmp = bpy.data.collections.new("AK_Export")
    scene.collection.children.link(tmp)
    by_colour = {}
    for ob in source.all_objects:
        if ob.type == "MESH" and ob.data.materials:
            colour = ob.data.materials[0].name.removeprefix("WS_")
            by_colour.setdefault(colour, []).append(baked_copy(ob, tmp))
    parts = []
    for colour, objects in sorted(by_colour.items()):
        bpy.ops.object.select_all(action="DESELECT")
        for o in objects:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        if len(objects) > 1:
            bpy.ops.object.join()
        merged = bpy.context.view_layer.objects.active
        merged.name = merged.data.name = f"{model}_{colour}"
        parts.append(merged)
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    path = os.path.join(OUT_DIR, f"ArenaKit_{model}.fbx")
    bpy.ops.export_scene.fbx(filepath=path, **FBX)
    tris = 0
    for p in parts:
        p.data.calc_loop_triangles()
        tris += len(p.data.loop_triangles)
    print(f"{path}: {len(parts)} meshes ({', '.join(p.name for p in parts)}), {tris} triangles")
    for ob in list(tmp.objects):
        me = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.meshes.remove(me)
    bpy.data.collections.remove(tmp)
