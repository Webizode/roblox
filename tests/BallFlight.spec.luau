local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local BallFlight = require("../src/shared/BallFlight")
local Combat = require("../src/shared/Combat")
local Config = require("../src/shared/Config/Combat")

local DT = 1 / 60
local devices = Config.homing.devices

-- A throw from the origin at `speed` towards (tx, ty, tz) through Combat.aimVelocity, the way the server aims.
local function throwAt(tx: number, ty: number, tz: number, speed: number)
	local ok, vx, vy, vz = Combat.aimVelocity(0, 0, 0, tx, ty, tz, speed, Config)
	assert(ok, "unusable aim")
	return BallFlight.new(0, 0, 0, vx, vy, vz)
end

-- Flies `ball` frame by frame against a target that moves with (wx, wz) studs/s from (x, y, z), and returns the
-- closest the ball came to the target's body axis (a capsule check like the server's) and the reach it had there.
local function fly(ball, x: number, y: number, z: number, wx: number, wz: number, assist: any?)
	local best, reachThere = math.huge, Config.hitRadius
	local t = 0
	while t < Config.maxFlight do
		local ax, ay, az = ball.x, ball.y, ball.z
		local target = { x = x + wx * t, y = y, z = z + wz * t }
		BallFlight.advance(ball, DT, target, assist, Config)
		t += DT
		local distance = Combat.closestToCapsule(
			ax,
			ay,
			az,
			ball.x,
			ball.y,
			ball.z,
			target.x,
			target.y,
			target.z,
			Config.hitHalfHeight
		)
		if distance < best then
			best, reachThere = distance, BallFlight.hitRadius(BallFlight.flown(ball), Config)
		end
	end
	return best, reachThere
end

local function hits(best: number, reach: number): boolean
	return best <= reach + Config.ballRadius
end

describe("BallFlight: the thrown ball", function()
	it("without a target it flies exactly the arc of Combat.position", function()
		local ball = BallFlight.new(1, 2, 3, 40, 12, -30)
		for _ = 1, 42 do
			BallFlight.advance(ball, DT, nil, nil, Config)
		end
		local x, y, z = Combat.position(1, 2, 3, 40, 12, -30, Config.gravity, 42 * DT)
		expect(ball.x).toBeCloseTo(x, 1e-6)
		expect(ball.y).toBeCloseTo(y, 1e-6)
		expect(ball.z).toBeCloseTo(z, 1e-6)
		expect(ball.homed).toBe(false)
	end)

	it("the reach grows with the distance flown, up to its cap", function()
		local growth = Config.hitGrowth
		expect(BallFlight.hitRadius(5, Config)).toBe(Config.hitRadius)
		expect(BallFlight.hitRadius(growth.from, Config)).toBe(Config.hitRadius)
		expect(BallFlight.hitRadius(60, Config)).toBeCloseTo(Config.hitRadius + 40 * growth.perStud, 1e-9)
		expect(BallFlight.hitRadius(1000, Config)).toBe(growth.max)
	end)

	it("a tap now reaches past 120 studs on its arc (it stopped at 66)", function()
		local ok, vx = Combat.aimVelocity(0, 0, 0, 130, 0, 0, Config.minSpeed, Config)
		expect(ok).toBe(true)
		-- through the aim point, not the straight fallback: the flight time fits
		expect(130 / vx <= Config.maxFlight).toBe(true)
	end)

	it("a rival walking across 60 studs away: missed without help, hit with the mouse's homing", function()
		-- aimed where they stood when the ball left the hand; they walk at 18 studs/s across the line of fire
		local without = throwAt(60, 0, 0, Config.maxSpeed)
		local best, reach = fly(without, 60, 0, 0, 0, 18, nil)
		expect(hits(best, reach)).toBe(false)
		local with = throwAt(60, 0, 0, Config.maxSpeed)
		best, reach = fly(with, 60, 0, 0, 0, 18, devices.keyboard)
		expect(hits(best, reach)).toBe(true)
		expect(with.homed).toBe(true)
	end)

	it("touch helps more than the mouse: it saves a throw the mouse's homing cannot", function()
		local mouse = throwAt(90, 0, 0, Config.minSpeed)
		local best = fly(mouse, 90, 0, 0, 0, 18, devices.keyboard)
		local touch = throwAt(90, 0, 0, Config.minSpeed)
		local touchBest, touchReach = fly(touch, 90, 0, 0, 0, 18, devices.touch)
		expect(touchBest).toBeLessThan(best)
		expect(hits(touchBest, touchReach)).toBe(true)
		expect(devices.touch.turn > devices.gamepad.turn and devices.gamepad.turn > devices.keyboard.turn).toBe(true)
	end)

	it("a ball already on its way to the head is left alone: headshots stay the player's", function()
		local headY = 1.59
		local plain = throwAt(50, headY, 0, Config.maxSpeed)
		local homed = throwAt(50, headY, 0, Config.maxSpeed)
		for _ = 1, 30 do
			BallFlight.advance(plain, DT, nil, nil, Config)
			BallFlight.advance(homed, DT, { x = 50, y = 0, z = 0 }, devices.touch, Config)
		end
		expect(homed.homed).toBe(false)
		expect(homed.y).toBeCloseTo(plain.y, 1e-9)
	end)

	it("homing aims at the body, never above it", function()
		-- a ball flying well over the target's head is pulled down to the top of the body column at most
		local ball = throwAt(40, 8, 3, Config.maxSpeed)
		local target = { x = 40, y = 0, z = 0 }
		local lowest = math.huge
		for _ = 1, 60 do
			BallFlight.advance(ball, DT, target, devices.touch, Config)
			if math.abs(ball.x - 40) < 1 then
				lowest = math.min(lowest, ball.y)
			end
		end
		expect(ball.homed).toBe(true)
		expect(lowest > Config.homing.bodyLow - 1).toBe(true)
	end)

	it("picks the rival closest to the aim, within the device's angle and the range only", function()
		local candidates = {
			{ x = 50, y = 0, z = 6 }, -- 6.8 degrees off
			{ x = 50, y = 0, z = 2 }, -- 2.3 degrees off
			{ x = 50, y = 0, z = -40 }, -- far off
		}
		expect(BallFlight.pick(0, 0, 0, 1, 0, 0, candidates, devices.keyboard, Config)).toBe(2)
		expect(BallFlight.pick(0, 0, 0, 1, 0, 0, { candidates[1] }, devices.keyboard, Config)).toBe(nil)
		expect(BallFlight.pick(0, 0, 0, 1, 0, 0, { candidates[1] }, devices.touch, Config)).toBe(1)
		local far = { { x = Config.homing.maxRange + 10, y = 0, z = 0 } }
		expect(BallFlight.pick(0, 0, 0, 1, 0, 0, far, devices.touch, Config)).toBe(nil)
		expect(BallFlight.pick(0, 0, 0, 0, 0, 0, candidates, devices.touch, Config)).toBe(nil)
	end)
end)
