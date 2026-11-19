local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local ScoopChest = require("../src/shared/ScoopChest")
local Config = require("../src/shared/Config/Chest")
local Flavors = require("../src/shared/Config/Flavors")
local Economy = require("../src/shared/Economy")
local EconomyConfig = require("../src/shared/Config/Economy")

local byId = Flavors.byId
local rarities = Flavors.rarities

-- a copy of the config with some values changed
local function with(changes: { [string]: any }): any
	local copy = table.clone(Config)
	for key, value in changes do
		copy[key] = value
	end
	return copy
end

local function empty(): ScoopChest.Chest
	return { items = {}, equipped = {} }
end

local function idOf(rarity: string): string
	for _, flavor in Flavors.list do
		if flavor.rarity == rarity then
			return flavor.id
		end
	end
	error("no flavor of rarity " .. rarity)
end

local COMMON, RARE, EPIC, LEGENDARY = idOf("common"), idOf("rare"), idOf("epic"), idOf("legendary")

describe("Scoop Chest: data", function()
	it("every flavor's rarity and passive is known to the chest", function()
		for _, flavor in Flavors.list do
			expect(table.find(rarities, flavor.rarity) ~= nil).toBe(true)
			expect(Flavors.rarityColors[flavor.rarity] ~= nil).toBe(true)
			if flavor.passive then
				expect(Config.passives.kinds[flavor.passive] ~= nil).toBe(true)
			end
		end
	end)

	it(
		"has the three boost kinds Coins 25 %, Luck 25 %, Tower Bonus 30 %, the prepared ones out of the window",
		function()
			expect(#Config.passives.order).toBe(3)
			expect(Config.passives.kinds.coins.cap).toBe(0.25)
			expect(Config.passives.kinds.luck.cap).toBe(0.25)
			expect(Config.passives.kinds.tower.cap).toBe(0.3)
			expect(Config.passives.kinds.catch).toBeNil()
			for _, kind in { "goldenLuck", "eventLuck", "xp", "sprinkles" } do
				local spec = Config.passives.kinds[kind]
				expect(spec ~= nil and spec.prepared == true).toBe(true)
				expect(table.find(Config.passives.order, kind)).toBeNil()
			end
		end
	)

	it("spreads the chest's flavors (rare and up) 3/3/4 over the three kinds, none on a prepared kind", function()
		expect(Config.minRarity).toBe("rare")
		for _, rarity in { "rare", "epic", "legendary" } do
			local counts = { coins = 0, luck = 0, tower = 0 }
			for _, flavor in Flavors.list do
				if flavor.rarity == rarity and not flavor.placeholder then
					local kind = flavor.passive or Config.passives.defaultPassive
					expect(counts[kind] ~= nil).toBe(true)
					counts[kind] += 1
				end
			end
			local sorted = { counts.coins, counts.luck, counts.tower }
			table.sort(sorted)
			expect(sorted[1]).toBe(3)
			expect(sorted[2]).toBe(3)
			expect(sorted[3]).toBe(4)
		end
	end)

	it("gives the uncommons no boost: they never reach the chest", function()
		for _, flavor in Flavors.list do
			if flavor.rarity == "uncommon" then
				expect(flavor.passive).toBeNil()
				expect(ScoopChest.keeps(flavor.id, nil, Flavors.byId, Flavors.rarities, Config)).toBe(false)
			end
		end
	end)

	it("the threshold is a known rarity, every passive kind is listed and capped", function()
		expect(table.find(rarities, Config.minRarity) ~= nil).toBe(true)
		for _, kind in Config.passives.order do
			expect(Config.passives.kinds[kind].cap).toBeGreaterThan(0)
		end
		expect(Config.passives.kinds[Config.passives.defaultPassive] ~= nil).toBe(true)
	end)

	it("rarer is never weaker: passive and sell value grow with the rank", function()
		local lastPassive, lastSell = -1, -1
		for _, rarity in rarities do
			local passive = Config.passives.byRarity[rarity] or 0
			local sell = Config.sell.byRarity[rarity] or 1
			expect(passive >= lastPassive).toBe(true)
			expect(sell >= lastSell).toBe(true)
			lastPassive, lastSell = passive, sell
		end
	end)
end)

describe("Scoop Chest: what is kept at a serve", function()
	it("rare and rarer go in, common is sold", function()
		expect(ScoopChest.keeps(COMMON, nil, byId, rarities, Config)).toBe(false)
		expect(ScoopChest.keeps(RARE, nil, byId, rarities, Config)).toBe(true)
		expect(ScoopChest.keeps(LEGENDARY, nil, byId, rarities, Config)).toBe(true)
	end)

	it("the threshold is a config value: at epic a rare is sold", function()
		local epicUp = with({ minRarity = "epic" })
		expect(ScoopChest.keeps(RARE, nil, byId, rarities, epicUp)).toBe(false)
		expect(ScoopChest.keeps(EPIC, nil, byId, rarities, epicUp)).toBe(true)
	end)

	it("a mutation always goes in, even on a common scoop", function()
		expect(ScoopChest.keeps(COMMON, "golden", byId, rarities, Config)).toBe(true)
		expect(ScoopChest.keeps(COMMON, "", byId, rarities, Config)).toBe(false)
	end)

	it("an unknown flavor is never kept", function()
		expect(ScoopChest.keeps("nope", "golden", byId, rarities, Config)).toBe(false)
	end)

	it("store marks the kept tower indices and stacks the same flavor", function()
		local chest = empty()
		local result = ScoopChest.store(chest, { COMMON, RARE, COMMON, RARE, EPIC }, nil, byId, rarities, Config)
		expect(result.kept[1]).toBeNil()
		expect(result.kept[2]).toBe(true)
		expect(result.kept[4]).toBe(true)
		expect(result.kept[5]).toBe(true)
		expect(#result.stored).toBe(3)
		expect(result.overflow).toBe(0)
		expect(#chest.items).toBe(2)
		expect(ScoopChest.used(chest)).toBe(3)
		expect(ScoopChest.find(chest, ScoopChest.key(RARE, "")).count).toBe(2)
	end)

	it("a mutated scoop stacks apart from the plain one", function()
		local chest = empty()
		ScoopChest.store(chest, { RARE, RARE }, { [2] = "golden" }, byId, rarities, Config)
		expect(#chest.items).toBe(2)
		expect(ScoopChest.find(chest, ScoopChest.key(RARE, "golden")).mutation).toBe("golden")
	end)

	it("a full chest sells the rest: it counts as overflow and is not kept", function()
		local small = with({ capacity = 2 })
		local chest = empty()
		local result = ScoopChest.store(chest, { RARE, EPIC, LEGENDARY, COMMON }, nil, byId, rarities, small)
		expect(ScoopChest.used(chest)).toBe(2)
		expect(result.overflow).toBe(1)
		expect(result.kept[3]).toBeNil()
		expect(ScoopChest.add(chest, RARE, nil, byId, small)).toBe(false)
	end)
end)

describe("Scoop Chest: at most 3 of a flavor, new flavors", function()
	it("keeps at most maxPerFlavor (3) of one plain flavor, sells the 4th and later at full value", function()
		expect(Config.maxPerFlavor).toBe(3)
		local chest = empty()
		local tower = { EPIC, EPIC, EPIC, EPIC, EPIC }
		local result = ScoopChest.store(chest, tower, nil, byId, rarities, Config)
		expect(#result.stored).toBe(3)
		expect(#result.capped).toBe(2)
		expect(result.capped[1]).toBe(EPIC)
		expect(result.kept[3]).toBe(true)
		expect(result.kept[4]).toBeNil()
		expect(result.kept[5]).toBeNil()
		expect(ScoopChest.plainCount(chest, EPIC)).toBe(3)
		-- the two sold ones pay their full value (a kept one counts for the height only)
		local value = Economy.serveValue(tower, byId, EconomyConfig, { kept = result.kept })
		expect(value).toBeCloseTo(byId[EPIC].value * 2 * Economy.heightMultiplier(5, EconomyConfig))
		-- a later serve of the same flavor sells it all
		local again = ScoopChest.store(chest, { EPIC }, nil, byId, rarities, Config)
		expect(#again.stored).toBe(0)
		expect(#again.capped).toBe(1)
	end)

	it("counts each flavor on its own", function()
		local chest = empty()
		local result = ScoopChest.store(chest, { EPIC, EPIC, EPIC, RARE, LEGENDARY }, nil, byId, rarities, Config)
		expect(#result.stored).toBe(5)
		expect(#result.capped).toBe(0)
	end)

	it("always stores golden and rainbow scoops while there is room, past the limit too", function()
		local chest = empty()
		ScoopChest.store(chest, { EPIC, EPIC, EPIC }, nil, byId, rarities, Config)
		local result = ScoopChest.store(chest, { EPIC, EPIC }, { "golden", "rainbow" }, byId, rarities, Config)
		expect(#result.stored).toBe(2)
		expect(#result.capped).toBe(0)
		local small = with({ capacity = 4 })
		local full = empty()
		ScoopChest.store(full, { EPIC, EPIC, EPIC }, nil, byId, rarities, small)
		local over = ScoopChest.store(full, { RARE, RARE }, { "golden", "golden" }, byId, rarities, small)
		expect(#over.stored).toBe(1)
		expect(over.overflow).toBe(1)
	end)

	it("marks the first of a flavor the player never had as new, nothing they had or have", function()
		local chest = empty()
		local result = ScoopChest.store(chest, { EPIC, EPIC, RARE, LEGENDARY }, nil, byId, rarities, Config, {
			[LEGENDARY] = 2, -- served before
		})
		expect(result.stored[1].new).toBe(true)
		expect(result.stored[2].new).toBe(false) -- the second of the same serve
		expect(result.stored[3].new).toBe(true)
		expect(result.stored[4].new).toBe(false)
		-- already in the chest: not new again
		expect(ScoopChest.store(chest, { RARE }, nil, byId, rarities, Config).stored[1].new).toBe(false)
	end)
end)

describe("Scoop Chest: selling by a filter", function()
	local function filled()
		local chest = empty()
		ScoopChest.store(chest, { RARE, RARE, RARE, EPIC, EPIC, LEGENDARY }, nil, byId, rarities, Config)
		ScoopChest.store(chest, { RARE }, { "golden" }, byId, rarities, Config)
		return chest
	end
	local function only(list: { string }): { [string]: boolean }
		local set = {}
		for _, rarity in list do
			set[rarity] = true
		end
		return set
	end

	it("sells the picked rarities, keeping one of each stack when asked", function()
		local chest = filled()
		local filter = { rarities = only({ "rare", "epic" }), mutations = false, keepOne = true }
		local _, count, coins = ScoopChest.sellPlan(chest, filter, byId, Config)
		expect(count).toBe(3) -- 2 of 3 rare, 1 of 2 epic; golden and legendary stay
		local got, sold = ScoopChest.sellFiltered(chest, filter, byId, Config)
		expect(sold).toBe(3)
		expect(got).toBe(coins)
		expect(ScoopChest.plainCount(chest, RARE)).toBe(1)
		expect(ScoopChest.plainCount(chest, EPIC)).toBe(1)
		expect(ScoopChest.plainCount(chest, LEGENDARY)).toBe(1)
		expect(ScoopChest.find(chest, ScoopChest.key(RARE, "golden")) ~= nil).toBe(true)
	end)

	it("sells everything of a rarity without keep one, golden and rainbow only when picked", function()
		local chest = filled()
		ScoopChest.sellFiltered(
			chest,
			{ rarities = only({ "rare" }), mutations = false, keepOne = false },
			byId,
			Config
		)
		expect(ScoopChest.plainCount(chest, RARE)).toBe(0)
		expect(ScoopChest.find(chest, ScoopChest.key(RARE, "golden")) ~= nil).toBe(true)
		ScoopChest.sellFiltered(chest, { rarities = only({ "rare" }), mutations = true, keepOne = false }, byId, Config)
		expect(ScoopChest.find(chest, ScoopChest.key(RARE, "golden"))).toBeNil()
	end)

	it("never empties an equipped stack: it keeps one and stays equipped", function()
		local chest = filled()
		ScoopChest.equip(chest, ScoopChest.key(EPIC, ""), Config)
		ScoopChest.sellFiltered(
			chest,
			{ rarities = only({ "epic" }), mutations = false, keepOne = false },
			byId,
			Config
		)
		expect(ScoopChest.plainCount(chest, EPIC)).toBe(1)
		expect(table.find(chest.equipped, ScoopChest.key(EPIC, "")) ~= nil).toBe(true)
	end)

	it("sells nothing with nothing picked", function()
		local chest = filled()
		local coins, count =
			ScoopChest.sellFiltered(chest, { rarities = {}, mutations = true, keepOne = false }, byId, Config)
		expect(count).toBe(0)
		expect(coins).toBe(0)
		expect(ScoopChest.used(chest)).toBe(7)
	end)
end)

describe("Every flavor is worth something", function()
	it("sells every one of the 52 flavors for more than 0 coins at a serve and from the chest", function()
		local count = 0
		for _, flavor in Flavors.list do
			if not flavor.placeholder then
				count += 1
			end
			expect(flavor.value).toBeGreaterThan(0)
			expect(Economy.serveValue({ flavor.id }, byId, EconomyConfig)).toBeGreaterThan(0)
			local item = { flavor = flavor.id, rarity = flavor.rarity, mutation = "", count = 1 }
			expect(ScoopChest.sellValue(item, byId, Config)).toBeGreaterThan(0)
		end
		expect(count).toBe(52)
	end)

	it("pays nothing for a tower the chest took whole: the serve shows the chest's message, not +0", function()
		local chest = empty()
		local result = ScoopChest.store(chest, { EPIC }, nil, byId, rarities, Config)
		expect(Economy.serveValue({ EPIC }, byId, EconomyConfig, { kept = result.kept })).toBe(0)
		expect(#result.stored).toBe(1)
	end)
end)

describe("Scoop Chest: serving pays for what is sold", function()
	it("kept scoops pay nothing but still count for the height", function()
		local tower = { COMMON, COMMON, RARE, COMMON }
		local kept = { [3] = true }
		local value = Economy.serveValue(tower, byId, EconomyConfig, { kept = kept })
		local commons = byId[COMMON].value * 3
		expect(value).toBeCloseTo(commons * Economy.heightMultiplier(4, EconomyConfig))
		-- the same three commons alone would be worth less: the kept scoop still raised the tower
		local alone = Economy.serveValue({ COMMON, COMMON, COMMON }, byId, EconomyConfig)
		expect(value).toBeGreaterThan(alone)
	end)

	it("the coins passive multiplies the pay", function()
		local tower = { COMMON, COMMON }
		local plain = Economy.serveValue(tower, byId, EconomyConfig)
		local bonus = Economy.serveValue(tower, byId, EconomyConfig, { coinBonus = 0.1 })
		expect(bonus).toBeCloseTo(plain * 1.1)
		expect(Economy.serveValue(tower, byId, EconomyConfig, { coinBonus = -1 })).toBeCloseTo(plain)
	end)

	it("the tower bonus pays nothing below its start, then grows with the tower up to the whole bonus", function()
		local spec = Config.passives.kinds.tower
		expect(Economy.towerBonus(spec.from - 1, 0.3, spec.from, spec.full)).toBe(0)
		local first = Economy.towerBonus(spec.from, 0.3, spec.from, spec.full)
		local middle = Economy.towerBonus(math.floor((spec.from + spec.full) / 2), 0.3, spec.from, spec.full)
		expect(first).toBeGreaterThan(0)
		expect(middle).toBeGreaterThan(first)
		expect(Economy.towerBonus(spec.full, 0.3, spec.from, spec.full)).toBeCloseTo(0.3)
		expect(Economy.towerBonus(200, 0.3, spec.from, spec.full)).toBeCloseTo(0.3)
		expect(Economy.towerBonus(50, 0, spec.from, spec.full)).toBe(0)
		-- it adds to the coins passive
		local tower = table.create(spec.full, COMMON)
		local plain = Economy.serveValue(tower, byId, EconomyConfig)
		local both = Economy.serveValue(tower, byId, EconomyConfig, { coinBonus = 0.1, towerBonus = 0.3 })
		expect(both).toBeCloseTo(plain * 1.4)
	end)

	it("a tower of only kept scoops pays nothing", function()
		expect(Economy.serveValue({ RARE }, byId, EconomyConfig, { kept = { true } })).toBe(0)
	end)
end)

describe("Scoop Chest: equipping", function()
	local function filled(): ScoopChest.Chest
		local chest = empty()
		for _, id in { RARE, EPIC, LEGENDARY } do
			ScoopChest.add(chest, id, nil, byId, Config)
		end
		ScoopChest.add(chest, COMMON, "golden", byId, Config)
		return chest
	end

	it("equips up to the slots, each stack once, only what is there", function()
		local chest = filled()
		expect(ScoopChest.equip(chest, ScoopChest.key(RARE), Config)).toBe(true)
		local ok, reason = ScoopChest.equip(chest, ScoopChest.key(RARE), Config)
		expect(ok).toBe(false)
		expect(reason).toBe("equipped")
		ok, reason = ScoopChest.equip(chest, ScoopChest.key("nope"), Config)
		expect(reason).toBe("unknown")
		expect(ScoopChest.equip(chest, ScoopChest.key(EPIC), Config)).toBe(true)
		expect(ScoopChest.equip(chest, ScoopChest.key(LEGENDARY), Config)).toBe(true)
		ok, reason = ScoopChest.equip(chest, ScoopChest.key(COMMON, "golden"), Config)
		expect(ok).toBe(false)
		expect(reason).toBe("full")
		expect(#chest.equipped).toBe(Config.equipSlots)
	end)

	it("unequip frees the slot", function()
		local chest = filled()
		ScoopChest.equip(chest, ScoopChest.key(RARE), Config)
		expect(ScoopChest.unequip(chest, ScoopChest.key(RARE))).toBe(true)
		expect(ScoopChest.unequip(chest, ScoopChest.key(RARE))).toBe(false)
		expect(#chest.equipped).toBe(0)
	end)
end)

describe("Scoop Chest: selling", function()
	it("pays value x rarity factor x mutation per scoop and takes them out", function()
		local chest = empty()
		for _ = 1, 3 do
			ScoopChest.add(chest, RARE, nil, byId, Config)
		end
		local key = ScoopChest.key(RARE)
		local each = math.floor(byId[RARE].value * Config.sell.byRarity.rare + 0.5)
		expect(ScoopChest.sellValue(ScoopChest.find(chest, key), byId, Config)).toBe(each)
		expect(ScoopChest.sell(chest, key, 2, byId, Config)).toBe(each * 2)
		expect(ScoopChest.find(chest, key).count).toBe(1)
	end)

	it("a golden scoop sells for its mutation's factor more", function()
		local plain = { flavor = COMMON, rarity = "common", mutation = "", count = 1 }
		local golden = { flavor = COMMON, rarity = "common", mutation = "golden", count = 1 }
		local factor = Config.mutations.kinds.golden.sell
		expect(ScoopChest.sellValue(golden, byId, Config)).toBe(ScoopChest.sellValue(plain, byId, Config) * factor)
	end)

	it("refuses more than there is, broken amounts and unknown stacks", function()
		local chest = empty()
		ScoopChest.add(chest, RARE, nil, byId, Config)
		local key = ScoopChest.key(RARE)
		for _, amount in { 0, -1, 2, 0.5, 0 / 0 } do
			local coins, reason = ScoopChest.sell(chest, key, amount, byId, Config)
			expect(coins).toBeNil()
			expect(reason).toBe("amount")
		end
		local coins, reason = ScoopChest.sell(chest, "nope|", 1, byId, Config)
		expect(coins).toBeNil()
		expect(reason).toBe("unknown")
		expect(ScoopChest.used(chest)).toBe(1)
	end)

	it("selling the last one of an equipped stack takes it off its slot", function()
		local chest = empty()
		ScoopChest.add(chest, EPIC, nil, byId, Config)
		local key = ScoopChest.key(EPIC)
		ScoopChest.equip(chest, key, Config)
		ScoopChest.sell(chest, key, 1, byId, Config)
		expect(#chest.items).toBe(0)
		expect(#chest.equipped).toBe(0)
	end)
end)

describe("Scoop Chest: passives", function()
	it("each scoop gives its flavor's kind at its rarity's amount, a mutation multiplies it", function()
		local rare = { flavor = RARE, rarity = "rare", mutation = "", count = 1 }
		local kind, amount = ScoopChest.passiveOf(rare, byId, Config)
		expect(kind).toBe(byId[RARE].passive or Config.passives.defaultPassive)
		expect(amount).toBeCloseTo(Config.passives.byRarity.rare)
		local golden = { flavor = RARE, rarity = "rare", mutation = "golden", count = 1 }
		local _, more = ScoopChest.passiveOf(golden, byId, Config)
		expect(more).toBeCloseTo(Config.passives.byRarity.rare * Config.mutations.kinds.golden.passive)
	end)

	it("a flavor without a passive gives the default one", function()
		local plain = { flavor = COMMON, rarity = "common", mutation = "golden", count = 1 }
		expect((ScoopChest.passiveOf(plain, byId, Config))).toBe(Config.passives.defaultPassive)
	end)

	it("only equipped scoops count, equal kinds add up, every kind is listed", function()
		local chest = empty()
		ScoopChest.add(chest, RARE, nil, byId, Config)
		ScoopChest.add(chest, RARE, "golden", byId, Config)
		ScoopChest.add(chest, EPIC, nil, byId, Config)
		local none = ScoopChest.bonuses(chest, byId, Config)
		for _, kind in Config.passives.order do
			expect(none[kind]).toBe(0)
		end
		ScoopChest.equip(chest, ScoopChest.key(RARE), Config)
		ScoopChest.equip(chest, ScoopChest.key(RARE, "golden"), Config)
		local kind = byId[RARE].passive or Config.passives.defaultPassive
		local both = ScoopChest.bonuses(chest, byId, Config)
		local rare = Config.passives.byRarity.rare
		expect(both[kind]).toBeCloseTo(rare + rare * Config.mutations.kinds.golden.passive)
	end)

	it("each kind stops at its cap", function()
		local strong = with({
			passives = {
				order = Config.passives.order,
				defaultPassive = Config.passives.defaultPassive,
				kinds = Config.passives.kinds,
				byRarity = { rare = 1, epic = 1, legendary = 1, common = 1, uncommon = 1 },
			},
		})
		local chest = empty()
		ScoopChest.add(chest, RARE, nil, byId, strong)
		ScoopChest.equip(chest, ScoopChest.key(RARE), strong)
		local kind = byId[RARE].passive or Config.passives.defaultPassive
		expect(ScoopChest.bonuses(chest, byId, strong)[kind]).toBeCloseTo(Config.passives.kinds[kind].cap)
	end)

	it("a key in the save that is no stack any more gives nothing", function()
		local chest = { items = {}, equipped = { ScoopChest.key(RARE) } }
		local totals = ScoopChest.bonuses(chest, byId, Config)
		for _, kind in Config.passives.order do
			expect(totals[kind]).toBe(0)
		end
	end)
end)

describe("Scoop Chest: luck", function()
	local pool = {
		{ id = COMMON, rarity = "common", weight = 10 },
		{ id = RARE, rarity = "rare", weight = 1 },
		{ id = EPIC, rarity = "epic", weight = 1 },
	}

	it("without luck, or a roll over it, nothing changes", function()
		expect(ScoopChest.luckyFlavor(COMMON, 0, 0, 0.5, pool, byId, rarities)).toBeNil()
		expect(ScoopChest.luckyFlavor(COMMON, 0.1, 0.2, 0.5, pool, byId, rarities)).toBeNil()
	end)

	it("a lucky roll gives the next rarer rarity that has flavors (uncommon has none)", function()
		expect(ScoopChest.luckyFlavor(COMMON, 0.1, 0.05, 0.5, pool, byId, rarities)).toBe(RARE)
		expect(ScoopChest.luckyFlavor(RARE, 0.1, 0.05, 0.5, pool, byId, rarities)).toBe(EPIC)
	end)

	it("nothing rarer in the pool: it stays", function()
		expect(ScoopChest.luckyFlavor(EPIC, 1, 0, 0.5, pool, byId, rarities)).toBeNil()
	end)
end)

describe("Scoop Chest: order in the window", function()
	it("rarest first, plain before golden before rainbow", function()
		local chest = empty()
		ScoopChest.add(chest, COMMON, "rainbow", byId, Config)
		ScoopChest.add(chest, RARE, nil, byId, Config)
		ScoopChest.add(chest, LEGENDARY, nil, byId, Config)
		ScoopChest.add(chest, COMMON, "golden", byId, Config)
		ScoopChest.add(chest, EPIC, nil, byId, Config)
		local order = {}
		for _, item in ScoopChest.sorted(chest, byId, rarities, Config) do
			table.insert(order, ScoopChest.key(item.flavor, item.mutation))
		end
		expect(order[1]).toBe(ScoopChest.key(LEGENDARY))
		expect(order[2]).toBe(ScoopChest.key(EPIC))
		expect(order[3]).toBe(ScoopChest.key(RARE))
		expect(order[4]).toBe(ScoopChest.key(COMMON, "golden"))
		expect(order[5]).toBe(ScoopChest.key(COMMON, "rainbow"))
		expect(#chest.items).toBe(5) -- the chest itself is untouched
	end)
end)
