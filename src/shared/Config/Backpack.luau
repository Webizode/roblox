--!strict
-- The waffle-cone backpack every player wears. For now an empty waffle, part of the collecting and tower side (not
-- the ice-ball ammo). Purely visual. Sizes are studs for a default R15 character and scale with the torso height.

return {
	referenceTorsoHeight = 1.6,

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

	-- shoulder straps
	strapWidth = 0.22,
	strapThickness = 0.08,
	strapReach = 0.2, -- how far the over-shoulder straps run on behind the back, into the rim

	drawDistance = 200, -- studs from the camera; farther backpacks are not drawn
	minUpright = 0.5, -- torso up-vector height below which the backpack hides (the knockdown lies at about 0.2)
	-- the local player's backpack fades out between these camera distances to its opening (studs, scaled)
	fadeStart = 3,
	fadeEnd = 1.5,
}
