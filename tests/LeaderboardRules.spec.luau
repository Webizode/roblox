local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local LeaderboardRules = require("../src/shared/LeaderboardRules")

describe("LeaderboardRules", function()
	it("stores whole, non-negative coins and nothing broken", function()
		expect(LeaderboardRules.storedCoins(12.9)).toBe(12)
		expect(LeaderboardRules.storedCoins(-5)).toBe(0)
		expect(LeaderboardRules.storedCoins(0 / 0)).toBe(0)
		expect(LeaderboardRules.storedCoins(math.huge)).toBe(0)
		expect(LeaderboardRules.storedCoins("100")).toBe(0)
	end)

	it("ranks a sorted page and drops bad keys, bad values and repeats", function()
		local rows = LeaderboardRules.rows({
			{ key = "111", value = 900 },
			{ key = "Player_5", value = 800 },
			{ key = "222", value = 0 / 0 },
			{ key = "333", value = 700.5 },
			{ key = "111", value = 600 },
			{ key = "-4", value = 500 },
			{ key = "444", value = 400 },
		}, 10)
		expect(#rows).toBe(3)
		expect(rows[1].userId).toBe(111)
		expect(rows[1].rank).toBe(1)
		expect(rows[2].userId).toBe(333)
		expect(rows[2].coins).toBe(700)
		expect(rows[3].userId).toBe(444)
		expect(rows[3].rank).toBe(3)
	end)

	it("shows at most `count` rows", function()
		local entries = {}
		for i = 1, 25 do
			table.insert(entries, { key = tostring(i), value = 100 - i })
		end
		local rows = LeaderboardRules.rows(entries, 10)
		expect(#rows).toBe(10)
		expect(rows[10].rank).toBe(10)
		expect(rows[10].userId).toBe(10)
	end)

	it("writes coins with separators and shortens big numbers", function()
		expect(LeaderboardRules.formatCoins(0)).toBe("0")
		expect(LeaderboardRules.formatCoins(999)).toBe("999")
		expect(LeaderboardRules.formatCoins(1000)).toBe("1,000")
		expect(LeaderboardRules.formatCoins(123456)).toBe("123,456")
		expect(LeaderboardRules.formatCoins(999999)).toBe("999,999")
		expect(LeaderboardRules.formatCoins(1250000)).toBe("1.2M")
		expect(LeaderboardRules.formatCoins(3400000000)).toBe("3.4B")
	end)

	it("writes a player again only after a change and the interval", function()
		expect(LeaderboardRules.dueWrite(100, nil, nil, 0, 60)).toBe(true)
		expect(LeaderboardRules.dueWrite(100, 100, 0, 500, 60)).toBe(false)
		expect(LeaderboardRules.dueWrite(150, 100, 0, 30, 60)).toBe(false)
		expect(LeaderboardRules.dueWrite(150, 100, 0, 60, 60)).toBe(true)
	end)
end)
