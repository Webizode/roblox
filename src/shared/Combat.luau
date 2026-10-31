--!strict
-- Pure maths for the ice-ball throw: the flight curve, the hit test against a player capsule, the headshot, hit power
-- and the ammo rules (the knockdown points are HitPoints). No Roblox globals; CombatService and CombatController use the same
-- functions, and tests/Combat.spec.luau covers them.

export type Config = {
	ammo: number,
	reloadPerBall: number,
	reloadDelay: number,
	throwInterval: number,
	perfect: { rise: number, window: number, speed: number },
	chargeTolerance: number,
	minSpeed: number,
	maxSpeed: number,
	powerAtMinCharge: number,
	lift: number,
	gravity: number,
	maxFlight: number,
	ballRadius: number,
	hitRadius: number,
	hitHalfHeight: number,
	minPower: number,
	headZoneScale: number,
}

export type Ammo = {
	count: number,
	reloadUntil: number, -- server time the next ball is loaded, 0 while the load is full
	lastThrowAt: number,
}

local Combat = {}

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- Position after t seconds of flight.
function Combat.position(
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	gravity: number,
	t: number
): (number, number, number)
	return ox + vx * t, oy + vy * t - 0.5 * gravity * t * t, oz + vz * t
end

-- The throw's strength after holding the button for `held` seconds: 0 for a tap, rising to 1 at perfect.rise, and 1
-- from then on.
function Combat.strength(held: number, config: Config): number
	if not isFinite(held) or held <= 0 then
		return 0
	end
	return math.min(1, held / config.perfect.rise)
end

-- The crosshair's inner circle after holding for `held` seconds, as a share of the outer circle: from 0 (the middle)
-- up to 1 (touching the outer circle) in perfect.rise, back down in the same time, and again while held.
function Combat.pulse(held: number, config: Config): number
	if not isFinite(held) or held <= 0 then
		return 0
	end
	local rise = config.perfect.rise
	local phase = held % (2 * rise)
	return if phase <= rise then phase / rise else 2 - phase / rise
end

-- How far (seconds) `held` is from the nearest moment the inner circle touches the outer one (rise, 3 rise, ...).
local function fromTouch(held: number, config: Config): number
	local rise = config.perfect.rise
	local k = math.max(0, math.floor((held - rise) / (2 * rise) + 0.5))
	return math.abs(held - (rise + 2 * rise * k))
end

-- Whether letting go after `held` seconds is a perfect throw: within perfect.window around a moment the inner circle
-- touches the outer one.
function Combat.isPerfect(held: number, config: Config): boolean
	return isFinite(held) and held > 0 and fromTouch(held, config) <= config.perfect.window / 2
end

-- The strength the server accepts: the client's claim as far as a hold within chargeTolerance of the server's own
-- measured one gives it, otherwise the nearest such value. A client can never claim more than its real hold allows,
-- and network jitter costs an honest player nothing.
function Combat.validateStrength(claimed: number, held: number, config: Config): number
	if not isFinite(held) or held < 0 then
		held = 0
	end
	local low = Combat.strength(held - config.chargeTolerance, config)
	local high = Combat.strength(held + config.chargeTolerance, config)
	if not isFinite(claimed) then
		return Combat.strength(held, config)
	end
	return math.clamp(claimed, low, high)
end

-- Whether the server accepts a claimed perfect throw: only if some hold within chargeTolerance of its own measured
-- one is perfect.
function Combat.validatePerfect(claimed: boolean, held: number, config: Config): boolean
	if claimed ~= true or not isFinite(held) or held < 0 then
		return false
	end
	return fromTouch(held, config) <= config.perfect.window / 2 + config.chargeTolerance
end

-- How the ball in the hand of a player charging since `startedAt` (server time, the ChargeStartedAt attribute) glows
-- at `now`: its strength (0..1, the glow's share) and whether letting go would be perfect (the bright green glow).
-- Nothing while not charging (startedAt nil or not a number) or for a start in the future.
function Combat.chargeGlow(startedAt: any, now: number, config: Config): (number, boolean)
	if type(startedAt) ~= "number" or not isFinite(startedAt) then
		return 0, false
	end
	local held = now - startedAt
	if held <= 0 then
		return 0, false
	end
	return Combat.strength(held, config), Combat.isPerfect(held, config)
end

-- Release speed at `strength` in [0, 1]; a perfect throw goes at perfect.speed.
function Combat.throwSpeed(strength: number, perfect: boolean, config: Config): number
	if perfect then
		return config.perfect.speed
	end
	return config.minSpeed + (config.maxSpeed - config.minSpeed) * math.clamp(strength, 0, 1)
end

-- Launch velocity from the release point (ox, oy, oz) through the aim point (tx, ty, tz) at `speed`: the flat arc
-- that passes through the aim point under gravity. A point out of reach (or not reached within maxFlight) gets a
-- straight aim with a little lift instead, so the ball falls short of it. Returns false for aims no real client
-- produces (not finite, or the aim point at the hand).
function Combat.aimVelocity(
	ox: number,
	oy: number,
	oz: number,
	tx: number,
	ty: number,
	tz: number,
	speed: number,
	config: Config
): (boolean, number, number, number)
	if not (isFinite(ox) and isFinite(oy) and isFinite(oz) and isFinite(tx) and isFinite(ty) and isFinite(tz)) then
		return false, 0, 0, 0
	end
	local dx, dy, dz = tx - ox, ty - oy, tz - oz
	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	if distance < 0.5 or not isFinite(distance) then
		return false, 0, 0, 0
	end
	local flat = math.sqrt(dx * dx + dz * dz)
	local g, v2 = config.gravity, speed * speed
	if flat > 1e-3 then
		local discriminant = v2 * v2 - g * (g * flat * flat + 2 * dy * v2)
		if discriminant >= 0 then
			local tangent = (v2 - math.sqrt(discriminant)) / (g * flat)
			local cos = 1 / math.sqrt(1 + tangent * tangent)
			if flat / (speed * cos) <= config.maxFlight then
				local horizontal = speed * cos / flat
				return true, dx * horizontal, speed * cos * tangent, dz * horizontal
			end
		end
	end
	local ux, uy, uz = dx / distance, dy / distance + config.lift, dz / distance
	local length = math.sqrt(ux * ux + uy * uy + uz * uz)
	return true, ux / length * speed, uy / length * speed, uz / length * speed
end

-- Shortest distance between the flight segment a->b and the vertical axis segment of a capsule centred at c,
-- plus where along a->b (0..1) it is closest. Exact segment-to-segment distance.
function Combat.closestToCapsule(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	cx: number,
	cy: number,
	cz: number,
	halfHeight: number
): (number, number)
	-- segment 1: p(s) = a + s*d1, segment 2: q(u) = (c - h*up) + u*d2 with d2 = (0, 2h, 0)
	local d1x, d1y, d1z = bx - ax, by - ay, bz - az
	local d2y = 2 * halfHeight
	local rx, ry, rz = ax - cx, ay - (cy - halfHeight), az - cz
	local a = d1x * d1x + d1y * d1y + d1z * d1z
	local e = d2y * d2y
	local f = d2y * ry
	local s, u
	if a <= 1e-9 then
		s = 0
		u = math.clamp(f / e, 0, 1)
	else
		local c = d1x * rx + d1y * ry + d1z * rz
		local b = d1y * d2y
		local denom = a * e - b * b
		s = if denom > 1e-9 then math.clamp((b * f - c * e) / denom, 0, 1) else 0
		u = (b * s + f) / e
		if u < 0 then
			u = 0
			s = math.clamp(-c / a, 0, 1)
		elseif u > 1 then
			u = 1
			s = math.clamp((b - c) / a, 0, 1)
		end
	end
	local px, py, pz = ax + d1x * s, ay + d1y * s, az + d1z * s
	local qx, qy, qz = cx, cy - halfHeight + d2y * u, cz
	local dx, dy, dz = px - qx, py - qy, pz - qz
	return math.sqrt(dx * dx + dy * dy + dz * dz), s
end

-- How centred a hit is: the closest the ball's path comes to the axis of the capsule centred at (cx, cy, cz), from
-- `fromT` (the moment it touched the capsule) on through the capsule. The frame step that finds a hit only sees the
-- short piece of path where the ball entered, always near the edge of the reach, so its distance there would make every
-- hit look grazing; this follows the arc on through the body in fine steps instead.
function Combat.passDistance(
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	fromT: number,
	cx: number,
	cy: number,
	cz: number,
	config: Config
): number
	local reach = config.hitRadius + config.ballRadius
	local speed = math.max(math.sqrt(vx * vx + (vy - config.gravity * fromT) ^ 2 + vz * vz), 1)
	local span = 2 * reach / speed -- long enough to cross the whole capsule
	local steps = 24
	local px, py, pz = Combat.position(ox, oy, oz, vx, vy, vz, config.gravity, fromT)
	local best = math.huge
	for step = 1, steps do
		local t = fromT + span * step / steps
		local qx, qy, qz = Combat.position(ox, oy, oz, vx, vy, vz, config.gravity, t)
		local distance = Combat.closestToCapsule(px, py, pz, qx, qy, qz, cx, cy, cz, config.hitHalfHeight)
		best = math.min(best, distance)
		px, py, pz = qx, qy, qz
	end
	return best
end

-- Closest distance from the point c to the segment a->b, and where along a->b (0..1) it is.
local function pointToSegment(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	cx: number,
	cy: number,
	cz: number
): (number, number)
	local dx, dy, dz = bx - ax, by - ay, bz - az
	local length2 = dx * dx + dy * dy + dz * dz
	local s = if length2 > 1e-9
		then math.clamp(((cx - ax) * dx + (cy - ay) * dy + (cz - az) * dz) / length2, 0, 1)
		else 0
	local px, py, pz = ax + dx * s - cx, ay + dy * s - cy, az + dz * s - cz
	return math.sqrt(px * px + py * py + pz * pz), s
end

export type Head = { x: number, y: number, z: number, radius: number }
export type TowerColumn = { x: number, y: number, z: number, height: number, radius: number } -- y: its bottom

-- Whether a ball that touched the body capsule at `fromT` is a headshot: following its arc on through the body (as
-- passDistance does), it reaches the head zone (the head's radius times headZoneScale, plus the ball) with its centre
-- at head height (above the bottom of the head itself) before it reaches the tower column on the back. Only the head
-- counts: a ball at the chest that grazes the chin is a body hit, and a tower in the way (a throw from behind) makes
-- it a normal hit. `tower` is nil without scoops. The server decides this from the flight alone.
function Combat.isHeadshot(
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	fromT: number,
	head: Head,
	tower: TowerColumn?,
	config: Config
): boolean
	local headReach = head.radius * config.headZoneScale + config.ballRadius
	local reach = config.hitRadius + config.ballRadius
	local speed = math.max(math.sqrt(vx * vx + (vy - config.gravity * fromT) ^ 2 + vz * vz), 1)
	local span = 2 * reach / speed -- long enough to cross the whole capsule
	local steps = 32
	local px, py, pz = Combat.position(ox, oy, oz, vx, vy, vz, config.gravity, fromT)
	for step = 1, steps do
		local t = fromT + span * step / steps
		local qx, qy, qz = Combat.position(ox, oy, oz, vx, vy, vz, config.gravity, t)
		local headDistance, headS = pointToSegment(px, py, pz, qx, qy, qz, head.x, head.y, head.z)
		local towerS = math.huge
		if tower and tower.height > 0 then
			local half = tower.height / 2
			local distance, s = Combat.closestToCapsule(px, py, pz, qx, qy, qz, tower.x, tower.y + half, tower.z, half)
			if distance <= tower.radius + config.ballRadius then
				towerS = s
			end
		end
		if headDistance <= headReach and py + (qy - py) * headS >= head.y - head.radius then
			return headS < towerS
		end
		if towerS < math.huge then
			return false
		end
		px, py, pz = qx, qy, qz
	end
	return false
end

-- Hit power, at most 1: a centred hit (distance 0) of a full-strength ball that has not slowed down yet is
-- strongest; grazing, slowed-down (impact speed below its release speed) and weaker (tapped) ones are less. A
-- perfect throw is full strength: faster, so it slows down less, but no harder.
function Combat.hitPower(
	distance: number,
	impactSpeed: number,
	releaseSpeed: number,
	strength: number,
	config: Config
): number
	local reach = config.hitRadius + config.ballRadius
	local centred = math.clamp(1 - distance / reach, 0, 1)
	local speedFactor = math.clamp(impactSpeed / math.max(releaseSpeed, 1e-6), 0.6, 1)
	local strengthFactor = config.powerAtMinCharge + (1 - config.powerAtMinCharge) * math.clamp(strength, 0, 1)
	local floor = config.minPower * 0.6 * config.powerAtMinCharge
	return math.clamp(speedFactor * strengthFactor * (config.minPower + (1 - config.minPower) * centred), floor, 1)
end

function Combat.newAmmo(config: Config): Ammo
	return { count = config.ammo, reloadUntil = 0, lastThrowAt = -math.huge }
end

-- Loads the balls whose time has come: one after another, reloadPerBall each, until the load is full again.
function Combat.refresh(ammo: Ammo, now: number, config: Config)
	while ammo.count < config.ammo and ammo.reloadUntil > 0 and now >= ammo.reloadUntil do
		ammo.count += 1
		ammo.reloadUntil = if ammo.count < config.ammo then ammo.reloadUntil + config.reloadPerBall else 0
	end
	if ammo.count >= config.ammo then
		ammo.reloadUntil = 0
	end
end

-- Spends one throw if a ball is loaded and the throw interval has passed. Every throw costs one, hit or miss, and
-- (re)starts the reload: the next ball is ready reloadDelay + reloadPerBall after it. A ball half loaded when the
-- throw comes starts over, so throwing keeps the reload waiting.
function Combat.tryThrow(ammo: Ammo, now: number, config: Config): boolean
	Combat.refresh(ammo, now, config)
	if ammo.count <= 0 or now - ammo.lastThrowAt < config.throwInterval then
		return false
	end
	ammo.count -= 1
	ammo.lastThrowAt = now
	ammo.reloadUntil = now + config.reloadDelay + config.reloadPerBall
	return true
end

-- What the ammo displays (the HUD circles, the ball in the hand) show for the replicated ammo: how many balls are
-- loaded and how far the next one has loaded (0..1; 0 while the load is full or the reload still waits after a
-- throw). Inputs come from attributes, so anything out of range is clamped. The count only rises when the server
-- says so; until then a finished ball shows as fully loaded.
function Combat.ammoDisplay(count: number, reloadUntil: number, now: number, config: Config): (number, number)
	local loaded = if count == count then math.clamp(math.floor(count), 0, config.ammo) else 0
	if loaded >= config.ammo or not isFinite(reloadUntil) or reloadUntil <= 0 then
		return loaded, 0
	end
	return loaded, math.clamp(1 - (reloadUntil - now) / config.reloadPerBall, 0, 1)
end

return Combat
