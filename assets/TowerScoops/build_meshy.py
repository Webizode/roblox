"""Tower scoops from Meshy (27.11.2026, test with two flavors: royal_cream, tiramisu).

Source: Meshy Image-to-3D (meshy-7.1, texture meshy-7 PBR 2K) from the design's main scoop (img2_3d/input/<fid>_ref.png),
then Meshy's own remesh to about 3,000 triangles (triangle topology), downloaded to meshy/<fid>_remesh.glb. Nothing is
re-baked: Meshy's mesh, UVs, colour and normal map stay Meshy's. Only:
- placed like the scoops it replaces (build_proto.py): 1 unit = 1 stud, Z up, front -Y, the scoop's centre at the
  origin, its lowest point DRIP below it and centred under it, scaled to the old LOD0's footprint (proto2/<fid>_report.json),
  so the tower stacks as before (Config/Tower scoopSpacing); a flat one is stretched up a little (MIN_TOP) so the
  next scoop rests on it instead of over a gap,
- the references have nothing on top (the next scoop sits there): royal_cream from img2_3d/input/
  royal_cream_ref_nocrown.png (crown and cream swirl painted over with a plain dome; the first try with the crown is
  kept as meshy/royal_cream_crown_*),
- LOD0 = the remesh as it is, LOD1 = a Decimate (collapse) copy with about LOD1_TRIS triangles, the same UVs and maps,
- no metalness; roughness from Meshy's map, lifted to a matte cream: its glossiest spots (sauce) stay glossy, metal
  spots (gold) become a glossy 0.4 instead of metal,
- maps at TEX px: color, normal, rough (meshy/textures/<fid>_<kind>.png), used by both LODs.

Run inside Blender (Blender MCP):
    ASSET_DIR = r"<repo>/assets/TowerScoops"
    exec(open(ASSET_DIR + "/build_meshy.py").read())
    build("royal_cream")

Writes meshy/<fid>_report.json (like proto2's), the FBX per LOD to Desktop/roblox-assets/TowerScoops/meshy_scoops/<ROUND> (import into
Studio as TS_<fid>_<LOD>), meshy/<fid>_LOD0.blend is not kept (the scene MeshyScoops in the open file is).
"""

import json
import os
import math

import bpy
import numpy as np
from mathutils import Matrix, Vector

ASSET_DIR = globals().get("ASSET_DIR") or os.path.dirname(bpy.data.filepath)
OUT = os.path.join(ASSET_DIR, "meshy")
TEX_DIR = os.path.join(OUT, "textures")
# one subfolder per round (legendary_epic, rare, uncommon, common), apart from the old scoops' FBX; set ROUND before
# exec'ing this file
ROUND = globals().get("ROUND") or "legendary_epic"
FBX_DIR = os.path.join(os.path.expanduser("~"), "Desktop", "roblox-assets", "TowerScoops", "meshy_scoops", ROUND)
SCENE = "MeshyScoops"

DRIP = 0.86  # Config/TowerScoops dripDepth: the lowest point below the scoop's centre
SPACING = 1.5  # Config/Tower scoopSpacing
# the top at least this far above the centre: the next scoop's lowest point (SPACING - DRIP = 0.64) sinks a little in
MIN_TOP = 0.74
LOD1_TRIS = 300
# narrow_rim: the rim in the lowest RIM_SHARE of the height (fading out up to RIM_FADE) is pulled in to RIM_TO x the
# body's radius, keeping RIM_KEEP of what stuck out beyond that
RIM_SHARE = 0.3
RIM_FADE = 0.45
RIM_TO = 0.8
RIM_KEEP = 0.1
BODY_WIDTH = 2.1  # studs across the body at mid height (ScoopModel.SIZE, the plain ball)
TEX = 1024
# Meshy's roughness (mostly 0.2 to 0.5, glossy all over) onto a matte cream by rank within the model, since the
# glossy parts sit at different values per model (tiramisu's sauce at 0.25 to 0.3): the glossiest ROUGH_RANKS share
# keeps a glossy ROUGH_OUT, the rest goes matte
ROUGH_RANKS = [0, 3, 12, 40, 80, 100]  # percentiles of Meshy's map over the used part of the texture
ROUGH_OUT = [0.25, 0.30, 0.45, 0.80, 0.90, 0.95]
COLOR_SAT = 1.2
COLOR_CONTRAST = 1.08
METAL_ROUGH = 0.4  # where Meshy made metal (gold): glossy instead of metallic


def scene():
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    bpy.context.window.scene = sc
    return sc


def tri_count(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


def pixels(img):
    a = np.empty(len(img.pixels), np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)


def save_png(name, arr, non_color, path):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(arr.astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    img.reload()
    return img


def shrink(arr, size):
    """Box filter down to size x size (Meshy's maps are 2048, a power of two above)."""
    h = arr.shape[0]
    f = h // size
    return arr.reshape(size, f, size, f, arr.shape[2]).mean(axis=(1, 3))


def import_remesh(fid):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, f"{fid}_remesh.glb"))
    meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    assert len(meshes) == 1, f"{fid}: {len(meshes)} meshes in the remesh"
    ob = meshes[0]
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)
    ob.parent = None
    for o in [o for o in bpy.data.objects if o not in before and o is not ob]:
        bpy.data.objects.remove(o, do_unlink=True)
    ob.name = f"MS_{fid}_LOD0"
    return ob


def narrow_rim(ob):
    """The melt rim at the bottom stands out like a plate (user 28.11.2026: the tower looked like stacked plates): in the
    lowest RIM_SHARE of the height, everything further out than RIM_TO x the body's radius (90th percentile at mid height)
    is pulled in to that, softly (RIM_KEEP of what stuck out stays), fading out up to RIM_FADE. UVs stay as they are."""
    vs = ob.data.vertices
    zs = [v.co.z for v in vs]
    lo, hi = min(zs), max(zs)
    h = hi - lo
    mid = sorted(math.hypot(v.co.x, v.co.y) for v in vs if lo + 0.35 * h <= v.co.z <= lo + 0.6 * h)
    body = mid[int(len(mid) * 0.9)] if mid else 1.0
    target = body * RIM_TO
    cx = (max(v.co.x for v in vs) + min(v.co.x for v in vs)) / 2
    cy = (max(v.co.y for v in vs) + min(v.co.y for v in vs)) / 2
    for v in vs:
        t = (v.co.z - lo) / h
        if t >= RIM_FADE:
            continue
        w = 1.0 if t <= RIM_SHARE else (RIM_FADE - t) / (RIM_FADE - RIM_SHARE)
        dx, dy = v.co.x - cx, v.co.y - cy
        r = math.hypot(dx, dy)
        if r <= target or r == 0:
            continue
        nr = target + (r - target) * RIM_KEEP
        f = 1 + ((nr / r) - 1) * w
        v.co.x, v.co.y = cx + dx * f, cy + dy * f
    ob.data.update()
    return body


def place(ob, fid, body=None):
    """Scale so the body (its radius from narrow_rim) is BODY_WIDTH across, or without it to the old LOD0's footprint,
    and put the lowest point DRIP under the origin, centred under it."""
    vs = [v.co for v in ob.data.vertices]
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    size = hi - lo
    if body:
        scale = BODY_WIDTH / (2 * body)
    else:
        with open(os.path.join(ASSET_DIR, "proto2", f"{fid}_report.json")) as f:
            old = json.load(f)["lods"]["LOD0"]["size"]  # Roblox (x, up, depth)
        scale = max(old[0], old[2]) / max(size.x, size.y)
    mid = (lo + hi) / 2
    # a flat scoop is stretched up just so far that the next scoop (SPACING above) rests on it, not over a gap
    stretch = max(1.0, (MIN_TOP + DRIP) / (size.z * scale))
    ob.data.transform(
        Matrix.Translation((0, 0, -DRIP))
        @ Matrix.Diagonal((scale, scale, scale * stretch, 1))
        @ Matrix.Translation((-mid.x, -mid.y, -lo.z))
    )
    ob.data.update()
    return scale, stretch


def maps(fid, ob):
    """Meshy's maps at TEX px: colour as it is, normal as it is, roughness lifted (see ROUGH_*), metal dropped."""
    mat = ob.active_material
    # found by what they feed (the names differ: texture_0 / Image_0, ..._metallic_roughness / Image_1)
    color = normal = mr = None
    for nd in mat.node_tree.nodes:
        if nd.type != "TEX_IMAGE":
            continue
        for link in nd.outputs[0].links:
            kind = link.to_node.type
            if kind == "BSDF_PRINCIPLED" and link.to_socket.name == "Base Color":
                color = nd.image
            elif kind == "NORMAL_MAP":
                normal = nd.image
            elif kind in ("SEPARATE_COLOR", "SEPRGB", "SEPARATE_RGB"):
                mr = nd.image
    assert color and normal and mr, f"{fid}: maps not found"
    os.makedirs(TEX_DIR, exist_ok=True)
    c = shrink(pixels(color), TEX)
    n = shrink(pixels(normal), TEX)
    m = shrink(pixels(mr), TEX)
    used = c[..., :3].sum(-1) > 0.02
    levels = np.percentile(m[..., 1][used], ROUGH_RANKS)
    levels = np.maximum.accumulate(levels + np.arange(len(levels)) * 1e-6)  # strictly rising for np.interp
    rough = np.interp(m[..., 1], levels, ROUGH_OUT)
    rough = np.where(m[..., 2] > 0.5, np.minimum(rough, METAL_ROUGH), rough)
    r = np.dstack([rough, rough, rough, np.ones_like(rough)])
    # stronger colours (user 28.11.2026: pale in the game next to Blender; the game's bright ambient light and haze
    # flatten them): saturation and contrast up, around each pixel's grey and the middle grey
    rgb = c[..., :3]
    grey = (rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
    rgb = grey + (rgb - grey) * COLOR_SAT
    rgb = 0.5 + (rgb - 0.5) * COLOR_CONTRAST
    c[..., :3] = np.clip(rgb, 0, 1)
    c[..., 3] = 1
    n[..., 3] = 1
    out = {}
    out["color"] = save_png(f"MS_{fid}_color", c, False, os.path.join(TEX_DIR, f"{fid}_color.png"))
    out["normal"] = save_png(f"MS_{fid}_normal", n, True, os.path.join(TEX_DIR, f"{fid}_normal.png"))
    out["rough"] = save_png(f"MS_{fid}_rough", r, True, os.path.join(TEX_DIR, f"{fid}_rough.png"))
    stats = {"rough_mean": round(float(rough[used].mean()), 3), "rough_glossy_share": round(float((rough[used] < 0.45).mean()), 3)}
    return out, stats


def game_material(fid, images):
    m = bpy.data.materials.new(f"MS_{fid}")
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    b = next(nd for nd in nodes if nd.type == "BSDF_PRINCIPLED")
    b.inputs["Metallic"].default_value = 0.0
    ct = nodes.new("ShaderNodeTexImage")
    ct.image = images["color"]
    links.new(ct.outputs["Color"], b.inputs["Base Color"])
    rt = nodes.new("ShaderNodeTexImage")
    rt.image = images["rough"]
    links.new(rt.outputs["Color"], b.inputs["Roughness"])
    nt = nodes.new("ShaderNodeTexImage")
    nt.image = images["normal"]
    nm = nodes.new("ShaderNodeNormalMap")
    links.new(nt.outputs["Color"], nm.inputs["Color"])
    links.new(nm.outputs["Normal"], b.inputs["Normal"])
    return m


def decimated(ob, target, name):
    low = ob.copy()
    low.data = ob.data.copy()
    low.name = name
    bpy.context.scene.collection.objects.link(low)
    # Meshy's mesh comes apart at every UV seam (each island has its own vertices): the collapse cannot join across
    # those cuts and leaves shards. Welded first, the UVs stay per corner, so the islands keep their place in the maps.
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(low.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    # welding can leave edges with more than two faces (where Meshy's parts touch); the collapse stops at them (stuck
    # at 400 to 700 triangles), so they are split again
    bmesh.ops.split_edges(bm, edges=[e for e in bm.edges if len(e.link_faces) > 2])
    bm.to_mesh(low.data)
    bm.free()
    mod = low.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.use_collapse_triangulate = True
    ratio = target / tri_count(ob)
    for _ in range(6):
        mod.ratio = ratio
        dg = bpy.context.evaluated_depsgraph_get()
        ev = low.evaluated_get(dg).to_mesh()
        ev.calc_loop_triangles()
        got = len(ev.loop_triangles)
        low.evaluated_get(dg).to_mesh_clear()
        if abs(got - target) <= target * 0.05:
            break
        ratio *= target / max(got, 1)
    bpy.context.view_layer.objects.active = low
    for o in bpy.context.view_layer.objects:
        o.select_set(o is low)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return low


def bounds(ob):
    """Roblox (x, z, -y) size and bounding box centre."""
    vs = [(v.co.x, v.co.z, -v.co.y) for v in ob.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    return [round(hi[i] - lo[i], 4) for i in range(3)], [round((hi[i] + lo[i]) / 2, 4) for i in range(3)]


def export_fbx(ob, fid, lod):
    os.makedirs(FBX_DIR, exist_ok=True)
    for o in bpy.context.view_layer.objects:
        o.select_set(o is ob)
    bpy.context.view_layer.objects.active = ob
    old = ob.name
    ob.name = f"TS_{fid}_{lod}"
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(FBX_DIR, f"{fid}_{lod}.fbx"),
        use_selection=True,
        object_types={"MESH"},
        global_scale=1.0,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_UNITS",
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
        path_mode="AUTO",
        embed_textures=False,
    )
    ob.name = old


def build(fid):
    scene()
    for o in [o for o in bpy.data.objects if o.name.startswith(f"MS_{fid}_")]:
        bpy.data.objects.remove(o, do_unlink=True)
    lod0 = import_remesh(fid)
    body = narrow_rim(lod0)
    scale, stretch = place(lod0, fid, body)
    images, rough = maps(fid, lod0)
    mat = game_material(fid, images)
    for poly in lod0.data.polygons:
        poly.use_smooth = True
    lod0.data.materials.clear()
    lod0.data.materials.append(mat)
    lod1 = decimated(lod0, LOD1_TRIS, f"MS_{fid}_LOD1")
    report = {"source": "meshy", "scale": round(scale, 4), "stretch_up": round(stretch, 3), "roughness": rough, "lods": {}}
    for lod, ob in (("LOD0", lod0), ("LOD1", lod1)):
        size, centre = bounds(ob)
        export_fbx(ob, fid, lod)
        report["lods"][lod] = {"tris": tri_count(ob), "size": size, "centre": centre}
    with open(os.path.join(OUT, f"{fid}_report.json"), "w") as f:
        json.dump(report, f, indent=1)
    print(fid, report)
    return report
