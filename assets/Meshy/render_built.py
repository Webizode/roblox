"""Renders a built model (assets/Meshy/export/<Name>.blend) like render.py renders the source: front, angle, top."""
import bpy, os, sys, math
from mathutils import Vector
args = sys.argv[sys.argv.index("--") + 1:]
here = os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.open_mainfile(filepath=os.path.join(here, "export", args[0] + ".blend"))
scene = bpy.context.scene
try: scene.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError: scene.render.engine = "BLENDER_EEVEE"
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("W"); scene.world = world; world.use_nodes = True
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs[0].default_value = (0.82, 0.86, 0.92, 1); bg.inputs[1].default_value = 1.0
# the baked maps: roughness and metal into the material so it shines like the game will
for mat in bpy.data.materials:
    if not mat.use_nodes: continue
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    stem = mat.name[:-4] if mat.name.endswith("_Mat") else None
    if not bsdf or not stem: continue
    for kind, socket in (("rough", "Roughness"), ("metal", "Metallic")):
        path = os.path.join(here, "export", f"{stem}_{kind}.png")
        if os.path.exists(path):
            node = nodes.new("ShaderNodeTexImage"); node.image = bpy.data.images.load(path)
            node.image.colorspace_settings.name = "Non-Color"
            links.new(node.outputs["Color"], bsdf.inputs[socket])
meshes = [o for o in scene.objects if o.type == "MESH"]
pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
centre = (lo + hi) / 2; radius = (hi - lo).length / 2
sun = bpy.data.lights.new("Sun", "SUN"); sun.energy = 3.0
so = bpy.data.objects.new("Sun", sun); scene.collection.objects.link(so); so.rotation_euler = (math.radians(50), 0, math.radians(-30))
cam = bpy.data.cameras.new("C"); cam.lens = 50; cam.clip_end = 1000
co = bpy.data.objects.new("C", cam); scene.collection.objects.link(co); scene.camera = co
scene.render.resolution_x = 640; scene.render.resolution_y = 640
dist = radius / math.sin(cam.angle / 2) * 1.05
for key, d in {"front": (0, -1, 0.12), "angle": (0.75, -1, 0.55), "top": (0.0, -0.25, 1)}.items():
    d = Vector(d).normalized()
    co.location = centre + d * dist
    co.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(args[1], f"{args[0]}_after_{key}.png")
    bpy.ops.render.render(write_still=True)
print("RENDERED", args[0])
