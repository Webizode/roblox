local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Combat = require("../src/shared/Combat")
local Config = require("../src/shared/Config/Combat")
local TowerModel = require("../src/shared/TowerModel")
local Flavors = require("../src/shared/Config/Flavors")
local Tuning = require("../src/shared/Config/Tower")

local DT = 1 / 60

describe("Ice-ball flight and hits", function()
	it("flies through the aim point at every charge, from the hand, within its flight time", function()
		for _, charge in { 0, 0.5, 1 } do
			local speed = Combat.throwSpeed(charge, Config)
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
		local weak, strong = Combat.throwSpeed(0, Config), Combat.throwSpeed(1, Config)
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

describe("Charging a throw", function()
	it("runs the bar up to its maximum, back down to its minimum, and again", function()
		local rise = Config.chargeRise
		expect(Combat.charge(0, Config)).toBe(0)
		expect(Combat.charge(rise / 2, Config)).toBeCloseTo(0.5, 1e-9)
		expect(Combat.charge(rise, Config)).toBeCloseTo(1, 1e-9)
		expect(Combat.charge(rise * 1.5, Config)).toBeCloseTo(0.5, 1e-9)
		expect(Combat.charge(rise * 2, Config)).toBeCloseTo(0, 1e-9)
		expect(Combat.charge(rise * 3, Config)).toBeCloseTo(1, 1e-9)
		expect(Combat.charge(-1, Config)).toBe(0)
		expect(Combat.charge(0 / 0, Config)).toBe(0)
		for held = 0, 10, 0.037 do
			local value = Combat.charge(held, Config)
			expect(value >= 0 and value <= 1).toBe(true)
		end
	end)

	it("accepts an honest bar within the network jitter", function()
		local rise, tolerance = Config.chargeRise, Config.chargeTolerance
		for held = 0, 4, 0.05 do
			for _, jitter in { -tolerance, -tolerance / 2, 0, tolerance / 2, tolerance } do
				local clientHeld = math.max(0, held + jitter)
				local bar = Combat.charge(clientHeld, Config)
				expect(Combat.validateCharge(bar, held, Config)).toBeCloseTo(bar, 1e-9)
			end
		end
		-- releasing right at the top: the full bar counts even if the server measured a little past the peak
		expect(Combat.validateCharge(1, rise + tolerance * 0.9, Config)).toBe(1)
	end)

	it("never gives more than the measured hold allows", function()
		local rise, tolerance = Config.chargeRise, Config.chargeTolerance
		-- a tap claiming a full bar
		local tap = Combat.validateCharge(1, 0.05, Config)
		expect(tap).toBeCloseTo(Combat.charge(0.05 + tolerance, Config), 1e-9)
		expect(tap).toBeLessThan(0.25)
		-- no hold at all (the start message never came): the weakest throw plus the jitter allowance
		expect(Combat.validateCharge(1, 0, Config)).toBeCloseTo(tolerance / rise, 1e-9)
		-- held to the bottom of the second swing, claiming the top
		expect(Combat.validateCharge(1, 2 * rise, Config)).toBeCloseTo(tolerance / rise, 1e-9)
		-- out of range and broken claims
		expect(Combat.validateCharge(5, rise, Config)).toBe(1)
		expect(Combat.validateCharge(-3, 2 * rise, Config)).toBe(0)
		expect(Combat.validateCharge(0 / 0, rise / 2, Config)).toBeCloseTo(0.5, 1e-9)
		expect(Combat.validateCharge(1, 0 / 0, Config)).toBeCloseTo(tolerance / rise, 1e-9)
	end)

	it("needs charged throws for a knockdown: weak hits in a row never knock down, two strong ones do", function()
		local weak = Combat.hitPower(0, Config.minSpeed, Config.minSpeed, 0, Config)
		local stagger, lastHitAt, down = 0, 0, false
		for index = 0, Config.ammo - 1 do
			local time = index * Config.throwInterval
			stagger, down = Combat.addHit(stagger, lastHitAt, time, weak, Config)
			lastHitAt = time
			expect(down).toBe(false)
		end
		local strong = Combat.hitPower(0, Config.maxSpeed, Config.maxSpeed, 1, Config)
		stagger = Combat.addHit(0, 0, 0, strong, Config)
		local _, knocked = Combat.addHit(stagger, 0, 0.6, strong, Config)
		expect(knocked).toBe(true)
	end)
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

	it("one full hit on an upright tower of up to 10 scoops is absorbed by the stabiliser", function()
		for count = 1, 10 do
			local state = TowerModel.newState(count)
			TowerModel.hitKick(state, Config, count, 1, 0, 1)
			expect(runWithAssist(state, count, 6)).toBe(false)
		end
	end)

	it("a hit on a tall tower forces a reaction: without a rescue it falls, with one it holds", function()
		local function hit(count: number, lean: number, power: number, rescue: boolean)
			local state = TowerModel.newState(2)
			state.x = lean * Tuning.tipAngle
			state.seenX = state.x
			TowerModel.hitKick(state, Config, count, 1, 0, power)
			if rescue then
				TowerModel.rescue(state, Tuning.rescue.duration)
			end
			return runWithAssist(state, count, 6)
		end
		expect(hit(12, 0.3, 1, false)).toBe(true)
		expect(hit(12, 0.3, 1, true)).toBe(false)
		expect(hit(16, 0, 1, false)).toBe(true)
		expect(hit(16, 0, 1, true)).toBe(false)
		-- the limit: a knockdown hit on a tall tower already leaning the same way is lost even with a rescue
		expect(hit(16, 0.5, Config.knockdownBoost, true)).toBe(true)
	end)
end)
