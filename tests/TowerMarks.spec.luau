local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local TowerMarks = require("../src/shared/TowerMarks")
local Flavors = require("../src/shared/Config/Flavors")
local Look = require("../src/shared/Config/TowerScoops")

local RING = Look.rarityRing
local RARITIES = Flavors.rarities

local function ring(rarity: string?, quality: string?)
	return TowerMarks.ring(rarity, quality or "high", RING, RARITIES, "#123456")
end

describe("Rarity rings on a tower", function()
	it("has none under a common scoop or one of an unknown rarity", function()
		expect(ring("common")).toBeNil()
		expect(ring(nil)).toBeNil()
		expect(ring("nonsense")).toBeNil()
	end)

	it("is plain for uncommon and rare, glows from epic and glints for a legendary", function()
		for _, rarity in { "uncommon", "rare" } do
			local r = ring(rarity)
			expect(r.glow).toBe(false)
			expect(r.sparkle).toBe(false)
		end
		expect(ring("epic").glow).toBe(true)
		expect(ring("epic").sparkle).toBe(false)
		expect(ring("legendary").glow).toBe(true)
		expect(ring("legendary").sparkle).toBe(true)
		expect(ring("legendary").color).toBe("#123456")
	end)

	it("drops the glow on low quality and the glints on medium", function()
		expect(ring("legendary", "low").glow).toBe(false)
		expect(ring("legendary", "low").sparkle).toBe(false)
		expect(ring("legendary", "medium").glow).toBe(true)
		expect(ring("legendary", "medium").sparkle).toBe(false)
		expect(ring("uncommon", "low") ~= nil).toBe(true)
	end)

	it("names rarities the config knows", function()
		expect(TowerMarks.rank(RING.glowFrom, RARITIES)).toBeGreaterThan(0)
		expect(TowerMarks.rank(RING.sparkleFrom, RARITIES)).toBeGreaterThan(0)
	end)
end)

describe("The rarest scoop on a tower", function()
	local byId = {
		a = { rarity = "common" },
		b = { rarity = "epic" },
		c = { rarity = "rare" },
		d = { rarity = "epic" },
	}

	it("finds the rarest, the highest of equals", function()
		expect(TowerMarks.rarest({ "a", "b", "c" }, byId, RARITIES)).toBe(2)
		expect(TowerMarks.rarest({ "b", "a", "d", "c" }, byId, RARITIES)).toBe(3)
		expect(TowerMarks.rarest({ "a", "a" }, byId, RARITIES)).toBe(2)
	end)

	it("is nil for an empty tower or unknown flavors", function()
		expect(TowerMarks.rarest({}, byId, RARITIES)).toBeNil()
		expect(TowerMarks.rarest({ "zzz" }, byId, RARITIES)).toBeNil()
	end)

	it("writes the rarity in capitals before the name", function()
		expect(TowerMarks.tagText("epic", "Tiramisu")).toBe("EPIC Tiramisu")
	end)
end)

describe("Aiming at a tower's column", function()
	-- a tower from (10, 0, 0) up to (10, 20, 0); looking along +X from the origin at height y
	local function hit(y: number, z: number?, maxDistance: number?)
		return TowerMarks.rayHitsColumn(0, y, z or 0, 1, 0, 0, 10, 0, 0, 10, 20, 0, 1.3, maxDistance or 100)
	end

	it("hits it from the side at its distance", function()
		expect(hit(5)).toBeCloseTo(10, 1e-6)
		expect(hit(5, 1.2)).toBeCloseTo(10, 1e-6)
	end)

	it("misses beside it, above it, behind the origin and past the distance", function()
		expect(hit(5, 1.5)).toBeNil()
		expect(hit(22)).toBeNil()
		expect(hit(5, 0, 8)).toBeNil()
		expect(TowerMarks.rayHitsColumn(20, 5, 0, 1, 0, 0, 10, 0, 0, 10, 20, 0, 1.3, 100)).toBeNil()
	end)

	it("hits it when looking down along it", function()
		local along = TowerMarks.rayHitsColumn(10, 30, 0, 0, -1, 0, 10, 0, 0, 10, 20, 0, 1.3, 100)
		expect(along).toBeCloseTo(10, 1e-6)
	end)
end)
