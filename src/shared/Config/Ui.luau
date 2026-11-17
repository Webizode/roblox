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
		-- the throw's charge arc (AimHud, "Glänzende Eiscreme-Bogenmeter nach rechts"): the empty arc; its pink fill (only the
		-- fill, the outline is the empty arc's), its fill
		-- as a white glaze and as green (a perfect moment), and the perfect window's green mark (the fill's own shape, from
		-- the cap down to where perfect starts)
		arcFrame = "rbxassetid://132241134077624",
		arcFill = "rbxassetid://139181164053577",
		arcFillWhite = "rbxassetid://94728324284540",
		arcFillGreen = "rbxassetid://98445986533488",
		arcMark = "rbxassetid://87533639520831",
	},

	-- the key badges (Buttons.badge): the key cap from "Glänzende Cartoon-Tastenkappen" recoloured (normal, pressed, wide
	-- for long keys) and the key's colour on it; `badgeStyle` picks one for every badge
	badgeStyle = "chocolate",
	badgeStyles = {
		-- glazed milk chocolate, a cream letter with a dark edge
		chocolate = {
			cap = "rbxassetid://122832040618299",
			pressed = "rbxassetid://98055143902194",
			wide = "rbxassetid://124834881193652",
			text = "#FFF4E4",
			stroke = true,
		},
		-- vanilla pink, a dark letter
		pastel = {
			cap = "rbxassetid://133568110141710",
			pressed = "rbxassetid://108104051603339",
			wide = "rbxassetid://128745802628414",
			text = "#3B2016",
			stroke = false,
		},
	},

	-- The kit's surfaces (Theme.skin): 9-slice images cut out of "Buntes Candy-UI-Asset-Sheet" (vault: Wooble scoops Map
	-- assets), drawn with ScaleType.Slice so corners, rims and glaze drips stay sharp at any size. Each image: id and
	-- size in source pixels; `inset` = left, top, right, bottom in source pixels, the part that is never stretched.
	-- `colors` are images drawn in a UI colour (the key is a token of `colors` below); any other colour gets `neutral`
	-- (light grey shading, dark outline) tinted with it. `scale`, if set, is the slice scale (design px per source px)
	-- whatever the height.
	skins = {
		-- MY PLOT, ARENA and the wide buttons
		pill = {
			inset = { 95, 60, 95, 60 },
			neutral = { id = "rbxassetid://115747297830724", w = 567, h = 163 },
			colors = {
				mint = { id = "rbxassetid://139330568477792", w = 567, h = 163 },
				pink = { id = "rbxassetid://117851583590393", w = 567, h = 163 },
				sky = { id = "rbxassetid://119475889313498", w = 567, h = 163 },
				yellow = { id = "rbxassetid://92154550549251", w = 567, h = 163 },
				red = { id = "rbxassetid://125587456468243", w = 566, h = 156 },
			},
		},
		-- the square icon buttons, the close button, tabs and buttons too narrow for a pill
		square = {
			inset = { 42, 42, 42, 42 },
			neutral = { id = "rbxassetid://91572493145695", w = 159, h = 152 },
			colors = {
				mint = { id = "rbxassetid://99000955043772", w = 159, h = 152 },
				pink = { id = "rbxassetid://100670758514977", w = 159, h = 152 },
				sky = { id = "rbxassetid://99269750304108", w = 159, h = 152 },
				purple = { id = "rbxassetid://128916004938741", w = 159, h = 152 },
				yellow = { id = "rbxassetid://90557718416522", w = 159, h = 152 },
				red = { id = "rbxassetid://96077048306813", w = 159, h = 152 },
			},
		},
		-- the chocolate info pill with the cream glaze on top: coins and the tower display
		info = { inset = { 210, 100, 210, 45 }, neutral = { id = "rbxassetid://112441439164525", w = 786, h = 162 } },
		-- the window: chocolate panel, pink glaze with cream drips along the top
		window = {
			inset = { 210, 150, 210, 55 },
			neutral = { id = "rbxassetid://130221680104782", w = 827, h = 428 },
			scale = 0.55,
		},
		-- the item cards, one per rarity (Config/Flavors.rarityColors order)
		card = {
			inset = { 50, 50, 50, 50 },
			neutral = { id = "rbxassetid://139738383645675", w = 233, h = 236 },
			rarities = {
				common = { id = "rbxassetid://139738383645675", w = 233, h = 236 },
				uncommon = { id = "rbxassetid://85219406357817", w = 233, h = 236 },
				rare = { id = "rbxassetid://110059342698382", w = 233, h = 236 },
				epic = { id = "rbxassetid://75057026689916", w = 233, h = 236 },
				legendary = { id = "rbxassetid://99059262292542", w = 233, h = 236 },
				-- the sheet's lower-left sparkle painted out: it sat on the name
				golden = { id = "rbxassetid://81475550744420", w = 233, h = 236 },
			},
		},
	},
	-- The info pills of coins and tower (Widgets.infoPill), one look for both: `height` design pixels, the icon
	-- (`icon` across) overhanging the left end, then one row of parts `gap` apart, below the cream glaze (`glaze`: the
	-- share of the height on top kept free), `padRight` before the right end. The pill is as long as its row, so it never
	-- shows much empty room; the coins' row is at least `coinsMinRow` long (the number centred in it) and a number longer
	-- than `maxChars` characters gets smaller instead of the pill growing on. Numbers in Theme.fontNumbers at `text`.
	infoPill = {
		height = 44,
		icon = 56,
		gap = 10,
		padRight = 18,
		glaze = 0.24,
		text = 30,
		worthText = 24,
		worthIcon = 24,
		steadyText = 18,
		coinsMinRow = 64,
		maxChars = 9,
	},

	-- the window's pink glaze: where its middle is, in source pixels from the top, and where the drips end
	windowGlaze = { middle = 52, band = 88, drips = 155 },
	-- The waffle pattern of "Glänzendes Eiswaffel-UI-Set" as a seamless tile (dark grooves, light ridges), repeated never
	-- stretched, faint on the window's panel and in the info pills. `tile` in design pixels.
	waffle = { id = "rbxassetid://119973752443891", tile = 37, transparency = 0.78 },
	-- single sprinkles from the same sheet, as decoration: a few on the window's glaze and on MY PLOT and ARENA, never
	-- over an icon or a word. Each placement: colour, x as a share of the width, y in design pixels from the top edge,
	-- rotation in degrees. `size` is a sprinkle's length in design pixels.
	sprinkles = {
		images = {
			pink = { id = "rbxassetid://86836605339940", w = 46, h = 38 },
			yellow = { id = "rbxassetid://91226069730612", w = 48, h = 36 },
			blue = { id = "rbxassetid://107655028167871", w = 40, h = 40 },
		},
		size = 24,
		-- on the pill's upper band, above the word (its letters start about 16 px down); the images lie diagonally, so
		-- these rotations lay them nearly flat
		plot = { { "yellow", 0.6, 9, -32 }, { "pink", 0.76, 9, -10 } },
		arena = { { "blue", 0.7, 9, -30 } },
		-- on the window's pink glaze, either side of the title: colour, x in design pixels from the left edge (negative:
		-- from the right edge), rotation; they sit on the glaze's middle line
		window = { { "yellow", 40, -24 }, { "blue", 70, 30 }, { "yellow", -84, 20 } },
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
		-- inset panels on a window (the Scoop Chest's slots, bonuses and grid): a darker chocolate inside a caramel rim,
		-- the waffle labels on them, and the warm cream of short hint lines
		panel = "#4E2C1E",
		rim = "#E39A4A",
		waffleLabel = "#E3942F",
		hint = "#F7DFA6",
		shadow = "#000000",
	},

	-- The fonts of the whole game (Theme.fontMain, Theme.fontText, Theme.fontNumbers; the server's signs and boards read
	-- them here too). `main` is an Enum.Font name (LuckiestGuy is the family LuckiestGuy.json): the bold cartoon face of
	-- buttons, titles, badges, the kill feed, hit messages, plot signs and the leaderboard. `text` is a family and a
	-- weight: Nunito ExtraBold (since 17.11.2026, before Builder Sans ExtraBold) for descriptions and small infos:
	-- passive texts, card details, hints, the settings, small numbers. `textEnum` is the nearest Enum.Font, only for
	-- measuring text (TextService:GetTextSize takes no Font).
	fonts = {
		main = "LuckiestGuy",
		text = { family = "rbxasset://fonts/families/Nunito.json", weight = "ExtraBold" },
		textEnum = "Nunito",
		-- the number displays (coins, the scoop count, the worth under it, later shop prices): a rounder face, Nunito at
		-- its heaviest weight (Black); a family and a weight, as no Enum.Font has that weight
		numbers = { family = "rbxasset://fonts/families/Nunito.json", weight = "Heavy" },
	},
	-- Luckiest Guy keeps room for descenders it hardly uses, so its capitals sit high in their box: words in the main
	-- font get this share of their box as padding on top (Theme.text, the key badges), which centres them again
	mainFontLift = 0.14,

	-- design sizes (pixels at 1280 x 720)
	reference = { width = 1280, height = 720 },
	stroke = 3, -- the chocolate outline
	textStroke = 2.5,
	corner = 16,
	shadow = 4, -- the dark edge under a button
	margin = 14, -- to the screen's (safe) edge
	gap = 10,
	-- between the left icon buttons (UiLayout.columnGap); on touch screens none, as their tap areas are bigger than
	-- their pictures anyway
	columnGap = 10,
	touchColumnGap = 0,
	thumb = 44, -- the smallest touch target, in screen pixels
	badge = 26, -- a key badge's height (its width follows the key cap)

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
	-- gap: px between the bars of two dash charges, two single bars with a small gap between them (kill test 13.11.2026;
	-- it was -1, the slanted ends tucked into each other and it looked like one bar with a line in it)
	dash = { height = 22, slice = 0.22, gap = 6 },
	-- from the top of the screen to MY PLOT, ARENA and the gear, in the free part of Roblox's top bar: room for the half of
	-- a key badge that stands over a button's top edge (Config/Ui badge / 2 - 4) and 1 px more
	topEdge = 10,
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

	-- The short messages (UiKit/Toast): no box, the main font with a thick dark outline and a small icon, free in the
	-- picture `above` design pixels over the bottom cluster (the tower pill). They pop in from `popFrom`, stand `hold`
	-- seconds (`touchHold` on touch screens, where they are also `touchScale` as big) and fade out in `fade`. The same
	-- text again within `repeatAfter` seconds only pops the one standing. Each kind's colour is a token of `colors`.
	toast = {
		textSize = 36,
		icon = 42,
		stroke = 4,
		above = 16,
		popFrom = 0.8,
		pop = 0.18,
		hold = 2,
		touchHold = 1.5,
		touchScale = 0.8,
		fade = 0.45,
		repeatAfter = 3,
		kinds = { normal = "text", warn = "yellow", bad = "red", good = "mint" },
	},

	-- The way to the own plot (Controllers/PlotGuide, GuideRules): once the cone is `showShare` full, a light stands over
	-- the own serve point (`height` studs, a core `width` wide in a soft halo `glowWidth` wide, fading upwards; a low
	-- `lightEmission` keeps its yellow from washing out against the bright sky) and, while the serve point is outside
	-- the picture, an arrow at the screen's edge (`arrow` design pixels, `arrowMargin` from the edge) points to it.
	-- Coming within `arriveRadius` studs of it with scoops lights up a ring on the ground there for `glowTime` seconds.
	guide = {
		showShare = 0.75,
		color = "#FFC61E",
		height = 70,
		width = 6,
		glowWidth = 16,
		lightEmission = 0.35,
		transparency = 0.35,
		arriveRadius = 20,
		glowTime = 1.8,
		glowSize = 18,
		arrow = 46,
		arrowMargin = 70,
		-- after spawning and after a teleport into the arena the arrow shows this many seconds, to get one's bearings
		arrowFlash = 2,
		-- the pin over the own plot (always there, only for the own player): the arrow's bubble and tip with YOU under
		-- it, `pin` design pixels across, `pinHeight` studs over the serve point, the same size on screen at any
		-- distance. Faint (`pinTransparency`), solid and `pinStrongScale` as big from showShare, fainter and smaller in
		-- combat mode; fading out from `pinFade` studs and gone within `pinHide` (on the plot itself). GuideRules.pinLook
		pin = 46,
		pinHeight = 16,
		pinTransparency = 0.4,
		pinStrongTransparency = 0,
		pinStrongScale = 1.15,
		pinCombatTransparency = 0.7,
		pinCombatScale = 0.75,
		pinFade = 40,
		pinHide = 22,
	},

	-- the pins over other players' plots (PlotPins, since the kill test of 13.11.2026: only the own base was
	-- recognisable): the owner's head shot in a round bubble with a tip in their player colour, their name under it,
	-- `pin` design pixels across, `pinHeight` studs over the plot's serve point, the same size on screen at any
	-- distance. Smaller and fainter than the own YOU pin, fainter and smaller in combat mode, fading out from `pinFade`
	-- studs and gone within `pinHide` (the name stands on the plot sign there); free plots show nothing. A serve there
	-- makes a coin glint at the pin (`glint` seconds). Rules: GuideRules.pinLook, the same as the own pin.
	plotPins = {
		pin = 36,
		-- the head shot: a round mask `headMask` of the bubble across, the picture `headScale` of the mask, `headDrop` of it
		-- lower than the middle, so the whole head fits inside the ring
		headMask = 0.84,
		headScale = 0.92,
		headDrop = 0.04,
		pinHeight = 16,
		pinTransparency = 0.15,
		pinStrongTransparency = 0.15,
		pinStrongScale = 1,
		pinCombatTransparency = 0.65,
		pinCombatScale = 0.75,
		pinFade = 60,
		pinHide = 35,
		nameSize = 15, -- design pixels, the main font
		glint = 0.9,
		maxPins = 11, -- a full server is 12 players
	},

	-- seconds: a button sinks in (press), eases back (release), a window pops up (pop), a number counts to its new value
	-- (count) while its pill pops `bump` times as big and back
	anim = { press = 0.07, release = 0.14, pop = 0.16, hover = 0.1, count = 0.4, bump = 1.08 },

	-- A big window that makes room (Window.new with hudAway, e.g. the Scoop Chest): it pops up from `from` of its size
	-- in `time` (Back, a clear overshoot), the dim fades in over `dimTime`.
	windowPop = { from = 0.35, time = 0.34, dimTime = 0.22 },
	-- The HUD making room for such a window (UiKit/HudAway): every visible top-level piece of these ScreenGuis glides
	-- out over its nearest screen edge in `away` seconds (Back In: a little wind-up) and back in `back` (Back Out), to
	-- `margin` pixels beyond the edge.
	hudAway = { guis = { "Hud", "Navigation" }, away = 0.28, back = 0.32, margin = 24 },

	-- The look of a mutated scoop's card (UiKit/MutationOverlay, Widgets.mutationOverlay): a see-through layer in the
	-- card's own shape over the card picture, under the scoop, the name and the count. One shared loop moves all of them
	-- `fps` times a second, only while one shows on an open screen; at a saved graphics level of `lowQuality` or lower
	-- (1-10, Automatic counts as high) the layers stand still.
	mutationOverlay = {
		fps = 30,
		lowQuality = 3,
		-- the pure-colour layers (the streak, the rainbow) are rounded rectangles `inset` design pixels inside the card
		-- with this corner radius, to stay within the card's round corners
		corner = 18,
		inset = 5,
		kinds = {
			-- gilded: a warm gold from top to bottom (`transparency` 0 = solid), and every `shineEvery` seconds a bright
			-- streak at `shineAngle` degrees sweeps across in `shineTime`
			golden = {
				top = "#FFF1A8",
				bottom = "#F2A81D",
				transparency = 0.2, -- the gold is laid over the card picture in its shape and multiplies with it
				shineEvery = 3,
				shineTime = 0.75,
				shineAngle = 30,
				shineWidth = 0.09, -- half the streak's width, of the card
				shineTransparency = 0.25,
				sparkles = {},
			},
			-- a rainbow that turns once in `cycle` seconds, with little stars twinkling (x, y as a share of the card, size
			-- in design pixels of a full card) every `twinkle` seconds
			rainbow = {
				colors = { "#FF5A5A", "#FFA63D", "#FFE94D", "#5EE07A", "#4DB8FF", "#8A6BFF", "#FF6BD6" },
				transparency = 0.62,
				cycle = 6,
				sparkles = { { 0.2, 0.3, 22 }, { 0.82, 0.52, 18 }, { 0.3, 0.68, 16 } },
				twinkle = 1.6,
			},
		},
	},
}
