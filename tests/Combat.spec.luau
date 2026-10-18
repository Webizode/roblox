local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Combat = require("../src/shared/Combat")
local Config = require("../src/shared/Config/Combat")
local TowerModel = require("../src/shared/TowerModel")
local Flavors = require("../src/shared/Config/Flavors")
local Tuning = require("../src/shared/Config/Tower")

local DT = 1 / 60

describe("Ice-ball flight and hits", function()
	it("launches along the aim with a little lift and falls under gravity", function()
		local ok, vx, vy, vz = Combat.launchVelocity(0, 0, 1, Config)
		expect(ok).toBe(true)
		expect(vz).toBeGreaterThan(0)
		expect(vy).toBeGreaterThan(0)
		expect(math.sqrt(vx * vx + vy * vy + vz * vz)).toBeCloseTo(Config.speed, 1e-6)
		local _, y1 = Combat.position(0, 0, 0, vx, vy, vz, Config.gravity, 0.1)
		local _, y2 = Combat.position(0, 0, 0, vx, vy, vz, Config.gravity, Config.maxFlight)
		expect(y1).toBeGreaterThan(0)
		expect(y2).toBeLessThan(y1)
	end)

	it("rejects aims a camera cannot produce", function()
		expect((Combat.launchVelocity(0 / 0, 0, 1, Config))).toBe(false)
		expect((Combat.launchVelocity(math.huge, 0, 0, Config))).toBe(false)
		expect((Combat.launchVelocity(0, 0, 50, Config))).toBe(false)
		expect((Combat.launchVelocity(0, 0, 0, Config))).toBe(false)
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

	it("makes centred, fast hits stronger than grazing or slow ones, all within [0, 1]", function()
		local full = Combat.hitPower(0, Config.speed, Config)
		local graze = Combat.hitPower(Config.hitRadius, Config.speed, Config)
		local slow = Combat.hitPower(0, Config.speed * 0.5, Config)
		expect(full).toBeCloseTo(1, 1e-6)
		expect(graze).toBeLessThan(full)
		expect(slow).toBeLessThan(full)
		expect(graze).toBeGreaterThan(0)
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

	it("two grazing hits do not knock down", function()
		local power = Combat.hitPower(Config.hitRadius + Config.ballRadius * 0.9, Config.speed * 0.7, Config)
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
