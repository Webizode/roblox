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
		coin = "rbxassetid://94064830097616", -- Vfx_Coin.png, 4 x 4 frames: one turn of a spinning coin
	},

	colors = {
		white = "#FFFFFF",
		gold = "#FFD23F", -- Palette.lemon: the headshot's stars, the stars over a knocked down head
		perfect = "#3DDC84", -- Config/Combat crosshair.perfectColor: the green of the charge arc
		perfectDeep = "#1E9E5A",
		safe = "#7FE3B0", -- the safe zone's mint, the green of the "SAVED!" message
		ringOutline = "#633F52", -- Berry, the landing circle's outline: carries a pale ring on the light floor
		safeRing = "#2FCB8A", -- the same, strong enough for a thin ring on the cream floor
		sprinklePink = "#FF8FA3",
		sprinkleMint = "#7FD9B6",
		sprinkleLemon = "#FFD23F",
		-- pastel, but strong enough to read on the arena's cream floor
		dustPink = "#FF9DBC",
		gummy = "#FF4F8B", -- the gummy bear pads (Arena Kit 2)
		dustBlue = "#9FD3F5",
		dustCream = "#EBCDA8", -- a dash's dust: the floor's cream, a shade darker so it reads on it
		coin = "#FFD23F", -- Palette.lemon, the coin of the HUD
		coinLight = "#FFF1B0",
		confettiBlue = "#7CC8F2",
		steam = "#FFF8F0", -- the Big Swirl's steam: warm white
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

	-- The light, lasting particles round a legendary scoop while it flies or lies on the ground (ScoopAura; never on a
	-- tower, 18.11.2026), each legendary flavor its own. Only within `maxDistance` studs of the camera and only the
	-- `maxShown` nearest at once; the VFX quality scales the rate (`quality`, low: none). Per flavor: a texture of
	-- `textures`, two colours (a gradient over the life), particles per second, size and life (min, max), speed (min,
	-- max, studs per second, in all directions, from the whole scoop), `rise` (studs per second squared, negative falls:
	-- snow, petals), `spin` (degrees per second) and `light` (LightEmission).
	-- The rarity beacon (ScoopBeacon, 18.11.2026): a soft light column in the rarity's colour (Config/Flavors
	-- rarityColors) over a scoop lying on the ground, so its rarity reads from far away. Only from rare on; the rarer,
	-- the higher and wider. A Beam facing the camera, see-through towards its top. Budget like the auras: only the
	-- maxShown nearest within maxDistance show (low VFX quality: half as many), checked every `check` seconds.
	beacons = {
		maxDistance = 260,
		maxShown = 16,
		check = 0.3,
		quality = { high = 1, medium = 1, low = 0.5 },
		-- height and width in studs, `transparency` at its foot (its top is fully see-through)
		byRarity = {
			rare = { height = 7, width = 0.9, transparency = 0.55 },
			epic = { height = 10, width = 1.2, transparency = 0.45 },
			legendary = { height = 14, width = 1.6, transparency = 0.35 },
			mythic = { height = 17, width = 1.9, transparency = 0.3 },
			secret = { height = 19, width = 2.1, transparency = 0.25 },
			divine = { height = 22, width = 2.4, transparency = 0.2 },
		},
	},

	-- A scoop's rarity in flight (19.11.2026, RarityFlight, ShotRenderer, SwirlAnnounce, RarityBanner): readable while
	-- it flies, not only when it lands. Colours are the rarity's (Config/Flavors rarityColors, like the name signs and
	-- landing circles), `color` overrides (legendary: gold). Per rarity:
	--   trail      width (studs), lifetime (s), transparency at the scoop, lightEmission; none for common
	--   glow       a PointLight on the scoop: brightness, range (studs)
	--   sparks     particles per second from the scoop
	--   highlight  a golden outline on the scoop (Highlight; only legendary and up, Roblox shows few at once)
	--   sound      played at the release (Config/Sounds), heard up to `hearing` studs
	--   announce   the Big Swirl before it fires: "flash" (a short burst of light) or "glow" (it glows for `time` s and
	--              this one shot leaves `delay` s later, the others keep their beat), in `color` or the rarity's
	--   banner     "LEGENDARY!" at the top of the screen for everybody in the arena, with the flavor's name
	-- `like` takes another rarity's look (mythic, secret and divine are not designed yet).
	flight = {
		byRarity = {
			common = {},
			uncommon = {
				trail = { width = 0.5, lifetime = 0.25, transparency = 0.35, lightEmission = 0.3 },
			},
			rare = {
				trail = { width = 0.8, lifetime = 0.35, transparency = 0.25, lightEmission = 0.5 },
				glow = { brightness = 1.5, range = 8 },
			},
			epic = {
				trail = { width = 1.4, lifetime = 0.5, transparency = 0.15, lightEmission = 0.8 },
				glow = { brightness = 2.5, range = 11 },
				sparks = 18,
				sound = "flightEpic",
				announce = { kind = "flash", time = 0.35, brightness = 6, range = 40 },
			},
			legendary = {
				color = "#FFD23F", -- gold (Palette.lemon)
				trail = { width = 2.2, lifetime = 0.7, transparency = 0.05, lightEmission = 1 },
				glow = { brightness = 4, range = 16 },
				sparks = 40,
				highlight = true,
				sound = "flightLegendary",
				announce = { kind = "glow", time = 1, delay = 1, brightness = 8, range = 60 },
				banner = true,
			},
			mythic = { like = "legendary" },
			secret = { like = "legendary" },
			divine = { like = "legendary" },
		},
		-- VFX quality (Settings; performance mode counts as low): the trail's lifetime share, the sparks' share, and
		-- whether lights and the highlight show. Low keeps only the trail. The Big Swirl's announcement shows always.
		quality = {
			high = { lifetime = 1, sparks = 1, light = true },
			medium = { lifetime = 0.8, sparks = 0.5, light = true },
			low = { lifetime = 0.6, sparks = 0, light = false },
		},
		hearing = 260, -- studs the release sounds carry (the arena is about 300 across)
		banner = {
			time = 2.6, -- seconds on screen
			popTime = 0.3,
			fadeTime = 0.4,
			top = 0.13, -- share of the screen height from the top to its middle
			width = 520, -- pixels at a 1080 high screen, scaled with it
			height = 120,
		},
	},

	auras = {
		maxDistance = 70,
		maxShown = 10,
		check = 0.25, -- seconds between looks at distance and quality
		quality = { high = 1, medium = 0.5, low = 0 },
		kinds = {
			royal_cream = {
				texture = "star",
				colors = { "#FFD54A", "#B57BFF" },
				rate = 5,
				size = { 0.18, 0.32 },
				life = { 0.8, 1.4 },
				speed = { 0.4, 1.0 },
				rise = 0.6,
				spin = 90,
				light = 0.6,
			}, -- gold and purple glitter
			midnight_berry = {
				texture = "star",
				colors = { "#D63FA8", "#6A2FA0" },
				rate = 4,
				size = { 0.15, 0.28 },
				life = { 1.0, 1.6 },
				speed = { 0.2, 0.6 },
				rise = 0.3,
				spin = 60,
				light = 0.5,
			}, -- night sparkles
			frosted_melon = {
				texture = "star",
				colors = { "#FFFFFF", "#BFEFFF" },
				rate = 5,
				size = { 0.14, 0.26 },
				life = { 1.2, 1.8 },
				speed = { 0.2, 0.5 },
				rise = -0.8,
				spin = 45,
				light = 0.3,
			}, -- snowflakes
			velvet_dream = {
				texture = "blob",
				colors = { "#FFD0DC", "#F08AA8" },
				rate = 4,
				size = { 0.16, 0.3 },
				life = { 0.8, 1.3 },
				speed = { 0.3, 0.7 },
				rise = 0.7,
				spin = 0,
				light = 0.4,
			}, -- soft pink bubbles
			mystic_plum = {
				texture = "star",
				colors = { "#FFD24A", "#E6B8F2" },
				rate = 4,
				size = { 0.16, 0.3 },
				life = { 1.0, 1.5 },
				speed = { 0.3, 0.6 },
				rise = 0.2,
				spin = 120,
				light = 0.7,
			}, -- golden moon dust
			arctic_coconut = {
				texture = "star",
				colors = { "#FFFFFF", "#7FD4FF" },
				rate = 6,
				size = { 0.12, 0.22 },
				life = { 1.2, 1.8 },
				speed = { 0.2, 0.4 },
				rise = -1.0,
				spin = 30,
				light = 0.3,
			}, -- fine snow
			crimson_velvet = {
				texture = "flash",
				colors = { "#FFC24A", "#E0182E" },
				rate = 6,
				size = { 0.1, 0.2 },
				life = { 0.5, 0.9 },
				speed = { 0.6, 1.4 },
				rise = 1.6,
				spin = 0,
				light = 0.9,
			}, -- small sparks
			honey_blossom = {
				texture = "drop",
				colors = { "#FFFFFF", "#FFD6B8" },
				rate = 3,
				size = { 0.2, 0.32 },
				life = { 1.4, 2.0 },
				speed = { 0.3, 0.6 },
				rise = -0.6,
				spin = 140,
				light = 0.1,
			}, -- petals
			velvet_mocha = {
				texture = "cloud",
				colors = { "#FFF0DC", "#C8A080" },
				rate = 3,
				size = { 0.3, 0.5 },
				life = { 1.0, 1.6 },
				speed = { 0.1, 0.3 },
				rise = 0.8,
				spin = 20,
				light = 0.0,
			}, -- warm steam
			sapphire_cream = {
				texture = "star",
				colors = { "#9EB0FF", "#1E3FBF" },
				rate = 5,
				size = { 0.16, 0.3 },
				life = { 0.8, 1.3 },
				speed = { 0.3, 0.8 },
				rise = 0.4,
				spin = 100,
				light = 0.8,
			}, -- blue sparkle
		},
	},

	-- camera jolts (Vfx.Camera); the camera shake setting switches all of them off. The victim's shakes are in
	-- Config/Movement (hitShake, landShake).
	camera = {
		hitThrower = { degrees = 0.45, time = 0.14 }, -- the local player's ball hit somebody
		headshotThrower = { degrees = 0.8, time = 0.18 },
		toppleOwner = { degrees = 1.4, time = 0.3 }, -- the local player's own tower topples (a shake)
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

		-- a tower topples (its scoops fly apart as free scoops, LootRenderer): a puff of cream where it stood, blobs in
		-- the colour of its scoops and sprinkles
		topple = {
			budget = { particles = 22, duration = 0.7 },
			layers = {
				{
					texture = "cloud",
					count = 6,
					color = "scoop",
					lighten = 0.6,
					lifetime = { 0.45, 0.7 },
					speed = { 5, 10 },
					spread = 180,
					size = { { 0, 1.6 }, { 0.4, 3.2 }, { 1, 4 } },
					transparency = { { 0, 0 }, { 0.5, 0.1 }, { 1, 1 } },
					drag = 4,
					rotation = { 0, 360 },
					rotSpeed = { -40, 40 },
				},
				{
					texture = "blob",
					count = 6,
					color = "scoop",
					lifetime = { 0.4, 0.65 },
					speed = { 10, 18 },
					spread = 120,
					size = { { 0, 0.8 }, { 0.6, 0.6 }, { 1, 0.1 } },
					transparency = { { 0, 0 }, { 0.85, 0 }, { 1, 1 } },
					accel = -38,
					drag = 2,
					rotation = { 0, 360 },
					rotSpeed = { -220, 220 },
					z = 0.3,
				},
				{
					texture = "sprinkle",
					count = 4,
					color = "sprinkleLemon",
					lifetime = { 0.45, 0.7 },
					speed = { 12, 22 },
					spread = 120,
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
					extra = true,
					count = 4,
					color = "sprinkleMint",
					lifetime = { 0.45, 0.7 },
					speed = { 12, 22 },
					spread = 120,
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
					lifetime = { 0.14, 0.14 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 3.5 }, { 1, 7 } },
					transparency = { { 0, 0.15 }, { 1, 1 } },
					light = 0.8,
					z = 1,
				},
				{
					texture = "ring",
					count = 1,
					color = "white",
					lifetime = { 0.3, 0.3 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 1.5 }, { 1, 7 } },
					transparency = { { 0, 0.3 }, { 1, 1 } },
					z = 0.8,
				},
			},
		},

		-- "SAVED!": the local player comes out of the arena into the safe zone with a groaning tower. Stars rise
		-- along the tower (and mint rings spread over the ground, groundRings.saved)
		saved = {
			budget = { particles = 14, duration = 0.8 },
			layers = {
				{
					texture = "star",
					count = 8,
					color = "safe",
					lifetime = { 0.5, 0.8 },
					speed = { 14, 22 },
					spread = 42,
					size = { { 0, 0.3 }, { 0.2, 1.1 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					drag = 2.5,
					rotation = { 0, 360 },
					rotSpeed = { -240, 240 },
					light = 0.2,
					z = 1.5,
				},
				{
					texture = "flash",
					extra = true,
					count = 6,
					color = "white",
					lifetime = { 0.35, 0.6 },
					speed = { 6, 12 },
					spread = 35,
					size = { { 0, 0 }, { 0.3, 1 }, { 1, 0 } },
					transparency = { { 0, 0.1 }, { 1, 0.4 } },
					drag = 2.5,
					light = 1,
					z = 1.6,
				},
			},
		},

		-- the smaller "SAVED!": the tower catches itself while still in the arena
		savedSmall = {
			budget = { particles = 4, duration = 0.6 },
			layers = {
				{
					texture = "star",
					count = 4,
					color = "safe",
					lifetime = { 0.4, 0.6 },
					speed = { 7, 11 },
					spread = 30,
					size = { { 0, 0.15 }, { 0.2, 0.5 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					drag = 2.5,
					rotation = { 0, 360 },
					rotSpeed = { -240, 240 },
					z = 0.6,
				},
			},
		},

		-- a scoop from the Big Swirl is caught: a pop of small stars in its colour where it lands on the tower
		catch = {
			budget = { particles = 8, duration = 0.5 },
			layers = {
				{
					texture = "star",
					count = 4,
					color = "scoop",
					lifetime = { 0.3, 0.5 },
					speed = { 6, 11 },
					spread = 180,
					size = { { 0, 0.15 }, { 0.2, 0.55 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					drag = 5,
					rotation = { 0, 360 },
					rotSpeed = { -300, 300 },
					z = 0.5,
				},
				{
					texture = "flash",
					extra = true,
					count = 3,
					color = "white",
					lifetime = { 0.2, 0.35 },
					speed = { 4, 8 },
					spread = 180,
					size = { { 0, 0 }, { 0.3, 0.7 }, { 1, 0 } },
					transparency = { { 0, 0.1 }, { 1, 0.4 } },
					drag = 5,
					light = 1,
					z = 0.6,
				},
				{
					texture = "ring",
					count = 1,
					color = "scoop",
					lighten = 0.25,
					lifetime = { 0.25, 0.25 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 0.8 }, { 1, 3.6 } },
					transparency = { { 0, 0.15 }, { 1, 1 } },
					z = 0.4,
				},
			},
		},
		-- luck turned a caught scoop rarer (Effects/Lucky, only the catcher): a bright flash on it, stars in the new
		-- rarity's colour burst out and a ring in that colour (passed as the "scoop" colour)
		lucky = {
			budget = { particles = 14, duration = 0.7 },
			layers = {
				{
					texture = "flash",
					count = 2,
					color = "white",
					lifetime = { 0.25, 0.35 },
					speed = { 0, 1 },
					spread = 180,
					size = { { 0, 1 }, { 0.35, 4.5 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0.6 } },
					light = 1,
					z = 0.8,
				},
				{
					texture = "star",
					count = 8,
					color = "scoop",
					lighten = 0.2,
					lifetime = { 0.45, 0.7 },
					speed = { 10, 18 },
					spread = 180,
					size = { { 0, 0.2 }, { 0.2, 0.9 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					drag = 4,
					rotation = { 0, 360 },
					rotSpeed = { -360, 360 },
					light = 0.6,
					z = 0.7,
				},
				{
					texture = "ring",
					count = 1,
					color = "scoop",
					lighten = 0.3,
					lifetime = { 0.4, 0.4 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 1.5 }, { 1, 7 } },
					transparency = { { 0, 0 }, { 1, 1 } },
					light = 0.5,
					z = 0.6,
				},
			},
		},

		-- a free scoop is picked up from the ground: a small pop, drops of its colour hop up
		pickup = {
			budget = { particles = 5, duration = 0.45 },
			layers = {
				{
					texture = "drop",
					orient = "velocity",
					count = 3,
					color = "scoop",
					lifetime = { 0.3, 0.45 },
					speed = { 9, 14 },
					spread = 40,
					size = { { 0, 0.45 }, { 1, 0.1 } },
					transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } },
					accel = -40,
					z = 0.3,
				},
				{
					texture = "star",
					extra = true,
					count = 2,
					color = "white",
					lifetime = { 0.25, 0.4 },
					speed = { 5, 9 },
					spread = 60,
					size = { { 0, 0.15 }, { 0.3, 0.45 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					drag = 4,
					rotation = { 0, 360 },
					rotSpeed = { -300, 300 },
					z = 0.4,
				},
			},
		},

		-- a gummy pad throws a player up (Config/Bounce): a soft puff around its rim and gummy drops jumping off
		bounce = {
			budget = { particles = 8, duration = 0.55 },
			layers = {
				{
					texture = "cloud",
					count = 4,
					color = "white",
					lifetime = { 0.35, 0.55 },
					speed = { 9, 14 },
					spread = 85,
					size = { { 0, 1.2 }, { 0.4, 2.4 }, { 1, 3 } },
					transparency = { { 0, 0.1 }, { 0.45, 0.25 }, { 1, 1 } },
					accel = 2,
					drag = 4,
					rotation = { 0, 360 },
					rotSpeed = { -40, 40 },
					z = 0.5,
				},
				{
					texture = "drop",
					orient = "velocity",
					count = 4,
					color = "gummy",
					lifetime = { 0.3, 0.5 },
					speed = { 12, 18 },
					spread = 35,
					size = { { 0, 0.5 }, { 1, 0.12 } },
					transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } },
					accel = -45,
					z = 0.3,
				},
			},
		},

		-- round 3 ---------------------------------------------------------------------------------------------------

		-- scoops are served: coins spin up out of the player and rain back down, a little confetti, a short flash,
		-- bigger with more scoops (Config/Vfx.serve). The local player's coins also fly to the coin counter (UI).
		-- the Scoop Chest opens (Effects/Chest): golden stars rise out of it with a few white glints and sprinkles, a
		-- soft golden flash in the opening. Start at once, peak at 0.3 s while the lid swings up, gone by 1.1 s.
		chestOpen = {
			budget = { particles = 26, duration = 1.2 },
			layers = {
				{
					texture = "star",
					count = 12,
					color = "gold",
					lifetime = { 0.7, 1.1 },
					speed = { 6, 12 },
					spread = 35,
					size = { { 0, 0.2 }, { 0.2, 0.9 }, { 0.75, 0.7 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0.2 } },
					accel = 2,
					drag = 1.6,
					rotation = { 0, 360 },
					rotSpeed = { -200, 200 },
					light = 0.4,
					z = 0.6,
				},
				{
					texture = "star",
					extra = true,
					count = 6,
					color = "white",
					lifetime = { 0.5, 0.8 },
					speed = { 4, 9 },
					spread = 50,
					size = { { 0, 0.1 }, { 0.3, 0.5 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					drag = 2,
					rotation = { 0, 360 },
					rotSpeed = { -360, 360 },
					light = 0.8,
					z = 0.7,
				},
				{
					texture = "sprinkle",
					count = 6,
					color = "sprinklePink",
					lifetime = { 0.8, 1.1 },
					speed = { 10, 16 },
					spread = 40,
					size = { { 0, 0.35 }, { 0.85, 0.35 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = -24,
					drag = 1.2,
					rotation = { 0, 360 },
					rotSpeed = { -540, 540 },
					z = 0.4,
				},
				{
					texture = "flash",
					count = 1,
					color = "gold",
					lifetime = { 0.3, 0.3 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 2 }, { 1, 7 } },
					transparency = { { 0, 0.35 }, { 1, 1 } },
					light = 1,
					z = 0.2,
				},
			},
		},
		-- while the chest stands open: now and then a glint rises slowly out of it (Config/Chest.glintEvery)
		chestGlint = {
			budget = { particles = 4, duration = 1 },
			reach = 0.6, -- only close by: the distances times 0.6
			layers = {
				{
					texture = "star",
					count = 2,
					color = "white",
					lifetime = { 0.7, 0.9 },
					speed = { 1.5, 3 },
					spread = 25,
					size = { { 0, 0 }, { 0.3, 0.45 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = 1,
					rotation = { 0, 360 },
					rotSpeed = { -120, 120 },
					light = 0.7,
					z = 0.5,
				},
				{
					texture = "star",
					extra = true,
					count = 2,
					color = "gold",
					lifetime = { 0.7, 0.9 },
					speed = { 1.5, 3 },
					spread = 25,
					size = { { 0, 0 }, { 0.3, 0.4 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = 1,
					rotation = { 0, 360 },
					rotSpeed = { -120, 120 },
					light = 0.5,
					z = 0.5,
				},
			},
		},

		serve = {
			budget = { particles = 30, duration = 1.1 },
			layers = {
				{
					texture = "coin",
					flipbook = true,
					count = 10,
					color = "coin",
					lifetime = { 0.8, 1.05 },
					speed = { 16, 24 },
					spread = 28,
					size = { { 0, 0.5 }, { 0.15, 1.1 }, { 0.85, 1.1 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = -46,
					drag = 0.6,
					bright = 1.1,
					z = 0.5,
				},
				{
					texture = "sprinkle",
					count = 6,
					color = "sprinklePink",
					lifetime = { 0.7, 1 },
					speed = { 12, 20 },
					spread = 55,
					size = { { 0, 0.4 }, { 0.85, 0.4 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = -30,
					drag = 1.5,
					rotation = { 0, 360 },
					rotSpeed = { -540, 540 },
					z = 0.4,
				},
				{
					texture = "sprinkle",
					extra = true,
					count = 6,
					color = "confettiBlue",
					lifetime = { 0.7, 1 },
					speed = { 12, 20 },
					spread = 55,
					size = { { 0, 0.4 }, { 0.85, 0.4 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = -30,
					drag = 1.5,
					rotation = { 0, 360 },
					rotSpeed = { -540, 540 },
					z = 0.4,
				},
				{
					texture = "sprinkle",
					extra = true,
					count = 6,
					color = "sprinkleMint",
					lifetime = { 0.7, 1 },
					speed = { 12, 20 },
					spread = 55,
					size = { { 0, 0.4 }, { 0.85, 0.4 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = -30,
					drag = 1.5,
					rotation = { 0, 360 },
					rotSpeed = { -540, 540 },
					z = 0.4,
				},
				{
					texture = "flash",
					count = 1,
					color = "coinLight",
					lifetime = { 0.2, 0.2 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 2.5 }, { 1, 6 } },
					transparency = { { 0, 0.2 }, { 1, 1 } },
					light = 0.7,
					z = 1,
				},
			},
		},

		-- the Big Swirl lets a scoop go: a puff of steam out of the cup and sparks in the scoop's colour along its way
		swirlShot = {
			budget = { particles = 11, duration = 0.95 },
			reach = 2, -- distance times 2: the Big Swirl stands in the middle and is seen from all of the arena
			layers = {
				{
					texture = "cloud",
					count = 4,
					color = "steam",
					lifetime = { 0.6, 0.9 },
					speed = { 3, 7 },
					spread = 50,
					size = { { 0, 1.2 }, { 0.4, 2.6 }, { 1, 3.4 } },
					transparency = { { 0, 0.25 }, { 0.5, 0.45 }, { 1, 1 } },
					accel = 3, -- steam rises
					drag = 2,
					rotation = { 0, 360 },
					rotSpeed = { -40, 40 },
				},
				{
					texture = "star",
					count = 5,
					color = "scoop",
					lighten = 0.2,
					lifetime = { 0.3, 0.5 },
					speed = { 14, 24 },
					spread = 30,
					size = { { 0, 0.5 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = -20,
					drag = 2,
					rotation = { 0, 360 },
					rotSpeed = { -400, 400 },
					light = 0.3,
					z = 0.4,
				},
				{
					texture = "flash",
					extra = true,
					count = 2,
					color = "white",
					lifetime = { 0.15, 0.25 },
					speed = { 0, 2 },
					spread = 20,
					size = { { 0, 1.5 }, { 1, 3.5 } },
					transparency = { { 0, 0.2 }, { 1, 1 } },
					light = 0.8,
					z = 0.6,
				},
			},
		},

		-- a scoop nobody caught comes down on its landing circle: a soft puff in its colour (and a ring,
		-- groundRings.landed)
		landed = {
			budget = { particles = 6, duration = 0.6 },
			layers = {
				{
					texture = "cloud",
					count = 4,
					color = "scoop",
					lighten = 0.6,
					lifetime = { 0.4, 0.6 },
					speed = { 4, 7 },
					spread = 80,
					size = { { 0, 0.8 }, { 1, 2.2 } },
					transparency = { { 0, 0.2 }, { 1, 1 } },
					drag = 4,
					rotation = { 0, 360 },
				},
				{
					texture = "drop",
					extra = true,
					orient = "velocity",
					count = 2,
					color = "scoop",
					lifetime = { 0.3, 0.45 },
					speed = { 8, 12 },
					spread = 45,
					size = { { 0, 0.4 }, { 1, 0.1 } },
					transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } },
					accel = -40,
					z = 0.3,
				},
			},
		},

		-- a teleport, at the start and at the target: a pastel puff with sprinkles and stars (and a ring on the
		-- ground, groundRings.teleport)
		teleport = {
			budget = { particles = 22, duration = 0.8 },
			layers = {
				{
					texture = "cloud",
					count = 6,
					color = "dustPink",
					lifetime = { 0.5, 0.75 },
					speed = { 5, 10 },
					spread = 70,
					size = { { 0, 1.6 }, { 0.5, 3.4 }, { 1, 4 } },
					transparency = { { 0, 0.15 }, { 0.6, 0.35 }, { 1, 1 } },
					accel = 2,
					drag = 3,
					rotation = { 0, 360 },
					rotSpeed = { -60, 60 },
				},
				{
					texture = "cloud",
					extra = true,
					count = 4,
					color = "dustBlue",
					lifetime = { 0.5, 0.75 },
					speed = { 5, 10 },
					spread = 70,
					size = { { 0, 1.4 }, { 0.5, 3 }, { 1, 3.6 } },
					transparency = { { 0, 0.15 }, { 0.6, 0.35 }, { 1, 1 } },
					accel = 2,
					drag = 3,
					rotation = { 0, 360 },
					rotSpeed = { -60, 60 },
				},
				{
					texture = "star",
					count = 5,
					color = "white",
					lifetime = { 0.4, 0.7 },
					speed = { 8, 14 },
					spread = 60,
					size = { { 0, 0.2 }, { 0.2, 0.6 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					drag = 3,
					rotation = { 0, 360 },
					rotSpeed = { -300, 300 },
					light = 0.2,
					z = 0.8,
				},
				{
					texture = "sprinkle",
					extra = true,
					count = 6,
					color = "sprinkleLemon",
					lifetime = { 0.45, 0.7 },
					speed = { 10, 16 },
					spread = 70,
					size = { { 0, 0.4 }, { 0.8, 0.4 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = -30,
					drag = 2,
					rotation = { 0, 360 },
					rotSpeed = { -540, 540 },
					z = 0.7,
				},
				{
					texture = "flash",
					count = 1,
					color = "white",
					lifetime = { 0.18, 0.18 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 3 }, { 1, 6.5 } },
					transparency = { { 0, 0.2 }, { 1, 1 } },
					light = 0.8,
					z = 1,
				},
			},
		},

		-- a dash: dust kicked up behind the feet where it starts and where it ends (the speed lines are on the screen,
		-- dashLines; the trail, ground streak and afterimages are MovementController's)
		dashDust = {
			budget = { particles = 6, duration = 0.55 },
			layers = {
				{
					texture = "cloud",
					count = 4,
					color = "dustCream",
					lifetime = { 0.35, 0.55 },
					speed = { 4, 8 },
					spread = 55,
					size = { { 0, 0.9 }, { 1, 2.4 } },
					transparency = { { 0, 0.2 }, { 1, 1 } },
					drag = 4,
					rotation = { 0, 360 },
					rotSpeed = { -60, 60 },
				},
				{
					texture = "cloud",
					extra = true,
					count = 2,
					color = "dustPink",
					lifetime = { 0.35, 0.55 },
					speed = { 4, 8 },
					spread = 55,
					size = { { 0, 0.7 }, { 1, 2 } },
					transparency = { { 0, 0.3 }, { 1, 1 } },
					drag = 4,
					rotation = { 0, 360 },
				},
			},
		},

		-- a lying scoop in its last moment blinks: a small glint each time it lights up (lootBlink)
		blinkGlint = {
			budget = { particles = 2, duration = 0.3 },
			layers = {
				{
					texture = "star",
					count = 1,
					color = "white",
					lifetime = { 0.25, 0.25 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 0.2 }, { 0.4, 0.9 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					rotation = { 0, 45 },
					rotSpeed = { 180, 180 },
					light = 0.6,
					z = 1,
				},
				{
					texture = "flash",
					extra = true,
					count = 1,
					color = "white",
					lifetime = { 0.15, 0.15 },
					speed = { 0, 0 },
					spread = 0,
					size = { { 0, 1 }, { 1, 2.2 } },
					transparency = { { 0, 0.4 }, { 1, 1 } },
					light = 0.8,
					z = 0.9,
				},
			},
		},

		-- its time is up: it pops in a puff of its colour with a few blobs and sprinkles
		lootPuff = {
			budget = { particles = 10, duration = 0.55 },
			layers = {
				{
					texture = "cloud",
					count = 4,
					color = "scoop",
					lighten = 0.45,
					lifetime = { 0.35, 0.5 },
					speed = { 3, 6 },
					spread = 180,
					size = { { 0, 1 }, { 1, 2.6 } },
					transparency = { { 0, 0.1 }, { 1, 1 } },
					drag = 4,
					rotation = { 0, 360 },
				},
				{
					texture = "blob",
					count = 3,
					color = "scoop",
					lifetime = { 0.35, 0.5 },
					speed = { 7, 11 },
					spread = 70,
					size = { { 0, 0.45 }, { 1, 0.1 } },
					transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } },
					accel = -35,
					drag = 2,
					rotation = { 0, 360 },
					z = 0.3,
				},
				{
					texture = "sprinkle",
					extra = true,
					count = 3,
					color = "sprinklePink",
					lifetime = { 0.35, 0.5 },
					speed = { 7, 12 },
					spread = 80,
					size = { { 0, 0.35 }, { 0.8, 0.35 }, { 1, 0 } },
					transparency = { { 0, 0 }, { 1, 0 } },
					accel = -35,
					drag = 2,
					rotation = { 0, 360 },
					rotSpeed = { -540, 540 },
					z = 0.4,
				},
			},
		},
	},

	-- Rings that run out flat over the ground (Vfx.groundRings): the ring picture on a thin pooled part, growing from
	-- `from` to `to` studs across in `time` seconds while it fades from `transparency`. color as for a layer; extra:
	-- only at a quality with extras and close by. `lift`: studs above the ground, so the floor does not swallow them.
	groundRings = {
		lift = 0.15,
		saved = {
			{ color = "safeRing", from = 2, to = 13, time = 0.55, transparency = 0 },
			{ color = "white", from = 1, to = 8, time = 0.7, transparency = 0.2, extra = true },
		},
		savedSmall = {
			{ color = "safeRing", from = 1.5, to = 6.5, time = 0.4, transparency = 0.1 },
		},
		-- a caught scoop's landing circle answers in the scoop's colour
		catch = {
			{ color = "ringOutline", from = 3.1, to = 8.9, time = 0.4, transparency = 0.25 },
			{ color = "scoop", from = 2.5, to = 8, time = 0.4, transparency = 0 },
			{ color = "white", from = 1.5, to = 5, time = 0.3, transparency = 0.25, extra = true },
		},
		pickup = {
			{ color = "ringOutline", from = 1.9, to = 6.9, time = 0.35, transparency = 0.25 },
			{ color = "scoop", from = 1.5, to = 6.4, time = 0.35, transparency = 0 },
			{ color = "white", from = 1, to = 3.8, time = 0.25, transparency = 0.25, extra = true },
		},
		-- a gummy pad bounces: a ring in gummy pink runs out from its rim
		bounce = {
			{ color = "ringOutline", from = 5, to = 11, time = 0.35, transparency = 0.3 },
			{ color = "gummy", from = 4.5, to = 10.5, time = 0.35, transparency = 0 },
		},
		-- a new landing circle shows itself: a ring in the scoop's colour runs out of it (the circle is
		-- Config/TowerScoops.landingCircle.size, 7, across)
		circle = {
			{ color = "ringOutline", from = 7.4, to = 13.4, time = 0.45, transparency = 0.35 },
			{ color = "scoop", from = 7, to = 13, time = 0.45, transparency = 0 },
		},
		-- a scoop nobody caught comes down on it
		landed = {
			{ color = "scoop", from = 1.5, to = 6, time = 0.35, transparency = 0.1 },
		},
		teleport = {
			{ color = "dustPink", from = 2, to = 11, time = 0.5, transparency = 0 },
			{ color = "white", from = 1, to = 7, time = 0.4, transparency = 0.2, extra = true },
		},
	},

	-- the hit effect's size by what was hit, and how far in front of the victim's body it shows (towards the thrower)
	hit = { headshotScale = 1.3, worldScale = 1, lift = 0.35 },

	-- every thrown ball in flight, kept quiet (BallVisual's streak and twinkles, dressed by Vfx.Effects.ThrowTrail):
	-- a short pale streak towards the scoop's colour and a few small glints. A perfect throw is dressed over it.
	throwTrail = {
		budget = { particles = 6 },
		rate = 14, -- glints per second at the high quality
		lifetime = 0.4,
		size = 0.5,
		trailLifetime = 0.22, -- seconds
		trailTransparency = 0.45,
		trailLight = 0.3,
		lighten = 0.5, -- the scoop's colour mixed this far towards white
	},

	-- a toppling tower's puff: `lift` studs above the tower's foot, bigger with every scoop that flies off (up to
	-- maxScale). A spill counts as a topple only `fresh` seconds after it happened: a player who joins later gets
	-- the lying scoops without the puff.
	topple = { perScoop = 0.04, maxScale = 1.8, fresh = 1.5, lift = 3 },

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

	-- a serve's coin fountain grows with the scoops served: times `perScoop` each, up to maxScale; it rises from
	-- `lift` studs above the player's feet
	serve = { perScoop = 0.04, maxScale = 1.7, lift = 2.5 },
	-- the local player's coins fly from the character to the HUD's coin counter while it counts up: one coin per
	-- scoop, between min and max (fewer at a lower VFX quality, never fewer than min), `size` pixels at 720 px
	-- screen height, one every `gap` seconds, each `time` seconds on its way; the counter pops when the first lands
	uiCoins = { min = 3, max = 10, size = 30, gap = 0.05, time = 0.5, arc = 0.25, pop = 1.18 },

	-- speed lines over the local player's screen while dashing (with the motion effects setting): `count` thin white
	-- streaks round the edge, pointing at the middle, `length` and `width` shares of the screen height, at most
	-- `alpha` opaque; they slide `slide` of their length inwards over the dash and fade in and out in `fade` seconds
	dashLines = { count = 16, length = 0.22, width = 0.006, alpha = 0.55, slide = 0.5, fade = 0.08, inner = 0.42 },

	-- a lying scoop's last moment (Config/Loot blinkSeconds, landedBlinkSeconds): it blinks `from` times a second
	-- at the start, `to` at the end, and glints each time it lights up (blinkGlint, only close by)
	lootBlink = { from = 6, to = 14, see = 0.65, glintLift = 0.6 },
}
