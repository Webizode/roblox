"""Builds, saves, exports and previews deco kit models in a background Blender, without touching an open session:
    blender -b --factory-startup --python assets/DecoKit/run_decokit.py -- BushRound PalmBent
No model names: every model of build_deco_pack.py. Opens assets/DecoKit/DecoKit.blend (made on the first run), rebuilds
the named models in it, saves it, writes assets/DecoKit/fbx/DecoKit_<Model>.fbx, the previews into the vault
(Wobble Scoops/Deko Kit Vorschau, not into the repo), records size, triangles and collision in
assets/DecoKit/decokit_models.json and writes assets/DecoKit/studio_decokit_templates.luau from it.

The deco kit reuses the hub kit as it is: hubkit.py (palette, figure, preview, export) and the building blocks and
the export/report/template code of build_hub_pack.py, read as text with the names switched (HK_ -> DK_, HubKit ->
DecoKit), so both kits stay one style and one pipeline.
"""

import os
import sys

import bpy

DECO_DIR = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.dirname(DECO_DIR)
VAULT_PREVIEWS = r"C:\Users\Wobble\Desktop\claude gehirn\Wobble Scoops\Deko Kit Vorschau"
args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
BLEND = os.path.join(DECO_DIR, "DecoKit.blend")

if os.path.exists(BLEND):
    bpy.ops.wm.open_mainfile(filepath=BLEND)
else:
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def renamed(text):
    for a, b in (("HK_", "DK_"), ("HubKit", "DecoKit"), ("hubkit", "decokit"), ("hub kit", "deco kit")):
        text = text.replace(a, b)
    # the template script cuts the prefix by length: "HubKit_" has 7 letters, "DecoKit_" 8
    text = text.replace('model.Name:sub(1, 7) == "DecoKit_"', 'model.Name:sub(1, 8) == "DecoKit_"')
    text = text.replace("local name = model.Name:sub(8)", "local name = model.Name:sub(9)")
    return text


g = globals()
g["HUB_DIR"] = DECO_DIR  # hubkit.py finds the arena kit next to it and writes fbx/ and previews/ here
exec(renamed(open(os.path.join(ASSETS, "HubKit", "hubkit.py"), encoding="utf-8").read()), g)
os.makedirs(VAULT_PREVIEWS, exist_ok=True)
g["PREVIEW_DIR"] = VAULT_PREVIEWS
_empty = os.path.join(DECO_DIR, "previews")  # made by hubkit.py, not used: the previews go to the vault
if os.path.isdir(_empty) and not os.listdir(_empty):
    os.rmdir(_empty)
hub_pack = renamed(open(os.path.join(ASSETS, "HubKit", "build_hub_pack.py"), encoding="utf-8").read())
# the building blocks (everything before the first hub model) and the preview/export/report/template code (from
# preview_variants up to the hub's own build loop); the hub's models themselves are not built here
blocks = hub_pack[: hub_pack.index("# Ice Tree:")]
pipeline = hub_pack[hub_pack.index("def preview_variants") : hub_pack.index("for _name in PACK or list(BUILDERS):")]
exec(blocks, g)
exec(pipeline, g)
g["PACK"] = list(args) or None
exec(open(os.path.join(DECO_DIR, "build_deco_pack.py"), encoding="utf-8").read(), g)
bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
print("saved", BLEND)
