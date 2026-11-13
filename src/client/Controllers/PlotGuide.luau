-- The way to the own plot, shown instead of told (Config/Ui.guide, GuideRules). Always: a faint pin with the house
-- icon and YOU floats over the own serve point, the same size on screen from anywhere on the map, fading out near the
-- plot and fainter and smaller in combat mode. Once the cone is three quarters full the pin turns solid, a light stands
-- over the serve point, an arrow at the screen's edge points there while it is outside the picture, and coming to it
-- with scoops lights up a ring on the ground. After spawning and after a teleport into the arena the arrow also shows
-- for a moment. All of it lives on this client only (Terrain attachments, PlayerGui, the camera): nobody else sees it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GuideRules = require(Shared:WaitForChild("GuideRules"))
local ArenaZone = require(Shared:WaitForChild("ArenaZone"))
local UiConfig = require(Shared:WaitForChild("Config"):WaitForChild("Ui"))
local MapConfig = require(Shared:WaitForChild("Config"):WaitForChild("Map"))

local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local Theme, Screen = UiKit.Theme, UiKit.Screen

local PlotGuide = {}

local Look = UiConfig.guide
local COLOR = Color3.fromHex(Look.color)
local FADE_SPEED = 3 -- the light comes and goes in about a third of a second
local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder lying flat: its axis points up

local player = Players.LocalPlayer
local registry
local bottom: Attachment
local top: Attachment
local beam: Beam
local glowBeam: Beam
local arrowGui: ScreenGui
local arrow: Frame
local arrowTurn: Frame
local pinGroup: CanvasGroup
local pinScale: UIScale
local lightAlpha = 0 -- 0 hidden .. 1 fully shown
local wasNear = false
local flashUntil = 0 -- the arrow shows until then (os.clock) after a spawn or a teleport into the arena
local lastRoot: Vector3? = nil
local TELEPORT_JUMP = 40 -- studs between two frames: a teleport, not a run or a dash

-- The light's look at `alpha` (0..1): strong at the foot, gone at the top.
local function setLight(alpha: number)
	local base = 1 - (1 - Look.transparency) * alpha
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, base),
		NumberSequenceKeypoint.new(0.6, 1 - (1 - base) * 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	glowBeam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - (1 - base) * 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Enabled = alpha > 0.01
	glowBeam.Enabled = beam.Enabled
end

local function buildLight()
	local terrain = workspace.Terrain
	bottom = Instance.new("Attachment")
	bottom.Name = "PlotGuideFoot"
	bottom.Parent = terrain
	top = Instance.new("Attachment")
	top.Name = "PlotGuideTop"
	top.Parent = terrain
	local function make(width: number): Beam
		local made = Instance.new("Beam")
		made.Attachment0 = bottom
		made.Attachment1 = top
		made.FaceCamera = true
		made.Segments = 1
		made.Width0 = width
		made.Width1 = width * 0.72
		made.LightEmission = Look.lightEmission
		made.LightInfluence = 0
		made.Color = ColorSequence.new(COLOR)
		made.Enabled = false
		made.Parent = terrain
		return made
	end
	beam = make(Look.width)
	glowBeam = make(Look.glowWidth) -- a soft wide halo round the core
	setLight(0)
end

-- The house icon in a cream bubble with a yellow tip, `size` design pixels across, filling `parent`: the arrow at the
-- screen's edge and the pin over the plot. The tip is a square turned on its corner, half behind the bubble, so a
-- triangle shows (one clear shape, readable small on a phone); it sits on the right of the returned frame, which turns
-- to point it (0 right, 90 down).
local function pinShape(parent: GuiObject, size: number): Frame
	local bubble = Theme.frame({
		Name = "Bubble",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("cream"),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = parent,
	})
	Theme.corner(bubble, UDim.new(0.5, 0))
	Theme.outline(bubble, 3)
	Theme.icon(Theme.icons.plot, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		ZIndex = 3,
		Parent = bubble,
	})
	local turn = Theme.frame({ Name = "Turn", Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = parent })
	local tip = Theme.frame({
		Name = "Tip",
		BackgroundTransparency = 0,
		BackgroundColor3 = COLOR,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.86, 0.5),
		Size = UDim2.fromOffset(size * 0.6, size * 0.6),
		Rotation = 45,
		ZIndex = 1,
		Parent = turn,
	})
	Theme.corner(tip, UDim.new(0.18, 0))
	Theme.outline(tip, 3)
	return turn
end

-- The arrow at the screen's edge, pointing to the plot.
local function buildArrow()
	arrowGui = Instance.new("ScreenGui")
	arrowGui.Name = "PlotGuide"
	arrowGui.ResetOnSpawn = false
	arrowGui.IgnoreGuiInset = true -- viewport points from the camera map onto it directly
	arrowGui.ScreenInsets = Enum.ScreenInsets.None
	arrowGui.DisplayOrder = 4
	arrowGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	arrowGui.Parent = player:WaitForChild("PlayerGui")
	local size = Look.arrow
	arrow = Theme.frame({
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		Visible = false,
		Parent = arrowGui,
	})
	local scale = Instance.new("UIScale")
	scale.Name = "Layout"
	scale.Parent = arrow
	Screen.onChanged(function(plan)
		scale.Scale = plan.scale
	end)
	arrowTurn = pinShape(arrow, size)
end

-- The pin over the own plot: the same bubble with its tip pointing down and YOU under it. It is drawn in the arrow's
-- ScreenGui at the plot's projected point (update), so it keeps its size on screen at any distance and shows through
-- everything; a BillboardGui with AlwaysOnTop was not drawn at all in the Studio playtest (13.11.2026), and without it
-- walls hid the pin. Only this player has it (their PlayerGui).
local function buildPin()
	-- a CanvasGroup fades bubble, tip, word and outlines as one; its bottom middle sits on the projected point
	pinGroup = Instance.new("CanvasGroup")
	pinGroup.Name = "Pin"
	pinGroup.BackgroundTransparency = 1
	pinGroup.AnchorPoint = Vector2.new(0.5, 1)
	pinGroup.Size = UDim2.fromOffset(Look.pin * 1.6, Look.pin * 2.1)
	pinGroup.Visible = false
	pinGroup.ZIndex = 0
	pinGroup.Parent = arrowGui
	pinScale = Instance.new("UIScale")
	pinScale.Parent = pinGroup
	local holder = Theme.frame({
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(Look.pin, Look.pin),
		Parent = pinGroup,
	})
	pinShape(holder, Look.pin).Rotation = 90
	Theme.text({
		Name = "You",
		Text = "YOU",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Look.pin * 1.25 + 4),
		Size = UDim2.fromOffset(Look.pin * 1.5, Look.pin * 0.5),
		TextScaled = true,
		ZIndex = 4,
		Parent = pinGroup,
	})
end
-- The ring that lights up on the ground at the serve point when the player arrives with scoops.
local function glow(servePoint: BasePart)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { servePoint.Parent :: Instance, player.Character :: Instance }
	local hit = workspace:Raycast(servePoint.Position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
	local y = if hit then hit.Position.Y else servePoint.Position.Y
	local ring = Instance.new("Part")
	ring.Name = "PlotGuideGlow"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = COLOR
	ring.Transparency = 0.15
	ring.Size = Vector3.new(0.12, Look.glowSize * 0.4, Look.glowSize * 0.4)
	ring.CFrame = CFrame.new(servePoint.Position.X, y + 0.1, servePoint.Position.Z) * FLAT
	ring.Parent = workspace.CurrentCamera -- local only, never in the way of a raycast of the game
	TweenService:Create(ring, TweenInfo.new(Look.glowTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, Look.glowSize, Look.glowSize),
		Transparency = 1,
	}):Play()
	task.delay(Look.glowTime + 0.1, function()
		ring:Destroy()
	end)
end

local pinTransparency = 1 -- what the pin shows now, eased towards GuideRules.pinLook
local pinSize = 1

local function update(dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local servePoint = registry.TowerController.servePoint()
	local count, capacity = registry.TowerController.fill()
	local distance = if root and servePoint then (root.Position - servePoint.Position).Magnitude else math.huge

	-- a jump of many studs in one frame that lands in the arena: a teleport there, so show the way home a moment
	if root then
		local position = root.Position
		if
			lastRoot
			and (position - lastRoot).Magnitude > TELEPORT_JUMP
			and ArenaZone.contains(position.X, position.Z, MapConfig.arena)
		then
			flashUntil = os.clock() + Look.arrowFlash
		end
		lastRoot = position
	end

	local near = GuideRules.near(distance, Look)
	if servePoint and GuideRules.arrived(count, wasNear, distance, Look) then
		glow(servePoint)
	end
	wasNear = near

	local show = servePoint ~= nil and root ~= nil and GuideRules.showLight(count, capacity, distance, Look)
	lightAlpha = math.clamp(lightAlpha + (if show then dt else -dt) * FADE_SPEED, 0, 1)
	if servePoint then
		bottom.WorldPosition = servePoint.Position
		top.WorldPosition = servePoint.Position + Vector3.new(0, Look.height, 0)
	end
	setLight(lightAlpha)

	-- the pin: always there, solid once the cone is nearly full, faint and small in combat mode, gone on the plot;
	-- on screen where the point over the serve point is, hidden while that point is behind the camera
	local camera = workspace.CurrentCamera
	local pinPoint = if servePoint and camera
		then camera:WorldToViewportPoint(servePoint.Position + Vector3.new(0, Look.pinHeight, 0))
		else nil
	local pinOn = root ~= nil and pinPoint ~= nil and pinPoint.Z > 0
	if not pinOn then
		pinGroup.Visible = false
	else
		pinGroup.Position = UDim2.fromOffset(pinPoint.X, pinPoint.Y)
		local strong = GuideRules.showLight(count, capacity, math.huge, Look)
		local combat = player:GetAttribute("CombatMode") == true
		local wantTransparency, wantScale = GuideRules.pinLook(distance, strong, combat, Look)
		local ease = math.clamp(dt * 6, 0, 1)
		pinTransparency += (wantTransparency - pinTransparency) * ease
		pinSize += (wantScale - pinSize) * ease
		pinGroup.GroupTransparency = pinTransparency
		pinGroup.Visible = pinTransparency < 0.99
		pinScale.Scale = pinSize * Screen.plan().scale
	end

	-- the arrow: with a nearly full cone, or for a moment after a spawn or a teleport into the arena; never on the plot
	local wanted = show or (os.clock() < flashUntil and not near)
	if wanted and camera and servePoint then
		local target = servePoint.Position + Vector3.new(0, 4, 0)
		local point = camera:WorldToViewportPoint(target) -- Z > 0: in front of the camera
		local viewport = camera.ViewportSize
		local x, y, angle = GuideRules.edgeArrow(
			point.X,
			point.Y,
			point.Z > 0,
			viewport.X,
			viewport.Y,
			Look.arrowMargin * Screen.plan().scale
		)
		arrow.Visible = x ~= nil
		if x and y and angle then
			arrow.Position = UDim2.fromOffset(x, y)
			arrowTurn.Rotation = angle
		end
	else
		arrow.Visible = false
	end
end

function PlotGuide.Init(reg)
	registry = reg
end

function PlotGuide.Start()
	buildLight()
	buildArrow()
	buildPin()
	-- every spawn: the way home for a moment (the new body is no teleport to measure)
	local function spawned()
		flashUntil = os.clock() + Look.arrowFlash
		lastRoot = nil
	end
	player.CharacterAdded:Connect(spawned)
	if player.Character then
		spawned()
	end
	RunService.RenderStepped:Connect(update)
end
return PlotGuide
