local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local TeleportRules = require("../src/shared/TeleportRules")
local MapConfig = require("../src/shared/Config/Map")

local function request(overrides)
	local r = {
		where = "plot",
		alive = true,
		inArena = false,
		carrying = false,
		down = false,
		sinceHit = math.huge,
		sinceRequest = math.huge,
	}
	for key, value in overrides or {} do
		r[key] = value
	end
	return r
end

describe("Teleport targets", function()
	it("knows the plot, the arena and the three shops, nothing else", function()
		for _, where in { "plot", "arena", "upgrades", "quests", "cosmetics" } do
			expect(TeleportRules.isTarget(where, MapConfig)).toBe(true)
		end
		for _, where in { "shop", "", 1, true, "Teleport_Upgrade" } do
			expect(TeleportRules.isTarget(where, MapConfig)).toBe(false)
		end
		expect(TeleportRules.isTarget(nil, MapConfig)).toBe(false)
	end)
end)

describe("Teleport requests", function()
	it("are granted outside the arena for every target", function()
		for _, where in { "plot", "arena", "upgrades", "quests", "cosmetics" } do
			expect(TeleportRules.refusal(request({ where = where }), MapConfig)).toBe(nil)
		end
	end)

	it(
		"are refused knocked down, right after a hit and in the arena with a tower, for every target the same",
		function()
			for _, where in { "plot", "arena", "upgrades", "quests", "cosmetics" } do
				local carrying = request({ where = where, inArena = true, carrying = true })
				expect(TeleportRules.refusal(carrying, MapConfig)).toBe("tower")
				expect(TeleportRules.refusal(request({ where = where, down = true }), MapConfig)).toBe("down")
				expect(TeleportRules.refusal(request({ where = where, sinceHit = 0.5 }), MapConfig)).toBe("hit")
			end
		end
	)

	it("are granted in the arena without scoops on the back, and outside it with them", function()
		expect(TeleportRules.refusal(request({ inArena = true }), MapConfig)).toBe(nil)
		expect(TeleportRules.refusal(request({ carrying = true }), MapConfig)).toBe(nil)
		-- a knockdown is the reason given first
		local down = request({ inArena = true, carrying = true, down = true })
		expect(TeleportRules.refusal(down, MapConfig)).toBe("down")
	end)

	it("open again once the hit lock has run out", function()
		local lock = MapConfig.teleportHitLock
		expect(TeleportRules.refusal(request({ sinceHit = lock - 0.01 }), MapConfig)).toBe("hit")
		expect(TeleportRules.refusal(request({ sinceHit = lock }), MapConfig)).toBe(nil)
	end)

	it("drops floods first and refuses dead characters and unknown targets", function()
		expect(TeleportRules.refusal(request({ sinceRequest = 0.1, inArena = true }), MapConfig)).toBe("flood")
		expect(TeleportRules.refusal(request({ alive = false }), MapConfig)).toBe("dead")
		expect(TeleportRules.refusal(request({ where = "moon" }), MapConfig)).toBe("unknown")
	end)
end)

describe("Teleport spots", function()
	it("picks the nearest of several targets", function()
		local points = { { 100, 0 }, { -50, 80 }, { 0, -120 } }
		expect(TeleportRules.nearest(points, -40, 70)).toBe(2)
		expect(TeleportRules.nearest(points, 90, 10)).toBe(1)
		expect(TeleportRules.nearest({}, 0, 0)).toBe(nil)
	end)

	it("lands on the first free spot and moves aside for players standing there", function()
		local spots = { { 0, 0 }, { -3.5, 0 }, { 3.5, 0 } }
		expect(TeleportRules.spot(spots, {}, 3)).toBe(1)
		expect(TeleportRules.spot(spots, { { 0.5, 0 } }, 3)).toBe(2)
		expect(TeleportRules.spot(spots, { { 0, 0 }, { -3.5, 0.5 } }, 3)).toBe(3)
	end)

	it("with every spot taken, takes the one with the most room", function()
		local spots = { { 0, 0 }, { 4, 0 }, { 8, 0 } }
		expect(TeleportRules.spot(spots, { { 0, 0 }, { 4, 0 }, { 7, 0 } }, 3)).toBe(3)
	end)

	it("the configured spots are at least the gap apart", function()
		local slots = MapConfig.teleportSlots
		for i = 1, #slots do
			for j = i + 1, #slots do
				local dx, dz = slots[i][1] - slots[j][1], slots[i][2] - slots[j][2]
				expect(math.sqrt(dx * dx + dz * dz) >= MapConfig.teleportSlotGap).toBe(true)
			end
		end
	end)
end)
