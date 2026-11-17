--!strict
-- The Scoop Chest on every plot (ChestService, ScoopChest, ChestController): rare scoops are kept in it instead of
-- sold, up to three of them are equipped for small passive bonuses. All values here are placeholders to tune.
--
-- Rarities come from Config/Flavors.rarities (their order is the rank). A new rarity (Mythic, Secret, Divine are
-- planned) only needs a line in passives.byRarity and sell.byRarity here; one without a line gives no bonus and sells
-- for its flavor's value. A new passive kind needs a line in passives.kinds and its place in passives.order, and the
-- code that applies it (ChestService.bonus is read by name).

return {
	-- scoops of this rarity and rarer go into the chest when served, the rest is sold; to decide with Nik (rare or epic)
	minRarity = "rare",
	-- a scoop with a mutation (Golden, Rainbow) always goes into the chest, whatever its rarity
	storeMutations = true,
	-- scoops it holds in all (each stored scoop counts, also in a stack); a full chest sells the rest as usual
	capacity = 50,
	equipSlots = 3,

	-- the mutations a stored scoop can have. So far only data and display: the Big Swirl does not fire them yet (that
	-- comes with Features.goldenScoops); `passive` and `sell` multiply the rarity's values
	mutations = {
		order = { "golden", "rainbow" }, -- sorting within a rarity: plain first, then these
		kinds = {
			golden = { label = "Golden", color = "#FFD23F", passive = 1.5, sell = 5 },
			rainbow = { label = "Rainbow", color = "#FF7AD9", passive = 2, sell = 10 },
		},
	},

	passives = {
		order = { "coins", "luck", "catch" }, -- as listed in the window
		-- a flavor without its own `passive` (Config/Flavors) gives this one
		defaultPassive = "coins",
		kinds = {
			-- times the coins of the scoops sold at a serve
			coins = { label = "Coins", text = "more coins when serving", color = "#FFC61E", cap = 0.25 },
			-- the chance that a caught scoop turns into one of the next rarer rarity (ChestService.luckyFlavor)
			luck = { label = "Luck", text = "chance for a rarer scoop when catching", color = "#2FD99A", cap = 0.15 },
			-- times the catch radius round the tower (Config/Launcher.catchRadius), on client and server alike
			catch = { label = "Catch", text = "bigger catch radius", color = "#2EA6F2", cap = 0.2 },
		},
		-- the bonus of one equipped scoop by its rarity (0.02 = +2 %), times its mutation's `passive`. Common and
		-- uncommon only reach the chest with a mutation.
		byRarity = {
			common = 0.01,
			uncommon = 0.015,
			rare = 0.02,
			epic = 0.05,
			legendary = 0.1,
			-- mythic, secret, divine: later
		},
	},

	-- selling one stored scoop: its flavor's value times its rarity's factor times its mutation's `sell`
	sell = {
		byRarity = { common = 1, uncommon = 1.5, rare = 3, epic = 5, legendary = 10 },
	},

	-- opening: the server opens the owner's chest when they come within openRadius studs of its pivot and closes it
	-- beyond closeRadius (checked every checkInterval s); the window's actions only go through within actionRadius.
	-- Only the owner opens it, everyone sees it open. It opens as they come near (before the prompt, which shows from
	-- promptDistance) and shuts a little farther away, so it does not flutter at the edge.
	openRadius = 14,
	closeRadius = 18,
	actionRadius = 24,
	checkInterval = 0.2,
	-- one window action (equip, unequip, sell) at most this often
	actionInterval = 0.15,

	-- the lid (the PlotKit model's `Lid`, turned about its `Hinge` round X; the front edge goes up)
	-- Soft both ways (since 17.11.2026; before Back out with an overshoot in 0.55 s and Quad in shut in 0.4 s): easing
	-- names of Enum.EasingStyle and Enum.EasingDirection
	lid = {
		angle = 100, -- degrees open
		openTime = 0.7,
		closeTime = 0.6,
		style = "Sine",
		direction = "InOut",
		resolveInterval = 1, -- seconds between looks for chests that streamed in
	},
	-- the glow inside while open: a PointLight `lift` studs above the pivot; it fades with the lid (lid times and curve)
	glow = { color = "#FFE7A3", brightness = 2.2, range = 14, lift = 6.5 },
	-- while open a small glint rises every `glintEvery` seconds (Config/Vfx effects.chestGlint); only within reach
	glintEvery = 0.7,
	-- where the sparkle of opening and the glints start, above the pivot
	sparkleLift = 6,
	soundHearing = 70, -- studs
	-- the prompt at the owner's own chest (key: Config/Controls.chest)
	promptDistance = 12,

	-- The window's pictures (17.11.2026, vault: Wobble Scoops/UI Vorschau/Icons/chest_*.png, uploaded through the Studio
	-- MCP, see docs/live-sync.md "Bilder hochladen"). Words in them (rarity, EQUIPPED, ACTIVE BOOSTS, SCOOP CHEST) are
	-- drawn into the picture. A rarity without a card or badge here falls back to the kit's card and a drawn pill.
	art = {
		-- the window: a 9-slice of chest_window (1024 x 725, glaze and drips in the top 130 px), the title plaque over it
		window = {
			panel = "rbxassetid://127437525279417", -- chest_window
			slice = { 90, 135, 934, 650 }, -- min x, min y, max x, max y
			sliceScale = 0.8,
			title = "rbxassetid://84163071747279", -- chest_title, 1024 x 339
			titleSize = { 420, 139 },
			titleY = 22,
			inset = { top = 112, side = 40, bottom = 40 },
		},
		-- the item cards by rarity: the rarity's word in the top band, an empty name bar at the bottom (about 450 x 512)
		cards = {
			common = "rbxassetid://107915915379547",
			uncommon = "rbxassetid://124125861499653",
			rare = "rbxassetid://115895657256505",
			epic = "rbxassetid://123921537323140",
			legendary = "rbxassetid://131019398952462",
			mythic = "rbxassetid://73352174656351",
			secret = "rbxassetid://118326141320847",
		},
		-- cards whose picture lacks the rarity's word in the top band (chest_card_rare): the word is written over it
		cardsWithoutWord = { rare = true },
		cardEmpty = "rbxassetid://100060651178387", -- an empty equip slot (shown dark and faint)
		cardAspect = 458 / 512,
		-- the rarity plaques of the details (about 768 x 275)
		badges = {
			common = "rbxassetid://139373099237847",
			uncommon = "rbxassetid://108399983699242",
			rare = "rbxassetid://122757086026145",
			epic = "rbxassetid://92963349057989",
			legendary = "rbxassetid://86141340756855",
			mythic = "rbxassetid://114027342882827",
			divine = "rbxassetid://73581780231569",
		},
		badgeAspect = 768 / 275,
		equippedLabel = "rbxassetid://116000204338020", -- the waffle plaque over the slots, 768 x 203
		equippedTag = "rbxassetid://83311215888526", -- the green tag on an equipped card, 640 x 226
		boostPanel = "rbxassetid://130299051416232", -- the bonuses' panel with cream glaze, 1024 x 518
		boostTitle = "rbxassetid://118325131598855", -- "ACTIVE BOOSTS" on its caramel bar, 1024 x 266
		-- the passives' icons; coins uses the kit's coin (Config/Ui.icons.coin)
		passiveIcons = {
			luck = "rbxassetid://122651245550491", -- the clover
			catch = "rbxassetid://87091706591755",
		},
	},
}
