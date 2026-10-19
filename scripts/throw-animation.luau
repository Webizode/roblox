-- lune run scripts/throw-animation
-- Bakes the throw poses from Config/Combat (throwAnimation, the same ones the procedural pose draws) into three
-- R15 KeyframeSequences for the Animation Editor: WobbleCombatStance (looped), WobbleThrowCharge (wind-up, "Held"
-- marker at its end) and WobbleThrow ("Release" marker at releaseDelay). Writes assets/WobbleThrowAnimations.rbxm.
-- It only creates keyframe data; publishing the animations is done in Studio (see README).

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local Combat = luau.load(fs.readFile("src/shared/Config/Combat.luau"))()
local ThrowPose = luau.load(fs.readFile("src/shared/ThrowPose.luau"))()
local Animation = Combat.throwAnimation

local OUTPUT = "assets/WobbleThrowAnimations.rbxm"

local function pose(name: string, parent, cframe, weight: number)
	local instance = Instance.new("Pose")
	instance.Name = name
	instance.CFrame = cframe
	instance.Weight = weight
	instance.EasingStyle = Enum.PoseEasingStyle.Cubic
	instance.EasingDirection = Enum.PoseEasingDirection.Out
	instance.Parent = parent
	return instance
end

-- One keyframe of the R15 hierarchy. Only the waist (UpperTorso), the right shoulder (RightUpperArm) and the right
-- elbow (RightLowerArm) carry the throw; the parents are there because poses must follow the rig.
local function keyframe(sequence, time: number, angles, marker: string?)
	local frame = Instance.new("Keyframe")
	frame.Time = time
	frame.Parent = sequence
	local root = pose("HumanoidRootPart", frame, CFrame.new(), 0)
	local lower = pose("LowerTorso", root, CFrame.new(), 0)
	local upper = pose("UpperTorso", lower, CFrame.Angles(0, math.rad(angles.waist), 0), 1)
	local arm = pose("RightUpperArm", upper, CFrame.Angles(math.rad(angles.shoulder), 0, 0), 1)
	pose("RightLowerArm", arm, CFrame.Angles(math.rad(angles.elbow), 0, 0), 1)
	if marker then
		local instance = Instance.new("KeyframeMarker")
		instance.Name = marker
		instance.Parent = frame
	end
end

local function sequence(name: string, looped: boolean)
	local instance = Instance.new("KeyframeSequence")
	instance.Name = name
	instance.Loop = looped
	instance.Priority = Enum.AnimationPriority.Action
	return instance
end

local poses = Animation.poses

local stance = sequence("WobbleCombatStance", true)
keyframe(stance, 0, poses.stance)
keyframe(stance, 1, poses.stance)

local charge = sequence("WobbleThrowCharge", false)
for step = 0, 3 do
	local time = Animation.windupTime * step / 3
	keyframe(charge, time, ThrowPose.charge(time, Combat), if step == 3 then "Held" else nil)
end

local throw = sequence("WobbleThrow", false)
local times = { 0, Combat.releaseDelay / 2, Combat.releaseDelay }
local follow = Combat.releaseDelay + Animation.followTime
for step = 1, 3 do
	table.insert(times, Combat.releaseDelay + Animation.followTime * step / 3)
end
for step = 1, 4 do
	table.insert(times, follow + Animation.recoverTime * step / 4)
end
for _, time in times do
	keyframe(throw, time, (ThrowPose.throw(time, Combat)), if time == Combat.releaseDelay then "Release" else nil)
end

local folder = Instance.new("Folder")
folder.Name = "WobbleThrowAnimations"
stance.Parent, charge.Parent, throw.Parent = folder, folder, folder

if not fs.isDir("assets") then
	fs.writeDir("assets")
end
fs.writeFile(OUTPUT, roblox.serializeModel({ folder }))
print(`wrote {OUTPUT}: {#stance:GetChildren()} + {#charge:GetChildren()} + {#throw:GetChildren()} keyframes`)
