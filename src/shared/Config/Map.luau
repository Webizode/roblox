--!strict
-- The ice cream island (Workspace."Ice Cream Map") and how the game reads it: where the Big Swirl stands, where
-- the sea starts, which surfaces scoops may land on and which decorations a thrown ball flies through.
-- Folder names are the map's own top-level folders (Polish, from Kornel's first island; the 16-player graybox keeps
-- them). The contract for Workspace.Pier is in MapService.

return {
	root = "Ice Cream Map", -- the map in Workspace, never changed by the game
	pier = "Pier", -- the invisible helpers in Workspace (MapService contract)

	-- the Big Swirl (our own machine, built by MapService) stands on this part in the middle of the plaza
	machineMarker = { "Plac", "Arena_Znacznik" },
	machine = {
		bodyHeight = 22,
		bodyDiameter = 16,
		nozzleSize = 7,
		nozzleGap = 3, -- studs from the top of the body to the centre of the nozzle
	},

	-- the sea: Terrain water from the original map file. Anything below waterLevel counts as water, so the sea floor
	-- under it is never ground.
	waterLevel = -6,
	-- a player whose root is below waterLevel + respawnMargin is in the sea and respawns at the own plot
	respawnMargin = 1.5,
	waterCheckInterval = 0.25, -- seconds between the server's checks

	-- the open sea to the horizon (client only, Controllers/Ocean): the terrain sea is a 1024 x 1024 square that ends
	-- in plain sight, so every client lays one flat sea over it that follows the camera: a part of tileSize studs drawn
	-- `scale` times as wide (SpecialMesh), `lift` above waterLevel (over the terrain water, whose waves would poke through
	-- a lower sea as dark patches), so there is one look everywhere and no square edge. It moves in steps of
	-- studsPerTile, so the drifting wave picture (assets/World/make_ocean_texture.py) never jumps. No collision, queries
	-- or touch: players and scoops still fall into the terrain sea below (respawn below waterLevel + respawnMargin).
	ocean = {
		tileSize = 2048,
		scale = 24,
		lift = 0.6,
		colour = "#1E7FC2",
		-- re-uploaded 11.11.2026: the first upload (90970251688437) had no content representation and logged a warning
		texture = "rbxassetid://79801396441990", -- Ocean_Waves.png
		studsPerTile = 48,
		wavesTransparency = 0.25,
		drift = { u = 1.4, v = 0.7 }, -- studs per second: calm
	},

	-- the arena zone (ArenaZone): the sunken floor round the Big Swirl and the 12 ramps up to their top edge, where a
	-- coloured line marks the start of the safe zone. Inside, scoops fly and ice balls hit; outside (the strip, the hub,
	-- the bridges and the plot islands) nobody is hit and the teleport buttons show. One line, both ways: no hysteresis.
	-- It has to match the map (Ice Cream Map: Plac, Schody, Strefa); MapService warns when the Big Swirl's marker is
	-- not at `center`
	arena = {
		center = { x = 0, z = 0 }, -- the Big Swirl's marker
		radius = 135, -- studs from the machine to the rim
		ramps = 12, -- one on every plot lane
		firstRamp = 15, -- degrees of the first lane (from +Z towards +X); the others follow every 360 / ramps
		rampHalfWidth = 6, -- studs either side of the lane
		rampTop = 159, -- studs from the machine to a ramp's top edge, where the strip starts
		-- seconds the buttons and the "safe zone" note wait for the zone to stay the same before they change, so they do
		-- not flicker on the line; the server decides at once
		displayDelay = 0.2,
		-- studs the server adds all round when it decides on combat mode (MouseRules): it sees a player's position a
		-- little late, so one who just walked in and pressed R is not turned away, nor one still in it cut short
		serverSlack = 4,
	},
	-- seconds a player's teleport requests are at least apart: only against floods, nobody clicks that fast
	teleportMinInterval = 0.25,
	-- no teleport for this many seconds after a hit that did harm (and none while knocked down): a button is never a
	-- way out of a fight, walking out of the arena is (TeleportRules)
	teleportHitLock = 3,
	-- the shop buttons: request name -> the invisible target part (Anchored, no collision, queries or touch) somewhere
	-- under Ice Cream Map.Dekoracje.Hub, on the paved forecourt in front of the shop's counter, its front (-Z) towards
	-- the counter. With several parts of one name the nearest is taken.
	teleportTargets = {
		upgrades = "Teleport_Upgrade",
		quests = "Teleport_Quest",
		cosmetics = "Teleport_Cosmetic",
	},
	-- spots round a shop target, so players arriving together do not land on each other: studs to the target's right
	-- and back (away from the counter). The first one nobody stands on (closer than teleportSlotGap) is taken.
	teleportSlots = {
		{ 0, 0 },
		{ -3.5, 0 },
		{ 3.5, 0 },
		{ -1.75, 3 },
		{ 1.75, 3 },
		{ -5.25, 3 },
		{ 5.25, 3 },
		{ 0, 6 },
	},
	teleportSlotGap = 3,

	-- The 12 plot islands (PlotLayout), one on every lane (arena.firstRamp + k * 360 / arena.ramps), each at the end of
	-- its bridge. A rectangle `width` along the ring by `depth` along the lane, its inner long side facing the arena; the
	-- bridge meets that side in the middle. Since 04.11.2026 (before: 70 x 70 round r 327). Local coordinates: `u`
	-- along the ring, right as seen from the bridge looking out (0 on the lane), `v` along the lane, outward from the
	-- island's centre. The place has to match (MapService warns): Ice Cream Map.Plots.Plot_NN, Pier.Plots.Plot_NN.
	plot = {
		centerRadius = 322, -- studs from the machine to the island's centre
		width = 110, -- along the ring
		depth = 60, -- along the lane
		rim = 3, -- studs of island edge round the walkable surface (104 x 54)
		corner = 6, -- radius of the rounded corners
		surfaceY = 9, -- top of the walkable surface (the strip and the bridges are at this height too)
		bridgeHalfWidth = 9, -- the bridge (Ice Cream Map.Mosty, 18 wide, unchanged) meets the inner side here
		bridgeEnd = 295, -- studs from the machine to where the bridge ends, a little onto the island
		-- the zones side by side along the ring, left to right as seen from the bridge, from u = -width/2 + rim to
		-- width/2 - rim, one round each station (since 06.11.2026; before four, with Upgrades on the right: upgrades
		-- go to the hub island). The graybox markers (Strefy) are hidden, the plot kit's models stand there.
		zones = {
			{ id = "WorkingStation", name = "WORKING STATION", width = 34, color = "#9DE0C4" },
			{ id = "SellCart", name = "SELL CART", width = 36, color = "#FFD23F" },
			{ id = "ScoopChest", name = "SCOOP CHEST", width = 34, color = "#FF8FA3" },
		},
		-- The plot kit's models (assets/PlotKit/studio_plotkit_place.luau), as seen from the bridge since 06.11.2026:
		-- the Working Station on the left, the Sell Cart at the back in the middle, the Scoop Chest on the right, all
		-- facing the round plaza in the middle; paths from the bridge over the plaza to all three. Each at (u, v), its
		-- pivot (bottom middle), turned `turn` degrees (0: its front to the bridge, -v; 90: to +u). Until 05.11.2026 the
		-- Sell Cart stood at the bridgehead (0, -17), the station at the back (0, 16.5), the chest at (28, -1).
		stations = {
			SellCart = { u = 0, v = 16, turn = 0 },
			WorkingStation = { u = -36, v = -4, turn = 90 },
			ScoopChest = { u = 32, v = -4, turn = -90 },
		},
		plaza = { u = 0, v = -4 }, -- the round plaza (PathRound, 14 across)
		-- the ServePoint: in front of the Sell Cart's counter, where a player at it stands (the cart's collision ends
		-- at v 11.35); until 05.11.2026 at the bridgehead (v -24)
		serveAt = { u = 0, v = 9 },
		-- the Spawn, also where "MY PLOT" brings the player: the middle of the plaza, out of the serve radius (13 studs
		-- from the ServePoint, so a fresh catch is not served away); until 05.11.2026 the island's centre (0, 0)
		spawnAt = { u = 0, v = -4 },
		-- the plot sign at the bridgehead, right of the path, facing the bridge (the plot kit's Plot Sign; until
		-- 05.11.2026 the graybox sign at u 13, inset 2)
		signAt = { u = 24, inset = 1 },
		-- room kept round every island for a sand rim to the water later (tropical look): the islands stay at least
		-- minGap apart with it
		sandReserve = 10,
		minGap = 15,
	},

	-- where the Big Swirl may land a scoop: MapService samples a grid of spots once at the start and keeps those
	-- where a player could stand (footprint flat, surface not blocked, not water)
	landing = {
		gridStep = 2, -- studs between sampled spots
		footprint = 1.5, -- studs from the spot to the four extra rays around it
		maxStep = 0.8, -- studs of height difference within the footprint (rules out railings, lamp heads, knobs)
		minNormalY = 0.8, -- surfaces steeper than about 37 degrees are not ground
		-- never a landing spot: roofs, palms, lamps, lollipops, bushes, the fence, decorations (the arena rim and the
		-- entrance arches), the cover, the barrier over the rim, the machine. Parts outside the map (a copy dragged out
		-- of it into Workspace) are never ground either (MapRules.landingSurface).
		blockedFolders = {
			"Stoiska",
			"Covery",
			"Palmy",
			"Latarnie",
			"Lizaki",
			"Trawa",
			"Plot",
			"Dekoracje",
			"Wodospady",
			"Wysepki",
			"BigSwirl",
			"Sperre",
		},
		blockedNamePrefixes = { "Poręcz", "Gałka" }, -- platform railings and the knobs on them
		-- a free scoop (from the Big Swirl or spilled) that comes to rest on a surface nobody stands on (the cover, the
		-- rim, the arches) or inside cover is put on the nearest free ground instead (MapService.settle): searched in
		-- settleStep steps out to settleRadius studs, with `footprint` studs of ground round it; past that, the nearest
		-- landing spot
		settleStep = 1,
		settleRadius = 16,
	},

	-- the cover in the arena (MapService.prepareCover): every Model in this folder is cover, however many copies and
	-- however turned. It collides only through one invisible box, its part named `coverCollision` (made from the
	-- model's bounding box when missing); its other parts neither collide nor take queries. Being in this folder keeps
	-- scoops from landing on it (landing.blockedFolders) and stops thrown balls (not in throwPassFolders).
	coverFolder = "Covery",
	coverCollision = "Collision",
	-- studs the meshes may stick out of that box before the start makes it bigger (MapRules.coverBoxFit): scaling the
	-- whole model scales the box with it, resizing only the meshes in Studio does not
	coverFitTolerance = 0.25,
	-- the names (prefixes) of the arena kit's cover models (ServerStorage.ArenaKit): the start warns about every copy
	-- that is not in coverFolder, because only there is it cover (copies pasted into Workspace were not)
	coverKitNames = { "CoverBlock", "WaffleCrate", "IcePillar" },

	-- thrown balls fly through thin decoration (garlands, lamps, lollipops, palm leaves and coconuts); palm trunks,
	-- stands, the fence and the cover in Covery stop them like any other solid part
	throwPassFolders = { "Girlandy", "Latarnie", "Lizaki" },

	-- invisible walls that only stop players (MapRules.playersOnly): Sperre stands over the arena rim between the
	-- ramps, exactly as thick as the wall and its pillars, so a jump or a dash never takes anyone over the rim; the
	-- ramps stay open at their sides. Throws, aim, the cameras and the ground and landing rays pass through.
	playersOnlyFolders = { "Sperre" },
	throwPassNames = { "PalmLeaf", "Coconut" },
}
