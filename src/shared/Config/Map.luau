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

	-- thrown balls fly through thin decoration (garlands, lamps, lollipops, palm leaves and coconuts); palm trunks,
	-- stands, the fence and the cover in Covery stop them like any other solid part
	throwPassFolders = { "Girlandy", "Latarnie", "Lizaki" },
	throwPassNames = { "PalmLeaf", "Coconut" },
}
