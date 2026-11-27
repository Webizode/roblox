"""Orthographic side view (from +X, front -Y to the left) of a source GLB with a 0.05 m grid, to find parts."""
import bpy, os, sys, math
args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=args[0])
sc = bpy.context.scene
try: sc.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError: sc.render.engine = "BLENDER_EEVEE"
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND"); bg.inputs[1].default_value = 1.2
sun = bpy.data.lights.new("S", "SUN"); sun.energy = 4; so = bpy.data.objects.new("S", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(40), 0, math.radians(60))
view = args[2] if len(args) > 2 else "side"
cam = bpy.data.cameras.new("C"); cam.type = "ORTHO"; cam.ortho_scale = 2.0
co = bpy.data.objects.new("C", cam); sc.collection.objects.link(co); sc.camera = co
if view == "side":
    co.location = (5, 0, 0.0); co.rotation_euler = (math.radians(90), 0, math.radians(90))
else:  # front
    co.location = (0, -5, 0.0); co.rotation_euler = (math.radians(90), 0, 0)
sc.render.resolution_x = 1000; sc.render.resolution_y = 1000
sc.render.filepath = args[1]
bpy.ops.render.render(write_still=True)
