local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local HealthPips = require("../src/shared/HealthPips")
local HitPoints = require("../src/shared/HitPoints")
local CombatConfig = require("../src/shared/Config/Combat")

local Knock = CombatConfig.knock
local Bar = CombatConfig.healthBar
local SEGMENTS = HealthPips.segments(Knock)

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

-- the share left after hits of `kinds` (headshot, perfect, power), close together but outside the multi window
local function after(kinds: { { boolean | number } }): number
	local state = HitPoints.new()
	for index, kind in kinds do
		local value = HitPoints.value(kind[1] :: boolean, kind[2] :: boolean, kind[3] :: number, Knock)
		local time = index * 0.5
		HitPoints.add(state, time, value, time + CombatConfig.knockdownTime, Knock)
	end
	return HealthPips.left(state.points, Knock)
end

describe("HealthPips segments", function()
	it("has one segment per normal hit up to the knockdown", function()
		expect(SEGMENTS).toBe(3)
		expect(HealthPips.segments({ points = { normal = 2 }, knockdownAt = 7, resetAfter = 6 })).toBe(4)
	end)

	it("empties one segment per normal hit, one and a half per perfect or headshot, half per graze", function()
		local normal = { false, false, 1 }
		local perfect = { false, true, 1 }
		local headshot = { true, false, 1 }
		local graze = { false, false, Knock.grazeBelow - 0.01 }
		expect(near(after({ normal }) * SEGMENTS, 2)).toBe(true)
		expect(near(after({ normal, normal }) * SEGMENTS, 1)).toBe(true)
		expect(near(after({ perfect }) * SEGMENTS, 1.5)).toBe(true)
		expect(near(after({ headshot }) * SEGMENTS, 1.5)).toBe(true)
		expect(near(after({ graze }) * SEGMENTS, 2.5)).toBe(true)
	end)

	it("fills segments from the left, partly where the share ends", function()
		local fills = HealthPips.fills(0.5, 3)
		expect(fills[1]).toBe(1)
		expect(near(fills[2], 0.5)).toBe(true)
		expect(fills[3]).toBe(0)
		local full = HealthPips.fills(1, 3)
		expect(full[3]).toBe(1)
		expect(HealthPips.fills(0, 3)[1]).toBe(0)
	end)

	it("clamps odd values", function()
		expect(HealthPips.left(0 / 0, Knock)).toBe(1)
		expect(HealthPips.left(99, Knock)).toBe(0)
		expect(HealthPips.left(-3, Knock)).toBe(1)
	end)
end)

describe("HealthPips tone", function()
	it("is green when full or after one normal hit, yellow at half, red one hit from the knockdown", function()
		expect(HealthPips.tone(1, false, false, Bar)).toBe("full")
		expect(HealthPips.tone(4 / 6, false, false, Bar)).toBe("full")
		expect(HealthPips.tone(3 / 6, false, false, Bar)).toBe("mid")
		expect(HealthPips.tone(2 / 6, false, false, Bar)).toBe("low")
		expect(HealthPips.tone(1 / 6, false, false, Bar)).toBe("low")
	end)

	it("is grey while down and blue while protected", function()
		expect(HealthPips.tone(1, true, true, Bar)).toBe("down")
		expect(HealthPips.tone(1, false, true, Bar)).toBe("protected")
	end)
end)

describe("HealthPips approach", function()
	it("drops at once and refills over `refill` seconds", function()
		expect(HealthPips.approach(1, 0.5, 0.016, Bar.refill)).toBe(0.5)
		local shown = 0
		local steps = 0
		while shown < 1 do
			shown = HealthPips.approach(shown, 1, 0.01, Bar.refill)
			steps += 1
		end
		expect(math.abs(steps * 0.01 - Bar.refill) < 0.02).toBe(true)
	end)
end)

describe("HealthPips hitAt", function()
	it("gives the last counted hit's time from KnockResetAt", function()
		expect(HealthPips.hitAt(20, Knock)).toBe(20 - Knock.resetAfter)
		expect(HealthPips.hitAt(0, Knock)).toBe(-math.huge)
		expect(HealthPips.hitAt(0 / 0, Knock)).toBe(-math.huge)
	end)
end)

describe("HealthPips pick", function()
	local far = Bar.near + 20
	it("shows near rivals, rivals in the crosshair and rivals just hit", function()
		expect(HealthPips.wanted({ id = 1, distance = Bar.near - 1, angle = 90, sinceHit = math.huge }, Bar)).toBe(true)
		expect(HealthPips.wanted({ id = 1, distance = far, angle = 90, sinceHit = math.huge }, Bar)).toBe(false)
		expect(HealthPips.wanted({ id = 1, distance = far, angle = Bar.aimAngle - 1, sinceHit = math.huge }, Bar)).toBe(
			true
		)
		expect(HealthPips.wanted({ id = 1, distance = Bar.aimRange + 1, angle = 0, sinceHit = math.huge }, Bar)).toBe(
			false
		)
		expect(HealthPips.wanted({ id = 1, distance = 500, angle = 90, sinceHit = Bar.afterHit - 0.1 }, Bar)).toBe(true)
		expect(HealthPips.wanted({ id = 1, distance = far, angle = 90, sinceHit = Bar.afterHit + 0.1 }, Bar)).toBe(
			false
		)
	end)

	it("keeps at most `max`, the latest hit first, then the nearest", function()
		local candidates = {}
		for id = 1, 8 do
			table.insert(candidates, { id = id, distance = id * 5, angle = 90, sinceHit = math.huge })
		end
		candidates[8].sinceHit = 1 -- far away but just hit
		local picked = HealthPips.pick(candidates, Bar)
		local count = 0
		for _ in picked do
			count += 1
		end
		expect(count).toBe(Bar.max)
		expect(picked[8]).toBe(true)
		expect(picked[1]).toBe(true)
		expect(picked[Bar.max]).toBe(nil)
	end)
end)
