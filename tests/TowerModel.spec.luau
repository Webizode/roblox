local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local TowerModel = require("../src/shared/TowerModel")
local Economy = require("../src/shared/Economy")
local Flavors = require("../src/shared/Config/Flavors")
local Tuning = require("../src/shared/Config/Tower")
local EconomyConfig = require("../src/shared/Config/Economy")

local DT = 1 / Tuning.stepRate
local PAD = Tuning.variant

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

	-- Since the pad only corrects at full strength, a fast, hard player no longer overshoots and holds up to 43
	-- (was 28); the other styles are unchanged. The starter cone only takes 20 anyway.
	it("50 scoops on a starter cone are beyond a 0.2 s player, whatever their style", function()
		for _, gains in { { 3, 0.8 }, { 2, 0.6 }, { 1.6, 0.4 }, { 1, 0.4 } } do
			local state = TowerModel.newState(13)
			local params = paramsFor(stack("vanilla", 50))
			simulate(state, params, PAD, 30, padPlayer(gains[1], gains[2]), 12)
			expect(state.toppled).toBe(true)
		end
	end)

	it("a full-speed reversal does not push towers of up to 8 scoops into the groan", function()
		for _, count in { 3, 5, 8 } do
			local toppled, peak = reversalPeak(count, PAD)
			expect(toppled).toBe(false)
			expect(peak).toBeLessThan(Tuning.groanFraction)
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

describe("Pad input (the path the stabiliser and the rescue use)", function()
	it("gives short towers a gentle pad and tall towers more leverage", function()
		local short = TowerModel.padAuthority(paramsFor(stack("vanilla", 1)), PAD, Tuning)
		local tall = TowerModel.padAuthority(paramsFor(stack("vanilla", 20)), PAD, Tuning)
		expect(short).toBeCloseTo(Tuning.padBase)
		expect(tall).toBeGreaterThan(9)
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

	it("a full push against the lean brings the tower back without throwing it over the other side", function()
		for _, count in { 5, 9, 12, 15 } do
			local state = TowerModel.newState(4)
			local params = paramsFor(stack("vanilla", count))
			state.x = 0.6 * Tuning.tipAngle
			local lowest, elapsed = state.x, 0
			-- a player holds the key and lets go a moment before the tower is upright; letting go late swings it over
			-- the other side by its own momentum, that part is skill
			while state.x + 0.3 * state.vx > 0.1 * Tuning.tipAngle and elapsed < 2 do
				TowerModel.step(state, params, { ax = 0, az = 0, padX = -1, padZ = 0 }, PAD, Tuning, DT)
				elapsed += DT
			end
			for _ = 1, 0.5 / DT do
				TowerModel.step(state, params, TowerModel.NO_INPUT, PAD, Tuning, DT)
				lowest = math.min(lowest, state.x)
			end
			expect(elapsed).toBeLessThan(2)
			expect(state.toppled).toBe(false)
			expect(lowest).toBeGreaterThan(-0.25 * Tuning.tipAngle)
		end
	end)

	it("a push with the lean still makes it worse", function()
		local helped, hurt = TowerModel.newState(4), TowerModel.newState(4)
		local params = paramsFor(stack("vanilla", 12))
		helped.x, hurt.x = 0.4 * Tuning.tipAngle, 0.4 * Tuning.tipAngle
		simulate(helped, params, PAD, 0.5, function()
			return { ax = 0, az = 0, padX = -1, padZ = 0 }
		end)
		simulate(hurt, params, PAD, 0.5, function()
			return { ax = 0, az = 0, padX = 1, padZ = 0 }
		end)
		expect(hurt.x).toBeGreaterThan(0.4 * Tuning.tipAngle)
		expect(helped.x).toBeLessThan(0.4 * Tuning.tipAngle)
	end)

	it("walking, stopping and turning with an upright short tower never reaches the groan", function()
		for _, count in { 2, 5, 8 } do
			local state = TowerModel.newState(count)
			local params = paramsFor(stack("vanilla", count))
			local vx, vz, peak = 0, 0, 0
			local legs = { { 0, 18 }, { 0, 0 }, { 18, 0 }, { -18, 0 }, { 0, -18 }, { 13, 13 }, { 0, 0 } }
			for _, leg in legs do
				for _ = 1, 0.8 / DT do
					local ax, az
					vx, vz, ax, az = TowerModel.baseVelocityStep(vx, vz, leg[1], leg[2], Tuning.accelSmoothing, DT)
					TowerModel.step(state, params, { ax = ax, az = az, padX = 0, padZ = 0 }, PAD, Tuning, DT)
					peak = math.max(peak, TowerModel.tilt(state))
				end
			end
			expect(peak).toBeLessThan(Tuning.groanFraction * Tuning.tipAngle)
		end
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

-- Runs the game's real per-step input: smoothed walking plus TowerModel.assist, no player input. `walk` turns
-- 90 degrees at full speed every 1.5 s; `rescueAt` triggers a rescue whenever the lean passes that share of the
-- tip angle and the cooldown allows. Returns the survival time and the peak lean as a share of the tip angle.
local function assistedRun(count: number, seed: number, seconds: number, walk: boolean, rescueAt: number?)
	local state = TowerModel.newState(seed)
	local params = paramsFor(stack("vanilla", count))
	local vx, vz, peak, lastRescue = 0, 0, 0, -math.huge
	for step = 1, seconds / DT do
		local t = step * DT
		if rescueAt and TowerModel.tilt(state) > rescueAt * Tuning.tipAngle then
			if TowerModel.rescueReady(lastRescue, state.t, Tuning.rescue) then
				lastRescue = state.t
				TowerModel.rescue(state, Tuning.rescue.duration)
			end
		end
		local tx, tz = 0, 0
		if walk then
			local leg = math.floor(t / 1.5) % 4
			tx, tz = ({ 18, 0, -18, 0 })[leg + 1], ({ 0, 18, 0, -18 })[leg + 1]
		end
		local ax, az
		vx, vz, ax, az = TowerModel.baseVelocityStep(vx, vz, tx, tz, Tuning.accelSmoothing, DT)
		local px, pz = TowerModel.assist(state, params, PAD, Tuning, DT)
		TowerModel.step(state, params, { ax = ax, az = az, padX = px, padZ = pz }, PAD, Tuning, DT)
		peak = math.max(peak, TowerModel.tilt(state) / Tuning.tipAngle)
		if state.toppled then
			return t, peak
		end
	end
	return seconds, peak
end

describe("Automatic stabiliser and rescue", function()
	it("keeps 1 to 5 scoops calm while standing and while walking with hard turns, without any input", function()
		for count = 1, 5 do
			local standing, standPeak = assistedRun(count, count, 30, false)
			local walking, walkPeak = assistedRun(count, count, 30, true)
			expect(standing).toBe(30)
			expect(walking).toBe(30)
			expect(standPeak).toBeLessThan(0.1)
			expect(walkPeak).toBeLessThan(0.5)
		end
	end)

	it("lets 6 to 10 scoops wobble more than short towers, but not fall on their own", function()
		local _, shortPeak = assistedRun(3, 1, 30, true)
		for count = 6, 10 do
			local walking, peak = assistedRun(count, count, 30, true)
			expect(walking).toBe(30)
			expect(peak).toBeGreaterThan(shortPeak)
			expect(assistedRun(count, count, 60, false)).toBe(60)
		end
	end)

	it("never lets a tall tower fall while standing still: no hidden time limit up to 20 scoops", function()
		for _, count in { 11, 14, 17, 20 } do
			for seed = 1, 3 do
				expect(assistedRun(count, seed, 90, false)).toBe(90)
			end
		end
	end)

	it("makes walking with tall towers dangerous, and well-timed rescues buy real time", function()
		for _, count in { 15, 17, 20 } do
			local without, with = 0, 0
			for seed = 1, 5 do
				without += assistedRun(count, seed, 30, true)
				with += assistedRun(count, seed, 30, true, 0.6)
			end
			expect(without / 5).toBeLessThan(20)
			expect(with).toBeGreaterThan(without * 1.4)
		end
	end)

	it("a rescue saves a tall tower from a lean the stabiliser has given up on", function()
		local function leaning(rescue: boolean)
			local state = TowerModel.newState(3)
			local params = paramsFor(stack("vanilla", 15))
			state.x = 0.75 * Tuning.tipAngle
			state.seenX = state.x
			if rescue then
				TowerModel.rescue(state, Tuning.rescue.duration)
			end
			for _ = 1, 3 / DT do
				local px, pz = TowerModel.assist(state, params, PAD, Tuning, DT)
				TowerModel.step(state, params, { ax = 0, az = 0, padX = px, padZ = pz }, PAD, Tuning, DT)
			end
			return state.toppled
		end
		expect(leaning(false)).toBe(true)
		expect(leaning(true)).toBe(false)
	end)

	it("a rescue can fail: a tall tower already at the tip angle and groaning goes over anyway", function()
		local state = TowerModel.newState(3)
		local params = paramsFor(stack("vanilla", 20))
		state.x, state.vx = 0.9 * Tuning.tipAngle, 0.4
		state.seenX = state.x
		state.groan = 0.25
		TowerModel.rescue(state, Tuning.rescue.duration)
		for _ = 1, 2 / DT do
			local px, pz = TowerModel.assist(state, params, PAD, Tuning, DT)
			TowerModel.step(state, params, { ax = 0, az = 0, padX = px, padZ = pz }, PAD, Tuning, DT)
		end
		expect(state.toppled).toBe(true)
	end)

	it("a rescue lasts exactly its duration", function()
		local state = TowerModel.newState(1)
		local params = paramsFor(stack("vanilla", 5))
		TowerModel.rescue(state, Tuning.rescue.duration)
		local activeFor = 0
		for _ = 1, 4 / DT do
			if TowerModel.rescueActive(state) then
				activeFor += DT
			end
			TowerModel.step(state, params, TowerModel.NO_INPUT, PAD, Tuning, DT)
		end
		expect(activeFor).toBeCloseTo(Tuning.rescue.duration, DT + 1e-6)
	end)

	it("the next rescue is only allowed after the duration plus the cooldown", function()
		local rescue = Tuning.rescue
		expect(rescue.duration).toBe(1.5)
		expect(rescue.cooldown).toBe(6)
		expect(TowerModel.rescueReady(10, 10, rescue)).toBe(false)
		expect(TowerModel.rescueReady(10, 10 + rescue.duration, rescue)).toBe(false)
		expect(TowerModel.rescueReady(10, 10 + rescue.duration + rescue.cooldown - 0.01, rescue)).toBe(false)
		expect(TowerModel.rescueReady(10, 10 + rescue.duration + rescue.cooldown, rescue)).toBe(true)
		-- the server's jitter slack only shaves off a fraction, it never makes back-to-back rescues possible
		expect(TowerModel.rescueReady(10, 10 + rescue.duration + 1, rescue, 0.25)).toBe(false)
		expect(TowerModel.rescueReady(-math.huge, 0, rescue)).toBe(true)
	end)

	it("a dash with an upright 10-scoop tower and only the stabiliser does not topple it", function()
		for seed = 1, 4 do
			local state = TowerModel.newState(seed)
			local params = paramsFor(stack("vanilla", 10))
			TowerModel.dashKick(state, Tuning.dash, 10, 1, 0)
			for _ = 1, 6 / DT do
				local px, pz = TowerModel.assist(state, params, PAD, Tuning, DT)
				TowerModel.step(state, params, { ax = 0, az = 0, padX = px, padZ = pz }, PAD, Tuning, DT)
			end
			expect(state.toppled).toBe(false)
		end
	end)

	it("reset clears the stabiliser's view and any running rescue", function()
		local state = TowerModel.newState(1)
		state.seenX, state.seenVz = 0.3, 0.2
		TowerModel.rescue(state, Tuning.rescue.duration)
		TowerModel.reset(state)
		expect(state.seenX).toBe(0)
		expect(state.seenVz).toBe(0)
		expect(TowerModel.rescueActive(state)).toBe(false)
	end)
end)
