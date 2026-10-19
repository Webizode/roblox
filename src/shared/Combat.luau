--!strict
-- Pure maths for the ice-ball throw: the flight curve, the hit test against a player capsule, hit power, the
-- knockdown threshold and the ammo rules. No Roblox globals; CombatService and CombatController use the same
-- functions, and tests/Combat.spec.luau covers them.

export type Config = {
	ammo: number,
	reloadTime: number,
	throwInterval: number,
	speed: number,
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

-- Launch velocity for an aim direction (the camera's look vector). Returns false for directions a real camera
-- cannot produce (not finite, not about unit length).
function Combat.launchVelocity(dx: number, dy: number, dz: number, config: Config): (boolean, number, number, number)
	if not (isFinite(dx) and isFinite(dy) and isFinite(dz)) then
		return false, 0, 0, 0
	end
	local length = math.sqrt(dx * dx + dy * dy + dz * dz)
	if length < 0.9 or length > 1.1 then
		return false, 0, 0, 0
	end
	dx, dy, dz = dx / length, dy / length + config.lift, dz / length
	length = math.sqrt(dx * dx + dy * dy + dz * dz)
	return true, dx / length * config.speed, dy / length * config.speed, dz / length * config.speed
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

-- Hit power in [minPower, 1]: centred hits (distance 0) at full speed are strongest, grazing ones weaker.
function Combat.hitPower(distance: number, impactSpeed: number, config: Config): number
	local reach = config.hitRadius + config.ballRadius
	local centred = math.clamp(1 - distance / reach, 0, 1)
	local speedFactor = math.clamp(impactSpeed / config.speed, 0.6, 1)
	return math.clamp(speedFactor * (config.minPower + (1 - config.minPower) * centred), config.minPower * 0.6, 1)
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

-- What a backpack shows for the replicated ammo: how many balls are loaded and, while an empty load refills, how
-- far along the reload is (0..1). Inputs come from attributes, so anything out of range is clamped.
function Combat.backpack(count: number, reloadUntil: number, now: number, config: Config): (number, number)
	local loaded = if count == count then math.clamp(math.floor(count), 0, config.ammo) else 0
	if loaded > 0 or not isFinite(reloadUntil) or reloadUntil <= 0 then
		return loaded, 0
	end
	return 0, math.clamp(1 - (reloadUntil - now) / config.reloadTime, 0, 1)
end

return Combat
