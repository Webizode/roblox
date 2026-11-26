-- The upgrade shop's window (Config/Upgrades, the rules in Upgrades; the server decides, UpgradeService):
--   Opening    only at the Upgrade shop in the hub: its prompt "Upgrades" (E, a tap, the gamepad's prompt key). The
--              HUD's UPGRADES button teleports there (Navigation, TeleportRules). Walking farther than
--              Config/Upgrades.closeDistance from the shop closes the window. HudAway like the Scoop Chest.
--   Window     the reference picture (vault: UI Vorschau/Upgrades/Upgrade-Shop Referenz.png) as nearly 1:1 as it goes,
--              from pictures cut out of it (Config/Upgrades.art, 26.11.2026): the window with its glaze, drips,
--              scoops, waffles and arrow, the plaque, coin pill and subtitle pill painted in without their words; the
--              close button. Live on top: the title, the own coins, the subtitle and one card per shown upgrade (the
--              card picture as a 9-slice, the upgrade's coloured tile, name, level pips and "LV 7/25" in the
--              upgrade's colour, a line, the effect "27 -> 28 scoops" in its colour, the pink buy button with the price).
--              The cards scroll in the kit's Scroller. All positions below are the reference's pixels (REF), scaled.
--   Buttons    too few coins: the grey button; at the top: a golden "MAX" instead of the button; at the level cap
--              (Config/Upgrades.levelCap, off for now): the grey button with "REBIRTH".
--   Buying     the button sends the level the card shows (UpgradeBuy); while that answer is on its way the card takes
--              no second click. Bought: the card bumps (Anim.bump), the new pips fill in one after the other and the
--              sound upgradeBuy plays. Levels come back as the Upgrade_<id> attributes, coins as leaderstats.Coins.
--   Layouts    "tall" (PC, tablet, console) and "wide" (phones in landscape): the same window, the phone's cards
--              flatter so more of them show at once. In Studio the attribute UpgradeLayout on Workspace ("wide" or
--              "tall") picks one, to look at the phone's on a PC.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))
local UpgradesConfig = require(Config:WaitForChild("Upgrades"))

local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local Sfx = require(client:WaitForChild("Sfx"))

local Theme, Window, Anim, Toast, Screen, Scroller =
	UiKit.Theme, UiKit.Window, UiKit.Anim, UiKit.Toast, UiKit.Screen, UiKit.Scroller

local UpgradeController = {}

local PROMPT_NAME = "UpgradeShopPrompt" -- UpgradeService puts it on the shop's Teleport_Upgrade parts
local CLOSE_CHECK = 0.2 -- seconds between two looks whether the player is still at the shop
local ARROW = "  \u{2192}  " -- between the value now and after the purchase
local PENDING_TIMEOUT = 3 -- seconds a card waits for the server's answer before it takes clicks again
local ART = UpgradesConfig.art

-- The reference picture's pixels (1312 x 1199) for everything placed on the window; WIDTH design pixels wide.
local REF = {
	width = 1312,
	height = 1199,
	title = { x = 675, y = 190, w = 560, h = 104 }, -- the word on the plaque (middle and box)
	close = { x = 1229, y = 228, size = 112 },
	coins = { x = 182, y = 272, w = 120, h = 62 }, -- the number in the coin pill (top left and box)
	subtitle = { x = 476, y = 284, w = 510, h = 38 },
	list = { x = 61, y = 362, w = 1195, h = 704 }, -- the board the cards scroll on
	-- inside a card (186 high in the reference; everything scales with the card's height, the button sits from the right)
	card = {
		height = 186,
		gap = -6, -- the reference's cards overlap their rims a little
		tile = { x = 36, y = 23, w = 161, h = 148 },
		text = 229, -- name, pips, line and effect start here
		name = { y = 22, h = 48 },
		pips = { y = 76, h = 20, w = 420, pitch = 21.5 },
		level = { x = 681, w = 130, h = 30 },
		line = { y = 104, h = 36 },
		effect = { y = 140, h = 38 },
		button = { right = 30, w = 284, h = 116 },
		price = { x = 112, w = 140 }, -- in the button: after the coin
	},
}
local WIDTH = 900
local S = WIDTH / REF.width
local HEIGHT = math.round(REF.height * S)
-- the card picture (1024 x 160) as a 9-slice: its corners in image pixels
local CARD_IMAGE = { w = 1024, h = 160, slice = Rect.new(44, 44, 980, 116) }

-- the cards' height in design pixels per layout: the phone's flatter, so more show on its short screen
local LAYOUTS: { [string]: { cardHeight: number } } = {
	tall = { cardHeight = 122 },
	wide = { cardHeight = 100 },
}

type Card = {
	id: string,
	frame: ImageLabel,
	level: TextLabel,
	pips: { Frame },
	filled: number, -- pips shown filled, so a purchase can fill the new ones one by one
	effect: TextLabel,
	button: ImageButton,
	price: TextLabel,
	max: TextLabel,
}

local player = Players.LocalPlayer
local layoutName = "tall"
local window: any = nil
local coinLabel: TextLabel? = nil
local cards: { [string]: Card } = {}
local pending: { [string]: number } = {} -- id -> when the purchase was sent
local shopPart: BasePart? = nil -- the shop the window was opened at

local function levelOf(id: string): number
	return Upgrades.clampLevel(id, player:GetAttribute("Upgrade_" .. id), UpgradesConfig)
end

-- the player's rebirths for Config/Upgrades.levelCap (the attribute Rebirths once the rebirth exists; 0 until then)
local function rebirths(): number
	local value = player:GetAttribute("Rebirths")
	return if type(value) == "number" then value else 0
end

local function coins(): number
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Coins")
	return if value and value:IsA("IntValue") then value.Value else 0
end

-- 12500 -> "12,500"
local function withCommas(value: number): string
	local text = tostring(math.floor(value))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^,", ""))
end

-- A word on the window or a card: `font`, `color`, the outline in `stroke` (chocolate, or white for the dark words on
-- the cream cards, as in the reference), scaled into its box but never above `max` pixels.
local function word(props: { [string]: any }, font: Font, color: Color3, stroke: Color3, thickness: number, max: number)
	props.FontFace = font
	props.TextColor3 = color
	props.TextScaled = true
	local label = Theme.text(props)
	local outline = label:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Color = stroke
		outline.Thickness = thickness
	end
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.Parent = label
	return label
end

-- ============================================================================================== the cards ======

local function paintPips(card: Card, level: number, animate: boolean)
	local color = Theme.color(UpgradesConfig.tracks[card.id].color)
	for index, pip in card.pips do
		local on = index <= level
		pip.BackgroundColor3 = if on then color else Theme.color("creamDark")
		pip.BackgroundTransparency = if on then 0 else 0.35
		if on and animate and index > card.filled then
			-- the new ones fill in one after the other
			local scale = Anim.scaleOf(pip)
			scale.Scale = 0.2
			task.delay((index - card.filled - 1) * 0.06, function()
				TweenService
					:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
					:Play()
			end)
		end
	end
	card.filled = level
end

local function paint(card: Card, animate: boolean?)
	local level = levelOf(card.id)
	local track = UpgradesConfig.tracks[card.id]
	card.level.Text = `LV {level}/{track.maxLevel}`
	paintPips(card, level, animate == true)
	card.effect.Text = Upgrades.change(card.id, level, UpgradesConfig, ARROW)
	local cost = Upgrades.cost(card.id, level, UpgradesConfig)
	local capped = cost ~= nil and level >= Upgrades.top(card.id, rebirths(), UpgradesConfig)
	card.max.Visible = cost == nil
	card.button.Visible = cost ~= nil
	if not cost then
		return
	end
	if capped then
		-- the highest level for now (Config/Upgrades.levelCap): more after the next rebirth
		card.button.Image = ART.buyOff
		card.price.Text = "REBIRTH"
	else
		card.button.Image = if coins() < cost then ART.buyOff else ART.buy
		card.price.Text = withCommas(cost)
	end
end

local function paintAll()
	if coinLabel then
		coinLabel.Text = withCommas(coins())
	end
	for _, card in cards do
		paint(card)
	end
end

local function buy(id: string)
	local level = levelOf(id)
	local cost = Upgrades.cost(id, level, UpgradesConfig)
	if not cost then
		return -- MAX
	end
	if level >= Upgrades.top(id, rebirths(), UpgradesConfig) then
		Toast.show("Rebirth to go higher!", "warn")
		return
	end
	if pending[id] and os.clock() - pending[id] < PENDING_TIMEOUT then
		return -- the answer to the last click is still on its way (a double click)
	end
	if coins() < cost then
		Toast.show("Not enough coins!", "warn", "coin")
		return
	end
	pending[id] = os.clock()
	Remotes.UpgradeBuy:FireServer(id, level)
end

local function makeCard(id: string, order: number, height: number, parent: GuiObject): Card
	local track = UpgradesConfig.tracks[id]
	local C = REF.card
	local k = height / C.height -- design pixels per reference pixel inside the card
	local color = Theme.color(track.color)
	local dark = Theme.color("textDark")
	local white = Color3.new(1, 1, 1)

	local frame = Instance.new("ImageLabel")
	frame.Name = "Card_" .. id
	frame.BackgroundTransparency = 1
	frame.Image = ART.card
	frame.ScaleType = Enum.ScaleType.Slice
	frame.SliceCenter = CARD_IMAGE.slice
	frame.SliceScale = height / CARD_IMAGE.h
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.LayoutOrder = order
	frame.ZIndex = 4
	frame.Parent = parent

	local tile = Instance.new("ImageLabel")
	tile.Name = "Tile"
	tile.BackgroundTransparency = 1
	tile.Image = ART.tiles[id] or ART.tiles.slots
	tile.ScaleType = Enum.ScaleType.Fit
	tile.Position = UDim2.fromOffset(C.tile.x * k, C.tile.y * k)
	tile.Size = UDim2.fromOffset(C.tile.w * k, C.tile.h * k)
	tile.ZIndex = 5
	tile.Parent = frame
	if not ART.tiles[id] or id == "slots" then
		-- a stand-in tile without a drawing: the upgrade's first letter on it
		word({
			Name = "Letter",
			Text = string.sub(track.label, 1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.6, 0.6),
			ZIndex = 6,
			Parent = tile,
		}, Theme.fontMain, white, dark, 3, 200)
	end

	local left = C.text * k
	local right = (C.button.right + C.button.w + 24) * k -- the words stop before the button
	word({
		Name = "Name",
		Text = string.upper(track.label),
		Position = UDim2.fromOffset(left, C.name.y * k),
		Size = UDim2.new(1, -left - right, 0, C.name.h * k),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = frame,
	}, Theme.fontMain, dark, white, 2, 200)

	-- one pip per level within the reference's row (25 levels fit, 16 pips stand at the reference's spacing)
	local pitch = math.min(C.pips.pitch, C.pips.w / track.maxLevel) * k
	local pipSize = math.max(4, math.floor(pitch * 0.82))
	local pipRow = Theme.frame({
		Name = "Pips",
		Position = UDim2.fromOffset(left, (C.pips.y + C.pips.h / 2) * k - pipSize / 2),
		Size = UDim2.fromOffset(pitch * track.maxLevel, pipSize),
		ZIndex = 5,
		Parent = frame,
	})
	local pips = {}
	for index = 1, track.maxLevel do
		local pip = Theme.frame({
			Name = "Pip" .. index,
			BackgroundTransparency = 0,
			Position = UDim2.fromOffset((index - 1) * pitch, 0),
			Size = UDim2.fromOffset(pipSize, pipSize),
			ZIndex = 5,
			Parent = pipRow,
		})
		Theme.corner(pip, UDim.new(0.5, 0))
		local rim = Instance.new("UIStroke")
		rim.Color = Theme.darker(color, 0.25)
		rim.Thickness = 1.5
		rim.Transparency = 0.2
		rim.Parent = pip
		pips[index] = pip
	end
	local level = word({
		Name = "Level",
		Position = UDim2.fromOffset(C.level.x * k, (C.pips.y + C.pips.h / 2 - C.level.h / 2) * k),
		Size = UDim2.fromOffset(C.level.w * k, C.level.h * k),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = frame,
	}, Theme.fontNumbers, dark, white, 0, 200)
	word({
		Name = "Line",
		Text = track.text,
		Position = UDim2.fromOffset(left, C.line.y * k),
		Size = UDim2.new(1, -left - right, 0, C.line.h * k),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = frame,
	}, Theme.fontText, dark, white, 0, 200)
	local effect = word({
		Name = "Effect",
		Position = UDim2.fromOffset(left, C.effect.y * k),
		Size = UDim2.new(1, -left - right, 0, C.effect.h * k),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = frame,
	}, Theme.fontNumbers, color, white, 2, 200)

	local button = Instance.new("ImageButton")
	button.Name = "Buy_" .. id
	button.BackgroundTransparency = 1
	button.Image = ART.buy
	button.ScaleType = Enum.ScaleType.Fit
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -C.button.right * k, 0.5, 0)
	button.Size = UDim2.fromOffset(C.button.w * k, C.button.h * k)
	button.ZIndex = 6
	button.Parent = frame
	Anim.button(button)
	local price = word({
		Name = "Price",
		Position = UDim2.fromScale(C.price.x / C.button.w, 0.22),
		Size = UDim2.fromScale(C.price.w / C.button.w, 0.52),
		ZIndex = 7,
		Parent = button,
	}, Theme.fontNumbers, white, Theme.color("outline"), 3, 200)
	button.Activated:Connect(function()
		buy(id)
	end)
	local max = word({
		Name = "Max",
		Text = "MAX",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -C.button.right * k, 0.5, 0),
		Size = UDim2.fromOffset(C.button.w * k, C.button.h * k * 0.62),
		Visible = false,
		ZIndex = 6,
		Parent = frame,
	}, Theme.fontMain, Theme.color("yellow"), Theme.color("outline"), 3, 200)

	local card: Card = {
		id = id,
		frame = frame,
		level = level,
		pips = pips,
		filled = levelOf(id),
		effect = effect,
		button = button,
		price = price,
		max = max,
	}
	paint(card)
	return card
end

-- ============================================================================================= the window ======

-- design pixels on the window for reference pixels
local function at(x: number, y: number): UDim2
	return UDim2.fromOffset(math.round(x * S), math.round(y * S))
end
local function size(w: number, h: number): UDim2
	return UDim2.fromOffset(math.round(w * S), math.round(h * S))
end

local function buildWindow()
	local L = LAYOUTS[layoutName]
	local made = Window.new({
		name = "UpgradeWindow",
		title = "UPGRADES",
		color = Theme.color("pink"),
		width = WIDTH,
		height = HEIGHT + 98, -- Window.new takes the content's height + 98; the insets below are 0
		hudAway = true,
		art = {
			panel = ART.window,
			-- the picture as it is: the slice's middle is a thin cross, the window is drawn at the picture's own shape
			slice = Rect.new(511, 467, 513, 469),
			sliceScale = WIDTH / 1024,
			titleY = math.round(REF.title.y * S),
			titleText = { width = math.round(REF.title.w * S), height = math.round(REF.title.h * S) },
			close = {
				image = ART.close,
				x = math.round(REF.close.x * S),
				y = math.round(REF.close.y * S),
				size = math.round(REF.close.size * S),
			},
			inset = { top = 0, side = 0, bottom = 0 },
		},
	})
	window = made
	local content = made.content

	coinLabel = word({
		Name = "Coins",
		Position = at(REF.coins.x, REF.coins.y),
		Size = size(REF.coins.w, REF.coins.h),
		ZIndex = 6,
		Parent = content,
	}, Theme.fontNumbers, Color3.new(1, 1, 1), Theme.color("outline"), 3, 200)
	word({
		Name = "Subtitle",
		Text = "Upgrades help your shop and your tower.",
		Position = at(REF.subtitle.x, REF.subtitle.y),
		Size = size(REF.subtitle.w, REF.subtitle.h),
		ZIndex = 6,
		Parent = content,
	}, Theme.fontText, Theme.color("textDark"), Color3.new(1, 1, 1), 0, 200)

	local scroller = Scroller.new({
		name = "Cards",
		position = at(REF.list.x, REF.list.y),
		size = size(REF.list.w, REF.list.h),
		zIndex = 4,
		parent = content,
	})
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, math.round(REF.card.gap * L.cardHeight / REF.card.height))
	list.Parent = scroller.list

	table.clear(cards)
	local first: GuiObject? = nil
	for order, id in Upgrades.visible(UpgradesConfig) do
		local card = makeCard(id, order, L.cardHeight, scroller.list)
		cards[id] = card
		first = first or card.button
	end
	made.firstSelection = first
	made.onClosed(function()
		if Screen.input() == "gamepad" then
			GuiService.SelectedObject = nil
		end
	end)
	paintAll()
end

local function onResult(id: any, ok: any, result: any, _cost: any)
	if type(id) ~= "string" then
		return
	end
	pending[id] = nil
	local card = cards[id]
	if ok == true then
		Sfx.play("upgradeBuy")
		local track = UpgradesConfig.tracks[id]
		if card then
			-- the level attribute may arrive just after this answer: its change fills the new pips (Start)
			paint(card, true)
			Anim.bump(card.frame)
		end
		if track then
			Toast.show(`{string.upper(track.label)} LEVEL {result}!`, "good")
		end
	elseif result == "coins" then
		Toast.show("Not enough coins!", "warn", "coin")
	elseif result == "max" then
		Toast.show("Already at the top level!", "warn")
	elseif result == "loading" then
		Toast.show("Your save is still loading...", "warn")
	elseif result == "cap" then
		Toast.show("Rebirth to go higher!", "warn")
	elseif result == "far" then
		Toast.show("Get closer to the shop!", "warn")
	end
	-- "stale" (a double click, or the window was a step behind): nothing to say, the cards show the real level
	paintAll()
end

-- Opens the window at `shop` (the shop's part whose prompt was triggered); it stays open while the player is near it.
function UpgradeController.open(shop: BasePart)
	shopPart = shop
	if window and not window.isOpen() then
		paintAll()
		window.open()
	end
end

-- Farther than Config/Upgrades.closeDistance from the shop (walked or teleported away, or no character): the window
-- closes. On the ground plane, like the server's check.
local function checkDistance()
	if not window or not window.isOpen() then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local shop = shopPart
	if not root or not shop or not shop.Parent then
		window.close()
		return
	end
	local offset = root.Position - shop.Position
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > UpgradesConfig.closeDistance then
		window.close()
	end
end

function UpgradeController.isOpen(): boolean
	return window ~= nil and window.isOpen()
end

function UpgradeController.Start()
	local function layoutFor(plan: any): string
		local forced = if RunService:IsStudio() then workspace:GetAttribute("UpgradeLayout") else nil
		if forced == "wide" or forced == "tall" then
			return forced
		end
		return if plan and plan.device == "phone" then "wide" else "tall"
	end
	layoutName = layoutFor(Screen.plan())
	buildWindow()
	local function relayout()
		local wanted = layoutFor(Screen.plan())
		if wanted == layoutName or not window then
			return
		end
		layoutName = wanted
		local wasOpen = window.isOpen()
		window.close()
		window.gui:Destroy()
		buildWindow()
		if wasOpen then
			window.open()
		end
	end
	Screen.onChanged(relayout)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("UpgradeLayout"):Connect(relayout)
	end

	Remotes.UpgradeResult.OnClientEvent:Connect(onResult)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local shop = prompt:FindFirstAncestorWhichIsA("BasePart")
		if prompt.Name == PROMPT_NAME and shop then
			UpgradeController.open(shop)
		end
	end)
	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceCheck += dt
		if sinceCheck >= CLOSE_CHECK then
			sinceCheck = 0
			checkDistance()
		end
	end)

	-- levels and coins change: the cards follow (only painted, nothing is rebuilt)
	for id in UpgradesConfig.tracks do
		player:GetAttributeChangedSignal("Upgrade_" .. id):Connect(function()
			local card = cards[id]
			if card then
				paint(card, true)
			end
		end)
	end
	task.spawn(function()
		local stats = player:WaitForChild("leaderstats")
		local value = stats:WaitForChild("Coins") :: IntValue
		value.Changed:Connect(function()
			if window and window.isOpen() then
				paintAll()
			end
		end)
	end)
end

return UpgradeController
