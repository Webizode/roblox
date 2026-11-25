local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local ScoopChest = require("../src/shared/ScoopChest")
local SaveData = require("../src/shared/SaveData")
local Loot = require("../src/shared/Loot")
local Config = require("../src/shared/Config/Chest")
local Flavors = require("../src/shared/Config/Flavors")
local UpgradesConfig = require("../src/shared/Config/Upgrades")
local LootConfig = require("../src/shared/Config/Loot")
local TowerConfig = require("../src/shared/Config/Tower")

local byId = Flavors.byId
local rarities = Flavors.rarities

local function idsOf(rarity: string): { string }
	local list = {}
	for _, flavor in Flavors.list do
		if flavor.rarity == rarity and not flavor.placeholder then
			table.insert(list, flavor.id)
		end
	end
	assert(#list >= 2, "need two flavors of " .. rarity)
	return list
end

local COMMONS, UNCOMMONS, RARES, EPICS = idsOf("common"), idsOf("uncommon"), idsOf("rare"), idsOf("epic")
local COMMON, COMMON2, UNCOMMON, RARE, EPIC = COMMONS[1], COMMONS[2], UNCOMMONS[1], RARES[1], EPICS[1]

local function empty(): ScoopChest.Chest
	return { items = {}, equipped = {} }
end

-- every flavor already served once: nothing is new
local function allSeen(): { [string]: number }
	local seen = {}
	for _, flavor in Flavors.list do
		seen[flavor.id] = 1
	end
	return seen
end

local function settings(changes: { [string]: any }): ScoopChest.AutoSell
	local result = ScoopChest.defaultAutoSell(rarities, Config)
	for key, value in changes do
		if key == "store" then
			for rarity, on in value do
				result.store[rarity] = on
			end
		else
			(result :: any)[key] = value
		end
	end
	return result
end

describe("Auto Sell: the defaults", function()
	it("store from rare on, sell common and uncommon; golden & rainbow and new flavors stored; 3 per flavor", function()
		local defaults = ScoopChest.defaultAutoSell(rarities, Config)
		expect(defaults.store.common).toBe(false)
		expect(defaults.store.uncommon).toBe(false)
		for _, rarity in { "rare", "epic", "legendary", "mythic", "secret", "divine" } do
			expect(defaults.store[rarity]).toBe(true)
		end
		expect(defaults.keepMutations).toBe(true)
		expect(defaults.keepNew).toBe(true)
		expect(defaults.perFlavor).toBe(3)
	end)

	it("an old save without settings: the migration gives {} and that reads as the defaults", function()
		-- a version 4 save from before Auto Sell (25.11.2026), no autoSell field at all
		local data = SaveData.migrate({
			version = 4,
			coins = 10,
			upgrades = {},
			flavorServes = { [RARE] = 2 },
			chest = { items = {}, equipped = {} },
		}, UpgradesConfig)
		expect(type(data.autoSell)).toBe("table")
		expect(next(data.autoSell)).toBeNil()
		local read = ScoopChest.readAutoSell(data.autoSell, rarities, Config)
		local defaults = ScoopChest.defaultAutoSell(rarities, Config)
		for _, rarity in rarities do
			expect(read.store[rarity]).toBe(defaults.store[rarity])
		end
		expect(read.keepMutations).toBe(true)
		expect(read.keepNew).toBe(true)
		expect(read.perFlavor).toBe(3)
		expect(ScoopChest.readAutoSell(nil, rarities, Config).perFlavor).toBe(3)
		-- a new save has the field too
		expect(type(SaveData.template().autoSell)).toBe("table")
	end)

	it("an old save serves exactly as before for flavors it had: rare up stored, the rest sold", function()
		local seen = allSeen()
		local chest = empty()
		local result = ScoopChest.store(chest, { COMMON, UNCOMMON, RARE, EPIC }, nil, byId, rarities, Config, seen, nil)
		expect(result.kept[1]).toBeNil()
		expect(result.kept[2]).toBeNil()
		expect(result.kept[3]).toBe(true)
		expect(result.kept[4]).toBe(true)
	end)
end)

describe("Auto Sell: store or sell per rarity", function()
	it("a rarity set to store goes in, one set to sell is sold, each on its own", function()
		local seen = allSeen()
		for _, rarity in { "common", "uncommon", "rare", "epic" } do
			local flavor = idsOf(rarity)[1]
			local storeIt = settings({ store = { [rarity] = true } })
			local sellIt = settings({ store = { [rarity] = false } })
			expect(ScoopChest.store(empty(), { flavor }, nil, byId, rarities, Config, seen, storeIt).kept[1]).toBe(true)
			expect(ScoopChest.store(empty(), { flavor }, nil, byId, rarities, Config, seen, sellIt).kept[1]).toBeNil()
		end
	end)

	it("selling the rares leaves the epics stored", function()
		local seen = allSeen()
		local rule = settings({ store = { rare = false } })
		local result = ScoopChest.store(empty(), { RARE, EPIC }, nil, byId, rarities, Config, seen, rule)
		expect(result.kept[1]).toBeNil()
		expect(result.kept[2]).toBe(true)
	end)
end)

describe("Auto Sell: golden & rainbow always stored", function()
	it("on: a golden common goes in although common is set to sell", function()
		local rule = settings({ keepMutations = true })
		local result = ScoopChest.store(empty(), { COMMON }, { "golden" }, byId, rarities, Config, allSeen(), rule)
		expect(result.kept[1]).toBe(true)
		expect(result.stored[1].mutation).toBe("golden")
	end)

	it("off: a mutation follows its rarity (rainbow common sold, rainbow rare stored)", function()
		local rule = settings({ keepMutations = false })
		local result = ScoopChest.store(
			empty(),
			{ COMMON, RARE },
			{ "rainbow", "rainbow" },
			byId,
			rarities,
			Config,
			allSeen(),
			rule
		)
		expect(result.kept[1]).toBeNil()
		expect(result.kept[2]).toBe(true)
	end)

	it("a mutation never counts against the per-flavor limit", function()
		local rule = settings({ perFlavor = 1 })
		local result = ScoopChest.store(
			empty(),
			{ RARE, RARE, RARE },
			{ [2] = "golden", [3] = "rainbow" },
			byId,
			rarities,
			Config,
			allSeen(),
			rule
		)
		expect(#result.stored).toBe(3)
		expect(#result.capped).toBe(0)
	end)
end)

describe("Auto Sell: new flavors always stored", function()
	it("on: the first scoop of a flavor never had goes in even when its rarity is set to sell", function()
		local rule = settings({ keepNew = true })
		local seen = { [COMMON2] = 4 } -- had COMMON2, never COMMON
		local result = ScoopChest.store(empty(), { COMMON, COMMON, COMMON2 }, nil, byId, rarities, Config, seen, rule)
		expect(result.kept[1]).toBe(true)
		expect(result.stored[1].new).toBe(true)
		expect(result.kept[2]).toBeNil() -- the second of it is no longer new: sold like any common
		expect(result.kept[3]).toBeNil() -- had before: sold
	end)

	it("a flavor already in the chest is not new", function()
		local rule = settings({ keepNew = true, store = { common = true } })
		local chest = empty()
		ScoopChest.store(chest, { COMMON }, nil, byId, rarities, Config, {}, rule)
		local sellCommons = settings({ keepNew = true })
		local again = ScoopChest.store(chest, { COMMON }, nil, byId, rarities, Config, {}, sellCommons)
		expect(again.kept[1]).toBeNil()
	end)

	it("off: a new flavor follows its rarity", function()
		local rule = settings({ keepNew = false })
		local result = ScoopChest.store(empty(), { COMMON, RARE }, nil, byId, rarities, Config, {}, rule)
		expect(result.kept[1]).toBeNil()
		expect(result.kept[2]).toBe(true) -- rare is set to store anyway
	end)

	it("the preview and the server agree once the client knows the served flavors", function()
		local seenList = { COMMON2 }
		local set = {}
		for _, id in seenList do
			set[id] = true
		end
		local server = ScoopChest.store(empty(), { COMMON, COMMON2 }, nil, byId, rarities, Config, { [COMMON2] = 9 })
		local client = ScoopChest.store(empty(), { COMMON, COMMON2 }, nil, byId, rarities, Config, set)
		expect(server.kept[1]).toBe(client.kept[1])
		expect(server.kept[2]).toBe(client.kept[2])
	end)
end)

describe("Auto Sell: the limit per flavor", function()
	for _, limit in { 1, 2, 3 } do
		it(`{limit} per flavor: the next ones are sold and reported`, function()
			local rule = settings({ perFlavor = limit })
			local chest = empty()
			local result =
				ScoopChest.store(chest, { EPIC, EPIC, EPIC, EPIC }, nil, byId, rarities, Config, allSeen(), rule)
			expect(#result.stored).toBe(limit)
			expect(#result.capped).toBe(4 - limit)
			expect(result.limit).toBe(limit)
			expect(ScoopChest.plainCount(chest, EPIC)).toBe(limit)
		end)
	end

	it("a lower limit leaves what is in the chest alone and stores no more of it", function()
		local chest = empty()
		ScoopChest.store(chest, { EPIC, EPIC, EPIC }, nil, byId, rarities, Config, allSeen())
		local result =
			ScoopChest.store(chest, { EPIC }, nil, byId, rarities, Config, allSeen(), settings({ perFlavor = 1 }))
		expect(ScoopChest.plainCount(chest, EPIC)).toBe(3)
		expect(#result.capped).toBe(1)
	end)
end)

describe("Auto Sell: what the client sends is checked", function()
	it("keeps valid values", function()
		local read = ScoopChest.readAutoSell({
			store = { common = true, rare = false },
			keepMutations = false,
			keepNew = false,
			perFlavor = 2,
		}, rarities, Config)
		expect(read.store.common).toBe(true)
		expect(read.store.rare).toBe(false)
		expect(read.store.epic).toBe(true) -- not sent: its default
		expect(read.keepMutations).toBe(false)
		expect(read.keepNew).toBe(false)
		expect(read.perFlavor).toBe(2)
	end)

	it("falls back to the default field by field for junk", function()
		for _, bad in { 0, 4, 2.5, 0 / 0, math.huge, -1, "3", true } do
			expect(ScoopChest.readAutoSell({ perFlavor = bad }, rarities, Config).perFlavor).toBe(3)
		end
		local read = ScoopChest.readAutoSell({
			store = { common = "yes", hacked = true, [1] = true },
			keepMutations = 1,
			keepNew = "no",
		}, rarities, Config)
		expect(read.store.common).toBe(false)
		expect(read.store.hacked).toBeNil()
		expect(read.keepMutations).toBe(true)
		expect(read.keepNew).toBe(true)
		for _, raw in { "store", 5, true } do
			expect(ScoopChest.readAutoSell(raw, rarities, Config).store.rare).toBe(true)
		end
		expect(ScoopChest.readAutoSell({ store = "all" }, rarities, Config).store.common).toBe(false)
	end)
end)

describe("Dash: catching and picking up along the dash's way", function()
	it("the nearest point of the way, clamped to its ends", function()
		local x, z = Loot.nearestOnWay(0, 0, 10, 0, 4, 3)
		expect(x).toBeCloseTo(4)
		expect(z).toBeCloseTo(0)
		x, z = Loot.nearestOnWay(0, 0, 10, 0, -5, 1)
		expect(x).toBeCloseTo(0)
		x, z = Loot.nearestOnWay(0, 0, 10, 0, 15, 1)
		expect(x).toBeCloseTo(10)
		x, z = Loot.nearestOnWay(2, 2, 2, 2, 9, 9) -- no way at all: its start
		expect(x).toBe(2)
		expect(z).toBe(2)
	end)

	it("a scoop dashed through is in reach from the way though the root is already past it", function()
		-- dashed 10 studs along x; the scoop lay at x = 4, the server sees the root at the end (12 with lag)
		local fromX, rootX = 0, 12
		local scoopX, scoopZ = 4, 1
		local direct = Loot.inReach(rootX - scoopX, 0, 0 - scoopZ, 20, true, LootConfig)
		expect(direct).toBe(false)
		local wx, wz = Loot.nearestOnWay(fromX, 0, rootX, 0, scoopX, scoopZ)
		expect(Loot.inReach(wx - scoopX, 0, wz - scoopZ, 20, true, LootConfig)).toBe(true)
		-- one beside the way stays out of reach
		local sx, sz = Loot.nearestOnWay(fromX, 0, rootX, 0, 4, 9)
		expect(Loot.inReach(sx - 4, 0, sz - 9, 20, true, LootConfig)).toBe(false)
	end)

	it("the trail is short and only right after a dash (config)", function()
		expect(TowerConfig.dash.trailGrace > 0 and TowerConfig.dash.trailGrace <= 1).toBe(true)
		expect(TowerConfig.dash.trailSlack > 0 and TowerConfig.dash.trailSlack <= 6).toBe(true)
	end)
end)
