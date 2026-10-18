-- How moving looks and feels. One controller for all of it; it changes no speed, jump power, dash distance or
-- other gameplay value, and adds no second animation system:
--   * animation ids from Config/Movement go into Roblox's own Animate script (empty ids keep the defaults),
--   * a procedural layer on the R15 root joint leans every character into runs and turns, plays a stumble on a
--     hit and a fall/get-up pose for a knockdown (every client draws it for every character from replicated
--     velocity and the server's hit events, so all players see the same thing),
--   * small local effects: dust and a little camera shake on landing, a FOV kick and trail on a dash, camera
--     shake on hits.
-- The tower hangs off the HumanoidRootPart, which this never moves, so balance and catching are untouched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Movement = require(Config:WaitForChild("Movement"))
local Palette = require(Config:WaitForChild("Palette"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))

local MovementController = {}

type Pose = {
	joint: Motor6D,
	baseC0: CFrame,
	pitch: number,
	roll: number,
	stumblePitch: number,
	stumbleRoll: number,
	down: number,
	downTarget: number,
	lastLook: Vector3,
}

local SHAKE_STEP = "WobbleCameraShake"

local player = Players.LocalPlayer
local poses: { [Model]: Pose } = {}
local shakeUntil = 0
local shakeStrength = 0
local baseFov: number? = nil
local fovTween: Tween? = nil

local function rootJoint(character: Model): Motor6D?
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local joint = lowerTorso and lowerTorso:FindFirstChild("Root")
	return if joint and joint:IsA("Motor6D") then joint else nil
end

local function poseFor(character: Model): Pose?
	local pose = poses[character]
	if pose then
		return pose
	end
	local joint = rootJoint(character)
	if not joint then
		return nil -- not R15 (or not loaded yet): no procedural layer, nothing breaks
	end
	pose = {
		joint = joint,
		baseC0 = joint.C0,
		pitch = 0,
		roll = 0,
		stumblePitch = 0,
		stumbleRoll = 0,
		down = 0,
		downTarget = 0,
		lastLook = Vector3.zAxis,
	}
	poses[character] = pose
	return pose
end

-- Puts configured animation ids into Roblox's Animate script; it reloads a set when one of its animations changes.
local function applyAnimations(character: Model)
	local animate = character:WaitForChild("Animate", 10)
	if not animate then
		return
	end
	for setName, entries in Movement.animations do
		for animationName, id in entries do
			if id ~= "" then
				local set = animate:WaitForChild(setName, 5)
				local animation = set and set:FindFirstChild(animationName)
				if animation and animation:IsA("Animation") then
					animation.AnimationId = id
				end
			end
		end
	end
end

local function shake(degrees: number)
	shakeStrength = math.max(if os.clock() < shakeUntil then shakeStrength else 0, degrees)
	shakeUntil = os.clock() + Movement.shakeTime
end

-- Runs after the camera script while a shake lasts, then unbinds itself.
local function onShakeStep()
	local left = shakeUntil - os.clock()
	if left <= 0 then
		RunService:UnbindFromRenderStep(SHAKE_STEP)
		return
	end
	local amount = math.rad(shakeStrength) * (left / Movement.shakeTime)
	local t = os.clock() * 40
	local camera = workspace.CurrentCamera
	camera.CFrame *= CFrame.Angles(math.sin(t) * amount, math.cos(t * 1.3) * amount, 0)
end

local function startShake(degrees: number)
	local running = os.clock() < shakeUntil
	shake(degrees)
	if not running then
		RunService:BindToRenderStep(SHAKE_STEP, Enum.RenderPriority.Camera.Value + 1, onShakeStep)
	end
end

local function dust(position: Vector3, amount: number)
	for index = 1, math.max(1, math.floor(Movement.dustPuffs * amount + 0.5)) do
		local angle = index / Movement.dustPuffs * math.pi * 2
		local part = Instance.new("Part")
		part.Name = "Dust"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Shape = Enum.PartType.Ball
		part.Color = Color3.fromHex(Palette.vanilla)
		part.Transparency = 0.35
		part.Size = Vector3.new(0.8, 0.8, 0.8)
		part.Position = position
		part.Parent = TowerVisual.root()
		local out = Vector3.new(math.cos(angle), 0.25, math.sin(angle)) * (1.5 + 1.5 * amount)
		TweenService:Create(part, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = position + out,
			Size = Vector3.new(1.8, 1.8, 1.8),
			Transparency = 1,
		}):Play()
		task.delay(0.45, function()
			part:Destroy()
		end)
	end
end

-- Local character only: landing dust and shake scaled by the time in the air.
local function watchLanding(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	local airborneSince: number? = nil
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Freefall or new == Enum.HumanoidStateType.Jumping then
			airborneSince = airborneSince or os.clock()
		elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			local since = airborneSince
			airborneSince = nil
			if not since then
				return
			end
			local airTime = os.clock() - since
			if airTime < Movement.landMinAirTime then
				return
			end
			local amount = math.clamp(
				(airTime - Movement.landMinAirTime) / (Movement.landFullAirTime - Movement.landMinAirTime),
				0.3,
				1
			)
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				dust(root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 - 0.2, 0), amount)
			end
			startShake(Movement.landShake * amount)
		end
	end)
end

local function onCharacter(character: Model)
	task.spawn(applyAnimations, character)
	task.spawn(watchLanding, character)
end

-- The procedural layer for every character: lean into runs and turns, stumble, knockdown pose.
local function onRenderStep(dt: number)
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local pose = character and root and humanoid and poseFor(character)
		if pose and root and humanoid then
			local velocity = root.AssemblyLinearVelocity
			local flat = Vector3.new(velocity.X, 0, velocity.Z)
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			local speedShare = math.clamp(flat.Magnitude / math.max(humanoid.WalkSpeed, 1), 0, 1.5)
			local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

			-- forward lean with speed, roll into turns from how fast the facing rotates
			local targetPitch = if grounded then -Movement.leanForward * math.min(speedShare, 1) else 0
			local turnRate = 0
			if look.Magnitude > 1e-3 and pose.lastLook.Magnitude > 1e-3 and dt > 0 then
				local a, b = pose.lastLook.Unit, look.Unit
				turnRate = math.asin(math.clamp(a:Cross(b).Y, -1, 1)) / dt
			end
			pose.lastLook = look
			local targetRoll = if grounded
				then math.clamp(turnRate * 0.12, -1, 1) * Movement.leanTurn * math.min(speedShare, 1)
				else 0
			local follow = 1 - math.exp(-Movement.leanResponse * dt)
			pose.pitch += (targetPitch - pose.pitch) * follow
			pose.roll += (targetRoll - pose.roll) * follow

			local recover = math.exp(-Movement.stumbleRecover * dt)
			pose.stumblePitch *= recover
			pose.stumbleRoll *= recover

			local rate = if pose.downTarget > pose.down then dt / Movement.knockdownIn else dt / Movement.getUpTime
			pose.down = if pose.downTarget > pose.down
				then math.min(pose.downTarget, pose.down + rate)
				else math.max(pose.downTarget, pose.down - rate)
			local fall = TweenService:GetValue(pose.down, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

			pose.joint.C0 = pose.baseC0
				* CFrame.new(0, -Movement.knockdownDrop * fall, 0)
				* CFrame.Angles(
					pose.pitch + pose.stumblePitch + Movement.knockdownAngle * fall,
					0,
					pose.roll + pose.stumbleRoll
				)
		end
	end
	for character in poses do
		if not character.Parent then
			poses[character] = nil
		end
	end
end

-- A hit on any character: it stumbles away from the ball (dirX/dirZ, the ball's flight on the ground).
function MovementController.stumble(character: Model, dirX: number, dirZ: number, strength: number)
	local pose = poseFor(character)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not pose or not root then
		return
	end
	-- the ball's direction in the character's own frame: from the front tilts it back, from the side rolls it
	local localDir = root.CFrame:VectorToObjectSpace(Vector3.new(dirX, 0, dirZ))
	local amount = Movement.stumbleAngle * math.clamp(strength, 0, 1.5)
	pose.stumblePitch += localDir.Z * amount
	pose.stumbleRoll += -localDir.X * amount
	if character == player.Character then
		startShake(Movement.hitShake * strength)
	end
end

-- Knockdown pose on any character for `seconds`, then it gets up.
function MovementController.knockDown(character: Model, seconds: number)
	local pose = poseFor(character)
	if not pose then
		return
	end
	pose.downTarget = 1
	if character == player.Character then
		startShake(Movement.hitShake * 1.6)
	end
	task.delay(seconds, function()
		if poses[character] == pose then
			pose.downTarget = 0
		end
	end)
end

-- A granted dash: a trail on any character, the FOV kick only for the local player.
function MovementController.dash(character: Model, duration: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
	top.Position = Vector3.new(0, 1.2, 0)
	bottom.Position = Vector3.new(0, -1.2, 0)
	top.Parent, bottom.Parent = root, root
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = top, bottom
	trail.Lifetime = 0.22
	trail.Color = ColorSequence.new(Color3.fromHex(Palette.lemon))
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.LightEmission = 0.4
	trail.FaceCamera = true
	trail.Parent = root
	task.delay(duration, function()
		trail.Enabled = false
	end)
	task.delay(duration + trail.Lifetime + 0.05, function()
		trail:Destroy()
		top:Destroy()
		bottom:Destroy()
	end)

	if character == player.Character then
		local camera = workspace.CurrentCamera
		baseFov = baseFov or camera.FieldOfView
		if fovTween then
			fovTween:Cancel()
		end
		camera.FieldOfView = (baseFov :: number) + Movement.dashFovKick
		fovTween = TweenService:Create(
			camera,
			TweenInfo.new(Movement.dashFovTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = baseFov }
		)
		fovTween:Play()
	end
end

function MovementController.Start()
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	RunService:BindToRenderStep("WobbleMovementPose", Enum.RenderPriority.Character.Value + 2, onRenderStep)
end

return MovementController
