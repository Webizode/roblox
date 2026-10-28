local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local SaveData = require("../src/shared/SaveData")
local Economy = require("../src/shared/Config/Economy")

describe("Save: a new player", function()
	it("starts with nothing, at the current version", function()
		local data = SaveData.template()
		expect(data.version).toBe(SaveData.VERSION)
		expect(data.coins).toBe(0)
		expect(data.upgrades.cone).toBe(0)
		expect(data.upgrades.sneakers).toBe(0)
		expect(data.upgrades.cart).toBe(0)
		expect(data.scoopsServed).toBe(0)
		expect(data.bestTower).toBe(0)
		expect(SaveData.flavorsCollected(data)).toBe(0)
	end)

	it("every template is a fresh table", function()
		local a, b = SaveData.template(), SaveData.template()
		a.upgrades.cone = 3
		a.flavorServes.vanilla = 1
		expect(b.upgrades.cone).toBe(0)
		expect(b.flavorServes.vanilla).toBeNil()
	end)

	it("a clean template needs no repair", function()
		local _, changed = SaveData.migrate(SaveData.template(), Economy)
		expect(changed).toBe(false)
	end)
end)

describe("Save: loading old or broken data", function()
	it("nothing or garbage becomes a fresh save", function()
		for _, raw in { nil, 42, "x", true } do
			local data, changed = SaveData.migrate(raw, Economy)
			expect(changed).toBe(true)
			expect(data.version).toBe(SaveData.VERSION)
			expect(data.coins).toBe(0)
			expect(data.upgrades.cart).toBe(0)
		end
	end)

	it("keeps what is valid and repairs only what is broken", function()
		local data, changed = SaveData.migrate({
			version = 1,
			coins = 1234.5,
			upgrades = { cone = 2, sneakers = -1, cart = 99 },
			flavorServes = { vanilla = 3, mint = 0, chili = 2.7 },
			scoopsServed = 0 / 0,
			bestTower = 17,
		}, Economy)
		expect(changed).toBe(true)
		expect(data.coins).toBe(1234.5)
		expect(data.upgrades.cone).toBe(2)
		expect(data.upgrades.sneakers).toBe(0)
		expect(data.upgrades.cart).toBe(SaveData.maxLevel("cart", Economy))
		expect(data.flavorServes.vanilla).toBe(3)
		expect(data.flavorServes.mint).toBeNil()
		expect(data.flavorServes.chili).toBe(2)
		expect(data.scoopsServed).toBe(0)
		expect(data.bestTower).toBe(17)
	end)

	it("never lets coins be negative or infinite", function()
		expect(SaveData.migrate({ coins = -5 }, Economy).coins).toBe(0)
		expect(SaveData.migrate({ coins = math.huge }, Economy).coins).toBe(0)
	end)

	it("fills fields a save is missing, without touching the others", function()
		local data = SaveData.migrate({ version = 1, coins = 50 }, Economy)
		expect(data.coins).toBe(50)
		expect(data.upgrades.cone).toBe(0)
		expect(data.scoopsServed).toBe(0)
		expect(type(data.flavorServes)).toBe("table")
	end)

	it("a version 1 save moves to version 2 with empty settings and keeps its progress", function()
		local data, changed = SaveData.migrate({
			version = 1,
			coins = 77,
			upgrades = { cone = 1, sneakers = 0, cart = 2 },
			flavorServes = { vanilla = 5 },
			scoopsServed = 5,
			bestTower = 5,
		}, Economy)
		expect(changed).toBe(true)
		expect(data.version).toBe(2)
		expect(type(data.settings)).toBe("table")
		expect(next(data.settings)).toBeNil()
		expect(data.coins).toBe(77)
		expect(data.upgrades.cart).toBe(2)
		expect(data.flavorServes.vanilla).toBe(5)
	end)

	it("settings a save already has survive the migration", function()
		local data = SaveData.migrate({ version = 1, settings = { fov = 95 } }, Economy)
		expect(data.settings.fov).toBe(95)
	end)

	it("a save from a newer game version keeps its unknown fields", function()
		local data = SaveData.migrate({ version = SaveData.VERSION + 1, coins = 10, futureField = "keep" }, Economy)
		expect(data.version).toBe(SaveData.VERSION)
		expect(data.coins).toBe(10)
		expect((data :: any).futureField).toBe("keep")
	end)

	it("flavors that left the game stay in the save", function()
		local data = SaveData.migrate({ flavorServes = { retiredFlavor = 4 } }, Economy)
		expect(data.flavorServes.retiredFlavor).toBe(4)
	end)

	it("level limits follow the upgrade config", function()
		expect(SaveData.maxLevel("cone", Economy)).toBe(#Economy.upgrades.cone.costs)
		expect(SaveData.maxLevel("unknown", Economy)).toBe(0)
	end)
end)

describe("Save: serving", function()
	it("adds coins, scoops, flavors and the record", function()
		local data = SaveData.template()
		SaveData.recordServe(data, { "vanilla", "vanilla", "mint" }, 40.5)
		expect(data.coins).toBe(40.5)
		expect(data.scoopsServed).toBe(3)
		expect(data.bestTower).toBe(3)
		expect(data.flavorServes.vanilla).toBe(2)
		expect(data.flavorServes.mint).toBe(1)
		expect(SaveData.flavorsCollected(data)).toBe(2)

		SaveData.recordServe(data, { "chili" }, 5)
		expect(data.coins).toBe(45.5)
		expect(data.scoopsServed).toBe(4)
		expect(data.bestTower).toBe(3) -- the record only goes up
		expect(SaveData.flavorsCollected(data)).toBe(3)
	end)

	it("ignores a broken coin value but still counts the scoops", function()
		local data = SaveData.template()
		SaveData.recordServe(data, { "vanilla" }, 0 / 0)
		SaveData.recordServe(data, { "vanilla" }, -10)
		expect(data.coins).toBe(0)
		expect(data.scoopsServed).toBe(2)
	end)

	it("a served save still loads unchanged", function()
		local data = SaveData.template()
		SaveData.recordServe(data, { "vanilla", "mint" }, 12)
		local _, changed = SaveData.migrate(data, Economy)
		expect(changed).toBe(false)
	end)
end)
