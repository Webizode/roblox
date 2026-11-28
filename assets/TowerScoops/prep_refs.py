"""Reference pictures for Meshy Image-to-3D (build_meshy.py): the design sheet's main scoop, cut out on a transparent
background (img2_3d/input/<fid>_ref.png). Nothing may sit high on top of a scoop, because the next scoop of the tower
sits there: with a CUT row, everything above it (crowns, cream swirls, fruit, flowers on top) is painted over with a
plain dome that carries the colours of the row below the cut upwards, with soft noise, speckles and shading.

Run inside Blender (Blender MCP):
    ASSET_DIR = r"<repo>/assets/TowerScoops"
    exec(open(ASSET_DIR + "/prep_refs.py").read())
    prep("midnight_berry", "20261118170206", cut=190)   # cut: row of the design sheet (1536 x 1024), None: keep the top

The design sheets (Desktop/claude gehirn/Wobble Scoops/Pasted image <stamp>.png) have the main scoop at the left, in
CROP; the small variants, the name plate and the purple background go.
"""

import os

import bpy
import numpy as np

ASSET_DIR = globals().get("ASSET_DIR") or os.path.dirname(bpy.data.filepath)
VAULT = os.path.join(os.path.expanduser("~"), "Desktop", "claude gehirn", "Wobble Scoops")
OUT = os.path.join(ASSET_DIR, "img2_3d", "input")
CROP = (70, 0, 860, 745)  # x0, y0, x1, y1 of the main scoop on the sheet
BLEND = 26  # rows over which the painted dome fades into the picture below the cut
DOME = 0.85  # the dome's height over its half width


def load(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1].copy()
    bpy.data.images.remove(img)
    return a


def save(path, rgba):
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    img.pixels[:] = rgba[::-1].ravel()
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def dilate(m):
    g = m.copy()
    g[1:] |= m[:-1]
    g[:-1] |= m[1:]
    g[:, 1:] |= m[:, :-1]
    g[:, :-1] |= m[:, 1:]
    return g


def flood(seed, allowed):
    m = seed & allowed
    for _ in range(3000):
        g = dilate(m) & allowed
        if (g == m).all():
            break
        m = g
    return m


def background(rgb, glow=0.35):
    """The sheet's dark purple and its magenta glow (purplish up to `glow` luminance), reached from the border. Pink and
    purple scoops need a low `glow`, or the flood runs into them."""
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    purplish = (rgb[..., 2] > rgb[..., 1] * 1.15) & (rgb[..., 0] > rgb[..., 1])
    like = (lum < 0.06) | (purplish & (lum < glow))
    seed = np.zeros_like(like)
    seed[0, :] = seed[-1, :] = True
    seed[:, 0] = seed[:, -1] = True
    return flood(seed, like)


def largest(mask):
    best, seen = None, np.zeros_like(mask)
    ys, xs = np.nonzero(mask)
    for sy, sx in zip(ys[::997], xs[::997]):
        if seen[sy, sx]:
            continue
        seed = np.zeros_like(mask)
        seed[sy, sx] = True
        part = flood(seed, mask)
        seen |= part
        if best is None or part.sum() > best.sum():
            best = part
    return best


def blur(z, k, n=3):
    for _ in range(n):
        z = (np.roll(z, k, 0) + np.roll(z, -k, 0) + np.roll(z, k, 1) + np.roll(z, -k, 1) + z) / 5
    return z


def repaint_top(rgb, alpha, cut, seed=7):
    """Everything above `cut` (rows of the crop) becomes a plain dome: an ellipse fitted to the scoop's sides below the
    cut, filled with the colours of the rows just below the cut carried upwards, soft noise, speckles and shading."""
    h, w = alpha.shape
    rng = np.random.default_rng(seed)
    # the scoop's widest row between the cut and the rim (the rim starts about 65 % down the crop), and the dome's
    # height from how much narrower the scoop is just below the cut
    def span(y):
        xs = np.nonzero(alpha[y] > 0.5)[0]
        return (xs.min(), xs.max()) if len(xs) else None

    best, cy, left, right = 0, cut + 60, 0, w
    for y in range(cut + 30, int(h * 0.6)):
        s = span(y)
        if s and s[1] - s[0] > best:
            best, cy, (left, right) = s[1] - s[0], y, s
    cx, rx = (left + right) / 2, (right - left) / 2
    ry = rx * DOME
    s = span(cut + 15)
    if s and cy > cut + 15:
        half = min((s[1] - s[0]) / 2, rx * 0.97)
        ry = (cy - (cut + 15)) / np.sqrt(1 - (half / rx) ** 2)
    ry = float(np.clip(ry, rx * 0.7, rx * 1.1))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    e = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
    inside = e <= 1.0
    # one colour: the median of the layer just below the cut (per column it gave streaks of sauce and highlights)
    band = rgb[cut + 4 : cut + 40][alpha[cut + 4 : cut + 40] > 0.5]
    colour = np.median(band, 0) if len(band) else np.array([0.95, 0.88, 0.75], np.float32)
    fill = np.broadcast_to(colour, (h, w, 3)).astype(np.float32)
    noise = blur(rng.standard_normal((h, w)).astype(np.float32), 6)
    noise /= noise.std() + 1e-6
    fill = fill * (1 + 0.035 * noise[..., None])
    dots = rng.random((h, w)) < 0.003
    dots = dots | np.roll(dots, 1, 0) | np.roll(dots, 1, 1)
    fill = np.where(dots[..., None], fill * 0.8, fill)
    nx, ny = (xx - cx) / rx, (yy - cy) / ry
    shade = 1.04 - 0.22 * np.clip(e, 0, 1) ** 2.2 + 0.05 * np.clip(-(nx * 0.4 + ny * 0.7), -1, 1)
    fill = np.clip(fill * shade[..., None], 0, 1)
    wgt = np.clip((cut - yy) / BLEND, 0, 1)
    above = yy < cut
    src = np.where((alpha > 0.5)[..., None], rgb, fill)
    out_rgb = np.where(above[..., None], src * (1 - wgt[..., None]) + fill * wgt[..., None], rgb)
    out_a = np.where(above, inside * wgt + alpha * (1 - wgt), alpha)
    out_a = np.where(above & ~inside & (wgt > 0.99), 0.0, out_a)
    return out_rgb, np.clip(out_a, 0, 1)


def prep(fid, stamp, cut=None, glow=0.35):
    a = load(os.path.join(VAULT, f"Pasted image {stamp}.png"))
    x0, y0, x1, y1 = CROP
    a = a[y0:y1, x0:x1]
    rgb = a[..., :3]
    keep = largest(~background(rgb, glow))
    inner = keep.copy()
    inner[1:] &= keep[:-1]
    inner[:-1] &= keep[1:]
    inner[:, 1:] &= keep[:, :-1]
    inner[:, :-1] &= keep[:, 1:]
    alpha = np.where(inner, 1.0, np.where(keep, 0.5, 0.0)).astype(np.float32)
    if cut is not None:
        rgb, alpha = repaint_top(rgb, alpha, cut - y0)
    rows, cols = np.nonzero(alpha > 0)
    t, b, l, r = rows.min(), rows.max() + 1, cols.min(), cols.max() + 1
    pad = 40
    side = max(b - t, r - l) + 2 * pad
    canvas = np.zeros((side, side, 4), np.float32)
    oy, ox = (side - (b - t)) // 2, (side - (r - l)) // 2
    piece = np.dstack([rgb * (alpha[..., None] > 0), alpha])[t:b, l:r]
    canvas[oy : oy + (b - t), ox : ox + (r - l)] = piece
    path = os.path.join(OUT, f"{fid}_ref.png")
    save(path, canvas)
    return path, canvas
