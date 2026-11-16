"""The waffle backpack's meshes (kill test 13.11.2026: team colour on the waffle, a nicer waffle).

Run in Blender (Text editor, or exec through the MCP): builds the scene "BackpackKit" and exports
Backpack_Waffle.fbx to EXPORT_DIR, then prints each mesh's size and centre in Roblox axes for Config/Backpack.meshes.

1 Blender unit = 1 stud, Z up (the FBX export turns it into Roblox's Y up), like the PlotKit. The cone's middle is the
origin, the opening at +Z, the measures those of Config/Backpack (cone 2.0 long, 1.9 across the top, 0.45 at the tip),
so the tower still sits in it (TowerShape.seatInCone) and Backpacks scales it with the torso.

Four meshes, one colour each (Studio's importer keeps one MeshPart per mesh, the client colours them):
  Waffle  the cone with its rounded tip and a lid just under the rim, waffle colour
  Lines   the raised diagonal ridges of the waffle pattern, a darker brown
  Rim     the round chocolate rim, its top at the cone's top plus RIM_LIFT (as the old cylinder rim)
  Glaze   the dipped glaze under the rim with drips, white: the client tints it in the plot's flavour colour
"""

import math
import os

import bmesh
import bpy

EXPORT_DIR = r"C:\Users\Wobble\Desktop\roblox-assets\Backpack"

LENGTH, TOP, TIP = 2.0, 1.9, 0.45
RIM_LIFT = 0.03
RIM_MINOR = 0.1
RIDGES = 8  # per direction
RIDGE_TURN = 0.5  # turns from the tip to the top
RIDGE_RADIUS = 0.028
DRIPS = [0.55, 0.3, 0.7, 0.38, 0.5, 0.26, 0.62, 0.34, 0.45, 0.3]


def radius_at(z):
    """Cone radius at height z (tip at -LENGTH / 2, top at +LENGTH / 2)."""
    share = (z + LENGTH / 2) / LENGTH
    return TIP / 2 + (TOP - TIP) / 2 * share


def colour(hexcode):
    h = hexcode.lstrip("#")
    srgb = [int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, 1.0)


def material(name, hexcode, roughness=0.5):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = colour(hexcode)
    bsdf.inputs["Roughness"].default_value = roughness
    m.diffuse_color = colour(hexcode)
    return m


def join(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    # a same-named object elsewhere (the preview scene) would turn this one into "Waffle.003" in the FBX
    taken = bpy.data.objects.get(name)
    if taken is not None and taken is not o:
        taken.name = name + "_alt"
    o.name = name
    o.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.shade_smooth()
    return o


def build():
    scene = bpy.data.scenes.get("BackpackKit") or bpy.data.scenes.new("BackpackKit")
    bpy.context.window.scene = scene
    for o in list(scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    col = scene.collection

    waffle_mat = material("BP_Waffle", "#E2AE62", 0.6)
    lines_mat = material("BP_Lines", "#A8692E", 0.55)
    rim_mat = material("BP_Rim", "#6A3F2A", 0.3)
    glaze_mat = material("BP_Glaze", "#FFFFFF", 0.2)

    # the cone, open at the top, a lid just under the rim, a round tip
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=32, radius1=TIP / 2, radius2=TOP / 2, depth=LENGTH)
    me = bpy.data.meshes.new("cone")
    bm.to_mesh(me)
    bm.free()
    cone = bpy.data.objects.new("cone", me)
    col.objects.link(cone)
    bpy.ops.mesh.primitive_circle_add(vertices=32, radius=radius_at(LENGTH / 2 - 0.06), fill_type="NGON",
                                      location=(0, 0, LENGTH / 2 - 0.06))
    lid = bpy.context.active_object
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=TIP / 2, location=(0, 0, -LENGTH / 2))
    tip = bpy.context.active_object
    waffle = join([cone, lid, tip], "Waffle")
    waffle.data.materials.append(waffle_mat)

    # the ridges: helices on the cone, both ways round
    ridges = []
    for direction in (1, -1):
        for k in range(RIDGES):
            curve = bpy.data.curves.new(f"ridge_{direction}_{k}", "CURVE")
            curve.dimensions = "3D"
            curve.bevel_depth = RIDGE_RADIUS
            curve.bevel_resolution = 0
            spline = curve.splines.new("POLY")
            steps = 12
            spline.points.add(steps)
            for i in range(steps + 1):
                t = i / steps
                z = -LENGTH / 2 + 0.12 + t * (LENGTH - 0.3)
                a = 2 * math.pi * k / RIDGES + direction * RIDGE_TURN * 2 * math.pi * t
                r = radius_at(z) + RIDGE_RADIUS * 0.4
                spline.points[i].co = (math.cos(a) * r, math.sin(a) * r, z, 1)
            obj = bpy.data.objects.new(curve.name, curve)
            col.objects.link(obj)
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.convert(target="MESH")
            ridges.append(bpy.context.view_layer.objects.active)
    lines = join(ridges, "Lines")
    lines.data.materials.append(lines_mat)

    # the rim: a torus whose top meets the old rim's top
    bpy.ops.mesh.primitive_torus_add(major_segments=32, minor_segments=8, major_radius=TOP / 2,
                                     minor_radius=RIM_MINOR, location=(0, 0, LENGTH / 2 + RIM_LIFT - RIM_MINOR))
    rim = join([bpy.context.active_object], "Rim")
    rim.data.materials.append(rim_mat)

    # the glaze: a dipped band under the rim and drips running down the cone
    top_z = LENGTH / 2
    parts = []
    bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=radius_at(top_z - 0.24) + 0.035, radius2=TOP / 2 + 0.04,
                                    depth=0.24, location=(0, 0, top_z - 0.12), end_fill_type="NOTHING")
    parts.append(bpy.context.active_object)
    for i, drip in enumerate(DRIPS):
        a = i / len(DRIPS) * 2 * math.pi + 0.35
        mid = 0.2 + drip / 2
        r = radius_at(top_z - mid) + 0.02
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=5, radius=0.1,
                                             location=(math.cos(a) * r, math.sin(a) * r, top_z - mid))
        body = bpy.context.active_object
        body.scale = (0.9, 0.9, (drip + 0.1) / 0.2)
        parts.append(body)
        rb = radius_at(top_z - 0.2 - drip) + 0.03
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=5, radius=0.105,
                                             location=(math.cos(a) * rb, math.sin(a) * rb, top_z - 0.2 - drip + 0.04))
        parts.append(bpy.context.active_object)
    glaze = join(parts, "Glaze")
    glaze.data.materials.append(glaze_mat)
    return [waffle, lines, rim, glaze]


def report(objects):
    """Size and centre of each mesh in Roblox axes (x, y up, z = -Blender y), for Config/Backpack.meshes."""
    lines = []
    for o in objects:
        xs = [v.co.x for v in o.data.vertices]
        ys = [v.co.y for v in o.data.vertices]
        zs = [v.co.z for v in o.data.vertices]
        size = (max(xs) - min(xs), max(zs) - min(zs), max(ys) - min(ys))
        centre = ((max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2, -(max(ys) + min(ys)) / 2)
        lines.append(
            "\t\t%s = { size = { %.3f, %.3f, %.3f }, centre = { %.3f, %.3f, %.3f } },"
            % (o.name.lower(), *size, *centre)
        )
    return "\n".join(lines)


def export(objects):
    os.makedirs(EXPORT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    path = os.path.join(EXPORT_DIR, "Backpack_Waffle.fbx")
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        global_scale=1.0,
        apply_unit_scale=True,
        axis_forward="-Z",
        axis_up="Y",
        object_types={"MESH"},
        mesh_smooth_type="FACE",
    )
    return path


objects = build()
print(export(objects))
print(report(objects))
