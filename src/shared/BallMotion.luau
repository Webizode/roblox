--!strict
-- Pure maths for the vanilla ball's three motions, taken from the Blender actions of WSB_ThrowBall: floating in the
-- hand (idle), the small hop and the flat disc spin of a thrown ball (flight), and the quick turn of the next ball
-- popping into the hand (nextThrow). Lengths in ball diameters, angles in radians. No Roblox globals; HeldBalls and
-- CombatController use it, tests/BallMotion.spec.luau covers it.

export type Config = {
	ballModel: {
		idle: { period: number, bob: number, pitch: number, yaw: number, roll: number },
		flight: { bounce: number, bounceRise: number, bounceEnd: number, turnsPerSecond: number },
		nextThrow: { duration: number },
	},
}

export type Idle = { lift: number, pitch: number, yaw: number, roll: number }

local BallMotion = {}

local TAU = 2 * math.pi

-- flat at both ends, like the Blender keys with clamped handles
local function smoothstep(alpha: number): number
	alpha = math.clamp(alpha, 0, 1)
	return alpha * alpha * (3 - 2 * alpha)
end

-- softer at both ends than smoothstep: the turn of Vanilla_NextThrow
local function smootherstep(alpha: number): number
	alpha = math.clamp(alpha, 0, 1)
	return alpha * alpha * alpha * (alpha * (alpha * 6 - 15) + 10)
end

-- `t` seconds of floating: up and down once per period, swaying around the up axis and sideways with it and tipping
-- forward and back twice as fast. Loops seamlessly.
function BallMotion.idle(t: number, config: Config): Idle
	local idle = config.ballModel.idle
	local phase = TAU * t / idle.period
	return {
		lift = idle.bob * math.sin(phase),
		pitch = math.rad(idle.pitch) * math.sin(2 * phase),
		yaw = math.rad(idle.yaw) * math.sin(phase),
		roll = math.rad(idle.roll) * math.sin(phase),
	}
end

-- `t` seconds after the ball left the hand: how far it hops above its path and how far it has turned around its up
-- axis. The hop is over at bounceEnd, the spin starts there and runs evenly.
function BallMotion.flight(t: number, config: Config): (number, number)
	local flight = config.ballModel.flight
	local lift = 0
	if t > 0 and t < flight.bounceRise then
		lift = flight.bounce * smoothstep(t / flight.bounceRise)
	elseif t >= flight.bounceRise and t < flight.bounceEnd then
		lift = flight.bounce * (1 - smoothstep((t - flight.bounceRise) / (flight.bounceEnd - flight.bounceRise)))
	end
	local spin = TAU * flight.turnsPerSecond * math.max(0, t - flight.bounceEnd)
	return lift, spin
end

-- `since` seconds after the next ball popped in: its turn around the up axis, one full turn over the duration. The
-- second value is false once the turn is over (the angle then stays at a full turn, the same as none).
function BallMotion.nextThrow(since: number, config: Config): (number, boolean)
	local duration = config.ballModel.nextThrow.duration
	return TAU * smootherstep(since / duration), since >= 0 and since < duration
end

return BallMotion
