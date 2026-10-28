-- The Big Swirl's arms on this client: every shot from an arm starts that arm's cycle (dive into the trough, scoop,
-- swing up, pull back, whip, back to rest), timed by the server clock, so every player sees the same arm at the same
-- moment. The motion is the cycle baked in Blender (Config/BigSwirlCycle); this turns only each arm's own two bones
-- (shoulder and wrist), so arms moving at once never blend into each other. Purely visual.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local LaunchArms = require(Shared:WaitForChild("LaunchArms"))
local ArmConfig = require(Config:WaitForChild("BigSwirl"))
local Cycle = require(Config:WaitForChild("BigSwirlCycle"))

local BigSwirlArms = {}

type Arm = { shoulder: Bone, cup: Bone }
type Run = { start: number, speed: number } -- server time the cycle began, its play speed

local arms: { [number]: Arm } = {}
local runs: { [number]: Run } = {}
local machine: Instance? = nil

-- The bone of that name in the machine. Only bones count: the imported model also keeps values named after them
-- (InitialPoses), which a plain search by name can find first.
local function bone(name: string): Bone?
	for _, item in (machine :: Instance):GetDescendants() do
		if item.Name == name and item:IsA("Bone") then
			return item
		end
	end
	return nil
end

-- The arm's bones, looked up once the machine has streamed in (and again if it was rebuilt).
local function armOf(index: number): Arm?
	local arm = arms[index]
	if arm and arm.shoulder.Parent and arm.cup.Parent then
		return arm
	end
	local pier = workspace:FindFirstChild("Pier")
	machine = pier and pier:FindFirstChild("BigSwirl")
	if not machine then
		return nil
	end
	local shoulder = bone(string.format(ArmConfig.shoulderBone, index))
	local cup = bone(string.format(ArmConfig.cupBone, index))
	if shoulder and cup then
		arm = { shoulder = shoulder, cup = cup }
		arms[index] = arm
		return arm
	end
	return nil
end

-- A shot from arm `index` leaves at server time t0: its cycle runs so that the release comes at t0.
function BigSwirlArms.start(index: number, t0: number, speed: number)
	runs[index] = { start = t0 - ArmConfig.releaseAt / speed, speed = speed }
end

-- Poses every arm for server time `now`: the ones in a cycle by the baked frames, the others at rest.
function BigSwirlArms.step(now: number)
	for index, run in runs do
		local arm = armOf(index)
		if not arm then
			continue
		end
		local elapsed = now - run.start
		local shoulder, wrist = LaunchArms.pose(Cycle, elapsed, run.speed)
		-- both joints turn about their bone's Y (measured against the Blender animation in Studio): the shoulder
		-- lifts the arm with a negative turn, the wrist tips the cup outward with a positive one
		arm.shoulder.Transform = CFrame.Angles(0, -math.rad(shoulder), 0)
		arm.cup.Transform = CFrame.Angles(0, math.rad(wrist), 0)
		if elapsed * run.speed > ArmConfig.cycleLength then
			runs[index] = nil -- back at rest, Transform already identity
		end
	end
end

-- The cup bone of arm `index` as posed this frame, or nil before the machine has streamed in.
function BigSwirlArms.cup(index: number): Bone?
	local arm = armOf(index)
	return arm and arm.cup
end

return BigSwirlArms
