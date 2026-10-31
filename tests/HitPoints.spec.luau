local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local HitPoints = require("../src/shared/HitPoints")
local CombatConfig = require("../src/shared/Config/Combat")

local Config = CombatConfig.knock
local P = Config.points
local DOWN = CombatConfig.knockdownTime

-- the values a hit can be worth, by kind; power 1 except for the graze
local KINDS = {
	{ name = "graze", headshot = false, perfect = false, power = Config.grazeBelow - 0.01 },
	{ name = "normal", headshot = false, perfect = false, power = 1 },
	{ name = "perfect", headshot = false, perfect = true, power = 1 },
	{ name = "headshot", headshot = true, perfect = false, power = 1 },
	{ name = "headshot perfect", headshot = true, perfect = true, power = 1 },
}

local function worth(kind): number
	return HitPoints.value(kind.headshot, kind.perfect, kind.power, Config)
end

-- hits at `times`, each worth values[i]; returns the index of the hit that knocks down, or nil
local function knockdownAt(values: { number }, times: { number }): number?
	local state = HitPoints.new()
	for index, value in values do
		local _, down = HitPoints.add(state, times[index], value, times[index] + DOWN, Config)
		if down then
			return index
		end
	end
	return nil
end

-- hits of one kind, `gap` seconds apart (at least the throw interval, so the window never merges them)
local function hitsToKnockdown(value: number, gap: number): number?
	local values, times = {}, {}
	for index = 1, 10 do
		values[index] = value
		times[index] = (index - 1) * gap
	end
	return knockdownAt(values, times)
end

describe("Knockdown points: what a hit is worth", function()
	it("normal 2, graze 1, perfect 3, headshot 3, perfect headshot 6, knockdown at 6", function()
		expect(P.normal).toBe(2)
		expect(P.graze).toBe(1)
		expect(P.perfect).toBe(3)
		expect(P.headshot).toBe(3)
		expect(P.headshotPerfect).toBe(6)
		expect(Config.knockdownAt).toBe(6)
		expect(Config.resetAfter).toBe(4)
		expect(Config.multiWindow).toBe(0.25)
		expect(Config.protection).toBe(2)
	end)

	it("every combination of headshot, perfect and power gets its value", function()
		for _, headshot in { false, true } do
			for _, perfect in { false, true } do
				for _, power in { 0.18, Config.grazeBelow - 0.001, Config.grazeBelow, 0.6, 1 } do
					local value = HitPoints.value(headshot, perfect, power, Config)
					local expected
					if headshot and perfect then
						expected = P.headshotPerfect
					elseif headshot then
						expected = P.headshot
					elseif perfect then
						expected = P.perfect
					elseif power < Config.grazeBelow then
						expected = P.graze
					else
						expected = P.normal
					end
					expect(value).toBe(expected)
				end
			end
		end
	end)

	it("only a normal hit can be a graze: a weak headshot or perfect throw keeps its value", function()
		expect(HitPoints.value(true, false, 0.2, Config)).toBe(P.headshot)
		expect(HitPoints.value(false, true, 0.2, Config)).toBe(P.perfect)
		expect(HitPoints.value(true, true, 0.2, Config)).toBe(P.headshotPerfect)
	end)
end)

describe("Knockdown points: one kind of hit in a row", function()
	-- a realistic pace: the throw interval and a short hold
	local gap = CombatConfig.throwInterval + 0.2

	it("knocks down after 6 grazes, 3 normal, 2 perfect, 2 headshots, 1 perfect headshot", function()
		local expected = { graze = 6, normal = 3, perfect = 2, headshot = 2, ["headshot perfect"] = 1 }
		for _, kind in KINDS do
			expect(hitsToKnockdown(worth(kind), gap)).toBe(expected[kind.name])
		end
	end)

	it("a single hit never knocks down, except a perfect headshot", function()
		for _, kind in KINDS do
			local down = knockdownAt({ worth(kind) }, { 0 }) ~= nil
			expect(down).toBe(kind.name == "headshot perfect")
		end
	end)
end)

describe("Knockdown points: every pair of hits", function()
	it("two hits knock down exactly when their values reach 6", function()
		for _, first in KINDS do
			for _, second in KINDS do
				local a, b = worth(first), worth(second)
				local at = knockdownAt({ a, b }, { 0, 1 })
				local expected = if a >= 6 then 1 elseif a + b >= 6 then 2 else nil
				expect(at).toBe(expected)
			end
		end
	end)

	it("every three hits of a load (1 s apart) knock down exactly when they reach 6", function()
		for _, a in KINDS do
			for _, b in KINDS do
				for _, c in KINDS do
					local values = { worth(a), worth(b), worth(c) }
					local sum, expected = 0, nil
					for index, value in values do
						sum += value
						if sum >= 6 and not expected then
							expected = index
						end
					end
					expect(knockdownAt(values, { 0, 1, 2 })).toBe(expected)
				end
			end
		end
	end)
end)

describe("Knockdown points: the reset after 4 s without a hit", function()
	it("a hit just before 4 s still adds up, one at 4 s starts from 0", function()
		local state = HitPoints.new()
		HitPoints.add(state, 0, P.normal, DOWN, Config)
		HitPoints.add(state, 3.99, P.normal, 3.99 + DOWN, Config)
		expect(state.points).toBe(4)

		state = HitPoints.new()
		HitPoints.add(state, 0, P.normal, DOWN, Config)
		HitPoints.add(state, 4, P.normal, 4 + DOWN, Config)
		expect(state.points).toBe(2)
	end)

	it("the 4 s run from the last hit: hits every 3.5 s keep adding up to a knockdown", function()
		expect(hitsToKnockdown(P.normal, 3.5)).toBe(3)
		expect(hitsToKnockdown(P.normal, 4)).toBeNil()
		expect(hitsToKnockdown(P.graze, 4)).toBeNil()
	end)

	it("the meter shows 0 once the reset time has passed, without a new hit", function()
		expect(HitPoints.display(4, 10, 0, 9.9, Config)).toBe(4)
		expect(HitPoints.display(4, 10, 0, 10, Config)).toBe(0)
	end)
end)

describe("Knockdown points: several players at once", function()
	it("hits within 0.25 s count once, the strongest, whichever comes first", function()
		for _, first in KINDS do
			for _, second in KINDS do
				local state = HitPoints.new()
				local a, b = worth(first), worth(second)
				local addedA, downA = HitPoints.add(state, 0, a, DOWN, Config)
				expect(addedA).toBe(a)
				if not downA then
					local addedB, downB = HitPoints.add(state, 0.2, b, 0.2 + DOWN, Config)
					expect(addedB).toBe(math.max(0, b - a))
					expect(downB).toBe(math.max(a, b) >= 6)
				end
			end
		end
	end)

	it("a normal hit and a headshot 0.1 s apart give 3, not 5", function()
		local state = HitPoints.new()
		HitPoints.add(state, 0, P.normal, DOWN, Config)
		HitPoints.add(state, 0.1, P.headshot, 0.1 + DOWN, Config)
		expect(state.points).toBe(3)
	end)

	it("three players within the window: still only the strongest", function()
		local state = HitPoints.new()
		HitPoints.add(state, 0, P.graze, DOWN, Config)
		HitPoints.add(state, 0.1, P.perfect, 0.1 + DOWN, Config)
		HitPoints.add(state, 0.2, P.normal, 0.2 + DOWN, Config)
		expect(state.points).toBe(3)
	end)

	it("the window runs from its first hit: 0.25 s later or more counts in full", function()
		local state = HitPoints.new()
		HitPoints.add(state, 0, P.normal, DOWN, Config)
		HitPoints.add(state, 0.25, P.normal, 0.25 + DOWN, Config)
		expect(state.points).toBe(4)

		state = HitPoints.new()
		HitPoints.add(state, 0, P.normal, DOWN, Config)
		HitPoints.add(state, 0.24, P.normal, 0.24 + DOWN, Config)
		expect(state.points).toBe(2)
	end)

	it("a weaker hit in the window still counts as a hit for the 4 s reset", function()
		local state = HitPoints.new()
		HitPoints.add(state, 0, P.perfect, DOWN, Config)
		HitPoints.add(state, 0.2, P.graze, 0.2 + DOWN, Config)
		HitPoints.add(state, 4.1, P.normal, 4.1 + DOWN, Config) -- 3.9 s after the weaker one
		expect(state.points).toBe(5)
	end)
end)

describe("Knockdown points: the get-up protection", function()
	it("a knockdown empties the count and protects for 2 s after getting up", function()
		local state = HitPoints.new()
		local _, down = HitPoints.add(state, 0, P.headshotPerfect, DOWN, Config)
		expect(down).toBe(true)
		expect(state.points).toBe(0)
		expect(state.protectedUntil).toBeCloseTo(DOWN + Config.protection, 1e-9)
	end)

	it("hits in the protection give no points, of any kind; right after it they count again", function()
		for _, kind in KINDS do
			local state = HitPoints.new()
			HitPoints.add(state, 0, P.headshotPerfect, DOWN, Config)
			local up = DOWN
			local added, down = HitPoints.add(state, up + Config.protection - 0.01, worth(kind), 99, Config)
			expect(added).toBe(0)
			expect(down).toBe(false)
			expect(state.points).toBe(0)
			added = HitPoints.add(state, up + Config.protection, worth(kind), 99, Config)
			expect(added).toBe(worth(kind))
		end
	end)

	it("a perfect headshot right after the protection knocks down again", function()
		local state = HitPoints.new()
		HitPoints.add(state, 0, P.headshotPerfect, DOWN, Config)
		local _, down = HitPoints.add(state, DOWN + Config.protection, P.headshotPerfect, 99, Config)
		expect(down).toBe(true)
	end)

	it("the meter shows the protection while it lasts", function()
		local _, protected = HitPoints.display(0, 0, 5, 4.9, Config)
		expect(protected).toBe(true)
		_, protected = HitPoints.display(0, 0, 5, 5, Config)
		expect(protected).toBe(false)
	end)

	it("the meter clamps odd replicated values", function()
		expect(HitPoints.display(0 / 0, 10, 0, 0, Config)).toBe(0)
		expect(HitPoints.display(99, 10, 0, 0, Config)).toBe(Config.knockdownAt)
		expect(HitPoints.display(-3, 10, 0, 0, Config)).toBe(0)
		expect(HitPoints.display(4, 0 / 0, 0, 0, Config)).toBe(0)
	end)
end)
