local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local FlavorOdds = require("../src/shared/FlavorOdds")
local Flavors = require("../src/shared/Config/Flavors")

local function real(flavor): boolean
	return not flavor.placeholder
end

local pools = FlavorOdds.pools(Flavors.list, real)

local function count(rarity: string): number
	return if pools[rarity] then #pools[rarity] else 0
end

describe("the flavors (18.11.2026)", function()
	it("has 11 common, 11 uncommon and 10 each of rare, epic and legendary, no mythic, secret or divine yet", function()
		expect(count("common")).toBe(11)
		expect(count("uncommon")).toBe(11)
		expect(count("rare")).toBe(10)
		expect(count("epic")).toBe(10)
		expect(count("legendary")).toBe(10)
		expect(count("mythic")).toBe(0)
		expect(count("secret")).toBe(0)
		expect(count("divine")).toBe(0)
	end)

	it("is worth the base value times its rarity's factor (x1, x2, x4, x10, x30)", function()
		local factors = { common = 1, uncommon = 2, rare = 4, epic = 10, legendary = 30 }
		for _, flavor in Flavors.list do
			if real(flavor) then
				expect(flavor.value).toBe(Flavors.baseValue * factors[flavor.rarity])
				expect(Flavors.valueFactors[flavor.rarity]).toBe(factors[flavor.rarity])
			end
		end
		expect(Flavors.valueFactors.mythic).toBe(100)
		expect(Flavors.valueFactors.secret).toBe(500)
		expect(Flavors.valueFactors.divine).toBe(1500)
	end)

	it("has a name colour for every rarity", function()
		for _, rarity in Flavors.rarities do
			expect(Flavors.rarityColors[rarity] ~= nil).toBe(true)
		end
	end)
end)

describe("the Big Swirl's odds", function()
	it("are the catalogue's chances and add up to 100 %", function()
		local sum = 0
		for _, rarity in Flavors.rarities do
			sum += Flavors.rarityChances[rarity]
		end
		expect(sum).toBeCloseTo(100)
		expect(Flavors.rarityChances.common).toBe(50.94)
		expect(Flavors.rarityChances.uncommon).toBe(25)
		expect(Flavors.rarityChances.rare).toBe(12)
		expect(Flavors.rarityChances.epic).toBe(7)
		expect(Flavors.rarityChances.legendary).toBe(3.5)
	end)

	it("give the share of rarities without flavors to common, still 100 % in all", function()
		local chances = FlavorOdds.chances(Flavors, pools)
		expect(chances.common).toBeCloseTo(50.94 + 1.5 + 0.05 + 0.01)
		expect(chances.mythic).toBe(0)
		expect(chances.legendary).toBe(3.5)
		local sum, flavorSum = 0, 0
		for _, rarity in Flavors.rarities do
			sum += chances[rarity]
		end
		for _, flavor in Flavors.list do
			flavorSum += FlavorOdds.flavorChance(flavor.id, Flavors, pools)
		end
		expect(sum).toBeCloseTo(100)
		expect(flavorSum).toBeCloseTo(100)
	end)

	it("splits a rarity evenly between its flavors", function()
		expect(FlavorOdds.flavorChance("cherry", Flavors, pools)).toBeCloseTo(25 / 11)
		expect(FlavorOdds.flavorChance("tiramisu", Flavors, pools)).toBeCloseTo(0.7)
		expect(FlavorOdds.flavorChance("royal_cream", Flavors, pools)).toBeCloseTo(0.35)
		expect(FlavorOdds.flavorChance("blue_moon", Flavors, pools)).toBe(0) -- a placeholder, never fired
	end)

	it("picks by the rolls: low rolls common, the last few percent legendary", function()
		expect(Flavors.byId[FlavorOdds.pick(0, 0, Flavors, pools)].rarity).toBe("common")
		expect(Flavors.byId[FlavorOdds.pick(0.5, 0, Flavors, pools)].rarity).toBe("common")
		expect(Flavors.byId[FlavorOdds.pick(0.53, 0, Flavors, pools)].rarity).toBe("uncommon")
		expect(Flavors.byId[FlavorOdds.pick(0.97, 0.5, Flavors, pools)].rarity).toBe("legendary")
		expect(Flavors.byId[FlavorOdds.pick(0.9999, 0.9999, Flavors, pools)].rarity).toBe("legendary")
	end)

	it("comes out at the chances over many evenly spread rolls", function()
		local seen: { [string]: number } = {}
		local steps = 20000
		for i = 0, steps - 1 do
			local id = FlavorOdds.pick((i + 0.5) / steps, ((i * 7919) % steps + 0.5) / steps, Flavors, pools)
			local rarity = Flavors.byId[id].rarity
			seen[rarity] = (seen[rarity] or 0) + 1
		end
		local chances = FlavorOdds.chances(Flavors, pools)
		for _, rarity in Flavors.rarities do
			expect(math.abs((seen[rarity] or 0) / steps * 100 - chances[rarity]) < 0.05).toBe(true)
		end
	end)
end)
