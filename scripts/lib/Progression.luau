--!strict
-- The progression simulation (scripts/progression.luau, tests/Progression.spec): one player plays for hours and buys
-- upgrades, with the game's own rules and configs. Everything that decides money is the real code:
--   the Big Swirl's flavor     FlavorOdds.pick with Config/Flavors (rarity chances, pools)
--   luck                       Luck.total (chest + upgrade source, each at its cap) and ScoopChest.luckyFlavor
--   the Scoop Chest            ScoopChest.store (rare scoops kept, maxPerFlavor, capacity), ScoopChest.bonuses
--   a serve                    Economy.serveValue (height, serve multiplier, kept scoops, coins and tower bonus)
--   the topple                 Economy.keepOnTopple
--   upgrades                   Upgrades.value / cost / buy with the given upgrade config
-- What the code cannot say is how a person plays. Those assumptions are the PLAY table below, measured where possible:
--   catchesPerMinute  6.8 by the debug dummies with 12 players and 6.9 with 4 (Studio, 25.11.2026). They run the best
--                     path to every reachable scoop, never fight and never topple, so a real player catches less;
--                     the default takes 70 % of it.
--   overhead          seconds per serve trip on top of the catching: out of the arena, the MY PLOT teleport, the serve,
--                     the ARENA teleport and back in.
--   comfort           a player carries until the tower is this many scoops past where walking gets wobbly
--                     (Config/Tower.walkHeavyFrom, raised by Stability), at most the cone's capacity. 10 + 4 = 14 at the
--                     start, inside the kill test's target of a median serve of 8 to 15 scoops.
--   topple            the chance a trip ends in a topple or a knockdown: base + perScoop for every scoop past the
--                     wobbly height. Then the tower spills by the game's rule and `recover` of what fell is picked up.
--   steady            the average steady bonus of a serve of 10 and more (the server caps it at 0.25).
-- The player equips the strongest stored scoops and always buys the cheapest next level it can afford.

local Economy = require("../../src/shared/Economy")
local FlavorOdds = require("../../src/shared/FlavorOdds")
local Luck = require("../../src/shared/Luck")
local ScoopChest = require("../../src/shared/ScoopChest")
local Upgrades = require("../../src/shared/Upgrades")
local Flavors = require("../../src/shared/Config/Flavors")
local EconomyConfig = require("../../src/shared/Config/Economy")
local ChestConfig = require("../../src/shared/Config/Chest")
local LuckConfig = require("../../src/shared/Config/Luck")
local TowerConfig = require("../../src/shared/Config/Tower")

local Progression = {}

Progression.PLAY = {
	catchesPerMinute = 6.8 * 0.7,
	overhead = 12,
	comfort = 4,
	topple = { base = 0.1, perScoop = 0.025, max = 0.7, recover = 0.5 },
	steady = 0.1,
}

export type Snapshot = {
	minute: number,
	coins: number, -- held
	earned: number, -- all coins so far
	levels: { [string]: number },
}

export type Result = {
	snapshots: { Snapshot }, -- one per `every` minutes
	firstUpgrade: number?, -- minute of the first purchase
	reached: { [number]: number? }, -- level -> minute when every sold upgrade had that share of its levels (of the longest)
	allMax: number?, -- minute when every sold upgrade was at the top
}

local pools = FlavorOdds.pools(Flavors.list, function(flavor)
	return not flavor.placeholder
end)
local luckPool = {}
for _, flavor in Flavors.list do
	if not flavor.placeholder then
		table.insert(luckPool, { id = flavor.id, rarity = flavor.rarity, weight = flavor.weight })
	end
end

-- Numbers in [0, 1) from a seed (Park-Miller, exact in doubles; Lune has no Roblox Random), the same every run.
local function newRandom(seed: number)
	local state = seed % 2147483646 + 1
	return {
		NextNumber = function(_self): number
			state = state * 48271 % 2147483647
			return (state - 1) / 2147483646
		end,
	}
end

local function chestConfigFor(slots: number): any
	local config = table.clone(ChestConfig)
	config.equipSlots = slots
	return config
end

-- Equips the stacks with the biggest bonus (each kind counts alike), as many as there are slots.
local function equipBest(chest: ScoopChest.Chest, config: any)
	local ranked = {}
	for _, item in chest.items do
		local _, amount = ScoopChest.passiveOf(item, Flavors.byId, config)
		table.insert(ranked, { key = ScoopChest.key(item.flavor, item.mutation), amount = amount })
	end
	table.sort(ranked, function(a, b)
		return a.amount > b.amount
	end)
	table.clear(chest.equipped)
	for index = 1, math.min(config.equipSlots, #ranked) do
		table.insert(chest.equipped, ranked[index].key)
	end
end

-- Plays `hours` hours. `upgrades` is the upgrade config to test (Config/Upgrades or a proposal); `play` overrides
-- PLAY; `seed` the random numbers. Snapshots every `every` minutes (default 1).
function Progression.run(upgrades: any, hours: number, seed: number, play: { [string]: any }?, every: number?): Result
	local P = table.clone(Progression.PLAY)
	for key, value in play or {} do
		P[key] = value
	end
	local rng = newRandom(seed)
	local sold = Upgrades.visible(upgrades)
	local longest = 0
	for _, id in sold do
		longest = math.max(longest, upgrades.tracks[id].maxLevel)
	end
	local levels: { [string]: number } = {}
	for id in upgrades.tracks do
		levels[id] = 0
	end
	local wallet = { coins = 0, upgrades = levels }
	local chest: ScoopChest.Chest = { items = {}, equipped = {} }
	local seen: { [string]: number } = {}
	local earned = 0
	local t = 0 -- seconds
	local stop = hours * 3600
	local step = (every or 1) * 60
	local nextSnap = 0
	local result: Result = { snapshots = {}, firstUpgrade = nil, reached = {}, allMax = nil }

	local function value(id: string): number
		return Upgrades.value(id, levels[id] or 0, upgrades)
	end
	local function hasTrack(id: string): boolean
		return upgrades.tracks[id] ~= nil
	end

	local function snapshot()
		while t >= nextSnap and nextSnap <= stop do
			table.insert(result.snapshots, {
				minute = nextSnap / 60,
				coins = wallet.coins,
				earned = earned,
				levels = table.clone(levels),
			})
			nextSnap += step
		end
	end

	local function checkReached()
		-- "level L" counts as a share of the longest track: an upgrade with fewer levels (Equip Slots, 3) needs the
		-- same share of its own (level 5 of 25 = 20 %: 1 of 3 slots)
		local allTop = true
		for level = 1, longest do
			if result.reached[level] then
				continue
			end
			local share = level / longest
			local ok = true
			for _, id in sold do
				local top = upgrades.tracks[id].maxLevel
				if levels[id] < math.ceil(share * top - 1e-9) then
					ok = false
					break
				end
			end
			if not ok then
				break
			end
			result.reached[level] = t / 60
		end
		for _, id in sold do
			if levels[id] < upgrades.tracks[id].maxLevel then
				allTop = false
			end
		end
		if allTop and not result.allMax then
			result.allMax = t / 60
		end
	end

	local function buyAll()
		while true do
			local bestId, bestCost = nil, math.huge
			for _, id in sold do
				local cost = Upgrades.cost(id, levels[id], upgrades)
				if cost and cost < bestCost then
					bestId, bestCost = id, cost
				end
			end
			if not bestId or wallet.coins < bestCost then
				return
			end
			Upgrades.buy(wallet, bestId, levels[bestId], upgrades)
			result.firstUpgrade = result.firstUpgrade or t / 60
			checkReached()
		end
	end

	local secondsPerCatch = 60 / P.catchesPerMinute
	while t < stop do
		local capacity = if hasTrack("cone") then value("cone") else 20
		local heavyFrom = if hasTrack("stability") then value("stability") else TowerConfig.walkHeavyFrom
		local slots = if hasTrack("slots") then value("slots") else ChestConfig.equipSlots
		local chestConfig = chestConfigFor(slots)
		local bonuses = ScoopChest.bonuses(chest, Flavors.byId, chestConfig)
		local luck = Luck.total({
			chest = bonuses.luck or 0,
			upgrade = if hasTrack("luck") then value("luck") else 0,
		}, LuckConfig)
		local target = math.max(1, math.min(capacity, math.floor(heavyFrom + P.comfort)))

		-- catching up to the target
		local tower = {}
		for _ = 1, target do
			t += secondsPerCatch
			local id = FlavorOdds.pick(rng:NextNumber(), rng:NextNumber(), Flavors, pools)
			local lucky = ScoopChest.luckyFlavor(
				id,
				luck,
				rng:NextNumber(),
				rng:NextNumber(),
				luckPool,
				Flavors.byId,
				Flavors.rarities
			)
			table.insert(tower, lucky or id)
		end
		t += P.overhead

		-- the way home may end in a topple
		local over = math.max(0, #tower - heavyFrom)
		local chance = math.min(P.topple.max, P.topple.base + P.topple.perScoop * over)
		if rng:NextNumber() < chance then
			local keep = Economy.keepOnTopple(#tower, EconomyConfig)
			local fell = #tower - keep
			local back = math.floor(fell * P.topple.recover + 0.5)
			for index = #tower, keep + back + 1, -1 do
				tower[index] = nil
			end
		end

		-- the serve: rare scoops into the chest, the rest sold
		if #tower > 0 then
			local stored = ScoopChest.store(chest, tower, nil, Flavors.byId, Flavors.rarities, chestConfig, seen)
			local coins = Economy.serveValue(tower, Flavors.byId, EconomyConfig, {
				steadyBonus = if #tower >= 10 then P.steady else 0,
				serveMultiplier = if hasTrack("cart") then value("cart") else 1,
				kept = stored.kept,
				coinBonus = bonuses.coins or 0,
				towerBonus = Economy.towerBonus(
					#tower,
					bonuses.tower or 0,
					ChestConfig.passives.kinds.tower.from,
					ChestConfig.passives.kinds.tower.full
				),
			})
			wallet.coins += coins
			earned += coins
			for _, id in tower do
				seen[id] = (seen[id] or 0) + 1
			end
			equipBest(chest, chestConfig)
		end
		snapshot()
		buyAll()
	end
	snapshot()
	return result
end

-- The median of several runs (each with its own seed): minutes of the milestones and the snapshots' numbers.
function Progression.median(upgrades: any, hours: number, runs: number, play: { [string]: any }?, every: number?)
	local results = {}
	for seed = 1, runs do
		results[seed] = Progression.run(upgrades, hours, seed * 7919, play, every)
	end
	local function mid(values: { number }): number?
		if #values == 0 then
			return nil
		end
		table.sort(values)
		return values[(#values + 1) // 2]
	end
	local function minutes(get: (Result) -> number?): number?
		local values = {}
		for _, result in results do
			table.insert(values, get(result) or math.huge)
		end
		local value = mid(values)
		return if value == math.huge then nil else value
	end
	local median = {
		firstUpgrade = minutes(function(r)
			return r.firstUpgrade
		end),
		allMax = minutes(function(r)
			return r.allMax
		end),
		reached = {},
		snapshots = {},
	}
	local top = 0
	for _, id in Upgrades.visible(upgrades) do
		top = math.max(top, upgrades.tracks[id].maxLevel)
	end
	for level = 1, top do
		median.reached[level] = minutes(function(r)
			return r.reached[level]
		end)
	end
	for index, first in results[1].snapshots do
		local snap = { minute = first.minute, coins = 0, earned = 0, levels = {} }
		local coins, earned = {}, {}
		for _, result in results do
			local s = result.snapshots[index]
			if s then
				table.insert(coins, s.coins)
				table.insert(earned, s.earned)
			end
		end
		snap.coins = mid(coins) or 0
		snap.earned = mid(earned) or 0
		for id in upgrades.tracks do
			local values = {}
			for _, result in results do
				local s = result.snapshots[index]
				if s then
					table.insert(values, s.levels[id])
				end
			end
			snap.levels[id] = mid(values) or 0
		end
		median.snapshots[index] = snap
	end
	return median
end

return Progression
