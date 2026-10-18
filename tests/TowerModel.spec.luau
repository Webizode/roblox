local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local TowerModel = require("../src/shared/TowerModel")
local Economy = require("../src/shared/Economy")
local Flavors = require("../src/shared/Config/Flavors")
local Tuning = require("../src/shared/Config/Tower")
local EconomyConfig = require("../src/shared/Config/Economy")

local DT = 1 / Tuning.stepRate
local PAD = Tuning.variants.B
local JOYSTICK = Tuning.variants.A

local function stack(id: string, count: number): { string }
	local ids = table.create(count, id)
	return ids
end

local function paramsFor(ids: { string }, coneMultiplier: number?)
	return TowerModel.params(ids, Flavors.byId, Tuning, coneMultiplier or 1)
end

-- Runs the model for `seconds`. `controller(observedState)` returns an Input; `delaySteps` simulates human
-- reaction time by feeding the controller an old snapshot of the tower.
local function simulate(state, params, variant, seconds: number, controller, delaySteps: number?)
	local history = {}
	local delay = delaySteps or 0
	local events = {}
	local steps = math.floor(seconds / DT + 0.5)
	for _ = 1, steps do
		table.insert(history, { x = state.x, z = state.z, vx = state.vx, vz = state.vz })
		local observed = history[math.max(1, #history - delay)]
		local input = if controller then controller(observed) else TowerModel.NO_INPUT
		local event = TowerModel.step(state, params, input, variant, Tuning, DT)
		if event then
			table.insert(events, event)
		end
		if state.toppled then
			break
		end
	end
	return events
end

-- A simple PD controller standing in for a player's thumb on the balance pad.
local function padPlayer(kp: number, kd: number)
	return function(observed)
		return {
			ax = 0,
			az = 0,
			padX = math.clamp(-(kp * observed.x + kd * observed.vx), -1, 1),
			padZ = math.clamp(-(kp * observed.z + kd * observed.vz), -1, 1),
		}
	end
end

-- The keyboard ramp from BalancePad: towards the target over keyRampTime, back to 0 over keyReleaseTime.
local function ramp(current: number, target: number): number
	if target == 0 then
		local step = DT / Tuning.keyReleaseTime
		return if current > 0 then math.max(0, current - step) else math.min(0, current + step)
	end
	return math.clamp(current + target * DT / Tuning.keyRampTime, -1, 1)
end

-- Someone on I/J/K/L: presses the key against the lean once it is clearly visible, through the key ramp.
local function keyboardPlayer()
	local x, z = 0, 0
	local function key(tilt: number, rate: number): number
		local lean = tilt + 0.35 * rate
		if lean > 0.05 then
			return -1
		elseif lean < -0.05 then
			return 1
		end
		return 0
	end
	return function(observed)
		x = ramp(x, key(observed.x, observed.vx))
		z = ramp(z, key(observed.z, observed.vz))
		return { ax = 0, az = 0, padX = x, padZ = z }
	end
end

-- Variant A through the real input path: the player steers MoveDirection (length <= 1) towards where the tower
-- falls, the Humanoid walks at most Economy.walkSpeed, and baseVelocityStep turns that into the acceleration the
-- tower feels, exactly like TowerController.
local function walkingPlayer(count: number, variant)
	local vx, vz = 0, 0
	local speed = Economy.walkSpeed(count, 0, EconomyConfig)
	local smoothing = variant.accelSmoothing or Tuning.accelSmoothing
	return function(observed)
		local mx, mz = observed.x + 3 * observed.vx, observed.z + 3 * observed.vz
		local length = math.sqrt(mx * mx + mz * mz)
		if length > 1 then
			mx, mz = mx / length, mz / length
		end
		local ax, az
		vx, vz, ax, az = TowerModel.baseVelocityStep(vx, vz, mx * speed, mz * speed, smoothing, DT)
		return { ax = ax, az = az, padX = 0, padZ = 0 }
	end
end

-- Running at full speed and flipping the stick to the opposite direction, through the real input path.
local function reversalPeak(count: number, variant): (boolean, number)
	local state = TowerModel.newState(1)
	local params = paramsFor(stack("vanilla", count))
	local speed = Economy.walkSpeed(count, 0, EconomyConfig)
	local smoothing = variant.accelSmoothing or Tuning.accelSmoothing
	local vx, vz = speed, 0
	local peak = 0
	for _ = 1, 300 do
		local ax, az
		vx, vz, ax, az = TowerModel.baseVelocityStep(vx, vz, -speed, 0, smoothing, DT)
		TowerModel.step(state, params, { ax = ax, az = az, padX = 0, padZ = 0 }, variant, Tuning, DT)
		peak = math.max(peak, TowerModel.tilt(state))
		if state.toppled then
			break
		end
	end
	return state.toppled, peak / Tuning.tipAngle
end

describe("TowerModel", function()
	it("stays upright with no scoops", function()
		local state = TowerModel.newState(1)
		simulate(state, paramsFor({}), PAD, 5, nil)
		expect(TowerModel.tilt(state)).toBe(0)
		expect(state.toppled).toBe(false)
	end)

	it("is deterministic for the same seed and inputs", function()
		local a, b = TowerModel.newState(42), TowerModel.newState(42)
		local params = paramsFor(stack("vanilla", 14))
		TowerModel.impulse(a, 0.3, -0.2)
		TowerModel.impulse(b, 0.3, -0.2)
		simulate(a, params, PAD, 3, padPlayer(2, 0.5))
		simulate(b, params, PAD, 3, padPlayer(2, 0.5))
		expect(a.x).toBe(b.x)
		expect(a.z).toBe(b.z)
		expect(a.step).toBe(b.step)
	end)

	it("short towers right themselves after a kick and never topple on their own", function()
		local state = TowerModel.newState(7)
		local params = paramsFor(stack("vanilla", 6))
		TowerModel.impulse(state, 0.6, 0.4)
		simulate(state, params, PAD, 30, nil)
		expect(state.toppled).toBe(false)
		expect(TowerModel.tilt(state)).toBeLessThan(0.01)
	end)

	it("a short tower survives a sprint start without help", function()
		local state = TowerModel.newState(3)
		local params = paramsFor(stack("vanilla", 8))
		-- full speed reached within the 0.25 s smoothing window: roughly 72 studs/s^2 for a quarter second
		local t = 0
		simulate(state, params, PAD, 4, function()
			t += DT
			local ax = if t < 0.25 then 72 else 0
			return { ax = ax, az = 0, padX = 0, padZ = 0 }
		end)
		expect(state.toppled).toBe(false)
	end)

	it("tall towers drift and topple when nobody balances", function()
		local state = TowerModel.newState(11)
		local params = paramsFor(stack("vanilla", 20))
		local events = simulate(state, params, PAD, 15, nil)
		expect(state.toppled).toBe(true)
		expect(events[#events]).toBe("toppled")
	end)

	it("a player with 0.2 s reaction time can hold 20 scoops on the pad", function()
		local state = TowerModel.newState(5)
		local params = paramsFor(stack("vanilla", 20))
		simulate(state, params, PAD, 30, padPlayer(3, 0.8), 12)
		expect(state.toppled).toBe(false)
	end)

	it("a careful player with 0.3 s reaction time can still hold 20 scoops", function()
		-- guards accessibility: retuning must not push the median tower out of reach for slower players
		for seed = 1, 4 do
			local state = TowerModel.newState(seed)
			simulate(state, paramsFor(stack("vanilla", 20)), PAD, 45, padPlayer(1.0, 0.4), 18)
			expect(state.toppled).toBe(false)
		end
	end)

	it("a player with 0.2 s reaction time can hold 30 scoops with an upgraded cone", function()
		local state = TowerModel.newState(9)
		local params = paramsFor(stack("vanilla", 30), 1.3)
		simulate(state, params, PAD, 30, padPlayer(1.6, 0.4), 12)
		expect(state.toppled).toBe(false)
	end)

	it("40 scoops on a starter cone are beyond a 0.2 s player, whatever their style", function()
		for _, gains in { { 3, 0.8 }, { 2, 0.6 }, { 1.6, 0.4 }, { 1, 0.4 } } do
			local state = TowerModel.newState(13)
			local params = paramsFor(stack("vanilla", 40))
			simulate(state, params, PAD, 30, padPlayer(gains[1], gains[2]), 12)
			expect(state.toppled).toBe(true)
		end
	end)

	it("variant A can hold 14 scoops by walking, through the real input path and 0.25 s reaction", function()
		for seed = 1, 3 do
			local state = TowerModel.newState(seed)
			simulate(state, paramsFor(stack("vanilla", 14)), JOYSTICK, 30, walkingPlayer(14, JOYSTICK), 15)
			expect(state.toppled).toBe(false)
		end
	end)

	it("a full-speed reversal does not push towers of up to 8 scoops into the groan, in A and B", function()
		for _, variant in { JOYSTICK, PAD } do
			for _, count in { 3, 5, 8 } do
				local toppled, peak = reversalPeak(count, variant)
				expect(toppled).toBe(false)
				expect(peak).toBeLessThan(Tuning.groanFraction)
			end
		end
	end)

	it("groans before toppling and can be saved", function()
		local state = TowerModel.newState(2)
		local params = paramsFor(stack("vanilla", 12))
		state.x = Tuning.tipAngle * (Tuning.groanFraction + 0.05)
		local first = TowerModel.step(state, params, TowerModel.NO_INPUT, PAD, Tuning, DT)
		expect(first).toBe("groan")
		local events = simulate(state, params, PAD, 1, function()
			return { ax = 0, az = 0, padX = -1, padZ = 0 }
		end)
		expect(table.find(events, "saved")).toBeTruthy()
		expect(state.toppled).toBe(false)
	end)

	it("topples after groaning for the groan duration", function()
		local state = TowerModel.newState(2)
		local params = paramsFor(stack("vanilla", 20))
		state.x = Tuning.tipAngle
		state.vx = 1
		local events = simulate(state, params, PAD, 2, function()
			return { ax = 0, az = 0, padX = 1, padZ = 0 }
		end)
		expect(state.toppled).toBe(true)
		expect(events[1]).toBe("groan")
		expect(events[#events]).toBe("toppled")
		expect(state.groan).toBeGreaterThan(Tuning.groanDuration - DT)
	end)

	it("never tilts past the tip angle", function()
		local state = TowerModel.newState(4)
		local params = paramsFor(stack("vanilla", 30))
		TowerModel.impulse(state, 20, 0)
		TowerModel.step(state, params, TowerModel.NO_INPUT, PAD, Tuning, DT)
		expect(TowerModel.tilt(state)).toBeLessThan(Tuning.tipAngle + 1e-9)
	end)

	it("heavy scoops at the bottom are more stable than at the top", function()
		local heavyLow = { "rocky_road", "rocky_road", "rocky_road", "vanilla", "vanilla", "vanilla" }
		local heavyHigh = { "vanilla", "vanilla", "vanilla", "rocky_road", "rocky_road", "rocky_road" }
		local low = paramsFor(heavyLow)
		local high = paramsFor(heavyHigh)
		expect(low.gravity).toBeLessThan(high.gravity)
		expect(low.stiffness).toBeCloseTo(high.stiffness)
	end)

	it("jelly makes the tower bouncier and pickles kick it", function()
		local plain = paramsFor(stack("vanilla", 5))
		local jelly = paramsFor(stack("jelly", 5))
		expect(jelly.damping).toBeLessThan(plain.damping)
		expect(paramsFor(stack("cursed_pickle", 1)).jerk).toBeGreaterThan(0)
		local still = TowerModel.newState(8)
		local kicked = TowerModel.newState(8)
		simulate(still, paramsFor(stack("vanilla", 4)), PAD, 2, nil)
		simulate(kicked, paramsFor({ "vanilla", "vanilla", "vanilla", "cursed_pickle" }), PAD, 2, nil)
		expect(TowerModel.tilt(still)).toBeLessThan(1e-9)
		expect(TowerModel.tilt(kicked)).toBeGreaterThan(1e-4)
	end)

	it("only drifts from the drift start on", function()
		expect(paramsFor(stack("vanilla", Tuning.driftStartScoops - 1)).drift).toBe(0)
		expect(paramsFor(stack("vanilla", Tuning.driftStartScoops)).drift).toBeGreaterThan(0)
	end)

	it("earns the steady bonus only on tall, calm towers and caps it", function()
		local short = TowerModel.newState(1)
		simulate(short, paramsFor(stack("vanilla", 5)), PAD, 10, nil)
		expect(TowerModel.steadyBonus(short, Tuning)).toBe(0)

		local tall = TowerModel.newState(1)
		simulate(tall, paramsFor(stack("vanilla", 12)), PAD, 20, padPlayer(3, 0.8))
		expect(TowerModel.steadyBonus(tall, Tuning)).toBeCloseTo(Tuning.steady.max)
	end)

	it("rigid towers ignore drift and input", function()
		local state = TowerModel.newState(6)
		local params = paramsFor(stack("vanilla", 30))
		TowerModel.makeRigid(state, 5)
		simulate(state, params, PAD, 4, function()
			return { ax = 72, az = 72, padX = 1, padZ = 1 }
		end)
		expect(state.toppled).toBe(false)
		expect(TowerModel.tilt(state)).toBeLessThan(1e-6)
	end)

	it("reset clears tilt and progress but keeps the clock", function()
		local state = TowerModel.newState(6)
		simulate(state, paramsFor(stack("vanilla", 20)), PAD, 15, nil)
		local clock = state.t
		TowerModel.reset(state)
		expect(state.toppled).toBe(false)
		expect(TowerModel.tilt(state)).toBe(0)
		expect(state.steadySeconds).toBe(0)
		expect(state.t).toBe(clock)
	end)
end)

describe("Pad and keyboard input", function()
	it("gives short towers a gentle pad and tall towers more leverage", function()
		local short = TowerModel.padAuthority(paramsFor(stack("vanilla", 1)), PAD, Tuning)
		local tall = TowerModel.padAuthority(paramsFor(stack("vanilla", 20)), PAD, Tuning)
		expect(short).toBeCloseTo(Tuning.padBase)
		expect(tall).toBeGreaterThan(9)
		expect(TowerModel.padAuthority(paramsFor(stack("vanilla", 20)), JOYSTICK, Tuning)).toBe(0)
	end)

	it("holding a key does not topple a tower of up to 5 scoops", function()
		-- regression: with a fixed pad strength a held key toppled even a one-scoop tower in 0.85 s
		for _, count in { 1, 3, 5 } do
			local state = TowerModel.newState(1)
			simulate(state, paramsFor(stack("vanilla", count)), PAD, 10, function()
				return { ax = 0, az = 0, padX = 1, padZ = 0 }
			end)
			expect(state.toppled).toBe(false)
			expect(TowerModel.tilt(state)).toBeLessThan(Tuning.groanFraction * Tuning.tipAngle)
		end
	end)

	it("a short key tap only nudges a tower of up to 8 scoops", function()
		for _, count in { 1, 5, 8 } do
			local state = TowerModel.newState(1)
			local u, step, peak = 0, 0, 0
			simulate(state, paramsFor(stack("vanilla", count)), PAD, 3, function()
				step += 1
				u = ramp(u, if step <= 9 then 1 else 0) -- 0.15 s tap
				peak = math.max(peak, TowerModel.tilt(state))
				return { ax = 0, az = 0, padX = u, padZ = 0 }
			end)
			expect(state.toppled).toBe(false)
			expect(peak / Tuning.tipAngle).toBeLessThan(0.3)
		end
	end)

	it("a keyboard player with 0.25 s reaction can hold 12 scoops", function()
		for seed = 1, 4 do
			local state = TowerModel.newState(seed)
			simulate(state, paramsFor(stack("vanilla", 12)), PAD, 30, keyboardPlayer(), 15)
			expect(state.toppled).toBe(false)
		end
	end)

	it("pad input actually moves the tower in the pushed direction", function()
		local state = TowerModel.newState(1)
		simulate(state, paramsFor(stack("vanilla", 6)), PAD, 1, function()
			return { ax = 0, az = 0, padX = 0.5, padZ = -0.5 }
		end)
		expect(state.x).toBeGreaterThan(0.02)
		expect(state.z).toBeLessThan(-0.02)
	end)

	it("smooths movement into a bounded acceleration that settles on the target velocity", function()
		local vx, vz = 0, 0
		local peak = 0
		for _ = 1, 120 do
			local ax
			vx, vz, ax = TowerModel.baseVelocityStep(vx, vz, 18, 0, Tuning.accelSmoothing, DT)
			peak = math.max(peak, ax)
		end
		expect(vx).toBeCloseTo(18, 0.01)
		expect(vz).toBe(0)
		expect(peak).toBeLessThan(18 / Tuning.accelSmoothing + 1e-6)
	end)

	it("a dash kicks against its direction, grows with height and is capped", function()
		local small, tall = TowerModel.newState(1), TowerModel.newState(1)
		local kickSmall = TowerModel.dashKick(small, Tuning.dash, 3, 1, 0)
		local kickTall = TowerModel.dashKick(tall, Tuning.dash, 12, 2, 0)
		expect(small.vx).toBeLessThan(0)
		expect(kickTall).toBeGreaterThan(kickSmall)
		expect(TowerModel.dashKick(TowerModel.newState(1), Tuning.dash, 500, 0, 1)).toBe(Tuning.dash.kickMax)
		expect(TowerModel.dashKick(TowerModel.newState(1), Tuning.dash, 0, 1, 0)).toBe(0)
	end)

	it("an upright tower of up to 8 scoops survives a dash with nobody balancing", function()
		for count = 1, 8 do
			local state = TowerModel.newState(count)
			TowerModel.dashKick(state, Tuning.dash, count, 1, 0)
			simulate(state, paramsFor(stack("vanilla", count)), PAD, 4, nil)
			expect(state.toppled).toBe(false)
		end
	end)

	it("a player with 0.25 s reaction time can dash with an upright 15-scoop tower", function()
		for seed = 1, 4 do
			local state = TowerModel.newState(seed)
			TowerModel.dashKick(state, Tuning.dash, 15, 1, 0)
			simulate(state, paramsFor(stack("vanilla", 15)), PAD, 10, padPlayer(1.6, 0.4), 15)
			expect(state.toppled).toBe(false)
		end
	end)

	it("a dash while a tall tower already leans back topples it, the same tower survives without the dash", function()
		local function leaningBack(dash: boolean)
			local state = TowerModel.newState(2)
			state.x = -0.6 * Tuning.tipAngle
			state.vx = -0.15
			if dash then
				TowerModel.dashKick(state, Tuning.dash, 15, 1, 0)
			end
			simulate(state, paramsFor(stack("vanilla", 15)), PAD, 6, padPlayer(1.6, 0.4), 15)
			return state.toppled
		end
		expect(leaningBack(false)).toBe(false)
		expect(leaningBack(true)).toBe(true)
	end)
end)
