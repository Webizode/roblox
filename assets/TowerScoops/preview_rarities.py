"""Preview renders of the rarer tower scoops (build_rarities.py): every flavor of a rarity side by side (front and
back), each flavor close up, and a mixed tower seen from 30 studs. Run after build_rarities.py in the same Blender:
    RARITY_SHOTS = ["lineups", "close", "tower"]
    exec(open(ASSET_DIR + "/preview_rarities.py").read())

Uses the look of preview_scoops.py (its shots are skipped). Writes renders/rarity_<rarity>.png, renders/close_<flavor>.png
and renders/tower_mix_30studs.png.
"""

import math
import os

import bpy

PREVIEW_SHOTS = []
for _ob in [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("Cube")]:
    bpy.data.objects.remove(_ob, do_unlink=True)  # the start file's cube
PREVIEW_FLAVOR = next(iter(BUILT))
exec(open(os.path.join(ASSET_DIR, "preview_scoops.py"), encoding="utf-8").read())

GROUPS = {
    "uncommon": ORDER[0:11],
    "rare": ORDER[11:21],
    "epic": ORDER[21:31],
    "legendary": ORDER[31:41],
}


def save(name, w, h):
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.resolution_percentage = 100
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", scene.render.filepath)


def lineup(rarity, ids):
    col = preview_collection()
    sun(col)
    ground(col).location = (0, 0, -ROOM)
    gap = 2.5
    for i, fid in enumerate(ids):
        x = (i - (len(ids) - 1) / 2) * gap
        scoop_copy(col, BUILT[fid]["LOD0"], (x, 0, 0), rotation=math.radians(-15))
        scoop_copy(col, BUILT[fid]["LOD0"], (x, 3.0, 0), rotation=math.radians(165))  # the back
    span = (len(ids) - 1) * gap
    camera(col, (0, -span * 0.5 - 2.5, 3.4), (0, 1.0, 0), lens_fov=48)
    save(f"rarity_{rarity}", 1800, 760)


def close(fid):
    col = preview_collection()
    sun(col)
    ground(col).location = (0, 0, -ROOM)
    scoop_copy(col, BUILT[fid]["LOD0"], (-1.3, 0, 0), rotation=math.radians(-15))
    scoop_copy(col, BUILT[fid]["LOD0"], (1.3, 0, 0), rotation=math.radians(165))
    camera(col, (0, -5.4, 2.0), (0, 0, 0.1), lens_fov=40)
    save(f"close_{fid}", 900, 600)


def tower_mix(ids, count=14):
    """A mixed tower from 30 studs, as a rival sees it: one flavor of each rarity in turn."""
    col = preview_collection()
    sun(col)
    ground(col).location = (0, 0, -ROOM - 1.4)
    for i in range(count):
        fid = ids[i % len(ids)]
        scoop_copy(col, BUILT[fid]["LOD0"], (0, 0, i * SPACING), rotation=math.radians(i * 37))
    top = (count - 1) * SPACING
    d = 30
    camera(col, (0, -d * math.cos(math.radians(10)), top * 0.5 + d * math.sin(math.radians(10))), (0, 0, top * 0.5),
           lens_fov=40)
    save("tower_mix_30studs", 900, 1200)


hide_sources(True)  # preview_scoops.py shows them again at its end; here they would stand at the origin
for shot in globals().get("RARITY_SHOTS", ["lineups"]):
    if shot == "lineups":
        for rarity, ids in GROUPS.items():
            lineup(rarity, ids)
    elif shot == "close":
        for fid in globals().get("CLOSE_IDS", ORDER):
            close(fid)
    elif shot == "tower":
        tower_mix(globals().get("TOWER_IDS", ORDER[::3]))
hide_sources(False)
