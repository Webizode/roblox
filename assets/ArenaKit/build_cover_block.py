"""Arena obstacle 1, the Cover Block (reference: the vault's "Eiscreme-Arena_ Cover-Block Präsentation.png").

Run inside Blender after arenakit.py, in the same session:
    ASSET_DIR = r"<repo>/assets/ArenaKit"
    exec(open(ASSET_DIR + "/arenakit.py").read())
    exec(open(ASSET_DIR + "/build_cover_block.py").read())

12 long x 3.9 deep x 5 high (studs): it hides a standing player's body (the hit capsule reaches 5.8 above the
ground, the head's top about 5.4), so the head only just and the tower on the back (its bottom scoop about 3.9 up,
every further one higher) show over it. Origin at the bottom centre. In Roblox one invisible box of the same size is
its collision; the meshes do not collide.

Layout along X: at each end a Cream foot, a Pink post and a Pink cap, the cone emblem on the end face; between them
a Gold plinth, the Waffle body with its lattice on front and back, Cream glaze on top with drips, a few sprinkles.
"""

COVER = dict(length=12.0, depth=3.9, height=5.0)

col = model_collection("CoverBlock")
L, D, H = COVER["length"], COVER["depth"], COVER["height"]
END_X = L / 2 - 1.0  # centre of the end blocks

for side, sx in (("L", -1), ("R", 1)):
    x = sx * END_X
    rounded_box(col, f"Foot_{side}", "Cream", (2.0, D, 1.0), (x, 0, 0.5), radius=0.3)
    # as deep as the glaze with its drips, so they end behind the post
    rounded_box(col, f"Post_{side}", "Pink", (1.6, D - 0.1, 3.3), (x, 0, 2.6), radius=0.28)
    rounded_box(col, f"Cap_{side}", "Pink", (2.2, D, 0.95), (x, 0, H - 0.475), radius=0.32)
    cone_emblem(col, f"Emblem_{side}", (x + sx * 0.8, 0, 2.6), (sx, 0, 0), width=2.1, height=2.7)

# the middle: plinth, waffle, glaze
rounded_box(col, "Plinth", "Gold", (L - 3.6, D - 0.4, 0.85), (0, 0, 0.425), radius=0.25)
waffle_panel(col, "Waffle", (L - 3.8, D - 0.9, 3.5), (0, 0, 0.85 + 1.75))
glaze(col, "Glaze", length=L - 3.6, depth=D - 0.7, top=H - 0.1)
sprinkles(
    col,
    "Sprinkles",
    [(-3.2, -0.5, H - 0.1), (-1.8, 0.6, H - 0.1), (-0.4, -0.4, H - 0.1), (1.0, 0.7, H - 0.1),
     (2.2, -0.6, H - 0.1), (3.3, 0.5, H - 0.1)],
)

print(f"CoverBlock: {len(col.objects)} objects, {triangles(col)} triangles")
