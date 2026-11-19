--!strict
-- Which flavor the Big Swirl fires (LauncherService) and the chances behind it. Pure: the flavor config is passed in.
-- First a rarity by its chance (Config/Flavors.rarityChances, in percent), then one of its flavors, all equally likely.
-- A rarity without flavors (Mythic, Secret and Divine until they are built) gives its share to the first rarity
-- (common), so the chances always add up to 100.

export type Pools = { [string]: { string } }

local FlavorOdds = {}

-- The flavors that can be fired, by rarity, in list order. `include(flavor)` leaves some out (the placeholders).
function FlavorOdds.pools(flavors: { any }, include: ((flavor: any) -> boolean)?): Pools
	local pools: Pools = {}
	for _, flavor in flavors do
		if not include or include(flavor) then
			pools[flavor.rarity] = pools[flavor.rarity] or {}
			table.insert(pools[flavor.rarity], flavor.id)
		end
	end
	return pools
end

-- The chance of each rarity in percent, the share of a rarity without flavors moved to the first rarity.
function FlavorOdds.chances(config: any, pools: Pools): { [string]: number }
	local result: { [string]: number } = {}
	local first = config.rarities[1]
	local spare = 0
	for _, rarity in config.rarities do
		local chance = config.rarityChances[rarity] or 0
		if pools[rarity] and #pools[rarity] > 0 then
			result[rarity] = chance
		else
			result[rarity] = 0
			spare += chance
		end
	end
	result[first] += spare
	return result
end

-- The chance of one flavor in percent.
function FlavorOdds.flavorChance(flavorId: string, config: any, pools: Pools): number
	local flavor = config.byId[flavorId]
	local pool = flavor and pools[flavor.rarity]
	if not pool or not table.find(pool, flavorId) then
		return 0
	end
	return FlavorOdds.chances(config, pools)[flavor.rarity] / #pool
end

-- A flavor from two rolls in [0, 1): the first picks the rarity, the second the flavor in it.
function FlavorOdds.pick(rarityRoll: number, flavorRoll: number, config: any, pools: Pools): string
	local chances = FlavorOdds.chances(config, pools)
	local total = 0
	for _, rarity in config.rarities do
		total += chances[rarity]
	end
	local left = math.clamp(rarityRoll, 0, 1) * total
	local chosen = config.rarities[1]
	for _, rarity in config.rarities do
		if chances[rarity] > 0 then
			chosen = rarity
			left -= chances[rarity]
			if left < 0 then
				break
			end
		end
	end
	local pool = pools[chosen]
	local index = math.clamp(math.floor(math.clamp(flavorRoll, 0, 1) * #pool) + 1, 1, #pool)
	return pool[index]
end

return FlavorOdds
