-- The throw animation: the combat stance presents the ball (right forearm raised, the hand flat with its palm up, the
-- ball floating above it), the wind-up while the throw button is held, the push forward on release and back into
-- the stance. The ball leaves the hand releaseDelay after the button-up (Config/Combat): the server starts it then,
-- and the throw releases at that moment.
--   * With the three animation ids in Config/Combat (throwAnimation) the local player plays them; Roblox replicates
--     them to everyone. The charge animation holds at its "Held" marker, the throw has a "Release" marker at
--     releaseDelay (checked in the output while Features.debugThrow is on).
--   * With only the throw id, that one animation carries wind-up and throw: the local player starts it with the
--     charge, it holds releaseDelay before throwRelease, and the button-up lets it swing through so its release meets
--     the server's. It replicates; on every client the procedural pose steps aside while a character plays it and
--     keeps the stance otherwise.
--   * While the ids are empty, a procedural pose stands in, drawn by every client for every player from the
--     CombatMode and Charging attributes and the IceBallThrown event. ThrowPose gives the angles; they are written
--     into the joints' Transform right after Roblox's Animator each frame, so the right arm leaves the walk cycle
--     for the pose (blended in and out) and the waist turn adds on top. That works the same for Motor6D joints and
--     for the AnimationConstraint joints of newer avatars, on R15 (waist, shoulder, elbow, wrist) and on R6 (its
--     one right shoulder, see ThrowPose.singleArm). It touches no joint MovementController uses (the root), so
--     lean, stumble and knockdown stay as they are, and nothing here moves the character, its speed or its tower.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ThrowPose = require(Shared:WaitForChild("ThrowPose"))
local CombatConfig = require(Config:WaitForChild("Combat"))
local Features = require(Config:WaitForChild("Features"))

local ThrowAnimator = {}

-- A Motor6D or an AnimationConstraint: both place Part1 from Part0 through a joint frame (C0, or Attachment0) and
-- the Transform the Animator writes.
type Joint = Motor6D | AnimationConstraint

type Rig = {
	character: Model,
	r6: boolean,
	waist: Joint?, -- R15 only
	shoulder: Joint,
	elbow: Joint?, -- R15 only
	wrist: Joint?, -- R15 only, and optional there
}

type Entry = {
	rig: Rig?,
	weight: number, -- 0 outside combat mode, 1 in it, blended
	chargeSince: number?, -- os.clock() the wind-up began
	throwAt: number?, -- os.clock() of the button-up
}

local Animation = CombatConfig.throwAnimation
local USE_TRACKS = Animation.stance ~= "" and Animation.charge ~= "" and Animation.throw ~= ""
-- only the throw animation: it carries the wind-up too, the procedural pose keeps the stance
local THROW_ONLY = not USE_TRACKS and Animation.throw ~= ""
local THROW_ID = string.match(Animation.throw, "%d+$")
local THROW_FADE = 0.15 -- seconds the throw animation fades out at its end or when a charge is dropped

local localPlayer = Players.LocalPlayer
local entries: { [Player]: Entry } = {}
local reported: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local localReleaseAt = -math.huge
local releasing = false -- THROW_ONLY: the local throw animation runs from the button-up to the release point

local function entryFor(player: Player): Entry
	local entry = entries[player]
	if not entry then
		entry = { rig = nil, weight = 0, chargeSince = nil, throwAt = nil }
		entries[player] = entry
	end
	return entry
end

local function joint(character: Model, partName: string, jointName: string): Joint?
	local part = character:FindFirstChild(partName)
	local found = part and part:FindFirstChild(jointName)
	if found and found:IsA("Motor6D") then
		return found
	elseif found and found:IsA("AnimationConstraint") and found.Attachment0 then
		return found
	end
	return nil
end

-- The joints of the pose: R15 (waist, right shoulder, elbow and, if there, wrist) or R6 (the right shoulder), as
-- Motor6D or AnimationConstraint. Nil for anything else; then there is no procedural pose.
local function rigFor(entry: Entry, character: Model): Rig?
	if entry.rig and entry.rig.character == character then
		return entry.rig
	end
	local rig: Rig? = nil
	local shoulder = joint(character, "RightUpperArm", "RightShoulder")
	local waist = joint(character, "UpperTorso", "Waist")
	local elbow = joint(character, "RightLowerArm", "RightElbow")
	if shoulder and waist and elbow then
		rig = {
			character = character,
			r6 = false,
			waist = waist,
			shoulder = shoulder,
			elbow = elbow,
			wrist = joint(character, "RightHand", "RightWrist"),
		}
	else
		local r6Shoulder = joint(character, "Torso", "Right Shoulder")
		if r6Shoulder then
			rig = { character = character, r6 = true, waist = nil, shoulder = r6Shoulder, elbow = nil, wrist = nil }
		end
	end
	entry.rig = rig
	if Features.debugThrow and not reported[character] then
		reported[character] = true
		if rig then
			print(
				`[Throw] {character.Name}: procedural throw pose on the {if rig.r6 then "R6" else "R15"} rig `
					.. `({rig.shoulder.ClassName} joints{if rig.wrist or rig.r6 then "" else ", no wrist"})`
			)
		else
			print(
				`[Throw] {character.Name}: no throw pose, the rig has neither the R15 Waist/RightShoulder/RightElbow `
					.. "nor the R6 Right Shoulder joint"
			)
		end
	end
	return rig
end

-- The joint frame on Part0's side: C0 of a Motor6D, Attachment0 of an AnimationConstraint.
local function frameOf(target: Joint): CFrame
	if target:IsA("Motor6D") then
		return target.C0
	end
	local attachment = (target :: AnimationConstraint).Attachment0
	return if attachment then attachment.CFrame else CFrame.identity
end

-- A turn given in Part0's own axes (x right, y up, -z forward for a torso standing upright), as the Transform of
-- this joint: R6's shoulder frame is turned a quarter, R15's are not, and both then bend the same way.
local function inParentAxes(target: Joint, rotation: CFrame): CFrame
	local frame = frameOf(target).Rotation
	return frame:Inverse() * rotation * frame
end

-- The arm takes the pose instead of the animation, blended by weight; the waist turn is added on top of it.
local function hold(target: Joint?, rotation: CFrame, weight: number)
	if target then
		target.Transform = target.Transform:Lerp(inParentAxes(target, rotation), weight)
	end
end

local function apply(rig: Rig, pose: ThrowPose.Pose, weight: number)
	local out = math.rad(pose.out)
	if rig.r6 then
		hold(rig.shoulder, CFrame.Angles(0, 0, out) * CFrame.Angles(math.rad(ThrowPose.singleArm(pose)), 0, 0), weight)
		return
	end
	hold(rig.shoulder, CFrame.Angles(0, 0, out) * CFrame.Angles(math.rad(pose.shoulder), 0, 0), weight)
	hold(rig.elbow, CFrame.Angles(math.rad(pose.elbow), 0, 0), weight)
	-- the twist levels the hand against the arm's turn out, so the palm faces straight up
	hold(rig.wrist, CFrame.Angles(0, 0, math.rad(pose.twist)) * CFrame.Angles(math.rad(pose.wrist), 0, 0), weight)
	local waist = rig.waist
	if waist then
		waist.Transform = inParentAxes(waist, CFrame.Angles(0, math.rad(pose.waist * weight), 0)) * waist.Transform
	end
end

-- Whether this character plays the throw animation right now: the local player's own track, or another player's,
-- which Roblox replicated. The procedural pose steps aside meanwhile, so the two never fight over the arm.
local function playsThrow(humanoid: Humanoid): boolean
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not THROW_ONLY or not animator then
		return false
	end
	for _, playing in animator:GetPlayingAnimationTracks() do
		if playing.IsPlaying and string.match(playing.Animation.AnimationId, "%d+$") == THROW_ID then
			return true
		end
	end
	return false
end

local tracks: { [string]: AnimationTrack } = {}

-- THROW_ONLY, the local throw animation: held just before the release while charging, at its own speed again once
-- the release point is reached after the button-up, faded out at its end.
local function stepThrowTrack()
	local throw = tracks.throw
	if not THROW_ONLY or not throw or not throw.IsPlaying then
		return
	end
	local holdAt = Animation.throwRelease - CombatConfig.releaseDelay
	if releasing then
		if throw.TimePosition >= Animation.throwRelease then
			releasing = false
			throw:AdjustSpeed(1)
		end
	elseif throw.Speed > 0 and throw.TimePosition >= holdAt and throw.TimePosition < Animation.throwRelease then
		throw.TimePosition = holdAt
		throw:AdjustSpeed(0) -- wound up; waits for the button-up
	end
	if throw.Length > 0 and throw.Speed > 0 and throw.TimePosition >= throw.Length - THROW_FADE then
		throw:Stop(THROW_FADE)
	end
end

-- Runs right after the Animator each frame (PreSimulation), so its Transform is the one this frame shows. When the
-- weight is back at 0 nothing is written and the Animator has the joints to itself again: nothing to restore.
local function onPoseStep(dt: number)
	stepThrowTrack()
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
		local active = humanoid.Health > 0
			and (player:GetAttribute("CombatMode") == true or throwing)
			and not (not rig.r6 and playsThrow(humanoid))
		entry.weight = math.clamp(entry.weight + (if active then blend else -blend), 0, 1)
		if entry.weight <= 0 then
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

-- Animation tracks for the local player, used instead of the procedural pose once all three ids are set (or, with
-- only the throw id, for the throw).
local tracksOf: Humanoid? = nil

local function track(name: string): AnimationTrack?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not humanoid or not animator then
		return nil
	end
	if THROW_ONLY and humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil -- the throw animation is made for R15; R6 keeps the procedural throw
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
	elseif name == "throw" and USE_TRACKS then
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
	elseif THROW_ONLY then
		-- the wind-up is the start of the throw animation; a dropped charge (not the one a throw ends) fades it out
		local throw = track("throw")
		if throw and on then
			releasing = false
			throw:Play(0.1)
			throw:AdjustSpeed(1)
		elseif throw and not releasing and throw.IsPlaying then
			throw:Stop(THROW_FADE)
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
	elseif THROW_ONLY then
		-- on to the release point in exactly releaseDelay (faster if the wind-up was cut short), then at its own speed
		local throw = track("throw")
		if throw then
			if not throw.IsPlaying then
				throw:Play(0.05)
			end
			local left = Animation.throwRelease - throw.TimePosition
			releasing = left > 0
			throw:AdjustSpeed(if left > 0 then math.max(1, left / CombatConfig.releaseDelay) else 1)
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
			releasing = false
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
				elseif
					THROW_ONLY
				then `[Throw] throw animation: {Animation.throw} for wind-up and throw (release at {Animation.throwRelease} s), procedural stance`
				else "[Throw] throw animation: no animation ids in Config/Combat, procedural pose"
		)
	end
	if not USE_TRACKS then
		-- after the Animator wrote this frame's Transforms; the held ball and backpack read the posed parts when the
		-- next frame renders
		RunService.PreSimulation:Connect(onPoseStep)
	end
end

return ThrowAnimator
