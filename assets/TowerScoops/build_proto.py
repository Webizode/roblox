"""Prototype 2 of the tower scoops (18.11.2026): real geometry instead of painted details.

Run inside Blender (Blender MCP or the Text Editor); every call starts fresh, so exec the file and call what is needed:
    ASSET_DIR = r"<repo>/assets/TowerScoops"
    exec(open(ASSET_DIR + "/build_proto.py").read())
    build("vanilla")          # high poly, LOD0 and LOD1, baked maps, mesh json and FBX
    preview_all()             # renders (preview_proto in this file)

Works in its own scene "Proto2", the old scoops (build_scoops.py, build_rarities.py) stay untouched.

Per flavor:
- a high-poly scoop: one of the base forms in FORMS (smooth, ridged with scoop marks and folds, lumpy, creamy swirl),
  an irregular silhouette and a thick melt rim with drips of random length hanging over the scoop below, a hollow
  underside that sits a little into the dome of the scoop below (Config/Tower scoopSpacing 1.5)
- its toppings as real parts (chunks half sunk into the scoop, cherries, cookies, sauce strands as thick tubes, ...)
- LOD0 (<= LOD0_TRIS triangles, toppings included) and LOD1 (<= LOD1_TRIS) by decimating body and toppings
- maps baked from the high poly onto each LOD (Cycles): ColorMap with ambient occlusion baked in, NormalMap,
  RoughnessMap (sauces and cherries glossy, the ice matte and creamy)

1 Blender unit = 1 stud, Z up, front -Y, the scoop's centre at the origin, its lowest drip at -DRIP (Config/TowerScoops
dripDepth). Roblox coordinates in the json: (x, z, -y).
"""

import json
import math
import os
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

ASSET_DIR = globals().get("ASSET_DIR") or os.path.dirname(bpy.data.filepath)
OUT = os.path.join(ASSET_DIR, "proto2")
FBX_DIR = os.path.join(os.path.expanduser("~"), "Desktop", "roblox-assets", "TowerScoops", "proto2")
SCENE = "Proto2"

DRIP = 0.86  # Config/TowerScoops dripDepth: the lowest drip below the scoop's centre
DOME = 1.0  # the dome's top above the centre
SPACING = 1.5
LOD0_TRIS = 1200
LOD1_TRIS = 250
TEX = {"LOD0": 1024, "LOD1": 256}


def srgb(hexstr):
    h = hexstr.lstrip("#")
    c = [int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def scene():
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    bpy.context.window.scene = sc
    return sc


def collection(name):
    sc = scene()
    col = bpy.data.collections.get(name)
    if col:
        for ob in list(col.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
    else:
        col = bpy.data.collections.new(name)
    if col.name not in sc.collection.children:
        sc.collection.children.link(col)
    col.hide_render = False
    return col


# ---------------------------------------------------------------------------------------------------------- forms

FORMS = {
    # lobes: count; jitter of their places; drip lengths; width spread. field: the surface detail on the dome.
    "smooth": {"lobes": 7, "jitter": 0.12, "drip": (0.10, 0.30), "width": (0.8, 1.2), "field": "smooth", "wobble": 0.03},
    "ridged": {"lobes": 8, "jitter": 0.15, "drip": (0.08, 0.26), "width": (0.7, 1.2), "field": "ridged", "wobble": 0.035},
    "lumpy": {"lobes": 6, "jitter": 0.18, "drip": (0.10, 0.28), "width": (0.8, 1.3), "field": "lumpy", "wobble": 0.05},
    "swirl": {"lobes": 7, "jitter": 0.10, "drip": (0.14, 0.32), "width": (0.85, 1.15), "field": "swirl", "wobble": 0.03},
}


def make_lobes(form, seed):
    rng = random.Random(seed)
    n = form["lobes"]
    out = []
    for i in range(n):
        centre = (i + rng.uniform(-form["jitter"], form["jitter"])) / n * 2 * math.pi
        out.append((centre, rng.uniform(*form["width"]) * math.pi / n, rng.uniform(*form["drip"])))
    return out


def lobe_at(theta, lobes):
    """L: 1 in a lobe's middle, 0 in the narrow notch between two; d: that lobe's drip length."""
    best, d = 0.0, 0.0
    for centre, half, length in lobes:
        delta = (theta - centre + math.pi) % (2 * math.pi) - math.pi
        x = min(1.0, abs(delta) / half)
        v = math.cos(x * math.pi / 2) ** 0.4
        if v > best:
            best, d = v, length
    return best, d


def profile(L, d):
    """Control points (r, z) from the top pole down over the dome, the melt roll, the drip, into the hollow. The hollow's
    apex is a little under the top of the scoop below (DOME - SPACING), so a stacked scoop sits into the one below."""
    return [
        (0.0, DOME),
        (0.42, DOME - 0.05),
        (0.74, DOME - 0.24),
        (0.90, 0.45),
        (0.95, 0.10),  # the dome is a ball down to its widest, under the centre
        (0.93, -0.16),  # a soft step into the melt roll
        (1.02 + 0.04 * L, -0.36 - 0.18 * d * L),  # the melt roll bulges out
        (1.07 + 0.03 * L, -0.54 - d * (0.4 + 0.6 * L)),  # the drip's round end
        (0.92 + 0.05 * L, -0.70 - d * (0.5 + 0.5 * L)),
        (0.66, -0.64 - 0.1 * d * L),  # the inner lip
        (0.42, -0.58),
        (0.0, DOME - SPACING - 0.08),  # the hollow's apex, 0.08 into the scoop below
    ]


def catmull(points, steps):
    out = []
    n = len(points)
    for i in range(n - 1):
        p0, p1, p2, p3 = points[max(i - 1, 0)], points[i], points[i + 1], points[min(i + 2, n - 1)]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(
                tuple(
                    0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                           + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3)
                    for k in range(2)
                )
            )
    out.append(points[-1])
    return out


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def field(kind, p, seed):
    """Displacement along the normal on the dome (studs)."""
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    if kind == "smooth":
        return 0.014 * noise.noise(p * 2.5 + off)
    if kind == "lumpy":
        return 0.055 * noise.noise(p * 2.0 + off) + 0.025 * noise.noise(p * 4.5 + off)
    if kind == "ridged":
        # the scoop's drag marks: curved ridges across the dome with a sharp fold between two, and a soft wobble
        a = Vector((0.8, 0.6, 0.0))
        b = Vector((-0.6, 0.8, 0.0))
        s = p.z + 0.3 * p.dot(a) + 0.35 * p.dot(b) ** 2
        g = abs(math.sin(math.pi * 1.8 * s))
        return 0.07 * (g ** 0.6 - 0.55) + 0.012 * noise.noise(p * 3 + off)
    if kind == "swirl":
        r = max(1e-4, p.length)
        phi = math.acos(max(-1.0, min(1.0, (p.z - 0.08) / r)))
        theta = math.atan2(p.x, -p.y)
        return 0.036 * smoothstep(0.25, 0.6, phi) * math.sin(3 * theta + 10 * phi) + 0.01 * noise.noise(p * 3 + off)
    return 0.0


def body_mesh(name, form_name, seed, around=192, steps=9):
    form = FORMS[form_name]
    lobes = make_lobes(form, seed)
    bm = bmesh.new()
    grid = []
    rows = None
    for s in range(around):
        theta = 2 * math.pi * s / around
        L, d = lobe_at(theta, lobes)
        rows_s = catmull(profile(L, d), steps)
        rows = rows_s
        grid.append(rows_s)
    nrows = len(rows)
    verts = []  # verts[row][s]
    off = Vector((seed * 0.7, seed * 1.3, 0))
    for row in range(1, nrows - 1):
        line = []
        for s in range(around):
            theta = 2 * math.pi * s / around
            r, z = grid[s][row]
            dirv = Vector((math.sin(theta), -math.cos(theta), 0))
            wob = 1 + form["wobble"] * noise.noise(Vector((dirv.x * 1.4, dirv.y * 1.4, z * 1.2)) + off)
            line.append(bm.verts.new((r * wob * dirv.x, r * wob * dirv.y, z)))
        verts.append(line)
    top = bm.verts.new((0, 0, DOME))
    apex = bm.verts.new((0, 0, grid[0][-1][1]))
    for s in range(around):
        t = (s + 1) % around
        bm.faces.new((top, verts[0][s], verts[0][t]))
        bm.faces.new((apex, verts[-1][t], verts[-1][s]))
        for row in range(len(verts) - 1):
            bm.faces.new((verts[row][s], verts[row + 1][s], verts[row + 1][t], verts[row][t]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    moves = []
    for v in bm.verts:
        w = smoothstep(-0.1, 0.25, v.co.z)  # the detail only on the dome
        rim = 1 - w
        f = w * field(form["field"], v.co.copy(), seed) + rim * 0.012 * noise.noise(v.co * 4 + off)
        moves.append(v.normal * f)
    for v, m in zip(bm.verts, moves):
        v.co += m
    low = min(v.co.z for v in bm.verts)
    k = (DRIP - 0.6) / (-low - 0.6)  # only the drips' ends move, the hollow stays where it sits into the scoop below
    for v in bm.verts:
        if v.co.z < -0.6:
            v.co.z = -0.6 + (v.co.z + 0.6) * k
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    return mesh


# ------------------------------------------------------------------------------------------------------- materials


def material(name, color, roughness, specks=None, metallic=0.0, clearcoat=0.0):
    """specks: (colour, voronoi scale, size 0..1) small flecks over the colour (vanilla beans, crumbs, gold flakes)."""
    m = bpy.data.materials.get(name)
    if m:
        bpy.data.materials.remove(m)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    b = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Specular IOR Level"].default_value = 0.4
    if clearcoat and "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = clearcoat
    base = srgb(color) + [1.0]
    if not specks:
        b.inputs["Base Color"].default_value = base
        return m
    coord = nodes.new("ShaderNodeTexCoord")
    vor = nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = specks[1]
    links.new(coord.outputs["Object"], vor.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = specks[2] * 0.6
    ramp.color_ramp.elements[0].color = (1, 1, 1, 1)
    ramp.color_ramp.elements[1].position = specks[2]
    ramp.color_ramp.elements[1].color = (0, 0, 0, 1)
    links.new(vor.outputs["Distance"], ramp.inputs["Fac"])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    sock = {s.identifier: s for s in mix.inputs}
    sock["A_Color"].default_value = base
    sock["B_Color"].default_value = srgb(specks[0]) + [1.0]
    links.new(ramp.outputs["Color"], sock["Factor_Float"])
    links.new(next(s for s in mix.outputs if s.identifier == "Result_Color"), b.inputs["Base Color"])
    return m


# -------------------------------------------------------------------------------------------------------- toppings


class Surface:
    """Rays from inside the scoop onto its high-poly surface: where toppings sit and sauces run."""

    def __init__(self, ob):
        self.tree = BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())
        self.origin = Vector((0, 0, 0.1))

    def at(self, theta_deg, elev_deg):
        t, e = math.radians(theta_deg), math.radians(elev_deg)
        d = Vector((math.sin(t) * math.cos(e), -math.cos(t) * math.cos(e), math.sin(e)))
        hit, normal, _, _ = self.tree.ray_cast(self.origin, d, 5.0)
        if hit is None:
            return self.origin + d, d
        return hit, normal.normalized()


def obj_from_bm(name, bm, mat, smooth=True):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    mesh.materials.append(mat)
    return bpy.data.objects.new(name, mesh)


def frame(normal, spin=0.0):
    """A rotation that turns +Z onto `normal`, spun by `spin` about it."""
    q = Vector((0, 0, 1)).rotation_difference(normal)
    return q.to_matrix().to_4x4() @ Matrix.Rotation(spin, 4, "Z")


def chunk(name, surf, theta, elev, size, mat, seed, sink=0.45, flat=0.8, sharp=False):
    """An irregular piece (cookie, chocolate, fruit bit) sunk `sink` of its height into the scoop."""
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2 if not sharp else 1, radius=1.0)
    off = Vector((seed * 1.1, seed * 0.3, seed * 2.7))
    for v in bm.verts:
        v.co *= 1 + 0.28 * noise.noise(v.co * 1.6 + off)
        v.co.x *= size * rng.uniform(0.9, 1.25)
        v.co.y *= size * rng.uniform(0.8, 1.1)
        v.co.z *= size * flat
    p, n = surf.at(theta, elev)
    m = Matrix.Translation(p - n * size * flat * (sink * 2 - 1)) @ frame(n, rng.uniform(0, 6.28))
    m = m @ Matrix.Rotation(rng.uniform(-0.35, 0.35), 4, "X")
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return obj_from_bm(name, bm, mat, smooth=not sharp)


def tube(name, points, radius, mat, sides=10, taper=0.18, radii=None, flat=1.0):
    """A thick strand along `points` (Vectors): rounded at both ends. flat < 1 squashes it towards the scoop (a sauce
    lies flat on the ice: `flat` of its width is its height, measured from the scoop's centre outwards)."""
    pts = [Vector(p) for p in points]
    # smooth the path a little (Chaikin)
    for _ in range(2):
        new = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            new += [a.lerp(b, 0.25), a.lerp(b, 0.75)]
        new.append(pts[-1])
        pts = new
    n = len(pts)
    bm = bmesh.new()
    rings = []
    prev_side = None
    for i, p in enumerate(pts):
        tangent = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        side = tangent.cross((p - Vector((0, 0, 0.1))).normalized() if flat < 1 else Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = tangent.cross(Vector((1, 0, 0)))
        side.normalize()
        if prev_side is not None and side.dot(prev_side) < 0:
            side = -side
        prev_side = side
        up = side.cross(tangent).normalized()
        t = i / (n - 1)
        end = min(t, 1 - t) / taper
        r = (radii[i * len(radii) // n] if radii else radius) * (math.sin(min(1.0, end) * math.pi / 2) ** 0.6 if end < 1 else 1)
        r = max(r, radius * 0.08)
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ring.append(bm.verts.new(p + (side * math.cos(a) + up * math.sin(a) * flat) * r))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(sides):
            j = (k + 1) % sides
            bm.faces.new((rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]))
    for ring, tip in ((rings[0], pts[0]), (rings[-1], pts[-1])):
        c = bm.verts.new(tip)
        for k in range(sides):
            bm.faces.new((c, ring[k], ring[(k + 1) % sides]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj_from_bm(name, bm, mat)


def sauce(name, surf, path, radius, mat, drips=(), lift=0.12):
    """A thick sauce strand lying on the scoop along `path` [(theta, elev)], a third sunk in, with drips running down
    from some of its points: drips [(index into path, length in degrees)]."""
    pts = []
    for theta, elev in path:
        p, n = surf.at(theta, elev)
        pts.append(p + n * radius * lift)
    parts = [tube(name, pts, radius, mat, sides=10, taper=0.08, flat=0.5)]
    for k, (index, length) in enumerate(drips):
        theta, elev = path[index]
        run = []
        for s in range(7):
            p, n = surf.at(theta + s * 1.5, elev - length * s / 6)
            run.append(p + n * radius * lift * 0.8)
        radii = [radius * 0.8] * 5 + [radius * 1.05] * 2  # a drop at the end
        parts.append(tube(f"{name}_drip{k}", run, radius * 0.8, mat, sides=8, taper=0.12, radii=radii, flat=0.6))
    return parts


def sphere(name, centre, radius, mat, dimple=0.0, seg=24, rings=14, squash=1.0, frame_m=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=radius)
    for v in bm.verts:
        v.co.z *= squash
        if dimple and v.co.z > 0:
            k = max(0.0, 1 - Vector((v.co.x, v.co.y)).length / (radius * 0.45))
            v.co.z -= dimple * radius * k * k
    m = Matrix.Translation(centre) @ (frame_m or Matrix.Identity(4))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return obj_from_bm(name, bm, mat)


def leaf(name, base, direction, length, width, mat, lift=0.25):
    """A bent leaf from `base` towards `direction` (two-sided, thin)."""
    bm = bmesh.new()
    d = direction.normalized()
    side = d.cross(Vector((0, 0, 1))).normalized()
    up = side.cross(d).normalized()
    steps = 8
    top, bot = [], []
    for i in range(steps + 1):
        t = i / steps
        w = width * math.sin(math.pi * t) ** 0.8
        along = base + d * length * t + up * (lift * length * math.sin(math.pi * t * 0.9))
        for sgn, lst in ((1, top), (-1, bot)):
            row = []
            for k in (-1, 0, 1):
                row.append(bm.verts.new(along + side * w * k + up * (0.015 * sgn - 0.05 * length * abs(k))))
            lst.append(row)
    for lst, flip in ((top, False), (bot, True)):
        for i in range(steps):
            for k in range(2):
                q = (lst[i][k], lst[i][k + 1], lst[i + 1][k + 1], lst[i + 1][k])
                bm.faces.new(q[::-1] if flip else q)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj_from_bm(name, bm, mat)


def disc(name, centre, normal, radius, thick, mat, ridges=0, spin=0.0, half=False, filling=None, rim=None, seg=40):
    """A cookie: a short cylinder with a ridged edge; `filling` (material) puts a cream layer in the middle
    (a sandwich cookie); `half` breaks it in half with a ragged edge; `rim` (material) colours its whole edge (a fruit
    slice's peel); `seg` points round it (6: a honeycomb cell)."""
    bm = bmesh.new()
    layers = [(-thick / 2, 1.0), (-thick * 0.14, 1.0), (-thick * 0.1, 0.96), (thick * 0.1, 0.96), (thick * 0.14, 1.0), (thick / 2, 1.0)]
    rings = []
    for z, s in layers:
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            if half and math.sin(a) < -0.05:
                a = math.atan2(-0.05, math.cos(a))  # the broken edge, a straight-ish line
            r = radius * s * (1 + (0.04 * math.cos(ridges * a) if ridges else 0))
            if half and abs(math.sin(a)) < 0.06:
                r *= 0.95 + 0.08 * noise.noise(Vector((k * 0.7, z * 9, 1)))
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(seg):
            j = (k + 1) % seg
            bm.faces.new((rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]))
    def relief(f, a):
        """The pressed pattern of a sandwich cookie's face: a raised ring near the edge, ticks round the middle and a
        raised medallion (0 = flat)."""
        if not ridges:
            return 0.0
        if 0.74 < f < 0.84:
            return 0.016
        if 0.46 < f < 0.66 and math.cos(14 * a) > 0.2:
            return 0.012
        if f < 0.36:
            return 0.012
        return 0.0

    for ring, z, flip in ((rings[0], -thick / 2, True), (rings[-1], thick / 2, False)):
        sign = -1 if flip else 1
        outer = ring
        for f in (0.9, 0.84, 0.74, 0.66, 0.56, 0.46, 0.36, 0.24, 0.12):
            inner = []
            for k, v in enumerate(ring):
                a = math.atan2(v.co.y, v.co.x)
                inner.append(bm.verts.new((v.co.x * f, v.co.y * f, z + sign * relief(f, a))))
            for k in range(seg):
                j = (k + 1) % seg
                q = (outer[k], outer[j], inner[j], inner[k])
                bm.faces.new(q[::-1] if flip else q)
            outer = inner
        c = bm.verts.new((0, 0, z + sign * relief(0.0, 0.0)))
        for k in range(seg):
            f = (c, outer[k], outer[(k + 1) % seg])
            bm.faces.new(f[::-1] if flip else f)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if filling is not None:
        # the cream between the two biscuit halves: faces of the middle band
        for f in bm.faces:
            zc = sum(v.co.z for v in f.verts) / len(f.verts)
            f.material_index = 1 if abs(zc) < thick * 0.13 and abs(f.normal.z) < 0.5 else 0
    elif rim is not None:
        for f in bm.faces:
            f.material_index = 1 if abs(f.normal.z) < 0.5 else 0
    m = Matrix.Translation(centre) @ frame(normal, spin)
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    ob = obj_from_bm(name, bm, mat)
    if filling is not None or rim is not None:
        ob.data.materials.append(filling if filling is not None else rim)
    return ob


def dollop(name, centre, radius, height, mat, arms=6, twist=2.2, seed=0):
    """Whipped cream: a star-shaped swirl narrowing to a curled tip."""
    bm = bmesh.new()
    seg, rows = 24, 9
    rings = []
    for i in range(rows):
        t = i / (rows - 1)
        r = radius * (1 - t) ** 0.8 * (0.9 + 0.1 * math.sin(t * 9))
        z = height * t
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            rr = r * (1 + 0.16 * math.cos(arms * a + twist * t * 6.28))
            bend = 0.12 * radius * t * t
            ring.append(bm.verts.new((centre.x + rr * math.cos(a) + bend, centre.y + rr * math.sin(a), centre.z + z)))
        rings.append(ring)
    for i in range(rows - 1):
        for k in range(seg):
            j = (k + 1) % seg
            bm.faces.new((rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]))
    tip = bm.verts.new((centre.x + 0.16 * radius, centre.y, centre.z + height * 1.04))
    # open at the bottom (it sits in the scoop): an open edge also keeps the decimation from caving the swirl in
    for k in range(seg):
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % seg], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj_from_bm(name, bm, mat)


def crown(name, centre, radius, height, mat, points=5, tilt=0.2):
    """A small gold crown: a band with points and a ball on each, tilted a little."""
    bm = bmesh.new()
    seg = points * 6
    bottom, top = [], []
    thick = radius * 0.12
    for k in range(seg):
        a = 2 * math.pi * k / seg
        phase = (k % 6) / 6
        h = height * (0.55 + 0.45 * max(0.0, 1 - abs(phase - 0.5) * 4) ** 1.2)
        for lst, rr, z in ((bottom, radius, 0.0), (top, radius * 1.08, h)):
            lst.append((rr, a, z))
    outer_b = [bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for r, a, z in bottom]
    outer_t = [bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for r, a, z in top]
    inner_b = [bm.verts.new(((r - thick) * math.cos(a), (r - thick) * math.sin(a), z)) for r, a, z in bottom]
    inner_t = [bm.verts.new(((r - thick) * math.cos(a), (r - thick) * math.sin(a), z)) for r, a, z in top]
    for k in range(seg):
        j = (k + 1) % seg
        bm.faces.new((outer_b[k], outer_b[j], outer_t[j], outer_t[k]))
        bm.faces.new((inner_b[j], inner_b[k], inner_t[k], inner_t[j]))
        bm.faces.new((outer_t[k], outer_t[j], inner_t[j], inner_t[k]))
        bm.faces.new((inner_b[k], inner_b[j], outer_b[j], outer_b[k]))
    m = Matrix.Translation(centre) @ Matrix.Rotation(tilt, 4, "X")
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    ob = obj_from_bm(name, bm, mat, smooth=False)
    balls = []
    for k in range(points):
        a = 2 * math.pi * (k * 6 + 3) / seg
        p = m @ Vector((radius * 1.08 * math.cos(a), radius * 1.08 * math.sin(a), height * 1.03))
        balls.append(sphere(f"{name}_ball{k}", p, radius * 0.13, mat, seg=8, rings=5))
    return [ob] + balls


def gem(name, centre, normal, size, mat, spin=0.0, sink=0.35):
    """A cut crystal: a stretched octahedron with a flat table, flat-shaded, sunk into the scoop."""
    bm = bmesh.new()
    seg = 6
    top = [bm.verts.new((size * 0.55 * math.cos(2 * math.pi * k / seg), size * 0.55 * math.sin(2 * math.pi * k / seg), size * 0.55)) for k in range(seg)]
    mid = [bm.verts.new((size * math.cos(2 * math.pi * (k + 0.5) / seg), size * math.sin(2 * math.pi * (k + 0.5) / seg), size * 0.25)) for k in range(seg)]
    tip = bm.verts.new((0, 0, -size * 1.1))
    table = bm.faces.new(top)
    for k in range(seg):
        j = (k + 1) % seg
        bm.faces.new((top[k], mid[k], top[j]))
        bm.faces.new((mid[k], mid[j], top[j]))
        bm.faces.new((mid[k], tip, mid[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    m = Matrix.Translation(centre - normal * size * sink) @ frame(normal, spin) @ Matrix.Rotation(0.5, 4, "X")
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return obj_from_bm(name, bm, mat, smooth=False)


# --------------------------------------------------------------------------------------------------------- flavors
# Every flavor: a form, a seed (its own lobes and noise), the body material and its toppings. Toppings sit on the
# sides or near the top inside radius 0.55, so on a tower the scoop above swallows what is on top and nothing pokes
# out of it. weight: the share of the toppings' triangle budget; lod1: kept on LOD1.


def flavor_vanilla(surf):
    bean = material("P_vanilla_bean", "#3B2416", 0.45)
    pods = []
    for k, path in enumerate(([(-40, 10), (-18, 30), (8, 46), (30, 54)], [(-10, 18), (12, 34), (34, 40), (58, 38)])):
        pts = []
        for theta, elev in path:
            p, n = surf.at(theta, elev)
            pts.append(p + n * 0.035)
        pods.append((tube(f"vanilla_pod{k}", pts, 0.042, bean, sides=8, taper=0.35), 1.0, k == 0))
    return {
        "form": "ridged",
        "seed": 11,
        "body": material("P_vanilla", "#F9DCA8", 0.62, specks=("#5A3A22", 9, 0.07)),
        "toppings": pods,
    }


def flavor_cookie(surf):
    # broken cookie pieces stuck in edgewise (a half cookie, the chocolate chips on it), and small crumbs
    dough = material("P_cookie_piece", "#B9783F", 0.85, specks=("#3A2214", 5, 0.2))
    crumb = material("P_cookie_crumb", "#8A5530", 0.85)
    out = []
    for k, (theta, elev, size, lean) in enumerate(((-18, 14, 0.3, 0.9), (95, 26, 0.27, 1.1), (215, 10, 0.29, 0.8))):
        p, n = surf.at(theta, elev)
        side = n.cross(Vector((0, 0, 1))).normalized()
        axis = (n * math.cos(lean) + side * math.sin(lean)).normalized()  # the cookie's face, leaning out of the scoop
        out.append((disc(f"cookie_piece{k}", p - n * 0.06, axis, size, 0.09, dough, ridges=0, spin=k * 1.7, half=True), 1.4, True))
    for k, (theta, elev, size) in enumerate(((40, 40, 0.09), (150, 4, 0.08), (285, 30, 0.1))):
        out.append((chunk(f"cookie_crumb{k}", surf, theta, elev, size, crumb, seed=k + 3, sink=0.5, flat=0.7, sharp=True), 0.4, False))
    return {
        "form": "lumpy",
        "seed": 23,
        "body": material("P_cookie", "#D9AE80", 0.7, specks=("#6B4325", 7, 0.09)),
        "toppings": out,
    }


def flavor_cherry(surf):
    red = material("P_cherry_fruit", "#C0102A", 0.12, clearcoat=1.0)
    stem_m = material("P_cherry_stem", "#6E9A2A", 0.5)
    leaf_m = material("P_cherry_leaf", "#7BC23A", 0.45)
    sauce_m = material("P_cherry_sauce", "#C8162F", 0.1, clearcoat=1.0)
    out = []
    p1, n1 = surf.at(-28, 14)
    p2, n2 = surf.at(-2, 8)
    c1 = p1 + n1 * 0.13
    c2 = p2 + n2 * 0.12
    out.append((sphere("cherry_a", c1, 0.22, red, dimple=0.35, frame_m=frame((n1 + Vector((0, 0, 1.6))).normalized())), 1.4, True))
    out.append((sphere("cherry_b", c2, 0.21, red, dimple=0.35, frame_m=frame((n2 + Vector((0, 0, 1.6))).normalized())), 1.4, True))
    top, tn = surf.at(-12, 34)
    joint = top + tn * 0.16
    for k, c in enumerate((c1, c2)):
        start = c + (c - Vector((0, 0, 0))).normalized() * 0.02 + Vector((0, 0, 0.2))
        mid = start.lerp(joint, 0.5) + Vector((0, 0, 0.06))
        out.append((tube(f"cherry_stem{k}", [start, mid, joint], 0.028, stem_m, sides=6, taper=0.05), 0.35, k == 0))
    out.append((leaf("cherry_leaf", joint, Vector((-0.8, -0.3, 0.15)), 0.42, 0.13, leaf_m), 0.4, False))
    out.append(
        (
            sauce("cherry_sauce", surf, [(30, 58), (60, 40), (95, 30), (130, 26), (165, 30), (200, 40)], 0.1, sauce_m,
                  drips=((2, 30),))[0],
            1.2,
            False,
        )
    )
    s2 = sauce("cherry_sauce2", surf, [(150, 2), (190, 12), (230, 16), (270, 10), (310, 2)], 0.095, sauce_m,
               drips=((1, 26), (3, 22)))
    out += [(s, 1.0 if i == 0 else 0.4, False) for i, s in enumerate(s2)]
    for k, (theta, elev) in enumerate(((60, 6), (115, 50), (250, 40))):
        out.append((chunk(f"cherry_bit{k}", surf, theta, elev, 0.07, red, seed=k + 40, sink=0.5, flat=0.6, sharp=True), 0.2, False))
    return {
        "form": "swirl",
        "seed": 31,
        "body": material("P_cherry", "#FAC6CE", 0.45, specks=("#E04A64", 7, 0.07)),
        "toppings": out,
    }


def flavor_cookies_cream(surf):
    biscuit = material("P_cc_biscuit", "#3D2820", 0.7)
    cream = material("P_cc_filling", "#F4EEE2", 0.6)
    choc = material("P_cc_sauce", "#4A2414", 0.12, clearcoat=0.8)
    out = []
    p, n = surf.at(-30, 18)
    out.append((disc("cc_cookie", p + n * 0.02, (n + Vector((0, -0.2, 0.25))).normalized(), 0.36, 0.17, biscuit, ridges=36, spin=0.4, filling=cream), 2.6, True))
    p, n = surf.at(8, 4)
    out.append((disc("cc_half", p + n * 0.0, (n + Vector((0.3, 0, 0.5))).normalized(), 0.3, 0.15, biscuit, ridges=30, spin=2.0, half=True, filling=cream), 1.8, False))
    s1 = sauce("cc_sauce", surf, [(20, 52), (60, 44), (100, 36), (140, 34), (180, 40), (220, 48)], 0.1, choc, drips=((2, 26),))
    s2 = sauce("cc_sauce2", surf, [(90, 4), (130, 12), (170, 14), (210, 10), (250, 4), (290, 6)], 0.095, choc, drips=((3, 22),))
    out += [(s, 1.0 if i == 0 else 0.4, False) for i, s in enumerate(s1 + s2)]
    for k, (theta, elev, size) in enumerate(((55, 20, 0.11), (200, 26, 0.12), (275, 14, 0.1), (130, 54, 0.09), (160, 6, 0.08), (240, 44, 0.09), (320, 30, 0.1), (100, 12, 0.08))):
        out.append((chunk(f"cc_crumb{k}", surf, theta, elev, size, biscuit, seed=k + 60, sink=0.5, flat=0.7, sharp=True), 0.25, False))
    return {
        "form": "ridged",
        "seed": 47,
        "body": material("P_cc", "#F3EADB", 0.6, specks=("#2B1C17", 6, 0.12)),
        "toppings": out,
    }


def flavor_royal_cream(surf):
    gold = material("P_royal_gold", "#F7BE2E", 0.2, clearcoat=1.0)  # no metal: a metal bakes black into the ColorMap
    purple = material("P_royal_sauce", "#7A1FA8", 0.12, clearcoat=1.0)
    whip = material("P_royal_whip", "#FBEBCB", 0.55)
    crystal = material("P_royal_gem", "#9B3DE0", 0.08, clearcoat=1.0)
    out = []
    top, tn = surf.at(0, 80)
    out.append((dollop("royal_whip", top - Vector((0, 0, 0.04)), 0.5, 0.44, whip), 1.6, True))
    for k, part in enumerate(crown("royal_crown", top + Vector((0.02, 0.06, 0.2)), 0.2, 0.2, gold, tilt=0.25)):
        out.append((part, 1.0 if k == 0 else 0.15, False))  # LOD1 (from 40 studs): the crown is too small to matter
    s = sauce("royal_sauce", surf, [(-80, -8), (-50, 4), (-20, 18), (10, 32), (40, 44), (75, 54), (115, 60)], 0.12, purple,
              drips=((2, 24),))
    out += [(x, 1.4 if i == 0 else 0.4, i == 0) for i, x in enumerate(s)]
    for k, (theta, elev, size) in enumerate(((-35, 2, 0.15), (60, 52, 0.11), (200, 18, 0.13))):
        p, n = surf.at(theta, elev)
        out.append((gem(f"royal_gem{k}", p, n, size, crystal, spin=k * 1.3), 0.5, False))
    return {
        "form": "smooth",
        "seed": 5,
        "body": material("P_royal", "#F6E2BC", 0.55, specks=("#E8A321", 7, 0.08)),
        "toppings": out,
    }


PROTOS = ["vanilla", "cookie", "cherry", "cookies_cream", "royal_cream"]
FORM_OF = {"vanilla": "ridged", "cookie": "lumpy", "cherry": "swirl", "cookies_cream": "ridged", "royal_cream": "smooth"}
SEED_OF = {"vanilla": 11, "cookie": 23, "cherry": 31, "cookies_cream": 47, "royal_cream": 5}


# ------------------------------------------------------------------------------------------------------ the build


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def decimated_copy(ob, target, name, keep_shape=True):
    """A copy of `ob` decimated to about `target` triangles (collapse)."""
    copy = ob.copy()
    copy.data = ob.data.copy()
    copy.name = name
    bpy.context.scene.collection.objects.link(copy)
    copy.hide_viewport = False  # a hidden object is not evaluated: the modifier would do nothing
    copy.hide_set(False)
    tris = tri_count(copy)

    def extent(mesh):
        cs = [v.co for v in mesh.vertices]
        return [max(c[k] for c in cs) - min(c[k] for c in cs) for k in range(3)]

    full = extent(copy.data)
    goal = target
    while target < tris:
        mod = copy.modifiers.new("Dec", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = max(0.001, goal / tris)
        mod.use_collapse_triangulate = True
        dg = bpy.context.evaluated_depsgraph_get()
        mesh = bpy.data.meshes.new_from_object(copy.evaluated_get(dg))
        copy.modifiers.clear()
        # the collapse can cave a shape in (the whipped cream lost its whole lower half): then keep more triangles
        if not keep_shape or all(e >= f * 0.8 for e, f in zip(extent(mesh), full)) or goal >= tris * 0.5:
            old = copy.data
            copy.data = mesh
            bpy.data.meshes.remove(old)
            break
        bpy.data.meshes.remove(mesh)
        goal = int(goal * 1.35) + 4
    bpy.context.scene.collection.objects.unlink(copy)
    return copy


def join(objects, name, col):
    bm = bmesh.new()
    mats = []
    for ob in objects:
        mesh = ob.data
        offset = len(mats)
        for m in mesh.materials:
            mats.append(m)
        tmp = bmesh.new()
        tmp.from_mesh(mesh)
        tmp.transform(ob.matrix_world)
        for f in tmp.faces:
            f.material_index += offset
        tmp_mesh = bpy.data.meshes.new("tmp")
        tmp.to_mesh(tmp_mesh)
        tmp.free()
        bm.from_mesh(tmp_mesh)
        bpy.data.meshes.remove(tmp_mesh)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for m in mats:
        mesh.materials.append(m)
    ob = bpy.data.objects.new(name, mesh)
    col.objects.link(ob)
    return ob


def set_engine(sc, name):
    try:
        sc.render.engine = name
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE_NEXT"


def bake_image(name, size, non_color=False):
    img = bpy.data.images.get(name)
    if img:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=non_color)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def bake_maps(fid, lod, low, high, size):
    """Bakes colour (with AO), normal and roughness from `high` onto `low`; writes the PNGs; returns their paths."""
    sc = bpy.context.scene
    set_engine(sc, "CYCLES")
    sc.cycles.device = "CPU"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.get_devices()
        if any(d.type != "CPU" for d in prefs.devices):
            sc.cycles.device = "GPU"
    except Exception:
        pass
    sc.cycles.samples = 24
    sc.world = sc.world or bpy.data.worlds.get("P2_World") or bpy.data.worlds.new("P2_World")
    if sc.world:
        sc.world.light_settings.distance = 0.25  # AO only from what is close: folds, toppings, the melt roll
    mat = bpy.data.materials.new(f"Bake_{fid}_{lod}")
    mat.use_nodes = True
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    mat.node_tree.nodes.active = tex
    low.data.materials.clear()
    low.data.materials.append(mat)
    for ob in bpy.context.view_layer.objects:
        ob.select_set(False)
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bake = sc.render.bake
    bake.use_selected_to_active = True
    # decimating pulls the low poly inside the high one on round parts: the cage must start outside it
    bake.cage_extrusion = 0.2 if size >= 512 else 0.3
    bake.max_ray_distance = 0.5 if size >= 512 else 0.8
    bake.margin = 6 if size >= 512 else 3
    out = {}
    results = {}
    for kind, btype, non_color in (("color", "DIFFUSE", False), ("ao", "AO", True), ("normal", "NORMAL", True), ("rough", "ROUGHNESS", True)):
        img = bake_image(f"P2_{fid}_{lod}_{kind}", size, non_color)
        tex.image = img
        # AO from the low poly itself (toppings included), not projected: a ray that starts inside the high poly
        # would see its hollow and bake black patches
        bake.use_selected_to_active = btype != "AO"
        high.select_set(btype != "AO")
        # only what is baked may render: the other scoops sit at the same origin and would shade this one
        for ob in sc.objects:
            ob.hide_render = ob not in ((low,) if btype == "AO" else (low, high))
        sc.cycles.samples = 128 if btype == "AO" else 8
        if btype == "DIFFUSE":
            bake.use_pass_direct = False
            bake.use_pass_indirect = False
            bake.use_pass_color = True
        bpy.ops.object.bake(type=btype)
        px = np.empty(size * size * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        results[kind] = (img, px.reshape(size, size, 4))
    color_img, color = results["color"]
    ao = results["ao"][1][..., 0]
    ao = (ao + np.roll(ao, 1, 0) + np.roll(ao, -1, 0) + np.roll(ao, 1, 1) + np.roll(ao, -1, 1)) / 5  # less grain
    ao = ao[..., None]
    color[..., :3] *= 0.62 + 0.38 * np.clip(ao, 0, 1)
    color_img.pixels.foreach_set(color.ravel())
    os.makedirs(os.path.join(OUT, "textures"), exist_ok=True)
    for kind in ("color", "normal", "rough"):
        img = results[kind][0]
        path = os.path.join(OUT, "textures", f"{fid}_{lod}_{kind}.png")
        save = bpy.data.images.new(f"P2S_{fid}_{lod}_{kind}", size, size, alpha=False)
        if kind != "color":
            save.colorspace_settings.name = "Non-Color"
        save.pixels.foreach_set(results[kind][1].ravel())
        save.filepath_raw = path
        save.file_format = "PNG"
        save.save()
        bpy.data.images.remove(save)
        out[kind] = path
    bpy.data.images.remove(results["ao"][0])
    return out, {k: results[k][0] for k in ("color", "normal", "rough")}


def game_material(fid, lod, images):
    """What the game shows: the baked maps, like the SurfaceAppearance (for the previews)."""
    name = f"P2_{fid}_{lod}"
    old = bpy.data.materials.get(name)
    if old:
        bpy.data.materials.remove(old)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    b = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Specular IOR Level"].default_value = 0.4
    c = nodes.new("ShaderNodeTexImage")
    c.image = images["color"]
    links.new(c.outputs["Color"], b.inputs["Base Color"])
    r = nodes.new("ShaderNodeTexImage")
    r.image = images["rough"]
    links.new(r.outputs["Color"], b.inputs["Roughness"])
    nt = nodes.new("ShaderNodeTexImage")
    nt.image = images["normal"]
    nm = nodes.new("ShaderNodeNormalMap")
    links.new(nt.outputs["Color"], nm.inputs["Color"])
    links.new(nm.outputs["Normal"], b.inputs["Normal"])
    return m


def mesh_json(ob):
    """Roblox coordinates (x, z, -y), per corner normals and UVs (V flipped: Roblox's 0 is the top), and the centre
    of the bounding box (Roblox centres a mesh on it): the game places the scoop's centre at -centre from the part."""
    mesh = ob.data
    mesh.calc_loop_triangles()
    try:
        mesh.calc_normals_split()
    except AttributeError:
        pass
    uv = mesh.uv_layers.active.data
    verts = [(round(v.co.x, 4), round(v.co.z, 4), round(-v.co.y, 4)) for v in mesh.vertices]
    tris, uvs, normals = [], [], []
    for t in mesh.loop_triangles:
        tris.append(list(t.vertices))
        uvs.append([(round(uv[li].uv[0], 4), round(1 - uv[li].uv[1], 4)) for li in t.loops])
        ns = [mesh.corner_normals[li].vector if hasattr(mesh, "corner_normals") else mesh.loops[li].normal for li in t.loops]
        normals.append([(round(n.x, 3), round(n.z, 3), round(-n.y, 3)) for n in ns])
    xs, ys, zs = zip(*verts)
    centre = ((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2)
    size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    return {"verts": verts, "tris": tris, "uvs": uvs, "normals": normals, "centre": centre, "size": size}


def unwrap(ob):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.012, area_weight=0.6)
    bpy.ops.object.mode_set(mode="OBJECT")
    for poly in ob.data.polygons:
        poly.use_smooth = True


def build(fid):
    sc = scene()
    col = collection(f"P2_{fid}")
    high_body = bpy.data.objects.new(f"P2_{fid}_body_high", body_mesh(f"P2_{fid}_body_high", FORM_OF[fid], SEED_OF[fid]))
    col.objects.link(high_body)
    surf = Surface(high_body)
    spec = globals()["flavor_" + fid](surf)
    high_body.data.materials.append(spec["body"])
    toppings = spec["toppings"]
    for ob, _, _ in toppings:
        col.objects.link(ob)
    high = join([high_body] + [ob for ob, _, _ in toppings], f"P2_{fid}_high", col)
    report = {"form": spec["form"], "lods": {}}
    for lod, total, body_share in (("LOD0", LOD0_TRIS, 0.5), ("LOD1", LOD1_TRIS, 0.6)):
        weights = [w for _, w, keep in toppings if lod == "LOD0" or keep]
        budget = total - int(total * body_share)
        parts = [decimated_copy(high_body, int(total * body_share), f"P2_{fid}_{lod}_body", keep_shape=False)]
        wsum = sum(weights) or 1
        for ob, w, keep in toppings:
            if lod == "LOD1" and not keep:
                continue
            parts.append(decimated_copy(ob, max(8, int(budget * w / wsum)), f"{ob.name}_{lod}"))
        low = join(parts, f"P2_{fid}_{lod}", col)
        for p in parts:
            bpy.data.objects.remove(p, do_unlink=True)
        # the decimation may land a little over: trim the body down until it fits
        guard = 0
        body_target = int(total * body_share)
        while tri_count(low) > total and guard < 8:
            guard += 1
            over = tri_count(low) - total
            bpy.data.objects.remove(low, do_unlink=True)
            body_target -= over + 10
            parts = [decimated_copy(high_body, body_target, f"P2_{fid}_{lod}_body", keep_shape=False)]
            for ob, w, keep in toppings:
                if lod == "LOD1" and not keep:
                    continue
                parts.append(decimated_copy(ob, max(8, int(budget * w / wsum)), f"{ob.name}_{lod}"))
            low = join(parts, f"P2_{fid}_{lod}", col)
            for p in parts:
                bpy.data.objects.remove(p, do_unlink=True)
        unwrap(low)
        # LOD1 drops the small toppings: bake it from a high poly without them, so they leave no ghost on it
        source = high if lod == "LOD0" else join([high_body] + [ob for ob, _, keep in toppings if keep], f"P2_{fid}_high1", col)
        paths, images = bake_maps(fid, lod, low, source, TEX[lod])
        if source is not high:
            bpy.data.objects.remove(source, do_unlink=True)
        low.data.materials.clear()
        low.data.materials.append(game_material(fid, lod, images))
        data = mesh_json(low)
        os.makedirs(os.path.join(OUT, "meshes"), exist_ok=True)
        with open(os.path.join(OUT, "meshes", f"{fid}_{lod}.json"), "w") as f:
            json.dump(data, f, separators=(",", ":"))
        export_fbx(low, fid, lod)
        mesh_png(fid, lod)  # the mesh as a picture for studio_proto.luau
        report["lods"][lod] = {"tris": tri_count(low), "size": data["size"], "centre": data["centre"]}
    high.hide_render = True
    high.hide_viewport = True
    high_body.hide_render = True
    high_body.hide_viewport = True
    for ob, _, _ in toppings:
        ob.hide_render = True
        ob.hide_viewport = True
    with open(os.path.join(OUT, f"{fid}_report.json"), "w") as f:
        json.dump(report, f, indent=1)
    print(fid, report)
    return report


def export_fbx(ob, fid, lod):
    os.makedirs(FBX_DIR, exist_ok=True)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.select_set(True)
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


# ------------------------------------------------------------------------------------- mesh data as a picture
# The Studio MCP can upload pictures but not meshes or files, and Studio may not fetch from localhost. So a LOD's
# mesh goes as a lossless PNG (studio_proto.luau reads it back as an EditableImage and builds the EditableMesh):
# a stream of 16-bit numbers, three bytes per pixel in R, G, B (alpha stays 255), width MESH_PNG_WIDTH.
#   count of vertices, count of triangles, then per vertex x y z (studs * 10000 + 32768), u v (* 65535), normal x y z
#   ((n + 1) / 2 * 65535), then per triangle its three vertex indices (0-based).
MESH_PNG_WIDTH = 256


def mesh_png(fid, lod):
    with open(os.path.join(OUT, "meshes", f"{fid}_{lod}.json")) as f:
        data = json.load(f)
    verts, index, tris = [], {}, []
    for t, uvs, normals in zip(data["tris"], data["uvs"], data["normals"]):
        tri = []
        for vi, uv, n in zip(t, uvs, normals):
            key = (vi, uv[0], uv[1], n[0], n[1], n[2])
            if key not in index:
                index[key] = len(verts)
                verts.append((data["verts"][vi], uv, n))
            tri.append(index[key])
        tris.append(tri)
    words = [len(verts), len(tris)]

    def pos(x):
        return max(0, min(65535, int(round(x * 10000 + 32768))))

    def unit(x):
        return max(0, min(65535, int(round(x * 65535))))

    for p, uv, n in verts:
        words += [pos(p[0]), pos(p[1]), pos(p[2]), unit(uv[0]), unit(uv[1])]
        words += [unit((c + 1) / 2) for c in n]
    for t in tris:
        words += t
    stream = []
    for w in words:
        stream += [w >> 8, w & 255]
    while len(stream) % 3:
        stream.append(0)
    pixels = len(stream) // 3
    height = (pixels + MESH_PNG_WIDTH - 1) // MESH_PNG_WIDTH
    px = np.zeros((height * MESH_PNG_WIDTH, 4), dtype=np.float32)
    px[:, 3] = 1.0
    px[:pixels, :3] = np.array(stream, dtype=np.float32).reshape(-1, 3) / 255.0
    # Blender's pixel rows run bottom up; the stream starts at the picture's top left
    px = px.reshape(height, MESH_PNG_WIDTH, 4)[::-1]
    img = bpy.data.images.new(f"P2M_{fid}_{lod}", MESH_PNG_WIDTH, height, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(px.ravel())
    path = os.path.join(OUT, "meshes", f"{fid}_{lod}_mesh.png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    # check: read it back and compare
    back = bpy.data.images.load(path, check_existing=False)
    got = np.empty(len(back.pixels), dtype=np.float32)
    back.pixels.foreach_get(got)
    bpy.data.images.remove(back)
    got = np.round(got.reshape(height, MESH_PNG_WIDTH, 4)[::-1].reshape(-1, 4)[:pixels, :3] * 255).astype(int).ravel()
    assert list(got[: len(stream)]) == stream, "the mesh picture does not read back"
    return path, len(verts), len(tris)
