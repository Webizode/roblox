"""Orthographic side view of a built model (assets/Meshy/export/<Name>.blend), front (-Y) to the left, with the hinge."""
import bpy, sys, math, json, os
args = sys.argv[sys.argv.index("--") + 1:]
name, out = args[0], args[1]
here = os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.open_mainfile(filepath=os.path.join(here, "export", name + ".blend"))
sc = bpy.context.scene
try: sc.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError: sc.render.engine = "BLENDER_EEVEE"
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND"); bg.inputs[1].default_value = 1.2
sun = bpy.data.lights.new("S", "SUN"); sun.energy = 4; so = bpy.data.objects.new("S", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(40), 0, math.radians(60))
info = json.load(open(os.path.join(here, "export", name + ".json")))
s = info["size"]
cam = bpy.data.cameras.new("C"); cam.type = "ORTHO"; cam.ortho_scale = 20
co = bpy.data.objects.new("C", cam); sc.collection.objects.link(co); sc.camera = co
co.location = (50, 0, 7); co.rotation_euler = (math.radians(90), 0, math.radians(90))
sc.render.resolution_x = 1000; sc.render.resolution_y = 1000
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("hinge", info.get("hinge"))
