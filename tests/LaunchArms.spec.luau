local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local LaunchArms = require("../src/shared/LaunchArms")
local Config = require("../src/shared/Config/BigSwirl")
local Launcher = require("../src/shared/Config/Launcher")
local Cycle = require("../src/shared/Config/BigSwirlCycle")

local ARMS = #Config.releasePoints

local function direction(arm: number): (number, number)
	local point = Config.releasePoints[arm]
	return point[1], point[3]
end

-- every arm busy until `untilTime` except the listed ones
local function busyExcept(untilTime: number, free: { number }): { number }
	local freeAt = {}
	for arm = 1, ARMS do
		freeAt[arm] = if table.find(free, arm) then 0 else untilTime
	end
	return freeAt
end

describe("Big Swirl arms: which arm fires", function()
	it("the arm pointing the target's way, when it is free", function()
		for arm = 1, ARMS do
			local dx, dz = direction(arm)
			expect(LaunchArms.pick(dx, dz, {}, 0, Config)).toBe(arm)
		end
	end)

	it("a busy arm passes the shot to its free neighbour", function()
		-- halfway between arm 1 and arm 2: both are close, arm 1 is busy
		local x1, z1 = direction(1)
		local x2, z2 = direction(2)
		local freeAt = busyExcept(10, { 2 })
		expect(LaunchArms.pick(x1 + x2, z1 + z2, freeAt, 5, Config)).toBe(2)
	end)

	it("never fires the opposite way: with only far-off arms free, the shot waits", function()
		local dx, dz = direction(1)
		local opposite = ARMS // 2 + 1
		local freeAt = busyExcept(10, { opposite })
		expect(LaunchArms.pick(dx, dz, freeAt, 5, Config)).toBeNil()
	end)

	it("an arm is free again at its freeAt time", function()
		local dx, dz = direction(3)
		local freeAt = busyExcept(7, {})
		expect(LaunchArms.pick(dx, dz, freeAt, 7, Config)).toBe(3)
	end)
end)

describe("Big Swirl arms: timing", function()
	it("at the launcher's slowest pace the arms play at their own speed", function()
		expect(LaunchArms.playSpeed(Launcher.baseInterval, Config)).toBe(Config.minPlaySpeed)
	end)

	it("a fast launcher never needs the arms faster than the limit allows, and they keep pace", function()
		local speed = LaunchArms.playSpeed(Launcher.minInterval, Config)
		expect(speed <= Config.maxPlaySpeed).toBe(true)
		local timing = LaunchArms.timing(speed, Config)
		-- all arms together, each busy for one cycle, cover one shot per interval
		expect((timing.busyFor - Config.busyMargin) / ARMS <= Launcher.minInterval * 1.01).toBe(true)
	end)

	it("the release comes releaseAt / speed after the start, the scoop shows before it", function()
		local timing = LaunchArms.timing(2, Config)
		expect(timing.releaseLead).toBeCloseTo(Config.releaseAt / 2)
		expect(timing.scoopLead).toBeCloseTo((Config.releaseAt - Config.scoopedAt) / 2)
		expect(timing.scoopLead < timing.releaseLead).toBe(true)
	end)

	it("six arms, and the release after the scoop inside the cycle", function()
		expect(ARMS).toBe(6)
		expect(Config.scoopedAt < Config.releaseAt and Config.releaseAt < Config.cycleLength).toBe(true)
	end)
end)

describe("Big Swirl arms: the motion", function()
	it("the baked cycle fills the cycle length, frame for frame", function()
		expect(#Cycle.shoulder).toBe(#Cycle.wrist)
		expect((#Cycle.shoulder - 1) / Cycle.fps).toBeCloseTo(Config.cycleLength)
	end)

	it("every cycle goes all the way down into the trough, whatever else is moving", function()
		-- the deepest point of the bake: what an arm reaches each time, since every client poses only its own bones
		local deepest = math.huge
		for _, s in Cycle.shoulder do
			deepest = math.min(deepest, s)
		end
		local lowest = math.huge
		for step = 0, 300 do
			local s = LaunchArms.pose(Cycle, Config.cycleLength * step / 300, 1)
			lowest = math.min(lowest, s)
		end
		expect(lowest).toBeCloseTo(deepest, 0.5)
		expect(deepest < -60).toBe(true) -- the arm drops 60+ degrees from rest: into the mix
	end)

	it("rests before and after its cycle, and follows the frames in between", function()
		local s, w = LaunchArms.pose(Cycle, -0.5, 1)
		expect(s).toBe(0)
		expect(w).toBe(0)
		s, w = LaunchArms.pose(Cycle, Config.cycleLength + 0.1, 1)
		expect(s).toBe(0)
		expect(w).toBe(0)
		s, w = LaunchArms.pose(Cycle, 14 / Cycle.fps, 1)
		expect(s).toBeCloseTo(Cycle.shoulder[15], 0.01)
		expect(w).toBeCloseTo(Cycle.wrist[15], 0.01)
	end)

	it("a faster arm reaches the same frame sooner", function()
		local s1 = LaunchArms.pose(Cycle, 1.0, 1)
		local s2 = LaunchArms.pose(Cycle, 0.5, 2)
		expect(s2).toBeCloseTo(s1, 0.01)
	end)
end)

describe("Big Swirl arms: in step with the Blender bake", function()
	-- the tests run from the repo root (lune run tests/run.luau)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local bake = serde.decode("json", fs.readFile("assets/BigSwirl/arm_cycle.json"))

	it("the cycle length and the markers are the bake's", function()
		expect(Config.cycleLength).toBeCloseTo(bake.length, 0.001)
		expect(Config.scoopedAt).toBeCloseTo(bake.markers.Scooped, 0.001)
		expect(Config.releaseAt).toBeCloseTo(bake.markers.Release, 0.001)
	end)

	it("every arm releases where the bake says", function()
		for arm, point in Config.releasePoints do
			local baked = bake.releasePoints[tostring(arm)]
			for axis = 1, 3 do
				expect(point[axis]).toBeCloseTo(baked[axis], 0.001)
			end
		end
	end)

	it("the generated frames are the bake's (else run scripts/bigswirl-cycle)", function()
		expect(Cycle.fps).toBe(bake.fps)
		expect(#Cycle.shoulder).toBe(#bake.frames)
		for i, frame in bake.frames do
			expect(Cycle.shoulder[i]).toBeCloseTo(frame.shoulder, 0.006)
			expect(Cycle.wrist[i]).toBeCloseTo(frame.wrist, 0.006)
		end
	end)
end)
