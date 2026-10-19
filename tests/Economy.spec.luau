local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Economy = require("../src/shared/Economy")
local Recipes = require("../src/shared/Recipes")
local Config = require("../src/shared/Config/Economy")
local Flavors = require("../src/shared/Config/Flavors")
local RecipeConfig = require("../src/shared/Config/Recipes")

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

		local party = { "cursed_pickle", "chili_lava", "cursed_pickle" }
		local partyStacks = Recipes.findStacks(party, RecipeConfig.secretStacks)
		local partyPlain = Economy.serveValue(party, Flavors.byId, Config)
		expect(Economy.serveValue(party, Flavors.byId, Config, { stacks = partyStacks }) / partyPlain).toBeCloseTo(2)
	end)

	it("keeps the bottom 30 % (at least 2) when a tower topples", function()
		expect(Economy.keepOnTopple(0, Config)).toBe(0)
		expect(Economy.keepOnTopple(1, Config)).toBe(1)
		expect(Economy.keepOnTopple(5, Config)).toBe(2)
		expect(Economy.keepOnTopple(10, Config)).toBe(3)
		expect(Economy.keepOnTopple(37, Config)).toBe(11)
	end)

	it("slows players down with height, never below the minimum", function()
		local empty = Economy.walkSpeed(0, 0, Config)
		expect(empty).toBe(Config.baseWalkSpeed)
		expect(Economy.walkSpeed(20, 0, Config)).toBeLessThan(empty)
		expect(Economy.walkSpeed(500, 0, Config)).toBe(Config.minWalkSpeed)
		expect(Economy.walkSpeed(20, 5, Config)).toBeGreaterThan(Economy.walkSpeed(20, 0, Config))
	end)

	it("speeds sprinting players up by the sprint multiplier, at every height", function()
		for _, count in { 0, 10, 500 } do
			local walk = Economy.walkSpeed(count, 0, Config)
			expect(Economy.walkSpeed(count, 0, Config, true)).toBeCloseTo(walk * Config.sprintMultiplier)
			expect(Economy.walkSpeed(count, 0, Config, false)).toBe(walk)
		end
	end)

	it("has strictly rising upgrade costs and effects", function()
		for _, track in { "cone", "sneakers", "cart" } do
			local costs = Config.upgrades[track].costs
			for index = 2, #costs do
				expect(costs[index]).toBeGreaterThan(costs[index - 1])
			end
			expect(Economy.upgradeCost(track, #costs, Config)).toBeNil()
		end
		for upgradeLevel = 1, 5 do
			expect(Economy.capacity(upgradeLevel, Config)).toBeGreaterThan(Economy.capacity(upgradeLevel - 1, Config))
			expect(Economy.coneStiffness(upgradeLevel, Config)).toBeGreaterThan(
				Economy.coneStiffness(upgradeLevel - 1, Config)
			)
			expect(Economy.serveMultiplier(upgradeLevel, Config)).toBeGreaterThan(
				Economy.serveMultiplier(upgradeLevel - 1, Config)
			)
		end
	end)

	it("clamps out-of-range upgrade levels", function()
		expect(Economy.capacity(-3, Config)).toBe(Config.upgrades.cone.capacity[1])
		expect(Economy.capacity(99, Config)).toBe(Config.upgrades.cone.capacity[#Config.upgrades.cone.capacity])
	end)

	it("lets the first serve buy the first sneakers", function()
		local firstServe = Economy.serveValue(stack("vanilla", 3), Flavors.byId, Config)
		expect(firstServe).toBeGreaterThan(Config.upgrades.sneakers.costs[1])
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
		local tower = { "rocky_road", "rocky_road", "mochi", "rocky_road", "rocky_road", "mochi" }
		expect(#Recipes.findStacks(tower, RecipeConfig.secretStacks)).toBe(2)
		local overlapping = { "cursed_pickle", "chili_lava", "cursed_pickle", "chili_lava", "cursed_pickle" }
		expect(#Recipes.findStacks(overlapping, RecipeConfig.secretStacks)).toBe(1)
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
		expect(#Flavors.list).toBe(10)
	end)
end)
