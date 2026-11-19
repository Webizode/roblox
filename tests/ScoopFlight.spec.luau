local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local ScoopFlight = require("../src/shared/ScoopFlight")
local Config = require("../src/shared/Config/TowerScoops")
local Flavors = require("../src/shared/Config/Flavors")

describe("Tower scoops: in flight", function()
	it("upright all the way up, tipped dome first once tipSpan past the apex", function()
		local apex = 0.45
		expect(ScoopFlight.tip(0, apex, Config)).toBe(0)
		expect(ScoopFlight.tip(apex, apex, Config)).toBe(0)
		expect(ScoopFlight.tip(apex + Config.flight.tipSpan / 2, apex, Config)).toBeCloseTo(0.5, 1e-6)
		expect(ScoopFlight.tip(apex + Config.flight.tipSpan, apex, Config)).toBe(1)
		expect(ScoopFlight.tip(1.1, apex, Config)).toBe(1)
	end)

	it("tips without a jerk: every frame turns it only a little", function()
		local apex, step = 0.4, 1 / 60 / 2.5 -- a frame of a 2.5 s flight
		local last = 0
		for alpha = 0, 1, step do
			local tip = ScoopFlight.tip(alpha, apex, Config)
			expect(tip - last < 0.15).toBe(true)
			expect(tip >= last).toBe(true)
			last = tip
		end
	end)

	it("tipped, the dome turns all the way to the direction it falls", function()
		-- falling straight down: the dome turns over completely (half a turn)
		expect(ScoopFlight.tipAngle(1, 0, -10, 0, Config)).toBeCloseTo(math.pi, 1e-6)
		-- falling at 45 degrees: three quarters of half a turn
		expect(ScoopFlight.tipAngle(1, 10, -10, 0, Config)).toBeCloseTo(math.pi * 0.75, 1e-6)
		-- upright it does not turn, whatever the direction
		expect(ScoopFlight.tipAngle(0, 3, -10, 1, Config)).toBe(0)
		expect(ScoopFlight.tipAngle(1, 0, 0, 0, Config)).toBe(0)
	end)

	it("turns about its own axis on the way", function()
		expect(ScoopFlight.spin(0, Config)).toBe(0)
		expect(ScoopFlight.spin(1, Config)).toBeCloseTo(Config.flight.spinRate, 1e-9)
	end)
end)

describe("Tower scoops: the catch", function()
	it("swings past upright and settles there", function()
		expect(ScoopFlight.righting(0, Config)).toBeCloseTo(0, 1e-9)
		local most = 0
		for step = 0, 100 do
			most = math.max(most, ScoopFlight.righting(Config.catch.rightTime * step / 100, Config))
		end
		expect(most > 1.05).toBe(true) -- the short swing
		expect(most < 1.4).toBe(true) -- but not a flip
		expect(ScoopFlight.righting(Config.catch.rightTime, Config)).toBeCloseTo(1, 1e-9)
		expect(ScoopFlight.righting(5, Config)).toBeCloseTo(1, 1e-9)
	end)

	it("plops onto the tower: drops in from above, squashes once, then rests in its place", function()
		local drop, sy, sxz = ScoopFlight.plop(0, Config)
		expect(drop).toBeCloseTo(Config.catch.plopDrop, 1e-9)
		expect(sy).toBe(1)
		expect(sxz).toBe(1)
		local flattest = 1
		for step = 0, 100 do
			local d, y, xz = ScoopFlight.plop(Config.catch.plopTime * step / 100, Config)
			expect(d >= 0).toBe(true)
			expect(d <= Config.catch.plopDrop).toBe(true)
			if y < 1 then
				expect(xz > 1).toBe(true) -- flatter means wider
				expect(d).toBe(0) -- it only squashes once it has landed
			end
			flattest = math.min(flattest, y)
		end
		expect(flattest).toBeCloseTo(1 - Config.catch.squash, 0.01)
		drop, sy, sxz = ScoopFlight.plop(Config.catch.plopTime, Config)
		expect(drop).toBe(0)
		expect(sy).toBe(1)
		expect(sxz).toBe(1)
	end)
end)

describe("Tower scoops: the far model", function()
	it("takes over from farDistance on and hands back a little closer, so it does not flicker", function()
		expect(ScoopFlight.useFar(Config.farDistance - 1, false, Config)).toBe(false)
		expect(ScoopFlight.useFar(Config.farDistance, false, Config)).toBe(true)
		expect(ScoopFlight.useFar(Config.farDistance - 1, true, Config)).toBe(true)
		expect(ScoopFlight.useFar(Config.farDistance - Config.hysteresis - 0.1, true, Config)).toBe(false)
	end)

	it("about 40 studs, as agreed", function()
		expect(Config.farDistance).toBe(40)
	end)
end)

describe("Flavors: the commons", function()
	local COMMONS = {
		"vanilla",
		"chocolate",
		"strawberry",
		"mint",
		"lemon",
		"bubblegum",
		"cookie",
		"pistachio",
		"mango",
		"stracciatella",
		"watermelon",
	}

	it("eleven classics with exactly vanilla's values and physics", function()
		local vanilla = Flavors.byId.vanilla
		for _, id in COMMONS do
			local flavor = Flavors.byId[id]
			expect(flavor ~= nil).toBe(true)
			expect(flavor.rarity).toBe("common")
			expect(flavor.family).toBe("classic")
			for _, key in { "value", "mass", "stiffness", "damping", "jerk", "weight" } do
				expect(flavor[key]).toBe(vanilla[key])
			end
		end
	end)

	it("the eleven commons are the common flavors (the rarer ones came 18.11.2026)", function()
		local commons = 0
		for _, flavor in Flavors.list do
			if not flavor.placeholder and flavor.rarity == "common" then
				commons += 1
			end
		end
		expect(commons).toBe(#COMMONS)
		for _, id in { "rocky_road", "cookie_dough", "mochi", "jelly", "chili_lava", "cursed_pickle" } do
			expect(Flavors.byId[id]).toBeNil()
		end
	end)

	it("every id once, every flavor a colour of its own", function()
		local ids, colors = {}, {}
		for _, flavor in Flavors.list do
			expect(ids[flavor.id]).toBeNil()
			expect(colors[flavor.color]).toBeNil()
			ids[flavor.id], colors[flavor.color] = true, true
		end
	end)
end)

describe("Tower scoops: the stack pose", function()
	it("is the same every time for the same place", function()
		for index = 1, 30 do
			local a, b, c, d = ScoopFlight.stackPose(index, Config)
			local e, f, g, h = ScoopFlight.stackPose(index, Config)
			expect(a).toBe(e)
			expect(b).toBe(f)
			expect(c).toBe(g)
			expect(d).toBe(h)
		end
	end)

	it("stays within the tilt and the size range, a full turn of yaw", function()
		for index = 1, 200 do
			local yaw, tiltX, tiltZ, scale = ScoopFlight.stackPose(index, Config)
			expect(yaw >= 0 and yaw < 2 * math.pi).toBe(true)
			expect(math.abs(tiltX) <= Config.stack.tilt).toBe(true)
			expect(math.abs(tiltZ) <= Config.stack.tilt).toBe(true)
			expect(scale >= Config.stack.scaleMin and scale <= Config.stack.scaleMax).toBe(true)
		end
	end)

	it("differs from place to place: no two neighbours turned alike", function()
		local sizes = {}
		for index = 1, 30 do
			local yaw = ScoopFlight.stackPose(index, Config)
			local next = ScoopFlight.stackPose(index + 1, Config)
			local apart = math.abs(yaw - next) % (2 * math.pi)
			expect(math.min(apart, 2 * math.pi - apart) > math.rad(3)).toBe(true)
			local _, _, _, scale = ScoopFlight.stackPose(index, Config)
			sizes[math.floor((scale - Config.stack.scaleMin) / 0.025)] = true
		end
		local spread = 0
		for _ in sizes do
			spread += 1
		end
		expect(spread >= 3).toBe(true)
	end)
end)
