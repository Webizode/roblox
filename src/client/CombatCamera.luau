-- The camera in combat mode: over the right shoulder, so the character stands left of the screen centre and the
-- crosshair looks past it into the world. With a mouse or gamepad it is our own camera (the mouse, held in the
-- centre, or the right stick turn it directly; walls pull it in), because Roblox's default camera only turns with
-- the mouse under its own shift lock or a held right button. Touch screens keep Roblox's camera (dragging turns
-- it) and only shift it over the shoulder. Either way the character faces where the camera looks, like under shift
-- lock: it turns with the camera, A/D strafe and the throw always goes forward. Leaving hands the camera back to
-- Roblox, looking the same way, and lets the character turn to its walking direction again. While a throw is aimed
-- (setAiming) it eases back by aimZoom and returns afterwards; leaving combat mode always ends that.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Combat"))
local Look = CombatConfig.camera

local CombatCamera = {}

local STEP = "WobbleCombatCamera"
local STICK_DEAD_ZONE = 0.15
local WALL_MARGIN = 0.4
local WALL_TRIES = 6 -- non-colliding parts a camera ray may pass before it gives up
local MIN_DISTANCE = 0.5 -- studs from the pivot the camera keeps even right against a wall

local player = Players.LocalPlayer
local active = false
local own = false -- our own camera (mouse or gamepad) instead of Roblox's shifted one
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

local function mouseSpeed(): number
	local ok, sensitivity = pcall(function()
		return UserSettings():GetService("UserGameSettings").MouseSensitivity
	end)
	return Look.mouseSpeed * (if ok and type(sensitivity) == "number" then sensitivity else 1)
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
-- plane. Parts without collision (garlands, decoration layers) are looked through.
local function unblocked(pivot: Vector3, offset: Vector3, character: Model): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skipped: { Instance } = { character }
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

local function ownStep(dt: number)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not camera or not root then
		return
	end
	local delta = UserInputService:GetMouseDelta()
	local speed = mouseSpeed()
	local turn = stick()
	yaw -= delta.X * speed + turn.X * Look.gamepadSpeed * dt
	pitch = math.clamp(pitch - delta.Y * speed + turn.Y * Look.gamepadSpeed * dt, Look.pitchMin, Look.pitchMax)

	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local pivot = root.Position + Vector3.new(0, Look.pivotUp, 0)
	local offset = rotation:VectorToWorldSpace(Vector3.new(Look.shoulder, Look.up, Look.distance + stepZoom(dt)))
	camera.CFrame = CFrame.new(pivot + unblocked(pivot, offset, character :: Model)) * rotation
	camera.Focus = CFrame.new(pivot)
	face(character :: Model, rotation.LookVector)
end

-- Touch: Roblox's camera keeps turning and zooming; this runs after it and only slides it over the shoulder. Roblox
-- keeps its own camera out of walls, but not the slide, so the shifted camera is pulled in like ours.
local function shiftStep(dt: number)
	local camera = workspace.CurrentCamera
	local character = player.Character
	if camera then
		local shifted = camera.CFrame * CFrame.new(Look.shoulder, Look.up, stepZoom(dt))
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character and root then
			local pivot = root.Position + Vector3.new(0, Look.pivotUp, 0)
			local offset = unblocked(pivot, shifted.Position - pivot, character)
			shifted = shifted.Rotation + pivot + offset
		end
		camera.CFrame = shifted
		if character then
			face(character, camera.CFrame.LookVector)
		end
	end
end

function CombatCamera.start()
	if active then
		return
	end
	active = true
	local camera = workspace.CurrentCamera
	own = UserInputService.MouseEnabled or UserInputService.GamepadEnabled
	if own and camera then
		local look = camera.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
		pitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), Look.pitchMin, Look.pitchMax)
		camera.CameraType = Enum.CameraType.Scriptable
		-- Roblox's camera does nothing while the camera is Scriptable, so this takes its place in the frame
		RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value, ownStep)
	else
		own = false
		RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value + 1, shiftStep)
	end
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

-- A new character: outside combat mode the camera follows it. Combat mode is already over (CombatController ends it
-- on every respawn); this also catches a camera Roblox left on the old character.
function CombatCamera.follow()
	if not active then
		handBack()
	end
end

-- A throw is being aimed (charged) or not: the camera eases back by aimZoom, or returns. Ignored outside combat mode.
function CombatCamera.setAiming(on: boolean)
	zoomTarget = if on and active then Look.aimZoom else 0
end

return CombatCamera
