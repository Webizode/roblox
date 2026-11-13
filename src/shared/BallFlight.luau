--!strict
-- The thrown ice ball's flight (Config/Combat): gravity, and the aim assist on the ball itself (homing), the reach of a
-- hit by how far the ball has flown, and which rival a throw homes in on. Pure: the server (CombatService) flies the
-- ball and checks the hits with it, every client draws the same flight (CombatController). Positions are passed as
-- plain numbers or { x, y, z } tables, so Lune can test it.
--
-- The flight runs in fixed steps of homing.step seconds, so the server and the clients make the same turns. Without a
-- target it is the plain arc of Combat.position.

export type Ball = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	t: number, -- seconds of flight so far
	ox: number, -- where it left the hand
	oy: number,
	oz: number,
	homed: boolean, -- the homing has turned it at least once (for the logs)
}

-- Where the ball homes in on: the target's HumanoidRootPart.
export type Target = { x: number, y: number, z: number }

-- A rival a throw may home in on: where their body is, and whether they count at all (in plain sight, in the arena).
export type Candidate = { x: number, y: number, z: number }

local BallFlight = {}

function BallFlight.new(ox: number, oy: number, oz: number, vx: number, vy: number, vz: number): Ball
	return { x = ox, y = oy, z = oz, vx = vx, vy = vy, vz = vz, t = 0, ox = ox, oy = oy, oz = oz, homed = false }
end

-- The capsule's radius for a ball that has flown `distance` studs from the hand (Config/Combat hitGrowth).
function BallFlight.hitRadius(distance: number, config: any): number
	local growth = config.hitGrowth
	local extra = math.max(distance - growth.from, 0) * growth.perStud
	return math.min(config.hitRadius + extra, growth.max)
end

-- How far the ball is from where it left the hand.
function BallFlight.flown(ball: Ball): number
	local dx, dy, dz = ball.x - ball.ox, ball.y - ball.oy, ball.z - ball.oz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Where the ball's arc (gravity, no more turning) passes the target's axis closest, seen from above: how far beside
-- the axis it is then, how high, and in how many seconds. nil when it flies away from the target.
local function arrival(ball: Ball, target: Target, config: any): (number?, number, number)
	local dx, dz = target.x - ball.x, target.z - ball.z
	local flatSpeed2 = ball.vx * ball.vx + ball.vz * ball.vz
	if flatSpeed2 < 1e-6 then
		return nil, 0, 0
	end
	local t = (dx * ball.vx + dz * ball.vz) / flatSpeed2
	if t <= 0 then
		return nil, 0, 0
	end
	local sx, sz = dx - ball.vx * t, dz - ball.vz * t
	local y = ball.y + ball.vy * t - 0.5 * config.gravity * t * t
	return math.sqrt(sx * sx + sz * sz), y, t
end

-- Whether the ball should turn: not when it is already past the target (it never turns back), and not when its arc
-- would pass through the target's body anyway (the whole capsule, the head too): beside the axis by at most onCourse
-- when it gets there, at a height inside the capsule.
local function shouldTurn(ball: Ball, target: Target, config: any): boolean
	local beside, y = arrival(ball, target, config)
	if beside == nil then
		return false
	end
	return beside > config.homing.onCourse or math.abs(y - target.y) > config.hitHalfHeight
end

-- The point on the target's body the ball turns towards: the body column at the height the ball would arrive at,
-- kept between bodyLow and bodyHigh (never the head).
local function aimPoint(ball: Ball, target: Target, config: any): (number, number, number)
	local homing = config.homing
	local _, arrive = arrival(ball, target, config)
	local y = math.clamp(arrive, target.y + homing.bodyLow, target.y + homing.bodyHigh)
	return target.x, y, target.z
end

-- Turns the velocity towards the point by at most `angle` radians, keeping its speed.
local function turnTowards(ball: Ball, px: number, py: number, pz: number, angle: number)
	local speed = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy + ball.vz * ball.vz)
	local dx, dy, dz = px - ball.x, py - ball.y, pz - ball.z
	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	if speed < 1e-6 or distance < 1e-6 then
		return
	end
	local ux, uy, uz = ball.vx / speed, ball.vy / speed, ball.vz / speed
	local wx, wy, wz = dx / distance, dy / distance, dz / distance
	local cos = math.clamp(ux * wx + uy * wy + uz * wz, -1, 1)
	local between = math.acos(cos)
	if between < 1e-6 then
		return
	end
	local share = math.min(angle / between, 1)
	-- spherical interpolation from the way it flies to the way to the point
	local sin = math.sin(between)
	local a, b = math.sin((1 - share) * between) / sin, math.sin(share * between) / sin
	ball.vx = (ux * a + wx * b) * speed
	ball.vy = (uy * a + wy * b) * speed
	ball.vz = (uz * a + wz * b) * speed
	ball.homed = true
end

-- Flies the ball on by `dt` seconds in fixed steps: gravity, and the homing towards `target` (nil: none) with the
-- device strength `assist` (Config/Combat homing.devices[...], nil: none).
function BallFlight.advance(ball: Ball, dt: number, target: Target?, assist: any?, config: any)
	local homing = config.homing
	local step = homing.step
	local left = dt
	while left > 1e-9 do
		local h = math.min(step, left)
		left -= h
		if target and assist then
			local dx, dy, dz = target.x - ball.x, target.y - ball.y, target.z - ball.z
			if dx * dx + dy * dy + dz * dz <= homing.range * homing.range then
				if shouldTurn(ball, target, config) then
					local px, py, pz = aimPoint(ball, target, config)
					turnTowards(ball, px, py, pz, math.rad(assist.turn) * h)
				end
			end
		end
		ball.x += ball.vx * h
		ball.y += ball.vy * h - 0.5 * config.gravity * h * h
		ball.z += ball.vz * h
		ball.vy -= config.gravity * h
		ball.t += h
	end
end

-- The rival a throw from (ox, oy, oz) aimed along (ax, ay, az) homes in on: the one closest to the aim within the
-- device's `acquire` degrees and maxRange studs. Returns their index in `candidates`, or nil.
function BallFlight.pick(
	ox: number,
	oy: number,
	oz: number,
	ax: number,
	ay: number,
	az: number,
	candidates: { Candidate },
	assist: any,
	config: any
): number?
	local length = math.sqrt(ax * ax + ay * ay + az * az)
	if length < 1e-6 then
		return nil
	end
	local ux, uy, uz = ax / length, ay / length, az / length
	local limit = math.cos(math.rad(assist.acquire))
	local best, bestCos = nil, limit
	for index, candidate in candidates do
		local dx, dy, dz = candidate.x - ox, candidate.y - oy, candidate.z - oz
		local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
		if distance > 1e-3 and distance <= config.homing.maxRange then
			local cos = (dx * ux + dy * uy + dz * uz) / distance
			if cos >= bestCos then
				best, bestCos = index, cos
			end
		end
	end
	return best
end

return BallFlight
