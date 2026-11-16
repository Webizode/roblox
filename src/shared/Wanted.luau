--!strict
-- The "wanted" rules (Config/Wanted): who becomes wanted, how long, and where a wanted player may stand. Pure: the
-- server (WantedService) and the client (the Wanted controller) ask the same functions, tests/Wanted.spec.luau pins
-- them down.

export type Config = {
	duration: number,
	stopShort: number,
}

export type Arena = {
	center: { x: number, z: number },
	radius: number,
	ramps: number,
	firstRamp: number,
	rampHalfWidth: number,
	rampTop: number,
}

local Wanted = {}

-- Whether picking up this free scoop is stealing: spilled from somebody else's tower (Big Swirl scoops never are).
function Wanted.isStolen(landed: boolean, owner: number, picker: number): boolean
	return not landed and owner ~= picker
end

-- Until when a player who stole at `now` is wanted. Every further stolen scoop starts it over, never adds up.
function Wanted.untilAfterSteal(now: number, config: Config): number
	return now + config.duration
end

-- The whole seconds left to show (10, 9, ... 1), 0 once it has run out. Odd inputs (attributes) count as run out.
function Wanted.secondsLeft(untilAt: number, now: number): number
	if untilAt ~= untilAt or now ~= now then
		return 0
	end
	local left = untilAt - now
	return if left > 0 then math.ceil(left) else 0
end

-- The nearest point a wanted player may stand at, for one at (x, z): anywhere on the arena floor, on a ramp only up
-- to `limit` studs from the machine (and within its width). Returns that point and how far (x, z) is from it (0
-- when the point is allowed).
function Wanted.allowedPoint(x: number, z: number, arena: Arena, limit: number): (number, number, number)
	local cx, cz = arena.center.x, arena.center.z
	local dx, dz = x - cx, z - cz
	if dx * dx + dz * dz <= arena.radius * arena.radius then
		return x, z, 0
	end
	-- the nearest ramp lane
	local angle = math.deg(math.atan2(dx, dz))
	local step = 360 / arena.ramps
	local index = math.floor((angle - arena.firstRamp) / step + 0.5) % arena.ramps
	local laneAngle = math.rad(arena.firstRamp + index * step)
	local sx, sz = math.sin(laneAngle), math.cos(laneAngle)
	local along = dx * sx + dz * sz
	local across = dx * sz - dz * sx
	local allowedAlong = math.clamp(along, 0, math.max(limit, 0))
	local allowedAcross = math.clamp(across, -arena.rampHalfWidth, arena.rampHalfWidth)
	-- back from (along, across) to the world: dx = along * s + across * (sz, -sx)
	local px = cx + allowedAlong * sx + allowedAcross * sz
	local pz = cz + allowedAlong * sz - allowedAcross * sx
	local ox, oz = x - px, z - pz
	return px, pz, math.sqrt(ox * ox + oz * oz)
end

-- The line a wanted player is held behind: stopShort studs before the ramps' top edge.
function Wanted.limit(arena: Arena, config: Config): number
	return arena.rampTop - config.stopShort
end

-- Where the server puts a wanted player back who got `slack` studs or more past the line, `back` studs inside it.
-- nil while they are within the slack, or when they are farther than `maxPull` past it (they did not walk there).
function Wanted.pullBackTo(
	x: number,
	z: number,
	arena: Arena,
	config: Config,
	slack: number,
	back: number,
	maxPull: number
): (number?, number?)
	local line = Wanted.limit(arena, config)
	local _, _, past = Wanted.allowedPoint(x, z, arena, line)
	if past < slack or past > maxPull then
		return nil, nil
	end
	local px, pz = Wanted.allowedPoint(x, z, arena, line - back)
	return px, pz
end

return Wanted
