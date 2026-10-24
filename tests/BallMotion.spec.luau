local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local BallMotion = require("../src/shared/BallMotion")
local Config = require("../src/shared/Config/Combat")

local Model = Config.ballModel

describe("Ball motion", function()
	it("floats up and down once per period and loops seamlessly", function()
		local start = BallMotion.idle(0, Config)
		expect(start.lift).toBeCloseTo(0, 1e-9)
		expect(start.yaw).toBeCloseTo(0, 1e-9)
		local top = BallMotion.idle(Model.idle.period / 4, Config)
		expect(top.lift).toBeCloseTo(Model.idle.bob, 1e-9)
		expect(top.yaw).toBeCloseTo(math.rad(Model.idle.yaw), 1e-9)
		expect(top.roll).toBeCloseTo(math.rad(Model.idle.roll), 1e-9)
		local loop = BallMotion.idle(Model.idle.period, Config)
		expect(loop.lift).toBeCloseTo(start.lift, 1e-9)
		expect(loop.pitch).toBeCloseTo(start.pitch, 1e-9)
		expect(loop.yaw).toBeCloseTo(start.yaw, 1e-9)
		expect(loop.roll).toBeCloseTo(start.roll, 1e-9)
		for t = 0, Model.idle.period, 0.01 do
			local idle = BallMotion.idle(t, Config)
			expect(math.abs(idle.lift) <= Model.idle.bob + 1e-9).toBe(true)
			expect(math.abs(idle.pitch) <= math.rad(Model.idle.pitch) + 1e-9).toBe(true)
		end
	end)

	it("hops first, back on its path at bounceEnd, and never dips below it", function()
		local flight = Model.flight
		expect((BallMotion.flight(0, Config))).toBeCloseTo(0, 1e-9)
		expect((BallMotion.flight(flight.bounceRise, Config))).toBeCloseTo(flight.bounce, 1e-9)
		local lift, spin = BallMotion.flight(flight.bounceEnd, Config)
		expect(lift).toBeCloseTo(0, 1e-9)
		expect(spin).toBeCloseTo(0, 1e-9)
		for t = 0, 1.5, 0.005 do
			local l = BallMotion.flight(t, Config)
			expect(l >= 0 and l <= flight.bounce + 1e-9).toBe(true)
		end
		-- no spin during the hop
		local _, early = BallMotion.flight(flight.bounceEnd / 2, Config)
		expect(early).toBe(0)
	end)

	it("spins evenly at turnsPerSecond once the hop is over", function()
		local flight = Model.flight
		local _, oneSecond = BallMotion.flight(flight.bounceEnd + 1, Config)
		expect(oneSecond).toBeCloseTo(2 * math.pi * flight.turnsPerSecond, 1e-9)
		local _, a = BallMotion.flight(flight.bounceEnd + 0.2, Config)
		local _, b = BallMotion.flight(flight.bounceEnd + 0.4, Config)
		local _, c = BallMotion.flight(flight.bounceEnd + 0.6, Config)
		expect(b - a).toBeCloseTo(c - b, 1e-9)
		expect(b - a).toBeGreaterThan(0)
	end)

	it("turns the next ball once, softly in and out", function()
		local duration = Model.nextThrow.duration
		local start, running = BallMotion.nextThrow(0, Config)
		expect(start).toBeCloseTo(0, 1e-9)
		expect(running).toBe(true)
		expect((BallMotion.nextThrow(duration / 2, Config))).toBeCloseTo(math.pi, 1e-9)
		local done, still = BallMotion.nextThrow(duration, Config)
		expect(done).toBeCloseTo(2 * math.pi, 1e-9)
		expect(still).toBe(false)
		expect((BallMotion.nextThrow(-math.huge, Config))).toBeCloseTo(0, 1e-9)
		expect((BallMotion.nextThrow(math.huge, Config))).toBeCloseTo(2 * math.pi, 1e-9)
		-- slow at the start, fastest in the middle
		local first = BallMotion.nextThrow(duration * 0.1, Config)
		local middle = BallMotion.nextThrow(duration * 0.55, Config) - BallMotion.nextThrow(duration * 0.45, Config)
		expect(first).toBeLessThan(middle)
		local last = -1
		for t = 0, duration, duration / 50 do
			local angle = BallMotion.nextThrow(t, Config)
			expect(angle >= last - 1e-9).toBe(true)
			last = angle
		end
	end)
end)
