-- How moving looks and feels. One controller for all of it; it changes no speed, jump power, dash distance or
-- other gameplay value (the sprint speed is set by the server), and adds no second animation system:
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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Dash = require(Shared:WaitForChild("Dash"))
local Movement = require(Config:WaitForChild("Movement"))
local Palette = require(Config:WaitForChild("Palette"))
local EconomyConfig = require(Config:WaitForChild("Economy"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))
local Sfx = require(client:WaitForChild("Sfx"))

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
local sprintFov = 0 -- extra field of view while the local player sprints

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
			-- measured against the normal walking speed, so a sprint leans further than a walk
			local speedShare = math.clamp(flat.Magnitude / EconomyConfig.baseWalkSpeed, 0, 1.5)
			local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

			-- forward lean with speed, roll into turns from how fast the facing rotates
			local targetPitch = if grounded
				then -Movement.leanForward * math.min(speedShare, Movement.sprintLean)
				else 0
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

-- Streaks behind both hands and feet for the length of the dash (from the DashSystem model).
local function limbTrails(character: Model, duration: number)
	for _, names in
		{
			{ "LeftHand", "Left Arm" },
			{ "RightHand", "Right Arm" },
			{ "LeftFoot", "Left Leg" },
			{
				"RightFoot",
				"Right Leg",
			},
		}
	do
		local limb = character:FindFirstChild(names[1]) or character:FindFirstChild(names[2])
		if limb and limb:IsA("BasePart") then
			local half = limb.Size.Y * 0.4
			local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
			top.Position, bottom.Position = Vector3.new(0, half, 0), Vector3.new(0, -half, 0)
			top.Parent, bottom.Parent = limb, limb
			local trail = Instance.new("Trail")
			trail.Name = "DashLimbTrail"
			trail.Attachment0, trail.Attachment1 = top, bottom
			trail.Lifetime = Movement.dashLimbTrailLifetime
			trail.FaceCamera = true
			trail.WidthScale = NumberSequence.new(0.12, 0.02)
			trail.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(0.5, 0.75),
				NumberSequenceKeypoint.new(1, 1),
			})
			trail.Parent = limb
			task.delay(duration, function()
				trail.Enabled = false
			end)
			task.delay(duration + trail.Lifetime + 0.05, function()
				trail:Destroy()
				top:Destroy()
				bottom:Destroy()
			end)
		end
	end
end

-- A white, fading copy of the body where it is right now (from the DashSystem model). Only parts and decals are
-- kept: no scripts, humanoid, sounds, effects or constraints, all anchored and out of every query.
local function afterimage(character: Model)
	if not character.Parent then
		return
	end
	local archivable = character.Archivable
	character.Archivable = true
	local ok, ghost = pcall(function()
		return character:Clone()
	end)
	character.Archivable = archivable
	if not ok or not ghost then
		return
	end
	ghost.Name = "DashAfterimage"
	local fade = TweenInfo.new(Movement.dashAfterimageFade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, item in ghost:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.CastShadow = false
			item.Color = Color3.new(1, 1, 1)
			item.Transparency = 1 - (1 - item.Transparency) * (1 - Movement.dashAfterimageTransparency)
			TweenService:Create(item, fade, { Transparency = 1 }):Play()
		elseif item:IsA("Decal") then
			TweenService:Create(item, fade, { Transparency = 1 }):Play()
		elseif not item:IsA("DataModelMesh") and not item:IsA("Accessory") and not item:IsA("JointInstance") then
			item:Destroy()
		end
	end
	ghost.Parent = TowerVisual.root()
	task.delay(Movement.dashAfterimageFade + 0.05, function()
		ghost:Destroy()
	end)
end

local function dashAssets(): Instance?
	return ReplicatedStorage:FindFirstChild("DashAssets")
end

-- The model's particle burst, turned towards the dash, if its assets were imported. Returns nothing either way.
local function dashParticles(root: BasePart, kind: Dash.Kind)
	local assets = dashAssets()
	local template = assets and assets:FindFirstChild("DashVfx")
	if not template or not template:IsA("BasePart") then
		return
	end
	local yaw = if kind == "back" then 180 elseif kind == "right" then 90 elseif kind == "left" then 270 else 0
	local effect = template:Clone()
	effect.Anchored = true
	effect.CanCollide = false
	effect.CanTouch = false
	effect.CanQuery = false
	effect.CFrame = root.CFrame * CFrame.Angles(0, math.rad(yaw), 0)
	effect.Parent = TowerVisual.root()
	for _, item in effect:GetDescendants() do
		if item:IsA("ParticleEmitter") then
			item.Enabled = false
			item:Emit(math.clamp(math.floor(item.Rate * 0.12), 4, 22))
		end
	end
	task.delay(2, function()
		effect:Destroy()
	end)
end

-- The model's dash sound at the character, heard by everyone nearby; false when its assets are not imported.
local function dashSound(root: BasePart, kind: Dash.Kind): boolean
	local assets = dashAssets()
	local sounds = assets and assets:FindFirstChild("Sounds")
	local source = sounds and sounds:FindFirstChild(if kind == "back" then "BackDash" else "FrontDash")
	if not source or not source:IsA("Sound") then
		return false
	end
	local sound = source:Clone()
	sound.Parent = root
	sound:Play()
	task.delay(4, function()
		sound:Destroy()
	end)
	return true
end

-- The local character's dash animation from Config/Movement, if one is set for this direction. Animations played
-- by the owner replicate to everyone, so other characters are left alone here.
local dashTracks: { [string]: AnimationTrack } = {}
local dashTracksOf: Humanoid? = nil
local nextForward = 1
local function playDashAnimation(character: Model, kind: Dash.Kind)
	local key: string = kind
	if kind == "forward" then
		key = "forward" .. nextForward
		nextForward = 3 - nextForward
	end
	local id = Movement.dashAnimations[key]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not id or id == "" or not humanoid or not animator then
		return
	end
	if dashTracksOf ~= humanoid then
		dashTracksOf = humanoid
		table.clear(dashTracks)
	end
	local track = dashTracks[key]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok then
			return
		end
		track = loaded
		track.Looped = false
		track.Priority = Enum.AnimationPriority.Action
		dashTracks[key] = track
	end
	track:Play(0.04)
end

-- A granted dash on any character, going (dirX, dirZ): trails, afterimages and the model's particles and sound for
-- everyone; the FOV kick, the animation and (without the model's sound) the game's own dash sound for the local
-- player.
function MovementController.dash(character: Model, duration: number, dirX: number, dirZ: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local look = root.CFrame.LookVector
	local kind = Dash.kind(dirX, dirZ, look.X, look.Z)
	limbTrails(character, duration)
	dashParticles(root, kind)
	local count = math.max(1, Movement.dashAfterimages)
	for index = 0, count - 1 do
		task.delay(duration * index / count, afterimage, character)
	end
	local soundPlayed = dashSound(root, kind)
	if character == player.Character then
		playDashAnimation(character, kind)
		if not soundPlayed then
			Sfx.play("dash")
		end
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
		camera.FieldOfView = (baseFov :: number) + sprintFov + Movement.dashFovKick
		fovTween = TweenService:Create(
			camera,
			TweenInfo.new(Movement.dashFovTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = (baseFov :: number) + sprintFov }
		)
		fovTween:Play()
	end
end

-- Local player only: a slightly wider view while sprinting. The speed itself is the server's (TowerService).
function MovementController.setSprinting(on: boolean)
	local camera = workspace.CurrentCamera
	baseFov = baseFov or camera.FieldOfView
	sprintFov = if on then Movement.sprintFov else 0
	if fovTween then
		fovTween:Cancel()
	end
	fovTween = TweenService:Create(
		camera,
		TweenInfo.new(Movement.sprintFovTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = (baseFov :: number) + sprintFov }
	)
	fovTween:Play()
end

function MovementController.Start()
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	RunService:BindToRenderStep("WobbleMovementPose", Enum.RenderPriority.Character.Value + 2, onRenderStep)
end

return MovementController
