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
		-- width/2 - rim. Flat markers with a name for now; the Sell Cart sits at the bridge with the ServePoint in it.
		zones = {
			{ id = "WorkingStation", name = "WORKING STATION", width = 39, color = "#9DE0C4" },
			{ id = "SellCart", name = "SELL CART", width = 26, color = "#FFD23F" },
			{ id = "ScoopChest", name = "SCOOP CHEST", width = 19.5, color = "#FF8FA3" },
			{ id = "Upgrades", name = "UPGRADES", width = 19.5, color = "#A0C4FF" },
		},
		serveInset = 6, -- studs from the inner side to the ServePoint, on the lane (the bridgehead)
		signAt = { u = 13, inset = 2 }, -- the plot sign: beside the bridgehead, facing the bridge
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
		-- never a landing spot: roofs, palms, lamps, lollipops, bushes, the fence, decorations, the cover, the machine
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
		},
		blockedNamePrefixes = { "Poręcz", "Gałka" }, -- platform railings and the knobs on them
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

	-- thrown balls fly through thin decoration (garlands, lamps, lollipops, palm leaves and coconuts); palm trunks,
	-- stands, the fence and the cover in Covery stop them like any other solid part
	throwPassFolders = { "Girlandy", "Latarnie", "Lizaki" },
	throwPassNames = { "PalmLeaf", "Coconut" },
}
