"""Builds, saves, exports and previews hub kit models in a background Blender, without touching an open session:
    blender -b --factory-startup --python assets/HubKit/run_hubkit.py -- IceTree Lantern
No model names: every model of build_hub_pack.py. Opens assets/HubKit/HubKit.blend (made on the first run), rebuilds
the named models in it, saves it, writes assets/HubKit/fbx/HubKit_<Model>.fbx and assets/HubKit/previews/<Model>.png,
records size, triangles and collision in assets/HubKit/hubkit_models.json and writes
assets/HubKit/studio_hubkit_templates.luau from it.
"""

import os
import sys

import bpy

HUB_DIR = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
BLEND = os.path.join(HUB_DIR, "HubKit.blend")

if os.path.exists(BLEND):
    bpy.ops.wm.open_mainfile(filepath=BLEND)
else:
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)

g = globals()
g["HUB_DIR"] = HUB_DIR
exec(open(os.path.join(HUB_DIR, "hubkit.py"), encoding="utf-8").read(), g)
g["PACK"] = list(args) or None
exec(open(os.path.join(HUB_DIR, "build_hub_pack.py"), encoding="utf-8").read(), g)
bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
print("saved", BLEND)
