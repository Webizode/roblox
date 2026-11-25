local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Economy = require("../src/shared/Economy")
local Recipes = require("../src/shared/Recipes")
local Config = require("../src/shared/Config/Economy")
local Upgrades = require("../src/shared/Upgrades")
local UpgradesConfig = require("../src/shared/Config/Upgrades")
local Flavors = require("../src/shared/Config/Flavors")
local RecipeConfig = require("../src/shared/Config/Recipes")

-- a secret stack that exists only in the tests: the whole tower counts double (scope "tower")
local TEST_STACKS = {
	{
		id = "test_party",
		name = "Test Party",
		sequence = { "lemon", "mango", "lemon" },
		effect = { kind = "valueMultiplier", scope = "tower", factor = 2 },
		rumor = "",
	},
}

local function stack(id: string, count: number): { string }
	return table.create(count, id)
end

describe("Economy", function()
	it("grows the serve value quadratically with height", function()
		expect(Economy.serveValue({}, Flavors.byId, Config)).toBe(0)
		-- 10 vanilla: 10 * 5 * (1 + 0.04 * 10)^2 = 98
		expect(Economy.serveValue(stack("vanilla", 10), Flavors.byId, Config)).toBeCloseTo(98)
		-- 20 vanilla: 20 * 5 * 1.8^2 = 324
		expect(Economy.serveValue(stack("vanilla", 20), Flavors.byId, Config)).toBeCloseTo(324)
	end)

	it("makes one more scoop always worth more than the scoop itself", function()
		for count = 1, 60 do
			local before = Economy.serveValue(stack("vanilla", count), Flavors.byId, Config)
			local after = Economy.serveValue(stack("vanilla", count + 1), Flavors.byId, Config)
			expect(after - before).toBeGreaterThan(Flavors.byId.vanilla.value)
		end
	end)

	it("applies steady bonus and serve multiplier", function()
		local base = Economy.serveValue(stack("vanilla", 10), Flavors.byId, Config)
		local boosted = Economy.serveValue(stack("vanilla", 10), Flavors.byId, Config, {
			steadyBonus = 0.25,
			serveMultiplier = 1.6,
		})
		expect(boosted).toBeCloseTo(base * 1.25 * 1.6)
	end)

	it("ignores negative steady claims", function()
		local base = Economy.serveValue(stack("vanilla", 10), Flavors.byId, Config)
		local claimed = Economy.serveValue(stack("vanilla", 10), Flavors.byId, Config, { steadyBonus = -5 })
		expect(claimed).toBeCloseTo(base)
	end)

	it("applies secret stack multipliers to the matched scoops or the whole tower", function()
		local tower = { "mint", "vanilla", "chocolate", "strawberry" }
		local stacks = Recipes.findStacks(tower, RecipeConfig.secretStacks)
		local plain = Economy.serveValue(tower, Flavors.byId, Config)
		local withStack = Economy.serveValue(tower, Flavors.byId, Config, { stacks = stacks })
		-- three of four equal scoops count triple: (5 + 15 + 15 + 15) / 20
		expect(withStack / plain).toBeCloseTo(2.5)

		-- a whole-tower stack (none in the game since the rarer flavors went; this one exists only here)
		local party = { "lemon", "mango", "lemon" }
		local partyStacks = Recipes.findStacks(party, TEST_STACKS)
		expect(#partyStacks).toBe(1)
		local partyPlain = Economy.serveValue(party, Flavors.byId, Config)
		expect(Economy.serveValue(party, Flavors.byId, Config, { stacks = partyStacks }) / partyPlain).toBeCloseTo(2)
	end)

	it(
		"spills all of a tower up to 5 scoops and 60 % (rounded) of a taller one when it topples or is knocked down",
		function()
			expect(Config.spillAllUpTo).toBe(5)
			expect(Config.spillShare).toBe(0.6)
			expect(Economy.keepOnTopple(0, Config)).toBe(0)
			expect(Economy.keepOnTopple(1, Config)).toBe(0)
			expect(Economy.keepOnTopple(5, Config)).toBe(0)
			expect(Economy.keepOnTopple(6, Config)).toBe(2) -- 3.6 spill: 4
			expect(Economy.keepOnTopple(7, Config)).toBe(3) -- 4.2 spill: 4
			expect(Economy.keepOnTopple(10, Config)).toBe(4)
			expect(Economy.keepOnTopple(37, Config)).toBe(15) -- 22.2 spill: 22
			for count = 6, 80 do
				local keep = Economy.keepOnTopple(count, Config)
				expect(keep >= 1 and keep < count).toBe(true) -- above 5 something always stays and something always falls
				expect(math.abs((count - keep) / count - Config.spillShare) <= 0.5 / count + 1e-9).toBe(true)
			end
		end
	)

	it("slows players down by how full the waffle is: a soft curve, 25 % at full, less with sneakers", function()
		local cap = Upgrades.value("cone", 0, UpgradesConfig)
		local empty = Economy.walkSpeed(0, cap, 0, Config)
		expect(empty).toBe(Config.baseWalkSpeed)
		local function slowAt(share: number): number
			return 1 - Economy.walkSpeed(cap * share, cap, 0, Config) / empty
		end
		expect(slowAt(1)).toBeCloseTo(0.25, 1e-9)
		expect(slowAt(0.5)).toBeCloseTo(0.25 * 0.5 ^ 1.5, 1e-9) -- about 9 %
		expect(slowAt(0.25) < 0.04).toBe(true) -- a little tower stays nimble
		-- the same at every cone size: full is full
		local bigCap = Upgrades.value("cone", UpgradesConfig.tracks.cone.maxLevel, UpgradesConfig)
		expect(Economy.walkSpeed(bigCap, bigCap, 0, Config)).toBeCloseTo(Economy.walkSpeed(cap, cap, 0, Config), 1e-9)
		-- more than fits counts as full, never below the minimum
		expect(Economy.walkSpeed(500, cap, 0, Config)).toBeCloseTo(Economy.walkSpeed(cap, cap, 0, Config), 1e-9)
		expect(Economy.walkSpeed(cap, cap, 0, Config) >= Config.minWalkSpeed).toBe(true)
		-- sneakers: faster and a smaller slow-down
		expect(Economy.walkSpeed(cap, cap, 5, Config)).toBeGreaterThan(Economy.walkSpeed(cap, cap, 0, Config))
	end)

	it("speeds sprinting players up by the sprint multiplier, at every height", function()
		local cap = Upgrades.value("cone", 0, UpgradesConfig)
		for _, count in { 0, 10, 500 } do
			local walk = Economy.walkSpeed(count, cap, 0, Config)
			expect(Economy.walkSpeed(count, cap, 0, Config, true)).toBeCloseTo(walk * Config.sprintMultiplier)
			expect(Economy.walkSpeed(count, cap, 0, Config, false)).toBe(walk)
		end
	end)

	it("shortens the dash with the tower: up to 20 % of its distance at a full waffle", function()
		local cap = Upgrades.value("cone", 0, UpgradesConfig)
		expect(Economy.dashScale(0, cap, 0, Config)).toBe(1)
		expect(Economy.dashScale(cap, cap, 0, Config)).toBeCloseTo(0.8, 1e-9)
		expect(Economy.dashScale(cap / 2, cap, 0, Config) > 0.9).toBe(true)
		expect(Economy.dashScale(cap, cap, 5, Config)).toBeGreaterThan(0.8)
	end)

	-- capacity and serve multiplier are shop upgrades since 25.11.2026 (tests/Upgrades.spec); the sneakers are not sold
	it("the Coin Boost multiplies a serve like the old cart did", function()
		local base = Economy.serveValue(stack("vanilla", 10), Flavors.byId, Config)
		local boosted = Economy.serveValue(stack("vanilla", 10), Flavors.byId, Config, {
			serveMultiplier = Upgrades.value("cart", 5, UpgradesConfig),
		})
		expect(Upgrades.value("cart", 5, UpgradesConfig)).toBe(1.2) -- +0.04 a level
		expect(boosted).toBeCloseTo(base * 1.2)
	end)

	it("one tower of ten buys the first upgrade of the shop", function()
		local serve = Economy.serveValue(stack("vanilla", 10), Flavors.byId, Config)
		local cheapest = math.huge
		for _, id in Upgrades.visible(UpgradesConfig) do
			cheapest = math.min(cheapest, Upgrades.cost(id, 0, UpgradesConfig) :: number)
		end
		expect(serve >= cheapest).toBe(true)
	end)
end)

describe("Recipes", function()
	it("finds secret stacks only in exact bottom-to-top order", function()
		local found = Recipes.findStacks({ "vanilla", "chocolate", "strawberry" }, RecipeConfig.secretStacks)
		expect(#found).toBe(1)
		expect(found[1].id).toBe("neapolitan")
		expect(found[1].from).toBe(1)
		expect(found[1].to).toBe(3)
		expect(#Recipes.findStacks({ "strawberry", "chocolate", "vanilla" }, RecipeConfig.secretStacks)).toBe(0)
	end)

	it("counts repeated stacks without overlap", function()
		local tower = { "vanilla", "chocolate", "strawberry", "vanilla", "chocolate", "strawberry" }
		expect(#Recipes.findStacks(tower, RecipeConfig.secretStacks)).toBe(2)
		local overlapping = { "lemon", "mango", "lemon", "mango", "lemon" }
		expect(#Recipes.findStacks(overlapping, TEST_STACKS)).toBe(1)
	end)

	it("resolves churn swirls in either order", function()
		local swirl = Recipes.churnResult("mint", "chocolate", RecipeConfig.swirls)
		expect(swirl and swirl.id).toBe("choco_mint_twist")
		expect(Recipes.churnResult("chocolate", "mint", RecipeConfig.swirls)).toBe(swirl)
		expect(Recipes.churnResult("vanilla", "vanilla", RecipeConfig.swirls)).toBeNil()
	end)

	it("only references flavors that exist", function()
		for _, def in RecipeConfig.secretStacks do
			for _, id in def.sequence do
				expect(Flavors.byId[id] ~= nil).toBe(true)
			end
		end
		for _, def in RecipeConfig.swirls do
			expect(#def.inputs).toBe(2)
			for _, id in def.inputs do
				expect(Flavors.byId[id] ~= nil).toBe(true)
			end
		end
	end)
end)

describe("Flavors", function()
	it("has unique ids, positive values and launcher weights", function()
		local seen = {}
		for _, flavor in Flavors.list do
			expect(seen[flavor.id]).toBeNil()
			seen[flavor.id] = true
			expect(flavor.value).toBeGreaterThan(0)
			expect(flavor.weight).toBeGreaterThan(0)
			expect(flavor.mass).toBeGreaterThan(0)
			expect(string.match(flavor.color, "^#%x%x%x%x%x%x$") ~= nil).toBe(true)
		end
		-- the eleven commons and since 18.11.2026 the 41 rarer flavors up to legendary (FlavorOdds.spec counts them by
		-- rarity); the Scoop Chest's placeholders stay known for old saves
		local real = 0
		for _, flavor in Flavors.list do
			if not flavor.placeholder then
				real += 1
			end
		end
		expect(real).toBe(52)
	end)
end)
