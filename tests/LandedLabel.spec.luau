local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Loot = require("../src/shared/Loot")
local LootConfig = require("../src/shared/Config/Loot")
local ScoopLabel = require("../src/shared/ScoopLabel")
local Flavors = require("../src/shared/Config/Flavors")
local Economy = require("../src/shared/Config/Economy")

describe("Landed scoops from the Big Swirl", function()
	local landedAt = 100
	local scoop = Loot.landed("vanilla", landedAt, 6, LootConfig)

	it("lie three seconds, set in the config", function()
		expect(LootConfig.landedLifetime).toBe(3)
		expect(scoop.endAt).toBe(landedAt + 3)
		expect(scoop.rule.expiresAt).toBe(landedAt + 3)
	end)

	it("anybody may pick one up as soon as it lies there, until it is gone", function()
		for _, userId in { 1, 42, 999 } do
			expect((Loot.canCollect(scoop.rule, userId, landedAt))).toBe(true)
			expect((Loot.canCollect(scoop.rule, userId, landedAt + 2.9))).toBe(true)
			local ok, reason = Loot.canCollect(scoop.rule, userId, landedAt + 3)
			expect(ok).toBe(false)
			expect(reason).toBe("gone")
		end
		expect((Loot.canCollect(scoop.rule, 1, landedAt - 0.1))).toBe(false) -- not down yet
	end)

	it("stay where they came down: no fall, no roll, on the ground", function()
		for _, elapsed in { 0, LootConfig.fallTime, 1, 2.5 } do
			-- elapsed since its path starts (t0): it is down at fallTime and stays put after that
			local x, y, z = Loot.position(scoop.path, LootConfig.fallTime + elapsed, LootConfig)
			expect(x).toBe(0)
			expect(y).toBe(0)
			expect(z).toBe(0)
		end
		expect(Loot.groundHeight(scoop.profile, 1)).toBe(6)
		expect(scoop.profile.sinkAt).toBeNil()
	end)

	it("blink only in the last second, then go", function()
		expect(Loot.blinks(scoop.endAt, landedAt + 1.9, true, false, LootConfig)).toBe(false)
		expect(Loot.blinks(scoop.endAt, landedAt + 2.1, true, false, LootConfig)).toBe(true)
		expect(Loot.blinks(scoop.endAt, landedAt + 3, true, false, LootConfig)).toBe(false)
	end)

	it("spilled scoops blink as before, sinking ones not at all", function()
		local endAt = 50
		expect(Loot.blinks(endAt, endAt - LootConfig.blinkSeconds + 0.1, false, false, LootConfig)).toBe(true)
		expect(Loot.blinks(endAt, endAt - LootConfig.blinkSeconds - 0.1, false, false, LootConfig)).toBe(false)
		expect(Loot.blinks(endAt, endAt - 0.5, false, true, LootConfig)).toBe(false)
	end)

	it("have their own limit: the oldest landed one goes, spilled scoops are not touched", function()
		expect(Loot.landedRoom(LootConfig.maxLanded - 1, LootConfig)).toBe(0)
		expect(Loot.landedRoom(LootConfig.maxLanded, LootConfig)).toBe(1)
		-- spilled scoops keep their own numbers
		expect(LootConfig.lifetime).toBe(12)
		expect(LootConfig.blinkSeconds).toBe(2)
	end)
end)

describe("The name sign over a scoop", function()
	local function text(id: string, golden: boolean?)
		return ScoopLabel.text(Flavors.byId[id], golden == true, Flavors, Economy)
	end

	it("name and value in coins", function()
		local label = text("vanilla")
		expect(label.name).toBe("Vanilla")
		expect(label.value).toBe("5")
		expect(label.color).toBe(Flavors.rarityColors.common)
	end)

	it("the name in the colour of its rarity", function()
		expect(text("rocky_road").color).toBe(Flavors.rarityColors.uncommon)
		expect(text("mochi").color).toBe(Flavors.rarityColors.rare)
		expect(text("chili_lava").color).toBe(Flavors.rarityColors.epic)
		expect(text("cursed_pickle").color).toBe(Flavors.rarityColors.legendary)
		expect(text("rocky_road").value).toBe("7.5")
	end)

	it("a golden scoop says so, in gold, with its real value", function()
		local label = text("vanilla", true)
		expect(label.name).toBe("Golden Vanilla")
		expect(label.value).toBe(tostring(5 * Economy.goldenMultiplier))
		expect(label.color).toBe(Flavors.rarityColors.golden)
		expect(text("rocky_road", true).value).toBe("37.5")
	end)

	it("every rarity has a colour", function()
		for _, flavor in Flavors.list do
			expect(Flavors.rarityColors[flavor.rarity] ~= nil).toBe(true)
		end
	end)
end)
