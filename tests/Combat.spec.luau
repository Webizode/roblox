local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Combat = require("../src/shared/Combat")
local Config = require("../src/shared/Config/Combat")
local TowerModel = require("../src/shared/TowerModel")
local Flavors = require("../src/shared/Config/Flavors")
local Tuning = require("../src/shared/Config/Tower")

local DT = 1 / 60

describe("Ice-ball flight and hits", function()
	it("flies through the aim point at every strength and perfect, from the hand, within its flight time", function()
		for _, speed in
			{
				Combat.throwSpeed(0, false, Config),
				Combat.throwSpeed(0.5, false, Config),
				Combat.throwSpeed(1, false, Config),
				Combat.throwSpeed(1, true, Config),
			}
		do
			for _, target in { { 0, 0, 20 }, { 15, -3, 30 }, { -10, 6, 25 }, { 0, -4, 5 } } do
				local ok, vx, vy, vz = Combat.aimVelocity(0, 4, 0, target[1], 4 + target[2], target[3], speed, Config)
				expect(ok).toBe(true)
				expect(math.sqrt(vx * vx + vy * vy + vz * vz)).toBeCloseTo(speed, 1e-6)
				local flat = math.sqrt(target[1] ^ 2 + target[3] ^ 2)
				local t = flat / math.sqrt(vx * vx + vz * vz)
				expect(t).toBeLessThan(Config.maxFlight + 1e-6)
				local x, y, z = Combat.position(0, 4, 0, vx, vy, vz, Config.gravity, t)
				expect(x).toBeCloseTo(target[1], 1e-4)
				expect(y).toBeCloseTo(4 + target[2], 1e-4)
				expect(z).toBeCloseTo(target[3], 1e-4)
			end
		end
	end)

	it("aims straight with a little lift at points out of reach, and stronger throws reach further", function()
		local weak, strong = Combat.throwSpeed(0, false, Config), Combat.throwSpeed(1, false, Config)
		expect(strong).toBeGreaterThan(weak)
		-- just out of a weak throw's reach (its best range is speed^2 / gravity), well inside a strong one's
		local distance = weak * weak / Config.gravity + 5
		local ok, _, vy, vz = Combat.aimVelocity(0, 0, 0, 0, 0, distance, weak, Config)
		expect(ok).toBe(true)
		expect(vy / weak).toBeCloseTo(Config.lift / math.sqrt(1 + Config.lift ^ 2), 1e-6)
		expect(vz).toBeGreaterThan(0)
		local hits, sx, sy, sz = Combat.aimVelocity(0, 0, 0, 0, 0, 60, strong, Config)
		expect(hits).toBe(true)
		local t = 60 / sz
		local _, y = Combat.position(0, 0, 0, sx, sy, sz, Config.gravity, t)
		expect(y).toBeCloseTo(0, 1e-4)
	end)

	it("rejects aims no client produces", function()
		expect((Combat.aimVelocity(0, 0, 0, 0 / 0, 0, 10, 60, Config))).toBe(false)
		expect((Combat.aimVelocity(math.huge, 0, 0, 0, 0, 10, 60, Config))).toBe(false)
		expect((Combat.aimVelocity(0, 0, 0, 0, 0.2, 0, 60, Config))).toBe(false)
	end)

	it("finds a centred hit, a grazing hit and a miss against the player capsule", function()
		-- ball flying along +z through z = 10, the target stands at (x, 0, 10)
		local centre = Combat.closestToCapsule(0, 0, 0, 0, 0, 20, 0, 0, 10, Config.hitHalfHeight)
		local graze = Combat.closestToCapsule(2.5, 0, 0, 2.5, 0, 20, 0, 0, 10, Config.hitHalfHeight)
		local miss = Combat.closestToCapsule(6, 0, 0, 6, 0, 20, 0, 0, 10, Config.hitHalfHeight)
		local over = Combat.closestToCapsule(0, 8, 0, 0, 8, 20, 0, 0, 10, Config.hitHalfHeight)
		local reach = Config.hitRadius + Config.ballRadius
		expect(centre).toBeCloseTo(0, 1e-6)
		expect(graze).toBeLessThan(reach)
		expect(miss).toBeGreaterThan(reach)
		expect(over).toBeGreaterThan(reach)
	end)

	it("says where along the segment the closest point is", function()
		local _, s = Combat.closestToCapsule(0, 0, 0, 0, 0, 20, 0, 0, 5, Config.hitHalfHeight)
		expect(s).toBeCloseTo(0.25, 1e-6)
	end)

	it(
		"makes centred, fast, charged hits stronger than grazing, slowed or uncharged ones, all within [0, 1]",
		function()
			local speed = Config.maxSpeed
			local full = Combat.hitPower(0, speed, speed, 1, Config)
			local graze = Combat.hitPower(Config.hitRadius, speed, speed, 1, Config)
			local slow = Combat.hitPower(0, speed * 0.5, speed, 1, Config)
			local weak = Combat.hitPower(0, Config.minSpeed, Config.minSpeed, 0, Config)
			expect(full).toBeCloseTo(1, 1e-6)
			expect(graze).toBeLessThan(full)
			expect(slow).toBeLessThan(full)
			expect(weak).toBeCloseTo(Config.powerAtMinCharge, 1e-6)
			expect(graze).toBeGreaterThan(0)
			local worst = Combat.hitPower(Config.hitRadius + Config.ballRadius, 1, speed, 0, Config)
			expect(worst).toBeGreaterThan(0)
			expect(Combat.hitPower(0, speed, speed, 7, Config)).toBe(1)
		end
	)
end)

describe("Holding a throw", function()
	it("a tap is strength 0, holding raises it to full in perfect.rise, and it stays full", function()
		local rise = Config.perfect.rise
		expect(Combat.strength(0, Config)).toBe(0)
		expect(Combat.strength(rise / 2, Config)).toBeCloseTo(0.5, 1e-9)
		expect(Combat.strength(rise, Config)).toBe(1)
		expect(Combat.strength(rise * 4, Config)).toBe(1)
		expect(Combat.strength(-1, Config)).toBe(0)
		expect(Combat.strength(0 / 0, Config)).toBe(0)
		local last = 0
		for held = 0, 3, 0.013 do
			local value = Combat.strength(held, Config)
			expect(value >= last).toBe(true)
			last = value
		end
	end)

	it("the inner circle grows to the outer one, shrinks back and again, as long as it is held", function()
		local rise = Config.perfect.rise
		expect(Combat.pulse(0, Config)).toBe(0)
		expect(Combat.pulse(rise / 2, Config)).toBeCloseTo(0.5, 1e-9)
		expect(Combat.pulse(rise, Config)).toBeCloseTo(1, 1e-9)
		expect(Combat.pulse(rise * 1.5, Config)).toBeCloseTo(0.5, 1e-9)
		expect(Combat.pulse(rise * 2, Config)).toBeCloseTo(0, 1e-9)
		expect(Combat.pulse(rise * 3, Config)).toBeCloseTo(1, 1e-9)
		expect(Combat.pulse(0 / 0, Config)).toBe(0)
		for held = 0, 5, 0.017 do
			local value = Combat.pulse(held, Config)
			expect(value >= 0 and value <= 1).toBe(true)
		end
	end)

	it("perfect exactly when it touches the outer circle, each time, faster and no harder", function()
		local p = Config.perfect
		for _, touch in { p.rise, 3 * p.rise, 5 * p.rise } do
			expect(Combat.isPerfect(touch, Config)).toBe(true)
			expect(Combat.isPerfect(touch - p.window / 2 + 0.001, Config)).toBe(true)
			expect(Combat.isPerfect(touch + p.window / 2 - 0.001, Config)).toBe(true)
			expect(Combat.isPerfect(touch - p.window / 2 - 0.01, Config)).toBe(false)
			expect(Combat.isPerfect(touch + p.window / 2 + 0.01, Config)).toBe(false)
			-- and only there: the inner circle is (nearly) the outer one
			expect(Combat.pulse(touch, Config)).toBeCloseTo(1, 1e-9)
		end
		expect(Combat.isPerfect(0, Config)).toBe(false)
		expect(Combat.isPerfect(2 * p.rise, Config)).toBe(false) -- back in the middle
		expect(Combat.isPerfect(0 / 0, Config)).toBe(false)
		expect(Combat.throwSpeed(1, true, Config)).toBe(p.speed)
		expect(p.speed).toBeGreaterThan(Config.maxSpeed)
		local full = Combat.hitPower(0, Config.maxSpeed, Config.maxSpeed, 1, Config)
		local perfect = Combat.hitPower(0, p.speed, p.speed, 1, Config)
		expect(perfect).toBeCloseTo(full, 1e-9)
		expect(p.window >= 0.1).toBe(true) -- doable with a thumb or a trigger
	end)

	it("accepts an honest strength and perfect throw within the network jitter", function()
		local tolerance = Config.chargeTolerance
		for held = 0, 3, 0.03 do
			for _, jitter in { -tolerance, -tolerance / 2, 0, tolerance / 2, tolerance } do
				local clientHeld = math.max(0, held + jitter)
				local strength = Combat.strength(clientHeld, Config)
				expect(Combat.validateStrength(strength, held, Config)).toBeCloseTo(strength, 1e-9)
				if Combat.isPerfect(clientHeld, Config) then
					expect(Combat.validatePerfect(true, held, Config)).toBe(true)
				end
			end
		end
	end)

	it("never gives more than the measured hold allows", function()
		local p, tolerance = Config.perfect, Config.chargeTolerance
		local tap = Combat.validateStrength(1, 0.05, Config)
		expect(tap).toBeCloseTo(Combat.strength(0.05 + tolerance, Config), 1e-9)
		expect(tap).toBeLessThan(0.5)
		expect(Combat.validateStrength(1, 0, Config)).toBeCloseTo(tolerance / p.rise, 1e-9)
		-- a perfect claim for a tap, or with the inner circle back in the middle, is turned down
		expect(Combat.validatePerfect(true, 0.05, Config)).toBe(false)
		expect(Combat.validatePerfect(true, 2 * p.rise, Config)).toBe(false)
		expect(Combat.validatePerfect(true, p.rise - p.window / 2 - tolerance - 0.02, Config)).toBe(false)
		-- just outside the window but within the jitter still counts
		expect(Combat.validatePerfect(true, p.rise + p.window / 2 + tolerance * 0.9, Config)).toBe(true)
		expect(Combat.validatePerfect("yes" :: any, p.rise, Config)).toBe(false)
		expect(Combat.validatePerfect(true, 0 / 0, Config)).toBe(false)
		expect(Combat.validateStrength(5, p.rise, Config)).toBe(1)
		expect(Combat.validateStrength(0 / 0, p.rise / 2, Config)).toBeCloseTo(0.5, 1e-9)
	end)

	it(
		"three taps on the middle knock down at the third, two do not, grazing taps never; two strong ones do",
		function()
			-- a whole load at a realistic pace: the throw interval, a short hold and the network on top
			local pace = Config.throwInterval + 0.2
			local function load(power: number): number?
				local stagger, lastHitAt = 0, -math.huge
				for index = 1, Config.ammo do
					local time = (index - 1) * pace
					local down
					stagger, down = Combat.addHit(stagger, lastHitAt, time, power, Config)
					lastHitAt = time
					if down then
						return index
					end
				end
				return nil
			end
			local tap = Combat.hitPower(0, Config.minSpeed, Config.minSpeed, 0, Config)
			expect(load(tap)).toBe(3)
			local grazingTap = Combat.hitPower(2, Config.minSpeed, Config.minSpeed, 0, Config)
			expect(load(grazingTap)).toBeNil()
			local strong = Combat.hitPower(0, Config.maxSpeed, Config.maxSpeed, 1, Config)
			local stagger = Combat.addHit(0, 0, 0, strong, Config)
			local _, knocked = Combat.addHit(stagger, 0, 0.6, strong, Config)
			expect(knocked).toBe(true)
		end
	)
end)

describe("Knockdown threshold", function()
	it("never knocks down with a single hit, however strong", function()
		local _, down = Combat.addHit(0, 0, 0, 1, Config)
		expect(down).toBe(false)
	end)

	it("knocks down after two solid hits in quick succession, not after two spread out", function()
		local stagger = Combat.addHit(0, 0, 0, 1, Config)
		local _, quick = Combat.addHit(stagger, 0, 0.4, 1, Config)
		local _, slow = Combat.addHit(stagger, 0, 3, 1, Config)
		expect(quick).toBe(true)
		expect(slow).toBe(false)
	end)

	it("two grazing hits do not knock down, even fully charged", function()
		local speed = Config.maxSpeed
		local power = Combat.hitPower(Config.hitRadius + Config.ballRadius * 0.9, speed * 0.7, speed, 1, Config)
		local stagger = Combat.addHit(0, 0, 0, power, Config)
		local _, down = Combat.addHit(stagger, 0, 0.4, power, Config)
		expect(down).toBe(false)
	end)

	it("a knockdown resets the stagger", function()
		local stagger, down = Combat.addHit(1.2, 0, 0, 1, Config)
		expect(down).toBe(true)
		expect(stagger).toBe(0)
	end)
end)

describe("Ammo", function()
	it("allows exactly three throws, then reloads for seven seconds and refills all three", function()
		local ammo = Combat.newAmmo(Config)
		expect(Combat.tryThrow(ammo, 0, Config)).toBe(true)
		expect(Combat.tryThrow(ammo, 0.5, Config)).toBe(true)
		expect(Combat.tryThrow(ammo, 1.0, Config)).toBe(true)
		expect(ammo.count).toBe(0)
		expect(ammo.reloadUntil).toBe(1.0 + Config.reloadTime)
		expect(Combat.tryThrow(ammo, 2, Config)).toBe(false)
		expect(Combat.tryThrow(ammo, 1.0 + Config.reloadTime - 0.01, Config)).toBe(false)
		expect(Combat.tryThrow(ammo, 1.0 + Config.reloadTime, Config)).toBe(true)
		expect(ammo.count).toBe(Config.ammo - 1)
	end)

	it("every throw costs one, and the interval stops a whole load in one burst", function()
		local ammo = Combat.newAmmo(Config)
		expect(Combat.tryThrow(ammo, 10, Config)).toBe(true)
		expect(Combat.tryThrow(ammo, 10.1, Config)).toBe(false)
		expect(ammo.count).toBe(Config.ammo - 1)
	end)

	it("a partly used load does not refill by itself", function()
		local ammo = Combat.newAmmo(Config)
		Combat.tryThrow(ammo, 0, Config)
		Combat.refresh(ammo, 100, Config)
		expect(ammo.count).toBe(Config.ammo - 1)
	end)
end)

describe("Ammo display", function()
	it("shows the loaded balls and no refill while there is ammo", function()
		local ammo = Combat.newAmmo(Config)
		for throws = 0, Config.ammo - 1 do
			local loaded, refill = Combat.ammoDisplay(ammo.count, ammo.reloadUntil, throws, Config)
			expect(loaded).toBe(Config.ammo - throws)
			expect(refill).toBe(0)
			Combat.tryThrow(ammo, throws, Config)
		end
	end)

	it("fills up over the reload of an empty load", function()
		local ammo = Combat.newAmmo(Config)
		for throws = 1, Config.ammo do
			Combat.tryThrow(ammo, throws, Config)
		end
		local start = ammo.reloadUntil - Config.reloadTime
		local loaded, refill = Combat.ammoDisplay(ammo.count, ammo.reloadUntil, start, Config)
		expect(loaded).toBe(0)
		expect(refill).toBeCloseTo(0)
		_, refill = Combat.ammoDisplay(ammo.count, ammo.reloadUntil, start + Config.reloadTime / 2, Config)
		expect(refill).toBeCloseTo(0.5)
		-- the refill message arrives a moment after the reload ends: the display stays full meanwhile
		_, refill = Combat.ammoDisplay(ammo.count, ammo.reloadUntil, ammo.reloadUntil + 0.1, Config)
		expect(refill).toBe(1)
	end)

	it("clamps attribute values that make no sense", function()
		expect(Combat.ammoDisplay(99, 0, 0, Config)).toBe(Config.ammo)
		expect(Combat.ammoDisplay(-2, 0, 0, Config)).toBe(0)
		expect(Combat.ammoDisplay(2.7, 0, 0, Config)).toBe(2)
		expect(Combat.ammoDisplay(0 / 0, 0, 0, Config)).toBe(0)
		local loaded, refill = Combat.ammoDisplay(0, math.huge, 0, Config)
		expect(loaded).toBe(0)
		expect(refill).toBe(0)
		_, refill = Combat.ammoDisplay(0, 0 / 0, 0, Config)
		expect(refill).toBe(0)
	end)
end)

local function runWithAssist(state, count: number, seconds: number)
	local params = TowerModel.params(table.create(count, "vanilla"), Flavors.byId, Tuning, 1)
	for _ = 1, seconds / DT do
		local px, pz = TowerModel.assist(state, params, Tuning.variant, Tuning, DT)
		TowerModel.step(state, params, { ax = 0, az = 0, padX = px, padZ = pz }, Tuning.variant, Tuning, DT)
	end
	return state.toppled
end

describe("Tower reaction to a hit", function()
	it("pushes the tower along the flight, harder for taller towers and stronger hits, capped", function()
		local small, tall, weak = TowerModel.newState(1), TowerModel.newState(1), TowerModel.newState(1)
		local kSmall = TowerModel.hitKick(small, Config, 3, 0, 1, 1)
		local kTall = TowerModel.hitKick(tall, Config, 15, 0, 1, 1)
		local kWeak = TowerModel.hitKick(weak, Config, 15, 0, 1, 0.5)
		expect(small.vz).toBeGreaterThan(0)
		expect(kTall).toBeGreaterThan(kSmall)
		expect(kWeak).toBeLessThan(kTall)
		expect(TowerModel.hitKick(TowerModel.newState(1), Config, 500, 1, 0, 1)).toBe(Config.towerKickMax)
	end)

	it("one full hit on an upright tower of up to 9 scoops is absorbed by the stabiliser", function()
		for count = 1, 9 do
			local state = TowerModel.newState(count)
			TowerModel.hitKick(state, Config, count, 1, 0, 1)
			expect(runWithAssist(state, count, 6)).toBe(false)
		end
	end)

	it("a hit on a tall tower forces a reaction: without the stance it falls, with it it holds", function()
		local function hit(count: number, lean: number, power: number, stance: boolean)
			local state = TowerModel.newState(2)
			state.x = lean * Tuning.tipAngle
			state.seenX = state.x
			TowerModel.hitKick(state, Config, count, 1, 0, power)
			TowerModel.setStance(state, stance)
			return runWithAssist(state, count, 6)
		end
		expect(hit(12, 0.3, 1, false)).toBe(true)
		expect(hit(12, 0.3, 1, true)).toBe(false)
		expect(hit(16, 0, 1, false)).toBe(true)
		expect(hit(16, 0, 1, true)).toBe(false)
		-- the limit: a knockdown hit on a very tall tower already leaning the same way is lost even in the stance
		expect(hit(25, 0.5, Config.knockdownBoost, true)).toBe(true)
	end)

	it("hits shake the tower: a hit right after another kicks harder, one after a long pause does not", function()
		local state = TowerModel.newState(1)
		local first = TowerModel.hitKick(state, Config, 5, 1, 0, 1)
		state.t += 0.45
		local second = TowerModel.hitKick(state, Config, 5, 1, 0, 1)
		expect(second).toBeGreaterThan(first)
		state.t += 10
		expect(TowerModel.hitKick(state, Config, 5, 1, 0, 1)).toBeCloseTo(first, 1e-9)
		-- a reset (topple, serve) forgets the shaking
		state.t += 0.1
		TowerModel.reset(state)
		expect(TowerModel.hitKick(state, Config, 5, 1, 0, 1)).toBeCloseTo(first, 1e-9)
	end)

	it("hits in quick succession can topple a short tower that the same hits spread out cannot", function()
		local function series(count: number, powers: { number }, interval: number): boolean
			local state = TowerModel.newState(7)
			runWithAssist(state, count, 1)
			for index, power in powers do
				TowerModel.hitKick(state, Config, count, 1, 0, power)
				if runWithAssist(state, count, if index < #powers then interval else 6) then
					return true
				end
			end
			return state.toppled
		end
		local quick = Config.throwInterval + 0.05
		expect(series(5, { 1, 1 }, quick)).toBe(true)
		expect(series(5, { 0.8, 0.8, 0.8 }, quick)).toBe(true)
		expect(series(5, { 1, 1, 1 }, 1.5)).toBe(false)
		expect(series(5, { 0.6, 0.6 }, quick)).toBe(false)
		-- no fixed number of hits: a single scoop rights itself after the two quick full hits that topple five
		expect(series(1, { 1, 1 }, quick)).toBe(false)
		-- but three quick full hits topple even the smallest tower (protection for small towers comes with the loot)
		expect(series(1, { 1, 1, 1 }, quick)).toBe(true)
	end)

	it("the steady stance is no shield: a hit in it reaches the tower at stanceTowerScale", function()
		local free, steady = TowerModel.newState(1), TowerModel.newState(1)
		TowerModel.setStance(steady, true)
		local kFree = TowerModel.hitKick(free, Config, 5, 1, 0, 1)
		local kSteady = TowerModel.hitKick(steady, Config, 5, 1, 0, 1)
		expect(kSteady).toBeCloseTo(kFree * Config.stanceTowerScale, 1e-9)
		expect(steady.vx).toBeGreaterThan(0)
		-- the shake builds up at the same share, so the next hit is softened too
		expect(steady.shake).toBeCloseTo(free.shake * Config.stanceTowerScale, 1e-9)
	end)

	it("held through two quick full hits, the stance keeps even 25 scoops up", function()
		local state = TowerModel.newState(7)
		runWithAssist(state, 25, 1)
		TowerModel.setStance(state, true)
		TowerModel.hitKick(state, Config, 25, 1, 0, 1)
		runWithAssist(state, 25, Config.throwInterval + 0.05)
		TowerModel.hitKick(state, Config, 25, 1, 0, 1)
		-- the rest of a full bar
		expect(runWithAssist(state, 25, 3)).toBe(false)
	end)
end)

describe("Hits: how centred they count", function()
	-- a ball thrown flat at the axis of a player 15 studs away, checked frame by frame like the server does
	local function firstHit(offset: number, strength: number)
		local speed = Combat.throwSpeed(strength, false, Config)
		local ox, oy, oz = 0, 5, 0
		local cx, cy, cz = offset, 5, 15
		-- aimed straight ahead; the player stands `offset` studs to the side of that line
		local _, vx, vy, vz = Combat.aimVelocity(ox, oy, oz, 0, 5, 15, speed, Config)
		local reach = Config.hitRadius + Config.ballRadius
		local last = 0
		for frame = 1, 120 do
			local t = frame / 60
			local ax, ay, az = Combat.position(ox, oy, oz, vx, vy, vz, Config.gravity, last)
			local bx, by, bz = Combat.position(ox, oy, oz, vx, vy, vz, Config.gravity, t)
			local entry = Combat.closestToCapsule(ax, ay, az, bx, by, bz, cx, cy, cz, Config.hitHalfHeight)
			if entry <= reach then
				local pass = Combat.passDistance(ox, oy, oz, vx, vy, vz, last, cx, cy, cz, Config)
				return entry, math.min(entry, pass), speed
			end
			last = t
		end
		return nil
	end

	it("a ball aimed at the middle counts as centred, not as the graze where it entered the reach", function()
		local entry, centred = firstHit(0, 1)
		-- the frame where it entered is near the edge of the reach: that alone made every hit a graze
		expect((entry :: number) > 1.5).toBe(true)
		expect(centred).toBeLessThan(0.5)
	end)

	it("a ball passing the side still counts as off-centre", function()
		local _, centred = firstHit(2, 1)
		expect(centred).toBeCloseTo(2, 0.3)
	end)

	it("knockdown happens: two full-strength hits on the middle, or three taps on the middle", function()
		local _, centred, speed = firstHit(0, 1)
		local strong = Combat.hitPower(centred, speed, speed, 1, Config)
		expect(strong).toBeGreaterThan(0.9)
		local stagger, down = Combat.addHit(0, -math.huge, 0, strong, Config)
		expect(down).toBe(false) -- one hit never knocks down
		stagger, down = Combat.addHit(stagger, 0, Config.throwInterval + 0.1, strong, Config)
		expect(down).toBe(true)

		local _, tapCentred, tapSpeed = firstHit(0, 0)
		local tap = Combat.hitPower(tapCentred, tapSpeed, tapSpeed, 0, Config)
		expect(tap).toBeGreaterThan(0.55)
		local s, last, knocked = 0, -math.huge, false
		for i = 1, Config.ammo do
			local now = (i - 1) * (Config.throwInterval + 0.1)
			local kd
			s, kd = Combat.addHit(s, last, now, tap, Config)
			last = now
			knocked = knocked or kd
		end
		expect(knocked).toBe(true)
	end)
end)
