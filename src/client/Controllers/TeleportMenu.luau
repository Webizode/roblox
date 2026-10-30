-- The teleport buttons at the top of the screen ("my plot", "arena") and the "safe zone" note under them. Both show
-- only outside the arena; the client asks ArenaZone with the character's position, the same function the server uses,
-- and changes what it shows once the answer has held for Config/Map.arena.displayDelay, so nothing flickers on the
-- line. The buttons are always clickable (mouse, touch, gamepad selection); the server decides at once and drops only
-- request floods. Features.debugArenaZone draws the zone half transparent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MapConfig = require(Config:WaitForChild("Map"))
local Features = require(Config:WaitForChild("Features"))
local ArenaZone = require(Shared:WaitForChild("ArenaZone"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))

local TeleportMenu = {}

local player = Players.LocalPlayer
local zone = MapConfig.arena
local panel: Frame
local shown: boolean? = nil -- what the screen shows: true outside the arena
local pending: boolean? = nil -- what the zone says now
local pendingSince = 0

local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local outside = if root then not ArenaZone.contains(root.Position.X, root.Position.Z, zone) else false
	local now = os.clock()
	if outside ~= pending then
		pending, pendingSince = outside, now
	end
	if pending ~= shown and (shown == nil or now - pendingSince >= zone.displayDelay) then
		shown = pending
		panel.Visible = shown == true
	end
end

-- The zone, half transparent: the floor disc and every ramp up to its top edge (Studio testing only).
local function drawZone()
	local folder = Instance.new("Folder")
	folder.Name = "ArenaZoneDebug"
	local function piece(size: Vector3, cframe: CFrame, shape: Enum.PartType)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromHex("#FF5A6E")
		p.Transparency = 0.75
		p.Shape = shape
		p.Size = size
		p.CFrame = cframe
		p.Parent = folder
	end
	local cx, cz, height = zone.center.x, zone.center.z, 24
	piece(
		Vector3.new(height, zone.radius * 2, zone.radius * 2),
		CFrame.new(cx, height / 2, cz) * CFrame.Angles(0, 0, math.rad(90)),
		Enum.PartType.Cylinder
	)
	for index = 1, zone.ramps do
		local sx, sz = ArenaZone.lane(index, zone)
		local direction = Vector3.new(sx, 0, sz)
		-- from well inside the disc to the ramp's top edge
		local from, to = zone.radius - 10, zone.rampTop
		local middle = Vector3.new(cx, height / 2, cz) + direction * ((from + to) / 2)
		piece(
			Vector3.new(zone.rampHalfWidth * 2, height, to - from),
			CFrame.lookAt(middle, middle + direction),
			Enum.PartType.Block
		)
	end
	folder.Parent = workspace
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Teleport"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 12)
	panel.Size = UDim2.fromOffset(0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.Parent = gui
	Ui.list(panel, Enum.FillDirection.Vertical, 6)
	Ui.autoScale(panel)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.LayoutOrder = 1
	bar.Size = UDim2.fromOffset(0, 52)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundTransparency = 1
	bar.Parent = panel
	Ui.list(bar, Enum.FillDirection.Horizontal, 12)

	local buttons = {
		{ where = "plot", text = "MY PLOT", color = "mint" },
		{ where = "arena", text = "ARENA", color = "strawberry" },
	}
	for order, entry in buttons do
		local button = Ui.button({
			Name = entry.where,
			Text = entry.text,
			LayoutOrder = order,
			Size = UDim2.fromOffset(150, 52),
			Selectable = true,
			Parent = bar,
		})
		-- a coloured stripe on the left says which one it is at a glance
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 8, 1, -16)
		stripe.Position = UDim2.fromOffset(10, 8)
		stripe.BorderSizePixel = 0
		stripe.BackgroundColor3 = Ui.color(entry.color)
		stripe.Parent = button
		Ui.corner(stripe, UDim.new(0.5, 0))
		button.Activated:Connect(function()
			Remotes.TeleportRequest:FireServer(entry.where)
		end)
	end

	-- the note that nobody can hit you here
	local note = Ui.card({
		Name = "SafeZone",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = panel,
	}, UDim.new(0.5, 0))
	Ui.padding(note, 14, 0)
	Ui.list(note, Enum.FillDirection.Horizontal, 8)
	local dot = Ui.circle(10, "mint", { LayoutOrder = 1 })
	dot.Parent = note
	Ui.text({ Text = "SAFE ZONE", TextSize = 16, TextColor3 = Ui.color("mint"), LayoutOrder = 2, Parent = note })
end

function TeleportMenu.Start()
	build()
	if Features.debugArenaZone then
		drawZone()
	end
	RunService.RenderStepped:Connect(update)
end

return TeleportMenu
