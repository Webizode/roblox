--!strict
-- The look of the tower scoops (stacked on the back, not the attack scoops): their model, the flight from the Big
-- Swirl (the trail by rarity is in Config/Vfx.flight). Purely visual; the server's flight path and catch rules stay as they are (Config/Launcher).
-- Models: ReplicatedStorage.TowerScoops.<flavor id> with the MeshParts LOD0 (close) and LOD1 (far), built in Blender
-- (assets/TowerScoops). A flavor without its model is drawn as the plain ball.

return {
	folder = "TowerScoops",
	-- one Highlight per tower: no outline (the dark #5A2E1A outline went in the kill test of 13.11.2026), red
	-- (Palette.awning) only while it groans
	-- the client draws LOD1 from farDistance studs on (from the camera) and LOD0 again below farDistance - hysteresis
	farDistance = 40,
	hysteresis = 4,
	-- every scoop on a tower sits a little differently (ScoopFlight.stackPose, since prototype 2 of 18.11.2026): a random
	-- turn about its own axis, tilted up to `tilt` either way, scaleMin to scaleMax of its size; the same for the same
	-- place, so a stack does not line up into stripes and looks wobbly and hand-made
	stack = {
		tilt = math.rad(3),
		scaleMin = 0.95,
		scaleMax = 1.05,
	},

	-- The name and value over a scoop in flight or lying on the ground (not on a tower): readable up to maxDistance
	-- studs, a fixed size on screen, so it stays readable on a phone. height: studs above the scoop's centre.
	-- "Mint 5[coin]": the design is drawn at textSize; on screen the text is screenShare of the screen's height, between
	-- minText and textSize pixels (a phone about 11, a PC 20; phone test 17.11.2026: 20 px stood big in the middle of
	-- the picture). The coin keeps coinGap pixels after the number.
	label = {
		maxDistance = 40,
		height = 1.7,
		textSize = 20,
		iconSize = 18,
		coinGap = 5,
		screenShare = 0.024,
		minText = 11,
	},
	-- the landing circle (ShotRenderer): a Neon disc, shrinking to 40 % as the scoop comes down. Since 25.11.2026 in the
	-- rarity's colour like the trail (RarityFlight.circleColor), a common one in light grey (`common`), and without the
	-- dark ring (04.11.2026 to 25.11.2026 a Berry ring picture on its top, for the light floor; it read as a black rim).
	-- A little more see-through (0.35 before) so the coloured discs show without glaring.
	landingCircle = {
		size = 7, -- studs across at the start
		transparency = 0.45,
		common = "#D9DDE6", -- light grey: white glares on the light floor
		-- when the Big Swirl fires, each new circle lights up (fully opaque) and settles to `transparency` in this many
		-- seconds: where the scoops will come down shows itself
		flash = 0.7,
		flashTransparency = 0.15, -- how strong it lights up first (0 before 25.11.2026: a full Neon flash glared)
	},
	-- The ring under a tower scoop from uncommon on (user 28.11.2026: in the stack one could not tell the rarities apart;
	-- TowerVisual, TowerMarks.ring), on every tower: a thin torus round the scoop's drip rim, where it sits on the scoop
	-- below, in the colour of the landing circle and the trail (golden for a legendary). Plain from uncommon, glowing a
	-- little (Neon, see-through) from `glowFrom`, a few gold glints from `sparkleFrom`; low VFX quality neither, medium
	-- no glints. One part per scoop, no Highlight (Roblox draws only 31 at once).
	rarityRing = {
		part = "TowerRarityRing", -- ReplicatedStorage.<part>: the torus, 1.96 studs across and 0.1 thick at scale 1
		height = -0.8, -- studs from the scoop's centre: its rim (radius about 0.89 there, all 52 Meshy models)
		transparency = 0, -- plain
		glowFrom = "epic",
		glowTransparency = 0.3,
		sparkleFrom = "legendary",
		sparkle = {
			texture = "star", -- Config/Vfx.textures
			rate = 1.5, -- glints per second and ring
			size = { 0.15, 0.3 },
			lifetime = { 0.5, 0.9 },
			lightEmission = 0.8,
			maxDistance = 60, -- studs from the camera; farther rings do not glint
		},
	},
	-- The name over a scoop: "EPIC Tiramisu" in the rarity's colour (the ring's), for `time` seconds, rising a little
	-- and fading. Over the own tower's new top scoop when it is caught; over a rival's tower while one aims at it (the
	-- crosshair in combat mode, else the mouse), naming its rarest scoop (TowerMarks.rarest). Never on every scoop.
	nameTag = {
		time = 1.5,
		popTime = 0.15,
		fadeTime = 0.35,
		rise = 0.8, -- studs it rises meanwhile
		above = 1.3, -- studs over the scoop's centre
		width = 300, -- pixels
		height = 34,
		peek = {
			maxDistance = 120, -- studs from the camera to a rival's tower
			radius = 1.3, -- studs round the tower's column that count as aiming at it
			again = 2, -- seconds before one tower's name shows again after aiming away and back (no flicker)
			check = 0.1, -- seconds between two looks
		},
	},
	-- how far the lowest drip is below the scoop's centre in the models (the same for every flavor: build_scoops.py
	-- base shape). The importer centres a mesh on its bounding box; from the bottom of that box this finds the scoop's
	-- centre, also for a flavor with something on top (the lemon slice)
	dripDepth = 0.86,

	-- The tower turns with its carrier (ScoopFlight.followYaw; team test of 20.11.2026: it stayed facing one way while
	-- the character turned): a spring towards the character's yaw. stiffness (1/s^2) and damping (1/s) give about a
	-- tenth of a second of lag and a small swing past the new heading (damping ratio about 0.55), so it looks carried, not
	-- glued. Purely visual: the lean, the catch column and the physics do not turn with it.
	turn = {
		stiffness = 160,
		damping = 14,
		maxStep = 1 / 60,
	},

	flight = {
		-- rising: the scoop turns slowly about its own axis, upright
		spinRate = math.rad(200), -- per second
		-- after the highest point it tips like a shuttlecock until the dome leads the way down: tipSpan is the share
		-- of the flight over which it turns (from the apex on), tipLead how far the dome turns towards the direction
		-- it flies (1 = exactly along it)
		tipSpan = 0.25,
		tipLead = 1,
	},

	catch = {
		-- caught: it turns back upright with a short swing past it ...
		rightTime = 0.22, -- seconds
		overshoot = 1.8, -- back-out easing: how far it swings past upright (0 = none)
		-- ... and plops onto the tower: the new top scoop drops in from above and squashes for a moment
		plopTime = 0.28,
		plopDrop = 0.7, -- studs above its place it starts
		squash = 0.22, -- share it gets flatter (and wider) when it lands
	},
}
