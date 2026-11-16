--!strict
-- The color tokens of the pier. Use these instead of ad-hoc colors so the world reads as one style.

return {
	vanilla = "#FFF3D6",
	strawberry = "#FF8FA3",
	mint = "#9DE0C4",
	chocolate = "#6A3F2A",
	waffle = "#E2AE62",
	sea = "#2D7DA8",
	skyTop = "#9AD7FF",
	skyBottom = "#FFB87A",
	lemon = "#FFD23F",
	awning = "#E5484D",
	ink = "#2B2D42",
	white = "#FFFFFF", -- the crosshair's default colour

	-- the main colour of each plot's flavour, Plot_01 to Plot_12 (the map's sector colours, assets/MapColors: Mint,
	-- Mango, Blaubeere, Zitrone, Lavendel, Erdbeere, Pistazie, Bubblegum, Karamell, Himmelblau, Schoko, Kirsche): the
	-- glaze on a player's waffle backpack (Backpacks)
	plotFlavors = {
		"#7FE0B8",
		"#FF6F12",
		"#6F7BEA",
		"#FFE15A",
		"#BB9CF0",
		"#FF7480",
		"#B4D46A",
		"#F06AAE",
		"#C8792F",
		"#75D6F2",
		"#9A6244",
		"#D7304E",
	},

	-- one per plot (PlotService sets it as the PlayerColor attribute): marks what belongs to a player, like the glow
	-- of their spilled scoops. Bright and far apart, so they read on the deck and on small screens.
	playerColors = {
		"#3A86FF",
		"#FF006E",
		"#FFBE0B",
		"#8338EC",
		"#06D6A0",
		"#FB5607",
		"#00B4D8",
		"#70E000",
		"#C1121F",
		"#F15BB5",
		"#5E60CE",
		"#2EC4B6",
	},
}
