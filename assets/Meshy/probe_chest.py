import bpy, os, sys
from collections import Counter
HERE = os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, "source", "ScoopChest.glb"))
ob = next(o for o in bpy.context.scene.objects if o.type == "MESH")
mw = ob.matrix_world
vs = [mw @ v.co for v in ob.data.vertices]
zmin = min(v.z for v in vs)
# height profile: per y band, the max z
for yb in range(-10, 11):
    y0 = yb * 0.05
    band = [v for v in vs if y0 <= v.y < y0 + 0.05]
    if band:
        print(f"y {y0:+.2f}: n {len(band):7d} z {min(v.z for v in band)-zmin:.3f}..{max(v.z for v in band)-zmin:.3f}")
# x histogram of vertices in the cups' band (front half, middle height)
for zl, zh in [(0.45, 0.6), (0.6, 0.75), (0.75, 0.9)]:
    c = Counter()
    for v in vs:
        if -0.3 < v.y < 0.15 and zl < v.z - zmin < zh:
            c[round(v.x, 1)] += 1
    print("z", zl, zh, sorted(c.items()))
