-- How moving looks and feels. One controller for all of it; it changes no speed, jump power, dash distance or
-- other gameplay value (the sprint speed is set by the server), and adds no second animation system:
--   * animation ids from Config/Movement go into Roblox's own Animate script (empty ids keep the defaults),
--   * a procedural layer on the root joint (R15 or R6, Motor6D or the AnimationConstraint of newer avatars) leans
--     every character into runs and turns, plays a stumble on a hit and a fall/get-up pose for a knockdown (every
--     client draws it for every character from replicated velocity and the server's hit events, so all players see
--     the same thing),
--   * small local effects: dust and a little camera shake on landing, a FOV kick and trail on a dash, camera
--     shake on hits,
--   * combat movement while the CombatMode attribute is on: the local character's combat walk, idle and sprint over
--     Animate (Config/Movement combat), the walk in reverse for walking backwards, the hips of every character
--     turning into a sideways walk while the upper body keeps facing the aim, and a stronger forward lean. All of it
--     ends with combat mode.
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
local Settings = require(client:WaitForChild("Settings"))

local MovementController = {}

-- A Motor6D or an AnimationConstraint: both place Part1 from Part0 through a joint frame (C0, or Attachment0) and
-- the Transform the Animator writes.
type Joint = Motor6D | AnimationConstraint

type Pose = {
	joint: Joint,
	waist: Joint?, -- R15 only: turned back against the hips, so the upper body keeps facing the aim
	offset: CFrame, -- lean, stumble and knockdown in the root part's axes, laid over the animation every frame
	hip: number, -- combat mode: the hips turned towards a sideways walk (radians, left +)
	dashPitch: number, -- the lean of the last dash (radians), faded in and out around dashStart..dashUntil
	dashRoll: number,
	dashStart: number,
	dashUntil: number,
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
local fovTween: Tween? = nil
local sprintFov = 0 -- extra field of view while the local player sprints

-- The joint between the HumanoidRootPart and the body: R15's LowerTorso.Root or R6's HumanoidRootPart.RootJoint, as
-- a Motor6D or as the AnimationConstraint of newer avatars.
local function rootJoint(character: Model): Joint?
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local root = character:FindFirstChild("HumanoidRootPart")
	local joint = (lowerTorso and lowerTorso:FindFirstChild("Root")) or (root and root:FindFirstChild("RootJoint"))
	if joint and joint:IsA("Motor6D") then
		return joint
	elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 then
		return joint
	end
	return nil
end

local function waistJoint(character: Model): Joint?
	local upperTorso = character:FindFirstChild("UpperTorso")
	local joint = upperTorso and upperTorso:FindFirstChild("Waist")
	if joint and joint:IsA("Motor6D") then
		return joint
	elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 then
		return joint
	end
	return nil
end

local function poseFor(character: Model): Pose?
	local pose = poses[character]
	if pose then
		return pose
	end
	local joint = rootJoint(character)
	if not joint then
		return nil -- no known root joint (or not loaded yet): no procedural layer, nothing breaks
	end
	pose = {
		joint = joint,
		waist = waistJoint(character),
		offset = CFrame.identity,
		hip = 0,
		dashPitch = 0,
		dashRoll = 0,
		dashStart = -math.huge,
		dashUntil = -math.huge,
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

-- Whether an animation id loads for this experience, checked once per id: Roblox only plays animations the
-- experience may use, and one that never arrives would leave the character stiff instead of Roblox's default.
local loads: { [string]: boolean } = {}
local LOAD_WAIT = 5 -- seconds

local function canLoad(animator: Animator, id: string): boolean
	if loads[id] ~= nil then
		return loads[id]
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	local waited = 0
	while ok and track.Length == 0 and waited < LOAD_WAIT do
		waited += task.wait(0.1)
	end
	loads[id] = ok and track.Length > 0
	if ok then
		track:Destroy()
	end
	if not loads[id] then
		warn(`[Movement] animation {id} does not load for this experience (no permission?); Roblox's default stays`)
	end
	return loads[id]
end

-- Puts configured animation ids into Roblox's Animate script; it reloads a set when one of its animations changes.
-- An id that does not load is left out, so that set keeps Roblox's default.
local function applyAnimations(character: Model)
	local animate = character:WaitForChild("Animate", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not animate or not animator or not animator:IsA("Animator") then
		return
	end
	for setName, entries in Movement.animations do
		for animationName, id in entries do
			if id ~= "" and canLoad(animator, id) then
				local set = animate:WaitForChild(setName, 5)
				local animation = set and set:FindFirstChild(animationName)
				if animation and animation:IsA("Animation") then
					animation.AnimationId = id
				end
			end
		end
	end
end

-- Combat movement of the local character (Config/Movement combat): its own walk, idle and sprint over Roblox's
-- Animate while the CombatMode attribute is on and it stands on the ground. Animations the owner plays replicate to
-- everyone, so only the local character gets them. Anything else (combat mode off, in the air, dead) fades them
-- out and Animate's own animations show again; an animation that does not load leaves that state to Animate too.
local Combat = Movement.combat

type CombatTracks = {
	humanoid: Humanoid,
	walk: AnimationTrack?,
	idle: AnimationTrack?,
	sprint: AnimationTrack?,
	current: AnimationTrack?,
}

local combatTracks: CombatTracks? = nil
local sprintingNow = false -- the local player's sprint, from setSprinting
local MAX_PLAY_SPEED = 2 -- a dash would otherwise spin the walk cycle

local function loadCombatTracks(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not animator or not animator:IsA("Animator") then
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return -- the combat animations are made for R15; R6 keeps Animate's
	end
	local function load(id: string): AnimationTrack?
		if id == "" or not canLoad(animator, id) then
			return nil
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Movement -- over Animate, under the throw (Action)
		track.Looped = true
		return track
	end
	local tracks = {
		humanoid = humanoid,
		walk = load(Combat.walk),
		idle = load(Combat.idle),
		sprint = load(Combat.sprint),
		current = nil,
	}
	if character == player.Character then
		combatTracks = tracks
	end
end

local function stepCombatTracks()
	local tracks = combatTracks
	if not tracks then
		return
	end
	local humanoid = tracks.humanoid
	local character = humanoid.Parent
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	local active = root ~= nil
		and character == player.Character
		and player:GetAttribute("CombatMode") == true
		and humanoid.Health > 0
		and not airborne
	local want: AnimationTrack? = nil
	local speed = 1
	local moving = false
	if active and root then
		local velocity = root.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		moving = flat.Magnitude > Combat.moveThreshold
		if moving then
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			local backwards = look.Magnitude > 1e-3 and flat.Unit:Dot(look.Unit) < -0.25
			if sprintingNow and tracks.sprint then
				want = tracks.sprint
				speed = flat.Magnitude / (Combat.walkSpeedAt * EconomyConfig.sprintMultiplier)
			else
				want = tracks.walk
				speed = flat.Magnitude / Combat.walkSpeedAt * (if sprintingNow then Combat.sprintPlaySpeed else 1)
			end
			speed = math.min(speed, MAX_PLAY_SPEED) * (if backwards then -1 else 1)
		else
			want = tracks.idle -- nil without a combat idle: Animate's idle shows
		end
	end
	if want ~= tracks.current then
		local fade = if active and not moving then Combat.stopFade else Combat.fade
		if tracks.current then
			tracks.current:Stop(fade)
		end
		if want then
			want:Play(fade)
		end
		tracks.current = want
	end
	if want then
		want:AdjustSpeed(speed)
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

-- The camera's field of view: the setting, widened while sprinting if the motion effects are on.
local function fovTarget(): number
	local effects = Settings.effective()
	return effects.fov + (if effects.motionEffects then sprintFov else 0)
end

local function startShake(degrees: number)
	if not Settings.effective().cameraShake then
		return -- switched off in the settings
	end
	local running = os.clock() < shakeUntil
	shake(degrees)
	if not running then
		RunService:BindToRenderStep(SHAKE_STEP, Enum.RenderPriority.Camera.Value + 1, onShakeStep)
	end
end

local function dust(position: Vector3, amount: number)
	-- fewer puffs at a lower VFX quality, none at all below one
	local puffs = math.floor(Movement.dustPuffs * amount * Settings.effective().particleScale + 0.5)
	for index = 1, puffs do
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
	combatTracks = nil -- the old character's tracks went with it
	task.spawn(applyAnimations, character)
	task.spawn(loadCombatTracks, character)
	task.spawn(watchLanding, character)
end

-- How far the hips turn towards a walk that goes sideways in combat mode (left +): along the walk for forwards and
-- sideways, mirrored for backwards (the legs then walk backwards), at most hipTurn either way.
local function hipTarget(root: BasePart, flat: Vector3): number
	local direction = root.CFrame:VectorToObjectSpace(flat.Unit)
	local x, z = direction.X, direction.Z
	if z > 0.25 then
		x, z = -x, -z
	end
	return math.clamp(-math.atan2(x, -z), -Combat.hipTurn, Combat.hipTurn)
end

-- The procedural layer for every character: lean into runs and turns, stumble, knockdown pose, and in combat mode
-- the hips turning into a sideways walk.
local function onRenderStep(dt: number)
	stepCombatTracks()
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
			local combat = other:GetAttribute("CombatMode") == true and humanoid.Health > 0

			-- hips into a sideways walk; back to straight when standing, in the air or out of combat mode
			local hipGoal = if combat
					and grounded
					and pose.waist
					and flat.Magnitude > Combat.moveThreshold
				then hipTarget(root, flat)
				else 0
			pose.hip += (hipGoal - pose.hip) * (1 - math.exp(-Combat.hipResponse * dt))

			-- forward lean with speed, roll into turns from how fast the facing rotates
			local targetPitch = if grounded
				then -Movement.leanForward * math.min(speedShare, Movement.sprintLean) * (if combat
					then Combat.leanBoost
					else 1)
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

			-- the dash lean: in quickly, held for the burst, out after it
			local clock = os.clock()
			local dashWeight = if clock < pose.dashStart
				then 0
				elseif clock < pose.dashUntil then math.min(1, (clock - pose.dashStart) / Movement.dashLeanIn)
				else math.max(0, 1 - (clock - pose.dashUntil) / Movement.dashLeanOut)
			dashWeight = TweenService:GetValue(dashWeight, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

			pose.offset = CFrame.new(0, -Movement.knockdownDrop * fall, 0)
				* CFrame.Angles(0, pose.hip, 0)
				* CFrame.Angles(
					pose.pitch + pose.stumblePitch + Movement.knockdownAngle * fall + pose.dashPitch * dashWeight,
					0,
					pose.roll + pose.stumbleRoll + pose.dashRoll * dashWeight
				)
		end
	end
	for character in poses do
		if not character.Parent then
			poses[character] = nil
		end
	end
end

-- The joint frame on Part0's side: C0 of a Motor6D, Attachment0 of an AnimationConstraint.
local function frameOf(joint: Joint): CFrame
	if joint:IsA("Motor6D") then
		return joint.C0
	end
	local attachment = (joint :: AnimationConstraint).Attachment0
	return if attachment then attachment.CFrame else CFrame.identity
end

-- Right after the Animator each frame (PreSimulation): the offset, given in the root part's axes, goes on top of the
-- animation's Transform. R6's root joint frame is turned against the root part, R15's is not; both lean the same.
local function onPoseStep()
	for _, pose in poses do
		if pose.offset ~= CFrame.identity then
			local frame = frameOf(pose.joint).Rotation
			pose.joint.Transform = frame:Inverse() * pose.offset * frame * pose.joint.Transform
		end
		-- the upper body turns back against the hips, so it keeps facing the aim
		local waist = pose.waist
		if waist and math.abs(pose.hip) > 1e-4 then
			local frame = frameOf(waist).Rotation
			waist.Transform = frame:Inverse() * CFrame.Angles(0, -pose.hip, 0) * frame * waist.Transform
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

-- The model's particle burst, turned towards the dash's actual direction (diagonals included; 0 ahead, 90 to the
-- right as in the model), if its assets were imported. Returns nothing either way.
local function dashParticles(root: BasePart, dirX: number, dirZ: number)
	local assets = dashAssets()
	local template = assets and assets:FindFirstChild("DashVfx")
	if not template or not template:IsA("BasePart") then
		return
	end
	local relative = root.CFrame:VectorToObjectSpace(Vector3.new(dirX, 0, dirZ))
	local yaw = math.atan2(relative.X, -relative.Z)
	local effect = template:Clone()
	effect.Anchored = true
	effect.CanCollide = false
	effect.CanTouch = false
	effect.CanQuery = false
	effect.CFrame = root.CFrame * CFrame.Angles(0, yaw, 0)
	effect.Parent = TowerVisual.root()
	for _, item in effect:GetDescendants() do
		if item:IsA("ParticleEmitter") then
			item.Enabled = false
			local count = math.clamp(math.floor(item.Rate * 0.12), 4, 22)
			item:Emit(math.max(1, math.floor(count * Settings.effective().particleScale + 0.5)))
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
	sound.SoundGroup = Sfx.effectsGroup()
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

-- The floor under a point (the character excluded), or nil over a gap.
local function floorBelow(character: Model, position: Vector3): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, TowerVisual.root() }
	params.RespectCanCollide = true
	return workspace:Raycast(position, Vector3.new(0, -8, 0), params)
end

-- A thin bright streak on the floor along the dash, from where it starts to where it will end, fading out; and a
-- puff of dust at both ends. The streak runs the actual direction, diagonals included; over a gap there is none.
local function groundStreak(character: Model, root: BasePart, dirX: number, dirZ: number, distance: number)
	local floor = floorBelow(character, root.Position)
	if not floor then
		return
	end
	local look = Movement.dashStreak
	local direction = Vector3.new(dirX, 0, dirZ)
	local start = floor.Position + Vector3.new(0, 0.04, 0)
	local streak = Instance.new("Part")
	streak.Name = "DashStreak"
	streak.Anchored = true
	streak.CanCollide = false
	streak.CanQuery = false
	streak.CanTouch = false
	streak.CastShadow = false
	streak.Material = Enum.Material.Neon
	streak.Color = Color3.fromHex(Palette.vanilla)
	streak.Transparency = look.transparency
	streak.Size = Vector3.new(look.width, 0.05, distance)
	streak.CFrame = CFrame.lookAt(start + direction * distance / 2, start + direction * distance)
	streak.Parent = TowerVisual.root()
	TweenService:Create(streak, TweenInfo.new(look.fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(look.width * 0.3, 0.05, distance),
	}):Play()
	task.delay(look.fade + 0.05, function()
		streak:Destroy()
	end)
	dust(start, 0.5)
end

-- A granted dash on any character, going (dirX, dirZ) for `distance` studs: the body leaning into it, trails,
-- afterimages, a streak on the floor, dust and the model's particles and sound for everyone; the FOV kick, the
-- animation and (without the model's sound) the game's own dash sound for the local player.
function MovementController.dash(character: Model, duration: number, dirX: number, dirZ: number, distance: number?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local look = root.CFrame.LookVector
	local kind = Dash.kind(dirX, dirZ, look.X, look.Z)
	-- lean into the actual direction: forward or back tips the body, sideways rolls it, diagonals mix both
	local pose = poseFor(character)
	if pose then
		local relative = root.CFrame:VectorToObjectSpace(Vector3.new(dirX, 0, dirZ))
		pose.dashPitch = relative.Z * Movement.dashLean -- ahead is -Z; a forward lean is a negative pitch
		pose.dashRoll = -relative.X * Movement.dashLean
		pose.dashStart = os.clock()
		pose.dashUntil = os.clock() + duration
	end
	local effects = Settings.effective()
	if effects.heavyDashEffects then
		limbTrails(character, duration)
	end
	dashParticles(root, dirX, dirZ)
	groundStreak(character, root, dirX, dirZ, distance or 10)
	task.delay(duration, function()
		local floor = root.Parent and floorBelow(character, root.Position)
		if floor then
			dust(floor.Position + Vector3.new(0, 0.1, 0), 0.4)
		end
	end)
	if effects.heavyDashEffects then
		local count = math.max(1, Movement.dashAfterimages)
		for index = 0, count - 1 do
			task.delay(duration * index / count, afterimage, character)
		end
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

	if character == player.Character and Settings.effective().motionEffects then
		local camera = workspace.CurrentCamera
		if fovTween then
			fovTween:Cancel()
		end
		camera.FieldOfView = fovTarget() + Movement.dashFovKick
		fovTween = TweenService:Create(
			camera,
			TweenInfo.new(Movement.dashFovTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = fovTarget() }
		)
		fovTween:Play()
	end
end

-- Local player only: a slightly wider view while sprinting. The speed itself is the server's (TowerService).
function MovementController.setSprinting(on: boolean)
	sprintingNow = on -- the combat sprint animation follows it
	local camera = workspace.CurrentCamera
	sprintFov = if on then Movement.sprintFov else 0
	if fovTween then
		fovTween:Cancel()
	end
	fovTween = TweenService:Create(
		camera,
		TweenInfo.new(Movement.sprintFovTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = fovTarget() }
	)
	fovTween:Play()
end

-- Local player: whether they sprint, and os.clock of their last dash start (-math.huge before any), for the
-- crosshair's spread (AimHud).
function MovementController.isSprinting(): boolean
	return sprintingNow
end

function MovementController.lastDash(): number
	local character = Players.LocalPlayer.Character
	local pose = character and poseFor(character)
	return if pose then pose.dashStart else -math.huge
end

function MovementController.Start()
	-- a changed FOV setting (or motion effects switched off) shows at once
	Settings.onChanged(function()
		if fovTween then
			fovTween:Cancel()
		end
		workspace.CurrentCamera.FieldOfView = fovTarget()
	end)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	-- the pose follows the frame here; it lands on the joints after the Animator, in onPoseStep
	RunService:BindToRenderStep("WobbleMovementPose", Enum.RenderPriority.Character.Value + 2, onRenderStep)
	RunService.PreSimulation:Connect(onPoseStep)
end

return MovementController
