"""Pictures for the fountain water (studio_fountain_water.luau). Plain Python with numpy, no Blender needed:
    "<Blender>/python/bin/python.exe" assets/HubKit/make_fountain_textures.py

Writes assets/HubKit/textures/<name>.png (small, phones load them cheaply):

    Fountain_Ripples   seamless cartoon ripples: soft white wavy streaks on transparent, 256 px. A Texture on the
                       water's top, scrolled by the client (FountainWater), tinted nothing: the water's own colour
                       shows through the transparent parts
    Fountain_Drop      one soft round droplet, white, 64 px, for the splash and jet particles (tinted there)

After a change: upload the PNGs again (Studio MCP upload_image) and put the new ids into studio_fountain_water.luau.
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


def ripples(size=256):
    # wavy bands from whole-number sine periods, so the tile repeats without a seam
    y, x = np.mgrid[0:size, 0:size] / size
    tau = 2 * np.pi
    warp = 0.06 * np.sin(tau * 2 * x + 1.3) + 0.03 * np.sin(tau * 3 * x + tau * 1 * y)
    bands = np.sin(tau * 5 * (y + warp))
    streak = np.clip((bands - 0.72) / 0.28, 0, 1) ** 1.5  # thin bright crests
    # break the crests into dashes along x, so it reads as moving water, not stripes
    dash = 0.5 + 0.5 * np.sin(tau * 3 * x + tau * 2 * y + 2.0 * np.sin(tau * 2 * y))
    alpha = streak * np.clip(dash * 1.6 - 0.2, 0, 1)
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (alpha * 210).astype(np.uint8)
    return rgba


def drop(size=64):
    y, x = np.mgrid[0:size, 0:size]
    c = (size - 1) / 2
    r = np.sqrt((x - c) ** 2 + (y - c) ** 2) / c
    alpha = np.clip(1 - r, 0, 1) ** 0.6
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (alpha * 255).astype(np.uint8)
    return rgba


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write_png(os.path.join(OUT, "Fountain_Ripples.png"), ripples())
    write_png(os.path.join(OUT, "Fountain_Drop.png"), drop())
    print("written to", OUT)
