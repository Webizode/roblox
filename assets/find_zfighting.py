"""Finds z-fighting in a kit .blend: faces of two different colours that lie in the same plane, facing the same way,
on top of each other. In Roblox those become two MeshParts (one per colour) whose surfaces flicker against each other.
Faces of the same colour do not matter (they end up in one mesh and look the same either way).

    blender -b <Kit>.blend --python assets/find_zfighting.py -- [prefix] [eps]

prefix: collections to check (default every collection whose name starts with PK_, HK_ or AK_), eps: how close counts
as "the same plane" in studs (default 0.01). Prints per model the colour pairs with the fighting area and an example
spot (Blender coordinates, Z up), so the fix can go to the right object.
"""

import sys
from collections import defaultdict

import bpy
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
PREFIXES = tuple(args[0].split(",")) if args else ("PK_", "HK_", "AK_")
EPS = float(args[1]) if len(args) > 1 else 0.01
SKIP = ("Preview", "Layout", "Export")

deps = bpy.context.evaluated_depsgraph_get()


def colour_of(ob):
    return ob.data.materials[0].name.removeprefix("WS_") if ob.data.materials else "?"


def world_mesh(ob):
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(deps), depsgraph=deps)
    me.transform(ob.matrix_world)
    return me


for col in bpy.data.collections:
    if not col.name.startswith(PREFIXES) or any(s in col.name for s in SKIP):
        continue
    by_colour = defaultdict(list)  # colour -> list of (object name, mesh)
    for ob in col.all_objects:
        if ob.type == "MESH" and not ob.name.startswith("Collision"):
            by_colour[(ob.get("part") or "", colour_of(ob))].append((ob.name, world_mesh(ob)))
    trees = {}
    for key, items in by_colour.items():
        verts, polys = [], []
        for _, me in items:
            base = len(verts)
            verts += [v.co.copy() for v in me.vertices]
            polys += [[base + i for i in p.vertices] for p in me.polygons]
        trees[key] = BVHTree.FromPolygons(verts, polys)
    found = defaultdict(lambda: [0.0, None, set()])
    for key, items in by_colour.items():
        for other, tree in trees.items():
            if other == key or other[0] != key[0]:  # moving parts (the lid) move apart, they do not fight
                continue
            for name, me in items:
                for p in me.polygons:
                    if p.area < 1e-4:
                        continue
                    hit = tree.find_nearest(p.center, EPS)
                    if hit[0] is not None and hit[1].dot(p.normal) > 0.98:
                        pair = tuple(sorted([key[1], other[1]]))
                        entry = found[pair]
                        entry[0] += p.area / 2  # each pair is seen from both sides
                        entry[1] = entry[1] or tuple(round(c, 2) for c in p.center)
                        entry[2].add(name)
    if found:
        print(f"== {col.name}")
        for pair, (area, spot, names) in sorted(found.items(), key=lambda kv: -kv[1][0]):
            print(f"   {pair[0]} / {pair[1]}: {area:.2f} sq studs, e.g. at {spot}, objects {sorted(names)[:6]}")
    else:
        print(f"== {col.name}: clean")
    for items in by_colour.values():
        for _, me in items:
            bpy.data.meshes.remove(me)
