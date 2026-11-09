"""The picture for the open sea (src/client/Controllers/Ocean.luau). Plain Python with numpy, no Blender needed:
    "<Blender>/python/bin/python.exe" assets/World/make_ocean_texture.py

Writes assets/World/textures/Ocean_Waves.png: calm cartoon waves, a few short soft white crests on transparent,
seamless, 512 px. The sea's own colour shows through; the client lays it on the top of the sea parts and lets it
drift slowly. After a change: upload again (Studio MCP upload_image) and put the id into Config/Map.ocean.texture.
"""

import os
import struct
import zlib

import numpy as np

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "textures")


def write_png(path, rgba):
    h, w, _ = rgba.shape
    raw = b"".join(b"\x00" + rgba[y].tobytes() for y in range(h))

    def chunk(kind, data):
        c = kind + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def waves(size=512, seed=7):
    # short crescent crests scattered on a jittered grid; every crest is drawn with wrap-around, so the tile is seamless
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    alpha = np.zeros((size, size), np.float32)
    cells = 6
    step = size / cells
    for i in range(cells):
        for j in range(cells):
            cx = (i + 0.5 + rng.uniform(-0.3, 0.3)) * step + (step / 2 if j % 2 else 0)
            cy = (j + 0.5 + rng.uniform(-0.25, 0.25)) * step
            length = rng.uniform(0.35, 0.55) * step
            bend = rng.uniform(0.10, 0.18) * step
            dx = (x - cx + size / 2) % size - size / 2
            dy = (y - cy + size / 2) % size - size / 2
            u = dx / length
            curve = bend * (1 - (2 * u) ** 2)  # a gentle arch over the crest's length
            d = np.abs(dy + curve)
            along = np.clip(1 - np.abs(2 * u), 0, 1) ** 0.7  # thin out to the ends
            crest = np.clip(1 - d / 4.5, 0, 1) * along * (np.abs(u) < 0.5)
            alpha = np.maximum(alpha, crest)
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (alpha * 170).astype(np.uint8)  # soft: the sea stays calm
    return rgba


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write_png(os.path.join(OUT, "Ocean_Waves.png"), waves())
    print("written to", OUT)
