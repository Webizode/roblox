local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Dash = require("../src/shared/Dash")

describe("Dash", function()
	it("names the dash direction relative to the facing", function()
		-- facing -Z (Roblox's default look), so +X is the character's right
		expect(Dash.kind(0, -1, 0, -1)).toBe("forward")
		expect(Dash.kind(0, 1, 0, -1)).toBe("back")
		expect(Dash.kind(1, 0, 0, -1)).toBe("right")
		expect(Dash.kind(-1, 0, 0, -1)).toBe("left")
		-- facing +X: right is +Z
		expect(Dash.kind(0, 1, 1, 0)).toBe("right")
		-- diagonals lean to forward and back, like the model
		expect(Dash.kind(0.7, -0.7, 0, -1)).toBe("forward")
		expect(Dash.kind(0.6, -0.8, 0, -1)).toBe("forward")
		expect(Dash.kind(0.8, 0.6, 0, -1)).toBe("right")
	end)

	it("stops at walls facing the dash, not at floors, slopes or walls it only grazes", function()
		expect(Dash.blocks(0, 0, 1, 0, -1)).toBe(true) -- a wall straight ahead
		expect(Dash.blocks(0, 1, 0, 0, -1)).toBe(false) -- the floor
		expect(Dash.blocks(0, 0.7, 0.7, 0, -1)).toBe(false) -- a ramp
		expect(Dash.blocks(1, 0, 0, 0, -1)).toBe(false) -- a wall alongside
		expect(Dash.blocks(0.99, 0, 0.1, 0, -1)).toBe(false) -- grazed
		expect(Dash.blocks(0, 0, -1, 0, -1)).toBe(false) -- facing away (behind the character)
	end)

	it("plays the dash animation fast enough to end shortly after the dash", function()
		-- the 1 s animations, a 0.125 s dash and 0.1 s to straighten up: over after 0.225 s
		expect(math.abs(Dash.animationSpeed(1, 0.125, 0.1) - 1 / 0.225) < 1e-9).toBe(true)
		expect(Dash.animationSpeed(1, 0.2, 0.05)).toBe(4) -- the power dash
		expect(Dash.animationSpeed(0.5, 0.5, 0)).toBe(1)
		-- not loaded yet, or no time at all: normal speed rather than a division by zero
		expect(Dash.animationSpeed(0, 0.125, 0.1)).toBe(1)
		expect(Dash.animationSpeed(1, 0, 0)).toBe(1)
	end)
end)
