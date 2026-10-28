"""Exports the Big Swirl as FBX for Roblox. Run after build_bigswirl.py and animate_bigswirl.py, in the same Blender
session:
    exec(open(r"<repo>/assets/BigSwirl/export_bigswirl.py").read())

Writes to Desktop\\roblox-assets:
    BigSwirl.fbx        the whole machine as one model: the rig (armature "BigSwirl" with the bones Root, ArmN and
                        ArmN_Cup) and every mesh, pictures embedded
    BigSwirl_Model.fbx  the same without embedded pictures (the 3D importer can hang on the full one), and BigSwirl.glb
    BigSwirl_Cups.fbx   only the cups on the rig

No animation is exported: the game turns the arms' bones itself from the baked cycle (Config/BigSwirlCycle, made by
scripts/bigswirl-cycle.luau from arm_cycle.json).

The meshes are merged per module and per colour (one material each, named after its palette colour), so Roblox gets
a few dozen MeshParts instead of 150 small ones. The arm parts are skinned to their bone with weight 1 (rigid); the
rest of the machine does not move and is not skinned. The scoops in the cups are left out: the game shows them in the
flavour that flies. 1 Blender unit = 1 stud. The working .blend is left as it was: everything here is built in a
temporary "Export" collection and removed again.
"""

import os

import bpy

OUT_DIR = os.path.join(os.path.expanduser("~"), "Desktop", "roblox-assets")
ARMS = tuple(arm_yaws)  # noqa: F821 (from build_bigswirl.py)

scene = bpy.context.scene
scene.frame_set(0)  # the rest pose: the rig's bones are laid out in it
os.makedirs(OUT_DIR, exist_ok=True)
if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")

source = bpy.data.collections["BigSwirl"]
exp = bpy.data.collections.get("Export") or bpy.data.collections.new("Export")
if exp.name not in scene.collection.children:
    scene.collection.children.link(exp)
for ob in list(exp.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
for leftover in [a for a in bpy.data.armatures if a.name.startswith("BigSwirlRig") and a.users == 0]:
    bpy.data.armatures.remove(leftover)


def baked_copy(ob):
    """The object's final mesh (modifiers applied) in world space, as a new object in the Export collection."""
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(deps), preserve_all_data_layers=True, depsgraph=deps)
    me.transform(ob.matrix_world)
    copy = bpy.data.objects.new(ob.name + "_x", me)
    exp.objects.link(copy)
    return copy


def merge_by_colour(objects, name):
    """Joins the objects and splits the result again by material: one object per colour, named name_colour."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = [o for o in bpy.context.selected_objects] or [joined]
    result = []
    for p in parts:
        used = {poly.material_index for poly in p.data.polygons}
        bpy.context.view_layer.objects.active = p
        bpy.ops.object.material_slot_remove_unused()
        mat = p.data.materials[0] if p.data.materials else None
        colour = mat.name.removeprefix("BS_") if mat else "none"
        p.name = p.data.name = f"{name}_{colour}"
        if not used:
            continue
        result.append(p)
    return result


# ---- the meshes, grouped: static modules, and per arm the arm and its cup (they hang on different bones)
groups = {}
for col in source.children:
    for ob in col.all_objects:
        if ob.type != "MESH" or ob.name.endswith("_Scoop"):
            continue
        if col.name.startswith("LauncherArm_"):
            n = col.name.rsplit("_", 1)[1]
            key = (f"Arm{n}_Cup" if ob.parent and ob.parent.name == f"Arm{n}_Wrist" else f"Arm{n}", True)
        else:
            key = (col.name, False)
        groups.setdefault(key, []).append(baked_copy(ob))

# ---- the rig: Root, and per arm a shoulder bone and a cup bone laid on the joints' frames in the rest pose
arm_data = bpy.data.armatures.new("BigSwirlRig")
rig = bpy.data.objects.new("BigSwirl", arm_data)
exp.objects.link(rig)
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
edit = arm_data.edit_bones
root = edit.new("Root")
root.head, root.tail = (0, 0, 0), (0, 0, 3)
for n in ARMS:
    for bone_name, joint_name, parent in ((f"Arm{n}", f"LauncherArm_{n}", root), (f"Arm{n}_Cup", f"Arm{n}_Wrist", None)):
        bone = edit.new(bone_name)
        bone.head, bone.tail = (0, 0, 0), (0, 2, 0)
        bone.matrix = bpy.data.objects[joint_name].matrix_world.normalized()
        bone.parent = parent or edit[f"Arm{n}"]
        bone.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")

# ---- merge, skin the moving parts rigidly, hang everything under the rig
parts = []
for (name, moves), objects in groups.items():
    for p in merge_by_colour(objects, name):
        if moves:
            group = p.vertex_groups.new(name=name)
            group.add(list(range(len(p.data.vertices))), 1.0, "REPLACE")
            mod = p.modifiers.new("Armature", "ARMATURE")
            mod.object = rig
        p.parent = rig
        parts.append(p)

FBX = dict(
    use_selection=True,
    object_types={"ARMATURE", "MESH"},
    global_scale=1.0,
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_UNITS",
    axis_forward="-Z",
    axis_up="Y",
    use_mesh_modifiers=True,
    mesh_smooth_type="FACE",
    add_leaf_bones=False,
    primary_bone_axis="Y",
    secondary_bone_axis="X",
    use_armature_deform_only=False,
    path_mode="COPY",
    embed_textures=True,
)


def select(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig


# the whole model with its pictures embedded
select([rig] + parts)
main = os.path.join(OUT_DIR, "BigSwirl.fbx")
bpy.ops.export_scene.fbx(filepath=main, bake_anim=False, **FBX)
written = [main]

# lighter files for the 3D importer, which can hang at "analysing" on the full one: no embedded pictures, as FBX
# and as glTF
lean = dict(FBX, path_mode="AUTO", embed_textures=False)
path = os.path.join(OUT_DIR, "BigSwirl_Model.fbx")
bpy.ops.export_scene.fbx(filepath=path, bake_anim=False, **lean)
written.append(path)
path = os.path.join(OUT_DIR, "BigSwirl.glb")
bpy.ops.export_scene.gltf(
    filepath=path,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_skins=True,
    export_animations=False,
    export_materials="EXPORT",
)
written.append(path)
# only the cups (bowl and rim per arm) on the rig: to swap them in the placed machine without importing it all again
select([rig] + [p for p in parts if "_Cup_" in p.name])
path = os.path.join(OUT_DIR, "BigSwirl_Cups.fbx")
bpy.ops.export_scene.fbx(filepath=path, bake_anim=False, **lean)
written.append(path)

# report, then clean up
tris = 0
for p in parts:
    p.data.calc_loop_triangles()
    tris += len(p.data.loop_triangles)
xs = [(p.matrix_world @ v.co) for p in parts for v in p.data.vertices]
size = [max(v[i] for v in xs) - min(v[i] for v in xs) for i in range(3)]
print(f"{len(parts)} meshes, {tris} triangles, {len(rig.data.bones)} bones; size {size[0]:.1f} x {size[2]:.1f} (high) x {size[1]:.1f} studs")
print("skinned:", sorted(p.name for p in parts if p.vertex_groups))
for path in written:
    print(path, os.path.getsize(path) // 1024, "KB")
for ob in list(exp.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
bpy.data.armatures.remove(arm_data)
bpy.data.collections.remove(exp)
