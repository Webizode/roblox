--!strict
-- The game's effects (src/client/Vfx): one style for all of them, the cartoon ice cream world. Sprinkles, splashes of
-- cream, drops of glaze, small stars, soft pastel puffs and short bright flashes; colours from the flavor of the scoop
-- and the UI's candy look. Purely visual and client-only: nothing here decides anything.
--
-- Every effect has a budget: the most particles it may show at once (at the high VFX quality) and the longest any of
-- them lives. VfxRules scales the counts with the VFX quality and the distance, and tests/VfxRules.spec.luau checks
-- that every effect keeps its budget and that the worst case stays under maxLive.
--
-- A layer is one burst of one picture:
--   texture     a key of `textures`
--   count       particles at the high quality, close by
--   extra       true: only at a quality with extras, and only close by
--   color       "scoop" (the flavor's colour, passed in by the effect), a key of `colors`, or a hex colour
--   lighten     0..1: the colour mixed this far towards white (whipped cream flying out of a splash of its flavor)
--   lifetime    { min, max } seconds
--   speed       { min, max } studs/s, spread: degrees round the effect's direction
--   size        { { time 0..1, studs }, ... }, transparency the same with 0..1
--   accel       studs/s² up (negative: it falls), drag, rotation and rotSpeed { min, max } in degrees
--   bright      Brightness (default 1): above 1 the picture's shaded body comes out lighter
--   light       LightEmission (0: the dark outline stays, 1: it glows)
--   flipbook    true: the picture is a 4 x 4 flipbook played once over the lifetime
--   orient      "velocity": the picture points the way it flies
--   z           ZOffset, studs towards the camera

return {
	-- assets/Vfx/textures (make_vfx_textures.py): white with a dark outline, tinted by the layer's colour
	textures = {
		sprinkle = "rbxassetid://93583976722930", -- Vfx_Sprinkle.png
		blob = "rbxassetid://92034411280713", -- Vfx_Blob.png
		drop = "rbxassetid://112400683967221", -- Vfx_Drop.png
		star = "rbxassetid://95919351417672", -- Vfx_Star.png
		cloud = "rbxassetid://96977485951841", -- Vfx_Cloud.png
		ring = "rbxassetid://105040632730662", -- Vfx_Ring.png
		flash = "rbxassetid://105144777635970", -- Vfx_Flash.png
		splat = "rbxassetid://105830721155613", -- Vfx_Splat.png, 4 x 4 frames
	},

	colors = {
		white = "#FFFFFF",
		gold = "#FFD23F", -- Palette.lemon: the headshot's stars, the stars over a knocked down head
		perfect = "#3DDC84", -- Config/Combat crosshair.perfectColor: the green of the charge arc
		perfectDeep = "#1E9E5A",
		sprinklePink = "#FF8FA3",
		sprinkleMint = "#7FD9B6",
		sprinkleLemon = "#FFD23F",
		-- pastel, but strong enough to read on the arena's cream floor
		dustPink = "#FF9DBC",
		dustBlue = "#9FD3F5",
	},
	-- the scoop colour of a throw whose flavor is not known (the ice ball is vanilla so far)
	defaultFlavor = "vanilla",

	-- what a VFX quality means here (Settings; the performance mode counts as low): the share of every count, and
	-- whether the extras (the layers marked `extra`) show at all
	quality = {
		high = { particles = 1, extras = true },
		medium = { particles = 0.5, extras = true },
		low = { particles = 0.25, extras = false },
	},
	-- how far from the camera an effect still plays: in full up to `full` studs, up to `reduced` with reducedScale of
	-- its particles and no extras, not at all beyond. The local player's own effects always play in full.
	distance = { full = 60, reduced = 140, reducedScale = 0.5 },
	-- particles of all effects alive at once; over it other players' effects thin out or are left out (the local
	-- player's own still play)
	maxLive = 400,

	-- camera jolts (Vfx.Camera); the camera shake setting switches all of them off. The victim's shakes are in
	-- Config/Movement (hitShake, landShake).
	camera = {
		hitThrower = { degrees = 0.45, time = 0.14 }, -- the local player's ball hit somebody
		headshotThrower = { degrees = 0.8, time = 0.18 },
	},

	-- the short white flash on the body of whoever was hit
	bodyFlash = { transparency = 0.3, time = 0.3 },

	effects = {
		-- an ice ball hits a player: cream splashes in the scoop's colour, sprinkles fly, a short white flash
		hit = {
			budget = { particles = 28, duration = 0.6 },
			layers = {
				{
					texture = "splat",
					flipbook = true,
					count = 2,
					color = "scoop",
					lifetime = { 0.34, 0.46 },
					speed = { 1, 3 },
					spread = 60,
					size = { { 0, 1.4 }, { 0.25, 3 }, { 1, 3.6 } },
					transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } },
					rotation = { 0, 360 },
					bright = 1.35,
					z = -0.3, -- behind the blobs and sprinkles that fly out of it
				},
				{
					texture = "blob",
					count = 8,
					color = "scoop",
					lighten = 0.55,
					lifetime = { 0.35, 0.55 },
					speed = { 10, 18 },
					spread = 65,
					size = { { 0, 0.75 }, { 0.6, 0.55 }, { 1, 0.1 } },
					transparency = { { 0, 0 }, { 0.85, 0 }, { 1, 1 } },
					accel = -38,
					drag = 2,
					rotation = { 0, 360 },
					rotSpeed = { -220, 220 },
					z = 0.3,
				},
				{
					texture = "drop",
					extra = true,
					count = 5,
					color = "scoop",
					orient = "velocity",
					lifetime = { 0.35, 0.6 },
					speed = { 14, 22 },
					spread = 75,
					size = { { 0, 0.5 }, { 1, 0.15 } },
					transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } },
					accel = -45,
					drag = 1.5,
					z = 0.3,
				},
				{
					texture = "sprinkle",
					count = 3,
					color = "sprinklePink",
					lifetime = { 0.4, 0.6 },
					speed = { 12, 22 },
					spread = 80,
					size = { { 0, 0.45 }, { 0.8, 0.45 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = -45,
					drag = 1.5,
					rotation = { 0, 360 },
					rotSpeed = { -540, 540 },
					z = 0.4,
				},
				{
					texture = "sprinkle",
					count = 3,
					color = "sprinkleMint",
					lifetime = { 0.4, 0.6 },
					speed = { 12, 22 },
					spread = 80,
					size = { { 0, 0.45 }, { 0.8, 0.45 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = -45,
					drag = 1.5,
					rotation = { 0, 360 },
					rotSpeed = { -540, 540 },
					z = 0.4,
				},
				{
					texture = "sprinkle",
					count = 3,
					color = "sprinkleLemon",
					lifetime = { 0.4, 0.6 },
					speed = { 12, 22 },
					spread = 80,
					size = { { 0, 0.45 }, { 0.8, 0.45 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = -45,
					drag = 1.5,
					rotation = { 0, 360 },
					rotSpeed = { -540, 540 },
					z = 0.4,
				},
				{
					texture = "flash",
					count = 1,
					color = "white",
					lifetime = { 0.12, 0.12 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 3 }, { 1, 5.5 } },
					transparency = { { 0, 0.1 }, { 1, 1 } },
					light = 0.8,
					z = 1,
				},
				{
					texture = "ring",
					count = 1,
					color = "white",
					lifetime = { 0.24, 0.24 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 1 }, { 1, 5 } },
					transparency = { { 0, 0.3 }, { 1, 1 } },
					z = 0.8,
				},
			},
		},

		-- on top of `hit` for a headshot: a burst of golden stars and a golden shock ring
		headshot = {
			budget = { particles = 12, duration = 0.6 },
			layers = {
				{
					texture = "star",
					count = 8,
					color = "gold",
					lifetime = { 0.4, 0.6 },
					speed = { 12, 20 },
					spread = 180,
					size = { { 0, 0.3 }, { 0.15, 1 }, { 0.7, 0.8 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					drag = 4,
					rotation = { 0, 360 },
					rotSpeed = { -240, 240 },
					z = 1.2,
				},
				{
					texture = "star",
					extra = true,
					count = 2,
					color = "white",
					lifetime = { 0.3, 0.45 },
					speed = { 6, 10 },
					spread = 180,
					size = { { 0, 0.2 }, { 0.3, 0.55 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					drag = 4,
					rotation = { 0, 360 },
					rotSpeed = { -360, 360 },
					light = 0.6,
					z = 1.3,
				},
				{
					texture = "ring",
					count = 1,
					color = "gold",
					lifetime = { 0.32, 0.32 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 1.5 }, { 1, 8 } },
					transparency = { { 0, 0.15 }, { 1, 1 } },
					light = 0.4,
					z = 0.9,
				},
				{
					texture = "flash",
					count = 1,
					color = "gold",
					lifetime = { 0.16, 0.16 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 4 }, { 1, 8 } },
					transparency = { { 0, 0.2 }, { 1, 1 } },
					light = 0.8,
					z = 1.1,
				},
			},
		},

		-- an ice ball ends on the world, on cover or on a player in their safe zone: a small splash
		hitWorld = {
			budget = { particles = 8, duration = 0.5 },
			layers = {
				{
					texture = "splat",
					flipbook = true,
					count = 1,
					color = "scoop",
					lifetime = { 0.34, 0.4 },
					speed = { 0, 1 },
					spread = 30,
					size = { { 0, 1 }, { 0.25, 2.2 }, { 1, 2.6 } },
					transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } },
					rotation = { 0, 360 },
					bright = 1.35,
					z = -0.3,
				},
				{
					texture = "blob",
					count = 4,
					color = "scoop",
					lighten = 0.55,
					lifetime = { 0.3, 0.45 },
					speed = { 8, 14 },
					spread = 70,
					size = { { 0, 0.5 }, { 1, 0.1 } },
					transparency = { { 0, 0 }, { 0.85, 0 }, { 1, 1 } },
					accel = -38,
					drag = 2,
					rotation = { 0, 360 },
					rotSpeed = { -220, 220 },
					z = 0.3,
				},
				{
					texture = "sprinkle",
					extra = true,
					count = 3,
					color = "sprinklePink",
					lifetime = { 0.35, 0.5 },
					speed = { 10, 16 },
					spread = 80,
					size = { { 0, 0.4 }, { 0.8, 0.4 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = -45,
					drag = 1.5,
					rotation = { 0, 360 },
					rotSpeed = { -540, 540 },
					z = 0.4,
				},
			},
		},

		-- a perfect throw leaves the hand: green glitter, matching the green of the charge arc
		perfectRelease = {
			budget = { particles = 16, duration = 0.5 },
			layers = {
				{
					texture = "star",
					count = 8,
					color = "perfect",
					lifetime = { 0.3, 0.5 },
					speed = { 7, 14 },
					spread = 180,
					size = { { 0, 0.2 }, { 0.2, 0.7 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					drag = 5,
					rotation = { 0, 360 },
					rotSpeed = { -300, 300 },
					light = 0.35,
					z = 0.5,
				},
				{
					texture = "flash",
					extra = true,
					count = 6,
					color = "white",
					lifetime = { 0.2, 0.4 },
					speed = { 4, 10 },
					spread = 180,
					size = { { 0, 0 }, { 0.3, 0.9 }, { 1, 0 } },
					transparency = { { 0, 0.1 }, { 1, 0.4 } },
					drag = 5,
					light = 1,
					z = 0.6,
				},
				{
					texture = "flash",
					count = 1,
					color = "perfect",
					lifetime = { 0.14, 0.14 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 2.5 }, { 1, 5 } },
					transparency = { { 0, 0.15 }, { 1, 1 } },
					light = 0.9,
					z = 0.8,
				},
				{
					texture = "ring",
					count = 1,
					color = "perfect",
					lifetime = { 0.26, 0.26 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 0.8 }, { 1, 4.5 } },
					transparency = { { 0, 0.2 }, { 1, 1 } },
					light = 0.6,
					z = 0.7,
				},
			},
		},

		-- the knocked down body hits the ground: soft pastel puffs of dust
		knockdownDust = {
			budget = { particles = 6, duration = 0.65 },
			layers = {
				{
					texture = "cloud",
					count = 3,
					color = "dustPink",
					lifetime = { 0.45, 0.65 },
					speed = { 10, 16 },
					spread = 88,
					size = { { 0, 1.6 }, { 0.4, 3 }, { 1, 3.8 } },
					transparency = { { 0, 0 }, { 0.45, 0.15 }, { 1, 1 } },
					accel = 3,
					drag = 4,
					rotation = { 0, 360 },
					rotSpeed = { -40, 40 },
					z = 1, -- in front of the body lying in it
				},
				{
					texture = "cloud",
					count = 3,
					color = "dustBlue",
					lifetime = { 0.45, 0.65 },
					speed = { 10, 16 },
					spread = 88,
					size = { { 0, 1.4 }, { 0.4, 2.6 }, { 1, 3.4 } },
					transparency = { { 0, 0 }, { 0.45, 0.15 }, { 1, 1 } },
					accel = 3,
					drag = 4,
					rotation = { 0, 360 },
					rotSpeed = { -40, 40 },
					z = 1, -- in front of the body lying in it
				},
			},
		},
	},

	-- the hit effect's size by what was hit, and how far in front of the victim's body it shows (towards the thrower)
	hit = { headshotScale = 1.3, worldScale = 1, lift = 0.35 },

	-- the perfect throw's ball in flight (BallVisual's streak and twinkles, dressed by Vfx.Effects.PerfectThrow): a
	-- glowing green streak and small stars falling off it. rate x lifetime is its budget of particles.
	perfectTrail = {
		budget = { particles = 16 },
		rate = 40, -- stars per second at the high quality
		lifetime = 0.4,
		size = 0.42,
		trailLifetime = 1.5, -- times the normal streak's
		trailLight = 0.9,
	},

	-- the stars circling over a knocked down head for as long as they lie there (a BillboardGui on the head): `count`
	-- at the high quality, never fewer than `min`
	knockdownStars = {
		count = 5,
		min = 3,
		color = "gold",
		height = 1.9, -- studs above the head's centre
		width = 4.2, -- studs across the circle; it is seen from the side, `tilt` of that tall
		tilt = 0.32,
		starSize = 0.3, -- share of the width, the nearest star; the farthest is `farScale` of that
		farScale = 0.6,
		turns = 0.9, -- per second
		fade = 0.25, -- seconds in and out
	},
	-- seconds after the knocking hit the dust rises: the body is down by then
	knockdownDustDelay = 0.28,
}
