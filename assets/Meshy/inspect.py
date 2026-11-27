"""Prints what each Meshy GLB holds: objects, triangles, materials and their images, size (metres and studs).
    blender -b --factory-startup --python assets/Meshy/inspect.py -- [Name ...]
"""
import os, sys, bpy
HERE = os.path.dirname(os.path.abspath(__file__))
names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
names = names or sorted(f[:-4] for f in os.listdir(os.path.join(HERE, "source")) if f.endswith(".glb"))
for name in names:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, "source", name + ".glb"))
    dg = bpy.context.evaluated_depsgraph_get()
    tris = 0; lo = [1e9]*3; hi = [-1e9]*3
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH": continue
        me = ob.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles(); t = len(me.loop_triangles); tris += t
        for v in me.vertices:
            w = ob.matrix_world @ v.co
            for i in range(3): lo[i] = min(lo[i], w[i]); hi[i] = max(hi[i], w[i])
        print(f"  {name} object {ob.name}: {t} tris, {len(me.vertices)} verts, mats {[m.name for m in ob.data.materials]}")
    size = [hi[i]-lo[i] for i in range(3)]
    print(f"{name}: {tris} tris, size m x{size[0]:.2f} y{size[1]:.2f} z{size[2]:.2f}, min {[round(v,2) for v in lo]}")
    for img in bpy.data.images:
        print(f"  image {img.name} {img.size[0]}x{img.size[1]}")
    for m in bpy.data.materials:
        if m.node_tree:
            print("  mat", m.name, [n.type for n in m.node_tree.nodes])
