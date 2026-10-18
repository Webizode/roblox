-- The HUD. Coins and the ice-ball ammo (with the reload countdown) on the left edge; at the bottom the tower card (scoops, worth, steady bonus) with at most one
-- hint above it; a balance meter with a spirit level on the right edge while carrying, which pulses when the tower
-- leans dangerously and shows whether the rescue (F / Steady) is working or cooling down; toasts for
-- SERVE!/SAVED!/TOPPLED!; and a marker on the player's own cart. Everything stays out of the middle of the
-- screen, where the character and the tower are. Catching and serving happen automatically.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Config:WaitForChild("Tower"))
local CombatConfig = require(Config:WaitForChild("Combat"))

local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))

local Hud = {}

local METER_HEIGHT = 170
local LEVEL_SIZE = 46
local LEVEL_DOT = 14

-- "catch" and "cart" show until the first serve; "steady" whenever the tower leans dangerously and a rescue is
-- ready, so the player learns when to react.
local HINTS = {
	catch = "Stand in a landing circle to catch scoops",
	cart = "Carry your tower to your cart",
	steady = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		then "It's tipping! Tap Steady"
		else "It's tipping! Press F to steady it",
}

local COLORS = {
	ink = Ui.color("ink"),
	vanilla = Ui.color("vanilla"),
	mint = Ui.color("mint"),
	lemon = Ui.color("lemon"),
	awning = Ui.color("awning"),
}

local player = Players.LocalPlayer
local gui: ScreenGui
local coinsText: TextLabel
local ammoBalls: { Frame } = {}
local reloadText: TextLabel
local towerCard: Frame
local countText: TextLabel
local worthText: TextLabel
local steadyDot: Frame
local steadyText: TextLabel
local hintCard: Frame
local hintText: TextLabel
local meter: Frame
local meterStroke: UIStroke
local meterFill: Frame
local levelDot: Frame
local levelStroke: UIStroke
local toastLabel: TextLabel
local toastStroke: UIStroke
local cartMarker: BillboardGui
local toastTweens: { Tween } = {}

local towerCount = 0
local warning = false
local rescueState = "ready"
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

	-- ice balls left in the load; while the load reloads, the seconds until it is full again
	local ammo = Ui.card({
		Name = "IceBalls",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
	}, UDim.new(0.5, 0))
	Ui.padding(ammo, 10, 0)
	Ui.list(ammo, Enum.FillDirection.Horizontal, 6)
	for index = 1, CombatConfig.ammo do
		local ball = Ui.circle(18, "skyTop", { Name = "Ball" .. index, LayoutOrder = index })
		Ui.stroke(ball, "vanilla", 2, 0.4)
		ball.Parent = ammo
		ammoBalls[index] = ball
	end
	reloadText = Ui.text({ Name = "Reload", LayoutOrder = CombatConfig.ammo + 1, TextSize = 18, Visible = false })
	reloadText.Parent = ammo
	ammo.Parent = side
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
-- Bottom right on PC, below the player list; above the jump button on touch screens.
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

	-- A spirit level above the bar: the dot shows which way the top leans, seen from the camera (up = away from
	-- you). Leaning towards or away from the camera is hard to see on the tower itself, and walking causes it.
	local level
	level, levelStroke = Ui.card({
		Name = "Level",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -28),
		Size = UDim2.fromOffset(LEVEL_SIZE, LEVEL_SIZE),
	}, UDim.new(0.5, 0))
	local centre = Ui.circle(10, "vanilla", {
		Name = "Centre",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 0.7,
	})
	centre.Parent = level
	levelDot = Ui.circle(LEVEL_DOT, "mint", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 2,
	})
	levelDot.Parent = level
	level.Parent = meter
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
		hintText.Text = HINTS[key]
	end
end

local function refreshHint()
	if towerCount == 0 then
		setHint(if hasServed then nil else "catch")
	elseif warning and rescueState == "ready" then
		setHint("steady")
	elseif not hasServed and not atCart then
		setHint("cart")
	else
		setHint(nil)
	end
end

function Hud.Init()
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

	RunService.RenderStepped:Connect(function()
		local count = player:GetAttribute("IceBalls")
		count = if type(count) == "number" then count else CombatConfig.ammo
		for index, ball in ammoBalls do
			ball.BackgroundTransparency = if index <= count then 0 else 0.8
		end
		local readyAt = player:GetAttribute("IceBallsReadyAt")
		local left = if type(readyAt) == "number" then readyAt - workspace:GetServerTimeNow() else 0
		reloadText.Visible = count <= 0 and left > 0
		if reloadText.Visible then
			reloadText.Text = string.format("%.1fs", left)
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

-- tilt is the share of the tip angle; leanX/leanY the lean in screen space as a share of it (x right, y away
-- from the camera). rescue is "ready", "active" or "cooldown".
function Hud.setBalance(tilt: number, groaning: boolean, visible: boolean, leanX: number, leanY: number, rescue: string)
	meter.Visible = visible
	warning = visible and tilt >= Tuning.warnFraction
	rescueState = rescue
	if not visible then
		return
	end
	meterFill.Size = UDim2.fromScale(1, math.clamp(1 - tilt, 0, 1))
	local danger = groaning or tilt >= Tuning.groanFraction
	local color = if danger then COLORS.awning elseif tilt >= 0.5 then COLORS.lemon else COLORS.mint
	meterFill.BackgroundColor3 = color
	local radius = (LEVEL_SIZE - LEVEL_DOT) / 2 - 2
	local dotX = math.round(math.clamp(leanX, -1, 1) * radius)
	local dotY = math.round(-math.clamp(leanY, -1, 1) * radius)
	levelDot.Position = UDim2.new(0.5, dotX, 0.5, dotY)
	levelDot.BackgroundColor3 = color
	meterFill.BackgroundTransparency = if groaning then 0.35 + 0.35 * math.sin(os.clock() * 18) else 0
	meterStroke.Color = if danger then COLORS.awning else COLORS.vanilla
	meterStroke.Transparency = if danger then 0 else 0.6

	-- the level's rim: mint while a rescue works, a red pulse when it is time to react, faded while cooling down
	if rescue == "active" then
		levelStroke.Color = COLORS.mint
		levelStroke.Transparency = 0
		levelStroke.Thickness = 3
	elseif warning then
		levelStroke.Color = COLORS.awning
		levelStroke.Transparency = 0.5 - 0.5 * math.sin(os.clock() * 10)
		levelStroke.Thickness = 3
	else
		levelStroke.Color = COLORS.vanilla
		levelStroke.Transparency = if rescue == "cooldown" then 0.85 else 0.6
		levelStroke.Thickness = 2
	end
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
