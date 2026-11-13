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
	it("none aimed at players any more (kill test of 13.11.2026): all random, set in the config", function()
		expect(Config.nearPlayerShare).toBe(0)
		for _, roll in { 0, 0.05, 0.19, 0.5, 0.99 } do
			expect(TargetRules.choose(roll, 0.3, 4, Config)).toBeNil()
		end
	end)

	it("with a share near players: that share of the shots near a moving player", function()
		local share = { nearPlayerShare = 0.2 }
		local near, shots = 0, 10000
		local roll = 0
		for _ = 1, shots do
			-- an even spread of rolls, like a random generator over many shots
			roll = (roll + 0.6180339887) % 1
			if TargetRules.choose(roll, 0.5, 3, share) then
				near += 1
			end
		end
		expect(near / shots).toBeCloseTo(share.nearPlayerShare, 0.01)
	end)

	it("never near anybody when everybody stands still: all random", function()
		for _, roll in { 0, 0.05, 0.19, 0.5, 0.99 } do
			expect(TargetRules.choose(roll, 0.3, 0, Config)).toBeNil()
		end
	end)

	it("picks every moving player, none twice as often", function()
		local count = {}
		for step = 0, 999 do
			local index = TargetRules.choose(0, step / 1000, 4, { nearPlayerShare = 0.2 }) :: number
			count[index] = (count[index] or 0) + 1
		end
		for index = 1, 4 do
			expect(count[index]).toBe(250)
		end
		expect(TargetRules.choose(0, 0.9999999, 4, { nearPlayerShare = 0.2 })).toBe(4)
	end)
end)

describe("Big Swirl aim: the random spots", function()
	it("evenly over the whole arena: one ring from the trough to the arena's edge, set in the config", function()
		local bands = Config.randomBands
		expect(#bands).toBe(1)
		expect(bands[1].inner <= 30).toBe(true) -- just outside the machine's trough (radius 26)
		expect(bands[1].outer).toBe(Config.landingRadius) -- out to the rim
	end)

	it("picks a ring by its share", function()
		local bands = {
			{ inner = 25, outer = 55, share = 0.35 },
			{ inner = 55, outer = 80, share = 0.35 },
			{ inner = 80, outer = 100, share = 0.30 },
		}
		local count = {}
		local rolls = 10000
		for i = 0, rolls - 1 do
			local band = TargetRules.band(i / rolls, bands)
			count[band] = (count[band] or 0) + 1
		end
		for _, band in bands do
			expect(math.abs(count[band] / rolls - band.share) < 0.001).toBe(true)
		end
		expect(TargetRules.band(0.9999999, bands)).toBe(bands[#bands])
		-- shares need not add up to 1
		local half = { { inner = 0, outer = 1, share = 1 }, { inner = 1, outer = 2, share = 1 } }
		expect(TargetRules.band(0.49, half)).toBe(half[1])
		expect(TargetRules.band(0.51, half)).toBe(half[2])
	end)

	it("only spots inside the ring, else the one closest to it", function()
		-- landing spots every 10 studs out to 130 along a line from the machine at (0, 0)
		local spots = {}
		for r = 0, 130, 10 do
			table.insert(spots, r)
			table.insert(spots, 6)
			table.insert(spots, 0)
		end
		local between = MapRules.spotsBetween(spots, 0, 0, 20, 50)
		expect(#between).toBe(4) -- 20, 30, 40, 50
		for _, index in between do
			local r = spots[index * 3 - 2]
			expect(r >= 20 and r <= 50).toBe(true)
		end
		local none = MapRules.spotsBetween(spots, 0, 0, 52, 58) -- no spot in there: the closest to the ring
		expect(#none).toBe(1)
		expect(spots[none[1] * 3 - 2]).toBe(50)
	end)
end)
