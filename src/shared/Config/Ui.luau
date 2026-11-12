--!strict
-- The UI kit's data (client/UiKit, UiLayout): the uploaded icons, the UI colours, the sizes of the HUD's clusters and
-- the shortcuts. Sizes are design pixels at the reference screen (1280 x 720); UiLayout turns them into a scale per
-- screen, so nothing is a fixed pixel size. The world's colours stay in Config/Palette, the rarity colours in
-- Config/Flavors.rarityColors.

return {
	-- icons cut out of the reference images (vault: Wobble Scoops/UI Vorschau/Icons), square, transparent
	icons = {
		plot = "rbxassetid://113523886784043", -- the house
		arena = "rbxassetid://75998445760866", -- two crossed cones
		upgrades = "rbxassetid://124439116105602", -- gear and mint cone
		cosmetics = "rbxassetid://95123446336843", -- cone with a cap
		quests = "rbxassetid://108351844801919", -- the scroll
		index = "rbxassetid://106084334264959", -- the book
		scoops = "rbxassetid://121681267523913", -- the stacked cone (also the tower display)
		settings = "rbxassetid://96059334174196", -- the gear
		coin = "rbxassetid://83326856542751",
		safe = "rbxassetid://87719825085359", -- the shield with a cone
		scoop = "rbxassetid://71686654409619", -- a loaded ice ball
		scoopEmpty = "rbxassetid://136488453883477", -- a spent one
		ammo = "rbxassetid://88516473493521", -- the tilted ice ball of the ammo display, loaded
		ammoEmpty = "rbxassetid://124448814262592", -- the same, greyed out: spent
		-- the balance gauge's frame: chocolate rim, icing and the cone on top, the inside cut out (balanceHole)
		balanceFrame = "rbxassetid://79214398588122",
		dashEmpty = "rbxassetid://129572576307748", -- the dash bar's slanted glass, grey
		dashFull = "rbxassetid://88072122245500", -- the same, blue and glowing
		sparkle = "rbxassetid://73467077175850", -- two little stars, when the dash bar is full again
	},

	-- the UI's colours, stronger than the world's pastels so buttons read on the beach (from the reference images)
	colors = {
		outline = "#3B2016", -- chocolate, round every button, card and word
		cream = "#FFF4DC",
		creamDark = "#F2D9AE",
		mint = "#2FD99A",
		red = "#F2445A",
		sky = "#2EA6F2",
		purple = "#9B5BF0",
		pink = "#F25CC8",
		yellow = "#FFC61E",
		silver = "#D9DDE6",
		chocolate = "#6A3F2A",
		locked = "#A9A3A0",
		text = "#FFFFFF",
		textDark = "#3B2016",
		select = "#FFE14D", -- the gamepad's selection frame
		shadow = "#000000",
	},

	font = "FredokaOne", -- Enum.Font name (Theme turns it into the Enum)

	-- design sizes (pixels at 1280 x 720)
	reference = { width = 1280, height = 720 },
	stroke = 3, -- the chocolate outline
	textStroke = 2.5,
	corner = 16,
	shadow = 4, -- the dark edge under a button
	margin = 14, -- to the screen's (safe) edge
	gap = 10,
	thumb = 44, -- the smallest touch target, in screen pixels

	iconButton = 72,
	wideButton = { width = 200, height = 64 },
	safeSign = { width = 168, height = 34 },
	settingsButton = 58,
	coins = { width = 186, height = 46 },
	bottom = { width = 190, height = 60 }, -- the tower pill
	-- the three ice balls, bottom right (combat mode only): one overlapping row, the left one in front; each next one
	-- `step` further right (a third under the one before), `rise` higher and `shrink` times as big
	ammo = { width = 236, height = 106, ball = 105, step = 70, rise = 8, shrink = 0.94 },
	-- the dash bar under the ice balls, as wide as their row (the arena); `slice` is the share of the image's height the
	-- slanted ends keep unstretched
	dash = { height = 22, slice = 0.22 },
	topEdge = 6, -- from the top of the screen to MY PLOT, ARENA and the gear, in the free part of Roblox's top bar
	-- the round balance gauge (the arena): the frame image's size, and its hole where the disc, the ring and the dot are
	-- drawn: the centre as shares of the width and the height from the top left, the radius as a share of the width
	balance = { width = 110, height = 154, hole = { x = 0.5, y = 0.64, radius = 0.363 } },
	quickButton = 64, -- the small MY PLOT button in combat mode, top centre
	touchIconScale = 1.3, -- the left icon buttons' tap area on touch screens (their picture: times touchFace)
	-- on touch screens the HUD's buttons (their picture, not their tap area) and the ice-ball group bottom right are
	-- drawn this much smaller, so they cover less of the screen
	touchFace = 0.83,

	-- scale = the screen's size over the reference, within these bounds; on touch never smaller than a thumb allows
	scale = { min = 0.55, max = 1.6 },
	-- a TV gets this share of its size as extra margin (overscan)
	tvMargin = 0.05,
	-- phones: shorter side at most this many pixels
	phoneMaxSide = 500,

	-- where Roblox's touch controls sit, as shares of the screen (x, y from the top left, w, h): the thumbstick bottom
	-- left, the jump button and the action buttons (Combat, Throw, Dash, ...) bottom right. Nothing of the HUD goes there.
	touchZones = {
		stick = { x = 0, y = 0.55, w = 0.4, h = 0.45 },
		buttons = { x = 0.62, y = 0.42, w = 0.38, h = 0.58 },
	},

	-- PC shortcuts of the navigation, in its order (the left column, then the big buttons)
	keys = {
		upgrades = "One",
		cosmetics = "Two",
		quests = "Three",
		index = "Four",
		scoops = "Five",
		plot = "H",
		arena = "T",
	},
	-- the gamepad: into the left column, and the settings (SettingsController)
	gamepad = { navigation = "DPadLeft", settings = "DPadUp", close = "ButtonB" },

	anim = { press = 0.07, pop = 0.16, hover = 0.1 },
}
