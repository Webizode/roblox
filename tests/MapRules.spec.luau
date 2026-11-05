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

	it("the barrier over the arena rim only stops players: balls fly through it, the rim itself stops them", function()
		expect(MapRules.playersOnly("Sperre", Config)).toBe(true)
		expect(MapRules.blocksThrow("Sperre", "Sperre_RandWand_01a", true, Config)).toBe(false)
		expect(MapRules.playersOnly("Dekoracje", Config)).toBe(false)
		expect(MapRules.blocksThrow("Dekoracje", "Collision", true, Config)).toBe(true)
		expect(MapRules.playersOnly(nil, Config)).toBe(false)
	end)
end)

describe("Map: cover box", function()
	local half = { 6, 2.5, 1.95 }

	it("leaves a box alone that covers the meshes, also when they are a hair larger", function()
		local centre, size = MapRules.coverBoxFit(half, { min = { -6.2, -2.5, -2.1 }, max = { 6.2, 2.6, 2.1 } }, Config)
		expect(centre).toBe(nil)
		expect(size).toBe(nil)
	end)

	it("grows the box to meshes resized on their own, keeping what the box already covered", function()
		local centre, size =
			MapRules.coverBoxFit(half, { min = { -9.6, -2.5, -3.12 }, max = { 9.6, 5.5, 3.12 } }, Config)
		assert(centre and size, "box must grow")
		expect(size[1]).toBe(19.2)
		expect(size[2]).toBe(8)
		expect(size[3]).toBe(6.24)
		expect(centre[1]).toBe(0)
		expect(centre[2]).toBe(1.5) -- the meshes grew upwards only: the box keeps its bottom
		expect(centre[3]).toBe(0)
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
		expect(MapRules.landingSurface(MapRules.terrain, "Terrain", 1, Config)).toBe(true)
	end)

	it("a part outside the map is never ground (a pillar copied into Workspace instead of Covery)", function()
		expect(MapRules.landingSurface(nil, "Collision", 1, Config)).toBe(false)
	end)

	it(
		"roofs, palms, lamps, lollipops, bushes, the fence, the cover, the rim, the barrier and the machine are not",
		function()
			for _, folder in
				{
					"Stoiska",
					"Covery",
					"Palmy",
					"Latarnie",
					"Lizaki",
					"Trawa",
					"Plot",
					"Dekoracje",
					"Sperre",
					"BigSwirl",
				}
			do
				expect(MapRules.landingSurface(folder, "Part", 1, Config)).toBe(false)
			end
		end
	)

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

-- The bug of 05.11.2026: a Watermelon from the Big Swirl lay on top of an Ice Cream Pillar, out of reach. A small map
-- with the arena floor (y 1.2), the pillar at (-71.3, 9.1) (its Collision box 8.4 x 8.4, top y 20.5, in Covery) and
-- a stretch of the arena rim (Dekoracje), seen from above the way MapService does: the surface's height when scoops
-- may lie on it (MapRules.landingSurface), nil otherwise.
describe("Map: free scoops settle on free ground", function()
	local FLOOR, PILLAR_TOP = 1.2, 20.5
	local px, pz, half = -71.3, 9.1, 4.2

	local function surface(x: number, z: number): number?
		if math.abs(x - px) <= half and math.abs(z - pz) <= half then
			return if MapRules.landingSurface("Covery", "Collision", 1, Config) then PILLAR_TOP else nil
		end
		if x >= 135 and x <= 140 then -- the rim wall
			return if MapRules.landingSurface("Dekoracje", "Collision", 1, Config) then 10 else nil
		end
		return if MapRules.landingSurface("Plac", "Arena_Boden", 1, Config) then FLOOR else nil
	end

	-- free ground with the footprint round it, like MapService.settle's probe
	local function probe(x: number, z: number): number?
		local foot = Config.landing.footprint
		local y = surface(x, z)
		if not y then
			return nil
		end
		for _, offset in { { foot, 0 }, { -foot, 0 }, { 0, foot }, { 0, -foot } } do
			if not surface(x + offset[1], z + offset[2]) then
				return nil
			end
		end
		return y
	end

	local offsets = MapRules.searchOffsets(Config.landing.settleStep, Config.landing.settleRadius)

	it("searches from the point itself outwards, nearest first", function()
		expect(offsets[1][1]).toBe(0)
		expect(offsets[1][2]).toBe(0)
		for index = 2, #offsets do
			local a, b = offsets[index - 1], offsets[index]
			expect(a[1] * a[1] + a[2] * a[2] <= b[1] * b[1] + b[2] * b[2]).toBe(true)
		end
		local last = offsets[#offsets]
		expect(math.sqrt(last[1] * last[1] + last[2] * last[2]) <= Config.landing.settleRadius).toBe(true)
	end)

	it("a scoop from the Big Swirl on top of the pillar does not rest well there", function()
		expect(MapRules.restsWell(surface(px, pz), PILLAR_TOP, Config)).toBe(false)
	end)

	it("and goes onto the floor right beside the pillar, clear of it", function()
		local x, y, z = MapRules.nearestFree(px, pz, offsets, probe)
		assert(x and y and z, "free ground beside the pillar")
		expect(y).toBe(FLOOR)
		local outside = math.max(math.abs(x - px), math.abs(z - pz)) - half
		expect(outside >= Config.landing.footprint).toBe(true) -- a player can stand beside it and pick it up
		expect(outside <= Config.landing.footprint + Config.landing.settleStep).toBe(true) -- and it is right beside it
	end)

	it("a spilled scoop that ended inside the pillar (its ray found the floor in the box) moves out too", function()
		expect(MapRules.restsWell(surface(px + 1, pz - 2), FLOOR, Config)).toBe(false)
		local x, y, z = MapRules.nearestFree(px + 1, pz - 2, offsets, probe)
		assert(x and y and z, "free ground beside the pillar")
		expect(y).toBe(FLOOR)
		expect(math.max(math.abs(x - px), math.abs(z - pz)) > half).toBe(true)
	end)

	it("a scoop on the floor next to the pillar stays where it is", function()
		expect(MapRules.restsWell(surface(px + half + 0.5, pz), FLOOR, Config)).toBe(true)
		expect(MapRules.restsWell(surface(0, 40), FLOOR, Config)).toBe(true)
	end)

	it("a scoop on the arena rim goes onto the floor beside it", function()
		expect(MapRules.restsWell(surface(137.5, 0), 10, Config)).toBe(false)
		local x, y = MapRules.nearestFree(137.5, 0, offsets, probe)
		assert(x and y, "free ground beside the rim")
		expect(y).toBe(FLOOR)
		expect(x < 135 or x > 140).toBe(true)
	end)

	it("nothing free within reach: nil, the caller falls back to the nearest landing spot", function()
		local x = MapRules.nearestFree(0, 0, offsets, function()
			return nil
		end)
		expect(x).toBeNil()
	end)
end)

describe("Map: arena kit cover", function()
	it("knows the kit's cover models by name, numbered copies too, not the rim or the arches", function()
		expect(MapRules.isCoverKit("IcePillar", Config)).toBe(true)
		expect(MapRules.isCoverKit("WaffleCrate", Config)).toBe(true)
		expect(MapRules.isCoverKit("CoverBlock_10", Config)).toBe(true)
		expect(MapRules.isCoverKit("ArenaRimPillar", Config)).toBe(false)
		expect(MapRules.isCoverKit("ArenaEntrance", Config)).toBe(false)
	end)
end)
