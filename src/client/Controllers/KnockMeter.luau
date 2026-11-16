-- The local player's own life bar (Config/Combat knock and healthBar, HealthPips) below the crosshair: the same bar
-- every rival has over their head (EnemyHealthBars, HealthBarView), so both read as one system. One segment per normal
-- hit up to the knockdown, emptied as hits add points, flashing white with a little shake on each hit, filling up again
-- once the count drops back to 0 after resetAfter seconds without a hit. Grey while knocked down, blue with
-- "PROTECTED" under it while the get-up protection lasts. It reads the KnockPoints, KnockResetAt, KnockProtectedUntil
-- and DownUntil attributes the server sets, so it only ever shows what the server counted. Shown in the arena while
-- there is something to show; it fades in and out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HitPoints = require(Shared:WaitForChild("HitPoints"))
local HealthPips = require(Shared:WaitForChild("HealthPips"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))

local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))
local HealthBarView = require(client:WaitForChild("HealthBarView"))

local KnockMeter = {}

local Knock = CombatConfig.knock
local Bar = CombatConfig.healthBar
local Look = Bar.own

local player = Players.LocalPlayer
local view: HealthBarView.View
local label: TextLabel
local shown = 1 -- share of the bar drawn (it refills over Bar.refill)
local alpha = 0
local lastResetAt: number? = nil

function KnockMeter.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "KnockMeter"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- centred on the viewport like the crosshair
	gui.Parent = player:WaitForChild("PlayerGui")

	-- the holder scales with the screen round the crosshair's middle, so the bar keeps its place under it
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(0, 0)
	holder.BackgroundTransparency = 1
	Ui.autoScale(holder)
	holder.Parent = gui

	view = HealthBarView.new(2.5)
	view.root.AnchorPoint = Vector2.new(0.5, 0)
	view.root.Position = UDim2.fromOffset(0, Look.below)
	view.root.Size = UDim2.fromOffset(Look.width, Look.height)
	view.root.Parent = holder

	label = Ui.text({ Text = "PROTECTED", TextSize = 14, AnchorPoint = Vector2.new(0.5, 0) })
	label.Position = UDim2.fromOffset(0, Look.below + Look.height + 3)
	label.TextColor3 = Color3.fromHex(Bar.colors.protected)
	label.Visible = false
	Ui.stroke(label, "outline", 2, 0).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	label.Parent = holder
end

local function number(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function onStep(dt: number)
	local now = workspace:GetServerTimeNow()
	local resetAt = number("KnockResetAt")
	local points, protected =
		HitPoints.display(number("KnockPoints"), resetAt, number("KnockProtectedUntil"), now, Knock)
	local down = now < number("DownUntil")
	if lastResetAt ~= nil and resetAt ~= lastResetAt then
		view.hit(os.clock()) -- a new counted hit moved the reset time
	end
	lastResetAt = resetAt

	local target = if down then 0 else HealthPips.left(points, Knock)
	shown = HealthPips.approach(shown, target, dt, Bar.refill)
	view.set(shown, HealthPips.tone(shown, down, protected, Bar))
	view.step(os.clock())

	local wanted = player:GetAttribute("InArena") == true and (shown < 1 or down or protected)
	alpha = math.clamp(alpha + (if wanted then dt else -dt) / Bar.fade, 0, 1)
	view.setAlpha(alpha)
	view.root.Visible = alpha > 0
	label.Visible = wanted and protected and not down
end

function KnockMeter.Start()
	RunService.RenderStepped:Connect(onStep)
end

return KnockMeter
