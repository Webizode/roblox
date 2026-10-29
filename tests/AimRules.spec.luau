local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local AimRules = require("../src/shared/AimRules")
local Config = require("../src/shared/Config/Combat")

local function spread(fields: { [string]: any }?): AimRules.Spread
	local base = { moving = false, sprinting = false, sinceDash = math.huge, sinceThrow = math.huge, strength = nil }
	for key, value in fields or {} do
		(base :: any)[key] = value
	end
	return base :: any
end

describe("Crosshair: its size", function()
	local calm = AimRules.radius(spread(), Config)

	it("is the base size when standing and not throwing", function()
		expect(calm).toBe(Config.crosshair.radius)
	end)

	it("grows while moving, more while sprinting, right after a dash and right after a throw", function()
		local moving = AimRules.radius(spread({ moving = true }), Config)
		local sprinting = AimRules.radius(spread({ moving = true, sprinting = true }), Config)
		expect(moving).toBeGreaterThan(calm)
		expect(sprinting).toBeGreaterThan(moving)
		expect(AimRules.radius(spread({ sinceDash = 0 }), Config)).toBeGreaterThan(calm)
		expect(AimRules.radius(spread({ sinceThrow = 0 }), Config)).toBeGreaterThan(calm)
	end)

	it("the dash and the throw wear off", function()
		expect(AimRules.radius(spread({ sinceDash = Config.crosshair.dashTime }), Config)).toBe(calm)
		expect(AimRules.radius(spread({ sinceThrow = Config.crosshair.throwTime }), Config)).toBe(calm)
		local early = AimRules.radius(spread({ sinceDash = 0.1 }), Config)
		local late = AimRules.radius(spread({ sinceDash = 0.3 }), Config)
		expect(late).toBeLessThan(early)
	end)

	it("pulls in while a throw is held, the more the stronger", function()
		local tap = AimRules.radius(spread({ strength = 0 }), Config)
		local half = AimRules.radius(spread({ strength = 0.5 }), Config)
		local full = AimRules.radius(spread({ strength = 1 }), Config)
		expect(tap).toBe(calm)
		expect(half).toBeLessThan(tap)
		expect(full).toBeLessThan(half)
		expect(full).toBeCloseTo(calm * (1 - Config.crosshair.holdShrink), 1e-9)
	end)

	it("eases towards its size without jumping and gets there", function()
		local r = 30
		for _ = 1, 120 do
			local nextR = AimRules.ease(r, 14, 1 / 60, Config)
			expect(nextR <= r and nextR >= 14).toBe(true)
			r = nextR
		end
		expect(r).toBeCloseTo(14, 0.01)
	end)
end)

describe("Aim help in the combat camera", function()
	local a = Config.aimAssist
	local function rival(angle: number, fields: { [string]: any }?): AimRules.Candidate
		local c = { angle = angle, distance = 30, visible = true, shielded = false }
		for key, value in fields or {} do
			(c :: any)[key] = value
		end
		return c :: any
	end

	it("mouse hardly, controller more, touch the most, by the input in use", function()
		local mouse = AimRules.device("keyboard", Config)
		local pad = AimRules.device("gamepad", Config)
		local touch = AimRules.device("touch", Config)
		expect(mouse.friction < pad.friction and pad.friction < touch.friction).toBe(true)
		expect(mouse.pull < pad.pull and pad.pull < touch.pull).toBe(true)
		expect(mouse.friction <= 0.2).toBe(true) -- hardly felt with a mouse
		expect(AimRules.device("something new", Config)).toBe(mouse) -- unknown: the lightest
	end)

	it("works on the rival closest to the crosshair, only in front of it and in reach", function()
		expect(AimRules.pick({ rival(5), rival(2), rival(6) }, Config)).toBe(2)
		expect(AimRules.pick({ rival(a.maxAngle + 1) }, Config)).toBeNil() -- beside the crosshair
		expect(AimRules.pick({ rival(170) }, Config)).toBeNil() -- behind the player: never
		expect(AimRules.pick({ rival(1, { distance = a.maxRange + 1 }) }, Config)).toBeNil()
		expect(AimRules.pick({}, Config)).toBeNil()
	end)

	it("never through a wall and never on somebody in their safe zone", function()
		expect(AimRules.pick({ rival(1, { visible = false }) }, Config)).toBeNil()
		expect(AimRules.pick({ rival(1, { shielded = true }) }, Config)).toBeNil()
		-- a hidden one closer to the crosshair does not hide a visible one a little further off
		expect(AimRules.pick({ rival(1, { visible = false }), rival(4) }, Config)).toBe(2)
	end)

	it("slows the turning near a rival, strongest right on them, gone at maxAngle", function()
		local touch = AimRules.device("touch", Config)
		expect(AimRules.friction(0, touch)).toBe(1) -- no rival: the turn as it is
		expect(AimRules.friction(AimRules.closeness(0, Config), touch)).toBeCloseTo(1 - touch.friction, 1e-9)
		expect(AimRules.closeness(a.maxAngle, Config)).toBe(0)
		expect(AimRules.closeness(a.maxAngle / 2, Config)).toBeCloseTo(0.5, 1e-9)
		expect(AimRules.closeness(0 / 0, Config)).toBe(0)
	end)

	it("draws the camera gently: never the whole way in a frame, nothing far off the crosshair", function()
		for _, kind in { "keyboard", "gamepad", "touch" } do
			local device = AimRules.device(kind, Config)
			local share = AimRules.pull(1, 1 / 60, device)
			expect(share > 0 and share < 0.1).toBe(true) -- no snapping
			expect(AimRules.pull(0, 1 / 60, device)).toBe(0)
		end
		-- the mouse's pull is a fraction of the touch one
		local mouse = AimRules.pull(1, 1 / 60, AimRules.device("keyboard", Config))
		local touch = AimRules.pull(1, 1 / 60, AimRules.device("touch", Config))
		expect(mouse < touch / 3).toBe(true)
	end)
end)

describe("Hit feedback: who toppled the tower", function()
	it("a topple counts as the thrower's shortly after their hit, not later", function()
		local window = Config.feedback.creditSeconds
		expect(AimRules.credited(10, 10.5, Config)).toBe(true)
		expect(AimRules.credited(10, 10 + window, Config)).toBe(true)
		expect(AimRules.credited(10, 10 + window + 0.01, Config)).toBe(false)
		expect(AimRules.credited(nil, 10, Config)).toBe(false)
		expect(AimRules.credited(12, 10, Config)).toBe(false)
	end)
end)
