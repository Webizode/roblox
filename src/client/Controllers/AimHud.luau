-- The crosshair, only in combat mode: one clean thin circle fixed in the middle of the screen, where every throw aims.
-- Its size comes from AimRules (bigger while moving, sprinting, after a dash and right after a throw, a little smaller
-- while a throw is held). While the throw button is held a small inner circle grows from the middle to the outer
-- circle and shrinks back, again and again (Combat.pulse); while letting go would be a perfect throw both turn green.
-- A hit of the local player flashes a red X in it, a headshot a bigger gold one (feedback.headshotMark). It is fixed:
-- white, its size from Config/Combat crosshair, no settings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Combat = require(Shared:WaitForChild("Combat"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))

local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))

local AimHud = {}

local Look = CombatConfig.crosshair
local PERFECT = Color3.fromHex(Look.perfectColor)
local MARK = Ui.color("awning")
local HEADSHOT = Ui.color("lemon")

local holder: Frame
local outer: Frame
local outerStroke: UIStroke
local inner: Frame
local innerStroke: UIStroke
local mark: Frame
local COLOR = Ui.color("white") -- fixed: the crosshair is not a setting
local markUntil = 0
local markBars: { Frame } = {}

-- A thin ring centred on the holder: a light line with a faint dark edge, so it reads on sky, sand and ice cream.
local function ring(name: string): (Frame, UIStroke)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundTransparency = 1
	Ui.corner(frame, UDim.new(0.5, 0))
	local line = Ui.stroke(frame, "white", Look.thickness, 0.05)
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Position = UDim2.fromScale(0.5, 0.5)
	edge.Size = UDim2.new(1, Look.thickness * 2, 1, Look.thickness * 2)
	edge.BackgroundTransparency = 1
	Ui.corner(edge, UDim.new(0.5, 0))
	Ui.stroke(edge, "ink", 1, 0.7)
	edge.Parent = frame
	frame.Parent = holder
	return frame, line
end

local function bar(rotation: number): Frame
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale(0.5, 0.5)
	line.Size = UDim2.new(1, 0, 0, 2)
	line.Rotation = rotation
	line.BackgroundColor3 = MARK
	line.BorderSizePixel = 0
	return line
end

function AimHud.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Aim"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- centred on the viewport, the point the throw aims through
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	holder = Instance.new("Frame")
	holder.Name = "Crosshair"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(0, 0)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui

	outer, outerStroke = ring("Outer")
	inner, innerStroke = ring("Inner")
	inner.Visible = false

	mark = Instance.new("Frame")
	mark.Name = "HitMark"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromOffset(14, 14)
	mark.Visible = false
	local a, b = bar(45), bar(-45)
	a.Parent, b.Parent = mark, mark
	markBars = { a, b }
	mark.Parent = holder
end

-- The local player's throw hit somebody: the red X flashes in the crosshair; a headshot shows a bigger, thicker gold
-- X for longer.
function AimHud.mark(headshot: boolean?)
	local look = CombatConfig.feedback
	local size = if headshot then look.headshotMark.size else 14
	mark.Size = UDim2.fromOffset(size, size)
	for _, line in markBars do
		line.BackgroundColor3 = if headshot then HEADSHOT else MARK
		line.Size = UDim2.new(1, 0, 0, if headshot then look.headshotMark.thickness else 2)
	end
	markUntil = os.clock() + (if headshot then look.headshotMark.time else look.markTime)
end

-- Called every frame. `active` shows the crosshair (combat mode), `ready` dims it while no throw is possible (empty
-- load); `radius` is its size (AimRules), `held` the seconds the throw button is held (nil:
-- not held).
function AimHud.set(active: boolean, ready: boolean, radius: number, held: number?)
	holder.Visible = active
	if not active then
		return
	end
	local perfect = held ~= nil and Combat.isPerfect(held, CombatConfig)
	local tint = if perfect then PERFECT else COLOR
	local r = radius
	outer.Size = UDim2.fromOffset(r * 2, r * 2)
	outerStroke.Color = tint
	outerStroke.Transparency = if ready then 0.05 else 0.6

	inner.Visible = held ~= nil
	if held then
		local share = Combat.pulse(held, CombatConfig)
		local ri = math.max(1, r * share)
		inner.Size = UDim2.fromOffset(ri * 2, ri * 2)
		innerStroke.Color = tint
	end

	mark.Visible = os.clock() < markUntil
end

return AimHud
