local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local TowerModel = require("../src/shared/TowerModel")
local Stance = require("../src/shared/Stance")
local Economy = require("../src/shared/Economy")
local Flavors = require("../src/shared/Config/Flavors")
local Tuning = require("../src/shared/Config/Tower")
local EconomyConfig = require("../src/shared/Config/Economy")
local Upgrades = require("../src/shared/Upgrades")
local UpgradesConfig = require("../src/shared/Config/Upgrades")

local DT = 1 / Tuning.stepRate
local PAD = Tuning.variant

local function stack(id: string, count: number): { string }
	local ids = table.create(count, id)
	return ids
end

-- The game's flavors plus three made-up ones that only exist here, so the physics modifiers (mass, damping, jerk)
-- stay tested while every flavor in the game is a plain classic. The rarer flavors that use them come later.
local FLAVORS = table.clone(Flavors.byId)
local function testFlavor(id: string, fields: { [string]: number })
	local flavor = table.clone(Flavors.byId.vanilla) :: any
	flavor.id = id
	for key, value in fields do
		flavor[key] = value
	end
	FLAVORS[id] = flavor
end
testFlavor("test_heavy", { mass = 2, stiffness = 0.3 })
testFlavor("test_bouncy", { mass = 0.8, damping = -0.5 })
testFlavor("test_kicker", { mass = 1.2, jerk = 1.2 })

local function paramsFor(ids: { string }, coneMultiplier: number?)
	return TowerModel.params(ids, FLAVORS, Tuning, coneMultiplier or 1)
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

-- Bigger and stiffer cones for the physics below: the six cone levels as they were before the upgrade shop
-- (Config/Economy until 25.11.2026). The shop's Big Cone grows in other steps and no longer stiffens the tower
-- (Config/Upgrades cone.stiffnessPerLevel = 0); these only test the model with such cones.
local CONE_CAPACITY = { 20, 28, 36, 45, 55, 65 }
local CONE_STIFFNESS = { 1, 1.1, 1.2, 1.3, 1.45, 1.6 }

-- The smallest waffle that holds `count` scoops (the cone a player carrying them has at least), for the game's walking
-- speed (Economy.walkSpeed goes by how full the waffle is)
local function capacityFor(count: number): number
	for _, capacity in CONE_CAPACITY do
		if capacity >= count then
			return capacity
		end
	end
	return CONE_CAPACITY[#CONE_CAPACITY]
end

-- Running at full speed and flipping the stick to the opposite direction, through the real input path.
local function reversalPeak(count: number, variant): (boolean, number)
	local state = TowerModel.newState(1)
	local params = paramsFor(stack("vanilla", count))
	local speed = Economy.walkSpeed(count, capacityFor(count), 0, EconomyConfig)
	local smoothing = variant.accelSmoothing or Tuning.accelSmoothing
	local vx, vz = speed, 0
	local peak = 0
	for _ = 1, 300 do
		local ax, az
		vx, vz, ax, az = TowerModel.baseVelocityStep(vx, vz, -speed, 0, smoothing, DT, Tuning.turnFactor)
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

	it("very tall towers drift and topple when nobody balances", function()
		local state = TowerModel.newState(11)
		local params = paramsFor(stack("vanilla", 30))
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

	-- Since the pad only corrects at full strength, a fast, hard player no longer overshoots; with the faint drift of
	-- tall towers the best style holds up to 70 and the others fewer. The starter cone only takes 20 anyway.
	it("80 scoops on a starter cone are beyond a 0.2 s player, whatever their style", function()
		for _, gains in { { 3, 0.8 }, { 2, 0.6 }, { 1.6, 0.4 }, { 1, 0.4 } } do
			local state = TowerModel.newState(13)
			local params = paramsFor(stack("vanilla", 80))
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
		local heavyLow = { "test_heavy", "test_heavy", "test_heavy", "vanilla", "vanilla", "vanilla" }
		local heavyHigh = { "vanilla", "vanilla", "vanilla", "test_heavy", "test_heavy", "test_heavy" }
		local low = paramsFor(heavyLow)
		local high = paramsFor(heavyHigh)
		expect(low.gravity).toBeLessThan(high.gravity)
		expect(low.stiffness).toBeCloseTo(high.stiffness)
	end)

	it("a bouncy flavor makes the tower bouncier and a kicking one kicks it", function()
		local plain = paramsFor(stack("vanilla", 5))
		local bouncy = paramsFor(stack("test_bouncy", 5))
		expect(bouncy.damping).toBeLessThan(plain.damping)
		expect(paramsFor(stack("test_kicker", 1)).jerk).toBeGreaterThan(0)
		local still = TowerModel.newState(8)
		local kicked = TowerModel.newState(8)
		simulate(still, paramsFor(stack("vanilla", 4)), PAD, 2, nil)
		simulate(kicked, paramsFor({ "vanilla", "vanilla", "vanilla", "test_kicker" }), PAD, 2, nil)
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

describe("Pad input (the path the stabiliser and the stance use)", function()
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
			vx, vz, ax = TowerModel.baseVelocityStep(vx, vz, 18, 0, Tuning.accelSmoothing, DT, Tuning.turnFactor)
			peak = math.max(peak, ax)
		end
		expect(vx).toBeCloseTo(18, 0.01)
		expect(vz).toBe(0)
		expect(peak).toBeLessThan(18 / Tuning.accelSmoothing + 1e-6)
	end)

	it("feels a turn of the heading at turnFactor, starting and stopping in full", function()
		expect(Tuning.turnFactor).toBe(0.5)
		local function step(vx: number, vz: number, tx: number, tz: number, factor: number?)
			local _, _, ax, az = TowerModel.baseVelocityStep(vx, vz, tx, tz, Tuning.accelSmoothing, DT, factor)
			return ax, az
		end
		-- starting off and stopping: along the velocity (or from standstill), unchanged
		local fullX = step(0, 0, 18, 0)
		expect((step(0, 0, 18, 0, Tuning.turnFactor))).toBeCloseTo(fullX, 1e-9)
		local brakeX = step(18, 0, 0, 0)
		expect((step(18, 0, 0, 0, Tuning.turnFactor))).toBeCloseTo(brakeX, 1e-9)
		-- a pure turn (walking +X, now steering +Z): the sideways part at half strength, the braking part in full
		local ax, az = step(18, 0, 0, 18)
		local tx, tz = step(18, 0, 0, 18, Tuning.turnFactor)
		expect(tx).toBeCloseTo(ax, 1e-9)
		expect(tz).toBeCloseTo(az * Tuning.turnFactor, 1e-9)
		-- the velocity itself still follows the input in full
		local nx, nz = TowerModel.baseVelocityStep(18, 0, 0, 18, Tuning.accelSmoothing, DT, Tuning.turnFactor)
		local ox, oz = TowerModel.baseVelocityStep(18, 0, 0, 18, Tuning.accelSmoothing, DT)
		expect(nx).toBe(ox)
		expect(nz).toBe(oz)
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
					vx, vz, ax, az = TowerModel.baseVelocityStep(
						vx,
						vz,
						leg[1],
						leg[2],
						Tuning.accelSmoothing,
						DT,
						Tuning.turnFactor
					)
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
-- 90 degrees at full speed every 1.5 s; `stanceAt` holds the steady stance whenever the lean passes that share of
-- the tip angle and the energy bar allows it, and lets go once the tower is calm again (walking slower meanwhile,
-- like in the game). Returns the survival time and the peak lean as a share of the tip angle.
local function assistedRun(count: number, seed: number, seconds: number, walk: boolean, stanceAt: number?)
	local state = TowerModel.newState(seed)
	local params = paramsFor(stack("vanilla", count))
	local meter = Stance.new()
	local vx, vz, peak = 0, 0, 0
	for step = 1, seconds / DT do
		local t = step * DT
		if stanceAt then
			local lean = TowerModel.tilt(state) / Tuning.tipAngle
			if lean > stanceAt then
				Stance.start(meter, Tuning.stance)
			elseif lean < 0.2 then
				Stance.stop(meter)
			end
			Stance.advance(meter, DT, Tuning.stance)
			TowerModel.setStance(state, meter.active)
		end
		local tx, tz = 0, 0
		if walk then
			local leg = math.floor(t / 1.5) % 4
			local speed = if state.stance then 18 * Tuning.stance.walkMultiplier else 18
			tx, tz = ({ speed, 0, -speed, 0 })[leg + 1], ({ 0, speed, 0, -speed })[leg + 1]
		end
		local ax, az
		vx, vz, ax, az = TowerModel.baseVelocityStep(vx, vz, tx, tz, Tuning.accelSmoothing, DT, Tuning.turnFactor)
		local px, pz = TowerModel.assist(state, params, PAD, Tuning, DT)
		TowerModel.step(state, params, { ax = ax, az = az, padX = px, padZ = pz }, PAD, Tuning, DT)
		peak = math.max(peak, TowerModel.tilt(state) / Tuning.tipAngle)
		if state.toppled then
			return t, peak
		end
	end
	return seconds, peak
end

describe("Automatic stabiliser and steady stance", function()
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

	it("makes walking with tall towers dangerous, and the stance used when it tips buys real time", function()
		-- hard 90 degree turns at full speed; with turnFactor 0.5 they feel half as hard, so the edge lies at about
		-- 28 scoops (22 with turnFactor 1)
		for _, count in { 28, 30, 32 } do
			local without, with = 0, 0
			for seed = 1, 5 do
				without += assistedRun(count, seed, 30, true)
				with += assistedRun(count, seed, 30, true, 0.6)
			end
			expect(without / 5).toBeLessThan(20)
			expect(with).toBeGreaterThan(without * 1.4)
		end
	end)

	it("the stance saves a tall tower from a lean the stabiliser has given up on, even a groaning one", function()
		local function leaning(count: number, lean: number, stance: boolean)
			local state = TowerModel.newState(3)
			local params = paramsFor(stack("vanilla", count))
			state.x = lean * Tuning.tipAngle
			state.seenX = state.x
			TowerModel.setStance(state, stance)
			for _ = 1, 3 / DT do
				local px, pz = TowerModel.assist(state, params, PAD, Tuning, DT)
				TowerModel.step(state, params, { ax = 0, az = 0, padX = px, padZ = pz }, PAD, Tuning, DT)
			end
			return state.toppled
		end
		expect(leaning(15, 0.75, false)).toBe(true)
		expect(leaning(15, 0.75, true)).toBe(false)
		expect(leaning(25, 0.95, true)).toBe(false)
	end)

	it("holding the stance keeps up to 30 scoops calm while walking with hard turns, for a whole bar", function()
		for _, count in { 15, 20, 25, 30 } do
			for seed = 1, 3 do
				local state = TowerModel.newState(seed)
				local params = paramsFor(stack("vanilla", count))
				local vx, vz, peak = 0, 0, 0
				TowerModel.setStance(state, true)
				for step = 1, Tuning.stance.holdSeconds / DT do
					local leg = math.floor(step * DT / 1.5) % 4
					local speed = 18 * Tuning.stance.walkMultiplier
					local ax, az
					vx, vz, ax, az = TowerModel.baseVelocityStep(
						vx,
						vz,
						({ speed, 0, -speed, 0 })[leg + 1],
						({ 0, speed, 0, -speed })[leg + 1],
						Tuning.accelSmoothing,
						DT,
						Tuning.turnFactor
					)
					local px, pz = TowerModel.assist(state, params, PAD, Tuning, DT)
					TowerModel.step(state, params, { ax = ax, az = az, padX = px, padZ = pz }, PAD, Tuning, DT)
					peak = math.max(peak, TowerModel.tilt(state) / Tuning.tipAngle)
				end
				expect(state.toppled).toBe(false)
				expect(peak).toBeLessThan(0.5)
			end
		end
	end)

	it("the stance is not invincible: a knockdown hit on a very tall tower leaning that way still wins", function()
		local CombatConfig = require("../src/shared/Config/Combat")
		local state = TowerModel.newState(2)
		local params = paramsFor(stack("vanilla", 30))
		state.x = 0.5 * Tuning.tipAngle
		state.seenX = state.x
		TowerModel.setStance(state, true)
		TowerModel.hitKick(state, CombatConfig, 30, 1, 0, CombatConfig.knockdownBoost)
		for _ = 1, 4 / DT do
			local px, pz = TowerModel.assist(state, params, PAD, Tuning, DT)
			TowerModel.step(state, params, { ax = 0, az = 0, padX = px, padZ = pz }, PAD, Tuning, DT)
		end
		expect(state.toppled).toBe(true)
	end)

	it("a toppled tower takes no stance", function()
		local state = TowerModel.newState(1)
		state.toppled = true
		TowerModel.setStance(state, true)
		expect(state.stance).toBe(false)
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

	it("reset clears the stabiliser's view and the stance", function()
		local state = TowerModel.newState(1)
		state.seenX, state.seenVz = 0.3, 0.2
		TowerModel.setStance(state, true)
		TowerModel.reset(state)
		expect(state.seenX).toBe(0)
		expect(state.seenVz).toBe(0)
		expect(state.stance).toBe(false)
	end)
end)

-- The danger comes from players, not from the physics alone (docs/design-regeln.md). Like assistedRun, but starting
-- with the landing kick of the last caught scoop and walking at the game's speed for the tower (Economy.walkSpeed):
-- `straight` walks 3 s, stops for 1 s and sets off again 30 degrees to the other side, as a player does on the way
-- to the cart. Returns the survival time.
local function freeRun(count: number, seed: number, seconds: number, straight: boolean, stanceAt: number?)
	local state = TowerModel.newState(seed)
	local params = paramsFor(stack("vanilla", count))
	local meter = Stance.new()
	local speed = Economy.walkSpeed(count, capacityFor(count), 0, EconomyConfig)
	local vx, vz = 0, 0
	TowerModel.landingKick(state, Tuning, count)
	for step = 1, seconds / DT do
		local t = step * DT
		if stanceAt then
			local lean = TowerModel.tilt(state) / Tuning.tipAngle
			if lean > stanceAt then
				Stance.start(meter, Tuning.stance)
			elseif lean < 0.2 then
				Stance.stop(meter)
			end
			Stance.advance(meter, DT, Tuning.stance)
			TowerModel.setStance(state, meter.active)
		end
		local tx, tz = 0, 0
		if straight and t % 4 < 3 then
			local leg = math.floor(t / 4)
			local angle = math.rad(30) * (if leg % 2 == 0 then leg / 2 else -(leg + 1) / 2)
			local s = if state.stance then speed * Tuning.stance.walkMultiplier else speed
			tx, tz = math.cos(angle) * s, math.sin(angle) * s
		end
		local ax, az
		vx, vz, ax, az = TowerModel.baseVelocityStep(vx, vz, tx, tz, Tuning.accelSmoothing, DT, Tuning.turnFactor)
		local px, pz = TowerModel.assist(state, params, PAD, Tuning, DT)
		TowerModel.step(state, params, { ax = ax, az = az, padX = px, padZ = pz }, PAD, Tuning, DT)
		if state.toppled then
			return t
		end
	end
	return seconds
end

describe("The danger comes from players, not from the physics alone", function()
	it("a tower standing still never topples by itself, up to 40 scoops", function()
		for _, count in { 25, 30, 35, 40 } do
			for seed = 1, 4 do
				expect(freeRun(count, seed, 120, false)).toBe(120)
			end
		end
	end)

	it("walking straight ahead with stops holds 25 scoops for a minute without any input", function()
		for seed = 1, 6 do
			expect(freeRun(25, seed, 60, true)).toBe(60)
		end
	end)

	it("walking straight ahead with 30 scoops needs the steady stance now and then", function()
		for seed = 1, 4 do
			expect(freeRun(30, seed, 60, true)).toBeLessThan(60)
			expect(freeRun(30, seed, 60, true, 0.6)).toBe(60)
		end
	end)
end)

describe("Outside the arena (safe zone): the tower wobbles but never topples", function()
	local limit = Tuning.safeTiltFraction * Tuning.tipAngle

	-- the worst a player can do: no help, hard turns back and forth, a dash kick and a hit-sized shove now and
	-- then, wild drift on a heavy tower; `safe` decides the zone. Returns the events, the highest lean and whether
	-- it toppled.
	local function abuse(count: number, seed: number, safe: boolean, seconds: number): ({ string }, number, boolean)
		local state = TowerModel.newState(seed)
		local params = paramsFor(stack("test_heavy", count))
		local events, peak = {}, 0
		local steps = math.floor(seconds / DT + 0.5)
		for step = 1, steps do
			local t = step * DT
			if step % 90 == 0 then
				TowerModel.dashKick(state, Tuning.dash, count, if (step // 90) % 2 == 0 then 1 else -1, 0)
			end
			if step % 150 == 0 then
				TowerModel.impulse(state, 0, 1.5)
			end
			local flip = if math.floor(t / 0.6) % 2 == 0 then 1 else -1
			local event = TowerModel.step(state, params, {
				ax = 60 * flip,
				az = 40 * -flip,
				padX = flip,
				padZ = flip,
				safe = safe,
			}, PAD, Tuning, DT)
			if event then
				table.insert(events, event)
			end
			peak = math.max(peak, TowerModel.tilt(state))
			if state.toppled then
				break
			end
		end
		return events, peak, state.toppled
	end

	it("the safe limit lies below the groan, so it can never groan there", function()
		expect(Tuning.safeTiltFraction < Tuning.groanFraction).toBe(true)
		expect(Tuning.safeTiltFraction > 0).toBe(true)
	end)

	it("inside the arena the same abuse topples it (so the test can tell)", function()
		local toppledSomewhere = false
		for seed = 1, 5 do
			local _, _, toppled = abuse(30, seed, false, 30)
			toppledSomewhere = toppledSomewhere or toppled
		end
		expect(toppledSomewhere).toBe(true)
	end)

	it("outside, no tower of any height topples or even groans, for a full minute of abuse", function()
		for _, count in { 1, 5, 12, 25, 40 } do
			for seed = 1, 3 do
				local events, peak, toppled = abuse(count, seed, true, 60)
				expect(toppled).toBe(false)
				expect(#events).toBe(0)
				expect(peak <= limit + 1e-9).toBe(true)
			end
		end
	end)

	it("it still wobbles outside: the lean moves, it is not frozen upright", function()
		local _, peak = abuse(20, 1, true, 10)
		expect(peak > 0.5 * limit).toBe(true)
	end)

	it("a tower groaning as it leaves the arena is saved at once", function()
		local state = TowerModel.newState(3)
		local params = paramsFor(stack("vanilla", 20))
		-- lean it into the groan inside the arena
		state.x = Tuning.groanFraction * Tuning.tipAngle + 0.02
		state.vx = 0.5
		local first = TowerModel.step(state, params, TowerModel.NO_INPUT, PAD, Tuning, DT)
		expect(first).toBe("groan")
		local inputSafe = { ax = 0, az = 0, padX = 0, padZ = 0, safe = true }
		local next = TowerModel.step(state, params, inputSafe, PAD, Tuning, DT)
		expect(next).toBe("saved")
		expect(state.groan).toBe(0)
		-- and stays up however long it is held there
		local events = simulate(state, params, PAD, 20, function()
			return inputSafe
		end)
		expect(#events).toBe(0)
		expect(state.toppled).toBe(false)
	end)

	it("leaving the arena at the edge, it rights itself smoothly instead of snapping back", function()
		local state = TowerModel.newState(5)
		local params = paramsFor(stack("vanilla", 20))
		state.x = Tuning.tipAngle -- right at the edge, past the groan
		state.vx = 0.3 -- still falling outward
		local inputSafe = { ax = 0, az = 0, padX = 0, padZ = 0, safe = true }
		local previous = TowerModel.tilt(state)
		local biggestDrop = 0
		for _ = 1, math.ceil(3 * Tuning.safeEaseTime / DT) do
			expect(TowerModel.step(state, params, inputSafe, PAD, Tuning, DT)).toBe(nil)
			local tilt = TowerModel.tilt(state)
			-- never leans further while above the limit, and never drops in one big jump
			expect(tilt <= previous + 1e-9).toBe(true)
			biggestDrop = math.max(biggestDrop, previous - tilt)
			previous = tilt
		end
		local excess = Tuning.tipAngle - limit
		expect(biggestDrop < 0.1 * excess).toBe(true)
		-- after three time constants at most 5 % of the excess is left
		expect(TowerModel.tilt(state) <= limit + 0.06 * excess).toBe(true)
		expect(state.toppled).toBe(false)
	end)

	it("outside it rights itself, so walking back into the arena does not topple it (playtest 04.11.2026)", function()
		for _, case in
			{ { "vanilla", 5 }, { "vanilla", 17 }, { "vanilla", 40 }, { "test_heavy", 17 }, { "test_heavy", 40 } }
		do
			local state = TowerModel.newState(6)
			local params = paramsFor(stack(case[1], case[2]))
			state.x = limit -- parked at the safe limit, as the playtest showed before the fix
			local inputSafe = { ax = 0, az = 0, padX = 0, padZ = 0, safe = true }
			simulate(state, params, PAD, 4, function()
				return inputSafe
			end)
			expect(TowerModel.tilt(state) < 0.1 * Tuning.tipAngle).toBe(true)
			-- back in the arena without any help, it stands for 2 s, or (a very tall one falls even from upright without
			-- help, that is the arena's job) most of the time a tower starting upright there gets. Parked at the limit,
			-- a 17-scoop tower used to fall in 0.9 s.
			local function secondsUp(s): number
				local t = 0
				while not s.toppled and t < 10 do
					TowerModel.step(s, params, TowerModel.NO_INPUT, PAD, Tuning, DT)
					t += DT
				end
				return t
			end
			local fresh = secondsUp(TowerModel.newState(6))
			expect(secondsUp(state) >= math.min(2, 0.6 * fresh)).toBe(true)
		end
	end)

	it("back in the arena the normal rules apply again", function()
		local state = TowerModel.newState(4)
		local params = paramsFor(stack("vanilla", 20))
		state.x = Tuning.tipAngle
		local event = nil
		for _ = 1, math.ceil(TowerModel.groanLimit(state, Tuning) / DT) + 5 do
			event = TowerModel.step(state, params, TowerModel.NO_INPUT, PAD, Tuning, DT) or event
			state.x = math.max(state.x, Tuning.tipAngle) -- held at the edge
			if state.toppled then
				break
			end
		end
		expect(state.toppled).toBe(true)
	end)
end)

-- Test of 20.11.2026: a tower of about 30 toppled, its owner gathered the spilled scoops and it toppled again at once,
-- over and over. Gathering is stop-and-go walking from scoop to scoop while the tower grows back; it ended leaning with
-- momentum where the stabiliser gives up. The fix: a grace after every pickup (and after getting up), the long warning
-- with a rescue for standing still, and the own sweep (Config/Loot ownSweepRadius).
local Loot = require("../src/shared/Loot")
local LootConfig = require("../src/shared/Config/Loot")
local TowerShape = require("../src/shared/TowerShape")
local HitConfig = require("../src/shared/Config/Combat")

-- Topples a tower of `count` on cone level 2, then walks greedily to each spilled scoop (pickupRadius, no sweep, the
-- harder case) and afterwards stands for `after` seconds. Returns whether it toppled again on its own.
local function gatherAgain(count: number, seed: number, grace: boolean, after: number, rules: any?): boolean
	local tuning = rules or Tuning
	local cone = CONE_STIFFNESS[3]
	local capacity = CONE_CAPACITY[3]
	local keep = Economy.keepOnTopple(count, EconomyConfig)
	local heading = (seed % 628) / 100
	local paths = Loot.spill(
		stack("vanilla", count),
		keep,
		math.cos(heading) * Tuning.tipAngle,
		math.sin(heading) * Tuning.tipAngle,
		seed,
		LootConfig,
		Tuning,
		TowerShape
	)
	local left = {}
	for _, path in paths do
		table.insert(left, { x = path.lx + path.rx, z = path.lz + path.rz })
	end
	local state = TowerModel.newState(seed)
	local held = keep
	local params = paramsFor(stack("vanilla", held), cone)
	local px, pz, vx, vz = 0, 0, 0, 0
	local standing = 0
	while standing < after do
		local tx, tz = 0, 0
		if #left > 0 then
			local best, bestDistance = 1, math.huge
			for index, scoop in left do
				local distance = math.sqrt((scoop.x - px) ^ 2 + (scoop.z - pz) ^ 2)
				if distance < bestDistance then
					best, bestDistance = index, distance
				end
			end
			local speed = Economy.walkSpeed(held, capacity, 0, EconomyConfig)
			tx, tz = (left[best].x - px) / bestDistance * speed, (left[best].z - pz) / bestDistance * speed
		else
			standing += DT
		end
		local ax, az
		vx, vz, ax, az = TowerModel.baseVelocityStep(vx, vz, tx, tz, Tuning.accelSmoothing, DT, Tuning.turnFactor)
		px += vx * DT
		pz += vz * DT
		for index = #left, 1, -1 do
			if math.sqrt((left[index].x - px) ^ 2 + (left[index].z - pz) ^ 2) <= LootConfig.pickupRadius then
				table.remove(left, index)
				held += 1
				params = paramsFor(stack("vanilla", held), cone)
				TowerModel.landingKick(state, Tuning, held)
				if grace then
					TowerModel.pickupGrace(state, Tuning)
				end
			end
		end
		local padX, padZ = TowerModel.assist(state, params, PAD, tuning, DT, tx == 0 and tz == 0)
		TowerModel.step(state, params, { ax = ax, az = az, padX = padX, padZ = padZ }, PAD, tuning, DT)
		if state.toppled then
			return true
		end
	end
	return false
end

-- Pushes a tower of `count` (cone level `cone`) over the groan line and runs it with the stabiliser; `still` is the
-- carrier standing still from the start, `hit` an ice-ball hit at the start. Returns whether it toppled.
local function groaning(count: number, cone: number, still: boolean, hit: boolean?): boolean
	local state = TowerModel.newState(5)
	local params = paramsFor(stack("vanilla", count), CONE_STIFFNESS[cone + 1])
	state.x, state.vx = 0.5 * Tuning.tipAngle, 1.2
	state.seenX, state.seenVx = state.x, state.vx
	if hit then
		TowerModel.hitKick(state, HitConfig, count, 1, 0, 0.3)
	end
	for _ = 1, 10 / DT do
		local padX, padZ = TowerModel.assist(state, params, PAD, Tuning, DT, still)
		TowerModel.step(state, params, { ax = 0, az = 0, padX = padX, padZ = padZ }, PAD, Tuning, DT)
		if state.toppled then
			return true
		end
	end
	return false
end

describe("Gathering a spilled tower (test of 20.11.2026)", function()
	it("reproduces the bug: under the old rules a gathered tower of 30 often topples again on its own", function()
		-- before 20.11.2026: no grace, no rescue, 0.5 s of groaning on its own too
		local old = table.clone(Tuning) :: any
		old.rescue = nil
		old.calmGroanDuration = nil
		local again = 0
		for seed = 1, 20 do
			if gatherAgain(30, seed * 977, false, 15, old) then
				again += 1
			end
		end
		expect(again).toBeGreaterThan(5)
	end)

	it("standing still after gathering mostly holds even without the grace (the rescue, once per cooldown)", function()
		-- since 26.11.2026 the rescue is limited (maxTilt, cooldown), so without the grace a few towers go again
		local again = 0
		for seed = 1, 20 do
			if gatherAgain(30, seed * 977, false, 15) then
				again += 1
			end
		end
		expect(again <= 2).toBe(true)
	end)

	it("with the grace a gathered tower of 28 to 34 stands: it never topples again on its own", function()
		for _, count in { 28, 30, 34 } do
			for seed = 1, 20 do
				expect(gatherAgain(count, seed * 977, true, 15)).toBe(false)
			end
		end
	end)

	it("in the grace the tower rights itself and cannot groan; afterwards the normal rules apply", function()
		local state = TowerModel.newState(3)
		local params = paramsFor(stack("vanilla", 30), CONE_STIFFNESS[3])
		state.x, state.vx = 0.9 * Tuning.tipAngle, 0.5
		TowerModel.startGrace(state, Tuning.graceSeconds)
		local events = simulate(state, params, PAD, Tuning.graceSeconds - 0.1, nil)
		expect(#events).toBe(0)
		expect(state.toppled).toBe(false)
		expect(TowerModel.tilt(state)).toBeLessThan(0.2 * Tuning.tipAngle)
		expect(TowerModel.inGrace(state)).toBe(true)
		simulate(state, params, PAD, 0.2, nil)
		expect(TowerModel.inGrace(state)).toBe(false)
	end)

	it("a hit or a dash ends the grace at once: hits keep their full danger", function()
		local state = TowerModel.newState(3)
		TowerModel.startGrace(state, Tuning.graceSeconds)
		TowerModel.hitKick(state, HitConfig, 20, 1, 0, 1)
		expect(TowerModel.inGrace(state)).toBe(false)
		TowerModel.startGrace(state, Tuning.graceSeconds)
		TowerModel.dashKick(state, Tuning.dash, 20, 1, 0)
		expect(TowerModel.inGrace(state)).toBe(false)
	end)

	it("the grace survives the reset a knockdown's spill brings", function()
		local state = TowerModel.newState(3)
		TowerModel.startGrace(state, 4)
		TowerModel.reset(state)
		expect(TowerModel.inGrace(state)).toBe(true)
	end)

	it("toppling on its own groans longer than after a hit or a dash", function()
		local state = TowerModel.newState(3)
		expect(TowerModel.groanLimit(state, Tuning)).toBe(Tuning.calmGroanDuration)
		TowerModel.hitKick(state, HitConfig, 10, 1, 0, 0.5)
		expect(TowerModel.groanLimit(state, Tuning)).toBe(Tuning.groanDuration)
		state.t += Tuning.forcedWindow + 0.1
		expect(TowerModel.groanLimit(state, Tuning)).toBe(Tuning.calmGroanDuration)
		expect(Tuning.calmGroanDuration > Tuning.groanDuration).toBe(true)
	end)

	it("standing still rescues a groaning tower of up to 40; walking on does not", function()
		for _, case in { { 20, 0 }, { 30, 2 }, { 40, 3 } } do
			expect(groaning(case[1], case[2], true)).toBe(false)
			expect(groaning(case[1], case[2], false)).toBe(true)
		end
	end)

	it("standing still does not rescue a tower a hit has just pushed over", function()
		expect(groaning(30, 2, true, true)).toBe(true)
	end)
end)

-- Test of 26.11.2026: a tower of 32 hung far over with a red gauge and "SAVED!" came again and again; it never fell.
-- The rescue let go at the groan line, where the stabiliser has given up, and caught it again at once. And every scoop
-- picked up from the ground (Big Swirl scoops too) restarted the grace, so gathering kept the tower safe for good.

-- A tower of `count` leaning `lean` (share of tipAngle) whose carrier stands still for `seconds`, with `rules`.
-- Returns whether it toppled and how often it was "saved".
local function standStill(count: number, lean: number, seconds: number, rules: any?): (boolean, number)
	local tuning = rules or Tuning
	local state = TowerModel.newState(3)
	local params = TowerModel.params(stack("vanilla", count), FLAVORS, tuning, 1)
	state.x = lean * Tuning.tipAngle
	state.seenX = state.x
	local saved = 0
	for _ = 1, seconds / DT do
		local padX, padZ = TowerModel.assist(state, params, PAD, tuning, DT, true)
		local event = TowerModel.step(state, params, { ax = 0, az = 0, padX = padX, padZ = padZ }, PAD, tuning, DT)
		if event == "saved" then
			saved += 1
		end
		if state.toppled then
			return true, saved
		end
	end
	return false, saved
end

-- Zigzag with a tower of `count`, nobody balancing: walking at 16 studs/s, the heading swinging 60 degrees to either
-- side every 0.8 s, with the Stability upgrade at `stability`. Returns when it toppled (nil: it stood for 120 s).
local function zigzag(count: number, seed: number, stability: number): number?
	local tuning = table.clone(Tuning) :: any
	tuning.walkHeavyFrom = Upgrades.value("stability", stability, UpgradesConfig)
	local state = TowerModel.newState(seed)
	local params = TowerModel.params(stack("vanilla", count), FLAVORS, tuning, 1)
	local vx, vz = 0, 0
	for step = 1, 120 / DT do
		local t = step * DT
		local side = if math.floor(t / 0.8) % 2 == 0 then 1 else -1
		local heading = math.rad(60) * side + seed
		local ax, az
		vx, vz, ax, az = TowerModel.baseVelocityStep(
			vx,
			vz,
			math.cos(heading) * 16,
			math.sin(heading) * 16,
			Tuning.accelSmoothing,
			DT,
			Tuning.turnFactor
		)
		local padX, padZ = TowerModel.assist(state, params, PAD, tuning, DT, false)
		TowerModel.step(state, params, { ax = ax, az = az, padX = padX, padZ = padZ }, PAD, tuning, DT)
		if state.toppled then
			return t
		end
	end
	return nil
end

describe("Rescue and grace are limited (test of 26.11.2026)", function()
	it(
		"reproduces the bug: under the old rescue a leaning tower of 32 is saved hundreds of times and never falls",
		function()
			local old = table.clone(Tuning) :: any
			old.rescue = { authority = Tuning.rescue.authority, kp = Tuning.rescue.kp, kd = Tuning.rescue.kd }
			local toppled, saved = standStill(32, 0.85, 60, old)
			expect(toppled).toBe(false)
			expect(saved).toBeGreaterThan(100)
		end
	)

	it("the values live in the config", function()
		expect(Tuning.rescue.maxTilt).toBe(0.9)
		expect(Tuning.rescue.cooldown).toBe(10)
		expect(Tuning.rescue.release < Tuning.groanFraction).toBe(true)
		expect(Tuning.rescue.maxTilt > Tuning.groanFraction).toBe(true)
		expect(Tuning.graceCooldown).toBe(10)
	end)

	it("a tower of 32 leaning past the limit topples although its carrier stands still", function()
		for _, lean in { Tuning.rescue.maxTilt, 0.95, 1 } do
			local toppled, saved = standStill(32, lean, 10)
			expect(toppled).toBe(true)
			expect(saved).toBe(0)
		end
	end)

	it("in the warning window below the limit standing still saves it once, upright, and it stays up", function()
		for _, lean in { 0.8, 0.85 } do
			local toppled, saved = standStill(32, lean, 60)
			expect(toppled).toBe(false)
			expect(saved).toBe(1)
		end
	end)

	it("a second groan within the cooldown is not rescued", function()
		local state = TowerModel.newState(3)
		local params = TowerModel.params(stack("vanilla", 32), FLAVORS, Tuning, 1)
		state.x = 0.85 * Tuning.tipAngle
		state.groan = DT
		TowerModel.assist(state, params, PAD, Tuning, DT, true)
		expect(state.rescuing).toBe(true)
		-- the carrier walks off, the rescue ends; it groans again 5 s later
		state.t += 5
		TowerModel.assist(state, params, PAD, Tuning, DT, false)
		expect(state.rescuing).toBe(false)
		TowerModel.assist(state, params, PAD, Tuning, DT, true)
		expect(state.rescuing).toBe(false)
		-- after the cooldown it would be rescued again
		state.t += Tuning.rescue.cooldown
		TowerModel.assist(state, params, PAD, Tuning, DT, true)
		expect(state.rescuing).toBe(true)
	end)

	-- (from Stability level 15 on, walking with 35 feels like walking with 20 to 25 and a tower can hold the zigzag: the
	-- upgrade does that on purpose; level 8 is the Studio save of 26.11.2026)
	it("zigzag with 35 scoops throws the tower over sooner or later, without the upgrade and at Stability 8", function()
		for _, stability in { 0, 8 } do
			for seed = 1, 8 do
				local toppledAt = zigzag(35, seed, stability)
				expect(toppledAt ~= nil).toBe(true)
			end
		end
	end)

	it("a pickup grace is not extended by more pickups and starts again only after the cooldown", function()
		local state = TowerModel.newState(3)
		expect(TowerModel.pickupGrace(state, Tuning)).toBe(true)
		local until1 = state.graceUntil
		state.t += 1
		expect(TowerModel.pickupGrace(state, Tuning)).toBe(false)
		expect(state.graceUntil).toBe(until1)
		state.t += Tuning.graceSeconds -- the grace is over, the cooldown not yet
		expect(TowerModel.inGrace(state)).toBe(false)
		expect(TowerModel.pickupGrace(state, Tuning)).toBe(false)
		state.t = Tuning.graceCooldown
		expect(TowerModel.pickupGrace(state, Tuning)).toBe(true)
	end)

	it("getting up always starts the grace, the pickup cooldown does not stop it", function()
		local state = TowerModel.newState(3)
		TowerModel.pickupGrace(state, Tuning)
		state.t += Tuning.graceSeconds + 1
		TowerModel.startGrace(state, 2 + Tuning.graceSeconds)
		expect(TowerModel.inGrace(state)).toBe(true)
	end)
end)

describe("Walking heaviness (Config/Tower walkHeavyFrom, for the Stability upgrade)", function()
	it("at the default walking feels exactly gravity - stiffness, on every cone", function()
		expect(Tuning.walkHeavyFrom).toBe(10)
		for cone = 0, 5 do
			for count = 1, 65 do
				local params = paramsFor(stack("vanilla", count), CONE_STIFFNESS[cone + 1])
				expect(params.walkInstability).toBeCloseTo(math.max(0, params.gravity - params.stiffness), 1e-9)
			end
		end
	end)

	it("a higher value only calms walking: gravity, pad and hits stay the same", function()
		local heavier = table.clone(Tuning) :: any
		heavier.walkHeavyFrom = Tuning.walkHeavyFrom + 6
		local ids = stack("vanilla", 30)
		local base = TowerModel.params(ids, FLAVORS, Tuning, 1)
		local calm = TowerModel.params(ids, FLAVORS, heavier, 1)
		expect(calm.gravity).toBe(base.gravity)
		expect(calm.stiffness).toBe(base.stiffness)
		expect(TowerModel.padAuthority(calm, PAD, heavier)).toBe(TowerModel.padAuthority(base, PAD, Tuning))
		expect(TowerModel.accelAuthority(calm, PAD)).toBeLessThan(TowerModel.accelAuthority(base, PAD))
		-- six scoops more: walking with 30 feels like walking with 24 did
		local felt = TowerModel.params(stack("vanilla", 24), FLAVORS, Tuning, 1)
		expect(calm.walkInstability).toBeCloseTo(felt.walkInstability, 1e-9)
		-- a hit kicks as hard either way (it does not look at params)
		local a, b = TowerModel.newState(1), TowerModel.newState(1)
		expect(TowerModel.hitKick(a, HitConfig, 30, 1, 0, 1)).toBe(TowerModel.hitKick(b, HitConfig, 30, 1, 0, 1))
	end)
end)
