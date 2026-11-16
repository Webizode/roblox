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

-- The lowest pulse (Combat.pulse) at which letting go is a perfect throw: the charge arc's green mark runs from here to
-- the top. Near a touch the pulse is 1 - |held - touch| / rise, so pulse >= this exactly when isPerfect.
function Combat.perfectShare(config: Config): number
	return 1 - (config.perfect.window / 2) / config.perfect.rise
end

-- Whether the pulse is on its way down (after a touch of the outer circle, the charge arc pales then).
function Combat.falling(held: number, config: Config): boolean
	if not isFinite(held) or held <= 0 then
		return false
	end
	local rise = config.perfect.rise
	return held % (2 * rise) > rise
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

-- A rival the crosshair ray may pass over: their HumanoidRootPart (x, y, z) and, if known, their head zone.
export type AimBody = { x: number, y: number, z: number, head: Head? }

-- How far along the crosshair ray (from o along the unit direction d, at most `length` studs) the nearest rival lies
-- that the ray passes over: within hitRadius of their body's axis (the capsule without its growth) or inside their
-- head zone (the head's radius times headZoneScale). nil when it passes none. The throw aims at the ray's point at
-- that distance instead of at the map behind: a character's head, limbs and hair do not collide, so the map ray flew
-- through them, the aim point lay far behind the rival, and the ball from the right hand ran almost parallel to the
-- crosshair ray, passing the rival on the left by about the hand's distance from the camera (kill test 13.11.2026).
function Combat.aimDepth(
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	length: number,
	bodies: { AimBody },
	config: Config
): number?
	local best: number? = nil
	local bx, by, bz = ox + dx * length, oy + dy * length, oz + dz * length
	for _, body in bodies do
		local distance, s =
			Combat.closestToCapsule(ox, oy, oz, bx, by, bz, body.x, body.y, body.z, config.hitHalfHeight)
		local along: number? = if distance <= config.hitRadius then s * length else nil
		local head = body.head
		if head then
			local t = math.clamp((head.x - ox) * dx + (head.y - oy) * dy + (head.z - oz) * dz, 0, length)
			local hx, hy, hz = ox + dx * t - head.x, oy + dy * t - head.y, oz + dz * t - head.z
			if math.sqrt(hx * hx + hy * hy + hz * hz) <= head.radius * config.headZoneScale then
				along = if along then math.min(along, t) else t
			end
		end
		if along and along > 0 and (best == nil or along < best) then
			best = along
		end
	end
	return best
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

export type Head = { x: number, y: number, z: number, radius: number }
-- the scoops on the back as a capsule: from the centre of the bottom scoop (x, y, z) `height` studs up to the centre of
-- the top one, `radius` the scoops' radius (height 0: a single scoop)
export type TowerColumn = { x: number, y: number, z: number, height: number, radius: number }

-- Whether a ball that touched the body capsule at `fromT` is a headshot: following its arc on through the body in fine
-- steps (about 0.06 studs), the first of the two zones its centre enters decides: the head zone (headRadius times
-- headZoneScale, plus the ball, with the ball's centre at head height, above the bottom of the head itself) makes it a
-- headshot, the tower column on the back (the scoops' radius plus the ball) a normal hit. Entering both at the same
-- step, the one it is deeper in wins. So from the front and the side a ball that visibly meets the head is a headshot,
-- and from behind the tower only protects where it really stands in front of the head. Only the head counts: a ball at
-- the chest that grazes the chin is a body hit. `tower` is nil without scoops. The server decides this from the flight
-- alone.
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
	local towerReach = if tower then tower.radius + config.ballRadius else 0
	local reach = config.hitRadius + config.ballRadius
	local speed = math.max(math.sqrt(vx * vx + (vy - config.gravity * fromT) ^ 2 + vz * vz), 1)
	local span = 2 * reach / speed -- long enough to cross the whole capsule
	local steps = 96
	for step = 0, steps do
		local px, py, pz = Combat.position(ox, oy, oz, vx, vy, vz, config.gravity, fromT + span * step / steps)
		local hx, hy, hz = px - head.x, py - head.y, pz - head.z
		local headDistance = math.sqrt(hx * hx + hy * hy + hz * hz)
		local inHead = headDistance <= headReach and py >= head.y - head.radius
		local towerDistance = math.huge
		if tower then
			-- from the ball's centre to the column's axis, the segment through the scoop centres
			local y = math.clamp(py, tower.y, tower.y + math.max(tower.height, 0))
			local tx, ty, tz = px - tower.x, py - y, pz - tower.z
			towerDistance = math.sqrt(tx * tx + ty * ty + tz * tz)
		end
		local inTower = tower ~= nil and towerDistance <= towerReach
		if inHead and inTower then
			return headDistance / headReach < towerDistance / towerReach
		elseif inHead then
			return true
		elseif inTower then
			return false
		end
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

-- A hit's slow-down (Config/Combat hitSlow) for one who was hit at `now`, given until when their last one ran
-- (`slowUntil`, 0: none yet): the new end of the slow-down, or nil when this hit slows nothing because one still runs
-- or ended less than `immune` seconds ago. It never stacks or grows longer, so nobody is held in place.
function Combat.hitSlow(
	slowUntil: number,
	now: number,
	config: { hitSlow: { seconds: number, immune: number } }
): number?
	if now < slowUntil + config.hitSlow.immune then
		return nil
	end
	return now + config.hitSlow.seconds
end

return Combat
