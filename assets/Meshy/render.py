"""Renders a model from the front, at an angle and from above, side by side, into one PNG.
    blender -b --factory-startup --python assets/Meshy/render.py -- <file.glb|file.fbx|file.blend> <out.png> [label]
Front is -Y in Blender (the side the player stands on); the model stands on z = 0 or is centred.
"""
import math, os, sys, bpy
from mathutils import Vector
args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
if src.endswith(".glb"):
    bpy.ops.import_scene.gltf(filepath=src)
elif src.endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=src)
scene = bpy.context.scene
try:
    scene.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError:
    scene.render.engine = "BLENDER_EEVEE"
scene.render.film_transparent = False
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("W"); scene.world = world; world.use_nodes = True
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs[0].default_value = (0.82, 0.86, 0.92, 1); bg.inputs[1].default_value = 1.0
meshes = [o for o in scene.objects if o.type == "MESH"]
pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
centre = (lo + hi) / 2; radius = (hi - lo).length / 2
sun = bpy.data.lights.new("Sun", "SUN"); sun.energy = 3.0
so = bpy.data.objects.new("Sun", sun); scene.collection.objects.link(so); so.rotation_euler = (math.radians(50), 0, math.radians(-30))
cam = bpy.data.cameras.new("C"); cam.lens = 50
co = bpy.data.objects.new("C", cam); scene.collection.objects.link(co); scene.camera = co
scene.render.resolution_x = 640; scene.render.resolution_y = 640
dist = radius / math.sin(cam.angle / 2) * 1.05
views = {"front": (0, -1, 0.12), "angle": (0.75, -1, 0.55), "top": (0.0, -0.25, 1)}
parts = []
for key, d in views.items():
    d = Vector(d).normalized()
    co.location = centre + d * dist
    co.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    path = out[:-4] + f"_{key}.png"; scene.render.filepath = path
    bpy.ops.render.render(write_still=True); parts.append(path)
print("RENDERED", parts, "size", [round(v, 3) for v in (hi - lo)])
