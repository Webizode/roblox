"""Exports the tower scoops as FBX for the Roblox 3D importer. Run after build_scoops.py in the same Blender session:
    exec(open(ASSET_DIR + "/export_scoops.py").read())

Writes to Desktop\\roblox-assets\\TowerScoops one file per flavor and LOD, <flavor>_<LOD>.fbx, each with a single
mesh named TS_<Flavor>_<LOD> (1 Blender unit = 1 stud, the same settings as the Big Swirl). In Studio: import both
LODs of a flavor (File > Import 3D), then studio_setup.luau turns them into the templates the game draws. The detail
picture is uploaded on its own (assets/TowerScoops/textures, see studio_setup.luau).
"""

import os

import bpy

OUT_DIR = os.path.join(os.path.expanduser("~"), "Desktop", "roblox-assets", "TowerScoops")
os.makedirs(OUT_DIR, exist_ok=True)

FBX = dict(
    use_selection=True,
    object_types={"MESH"},
    global_scale=1.0,
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_UNITS",
    axis_forward="-Z",
    axis_up="Y",
    use_mesh_modifiers=False,  # the preview outline is a modifier; the game draws its own (a Highlight)
    mesh_smooth_type="FACE",
    path_mode="AUTO",
    embed_textures=False,
)

for flavor_id, lods in BUILT.items():
    for lod_name, ob in lods.items():
        bpy.ops.object.select_all(action="DESELECT")
        ob.hide_set(False)
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        path = os.path.join(OUT_DIR, f"{flavor_id}_{lod_name}.fbx")
        bpy.ops.export_scene.fbx(filepath=path, **FBX)
        print(path, len(ob.data.polygons), "triangles")
