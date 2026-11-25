local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Progression = require("../scripts/lib/Progression")
local UpgradesConfig = require("../src/shared/Config/Upgrades")

-- The progression goals (25.11.2026, vault: Progression und Liegezeit 2026-11-25) for the typical player of the
-- simulation (scripts/lib/Progression.luau with Progression.PLAY). A price change that breaks them fails here; rerun
-- `lune run scripts/progression` to see the whole table.
describe("Progression: the upgrade prices meet the goals", function()
	local result = Progression.median(UpgradesConfig, 52, 5, nil, 60)

	-- about 3 minutes until 25.11.2026; since then a new flavor goes into the chest by default (Auto Sell "new flavors:
	-- store", decided 25.11.2026), so a new player's first towers pay less: about 6 minutes
	it("the first upgrade after the first serves, about 6 minutes in", function()
		expect(result.firstUpgrade ~= nil and result.firstUpgrade <= 7).toBe(true)
	end)

	it("every upgrade at about level 5 after 1 hour", function()
		local at = result.reached[5] or math.huge
		expect(at >= 40 and at <= 80).toBe(true) -- about 44 minutes since the new flavors are stored (58 before)
	end)

	it("half the levels after about 10 hours", function()
		local at = result.reached[13] or math.huge
		expect(at >= 7 * 60 and at <= 14 * 60).toBe(true)
	end)

	it("everything at the top after 30 to 50 hours", function()
		local at = result.allMax or math.huge
		expect(at >= 30 * 60 and at <= 50 * 60).toBe(true)
	end)
end)

describe("Progression: the level cap per rebirth is prepared but off", function()
	it("is off until the rebirth exists", function()
		expect(UpgradesConfig.levelCap.enabled).toBe(false)
		expect(UpgradesConfig.levelCap.base).toBe(10)
		expect(UpgradesConfig.levelCap.perRebirth).toBe(5)
	end)
end)
