local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local TargetRules = require("../src/shared/TargetRules")
local Config = require("../src/shared/Config/Launcher")
local MapRules = require("../src/shared/MapRules")

describe("Big Swirl aim: standing still", function()
	it("counts as standing still after idleSeconds within idleRadius", function()
		local track = TargetRules.track(nil, 10, 10, 0, Config)
		expect(TargetRules.isIdle(track, Config.idleSeconds - 0.1, Config)).toBe(false)
		-- shuffling about on the spot does not count as moving
		track = TargetRules.track(track, 10 + Config.idleRadius * 0.7, 10, 1, Config)
		track = TargetRules.track(track, 10, 10 - Config.idleRadius * 0.7, 2, Config)
		expect(TargetRules.isIdle(track, Config.idleSeconds, Config)).toBe(true)
	end)

	it("moving on starts the clock again", function()
		local track = TargetRules.track(nil, 0, 0, 0, Config)
		expect(TargetRules.isIdle(track, 10, Config)).toBe(true)
		track = TargetRules.track(track, Config.idleRadius + 1, 0, 10, Config)
		expect(TargetRules.isIdle(track, 10, Config)).toBe(false)
		expect(TargetRules.isIdle(track, 10 + Config.idleSeconds, Config)).toBe(true)
	end)
end)

describe("Big Swirl aim: random or near a player", function()
	it("about 80 % random, the rest near a moving player, set in the config", function()
		expect(Config.nearPlayerShare).toBe(0.2)
		local near, shots = 0, 10000
		local roll = 0
		for _ = 1, shots do
			-- an even spread of rolls, like a random generator over many shots
			roll = (roll + 0.6180339887) % 1
			if TargetRules.choose(roll, 0.5, 3, Config) then
				near += 1
			end
		end
		expect(near / shots).toBeCloseTo(Config.nearPlayerShare, 0.01)
	end)

	it("never near anybody when everybody stands still: all random", function()
		for _, roll in { 0, 0.05, 0.19, 0.5, 0.99 } do
			expect(TargetRules.choose(roll, 0.3, 0, Config)).toBeNil()
		end
	end)

	it("picks every moving player, none twice as often", function()
		local count = {}
		for step = 0, 999 do
			local index = TargetRules.choose(0, step / 1000, 4, Config) :: number
			count[index] = (count[index] or 0) + 1
		end
		for index = 1, 4 do
			expect(count[index]).toBe(250)
		end
		expect(TargetRules.choose(0, 0.9999999, 4, Config)).toBe(4)
	end)
end)

describe("Big Swirl aim: the random spots", function()
	it("only spots within randomRadius of the machine, the arena and the inner ring", function()
		-- landing spots every 10 studs out to 100 along a line from the machine at (0, 0)
		local spots = {}
		for r = 0, 100, 10 do
			table.insert(spots, r)
			table.insert(spots, 6)
			table.insert(spots, 0)
		end
		local inside = MapRules.spotsNear(spots, 0, 0, Config.randomRadius)
		for _, index in inside do
			expect(spots[index * 3 - 2] <= Config.randomRadius).toBe(true)
		end
		expect(#inside).toBe(7) -- 0 to 60
		expect(Config.randomRadius < 81).toBe(true) -- never out on the sand ring with the stands
	end)
end)
