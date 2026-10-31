local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local MouseRules = require("../src/shared/MouseRules")

describe("Mouse in combat mode", function()
	it("in the arena in combat mode it stays locked and hidden, even with the right mouse button held", function()
		expect(MouseRules.mode(true, true, true, false)).toBe("locked")
		expect(MouseRules.mode(true, true, true, true)).toBe("locked")
	end)

	it("outside combat mode it is free, in the arena and outside", function()
		for _, inArena in { true, false } do
			for _, right in { true, false } do
				expect(MouseRules.mode(false, inArena, true, right)).toBe("free")
			end
		end
	end)

	it("outside the arena it is free, so the teleport buttons can be clicked", function()
		expect(MouseRules.mode(true, false, true, false)).toBe("free")
		expect(MouseRules.mode(true, false, true, true)).toBe("free")
	end)

	it("without a mouse (touch, gamepad) there is nothing to lock", function()
		expect(MouseRules.mode(true, true, false, false)).toBe("free")
	end)
end)

describe("Combat mode and the arena", function()
	it("R switches combat mode on in the arena only", function()
		expect(MouseRules.canEnterCombat(true)).toBe(true)
		expect(MouseRules.canEnterCombat(false)).toBe(false)
	end)

	it("leaving the arena ends combat mode; outside it nothing is left to end", function()
		expect(MouseRules.mustLeaveCombat(true, false)).toBe(true)
		expect(MouseRules.mustLeaveCombat(true, true)).toBe(false)
		expect(MouseRules.mustLeaveCombat(false, false)).toBe(false)
		expect(MouseRules.mustLeaveCombat(false, true)).toBe(false)
	end)
end)
