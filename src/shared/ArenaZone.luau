--!strict
-- The arena zone (Config/Map.arena): the sunken floor round the Big Swirl, a disc of `radius`, and the ramps out of
-- it, each a strip `rampHalfWidth` either side of its lane up to `rampTop`, where the safe zone starts. It reaches up
-- and down without end, so jumping never takes anyone out of it. Pure: server (ArenaService, the Studio tools) and
-- client (the teleport buttons) ask the same function.

export type Config = {
	center: { x: number, z: number },
	radius: number,
	ramps: number,
	firstRamp: number,
	rampHalfWidth: number,
	rampTop: number,
}

local ArenaZone = {}

-- The direction (sin, cos on X/Z) of the lane `index` (1-based) round the machine.
function ArenaZone.lane(index: number, config: Config): (number, number)
	local angle = math.rad(config.firstRamp + (index - 1) * 360 / config.ramps)
	return math.sin(angle), math.cos(angle)
end

-- The lane (1-based) nearest to the direction from the machine to (x, z).
function ArenaZone.nearestLane(x: number, z: number, config: Config): number
	local dx, dz = x - config.center.x, z - config.center.z
	local angle = math.deg(math.atan2(dx, dz))
	local step = 360 / config.ramps
	local index = math.floor((angle - config.firstRamp) / step + 0.5)
	return index % config.ramps + 1
end

-- Whether the point (x, z) lies in the arena: on the floor disc, or on a ramp up to its top edge. `slack` (studs,
-- default 0) widens the zone all round; the server uses it for the position it sees a little late.
function ArenaZone.contains(x: number, z: number, config: Config, slack: number?): boolean
	local extra = slack or 0
	local dx, dz = x - config.center.x, z - config.center.z
	local radius = config.radius + extra
	if dx * dx + dz * dz <= radius * radius then
		return true
	end
	local sx, sz = ArenaZone.lane(ArenaZone.nearestLane(x, z, config), config)
	local along = dx * sx + dz * sz
	local across = dx * sz - dz * sx
	return along > 0 and along <= config.rampTop + extra and math.abs(across) <= config.rampHalfWidth + extra
end

return ArenaZone
