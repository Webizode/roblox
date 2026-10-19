--!strict
-- The waffle-cone backpack every player wears. It holds the loaded ice balls, so the ammo shows on the character
-- itself, to the player (the camera looks at the back) and to everyone else. Purely visual: the server owns the
-- ammo (Config/Combat). Sizes are studs for a default R15 character and scale with the torso height.

return {
	referenceTorsoHeight = 1.6,

	-- the cone, tip down, on the back; stepped from a few cylinders like the tower's cone
	coneLength = 2.0,
	coneTopDiameter = 1.9,
	coneTipDiameter = 0.45,
	coneSegments = 4,
	rimHeight = 0.18, -- chocolate-dipped rim
	coneUp = -0.3, -- cone centre above the torso centre; the top ball sits behind the lower half of the head
	coneBack = 0.05, -- gap between the back and the rim, the cone's closest point
	-- the opening leans away from the back, so the balls show over the shoulder; about the cone's half angle, so
	-- its near side runs along the back
	coneTilt = math.rad(20),

	-- ice balls in the opening, relative to its centre (x right, y up, z back). The last slot is thrown first; a
	-- load bigger than the list stacks further up.
	ballDiameter = 0.95,
	slots = {
		{ -0.475, 0.2, 0 },
		{ 0.475, 0.2, 0 },
		{ 0, 1.02, 0 },
	},

	-- shoulder straps
	strapWidth = 0.22,
	strapThickness = 0.08,
	strapReach = 0.2, -- how far the over-shoulder straps run on behind the back, into the rim

	-- animation: a thrown ball pops out, a refilled load pops in one after the other; while an empty load
	-- refills, see-through frost balls grow in the slots
	popIn = 0.25, -- seconds
	popOut = 0.1,
	popStagger = 0.06,
	frostMax = 0.85, -- share of the ball size the frost reaches at the end of the reload; it starts at zero
	frostTransparency = 0.55,

	drawDistance = 200, -- studs from the camera; farther backpacks are not drawn
	minUpright = 0.5, -- torso up-vector height below which the backpack hides (the knockdown lies at about 0.2)
	-- the local player's backpack fades out between these camera distances to its opening (studs, scaled)
	fadeStart = 3,
	fadeEnd = 1.5,
}
