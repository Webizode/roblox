-- The HUD. Coins and the settings button on the left edge; at the bottom the tower card (scoops, worth, steady
-- bonus) with at most one hint above it; a balance meter on the right edge while carrying; toasts for
-- SERVE!/SAVED!/TOPPLED!; and a marker on the player's own cart. Everything stays out of the middle of the
-- screen, where the character and the tower are. Catching and serving happen automatically, so there are no
-- action buttons, and the control scheme is never named: the only hint about it says what to do.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Config:WaitForChild("Tower"))

local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))

local Hud = {}

local CONTROLS_HINT_SECONDS = 8 -- how long the balancing hint stays once a tower starts
local METER_HEIGHT = 170

-- Tutorial lines. "catch" and "cart" show until the first serve; the control lines show at the start of the
-- first tower and again after the scheme changes (for example when the balance pad is switched on).
local HINTS = {
	catch = "Stand in a landing circle to catch scoops",
	cart = "Carry your tower to your cart",
	keys = "Push it back against the lean",
	pad = "Drag the pad against the lean",
	gyro = "Tilt your device against the lean",
	walk = "Walk the way it leans to keep it up",
}

local COLORS = {
	ink = Ui.color("ink"),
	vanilla = Ui.color("vanilla"),
	mint = Ui.color("mint"),
	lemon = Ui.color("lemon"),
	awning = Ui.color("awning"),
}

local player = Players.LocalPlayer
local registry
local gui: ScreenGui
local coinsText: TextLabel
local towerCard: Frame
local countText: TextLabel
local worthText: TextLabel
local steadyDot: Frame
local steadyText: TextLabel
local hintCard: Frame
local hintText: TextLabel
local keycaps: Frame
local meter: Frame
local meterStroke: UIStroke
local meterFill: Frame
local toastLabel: TextLabel
local toastStroke: UIStroke
local cartMarker: BillboardGui
local toastTweens: { Tween } = {}

local towerCount = 0
local controls = "walk"
local controlsHintPending = true
local controlsHintUntil = 0
local hasServed = false
local atCart = false
local shownHint: string? = nil

local function withCommas(value: number): string
	local digits = tostring(math.max(0, math.floor(value)))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", ""))
end

local function holder(name: string, props: { [string]: any }): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	for key, value in props do
		(frame :: any)[key] = value
	end
	return frame
end

local function dot(order: number): Frame
	return Ui.circle(6, "vanilla", { Name = "Dot", LayoutOrder = order, BackgroundTransparency = 0.5 })
end

local function coinIcon(): Frame
	local coin = Ui.circle(28, "lemon", { Name = "CoinIcon", LayoutOrder = 1 })
	Ui.stroke(coin, "waffle", 2)
	local inner = Ui.circle(14, "lemon", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	Ui.stroke(inner, "waffle", 2, 0.35)
	inner.Parent = coin
	return coin
end

-- two scoops on a waffle tip
local function scoopIcon(): Frame
	local icon = holder("ScoopIcon", { AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.fromOffset(20, 30) })
	local tip = Instance.new("Frame")
	tip.AnchorPoint = Vector2.new(0.5, 1)
	tip.Position = UDim2.new(0.5, 0, 1, -3)
	tip.Size = UDim2.fromOffset(11, 11)
	tip.Rotation = 45
	tip.BackgroundColor3 = Ui.color("waffle")
	tip.BorderSizePixel = 0
	tip.Parent = icon
	local scoops = { { "mint", 9, 2 }, { "strawberry", 0, 3 } }
	for _, scoop in scoops do
		Ui.circle(16, scoop[1], {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, scoop[2]),
			ZIndex = scoop[3],
		}).Parent =
			icon
	end
	return icon
end

-- three slider bars, the usual settings symbol
local function settingsIcon(parent: GuiObject)
	for index, knobX in { 0.3, 0.7, 0.45 } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.new(0.5, 0, 0.5, (index - 2) * 7)
		bar.Size = UDim2.fromOffset(20, 3)
		bar.BackgroundColor3 = Ui.color("vanilla")
		bar.BorderSizePixel = 0
		Ui.corner(bar, UDim.new(0.5, 0))
		bar.Parent = parent
		Ui.circle(8, "lemon", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(knobX, 0.5),
		}).Parent =
			bar
	end
end

local function keycap(letter: string, x: number, y: number): TextLabel
	local cap = Ui.text({
		Name = letter,
		Text = letter,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.fromOffset(x, y),
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.color("vanilla"),
		TextColor3 = Ui.color("ink"),
		TextSize = 16,
	})
	Ui.corner(cap, UDim.new(0, 6))
	return cap
end

-- I J K L as an inverted T, laid out like the keys themselves
local function keycapCluster(): Frame
	local cluster = holder("Keys", { AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.fromOffset(78, 51) })
	keycap("I", 27, 0).Parent = cluster
	keycap("J", 0, 27).Parent = cluster
	keycap("K", 27, 27).Parent = cluster
	keycap("L", 54, 27).Parent = cluster
	return cluster
end

-- Left edge, a little above the middle: clear of the chat (top left), the player list (top right) and the
-- thumbstick (bottom left).
local function buildSide()
	local side = holder("Side", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.42, 0),
	})
	local layout = Ui.list(side, Enum.FillDirection.Vertical, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	Ui.autoScale(side)

	local coins = Ui.card({
		Name = "Coins",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
	}, UDim.new(0.5, 0))
	Ui.padding(coins, 9, 0)
	Ui.list(coins, Enum.FillDirection.Horizontal, 8)
	coinIcon().Parent = coins
	coinsText = Ui.text({ Name = "Amount", LayoutOrder = 2, Text = "0", TextSize = 24 })
	coinsText.Parent = coins
	coins.Parent = side

	local settings = Ui.button({ Name = "Settings", LayoutOrder = 2, Size = UDim2.fromOffset(44, 44) })
	settingsIcon(settings)
	settings.Activated:Connect(function()
		registry.Settings.toggle()
	end)
	settings.Parent = side
	side.Parent = gui
end

-- Bottom centre, between the thumbstick and the jump button: the hint on top, the tower card below it.
local function buildBottom()
	local bottom = holder("Bottom", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
	})
	local layout = Ui.list(bottom, Enum.FillDirection.Vertical, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	Ui.autoScale(bottom)

	hintCard = Ui.card({
		Name = "Hint",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
	})
	Ui.padding(hintCard, 14, 8)
	Ui.list(hintCard, Enum.FillDirection.Horizontal, 10)
	keycaps = keycapCluster()
	keycaps.LayoutOrder = 1
	keycaps.Parent = hintCard
	hintText = Ui.text({ Name = "Text", LayoutOrder = 2, TextSize = 19 })
	hintText.Parent = hintCard
	hintCard.Parent = bottom

	towerCard = Ui.card({
		Name = "Tower",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
	}, UDim.new(0.5, 0))
	Ui.padding(towerCard, 14, 0)
	Ui.list(towerCard, Enum.FillDirection.Horizontal, 9)
	local icon = scoopIcon()
	icon.LayoutOrder = 1
	icon.Parent = towerCard
	countText = Ui.text({ Name = "Count", LayoutOrder = 2 })
	countText.Parent = towerCard
	dot(3).Parent = towerCard
	worthText = Ui.text({ Name = "Worth", LayoutOrder = 4, TextColor3 = COLORS.lemon })
	worthText.Parent = towerCard
	steadyDot = dot(5)
	steadyDot.Parent = towerCard
	steadyText = Ui.text({ Name = "Steady", LayoutOrder = 6, TextColor3 = COLORS.mint })
	steadyText.Parent = towerCard
	towerCard.Parent = bottom
	bottom.Parent = gui
end

-- Right edge: how much balance is left. Full and green is steady; below the red line the tower groans.
-- It sits where the balance pad would be (the two never show together): bottom right on PC, below the player
-- list; above the jump button on touch screens.
local function buildMeter()
	meter, meterStroke = Ui.card({
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 1),
		Position = if UserInputService.TouchEnabled then UDim2.new(1, -24, 0.62, 0) else UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(30, METER_HEIGHT),
		Visible = false,
	}, UDim.new(0.5, 0))
	Ui.autoScale(meter)

	local track = holder("Track", {
		AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
	})
	track.Parent = meter
	meterFill = Instance.new("Frame")
	meterFill.Name = "Fill"
	meterFill.AnchorPoint = Vector2.new(0, 1)
	meterFill.Position = UDim2.fromScale(0, 1)
	meterFill.Size = UDim2.fromScale(1, 1)
	meterFill.BackgroundColor3 = COLORS.mint
	meterFill.BorderSizePixel = 0
	Ui.corner(meterFill, UDim.new(0.5, 0))
	meterFill.Parent = track

	local groanLine = Instance.new("Frame")
	groanLine.Name = "GroanLine"
	groanLine.AnchorPoint = Vector2.new(0.5, 0.5)
	groanLine.Position = UDim2.fromScale(0.5, Tuning.groanFraction)
	groanLine.Size = UDim2.new(1, 8, 0, 2)
	groanLine.BackgroundColor3 = COLORS.awning
	groanLine.BorderSizePixel = 0
	groanLine.ZIndex = 2
	groanLine.Parent = track

	Ui.text({
		Name = "Label",
		Text = "Balance",
		TextSize = 14,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
	}).Parent =
		meter
	meter.Parent = gui
end

local function buildToast()
	toastLabel = Ui.text({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.14),
		TextSize = 46,
		TextTransparency = 1,
	})
	toastStroke = Instance.new("UIStroke")
	toastStroke.Color = COLORS.ink
	toastStroke.Thickness = 3
	toastStroke.Transparency = 1
	toastStroke.Parent = toastLabel
	Ui.autoScale(toastLabel)
	toastLabel.Parent = gui
end

local function buildCartMarker()
	-- BillboardGuis do not render inside a ScreenGui, so this one lives directly in PlayerGui
	cartMarker = Instance.new("BillboardGui")
	cartMarker.Name = "CartMarker"
	cartMarker.AlwaysOnTop = true
	cartMarker.ResetOnSpawn = false
	cartMarker.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	cartMarker.Size = UDim2.fromOffset(150, 46)
	cartMarker.StudsOffset = Vector3.new(0, 4.5, 0)
	cartMarker.Enabled = false
	cartMarker.Parent = gui.Parent

	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.new(1, 0, 0, 34)
	tag.BackgroundColor3 = COLORS.lemon
	tag.BorderSizePixel = 0
	tag.Font = Ui.FONT
	tag.TextSize = 20
	tag.TextColor3 = COLORS.ink
	tag.Text = "YOUR CART"
	tag.ZIndex = 2
	Ui.corner(tag)
	Ui.stroke(tag, "ink", 2)
	tag.Parent = cartMarker
	-- a lemon arrow tip under the tag, pointing at the cart
	local tip = Instance.new("Frame")
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromOffset(75, 34)
	tip.Size = UDim2.fromOffset(14, 14)
	tip.Rotation = 45
	tip.BackgroundColor3 = COLORS.lemon
	tip.BorderSizePixel = 0
	tip.ZIndex = 1
	Ui.stroke(tip, "ink", 2)
	tip.Parent = cartMarker
end

local function setHint(key: string?)
	if key == shownHint then
		return
	end
	shownHint = key
	hintCard.Visible = key ~= nil
	if key then
		keycaps.Visible = key == "keys"
		hintText.Text = HINTS[key]
	end
end

local function refreshHint()
	if towerCount == 0 then
		setHint(if hasServed then nil else "catch")
	elseif os.clock() < controlsHintUntil then
		setHint(controls)
	elseif not hasServed and not atCart then
		setHint("cart")
	else
		setHint(nil)
	end
end

function Hud.Init(reg)
	registry = reg
	gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	buildSide()
	buildBottom()
	buildMeter()
	buildToast()
	buildCartMarker()
end

function Hud.Start()
	Remotes.Served.OnClientEvent:Connect(function(who: Player)
		if who == player then
			hasServed = true
			refreshHint()
		end
	end)

	local leaderstats = player:WaitForChild("leaderstats")
	local coins = leaderstats:WaitForChild("Coins") :: IntValue
	local function update()
		coinsText.Text = withCommas(coins.Value)
	end
	coins.Changed:Connect(update)
	update()
end

function Hud.setTower(count: number, value: number, steady: number)
	if count > 0 and towerCount == 0 and controlsHintPending then
		controlsHintPending = false
		controlsHintUntil = os.clock() + CONTROLS_HINT_SECONDS
	end
	towerCount = count
	towerCard.Visible = count > 0
	if count > 0 then
		countText.Text = if count == 1 then "1 scoop" else string.format("%d scoops", count)
		worthText.Text = string.format("worth %d", math.floor(value))
		local percent = math.floor(steady * 100 + 0.5)
		steadyDot.Visible = percent > 0
		steadyText.Visible = percent > 0
		steadyText.Text = string.format("steady +%d%%", percent)
	end
	refreshHint()
end

-- Called when the control scheme changes. Only decides when the balancing hint shows again.
function Hud.setControls(scheme: string)
	if scheme == controls then
		return
	end
	controls = scheme
	if towerCount > 0 then
		controlsHintUntil = os.clock() + CONTROLS_HINT_SECONDS
	else
		controlsHintPending = true
	end
end

-- tilt is the share of the tip angle.
function Hud.setBalance(tilt: number, groaning: boolean, visible: boolean)
	meter.Visible = visible
	if not visible then
		return
	end
	meterFill.Size = UDim2.fromScale(1, math.clamp(1 - tilt, 0, 1))
	local danger = groaning or tilt >= Tuning.groanFraction
	meterFill.BackgroundColor3 = if danger then COLORS.awning elseif tilt >= 0.5 then COLORS.lemon else COLORS.mint
	meterFill.BackgroundTransparency = if groaning then 0.35 + 0.35 * math.sin(os.clock() * 18) else 0
	meterStroke.Color = if danger then COLORS.awning else COLORS.vanilla
	meterStroke.Transparency = if danger then 0 else 0.6
end

function Hud.toast(text: string, colorHex: string?)
	for _, tween in toastTweens do
		tween:Cancel()
	end
	toastLabel.Text = text
	toastLabel.TextColor3 = if colorHex then Color3.fromHex(colorHex) else COLORS.vanilla
	toastLabel.TextTransparency = 0
	toastStroke.Transparency = 0
	local fade = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.9)
	toastTweens = {
		TweenService:Create(toastLabel, fade, { TextTransparency = 1 }),
		TweenService:Create(toastStroke, fade, { Transparency = 1 }),
	}
	for _, tween in toastTweens do
		tween:Play()
	end
end

-- atCart: the player stands at the serve point, so the "carry it to your cart" hint is not needed.
function Hud.setCartTarget(part: BasePart?, isAtCart: boolean)
	cartMarker.Adornee = part
	cartMarker.Enabled = part ~= nil
	atCart = isAtCart
end

return Hud
