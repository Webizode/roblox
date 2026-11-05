"""Builds, saves, exports and previews plot kit models in a background Blender, without touching an open session:
    blender -b --factory-startup --python assets/PlotKit/run_plotkit.py -- SellCart ScoopChest
    blender -b --factory-startup --python assets/PlotKit/run_plotkit.py -- +layout      (the whole plot, preview only)
No model names: every model of build_plot_pack.py. Opens assets/PlotKit/PlotKit.blend (made on the first run), rebuilds
the named models in it, saves it, writes Desktop/roblox-assets/PlotKit/PlotKit_<Model>.fbx and
assets/PlotKit/previews/<Model>.png, and records size, triangles and collision in assets/PlotKit/plotkit_models.json.
"""

import os
import sys

import bpy

PLOT_DIR = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
BLEND = os.path.join(PLOT_DIR, "PlotKit.blend")

if os.path.exists(BLEND):
    bpy.ops.wm.open_mainfile(filepath=BLEND)
else:
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)

g = globals()
g["PLOT_DIR"] = PLOT_DIR
exec(open(os.path.join(PLOT_DIR, "plotkit.py"), encoding="utf-8").read(), g)
g["PACK"] = [a for a in args if not a.startswith("+")] or None
g["LAYOUT"] = "+layout" in args
exec(open(os.path.join(PLOT_DIR, "build_plot_pack.py"), encoding="utf-8").read(), g)
bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
print("saved", BLEND)
