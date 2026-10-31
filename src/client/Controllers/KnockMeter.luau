-- The local player's own knockdown meter (Config/Combat knock, feedback.meter): a row of segments below the
-- crosshair, one per point up to the knockdown, filled red as hits add up and empty again once the count drops back
-- to 0 after resetAfter seconds without a hit. While the get-up protection lasts the row turns mint with
-- "PROTECTED" under it. It reads the KnockPoints, KnockResetAt and KnockProtectedUntil attributes the server sets
-- (HitPoints.display), so it only ever shows what the server counted. Shown in the arena, while there is something
-- to show.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HitPoints = require(Shared:WaitForChild("HitPoints"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))

local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))

local KnockMeter = {}

local Knock = CombatConfig.knock
local Look = CombatConfig.feedback.meter
local FULL = Ui.color("awning")
local SAFE = Ui.color("mint")
local EMPTY = Ui.color("ink")

local player = Players.LocalPlayer
local row: Frame
local label: TextLabel
local segments: { Frame } = {}

function KnockMeter.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "KnockMeter"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- centred on the viewport like the crosshair
	gui.Parent = player:WaitForChild("PlayerGui")

	local count = Knock.knockdownAt
	row = Instance.new("Frame")
	row.Name = "Row"
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0.5, Look.below)
	row.Size = UDim2.fromOffset(count * Look.segment + (count - 1) * Look.gap, Look.height)
	row.BackgroundTransparency = 1
	row.Visible = false
	Ui.list(row, Enum.FillDirection.Horizontal, Look.gap)
	for index = 1, count do
		local segment = Instance.new("Frame")
		segment.Name = "Point" .. index
		segment.LayoutOrder = index
		segment.Size = UDim2.fromOffset(Look.segment, Look.height)
		segment.BorderSizePixel = 0
		Ui.corner(segment, UDim.new(0.5, 0))
		Ui.stroke(segment, "ink", 1, 0.3)
		segment.Parent = row
		segments[index] = segment
	end
	row.Parent = gui

	label = Ui.text({ Text = "PROTECTED", TextSize = 14, AnchorPoint = Vector2.new(0.5, 0) })
	label.Position = UDim2.new(0.5, 0, 0.5, Look.below + Look.height + 4)
	label.TextColor3 = SAFE
	label.Visible = false
	Ui.stroke(label, "ink", 1.5, 0.1).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	label.Parent = gui
end

local function number(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function onStep()
	local points, protected = HitPoints.display(
		number("KnockPoints"),
		number("KnockResetAt"),
		number("KnockProtectedUntil"),
		workspace:GetServerTimeNow(),
		Knock
	)
	local shown = player:GetAttribute("InArena") == true and (points > 0 or protected)
	row.Visible = shown
	label.Visible = shown and protected
	if not shown then
		return
	end
	for index, segment in segments do
		local filled = index <= points
		segment.BackgroundColor3 = if protected then SAFE elseif filled then FULL else EMPTY
		segment.BackgroundTransparency = if filled or protected then 0 else 0.55
	end
end

function KnockMeter.Start()
	RunService.RenderStepped:Connect(onStep)
end

return KnockMeter
