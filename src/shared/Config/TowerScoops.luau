--!strict
-- The look of the tower scoops (stacked on the back, not the attack scoops): their model, the flight from the Big
-- Swirl and the trail. Purely visual; the server's flight path and catch rules stay as they are (Config/Launcher).
-- Models: ReplicatedStorage.TowerScoops.<flavor id> with the MeshParts LOD0 (close) and LOD1 (far), built in Blender
-- (assets/TowerScoops). A flavor without its model is drawn as the plain ball.

return {
	folder = "TowerScoops",
	outline = "#5A2E1A", -- one Highlight per tower, the Big Swirl's outline colour; red (Palette.awning) while it groans
	-- the client draws LOD1 from farDistance studs on (from the camera) and LOD0 again below farDistance - hysteresis
	farDistance = 40,
	hysteresis = 4,
	-- every scoop on a tower is turned a little further about its own axis than the one below it, so the lobes of a
	-- stack do not line up into stripes
	stackTwist = math.rad(37),
	-- how far the lowest drip is below the scoop's centre in the models (the same for every flavor: build_scoops.py
	-- base shape). The importer centres a mesh on its bounding box; from the bottom of that box this finds the scoop's
	-- centre, also for a flavor with something on top (the lemon slice)
	dripDepth = 0.86,

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

	-- The trail in the flavor's colour, by the flavor's rarity (Config/Flavors): the rarer, the longer and brighter the
	-- trail; golden scoops also sparkle.
	trail = {
		tiers = { common = "common", uncommon = "rare", rare = "rare", epic = "epic", legendary = "epic" },
		styles = {
			common = { lifetime = 0.18, width = 0.9, transparency = 0.45, lightEmission = 0.2, sparkles = 0 },
			rare = { lifetime = 0.3, width = 1.2, transparency = 0.3, lightEmission = 0.5, sparkles = 0 },
			epic = { lifetime = 0.4, width = 1.4, transparency = 0.2, lightEmission = 0.8, sparkles = 8 },
			golden = {
				lifetime = 0.45,
				width = 1.5,
				transparency = 0.15,
				lightEmission = 1,
				sparkles = 24,
				color = "#FFD23F", -- Palette.lemon
			},
		},
		-- VFX quality (Settings; the performance mode counts as low): the share of the trail's lifetime and of the
		-- sparkles that is left. Low keeps a short trail so a scoop can still be followed, without sparkles.
		quality = {
			high = { lifetime = 1, sparkles = 1 },
			medium = { lifetime = 0.7, sparkles = 0.5 },
			low = { lifetime = 0.45, sparkles = 0 },
		},
	},
}
