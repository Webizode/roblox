local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local MapRules = require("../src/shared/MapRules")
local Config = require("../src/shared/Config/Map")

describe("Map: throws", function()
	it("solid parts stop a ball, parts without collision never do", function()
		expect(MapRules.blocksThrow("Stoiska", "Part", true, Config)).toBe(true)
		expect(MapRules.blocksThrow("Stoiska", "Part", false, Config)).toBe(false)
		expect(MapRules.blocksThrow(nil, "Part", true, Config)).toBe(true)
	end)

	it("garlands, lamps, lollipops, palm leaves and coconuts let it through, palm trunks stop it", function()
		expect(MapRules.blocksThrow("Latarnie", "Part", true, Config)).toBe(false)
		expect(MapRules.blocksThrow("Lizaki", "Part", true, Config)).toBe(false)
		expect(MapRules.blocksThrow("Girlandy", "Part", true, Config)).toBe(false)
		expect(MapRules.blocksThrow("Palmy", "PalmLeaf", true, Config)).toBe(false)
		expect(MapRules.blocksThrow("Palmy", "Coconut", true, Config)).toBe(false)
		expect(MapRules.blocksThrow("Palmy", "PalmTrunk", true, Config)).toBe(true)
	end)

	it("cover in Covery stops it", function()
		expect(MapRules.blocksThrow("Covery", "Part", true, Config)).toBe(true)
	end)
end)

describe("Map: sea", function()
	it("heights below the water level are sea, the island is not", function()
		expect(MapRules.belowSea(Config.waterLevel - 0.1, Config)).toBe(true)
		expect(MapRules.belowSea(8.4, Config)).toBe(false)
	end)

	it("a root just above the surface is still in the sea, one on the shore rocks is not", function()
		expect(MapRules.inSea(Config.waterLevel + 0.5, Config)).toBe(true)
		expect(MapRules.inSea(-10, Config)).toBe(true) -- on the sea floor
		expect(MapRules.inSea(Config.waterLevel + Config.respawnMargin + 0.5, Config)).toBe(false)
		expect(MapRules.inSea(11.4, Config)).toBe(false) -- standing on the island
	end)
end)

describe("Map: landing spots", function()
	it("flat ground in the open is a landing surface", function()
		expect(MapRules.landingSurface("Plac", "Arena_Obwod", 1, Config)).toBe(true)
		expect(MapRules.landingSurface("Mosty", "Part", 1, Config)).toBe(true)
		expect(MapRules.landingSurface(nil, "Part", 1, Config)).toBe(true)
	end)

	it("roofs, palms, lamps, lollipops, bushes, the fence, the cover and the machine are not", function()
		for _, folder in { "Stoiska", "Covery", "Palmy", "Latarnie", "Lizaki", "Trawa", "Plot", "BigSwirl" } do
			expect(MapRules.landingSurface(folder, "Part", 1, Config)).toBe(false)
		end
	end)

	it("platform railings and knobs are not, the platform deck is", function()
		expect(MapRules.landingSurface("Platformy", "Poręcz_0", 1, Config)).toBe(false)
		expect(MapRules.landingSurface("Platformy", "Gałka", 1, Config)).toBe(false)
		expect(MapRules.landingSurface("Platformy", "Podest", 1, Config)).toBe(true)
	end)

	it("steep surfaces are not", function()
		expect(MapRules.landingSurface("Plac", "Part", 0.5, Config)).toBe(false)
		expect(MapRules.landingSurface("Plac", "Part", Config.landing.minNormalY, Config)).toBe(true)
	end)

	it("a footprint must be complete and flat within maxStep", function()
		expect(MapRules.flatFootprint({ 8.4, 8.4, 8.6, 8.4, 8.5 }, 5, Config)).toBe(true)
		expect(MapRules.flatFootprint({ 8.4, 8.4, nil, 8.4, 8.5 }, 5, Config)).toBe(false)
		-- a railing: the middle ray lands on it, the others on the floor below
		expect(MapRules.flatFootprint({ 12.3, 8.4, 8.4, 8.4, 8.4 }, 5, Config)).toBe(false)
		expect(MapRules.flatFootprint({}, 0, Config)).toBe(false)
	end)

	it("picks the spots within the radius, or the nearest when none is", function()
		local spots = { 0, 5, 0, 10, 5, 0, 30, 5, 0 }
		local near = MapRules.spotsNear(spots, 1, 0, 12)
		expect(#near).toBe(2)
		expect(near[1]).toBe(1)
		expect(near[2]).toBe(2)
		local nearest = MapRules.spotsNear(spots, 26, 0, 1)
		expect(#nearest).toBe(1)
		expect(nearest[1]).toBe(3)
		expect(#MapRules.spotsNear({}, 0, 0, 5)).toBe(0)
	end)
end)
