local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Wanted = require("../src/shared/Wanted")
local ArenaZone = require("../src/shared/ArenaZone")
local Config = require("../src/shared/Config/Wanted")
local MapConfig = require("../src/shared/Config/Map")

local arena = MapConfig.arena
local LIMIT = Wanted.limit(arena, Config)

-- a point `along` studs out on ramp lane `lane` (1-based), `across` studs to its side
local function onLane(lane: number, along: number, across: number?): (number, number)
	local sx, sz = ArenaZone.lane(lane, arena)
	local side = across or 0
	return arena.center.x + along * sx + side * sz, arena.center.z + along * sz - side * sx
end

describe("Wanted: who becomes wanted", function()
	it("picking up somebody else's spilled scoop is stealing", function()
		expect(Wanted.isStolen(false, 111, 222)).toBe(true)
	end)

	it("picking up the own spilled scoops or Big Swirl scoops is not", function()
		expect(Wanted.isStolen(false, 222, 222)).toBe(false)
		expect(Wanted.isStolen(true, 0, 222)).toBe(false)
		expect(Wanted.isStolen(true, 111, 222)).toBe(false)
	end)
end)

describe("Wanted: the time", function()
	it("lasts 10 s and starts over with every stolen scoop, never adding up", function()
		expect(Config.duration).toBe(10)
		expect(Wanted.untilAfterSteal(100, Config)).toBe(110)
		expect(Wanted.untilAfterSteal(107, Config)).toBe(117) -- again 3 s before the end: 10 s from now
	end)

	it("counts down 10, 9, ... 1 and then 0", function()
		expect(Wanted.secondsLeft(110, 100)).toBe(10)
		expect(Wanted.secondsLeft(110, 100.01)).toBe(10)
		expect(Wanted.secondsLeft(110, 101)).toBe(9)
		expect(Wanted.secondsLeft(110, 109.5)).toBe(1)
		expect(Wanted.secondsLeft(110, 110)).toBe(0)
		expect(Wanted.secondsLeft(110, 200)).toBe(0)
		expect(Wanted.secondsLeft(0 / 0, 100)).toBe(0)
	end)
end)

describe("Wanted: the edge", function()
	it("the line lies inside the arena, short of every ramp's top edge", function()
		expect(LIMIT).toBeLessThan(arena.rampTop)
		expect(LIMIT).toBeGreaterThan(arena.radius)
		for lane = 1, arena.ramps do
			local x, z = onLane(lane, LIMIT, 0)
			expect(ArenaZone.contains(x, z, arena)).toBe(true)
		end
	end)

	it("anywhere on the floor and on a ramp below the line is allowed", function()
		local _, _, past = Wanted.allowedPoint(arena.center.x + 30, arena.center.z - 80, arena, LIMIT)
		expect(past).toBe(0)
		for lane = 1, arena.ramps do
			local x, z = onLane(lane, LIMIT - 1, arena.rampHalfWidth - 0.5)
			local _, _, onRamp = Wanted.allowedPoint(x, z, arena, LIMIT)
			expect(onRamp).toBeCloseTo(0, 1e-6)
		end
	end)

	it("past the line up a ramp it says how far and points straight back down the lane", function()
		for lane = 1, arena.ramps do
			local x, z = onLane(lane, LIMIT + 3, 2)
			local px, pz, past = Wanted.allowedPoint(x, z, arena, LIMIT)
			expect(past).toBeCloseTo(3, 1e-6)
			local ex, ez = onLane(lane, LIMIT, 2)
			expect(px).toBeCloseTo(ex, 1e-6)
			expect(pz).toBeCloseTo(ez, 1e-6)
		end
	end)

	it("in the safe zone beyond the top edge it is past the line too", function()
		local x, z = onLane(4, arena.rampTop + 5, 0)
		local _, _, past = Wanted.allowedPoint(x, z, arena, LIMIT)
		expect(past).toBeCloseTo(arena.rampTop + 5 - LIMIT, 1e-6)
	end)

	it("the server only pulls back beyond its slack, to a point inside the line", function()
		local x, z = onLane(7, LIMIT + Config.serverSlack - 0.5, 0)
		expect(Wanted.pullBackTo(x, z, arena, Config, Config.serverSlack, Config.pullBack, Config.maxPull)).toBeNil()
		x, z = onLane(7, LIMIT + Config.serverSlack + 1, 1)
		local px, pz = Wanted.pullBackTo(x, z, arena, Config, Config.serverSlack, Config.pullBack, Config.maxPull)
		local ex, ez = onLane(7, LIMIT - Config.pullBack, 1)
		expect(px).toBeCloseTo(ex, 1e-6)
		expect(pz).toBeCloseTo(ez, 1e-6)
	end)

	it("leaves a player far out alone (the plot or the hub, not a ramp run)", function()
		local x, z = onLane(2, 320, 0)
		expect(Wanted.pullBackTo(x, z, arena, Config, Config.serverSlack, Config.pullBack, Config.maxPull)).toBeNil()
	end)
end)
