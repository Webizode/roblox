local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Combat = require("../src/shared/Combat")
local HitPoints = require("../src/shared/HitPoints")
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
end)

describe("Ammo: ball by ball", function()
	local per, delay, gap = Config.reloadPerBall, Config.reloadDelay, Config.throwInterval
	local EPS = 0.001

	-- the count after refreshing at `time`
	local function countAt(ammo, time: number): number
		Combat.refresh(ammo, time, Config)
		return ammo.count
	end

	it("one ball loads in about 1.4 s after a 0.5 s wait, and empty to full takes a bit over 4 s", function()
		expect(per).toBe(1.4)
		expect(delay).toBe(0.5)
		expect(Config.ammo * per).toBeCloseTo(4.2, 1e-9)
	end)

	it("throwing 1: it comes back alone, delay + one ball after the throw", function()
		local ammo = Combat.newAmmo(Config)
		expect(Combat.tryThrow(ammo, 0, Config)).toBe(true)
		expect(ammo.count).toBe(2)
		expect(countAt(ammo, delay + per - EPS)).toBe(2)
		expect(countAt(ammo, delay + per)).toBe(3)
		expect(ammo.reloadUntil).toBe(0) -- full: nothing loads
		expect(countAt(ammo, 100)).toBe(3)
	end)

	it("throwing 2: they come back one after another", function()
		local ammo = Combat.newAmmo(Config)
		Combat.tryThrow(ammo, 0, Config)
		Combat.tryThrow(ammo, gap, Config)
		expect(ammo.count).toBe(1)
		local first = gap + delay + per
		expect(countAt(ammo, first - EPS)).toBe(1)
		expect(countAt(ammo, first)).toBe(2)
		expect(countAt(ammo, first + per - EPS)).toBe(2)
		expect(countAt(ammo, first + per)).toBe(3)
	end)

	it("throwing all 3: no throw while empty, then one by one, full a bit over 4 s after the last throw", function()
		local ammo = Combat.newAmmo(Config)
		for index = 0, 2 do
			expect(Combat.tryThrow(ammo, index * gap, Config)).toBe(true)
		end
		local last = 2 * gap
		expect(ammo.count).toBe(0)
		expect(Combat.tryThrow(ammo, last + gap, Config)).toBe(false) -- nothing loaded: no throw
		expect(ammo.count).toBe(0)
		local first = last + delay + per
		expect(countAt(ammo, first - EPS)).toBe(0)
		expect(countAt(ammo, first)).toBe(1)
		expect(countAt(ammo, first + per)).toBe(2)
		expect(countAt(ammo, first + 2 * per)).toBe(3)
		expect(first + 2 * per - last).toBeCloseTo(delay + 3 * per, 1e-9) -- 4.7 s
	end)

	it("a refresh long after catches up all at once, never past 3", function()
		local ammo = Combat.newAmmo(Config)
		for index = 0, 2 do
			Combat.tryThrow(ammo, index * gap, Config)
		end
		expect(countAt(ammo, 1000)).toBe(3)
		expect(ammo.reloadUntil).toBe(0)
	end)

	it("throwing while reloading: the half-loaded ball starts over after the wait, the loaded ones stay", function()
		local ammo = Combat.newAmmo(Config)
		Combat.tryThrow(ammo, 0, Config)
		Combat.tryThrow(ammo, gap, Config) -- 1 left
		local midway = gap + delay + per / 2 -- the next ball half loaded
		expect(Combat.tryThrow(ammo, midway, Config)).toBe(true)
		expect(ammo.count).toBe(0)
		expect(ammo.reloadUntil).toBeCloseTo(midway + delay + per, 1e-9)
		expect(countAt(ammo, midway + delay + per - EPS)).toBe(0)
		expect(countAt(ammo, midway + delay + per)).toBe(1)
	end)

	it("throwing a ball that just loaded: it was really there, and the reload waits again", function()
		local ammo = Combat.newAmmo(Config)
		for index = 0, 2 do
			Combat.tryThrow(ammo, index * gap, Config)
		end
		local loaded = 2 * gap + delay + per
		expect(Combat.tryThrow(ammo, loaded - EPS, Config)).toBe(false)
		expect(Combat.tryThrow(ammo, loaded, Config)).toBe(true)
		expect(ammo.count).toBe(0)
		expect(ammo.reloadUntil).toBeCloseTo(loaded + delay + per, 1e-9)
	end)

	it("every throw costs one, and the interval stops a whole load in one burst", function()
		local ammo = Combat.newAmmo(Config)
		expect(Combat.tryThrow(ammo, 10, Config)).toBe(true)
		expect(Combat.tryThrow(ammo, 10 + gap - EPS, Config)).toBe(false)
		expect(ammo.count).toBe(Config.ammo - 1)
	end)

	it("throwing on and on at the throw interval never gets more balls than were loaded", function()
		local ammo = Combat.newAmmo(Config)
		local thrown = 0
		for step = 0, 200 do
			if Combat.tryThrow(ammo, step * gap, Config) then
				thrown += 1
			end
		end
		-- 3 at the start; after that a refused throw changes nothing, so each further ball is thrown on the first
		-- try once it is loaded: delay + one ball after the throw before, on the throw-interval grid
		local every = math.ceil((delay + per) / gap)
		expect(thrown).toBe(Config.ammo + (200 - (Config.ammo - 1)) // every)
	end)
end)

describe("Ammo display", function()
	local per, delay = Config.reloadPerBall, Config.reloadDelay

	it("a full load shows 3 and no refill", function()
		local loaded, refill = Combat.ammoDisplay(3, 0, 5, Config)
		expect(loaded).toBe(3)
		expect(refill).toBe(0)
	end)

	it("the ball loading fills up, also with balls left; nothing during the wait after a throw", function()
		local ammo = Combat.newAmmo(Config)
		Combat.tryThrow(ammo, 0, Config)
		local loaded, refill = Combat.ammoDisplay(ammo.count, ammo.reloadUntil, delay / 2, Config)
		expect(loaded).toBe(2)
		expect(refill).toBe(0)
		_, refill = Combat.ammoDisplay(ammo.count, ammo.reloadUntil, delay + per / 2, Config)
		expect(refill).toBeCloseTo(0.5, 1e-9)
		-- the refill message arrives a moment after the ball is loaded: the circle stays full meanwhile
		_, refill = Combat.ammoDisplay(ammo.count, ammo.reloadUntil, delay + per + 0.03, Config)
		expect(refill).toBe(1)
	end)

	it("the second ball of a reload fills from 0 again", function()
		local ammo = Combat.newAmmo(Config)
		Combat.tryThrow(ammo, 0, Config)
		Combat.tryThrow(ammo, 1, Config)
		local first = 1 + delay + per
		Combat.refresh(ammo, first, Config)
		local loaded, refill = Combat.ammoDisplay(ammo.count, ammo.reloadUntil, first, Config)
		expect(loaded).toBe(2)
		expect(refill).toBeCloseTo(0, 1e-9)
		_, refill = Combat.ammoDisplay(ammo.count, ammo.reloadUntil, first + per / 4, Config)
		expect(refill).toBeCloseTo(0.25, 1e-9)
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
		_, refill = Combat.ammoDisplay(3, 50, 0, Config) -- full: whatever the time says, nothing loads
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

	it("grazes by power: a centred tap is a normal hit, a grazing tap and a weak graze are worth less", function()
		local Knock = Config.knock
		local _, centred, speed = firstHit(0, 1)
		local strong = Combat.hitPower(centred, speed, speed, 1, Config)
		expect(HitPoints.value(false, false, strong, Knock)).toBe(Knock.points.normal)
		local _, tapCentred, tapSpeed = firstHit(0, 0)
		local tap = Combat.hitPower(tapCentred, tapSpeed, tapSpeed, 0, Config)
		expect(HitPoints.value(false, false, tap, Knock)).toBe(Knock.points.normal)
		local _, tapOff = firstHit(2, 0)
		local grazingTap = Combat.hitPower(tapOff, tapSpeed, tapSpeed, 0, Config)
		expect(grazingTap < Knock.grazeBelow).toBe(true)
		expect(HitPoints.value(false, false, grazingTap, Knock)).toBe(Knock.points.graze)
		-- a full-strength ball passing the side is still a normal hit
		local _, off = firstHit(2, 1)
		expect(HitPoints.value(false, false, Combat.hitPower(off, speed, speed, 1, Config), Knock)).toBe(
			Knock.points.normal
		)
	end)
end)

describe("Knockdown animations", function()
	local reaction = Config.reactionAnimations

	it("the knockdown lasts as long as fall, lying still and the faster get-up together", function()
		local total = reaction.fallLength + reaction.fallHold + reaction.getUpLength / reaction.getUpSpeed
		expect(math.abs(Config.knockdownTime - total) < 0.01).toBe(true)
		expect(math.abs(Config.knockdownTime - 1.6) < 0.05).toBe(true)
	end)

	it("the get-up fades in over about a quarter second and out into idle at its end", function()
		expect(reaction.getUpFade).toBe(0.25)
		expect(reaction.getUpSpeed).toBe(1.25)
		expect(reaction.fallHold).toBe(0.2)
		expect(reaction.idleFade > 0 and reaction.idleFade < reaction.getUpLength / reaction.getUpSpeed).toBe(true)
	end)

	it("the hit plays over walking and aiming, the knockdown over everything", function()
		expect(reaction.hitPriority).toBe("Action2")
		expect(reaction.knockdownPriority).toBe("Action4")
	end)
end)

describe("Headshots", function()
	-- a victim 15 studs ahead, its HumanoidRootPart at y 5 and the R15 head 1.59 above it (Head part 1.2 big, measured
	-- on the R15 rig in Studio), facing
	-- the thrower at the origin (-Z); the tower column stands on the back (+Z) like CombatService builds it
	local ROOT = { x = 0, y = 5, z = 15 }
	local HEAD = { x = 0, y = 6.59, z = 15, radius = 0.6 }
	local function towerOf(scoops: number)
		return {
			x = ROOT.x,
			y = ROOT.y + Config.towerUp,
			z = ROOT.z + Config.towerBack,
			height = (scoops - 1) * Tuning.scoopSpacing,
			radius = Config.towerRadius,
		}
	end

	-- a perfect throw from (ox, oy, oz) at the point (tx, ty, tz), followed frame by frame like the server does;
	-- whether it is a headshot once it touches the body capsule, nil if it misses the body
	local function throwAt(ox, oy, oz, tx, ty, tz, tower, config): boolean?
		config = config or Config
		local speed = Combat.throwSpeed(1, true, config)
		local _, vx, vy, vz = Combat.aimVelocity(ox, oy, oz, tx, ty, tz, speed, config)
		local reach = config.hitRadius + config.ballRadius
		local last = 0
		for frame = 1, 120 do
			local t = frame / 60
			local ax, ay, az = Combat.position(ox, oy, oz, vx, vy, vz, config.gravity, last)
			local bx, by, bz = Combat.position(ox, oy, oz, vx, vy, vz, config.gravity, t)
			if
				Combat.closestToCapsule(ax, ay, az, bx, by, bz, ROOT.x, ROOT.y, ROOT.z, config.hitHalfHeight) <= reach
			then
				return Combat.isHeadshot(ox, oy, oz, vx, vy, vz, last, HEAD, tower, config)
			end
			last = t
		end
		return nil
	end

	it("a ball at the head is a headshot, one at the chest or the legs is not", function()
		expect(throwAt(0, 6.5, 0, HEAD.x, HEAD.y, HEAD.z)).toBe(true)
		expect(throwAt(0, 6.5, 0, ROOT.x, ROOT.y, ROOT.z)).toBe(false)
		expect(throwAt(0, 6.5, 0, ROOT.x, ROOT.y - 1.5, ROOT.z)).toBe(false)
	end)

	it("a ball at the neck grazes the chin with the ball but is a body hit: only the head counts", function()
		local neck = HEAD.y - HEAD.radius - 0.2
		-- within reach of the head zone, so without the head-height rule it would count
		expect(HEAD.y - neck <= HEAD.radius * Config.headZoneScale + Config.ballRadius).toBe(true)
		expect(throwAt(0, neck, 0, HEAD.x, neck, HEAD.z)).toBe(false)
		-- the bottom of the head itself is still the head
		local chin = HEAD.y - HEAD.radius + 0.05
		expect(throwAt(0, chin, 0, HEAD.x, chin, HEAD.z)).toBe(true)
	end)

	it("the head zone is a bit bigger than the head: headZoneScale decides a near miss", function()
		local reach = HEAD.radius * Config.headZoneScale + Config.ballRadius
		local plain = table.clone(Config)
		plain.headZoneScale = 1
		local plainReach = HEAD.radius + Config.ballRadius
		local between = (reach + plainReach) / 2
		expect(Config.headZoneScale > 1).toBe(true)
		expect(throwAt(0, 6.5, 0, between, HEAD.y, HEAD.z)).toBe(true)
		expect(throwAt(0, 6.5, 0, between, HEAD.y, HEAD.z, nil, plain)).toBe(false)
		expect(throwAt(0, 6.5, 0, reach + 0.3, HEAD.y, HEAD.z)).toBe(false)
	end)

	it("from behind the tower on the back takes the ball: a normal hit, unless there is no tower", function()
		expect(throwAt(0, 6.5, 30, HEAD.x, HEAD.y, HEAD.z, towerOf(5))).toBe(false)
		expect(throwAt(0, 6.5, 30, HEAD.x, HEAD.y, HEAD.z, nil)).toBe(true) -- no scoops: no column
		-- even a single scoop sits high enough on the back to cover the head from straight behind
		expect(throwAt(0, 6.5, 30, HEAD.x, HEAD.y, HEAD.z, towerOf(1))).toBe(false)
	end)

	it("the column is the stack of scoops: centre to centre, the scoop radius round", function()
		local tower = towerOf(3)
		expect(tower.height).toBeCloseTo(2 * Tuning.scoopSpacing, 1e-9)
		expect(towerOf(1).height).toBe(0)
		-- a ball from behind well above a 1-scoop tower and over the head reaches the head zone untouched
		local over = ROOT.y + Config.towerUp + Config.towerRadius + Config.ballRadius + 0.05
		expect(over < HEAD.y + HEAD.radius * Config.headZoneScale + Config.ballRadius).toBe(true)
		expect(throwAt(0, over, 30, HEAD.x, over, HEAD.z, towerOf(1))).toBe(true)
	end)

	it("from the front the tower does not shield the head", function()
		expect(throwAt(0, 6.5, 0, HEAD.x, HEAD.y, HEAD.z, towerOf(5))).toBe(true)
		expect(throwAt(0, 6.5, 0, HEAD.x, HEAD.y, HEAD.z, towerOf(20))).toBe(true)
	end)

	it("a throw from the side at the head is a headshot, the tower behind it does not matter", function()
		expect(throwAt(-15, 6.5, 15, HEAD.x, HEAD.y, HEAD.z, towerOf(5))).toBe(true)
	end)

	it("aim help draws to the chest, never the head: a throw at its point is no headshot", function()
		local point = ROOT.y + Config.aimAssist.aimHeight
		expect(point < HEAD.y - HEAD.radius * Config.headZoneScale).toBe(true)
		expect(throwAt(0, point, 0, ROOT.x, point, ROOT.z)).toBe(false)
		expect(throwAt(0, point, 40, ROOT.x, point, ROOT.z)).toBe(false)
	end)
end)

describe("Charge glow", function()
	local p = Config.perfect

	it("grows with the hold and turns perfect exactly in the perfect window, again and again", function()
		expect(Combat.chargeGlow(10, 10 + p.rise / 2, Config)).toBeCloseTo(0.5, 1e-9)
		local level, perfect = Combat.chargeGlow(10, 10 + p.rise, Config)
		expect(level).toBe(1)
		expect(perfect).toBe(true)
		_, perfect = Combat.chargeGlow(10, 10 + p.rise * 2, Config)
		expect(perfect).toBe(false)
		_, perfect = Combat.chargeGlow(10, 10 + p.rise * 3, Config)
		expect(perfect).toBe(true)
		-- the same moments the crosshair shows and the server accepts
		for _, held in { 0.1, p.rise - p.window / 2, p.rise + p.window / 2 + 0.01, 1.7 } do
			local _, glowPerfect = Combat.chargeGlow(0, held, Config)
			expect(glowPerfect).toBe(Combat.isPerfect(held, Config))
		end
	end)

	it("nothing while not charging, for odd values or a start in the future", function()
		for _, startedAt in { nil, "x", 0 / 0, math.huge, 20 } do
			local level, perfect = Combat.chargeGlow(startedAt, 10, Config)
			expect(level).toBe(0)
			expect(perfect).toBe(false)
		end
	end)
end)
