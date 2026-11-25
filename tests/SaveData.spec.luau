local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local SaveData = require("../src/shared/SaveData")
local UpgradesConfig = require("../src/shared/Config/Upgrades")

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
		local _, changed = SaveData.migrate(SaveData.template(), UpgradesConfig)
		expect(changed).toBe(false)
	end)
end)

describe("Save: loading old or broken data", function()
	it("nothing or garbage becomes a fresh save", function()
		for _, raw in { nil, 42, "x", true } do
			local data, changed = SaveData.migrate(raw, UpgradesConfig)
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
		}, UpgradesConfig)
		expect(changed).toBe(true)
		expect(data.coins).toBe(1234.5)
		-- an old cone level 2 held 36 scoops: the shop's first level with at least that (20 + 16 = 36)
		expect(data.upgrades.cone).toBe(16)
		expect(data.upgrades.sneakers).toBe(0)
		-- an old cart level beyond the top counts as the old top (x1.6): the shop's level 15 gives x1.6
		expect(data.upgrades.cart).toBe(15)
		expect(data.flavorServes.vanilla).toBe(3)
		expect(data.flavorServes.mint).toBeNil()
		expect(data.flavorServes.chili).toBe(2)
		expect(data.scoopsServed).toBe(0)
		expect(data.bestTower).toBe(17)
	end)

	it("never lets coins be negative or infinite", function()
		expect(SaveData.migrate({ coins = -5 }, UpgradesConfig).coins).toBe(0)
		expect(SaveData.migrate({ coins = math.huge }, UpgradesConfig).coins).toBe(0)
	end)

	it("fills fields a save is missing, without touching the others", function()
		local data = SaveData.migrate({ version = 1, coins = 50 }, UpgradesConfig)
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
		}, UpgradesConfig)
		expect(changed).toBe(true)
		expect(data.version).toBe(SaveData.VERSION)
		expect(type(data.settings)).toBe("table")
		expect(next(data.settings)).toBeNil()
		expect(data.coins).toBe(77)
		-- old cart level 2 gave x1.25: lifted to the shop's first level with at least that (x1.28, level 7)
		expect(data.upgrades.cart).toBe(7)
		expect(data.upgrades.cone).toBe(8) -- old level 1 held 28: 20 + 8
		expect(data.flavorServes.vanilla).toBe(5)
	end)

	it("settings a save already has survive the migration", function()
		local data = SaveData.migrate({ version = 1, settings = { fov = 95 } }, UpgradesConfig)
		expect(data.settings.fov).toBe(95)
	end)

	it("a save from a newer game version keeps its unknown fields", function()
		local data =
			SaveData.migrate({ version = SaveData.VERSION + 1, coins = 10, futureField = "keep" }, UpgradesConfig)
		expect(data.version).toBe(SaveData.VERSION)
		expect(data.coins).toBe(10)
		expect((data :: any).futureField).toBe("keep")
	end)

	it("flavors that left the game stay in the save", function()
		local data = SaveData.migrate({ flavorServes = { retiredFlavor = 4 } }, UpgradesConfig)
		expect(data.flavorServes.retiredFlavor).toBe(4)
	end)

	it("level limits follow the upgrade config", function()
		expect(SaveData.maxLevel("cone", UpgradesConfig)).toBe(UpgradesConfig.tracks.cone.maxLevel)
		expect(SaveData.maxLevel("sneakers", UpgradesConfig)).toBe(UpgradesConfig.legacy.sneakers)
		expect(SaveData.maxLevel("unknown", UpgradesConfig)).toBe(0)
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
		local _, changed = SaveData.migrate(data, UpgradesConfig)
		expect(changed).toBe(false)
	end)
end)

describe("Save: the Scoop Chest (version 3)", function()
	it("a version 2 save gets an empty chest and keeps everything else", function()
		local data, changed = SaveData.migrate({ version = 2, coins = 120, settings = { fov = 80 } }, UpgradesConfig)
		expect(changed).toBe(true)
		expect(data.version).toBe(SaveData.VERSION)
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
		local _, changed = SaveData.migrate(data, UpgradesConfig)
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
		local _, changed = SaveData.migrate(data, UpgradesConfig)
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
		SaveData.migrate(data, UpgradesConfig)
		expect(#data.chest.equipped).toBe(3)
		expect(data.chest.equipped[1]).toBe("a|")
		expect(data.chest.equipped[2]).toBe("b|")
		expect(data.chest.equipped[3]).toBe("c|")
	end)

	it("a flavor that left the game stays in the chest", function()
		local data = SaveData.template()
		data.chest.items = { { flavor = "old_flavor", rarity = "epic", mutation = "", count = 4 } }
		SaveData.migrate(data, UpgradesConfig)
		expect(data.chest.items[1].count).toBe(4)
	end)

	it("a chest that is not a table becomes an empty one", function()
		local data = SaveData.template() :: any
		data.chest = "x"
		local _, changed = SaveData.migrate(data, UpgradesConfig)
		expect(changed).toBe(true)
		expect(#data.chest.items).toBe(0)
	end)
end)

describe("Save: the upgrade shop (version 4)", function()
	local Upgrades = require("../src/shared/Upgrades")

	it("a version 3 save gets every new upgrade at 0 and keeps the rest", function()
		local data, changed = SaveData.migrate({
			version = 3,
			coins = 500,
			upgrades = { cone = 0, sneakers = 0, cart = 0 },
			settings = {},
			chest = { items = {}, equipped = {} },
		}, UpgradesConfig)
		expect(changed).toBe(true)
		expect(data.version).toBe(4)
		expect(data.coins).toBe(500)
		for id in UpgradesConfig.tracks do
			expect(data.upgrades[id]).toBe(0)
		end
		expect(data.upgrades.sneakers).toBe(0)
	end)

	it("old cone and cart levels become the first shop level worth at least as much", function()
		-- before: cone capacity 20, 28, 36, 45, 55, 65 and cart x1, 1.12, 1.25, 1.38, 1.5, 1.6
		local old = { 28, 36, 45, 55, 65 }
		local oldCart = { 1.12, 1.25, 1.38, 1.5, 1.6 }
		for level = 1, 5 do
			local data = SaveData.migrate({ version = 3, upgrades = { cone = level, cart = level } }, UpgradesConfig)
			local capacity = Upgrades.value("cone", data.upgrades.cone, UpgradesConfig)
			local top = Upgrades.value("cone", UpgradesConfig.tracks.cone.maxLevel, UpgradesConfig)
			expect(capacity >= math.min(old[level], top)).toBe(true)
			local multiplier = Upgrades.value("cart", data.upgrades.cart, UpgradesConfig)
			expect(multiplier >= oldCart[level] - 1e-9).toBe(true)
		end
	end)

	it("old sneakers levels go back to 0: walking speed is not an upgrade", function()
		local data = SaveData.migrate({ version = 3, upgrades = { cone = 0, sneakers = 2, cart = 0 } }, UpgradesConfig)
		expect(data.upgrades.sneakers).toBe(0)
	end)

	it("a version 4 save is not lifted a second time", function()
		local data = SaveData.template()
		data.upgrades.cone = 2
		data.upgrades.cart = 2
		local _, changed = SaveData.migrate(data, UpgradesConfig)
		expect(changed).toBe(false)
		expect(data.upgrades.cone).toBe(2)
		expect(data.upgrades.cart).toBe(2)
	end)

	it("levels beyond the top or broken ones are repaired", function()
		local data = SaveData.migrate({
			version = 4,
			upgrades = { luck = 999, stability = -2, slots = 0 / 0, sprinkles = 1.7 },
		}, UpgradesConfig)
		expect(data.upgrades.luck).toBe(UpgradesConfig.tracks.luck.maxLevel)
		expect(data.upgrades.stability).toBe(0)
		expect(data.upgrades.slots).toBe(0)
		expect(data.upgrades.sprinkles).toBe(1)
	end)

	it("the equipped scoops kept follow the Equip Slots level", function()
		local function withFive(slotsLevel: number)
			local data = SaveData.template()
			data.upgrades.slots = slotsLevel
			for _, flavor in { "a", "b", "c", "d", "e" } do
				table.insert(data.chest.items, { flavor = flavor, rarity = "rare", mutation = "", count = 1 })
				table.insert(data.chest.equipped, flavor .. "|")
			end
			SaveData.migrate(data, UpgradesConfig)
			return data
		end
		expect(SaveData.equipSlots(SaveData.template(), UpgradesConfig)).toBe(3)
		expect(#withFive(0).chest.equipped).toBe(3)
		expect(#withFive(2).chest.equipped).toBe(5)
		expect(SaveData.equipSlots(withFive(3), UpgradesConfig)).toBe(6)
	end)

	it("a purchase is saved and loads back unchanged", function()
		local data = SaveData.template()
		data.coins = 10000
		expect((Upgrades.buy(data, "cone", 0, UpgradesConfig))).toBe(true)
		expect((Upgrades.buy(data, "luck", 0, UpgradesConfig))).toBe(true)
		-- what ProfileStore writes is the table itself; loading it runs migrate again
		local loaded, changed = SaveData.migrate(data, UpgradesConfig)
		expect(changed).toBe(false)
		expect(loaded.upgrades.cone).toBe(1)
		expect(loaded.upgrades.luck).toBe(1)
		expect(loaded.coins).toBe(
			10000 - Upgrades.cost("cone", 0, UpgradesConfig) - Upgrades.cost("luck", 0, UpgradesConfig)
		)
	end)

	it("one call resets every upgrade (for the rebirth); the chest keeps its scoops", function()
		local data = SaveData.template()
		for id in UpgradesConfig.tracks do
			data.upgrades[id] = UpgradesConfig.tracks[id].maxLevel
		end
		data.upgrades.sneakers = 2
		data.coins = 42
		for _, flavor in { "a", "b", "c", "d", "e", "f" } do
			table.insert(data.chest.items, { flavor = flavor, rarity = "rare", mutation = "", count = 1 })
			table.insert(data.chest.equipped, flavor .. "|")
		end
		expect(SaveData.resetUpgrades(data, UpgradesConfig)).toBe(true)
		for _, level in data.upgrades do
			expect(level).toBe(0)
		end
		expect(#data.chest.equipped).toBe(3) -- back to the start's slots
		expect(#data.chest.items).toBe(6) -- nothing taken out of the chest
		expect(data.coins).toBe(42) -- coins are the rebirth's business, not this call's
		expect(SaveData.resetUpgrades(data, UpgradesConfig)).toBe(false)
		local _, changed = SaveData.migrate(data, UpgradesConfig)
		expect(changed).toBe(false)
	end)
end)
