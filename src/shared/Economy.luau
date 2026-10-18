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
}

export type Config = {
	heightFactor: number,
	keepOnToppleFraction: number,
	keepOnToppleMin: number,
	baseWalkSpeed: number,
	walkSpeedPenaltyPerScoop: number,
	minWalkSpeed: number,
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

	local base = 0
	for index, id in flavorIds do
		local flavor = flavors[id]
		base += (if flavor then flavor.value else 0) * perScoop[index]
	end

	local steady = math.max(0, opts.steadyBonus or 0)
	local serveMultiplier = opts.serveMultiplier or 1
	return base * Economy.heightMultiplier(count, config) * (1 + steady) * serveMultiplier * towerFactor
end

-- How many scoops stay on the cone when a tower topples. The rest roll away.
function Economy.keepOnTopple(count: number, config: Config): number
	local keep = math.max(config.keepOnToppleMin, math.floor(count * config.keepOnToppleFraction))
	return math.min(count, keep)
end

function Economy.walkSpeed(count: number, sneakersLevel: number, config: Config): number
	local sneakers = config.upgrades.sneakers
	local speed = config.baseWalkSpeed * level(sneakers.speed, sneakersLevel)
	local penalty = config.walkSpeedPenaltyPerScoop * level(sneakers.penaltyScale, sneakersLevel)
	return math.max(config.minWalkSpeed, speed / (1 + penalty * count))
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
