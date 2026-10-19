-- The crosshair in the middle of the screen and, while the throw button is held, the charge bar under it. The
-- crosshair marks where a throw goes (CombatController aims through the screen centre); the bar shows how strong
-- the next throw will be, weak to strong from left to right, with the maximum marked at its right end. Both stay
-- small and below the aim point, so they never cover what the player aims at.

local Players = game:GetService("Players")

local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))

local AimHud = {}

local BAR_WIDTH = 120
local BAR_HEIGHT = 10
local BAR_GAP = 28 -- pixels from the screen centre down to the bar
local MAX_AT = 0.97 -- from this charge on the maximum point lights up
local MAX_SIZE, MAX_SIZE_LIT = 12, 18

local COLORS = {
	ink = Ui.color("ink"),
	lemon = Ui.color("lemon"),
}

local ring: UIStroke
local dot: Frame
local bar: Frame
local fill: Frame
local maxPoint: Frame
local shownReady: boolean? = nil
local shownLit: boolean? = nil

local function centred(props: { [string]: any }?): { [string]: any }
	local result = { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }
	for key, value in props or {} do
		result[key] = value
	end
	return result
end

function AimHud.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Aim"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- centred on the viewport, the point the throw aims through
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- a thin ring around a dot: easy to see on any background, too small to hide a target
	local circle = Ui.circle(22, "ink", centred({ Name = "Crosshair", BackgroundTransparency = 1 }))
	ring = Ui.stroke(circle, "vanilla", 2, 0.25)
	circle.Parent = gui
	dot = Ui.circle(6, "vanilla", centred({ Name = "Dot" }))
	Ui.stroke(dot, "ink", 1.5, 0.2)
	dot.Parent = gui

	bar = Instance.new("Frame")
	bar.Name = "Charge"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0.5, BAR_GAP)
	bar.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	bar.BackgroundColor3 = COLORS.ink
	bar.BackgroundTransparency = 0.35
	bar.BorderSizePixel = 0
	bar.Visible = false
	Ui.corner(bar, UDim.new(0.5, 0))
	Ui.stroke(bar, "vanilla", 1.5, 0.5)
	bar.Parent = gui

	-- the fill clips a full-width gradient, so every colour stays at its place: weak on the left, strong on the right
	fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundTransparency = 1
	fill.ClipsDescendants = true
	fill.Parent = bar
	local strip = Instance.new("Frame")
	strip.Name = "Gradient"
	strip.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	strip.BackgroundColor3 = Color3.new(1, 1, 1)
	strip.BorderSizePixel = 0
	Ui.corner(strip, UDim.new(0.5, 0))
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Ui.color("mint")),
		ColorSequenceKeypoint.new(0.55, Ui.color("lemon")),
		ColorSequenceKeypoint.new(1, Ui.color("awning")),
	})
	gradient.Parent = strip
	strip.Parent = fill

	-- the maximum: always visible at the right end, lit while the bar is at the top
	maxPoint = Ui.circle(MAX_SIZE, "ink", {
		Name = "Max",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		ZIndex = 2,
	})
	Ui.stroke(maxPoint, "lemon", 2, 0)
	maxPoint.Parent = bar
end

-- Called every frame: `ready` dims the crosshair while no throw is possible (empty load, knocked down); `charge`
-- is the bar value while the throw button is held, nil hides the bar.
function AimHud.set(ready: boolean, charge: number?)
	if shownReady ~= ready then
		shownReady = ready
		ring.Transparency = if ready then 0.25 else 0.7
		dot.BackgroundTransparency = if ready then 0 else 0.6
	end
	bar.Visible = charge ~= nil
	if not charge then
		return
	end
	fill.Size = UDim2.fromScale(math.clamp(charge, 0, 1), 1)
	local lit = charge >= MAX_AT
	if shownLit ~= lit then
		shownLit = lit
		maxPoint.BackgroundColor3 = if lit then COLORS.lemon else COLORS.ink
		maxPoint.Size = UDim2.fromOffset(if lit then MAX_SIZE_LIT else MAX_SIZE, if lit then MAX_SIZE_LIT else MAX_SIZE)
	end
end

return AimHud
