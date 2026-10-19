-- The throw animation: combat stance with the ball in the right hand, the wind-up while the throw button is held,
-- the explosive throw on release and the swing back into the stance. The ball leaves the hand releaseDelay after the
-- button-up (Config/Combat): the server starts it then, and the throw releases at that moment.
--   * With the three animation ids in Config/Combat (throwAnimation) the local player plays them; Roblox replicates
--     them to everyone. The charge animation holds at its "Held" marker, the throw has a "Release" marker at
--     releaseDelay (checked in the output while Features.debugThrow is on).
--   * While the ids are empty, a procedural pose stands in: the right shoulder, the right elbow and the waist of
--     every R15 character are turned by ThrowPose, drawn by every client from the CombatMode and Charging
--     attributes and the IceBallThrown event. It touches no joint MovementController uses (the root), so lean,
--     stumble and knockdown stay as they are, and nothing here moves the character, its speed or its tower.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ThrowPose = require(Shared:WaitForChild("ThrowPose"))
local CombatConfig = require(Config:WaitForChild("Combat"))
local Features = require(Config:WaitForChild("Features"))

local ThrowAnimator = {}

type Rig = {
	character: Model,
	joints: { Motor6D }, -- waist, shoulder, elbow
	base: { CFrame }, -- their C0 before any pose
	applied: boolean,
}

type Entry = {
	rig: Rig?,
	weight: number, -- 0 outside combat mode, 1 in it, blended
	chargeSince: number?, -- os.clock() the wind-up began
	throwAt: number?, -- os.clock() of the button-up
}

local STEP = "WobbleThrowPose"
local Animation = CombatConfig.throwAnimation
local USE_TRACKS = Animation.stance ~= "" and Animation.charge ~= "" and Animation.throw ~= ""

local localPlayer = Players.LocalPlayer
local entries: { [Player]: Entry } = {}
local reported: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local localReleaseAt = -math.huge

local function entryFor(player: Player): Entry
	local entry = entries[player]
	if not entry then
		entry = { rig = nil, weight = 0, chargeSince = nil, throwAt = nil }
		entries[player] = entry
	end
	return entry
end

local function joint(character: Model, partName: string, jointName: string): Motor6D?
	local part = character:FindFirstChild(partName)
	local found = part and part:FindFirstChild(jointName)
	return if found and found:IsA("Motor6D") then found else nil
end

-- The three R15 joints of the pose, or nil for other rigs (R6 has no waist or elbow: no procedural pose there).
local function rigFor(entry: Entry, character: Model): Rig?
	if entry.rig and entry.rig.character == character then
		return entry.rig
	end
	local waist = joint(character, "UpperTorso", "Waist")
	local shoulder = joint(character, "RightUpperArm", "RightShoulder")
	local elbow = joint(character, "RightLowerArm", "RightElbow")
	if not waist or not shoulder or not elbow then
		entry.rig = nil
		if Features.debugThrow and not reported[character] then
			reported[character] = true
			print(
				`[Throw] {character.Name}: no throw pose, the rig has no R15 Waist/RightShoulder/RightElbow (R6?). `
					.. "Set the avatar type to R15 or use published animations for this rig."
			)
		end
		return nil
	end
	if Features.debugThrow and not reported[character] then
		reported[character] = true
		print(`[Throw] {character.Name}: procedural throw pose on the R15 rig (no animation ids set)`)
	end
	local rig = {
		character = character,
		joints = { waist, shoulder, elbow },
		base = { waist.C0, shoulder.C0, elbow.C0 },
		applied = false,
	}
	entry.rig = rig
	return rig
end

local function apply(rig: Rig, pose: ThrowPose.Pose, weight: number)
	local joints, base = rig.joints, rig.base
	joints[1].C0 = base[1] * CFrame.Angles(0, math.rad(pose.waist * weight), 0)
	joints[2].C0 = base[2] * CFrame.Angles(math.rad(pose.shoulder * weight), 0, 0)
	joints[3].C0 = base[3] * CFrame.Angles(math.rad(pose.elbow * weight), 0, 0)
	rig.applied = true
end

local function restore(rig: Rig)
	for index, motor in rig.joints do
		motor.C0 = rig.base[index]
	end
	rig.applied = false
end

local function onPoseStep(dt: number)
	local clock = os.clock()
	local blend = dt / Animation.blendTime
	for player, entry in entries do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rig = character and rigFor(entry, character)
		if not rig or not humanoid then
			continue
		end
		local throwing = entry.throwAt ~= nil and clock - entry.throwAt < ThrowPose.throwLength(CombatConfig)
		local active = humanoid.Health > 0 and (player:GetAttribute("CombatMode") == true or throwing)
		entry.weight = math.clamp(entry.weight + (if active then blend else -blend), 0, 1)
		if entry.weight <= 0 then
			if rig.applied then
				restore(rig)
			end
			continue
		end
		local pose
		if throwing then
			pose = ThrowPose.throw(clock - (entry.throwAt :: number), CombatConfig)
		elseif entry.chargeSince then
			pose = ThrowPose.charge(clock - entry.chargeSince, CombatConfig)
		else
			pose = Animation.poses.stance
		end
		apply(rig, pose, entry.weight)
	end
end

-- Animation tracks for the local player, used instead of the procedural pose once all three ids are set.
local tracks: { [string]: AnimationTrack } = {}
local tracksOf: Humanoid? = nil

local function track(name: string): AnimationTrack?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not humanoid or not animator then
		return nil
	end
	if tracksOf ~= humanoid then
		tracksOf = humanoid
		table.clear(tracks)
	end
	local existing = tracks[name]
	if existing then
		return existing
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = Animation[name]
	local ok, loaded = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		return nil
	end
	loaded.Priority = Enum.AnimationPriority.Action
	loaded.Looped = name == "stance"
	if name == "charge" then
		loaded:GetMarkerReachedSignal("Held"):Connect(function()
			loaded:AdjustSpeed(0) -- hold the full wind-up until the release
		end)
	elseif name == "throw" then
		loaded:GetMarkerReachedSignal("Release"):Connect(function()
			local late = os.clock() - localReleaseAt - CombatConfig.releaseDelay
			if Features.debugThrow and math.abs(late) > 0.03 then
				print(
					string.format(
						"[Throw] the throw animation's Release marker came %.0f ms off releaseDelay; move it to %.2f s",
						late * 1000,
						CombatConfig.releaseDelay
					)
				)
			end
		end)
	end
	tracks[name] = loaded
	return loaded
end

local function syncStance()
	if not USE_TRACKS then
		return
	end
	local stance = track("stance")
	if not stance then
		return
	end
	local on = localPlayer:GetAttribute("CombatMode") == true
	if on and not stance.IsPlaying then
		stance:Play(Animation.blendTime)
	elseif not on and stance.IsPlaying then
		stance:Stop(Animation.blendTime)
		local charge = tracks.charge
		if charge and charge.IsPlaying then
			charge:Stop(0.1)
		end
	end
end

-- The local player started (true) or dropped (false) a charge.
function ThrowAnimator.charge(on: boolean)
	local entry = entryFor(localPlayer)
	entry.chargeSince = if on then os.clock() else nil
	if USE_TRACKS then
		local charge = track("charge")
		if charge then
			if on then
				charge:Play(0.05)
				charge:AdjustSpeed(1)
			else
				charge:Stop(0.1)
			end
		end
	end
end

-- The local player let go of the throw button and the throw was sent: the throw animation starts now.
function ThrowAnimator.release()
	local clock = os.clock()
	localReleaseAt = clock
	local entry = entryFor(localPlayer)
	entry.throwAt = clock
	entry.chargeSince = nil
	if USE_TRACKS then
		local charge = tracks.charge
		if charge and charge.IsPlaying then
			charge:Stop(0.03)
		end
		local throw = track("throw")
		if throw then
			throw:Play(0.03)
		end
	end
end

-- The server announced a throw (IceBallThrown); t0 is when the ball leaves the hand. Starts the throw for other
-- players; the local player's started at the button-up already.
function ThrowAnimator.thrown(thrower: Player, t0: number)
	if thrower == localPlayer and os.clock() - localReleaseAt < 1 then
		return
	end
	local entry = entryFor(thrower)
	local since = math.max(0, workspace:GetServerTimeNow() - (t0 - CombatConfig.releaseDelay))
	entry.throwAt = os.clock() - since
	entry.chargeSince = nil
end

local function watch(player: Player)
	local entry = entryFor(player)
	if player == localPlayer then
		player:GetAttributeChangedSignal("CombatMode"):Connect(syncStance)
		player.CharacterAdded:Connect(function()
			entry.chargeSince, entry.throwAt = nil, nil
			task.defer(syncStance)
		end)
		return
	end
	-- other players' wind-up comes from the server's Charging attribute
	player:GetAttributeChangedSignal("Charging"):Connect(function()
		entry.chargeSince = if player:GetAttribute("Charging") == true then os.clock() else nil
	end)
end

function ThrowAnimator.Start()
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		entries[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	if Features.debugThrow then
		print(
			if USE_TRACKS
				then "[Throw] throw animation: playing the three animation ids from Config/Combat"
				else "[Throw] throw animation: no animation ids in Config/Combat, procedural pose"
		)
	end
	if not USE_TRACKS then
		-- with MovementController's pose (Character + 2), before the held ball and backpack read the posed parts
		RunService:BindToRenderStep(STEP, Enum.RenderPriority.Character.Value + 2, onPoseStep)
	end
end

return ThrowAnimator
