--!strict
-- Serve value, topple losses, walk speed and upgrades. The server is the only one that pays out; the client
-- uses the same functions to preview the tower value.

export type ValueFlavor = { value: number }

export type StackMatch = {
	from: number,
	to: number,
	effect: {
		kind: string,
		scope: string?,
		factor: number?,
	},
}

export type ServeOptions = {
	steadyBonus: number?,
	serveMultiplier: number?,
	stacks: { StackMatch }?,
	-- tower indices that are not sold (they went into the Scoop Chest): they pay nothing, but still count for the
	-- height multiplier, so keeping a rare scoop never makes the rest of a tall tower worth less
	kept: { [number]: boolean }?,
	coinBonus: number?, -- the Scoop Chest's coins passive (0.05 = +5 %)
	towerBonus: number?, -- the Scoop Chest's tower bonus as it counts for this tower (Economy.towerBonus), added to coinBonus
}

export type Config = {
	heightFactor: number,
	spillShare: number,
	spillAllUpTo: number,
	baseWalkSpeed: number,
	towerSlow: { walk: number, dash: number, jump: number?, curve: number },
	minWalkSpeed: number,
	sprintMultiplier: number,
	upgrades: {
		cone: { costs: { number }, capacity: { number }, stiffness: { number } },
		sneakers: { costs: { number }, speed: { number }, penaltyScale: { number } },
		cart: { costs: { number }, serveMultiplier: { number } },
	},
}

local Economy = {}

local function level(values: { number }, upgradeLevel: number): number
	return values[math.clamp(upgradeLevel, 0, #values - 1) + 1]
end

function Economy.heightMultiplier(count: number, config: Config): number
	local factor = 1 + config.heightFactor * count
	return factor * factor
end

-- flavorIds are bottom to top.
function Economy.serveValue(
	flavorIds: { string },
	flavors: { [string]: ValueFlavor },
	config: Config,
	options: ServeOptions?
): number
	local count = #flavorIds
	if count == 0 then
		return 0
	end

	local opts: ServeOptions = options or {}
	local perScoop = table.create(count, 1)
	local towerFactor = 1
	for _, match in opts.stacks or {} do
		local effect = match.effect
		if effect.kind == "valueMultiplier" then
			local factor = effect.factor or 1
			if effect.scope == "tower" then
				towerFactor *= factor
			else
				for index = match.from, match.to do
					perScoop[index] *= factor
				end
			end
		end
	end

	local kept = opts.kept or {}
	local base = 0
	for index, id in flavorIds do
		local flavor = flavors[id]
		if not kept[index] then
			base += (if flavor then flavor.value else 0) * perScoop[index]
		end
	end

	local steady = math.max(0, opts.steadyBonus or 0)
	local serveMultiplier = opts.serveMultiplier or 1
	local coinBonus = math.max(0, opts.coinBonus or 0) + math.max(0, opts.towerBonus or 0)
	return base
		* Economy.heightMultiplier(count, config)
		* (1 + steady)
		* serveMultiplier
		* towerFactor
		* (1 + coinBonus)
end

-- The Scoop Chest's tower bonus (Config/Chest passives.kinds.tower) for a tower of `count` scoops: nothing below
-- `from`, then rising evenly to the whole `bonus` at `full` scoops and above.
function Economy.towerBonus(count: number, bonus: number, from: number, full: number): number
	if bonus <= 0 or count < from then
		return 0
	end
	local share = if full > from then (count - from + 1) / (full - from + 1) else 1
	return bonus * math.clamp(share, 0, 1)
end

-- How many scoops stay on the cone when a tower topples or its carrier is knocked down: none of a small tower (up to
-- spillAllUpTo), else what is left after spillShare fell from the top (rounded to the nearest scoop). The rest spill
-- (Loot).
function Economy.keepOnTopple(count: number, config: Config): number
	if count <= config.spillAllUpTo then
		return 0
	end
	local spilled = math.floor(count * config.spillShare + 0.5)
	return math.clamp(count - spilled, 0, count)
end

-- How much the tower weighs on its carrier, 0..1: (scoops / capacity) ^ towerSlow.curve, a soft curve that stays small
-- while the waffle is far from full.
function Economy.towerLoad(count: number, capacity: number, config: Config): number
	if capacity <= 0 then
		return 0
	end
	return math.clamp(count / capacity, 0, 1) ^ config.towerSlow.curve
end

-- Walking speed with `count` scoops in a waffle of `capacity`: the tower's load costs up to towerSlow.walk of it (less
-- with sneakers, their penaltyScale), never below minWalkSpeed; sprinting multiplies it by sprintMultiplier.
function Economy.walkSpeed(
	count: number,
	capacity: number,
	sneakersLevel: number,
	config: Config,
	sprinting: boolean?
): number
	local sneakers = config.upgrades.sneakers
	local speed = config.baseWalkSpeed * level(sneakers.speed, sneakersLevel)
	local slow = config.towerSlow.walk * level(sneakers.penaltyScale, sneakersLevel)
	local walk = math.max(config.minWalkSpeed, speed * (1 - slow * Economy.towerLoad(count, capacity, config)))
	return if sprinting then walk * config.sprintMultiplier else walk
end

-- The share of the dash's distance (its duration) left with that tower: 1 - towerSlow.dash x load (less with sneakers).
function Economy.dashScale(count: number, capacity: number, sneakersLevel: number, config: Config): number
	local slow = config.towerSlow.dash * level(config.upgrades.sneakers.penaltyScale, sneakersLevel)
	return 1 - slow * Economy.towerLoad(count, capacity, config)
end

-- The share of a gummy pad's jump height left with that tower (Config/Bounce): 1 - towerSlow.jump x load.
function Economy.jumpScale(count: number, capacity: number, config: Config): number
	return 1 - (config.towerSlow.jump or 0) * Economy.towerLoad(count, capacity, config)
end

function Economy.capacity(coneLevel: number, config: Config): number
	return level(config.upgrades.cone.capacity, coneLevel)
end

function Economy.coneStiffness(coneLevel: number, config: Config): number
	return level(config.upgrades.cone.stiffness, coneLevel)
end

function Economy.serveMultiplier(cartLevel: number, config: Config): number
	return level(config.upgrades.cart.serveMultiplier, cartLevel)
end

-- Cost of the next level, or nil when the track is maxed.
function Economy.upgradeCost(track: "cone" | "sneakers" | "cart", currentLevel: number, config: Config): number?
	local costs = config.upgrades[track].costs
	return costs[currentLevel + 1]
end

return Economy
