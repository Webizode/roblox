-- The four HUD elements: coins, tower value + steady bonus, a toast for SERVE!/SAVED!/TOPPLED!, and a
-- marker on the player's own cart.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Palette"))

local Hud = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local coinsLabel: TextLabel
local towerLabel: TextLabel
local toastLabel: TextLabel
local cartMarker: BillboardGui
local toastTween: Tween?

local function label(name: string, props: { [string]: any }): TextLabel
	local instance = Instance.new("TextLabel")
	instance.Name = name
	instance.BackgroundTransparency = 1
	instance.Font = Enum.Font.FredokaOne
	instance.TextColor3 = Color3.fromHex(Palette.ink)
	instance.TextStrokeColor3 = Color3.new(1, 1, 1)
	instance.TextStrokeTransparency = 0.3
	instance.TextScaled = true
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = gui
	return instance
end

function Hud.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	coinsLabel = label("Coins", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(260, 40),
		Text = "0 coins",
	})
	towerLabel = label("Tower", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(420, 34),
		Text = "",
	})
	toastLabel = label("Toast", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(460, 70),
		Text = "",
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	-- BillboardGuis do not render inside a ScreenGui, so this one lives directly in PlayerGui
	cartMarker = Instance.new("BillboardGui")
	cartMarker.Name = "CartMarker"
	cartMarker.AlwaysOnTop = true
	cartMarker.ResetOnSpawn = false
	cartMarker.Size = UDim2.fromOffset(140, 36)
	cartMarker.StudsOffset = Vector3.new(0, 4, 0)
	cartMarker.Enabled = false
	cartMarker.Parent = gui.Parent
	local markerText = Instance.new("TextLabel")
	markerText.Size = UDim2.fromScale(1, 1)
	markerText.BackgroundColor3 = Color3.fromHex(Palette.lemon)
	markerText.Font = Enum.Font.FredokaOne
	markerText.TextScaled = true
	markerText.TextColor3 = Color3.fromHex(Palette.ink)
	markerText.Text = "YOUR CART"
	markerText.Parent = cartMarker
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = markerText
end

function Hud.Start()
	local leaderstats = player:WaitForChild("leaderstats")
	local coins = leaderstats:WaitForChild("Coins") :: IntValue
	local function update()
		coinsLabel.Text = string.format("%d coins", coins.Value)
	end
	coins.Changed:Connect(update)
	update()
end

function Hud.setTower(count: number, value: number, steady: number)
	if count == 0 then
		towerLabel.Text = "Stand in a landing circle to catch scoops"
		return
	end
	local steadyText = if steady > 0 then string.format("  ·  steady +%d%%", math.floor(steady * 100 + 0.5)) else ""
	towerLabel.Text = string.format("%d scoops  ·  worth %d%s", count, math.floor(value), steadyText)
end

function Hud.toast(text: string, colorHex: string?)
	if toastTween then
		toastTween:Cancel()
	end
	toastLabel.Text = text
	toastLabel.TextColor3 = Color3.fromHex(colorHex or Palette.ink)
	toastLabel.TextTransparency = 0
	toastLabel.TextStrokeTransparency = 0.2
	toastTween = TweenService:Create(
		toastLabel,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.9),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	toastTween:Play()
end

function Hud.setCartTarget(part: BasePart?)
	cartMarker.Adornee = part
	cartMarker.Enabled = part ~= nil
end

return Hud
