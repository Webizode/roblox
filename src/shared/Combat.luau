--!strict
-- Pure maths for the ice-ball throw: the flight curve, the hit test against a player capsule, hit power, the
-- knockdown threshold and the ammo rules. No Roblox globals; CombatService and CombatController use the same
-- functions, and tests/Combat.spec.luau covers them.

export type Config = {
	ammo: number,
	reloadTime: number,
	throwInterval: number,
	chargeRise: number,
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
	staggerDecay: number,
	knockdownAt: number,
}

export type Ammo = {
	count: number,
	reloadUntil: number, -- server time the load refills, 0 while there is ammo left
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

-- The charge bar after holding the throw button for `held` seconds: up from 0 to 1 in chargeRise, back down to 0
-- in the same time, and again while held.
function Combat.charge(held: number, config: Config): number
	if not isFinite(held) or held <= 0 then
		return 0
	end
	local phase = held % (2 * config.chargeRise)
	return if phase <= config.chargeRise then phase / config.chargeRise else 2 - phase / config.chargeRise
end

-- The charge the server accepts for a throw: the client's bar value if some hold within chargeTolerance of the
-- server's own measured hold gives it, otherwise the nearest value such a hold gives. So a client can never claim
-- more than the hold it really made allows, and network jitter does not cost an honest player anything.
function Combat.validateCharge(claimed: number, held: number, config: Config): number
	if not isFinite(held) or held < 0 then
		held = 0
	end
	local from, to = math.max(0, held - config.chargeTolerance), held + config.chargeTolerance
	local period = 2 * config.chargeRise
	local low, high = 0, 1
	if to - from < period then
		local a, b = Combat.charge(from, config), Combat.charge(to, config)
		low, high = math.min(a, b), math.max(a, b)
		-- a peak (1) lies at chargeRise + k * period, a trough (0) at k * period
		if math.floor((to - config.chargeRise) / period) > math.floor((from - config.chargeRise) / period) then
			high = 1
		end
		if math.floor(to / period) > math.floor(from / period) then
			low = 0
		end
	end
	if not isFinite(claimed) then
		return Combat.charge(held, config)
	end
	return math.clamp(claimed, low, high)
end

-- Release speed for a charge in [0, 1].
function Combat.throwSpeed(charge: number, config: Config): number
	return config.minSpeed + (config.maxSpeed - config.minSpeed) * math.clamp(charge, 0, 1)
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

-- Hit power, at most 1: a centred hit (distance 0) of a fully charged ball that has not slowed down yet is
-- strongest; grazing, slowed-down (impact speed below its release speed) and less charged ones are weaker.
function Combat.hitPower(
	distance: number,
	impactSpeed: number,
	releaseSpeed: number,
	charge: number,
	config: Config
): number
	local reach = config.hitRadius + config.ballRadius
	local centred = math.clamp(1 - distance / reach, 0, 1)
	local speedFactor = math.clamp(impactSpeed / math.max(releaseSpeed, 1e-6), 0.6, 1)
	local chargeFactor = config.powerAtMinCharge + (1 - config.powerAtMinCharge) * math.clamp(charge, 0, 1)
	local floor = config.minPower * 0.6 * config.powerAtMinCharge
	return math.clamp(speedFactor * chargeFactor * (config.minPower + (1 - config.minPower) * centred), floor, 1)
end

-- Adds a hit to the victim's stagger. Returns the new stagger and whether this hit knocks them down (which
-- resets the stagger). A single hit is at most 1 and never reaches knockdownAt on its own.
function Combat.addHit(
	stagger: number,
	lastHitAt: number,
	now: number,
	power: number,
	config: Config
): (number, boolean)
	local drained = math.max(0, stagger - config.staggerDecay * math.max(0, now - lastHitAt))
	local value = drained + power
	if value >= config.knockdownAt then
		return 0, true
	end
	return value, false
end

function Combat.newAmmo(config: Config): Ammo
	return { count = config.ammo, reloadUntil = 0, lastThrowAt = -math.huge }
end

-- Refills an empty load once its reload time is over.
function Combat.refresh(ammo: Ammo, now: number, config: Config)
	if ammo.count <= 0 and now >= ammo.reloadUntil then
		ammo.count = config.ammo
		ammo.reloadUntil = 0
	end
end

-- Spends one throw if allowed. Every throw costs one, hit or miss; the third starts the reload.
function Combat.tryThrow(ammo: Ammo, now: number, config: Config): boolean
	Combat.refresh(ammo, now, config)
	if ammo.count <= 0 or now - ammo.lastThrowAt < config.throwInterval then
		return false
	end
	ammo.count -= 1
	ammo.lastThrowAt = now
	if ammo.count == 0 then
		ammo.reloadUntil = now + config.reloadTime
	end
	return true
end

-- What the ammo display (the ball in the hand) shows for the replicated ammo: how many balls are loaded and, while
-- an empty load refills, how far along the reload is (0..1). Inputs come from attributes, so anything out of range
-- is clamped.
function Combat.ammoDisplay(count: number, reloadUntil: number, now: number, config: Config): (number, number)
	local loaded = if count == count then math.clamp(math.floor(count), 0, config.ammo) else 0
	if loaded > 0 or not isFinite(reloadUntil) or reloadUntil <= 0 then
		return loaded, 0
	end
	return 0, math.clamp(1 - (reloadUntil - now) / config.reloadTime, 0, 1)
end

return Combat
