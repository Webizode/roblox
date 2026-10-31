local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local ArenaZone = require("../src/shared/ArenaZone")
local MapConfig = require("../src/shared/Config/Map")

local Config = MapConfig.arena

-- a point `along` studs out on lane `index` and `across` studs to the side of it
local function onLane(index: number, along: number, across: number): (number, number)
	local sx, sz = ArenaZone.lane(index, Config)
	return Config.center.x + sx * along + sz * across, Config.center.z + sz * along - sx * across
end

describe("Arena zone: the floor", function()
	it("everything within the rim is arena, in every direction", function()
		for degrees = 0, 359, 7 do
			local a = math.rad(degrees)
			expect(ArenaZone.contains(math.sin(a) * 30, math.cos(a) * 30, Config)).toBe(true)
			expect(
				ArenaZone.contains(math.sin(a) * (Config.radius - 0.01), math.cos(a) * (Config.radius - 0.01), Config)
			).toBe(true)
		end
	end)

	it("the strip beside the ramps is safe zone right behind the rim", function()
		for index = 1, Config.ramps do
			local x, z = onLane(index, Config.radius + 1, Config.rampHalfWidth + 0.5)
			expect(ArenaZone.contains(x, z, Config)).toBe(false)
			x, z = onLane(index, Config.radius + 1, -(Config.rampHalfWidth + 0.5))
			expect(ArenaZone.contains(x, z, Config)).toBe(false)
		end
	end)
end)

describe("Arena zone: the ramps", function()
	it("every ramp is arena up to its top edge, and the strip right after it is not", function()
		for index = 1, Config.ramps do
			for _, across in { 0, Config.rampHalfWidth - 0.01, -(Config.rampHalfWidth - 0.01) } do
				for _, along in { Config.radius + 0.5, (Config.radius + Config.rampTop) / 2, Config.rampTop - 0.01 } do
					local x, z = onLane(index, along, across)
					expect(ArenaZone.contains(x, z, Config)).toBe(true)
				end
				local x, z = onLane(index, Config.rampTop + 0.01, across)
				expect(ArenaZone.contains(x, z, Config)).toBe(false)
			end
		end
	end)

	it("the same line both ways: walking up and down a ramp switches at the top edge only", function()
		local switches = {}
		for _, direction in { 1, -1 } do
			local was = nil
			local from, to = Config.rampTop - 3, Config.rampTop + 3
			if direction < 0 then
				from, to = to, from
			end
			for step = 0, 600 do
				local along = from + (to - from) * step / 600
				local x, z = onLane(4, along, 2)
				local now = ArenaZone.contains(x, z, Config)
				if was ~= nil and now ~= was then
					table.insert(switches, along)
				end
				was = now
			end
		end
		expect(#switches).toBe(2)
		expect(math.abs(switches[1] - Config.rampTop) < 0.02).toBe(true)
		expect(math.abs(switches[2] - Config.rampTop) < 0.02).toBe(true)
	end)

	it("the lanes are the plot lanes: 15 degrees, then every 30", function()
		expect(Config.ramps).toBe(12)
		expect(Config.firstRamp).toBe(15)
		local sx, sz = ArenaZone.lane(2, Config)
		expect(math.abs(sx - math.sin(math.rad(45))) < 1e-9).toBe(true)
		expect(math.abs(sz - math.cos(math.rad(45))) < 1e-9).toBe(true)
		for index = 1, Config.ramps do
			local x, z = onLane(index, 200, 0)
			expect(ArenaZone.nearestLane(x, z, Config)).toBe(index)
		end
	end)

	it("far out on a lane (hub, bridge, plot) is safe zone", function()
		for index = 1, Config.ramps do
			for _, along in { 165, 200, 260, 327 } do
				local x, z = onLane(index, along, 0)
				expect(ArenaZone.contains(x, z, Config)).toBe(false)
			end
		end
	end)
end)

describe("Arena zone: the server's slack", function()
	it("widens the floor and the ramps by the slack, and only by it", function()
		local slack = MapConfig.arena.serverSlack
		local edge = Config.radius + slack / 2
		expect(ArenaZone.contains(edge, 0, Config)).toBe(false)
		expect(ArenaZone.contains(edge, 0, Config, slack)).toBe(true)
		expect(ArenaZone.contains(Config.radius + slack + 0.5, 0, Config, slack)).toBe(false)
		for index = 1, Config.ramps do
			local x, z = onLane(index, Config.radius + 1, Config.rampHalfWidth + slack / 2)
			expect(ArenaZone.contains(x, z, Config)).toBe(false)
			expect(ArenaZone.contains(x, z, Config, slack)).toBe(true)
			x, z = onLane(index, Config.rampTop + slack / 2, 0)
			expect(ArenaZone.contains(x, z, Config, slack)).toBe(true)
		end
	end)
end)
