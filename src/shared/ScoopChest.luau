--!strict
-- The Scoop Chest's rules (Config/Chest): which served scoops are kept, stacking, the capacity, equipping, selling and
-- the passive bonuses of what is equipped. Pure: the flavor list and the configs are passed in, so the rules run in
-- the Lune tests. ChestService applies them to the save (SaveData's `chest`), the client only shows the result.
--
-- A stored scoop is an item: flavor, rarity, mutation ("" for none) and count. Items of the same flavor and mutation
-- stack; `key` names a stack ("flavor|mutation"). The rarity is written into the save when stored, but the flavor's
-- rarity in Config/Flavors wins while the flavor exists, so a rebalanced flavor counts at its new rarity.

export type Item = { flavor: string, rarity: string, mutation: string, count: number }
export type Chest = { items: { Item }, equipped: { string } }

export type FlavorInfo = { name: string?, rarity: string, value: number, passive: string? }
export type Flavors = { [string]: FlavorInfo }

export type Config = {
	minRarity: string,
	storeMutations: boolean,
	maxPerFlavor: number?,
	capacity: number,
	equipSlots: number,
	mutations: { order: { string }, kinds: { [string]: { passive: number, sell: number } } },
	passives: {
		order: { string },
		defaultPassive: string,
		kinds: { [string]: { cap: number } },
		byRarity: { [string]: number },
	},
	sell: { byRarity: { [string]: number } },
}

export type StoreResult = {
	kept: { [number]: boolean }, -- tower indices that went into the chest (not sold)
	-- what went in, bottom to top; `new`: a flavor the player never had before (`seen` of store), the first of it
	stored: { { flavor: string, mutation: string, new: boolean } },
	overflow: number, -- scoops that would have gone in but the chest was full (sold instead)
	capped: { string }, -- flavors sold because the chest already holds maxPerFlavor plain ones of them, bottom to top
}

local ScoopChest = {}

-- The stack name of a flavor with a mutation ("" or nil: none).
function ScoopChest.key(flavor: string, mutation: string?): string
	return flavor .. "|" .. (mutation or "")
end

-- The rank of a rarity in `rarities` (Config/Flavors.rarities, common first = 1); 0 for an unknown one.
function ScoopChest.rank(rarity: string, rarities: { string }): number
	return table.find(rarities, rarity) or 0
end

-- The rarity an item counts at: its flavor's while the flavor exists, else the one stored with it.
function ScoopChest.rarityOf(item: Item, flavors: Flavors): string
	local flavor = flavors[item.flavor]
	return if flavor then flavor.rarity else item.rarity
end

-- Whether a served scoop of `flavorId` (with `mutation`) belongs in the chest rather than being sold.
function ScoopChest.keeps(
	flavorId: string,
	mutation: string?,
	flavors: Flavors,
	rarities: { string },
	config: Config
): boolean
	local flavor = flavors[flavorId]
	if not flavor then
		return false
	end
	if mutation and mutation ~= "" and config.storeMutations then
		return true
	end
	local threshold = ScoopChest.rank(config.minRarity, rarities)
	return threshold > 0 and ScoopChest.rank(flavor.rarity, rarities) >= threshold
end

-- All stored scoops, stacks counted in full.
function ScoopChest.used(chest: Chest): number
	local total = 0
	for _, item in chest.items do
		total += item.count
	end
	return total
end

function ScoopChest.find(chest: Chest, key: string): (Item?, number?)
	for index, item in chest.items do
		if ScoopChest.key(item.flavor, item.mutation) == key then
			return item, index
		end
	end
	return nil, nil
end

-- Puts one scoop in; false when the chest is full or the flavor unknown.
function ScoopChest.add(chest: Chest, flavorId: string, mutation: string?, flavors: Flavors, config: Config): boolean
	local flavor = flavors[flavorId]
	if not flavor or ScoopChest.used(chest) >= config.capacity then
		return false
	end
	local item = ScoopChest.find(chest, ScoopChest.key(flavorId, mutation))
	if item then
		item.count += 1
	else
		table.insert(chest.items, { flavor = flavorId, rarity = flavor.rarity, mutation = mutation or "", count = 1 })
	end
	return true
end

-- How many plain (unmutated) scoops of `flavorId` the chest holds.
function ScoopChest.plainCount(chest: Chest, flavorId: string): number
	local item = ScoopChest.find(chest, ScoopChest.key(flavorId, ""))
	return if item then item.count else 0
end

-- A served tower (`scoops` bottom to top, `mutations` by the same index or nil): the scoops the chest keeps go in
-- while there is room; what does not fit is sold with the rest. Of a plain flavor at most config.maxPerFlavor go in,
-- the next ones are sold at full value (`capped`); a mutation (Golden, Rainbow) always goes in while there is room.
-- `seen` (flavor id -> anything) holds the flavors the player already had: the first stored one of any other is `new`.
function ScoopChest.store(
	chest: Chest,
	scoops: { string },
	mutations: { [number]: string }?,
	flavors: Flavors,
	rarities: { string },
	config: Config,
	seen: { [string]: any }?
): StoreResult
	local result: StoreResult = { kept = {}, stored = {}, overflow = 0, capped = {} }
	local had: { [string]: boolean } = {}
	for flavorId in seen or {} do
		had[flavorId] = true
	end
	for _, item in chest.items do
		had[item.flavor] = true
	end
	for index, flavorId in scoops do
		local mutation = mutations and mutations[index] or ""
		if ScoopChest.keeps(flavorId, mutation, flavors, rarities, config) then
			local limit = config.maxPerFlavor
			if mutation == "" and limit and ScoopChest.plainCount(chest, flavorId) >= limit then
				table.insert(result.capped, flavorId)
			elseif ScoopChest.add(chest, flavorId, mutation, flavors, config) then
				result.kept[index] = true
				table.insert(result.stored, { flavor = flavorId, mutation = mutation, new = not had[flavorId] })
				had[flavorId] = true
			else
				result.overflow += 1
			end
		end
	end
	return result
end

export type SellFilter = {
	rarities: { [string]: boolean }, -- the rarities to sell
	mutations: boolean, -- also sell golden and rainbow scoops (else they stay)
	keepOne: boolean, -- keep one of every stack
}

-- What selling by `filter` would do, without changing the chest: per stack key how many go, how many in all and the
-- coins. An equipped stack always keeps one (its slot stays).
function ScoopChest.sellPlan(
	chest: Chest,
	filter: SellFilter,
	flavors: Flavors,
	config: Config
): ({ [string]: number }, number, number)
	local plan: { [string]: number } = {}
	local count, coins = 0, 0
	for _, item in chest.items do
		if not filter.rarities[ScoopChest.rarityOf(item, flavors)] then
			continue
		end
		if item.mutation ~= "" and not filter.mutations then
			continue
		end
		local key = ScoopChest.key(item.flavor, item.mutation)
		local keep = if filter.keepOne or table.find(chest.equipped, key) then 1 else 0
		local amount = math.max(0, item.count - keep)
		if amount > 0 then
			plan[key] = amount
			count += amount
			coins += ScoopChest.sellValue(item, flavors, config) * amount
		end
	end
	return plan, count, coins
end

-- Sells by `filter` (ScoopChest.sellPlan). Returns the coins and how many scoops went.
function ScoopChest.sellFiltered(chest: Chest, filter: SellFilter, flavors: Flavors, config: Config): (number, number)
	local plan, count = ScoopChest.sellPlan(chest, filter, flavors, config)
	local coins = 0
	for key, amount in plan do
		coins += ScoopChest.sell(chest, key, amount, flavors, config) or 0
	end
	return coins, count
end

-- Equips the stack `key` into the next free slot. Returns true, or false and why ("unknown", "equipped", "full").
function ScoopChest.equip(chest: Chest, key: string, config: Config): (boolean, string?)
	if not ScoopChest.find(chest, key) then
		return false, "unknown"
	end
	if table.find(chest.equipped, key) then
		return false, "equipped"
	end
	if #chest.equipped >= config.equipSlots then
		return false, "full"
	end
	table.insert(chest.equipped, key)
	return true, nil
end

function ScoopChest.unequip(chest: Chest, key: string): boolean
	local index = table.find(chest.equipped, key)
	if not index then
		return false
	end
	table.remove(chest.equipped, index)
	return true
end

-- What one scoop of an item sells for (whole coins, at least 1).
function ScoopChest.sellValue(item: Item, flavors: Flavors, config: Config): number
	local flavor = flavors[item.flavor]
	local base = if flavor then flavor.value else 1
	local factor = config.sell.byRarity[ScoopChest.rarityOf(item, flavors)] or 1
	local mutation = config.mutations.kinds[item.mutation]
	local mutationFactor = if mutation then mutation.sell else 1
	return math.max(1, math.floor(base * factor * mutationFactor + 0.5))
end

-- Sells `amount` scoops of the stack `key`. Returns the coins, or nil and why ("unknown", "amount"). The last one of
-- a stack takes the stack out of the chest and off its slot.
function ScoopChest.sell(
	chest: Chest,
	key: string,
	amount: number,
	flavors: Flavors,
	config: Config
): (number?, string?)
	local item, index = ScoopChest.find(chest, key)
	if not item or not index then
		return nil, "unknown"
	end
	if amount ~= amount or amount < 1 or amount ~= math.floor(amount) or amount > item.count then
		return nil, "amount"
	end
	local coins = ScoopChest.sellValue(item, flavors, config) * amount
	item.count -= amount
	if item.count <= 0 then
		table.remove(chest.items, index)
		ScoopChest.unequip(chest, key)
	end
	return coins, nil
end

-- The passive an item gives equipped: its kind and amount (0.02 = +2 %).
function ScoopChest.passiveOf(item: Item, flavors: Flavors, config: Config): (string, number)
	local flavor = flavors[item.flavor]
	local kind = flavor and flavor.passive or config.passives.defaultPassive
	if not config.passives.kinds[kind] then
		kind = config.passives.defaultPassive
	end
	local amount = config.passives.byRarity[ScoopChest.rarityOf(item, flavors)] or 0
	local mutation = config.mutations.kinds[item.mutation]
	if mutation then
		amount *= mutation.passive
	end
	return kind, amount
end

-- The bonuses of everything equipped: each kind summed, then held at its cap. Every kind in passives.order is there
-- (0 when nothing gives it).
function ScoopChest.bonuses(chest: Chest, flavors: Flavors, config: Config): { [string]: number }
	local totals: { [string]: number } = {}
	for _, kind in config.passives.order do
		totals[kind] = 0
	end
	for slot, key in chest.equipped do
		if slot > config.equipSlots then
			break
		end
		local item = ScoopChest.find(chest, key)
		if item then
			local kind, amount = ScoopChest.passiveOf(item, flavors, config)
			totals[kind] = (totals[kind] or 0) + amount
		end
	end
	for kind, total in totals do
		local spec = config.passives.kinds[kind]
		totals[kind] = math.clamp(total, 0, if spec then spec.cap else 0)
	end
	return totals
end

-- The items in display order: rarest first, then plain before the mutations (in mutations.order), then by name.
-- Returns a new list; the chest stays as it is.
function ScoopChest.sorted(chest: Chest, flavors: Flavors, rarities: { string }, config: Config): { Item }
	local list = table.clone(chest.items)
	local function mutationRank(item: Item): number
		return if item.mutation == "" then 0 else (table.find(config.mutations.order, item.mutation) or 99)
	end
	local function name(item: Item): string
		local flavor = flavors[item.flavor]
		return if flavor and flavor.name then flavor.name else item.flavor
	end
	table.sort(list, function(a, b)
		local ra = ScoopChest.rank(ScoopChest.rarityOf(a, flavors), rarities)
		local rb = ScoopChest.rank(ScoopChest.rarityOf(b, flavors), rarities)
		if ra ~= rb then
			return ra > rb
		end
		local ma, mb = mutationRank(a), mutationRank(b)
		if ma ~= mb then
			return ma < mb
		end
		local na, nb = name(a), name(b)
		if na ~= nb then
			return na < nb
		end
		return a.mutation < b.mutation
	end)
	return list
end

-- Luck: a caught scoop of `flavorId` turns into one of the next rarer rarity that has flavors in `pool` (skipping
-- rarities without any) when `roll` (0..1) is under `luck`; `pick` (0..1) chooses among them by weight. Returns the
-- new flavor id, or nil when nothing changes (no luck, the rarest already, nothing rarer in the pool).
function ScoopChest.luckyFlavor(
	flavorId: string,
	luck: number,
	roll: number,
	pick: number,
	pool: { { id: string, rarity: string, weight: number } },
	flavors: Flavors,
	rarities: { string }
): string?
	local flavor = flavors[flavorId]
	if not flavor or luck <= 0 or roll >= luck then
		return nil
	end
	local rank = ScoopChest.rank(flavor.rarity, rarities)
	if rank == 0 then
		return nil
	end
	for next = rank + 1, #rarities do
		local candidates = {}
		local total = 0
		for _, entry in pool do
			if entry.rarity == rarities[next] and entry.weight > 0 then
				table.insert(candidates, entry)
				total += entry.weight
			end
		end
		if #candidates > 0 then
			local left = math.clamp(pick, 0, 1) * total
			for _, entry in candidates do
				left -= entry.weight
				if left <= 0 then
					return entry.id
				end
			end
			return candidates[#candidates].id
		end
	end
	return nil
end

return ScoopChest
