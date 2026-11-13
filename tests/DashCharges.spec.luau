local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local DashCharges = require("../src/shared/DashCharges")
local Tuning = require("../src/shared/Config/Tower")

local config = Tuning.dash

describe("DashCharges: a dash with stored charges", function()
	it("starts full: two dashes right after each other, the minimum gap apart, then a wait", function()
		local state = DashCharges.new(config)
		expect(DashCharges.tryUse(state, 10, config)).toBe(true)
		-- too soon for the second
		expect(DashCharges.tryUse(state, 10 + config.minGap / 2, config)).toBe(false)
		expect(DashCharges.tryUse(state, 10 + config.minGap, config)).toBe(true)
		-- both used: nothing until the first one is back
		expect(DashCharges.tryUse(state, 10 + config.minGap * 2, config)).toBe(false)
		expect(DashCharges.tryUse(state, 10 + config.recharge - 0.01, config)).toBe(false)
		expect(DashCharges.tryUse(state, 10 + config.recharge, config)).toBe(true)
	end)

	it("recharges one charge after the other, each in `recharge` seconds", function()
		local state = DashCharges.new(config)
		DashCharges.tryUse(state, 0, config)
		DashCharges.tryUse(state, config.minGap, config)
		DashCharges.refresh(state, config.recharge, config)
		expect(state.charges).toBe(1)
		DashCharges.refresh(state, config.recharge * 2 - 0.01, config)
		expect(state.charges).toBe(1)
		DashCharges.refresh(state, config.recharge * 2, config)
		expect(state.charges).toBe(config.charges)
		-- and it stays full
		DashCharges.refresh(state, 100, config)
		expect(state.charges).toBe(config.charges)
	end)

	it("a dash while one charge is still loading keeps that one loading", function()
		local state = DashCharges.new(config)
		DashCharges.tryUse(state, 0, config) -- 1 left, the other back at `recharge`
		expect(DashCharges.tryUse(state, 1, config)).toBe(true) -- 0 left
		DashCharges.refresh(state, config.recharge, config)
		expect(state.charges).toBe(1) -- the first came back on time, not later
	end)

	it("the bar: full segments for ready charges, the loading one filling up", function()
		local state = DashCharges.new(config)
		local fills = DashCharges.segments(state, 0, config)
		expect(#fills).toBe(config.charges)
		expect(fills[1]).toBe(1)
		expect(fills[2]).toBe(1)
		DashCharges.tryUse(state, 0, config)
		fills = DashCharges.segments(state, config.recharge / 2, config)
		expect(fills[1]).toBe(1)
		expect(math.abs(fills[2] - 0.5) < 1e-6).toBe(true)
		DashCharges.tryUse(state, config.recharge / 2, config)
		fills = DashCharges.segments(state, config.recharge / 2, config)
		expect(math.abs(fills[1] - 0.5) < 1e-6).toBe(true)
		expect(fills[2]).toBe(0)
	end)

	it("the server's slack lets a request a little early through", function()
		local state = DashCharges.new(config)
		DashCharges.tryUse(state, 0, config)
		DashCharges.tryUse(state, config.minGap, config)
		expect(DashCharges.tryUse(state, config.recharge - 0.1, config, 0.2)).toBe(true)
	end)

	it("starting values: two charges, faster than the old single 4 s cooldown", function()
		expect(config.charges).toBe(2)
		expect(config.recharge < 4).toBe(true)
		expect(config.minGap > 0 and config.minGap < 1).toBe(true)
	end)
end)
