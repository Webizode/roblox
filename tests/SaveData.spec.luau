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

	it("a version 1 save moves up with empty settings (and an empty chest) and keeps its progress", function()
		local data, changed = SaveData.migrate({
			version = 1,
			coins = 77,
			upgrades = { cone = 1, sneakers = 0, cart = 2 },
			flavorServes = { vanilla = 5 },
			scoopsServed = 5,
			bestTower = 5,
		}, Economy)
		expect(changed).toBe(true)
		expect(data.version).toBe(SaveData.VERSION)
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

describe("Save: the Scoop Chest (version 3)", function()
	it("a version 2 save gets an empty chest and keeps everything else", function()
		local data, changed = SaveData.migrate({ version = 2, coins = 120, settings = { fov = 80 } }, Economy, 3)
		expect(changed).toBe(true)
		expect(data.version).toBe(3)
		expect(data.coins).toBe(120)
		expect(data.settings.fov).toBe(80)
		expect(#data.chest.items).toBe(0)
		expect(#data.chest.equipped).toBe(0)
	end)

	it("a clean chest loads unchanged", function()
		local data = SaveData.template()
		data.chest.items = {
			{ flavor = "blue_moon", rarity = "rare", mutation = "", count = 2 },
			{ flavor = "vanilla", rarity = "common", mutation = "golden", count = 1 },
		}
		data.chest.equipped = { "blue_moon|", "vanilla|golden" }
		local _, changed = SaveData.migrate(data, Economy, 3)
		expect(changed).toBe(false)
		expect(#data.chest.items).toBe(2)
		expect(#data.chest.equipped).toBe(2)
	end)

	it("broken stacks go, duplicates merge, counts become whole numbers", function()
		local data = SaveData.template()
		data.chest.items = {
			{ flavor = "blue_moon", rarity = "rare", count = 2.7 }, -- no mutation: ""
			{ flavor = "blue_moon", rarity = "rare", mutation = "", count = 1 },
			{ flavor = "", rarity = "rare", count = 1 },
			{ flavor = "galaxy_grape", rarity = "epic", mutation = "", count = 0 },
			{ flavor = "galaxy_grape", rarity = "epic", mutation = "", count = 0 / 0 },
			"garbage",
		}
		local _, changed = SaveData.migrate(data, Economy, 3)
		expect(changed).toBe(true)
		expect(#data.chest.items).toBe(1)
		expect(data.chest.items[1].mutation).toBe("")
		expect(data.chest.items[1].count).toBe(3)
	end)

	it("equipped keys only for stacks that exist, each once, at most the slots", function()
		local data = SaveData.template()
		data.chest.items = {
			{ flavor = "a", rarity = "rare", mutation = "", count = 1 },
			{ flavor = "b", rarity = "rare", mutation = "", count = 1 },
			{ flavor = "c", rarity = "rare", mutation = "", count = 1 },
			{ flavor = "d", rarity = "rare", mutation = "", count = 1 },
		}
		data.chest.equipped = { "a|", "a|", "gone|", 5, "b|", "c|", "d|" }
		SaveData.migrate(data, Economy, 3)
		expect(#data.chest.equipped).toBe(3)
		expect(data.chest.equipped[1]).toBe("a|")
		expect(data.chest.equipped[2]).toBe("b|")
		expect(data.chest.equipped[3]).toBe("c|")
	end)

	it("a flavor that left the game stays in the chest", function()
		local data = SaveData.template()
		data.chest.items = { { flavor = "old_flavor", rarity = "epic", mutation = "", count = 4 } }
		SaveData.migrate(data, Economy, 3)
		expect(data.chest.items[1].count).toBe(4)
	end)

	it("a chest that is not a table becomes an empty one", function()
		local data = SaveData.template() :: any
		data.chest = "x"
		local _, changed = SaveData.migrate(data, Economy, 3)
		expect(changed).toBe(true)
		expect(#data.chest.items).toBe(0)
	end)
end)
