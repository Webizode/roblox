local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Luck = require("../src/shared/Luck")
local Config = require("../src/shared/Config/Luck")
local ChestConfig = require("../src/shared/Config/Chest")

describe("Luck from several sources", function()
	it("counts one source as it is, up to its cap", function()
		expect((Luck.total({ chest = 0.1 }, Config))).toBeCloseTo(0.1)
		local total, counted = Luck.total({ chest = 0.9 }, Config)
		expect(total).toBeCloseTo(Config.sources.chest.cap)
		expect(counted.chest).toBeCloseTo(Config.sources.chest.cap)
	end)

	it("adds the sources, each at its cap, the sum at the total cap", function()
		local total = Luck.total({ chest = 0.05, potion = 0.1 }, Config)
		expect(total).toBeCloseTo(0.15)
		local all = {}
		for name in Config.sources do
			all[name] = 10
		end
		expect((Luck.total(all, Config))).toBeCloseTo(Config.totalCap)
	end)

	it("counts nothing from an unknown source, a negative or broken value", function()
		local total, counted = Luck.total({ cheat = 1, chest = -0.5, potion = 0 / 0 }, Config)
		expect(total).toBe(0)
		expect(counted.cheat).toBe(0)
		expect(counted.chest).toBe(0)
		expect(counted.potion).toBe(0)
		expect((Luck.total({}, Config))).toBe(0)
	end)

	it("lets the chest's luck through whole: its source cap is not below the chest's own", function()
		expect(Config.sources.chest.cap >= ChestConfig.passives.kinds.luck.cap).toBe(true)
		expect(Config.totalCap >= Config.sources.chest.cap).toBe(true)
	end)
end)
