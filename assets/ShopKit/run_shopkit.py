"""Builds, saves, exports and previews shop kit models in a background Blender, without touching an open session:
    blender -b --factory-startup --python assets/ShopKit/run_shopkit.py -- UpgradeShop
No model names: every model of build_shop_pack.py. Opens assets/ShopKit/ShopKit.blend (made on the first run), rebuilds
the named models in it, saves it, writes assets/ShopKit/fbx/ShopKit_<Model>.fbx, the previews into the vault
(Wobble Scoops/Shop Kit Vorschau, not into the repo), records size, triangles and collision in
assets/ShopKit/shopkit_models.json and writes assets/ShopKit/studio_shopkit_templates.luau from it.

The shop kit reuses the hub kit as it is: hubkit.py (palette, figure, preview, export) and the building blocks and
the export/report/template code of build_hub_pack.py, read as text with the names switched (HK_ -> DK_, HubKit ->
ShopKit), so both kits stay one style and one pipeline.
"""

import os
import sys

import bpy

SHOP_DIR = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.dirname(SHOP_DIR)
VAULT_PREVIEWS = r"C:\Users\Wobble\Desktop\claude gehirn\Wobble Scoops\Shop Kit Vorschau"
args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
BLEND = os.path.join(SHOP_DIR, "ShopKit.blend")

if os.path.exists(BLEND):
    bpy.ops.wm.open_mainfile(filepath=BLEND)
else:
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def renamed(text):
    for a, b in (("HK_", "SK_"), ("HubKit", "ShopKit"), ("hubkit", "shopkit"), ("hub kit", "shop kit")):
        text = text.replace(a, b)
    # the template script cuts the prefix by length: "HubKit_" has 7 letters, "ShopKit_" 8
    text = text.replace('model.Name:sub(1, 7) == "ShopKit_"', 'model.Name:sub(1, 8) == "ShopKit_"')
    text = text.replace("local name = model.Name:sub(8)", "local name = model.Name:sub(9)")
    return text


g = globals()
g["HUB_DIR"] = SHOP_DIR  # hubkit.py finds the arena kit next to it and writes fbx/ and previews/ here
exec(renamed(open(os.path.join(ASSETS, "HubKit", "hubkit.py"), encoding="utf-8").read()), g)
os.makedirs(VAULT_PREVIEWS, exist_ok=True)
g["PREVIEW_DIR"] = VAULT_PREVIEWS
_empty = os.path.join(SHOP_DIR, "previews")  # made by hubkit.py, not used: the previews go to the vault
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
exec(open(os.path.join(SHOP_DIR, "build_shop_pack.py"), encoding="utf-8").read(), g)
bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
print("saved", BLEND)
