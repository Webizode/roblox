--!strict
-- The leaderboard signs in the hub (LeaderboardService): the global top players by coins, from an OrderedDataStore.
-- The coins themselves are saved by DataService (ProfileStore); the ordered store only keeps a copy for the ranking.

return {
	storeName = "CoinsTop",
	-- Studio ranks into its own store (as Config/Save.studioSuffix), so playtests never show up on the live boards
	studioSuffix = "_Studio",
	-- places on a board (read from the store and shown): the board shows visibleRows of them and scrolls (wheel, a
	-- finger, the kit's bar). 10 without scrolling until 25.11.2026. GetSortedAsync reads count x 2 (at most 100).
	count = 50,
	visibleRows = 10,
	-- the ranking for the clients' boards: ReplicatedStorage.<publishName>, JSON (LeaderboardService.render)
	publishName = "LeaderboardTop",
	refreshSeconds = 90, -- how often the top list is read (60 to 120; one GetSortedAsync per refresh for all boards)
	writeSeconds = 60, -- a player's coins go to the ordered store at most this often, and when they leave
	retrySeconds = 15, -- after a failed read or write, the next try waits this long (it doubles up to 4x)

	-- the signs: every Model with this name anywhere under the map that has the invisible parts Display (the board)
	-- and Header (the plank above it), made by assets/DecoKit/studio_decokit_templates.luau
	modelName = "Leaderboard",
	title = "LEADERBOARD",
	emptyText = "Serve towers to get on the board!",

	pixelsPerStud = 50,
	colours = {
		text = "#FFF5E8", -- cream on the chocolate board
		dim = "#E8C9A8",
		titleText = "#FFFFFF",
		titleStroke = "#6A3F2A",
		rowStripe = "#5A3320", -- every second row, a shade darker than the board
		-- places 1 to 3: the badge behind the place number and the coins in the same colour
		top = { "#F2C94C", "#D8DEE6", "#E09A5B" },
	},
}
