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
