--!strict
-- The waffle-cone backpack every player wears. For now an empty waffle, part of the collecting and tower side (not
-- the ice-ball ammo). Purely visual. Sizes are studs for a default R15 character and scale with the torso height.

return {
	referenceTorsoHeight = 1.6,
	-- the whole waffle (meshes, rim, the tower's seat in it) this much bigger than the measures below; it sits further
	-- back by as much as it gets wider, the straps stay. 1.25 since the team test of 20.11.2026 (1 before: too small
	-- for the tower scoops with their real geometry)
	waffleScale = 1.25,

	-- the cone, tip down, on the back; stepped from a few cylinders like the tower's cone
	coneLength = 2.0,
	coneTopDiameter = 1.9,
	coneTipDiameter = 0.45,
	coneSegments = 4,
	rimHeight = 0.18, -- chocolate-dipped rim
	coneUp = -0.3, -- cone centre above the torso centre
	coneBack = 0.05, -- gap between the back and the rim, the cone's closest point
	-- the opening leans away from the back; about the cone's half angle, so its near side runs along the back
	coneTilt = math.rad(20),
	-- the bottom scoop of the tower sits on the cone's axis, just high enough that this much of the chocolate rim
	-- (and of the waffle below it) stays visible all round it instead of the scoop cutting through them
	scoopMargin = 0.08,

	-- The waffle from Blender (since the kill test of 13.11.2026, assets/Backpack): four meshes in ReplicatedStorage.<kit>
	-- (assets/Backpack/studio_backpack_templates.luau makes them from Studio's import). Size and centre per mesh at scale 1
	-- in the cone's frame (origin on the axis at the cone's middle, +Y to the opening), as build_backpack.py prints them;
	-- the measures above stay those of the meshes, so the tower sits in it as before. Without the kit the old stepped
	-- cylinders are drawn. The glaze is white in the mesh and takes the colour of the owner's plot (Palette.plotFlavors),
	-- glazeFallback without a plot.
	kit = "BackpackKit",
	meshes = {
		waffle = { size = { 1.9, 2.225, 1.9 }, centre = { 0, -0.113, 0 }, color = "#E2AE62" },
		lines = { size = { 1.83, 1.735, 1.83 }, centre = { 0, -0.028, 0 }, color = "#A8692E" },
		rim = { size = { 2.1, 0.2, 2.1 }, centre = { 0, 0.93, 0 }, color = "#6A3F2A" },
		glaze = { size = { 1.98, 0.965, 1.98 }, centre = { 0, 0.517, 0 } },
	},
	glazeFallback = "#FFF4E4",

	-- shoulder straps
	strapWidth = 0.22,
	strapThickness = 0.08,
	strapReach = 0.2, -- how far the over-shoulder straps run on behind the back, into the rim

	drawDistance = 200, -- studs from the camera; farther backpacks are not drawn
	minUpright = 0.5, -- knocked down (DownUntil) with the torso up-vector height below this, the backpack hides (lying is about
	-- 0.2; a sprinting dash leans to about 0.4, so the angle alone is never enough)
	-- the local player's backpack fades out between these camera distances to its opening (studs, scaled)
	fadeStart = 3,
	fadeEnd = 1.5,
}
