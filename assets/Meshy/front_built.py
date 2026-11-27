"""Orthographic front view of a built model (export/<Name>.blend) in studs: 50 px per stud, the model's bottom middle at
pixel (W/2, H - 50), to measure where things sit (signs)."""
import bpy, sys, math, os
args = sys.argv[sys.argv.index("--") + 1:]
here = os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.open_mainfile(filepath=os.path.join(here, "export", args[0] + ".blend"))
sc = bpy.context.scene
try: sc.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError: sc.render.engine = "BLENDER_EEVEE"
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
next(n for n in w.node_tree.nodes if n.type == "BACKGROUND").inputs[1].default_value = 1.5
W, H = 1500, 1500
cam = bpy.data.cameras.new("C"); cam.type = "ORTHO"; cam.ortho_scale = W / 50
co = bpy.data.objects.new("C", cam); sc.collection.objects.link(co); sc.camera = co
co.location = (0, -100, H / 100 - 1); co.rotation_euler = (math.radians(90), 0, 0)
cam.clip_end = 300
sc.render.resolution_x = W; sc.render.resolution_y = H
sc.render.filepath = args[1]
bpy.ops.render.render(write_still=True)
print("DONE")
