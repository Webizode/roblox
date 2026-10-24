local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Stance = require("../src/shared/Stance")
local Tuning = require("../src/shared/Config/Tower")

local Config = Tuning.stance
local DT = 1 / 60

local function run(meter, seconds: number): boolean
	local ranOut = false
	for _ = 1, math.floor(seconds / DT + 0.5) do
		ranOut = Stance.advance(meter, DT, Config) or ranOut
	end
	return ranOut
end

describe("Steady stance energy bar", function()
	it("starts full, and a full bar lasts holdSeconds before the stance stops by itself", function()
		local meter = Stance.new()
		expect(meter.energy).toBe(1)
		expect(Stance.start(meter, Config)).toBe(true)
		expect(run(meter, Config.holdSeconds - 0.1)).toBe(false)
		expect(meter.active).toBe(true)
		expect(run(meter, 0.2)).toBe(true)
		expect(meter.active).toBe(false)
		expect(meter.energy).toBe(0)
	end)

	it("refills only after the delay, from empty to full in refillSeconds", function()
		local meter = Stance.new()
		meter.energy = 0
		Stance.start(meter, Config, 1)
		Stance.stop(meter)
		run(meter, Config.refillDelay)
		expect(meter.energy).toBeCloseTo(0, 1e-9)
		run(meter, Config.refillSeconds / 2)
		expect(meter.energy).toBeCloseTo(0.5, 0.01)
		run(meter, Config.refillSeconds)
		expect(meter.energy).toBe(1)
	end)

	it("a nearly empty bar cannot be tapped back on, a refilled one can", function()
		local meter = Stance.new()
		Stance.start(meter, Config)
		run(meter, Config.holdSeconds + 0.1)
		expect(Stance.start(meter, Config)).toBe(false)
		run(meter, Config.refillDelay + Config.refillSeconds * Config.minStart + 0.05)
		expect(Stance.start(meter, Config)).toBe(true)
	end)

	it("letting go early keeps what is left, and the bar does not refill while held", function()
		local meter = Stance.new()
		Stance.start(meter, Config)
		run(meter, Config.holdSeconds / 2)
		Stance.stop(meter)
		expect(meter.energy).toBeCloseTo(0.5, 0.01)
		Stance.start(meter, Config)
		local before = meter.energy
		run(meter, 0.5)
		expect(meter.energy).toBeLessThan(before)
	end)

	it("the server's slack only shaves off a little, it never allows a stance on an empty bar", function()
		local meter = Stance.new()
		meter.energy = Config.minStart - 0.05
		expect(Stance.canStart(meter, Config)).toBe(false)
		expect(Stance.canStart(meter, Config, 0.1)).toBe(true)
		meter.energy = 0
		expect(Stance.canStart(meter, Config, 0.1)).toBe(false)
	end)

	it("a throw or a dash ends the stance and locks it for the lockout, then F works again", function()
		local meter = Stance.new()
		Stance.start(meter, Config)
		expect(Stance.interrupt(meter, Config, Config.lockRecent)).toBe(true)
		expect(meter.active).toBe(false)
		run(meter, Config.lockout - 0.1)
		expect(Stance.start(meter, Config)).toBe(false)
		run(meter, 0.15)
		expect(Stance.start(meter, Config)).toBe(true)
	end)

	it("letting go of F locks nothing, and a throw or dash long after the stance locks nothing either", function()
		local meter = Stance.new()
		Stance.start(meter, Config)
		run(meter, 0.5)
		Stance.stop(meter)
		expect(Stance.start(meter, Config)).toBe(true)
		Stance.stop(meter)
		run(meter, Config.lockRecent + 0.1)
		expect(Stance.interrupt(meter, Config, Config.lockRecent)).toBe(false)
		expect(Stance.start(meter, Config)).toBe(true)
		-- a fresh bar has never been held, so an early throw or dash finds nothing to lock
		local fresh = Stance.new()
		expect(Stance.interrupt(fresh, Config, Config.lockRecent)).toBe(false)
		run(fresh, 0.5)
		expect(fresh.energy).toBe(1)
	end)

	it("a stance released just before the throw or dash is locked too, whatever the order", function()
		local meter = Stance.new()
		Stance.start(meter, Config)
		Stance.stop(meter)
		run(meter, Config.lockRecent / 2)
		expect(Stance.interrupt(meter, Config, Config.lockRecent)).toBe(true)
		expect(Stance.canStart(meter, Config)).toBe(false)
	end)

	it("the server's lockout slack only shaves off a little of the lockout", function()
		local meter = Stance.new()
		Stance.start(meter, Config)
		Stance.interrupt(meter, Config)
		run(meter, Config.lockout - 0.2)
		expect(Stance.canStart(meter, Config)).toBe(false)
		expect(Stance.canStart(meter, Config, 0.1, 0.3)).toBe(true)
		expect(Stance.canStart(Stance.new(), Config, 0, 0)).toBe(true)
	end)

	it("hits in the stance drain the bar, a full hit stanceDrain of it, and an emptied bar ends the stance", function()
		local CombatConfig = require("../src/shared/Config/Combat")
		local meter = Stance.new()
		Stance.start(meter, Config)
		expect(Stance.drain(meter, 1 * CombatConfig.stanceDrain)).toBe(false)
		expect(meter.energy).toBeCloseTo(1 - CombatConfig.stanceDrain, 1e-9)
		meter.energy = 0.1
		expect(Stance.drain(meter, 0.5 * CombatConfig.stanceDrain)).toBe(true)
		expect(meter.active).toBe(false)
		expect(meter.energy).toBe(0)
		-- outside the stance a hit costs nothing
		local idle = Stance.new()
		expect(Stance.drain(idle, CombatConfig.stanceDrain)).toBe(false)
		expect(idle.energy).toBe(1)
	end)

	it("cannot run without any cost: holding it in a loop averages well under half the time", function()
		-- a player who holds whenever the bar allows it: on as soon as it may start, until it runs out
		local meter = Stance.new()
		local held = 0
		for _ = 1, 60 / DT do
			Stance.start(meter, Config)
			if meter.active then
				held += DT
			end
			Stance.advance(meter, DT, Config)
		end
		expect(held / 60).toBeLessThan(0.45)
	end)
end)
