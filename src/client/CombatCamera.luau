-- The camera in combat mode: over the right shoulder, so the character stands left of the screen centre and the
-- crosshair looks past it into the world. It is our own camera for every input: the mouse (held in the centre),
-- the right stick or a finger dragging over the screen (not on a button) turn it, each at its own sensitivity from
-- the settings; walls pull it in. Roblox's default camera only turns with the mouse under its own shift lock or a held
-- right button, and its speeds cannot be set. The character faces where the camera looks, like under shift lock: it turns with the camera, A/D strafe and the throw always goes forward. Leaving hands the camera back to
-- Roblox, looking the same way, and lets the character turn to its walking direction again. While a throw is aimed
-- (setAiming) it eases back by aimZoom and returns afterwards; leaving combat mode always ends that.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))
local LootConfig = require(Shared:WaitForChild("Config"):WaitForChild("Loot"))
local AimRules = require(Shared:WaitForChild("AimRules"))
local Loot = require(Shared:WaitForChild("Loot"))
local MapQuery = require(Shared:WaitForChild("MapQuery"))
local Look = CombatConfig.camera
local Assist = CombatConfig.aimAssist

local Settings = require(script.Parent:WaitForChild("Settings"))

local CombatCamera = {}

local STEP = "WobbleCombatCamera"
local STICK_DEAD_ZONE = 0.15
local WALL_MARGIN = 0.4
local WALL_TRIES = 6 -- non-colliding parts a camera ray may pass before it gives up
local MIN_DISTANCE = 0.5 -- studs from the pivot the camera keeps even right against a wall

local player = Players.LocalPlayer
local active = false
local touchDelta = Vector2.zero -- pixels fingers dragged over the screen since the last frame (not on buttons)
local yaw, pitch = 0, 0
local turned: Humanoid? = nil -- the humanoid whose AutoRotate combat mode switched off
local zoom, zoomTarget = 0, 0 -- extra studs behind the character while aiming, and where it is easing to

-- Eases the aiming zoom towards its target; the same curve whichever camera runs.
local function stepZoom(dt: number): number
	zoom += (zoomTarget - zoom) * (1 - math.exp(-dt / Look.zoomTime))
	return zoom
end

local function releaseFacing()
	if turned then
		turned.AutoRotate = true
		turned = nil
	end
end

-- Turns the character to the camera's flat look direction. The humanoid's own turning to the walking direction is
-- off meanwhile, or it would turn the character straight back.
local function face(character: Model, look: Vector3)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local flat = Vector3.new(look.X, 0, look.Z)
	if not humanoid or not root or humanoid.Health <= 0 or humanoid.Sit or flat.Magnitude < 1e-3 then
		return
	end
	if turned ~= humanoid then
		releaseFacing()
		turned = humanoid
		humanoid.AutoRotate = false
	end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
end

-- Radians per pixel of mouse movement: Roblox's own mouse sensitivity times ours from the settings.
local function mouseSpeed(): number
	local ok, sensitivity = pcall(function()
		return UserSettings():GetService("UserGameSettings").MouseSensitivity
	end)
	local roblox = if ok and type(sensitivity) == "number" then sensitivity else 1
	return Look.mouseSpeed * roblox * Settings.get().mouseSensitivity
end

local function stick(): Vector2
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local position = Vector2.new(input.Position.X, input.Position.Y)
			return if position.Magnitude > STICK_DEAD_ZONE then position else Vector2.zero
		end
	end
	return Vector2.zero
end

-- How far the camera may go from `pivot` along `offset` before it would sit in a solid part: a sphere of
-- Look.wallRadius is swept along the way, so roof edges and palm leaves cannot slip past a thin ray into the near
-- plane. Parts without collision (garlands, decoration layers) are looked through, and so is everything drawn in
-- LocalVisuals (the own tower and its waffle, scoops, balls): they never push the camera.
local function unblocked(pivot: Vector3, offset: Vector3, character: Model): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skipped: { Instance } = { character }
	local visuals = workspace:FindFirstChild("LocalVisuals")
	if visuals then
		table.insert(skipped, visuals)
	end
	for _ = 1, WALL_TRIES do
		params.FilterDescendantsInstances = skipped
		local wall = workspace:Spherecast(pivot, Look.wallRadius, offset, params)
		if not wall then
			return offset
		end
		if wall.Instance:IsA("Terrain") or (wall.Instance :: BasePart).CanCollide then
			return offset.Unit * math.max(MIN_DISTANCE, wall.Distance - WALL_MARGIN)
		end
		table.insert(skipped, wall.Instance)
	end
	return offset
end

-- Whether `other` stands in their own plot's safe zone right now (Loot.isShielded, as the server decides it).
local function shielded(other: Player, position: Vector3): boolean
	local pier = workspace:FindFirstChild("Pier")
	local plots = pier and pier:FindFirstChild("Plots")
	local plotName = other:GetAttribute("PlotName")
	local plot = plots and type(plotName) == "string" and plots:FindFirstChild(plotName)
	local servePoint = plot and plot:FindFirstChild("ServePoint") :: BasePart?
	if not servePoint then
		return false
	end
	local until_ = other:GetAttribute("UnshieldedUntil")
	return Loot.isShielded(
		(position - servePoint.Position).Magnitude,
		workspace:GetServerTimeNow(),
		if type(until_) == "number" then until_ else 0,
		LootConfig
	)
end

-- The rival the aim help works on (AimRules.pick) seen from `camera`: where to draw the camera to and how close to
-- the crosshair they are (0..1), or nil. Only players in front of the crosshair, in plain sight (MapQuery's throw
-- rule: what a ball flies through does not hide anybody) and not in their safe zone.
local function assistTarget(camera: Camera, character: Model): (Vector3?, number)
	local origin, look = camera.CFrame.Position, camera.CFrame.LookVector
	local candidates: { AimRules.Candidate } = {}
	local points: { Vector3 } = {}
	for _, other in Players:GetPlayers() do
		local body = other ~= player and other.Character
		local root = body and body:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = body and body:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local point = root.Position + Vector3.new(0, Assist.aimHeight, 0)
			local to = point - origin
			local distance = to.Magnitude
			local angle = math.deg(math.acos(math.clamp(look:Dot(to.Unit), -1, 1)))
			local visible = false
			if angle < Assist.maxAngle and distance <= Assist.maxRange then
				local ignore: { Instance } = { character, body :: Model }
				local visuals = workspace:FindFirstChild("LocalVisuals")
				if visuals then
					table.insert(ignore, visuals)
				end
				visible = MapQuery.throwRaycast(origin, to, ignore) == nil
			end
			table.insert(candidates, {
				angle = angle,
				distance = distance,
				visible = visible,
				shielded = visible and shielded(other, root.Position),
			})
			table.insert(points, point)
		end
	end
	local index = AimRules.pick(candidates, CombatConfig)
	if not index then
		return nil, 0
	end
	return points[index], AimRules.closeness(candidates[index].angle, CombatConfig)
end

-- The shortest turn from angle `from` to `to` (radians), between -pi and pi.
local function turnTo(from: number, to: number): number
	return (to - from + math.pi) % (2 * math.pi) - math.pi
end

local function ownStep(dt: number)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not camera or not root then
		return
	end
	local settings = Settings.get()
	local delta = UserInputService:GetMouseDelta()
	local speed = mouseSpeed()
	local turn = stick() * Look.gamepadSpeed * settings.gamepadSensitivity * dt
	local swipe = touchDelta * Look.touchSpeed * settings.touchSensitivity
	touchDelta = Vector2.zero
	-- the aim help: near a rival the player's own turning slows down and the camera is drawn gently to them
	local device = AimRules.device(Settings.inputKind(), CombatConfig)
	local target, closeness = assistTarget(camera, character :: Model)
	local slow = AimRules.friction(closeness, device)
	yaw -= (delta.X * speed + turn.X + swipe.X) * slow
	pitch = math.clamp(pitch - (delta.Y * speed - turn.Y + swipe.Y) * slow, Look.pitchMin, Look.pitchMax)
	if target then
		local to = (target - camera.CFrame.Position).Unit
		local share = AimRules.pull(closeness, dt, device)
		yaw += turnTo(yaw, math.atan2(-to.X, -to.Z)) * share
		pitch = math.clamp(pitch + (math.asin(math.clamp(to.Y, -1, 1)) - pitch) * share, Look.pitchMin, Look.pitchMax)
	end

	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local pivot = root.Position + Vector3.new(0, Look.pivotUp, 0)
	local offset = rotation:VectorToWorldSpace(Vector3.new(Look.shoulder, Look.up, Look.distance + stepZoom(dt)))
	camera.CFrame = CFrame.new(pivot + unblocked(pivot, offset, character :: Model)) * rotation
	camera.Focus = CFrame.new(pivot)
	face(character :: Model, rotation.LookVector)
end

function CombatCamera.start()
	if active then
		return
	end
	active = true
	local camera = workspace.CurrentCamera
	touchDelta = Vector2.zero
	if camera then
		local look = camera.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
		pitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), Look.pitchMin, Look.pitchMax)
		camera.CameraType = Enum.CameraType.Scriptable
	end
	-- Roblox's camera does nothing while the camera is Scriptable, so this takes its place in the frame
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value, ownStep)
end

-- Gives the camera to Roblox's own camera, following the current character. Nothing saved earlier is restored: after
-- a respawn the old camera state still points at the old character (in the sea, or gone).
local function handBack()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and camera.CameraSubject ~= humanoid then
		camera.CameraSubject = humanoid
	end
end

function CombatCamera.stop()
	if not active then
		return
	end
	active = false
	RunService:UnbindFromRenderStep(STEP)
	releaseFacing()
	zoom, zoomTarget = 0, 0 -- never left pulled back for the next combat mode
	-- Roblox's camera carries on from the current look direction
	handBack()
end

-- A finger dragging over the screen turns the camera in combat mode; a touch that started on a button or the move
-- stick (processed by the game) does not.
UserInputService.InputChanged:Connect(function(input, processed)
	if active and not processed and input.UserInputType == Enum.UserInputType.Touch then
		touchDelta += Vector2.new(input.Delta.X, input.Delta.Y)
	end
end)

-- A new character: outside combat mode the camera follows it. Combat mode is already over (CombatController ends it
-- on every respawn); this also catches a camera Roblox left on the old character.
function CombatCamera.follow()
	if not active then
		handBack()
	end
end

-- A throw is being aimed (charged) or not: the camera eases back by aimZoom, or returns. Ignored outside combat mode.
function CombatCamera.setAiming(on: boolean)
	zoomTarget = if on and active and Settings.effective().motionEffects then Look.aimZoom else 0
end

return CombatCamera
