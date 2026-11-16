"""Builds, saves, exports and previews arena kit 2 models in a background Blender, without touching an open session:
    blender -b --factory-startup --python assets/ArenaKit2/run_arenakit2.py -- WaffleCrates ChocoWall
No model names: every model of build_arena_pack2.py. Opens assets/ArenaKit2/ArenaKit2.blend (made on the first run),
rebuilds the named models in it, saves it, writes assets/ArenaKit2/fbx/ArenaKit2_<Model>.fbx, the previews into the
vault (Wobble Scoops/Arena Kit 2 Vorschau, not into the repo), records size, triangles and collision in
assets/ArenaKit2/arenakit2_models.json and writes assets/ArenaKit2/studio_arenakit2_templates.luau from it.

Like the deco kit it reuses the hub kit as it is (hubkit.py: palette, figure, preview, export; build_hub_pack.py: the
building blocks and the export/report/template code), read as text with the names switched (HK_ -> AK2_, HubKit ->
ArenaKit2), so all kits stay one style and one pipeline. Two additions here, patched into that text:
  * collision wedges (kind "wedge": ramps), so a ramp collides exactly like the ramp you see
  * the template script makes them invisible WedgeParts
"""

import os
import sys

import bpy

AK2_DIR = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.dirname(AK2_DIR)
VAULT_PREVIEWS = r"C:\Users\Wobble\Desktop\claude gehirn\Wobble Scoops\Arena Kit 2 Vorschau"
args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
BLEND = os.path.join(AK2_DIR, "ArenaKit2.blend")

if os.path.exists(BLEND):
    bpy.ops.wm.open_mainfile(filepath=BLEND)
else:
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def renamed(text):
    for a, b in (("HK_", "AK2_"), ("HubKit", "ArenaKit2"), ("hubkit", "arenakit2"), ("hub kit", "arena kit 2")):
        text = text.replace(a, b)
    # the template script cuts the prefix by length: "HubKit_" has 7 letters, "ArenaKit2_" 10
    text = text.replace('model.Name:sub(1, 7) == "ArenaKit2_"', 'model.Name:sub(1, 10) == "ArenaKit2_"')
    text = text.replace("local name = model.Name:sub(8)", "local name = model.Name:sub(11)")
    return text


def patched(text, old, new):
    assert text.count(old) == 1, "patch target not found once: " + old[:60]
    return text.replace(old, new)


g = globals()
g["HUB_DIR"] = AK2_DIR  # hubkit.py finds the arena kit next to it and writes fbx/ and previews/ here
exec(renamed(open(os.path.join(ASSETS, "HubKit", "hubkit.py"), encoding="utf-8").read()), g)
os.makedirs(VAULT_PREVIEWS, exist_ok=True)
g["PREVIEW_DIR"] = VAULT_PREVIEWS
_empty = os.path.join(AK2_DIR, "previews")  # made by hubkit.py, not used: the previews go to the vault
if os.path.isdir(_empty) and not os.listdir(_empty):
    os.rmdir(_empty)
hub_pack = renamed(open(os.path.join(ASSETS, "HubKit", "build_hub_pack.py"), encoding="utf-8").read())
blocks = hub_pack[: hub_pack.index("# Ice Tree:")]
pipeline = hub_pack[hub_pack.index("def preview_variants") : hub_pack.index("for _name in PACK or list(BUILDERS):")]

# collision wedges: the report writes their turn (yaw, degrees round Roblox's Y), the template makes WedgeParts
pipeline = patched(
    pipeline,
    'centre = {_v3(_rb(c["center"]))} }},\')',
    'centre = {_v3(_rb(c["center"]))}{(", yaw = %g" % c["yaw"]) if "yaw" in c else ""} }},\')',
)
pipeline = patched(
    pipeline,
    'local p = Instance.new("Part")\n\tp.Name = name\n\tp.Shape = shape or Enum.PartType.Block',
    'local p = Instance.new(if shape == "wedge" then "WedgePart" else "Part")\n\tp.Name = name\n'
    '\tif shape ~= "wedge" then\n\t\tp.Shape = shape or Enum.PartType.Block\n\tend',
)
pipeline = patched(
    pipeline,
    '\t\tif spec.kind == "cylinder" then\n\t\t\tpart = invisible("Collision", at * UP, spec.size, Enum.PartType.Cylinder)\n',
    '\t\tif spec.kind == "cylinder" then\n\t\t\tpart = invisible("Collision", at * UP, spec.size, Enum.PartType.Cylinder)\n'
    '\t\telseif spec.kind == "wedge" then\n'
    '\t\t\t-- a ramp: a WedgePart is high at its +Z end, turned by yaw round Y (assets/ArenaKit2)\n'
    '\t\t\tpart = invisible("Collision", at * CFrame.Angles(0, math.rad(spec.yaw or 0), 0), spec.size, "wedge")\n',
)
exec(blocks, g)
exec(pipeline, g)
g["PACK"] = list(args) or None
exec(open(os.path.join(AK2_DIR, "build_arena_pack2.py"), encoding="utf-8").read(), g)
bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
print("saved", BLEND)
