local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Upgrades = require("../src/shared/Upgrades")
local Config = require("../src/shared/Config/Upgrades")
local TowerConfig = require("../src/shared/Config/Tower")
local ChestConfig = require("../src/shared/Config/Chest")
local LuckConfig = require("../src/shared/Config/Luck")

local function wallet(coins: number, levels: { [string]: number }?)
	return { coins = coins, upgrades = levels or { cone = 0, stability = 0, cart = 0, luck = 0, slots = 0 } }
end

describe("Upgrades: the config", function()
	it("every upgrade of the order exists, has 20 to 25 levels (the slots 3) and rising prices", function()
		for _, id in Config.order do
			local track = Config.tracks[id]
			expect(track ~= nil).toBe(true)
			local levels = if id == "slots" then 3 else track.maxLevel
			expect(track.maxLevel == levels and levels >= 3 and levels <= 25).toBe(true)
			expect(id == "slots" or track.maxLevel >= 20).toBe(true)
			local last = 0
			for level = 0, track.maxLevel - 1 do
				local cost = Upgrades.cost(id, level, Config)
				expect(cost ~= nil).toBe(true)
				expect(cost :: number).toBeGreaterThan(last)
				last = cost :: number
			end
		end
	end)

	it("the shop shows five upgrades; the sprinkles are prepared but hidden", function()
		local visible = Upgrades.visible(Config)
		expect(#visible).toBe(5)
		expect(table.find(visible, "sprinkles")).toBeNil()
		expect(Config.tracks.sprinkles.hidden).toBe(true)
	end)

	it("nothing in the shop helps in the fight: no sneakers, no stiffer cone", function()
		expect(Config.tracks.sneakers).toBeNil()
		expect(Config.tracks.cone.stiffnessPerLevel).toBe(0)
		for level = 0, Config.tracks.cone.maxLevel do
			expect(Upgrades.stiffness(level, Config)).toBe(1)
		end
	end)

	it("starts where the game stands today", function()
		expect(Config.tracks.stability.start).toBe(TowerConfig.walkHeavyFrom)
		expect(Config.tracks.slots.start).toBe(ChestConfig.equipSlots)
		expect(Upgrades.value("slots", Config.tracks.slots.maxLevel, Config)).toBe(6)
		expect(Upgrades.value("cone", 0, Config)).toBe(20)
		expect(Upgrades.value("cart", 0, Config)).toBe(1)
		expect(Upgrades.value("luck", 0, Config)).toBe(0)
	end)

	it("the top Luck level is exactly the luck source's own cap", function()
		local top = Upgrades.value("luck", Config.tracks.luck.maxLevel, Config)
		expect(top).toBeCloseTo(LuckConfig.sources.upgrade.cap, 1e-9)
	end)
end)

describe("Upgrades: values and prices", function()
	it("value = start + perLevel x level, clamped, free of float dust", function()
		expect(Upgrades.value("cone", 3, Config)).toBe(23)
		expect(Upgrades.value("cart", 3, Config)).toBe(1.12)
		expect(Upgrades.value("cone", -5, Config)).toBe(20)
		expect(Upgrades.value("cone", 99, Config)).toBe(Upgrades.value("cone", Config.tracks.cone.maxLevel, Config))
		expect(Upgrades.value("unknown", 1, Config)).toBe(0)
	end)

	it("prices follow base x growth ^ level, past the bend lateGrowth, rounded to two leading digits", function()
		expect(Upgrades.roundPrice(1234, 2)).toBe(1200)
		expect(Upgrades.roundPrice(98.6, 2)).toBe(99)
		expect(Upgrades.roundPrice(0.4, 2)).toBe(1)
		local track = Config.tracks.cone
		for level = 0, track.maxLevel - 1 do
			local c = track.cost
			local exact = c.base * c.growth ^ math.min(level, c.bend) * c.lateGrowth ^ math.max(0, level - c.bend)
			local cost = Upgrades.cost("cone", level, Config) :: number
			expect(math.abs(cost - exact) / exact <= 0.05).toBe(true)
		end
		-- the prices of 25.11.2026 (Config/Upgrades PRICE)
		expect(Upgrades.cost("cone", 0, Config)).toBe(43)
		expect(Upgrades.cost("cone", 11, Config)).toBe(19000)
		expect(Upgrades.cost("cone", 12, Config)).toBe(33000)
		expect(Upgrades.cost("cone", 24, Config)).toBe(75000)
		expect(Upgrades.cost("slots", 0, Config)).toBe(690)
		expect(Upgrades.cost("slots", 1, Config)).toBe(33000)
		expect(Upgrades.cost("slots", 2, Config)).toBe(65000)
		expect(Upgrades.cost("cone", track.maxLevel, Config)).toBeNil()
		expect(Upgrades.cost("cone", 1.5, Config)).toBeNil()
		expect(Upgrades.totalCost("cone", Config)).toBeGreaterThan(Upgrades.cost("cone", 0, Config) :: number)
	end)

	it("with a bend the price rises by lateGrowth per level from there on", function()
		local config = {
			priceDigits = 6,
			order = { "x" },
			tracks = {
				x = {
					maxLevel = 20,
					start = 0,
					perLevel = 1,
					cost = { base = 10, growth = 2, bend = 3, lateGrowth = 1.5 },
				},
			},
		}
		expect(Upgrades.cost("x", 0, config :: any)).toBe(10)
		expect(Upgrades.cost("x", 3, config :: any)).toBe(80) -- 10 x 2^3, still the early growth
		expect(Upgrades.cost("x", 4, config :: any)).toBe(120) -- 80 x 1.5
		expect(Upgrades.cost("x", 5, config :: any)).toBe(180)
		-- without a bend nothing changes
		config.tracks.x.cost = { base = 10, growth = 2 } :: any
		expect(Upgrades.cost("x", 5, config :: any)).toBe(320)
	end)

	it("the card's lines", function()
		expect(Upgrades.change("cone", 2, Config)).toBe("22 -> 23 scoops")
		expect(Upgrades.change("cart", 1, Config)).toBe("x1.04 -> x1.08")
		expect(Upgrades.change("luck", 1, Config)).toBe("+0.6% -> +1.2%")
		expect(Upgrades.change("slots", 3, Config)).toBe("6 slots") -- at the top only the value
		expect(Upgrades.change("cone", 0, Config, " > ")).toBe("20 > 21 scoops")
	end)
end)

describe("Upgrades: buying", function()
	it("takes the price and raises the level", function()
		local w = wallet(1000)
		local ok, level, cost = Upgrades.buy(w, "cone", 0, Config)
		expect(ok).toBe(true)
		expect(level).toBe(1)
		expect(cost).toBe(Upgrades.cost("cone", 0, Config))
		expect(w.coins).toBe(1000 - (cost :: number))
		expect(w.upgrades.cone).toBe(1)
	end)

	it("too few coins: refused, nothing changes", function()
		local price = Upgrades.cost("luck", 0, Config) :: number
		local w = wallet(price - 1)
		local ok, reason = Upgrades.buy(w, "luck", 0, Config)
		expect(ok).toBe(false)
		expect(reason).toBe("coins")
		expect(w.coins).toBe(price - 1)
		expect(w.upgrades.luck).toBe(0)
		-- exactly enough is enough
		local exact = wallet(price)
		expect((Upgrades.buy(exact, "luck", 0, Config))).toBe(true)
		expect(exact.coins).toBe(0)
	end)

	it("at the top: refused as max", function()
		local top = Config.tracks.slots.maxLevel
		local w = wallet(1e9, { slots = top })
		local ok, reason = Upgrades.buy(w, "slots", top, Config)
		expect(ok).toBe(false)
		expect(reason).toBe("max")
		expect(w.coins).toBe(1e9)
		expect(w.upgrades.slots).toBe(top)
	end)

	it("a double click buys once: the second finds the level raised", function()
		local w = wallet(100000)
		expect((Upgrades.buy(w, "cart", 0, Config))).toBe(true)
		local coins = w.coins
		local ok, reason = Upgrades.buy(w, "cart", 0, Config)
		expect(ok).toBe(false)
		expect(reason).toBe("stale")
		expect(w.coins).toBe(coins)
		expect(w.upgrades.cart).toBe(1)
	end)

	it("buys every level up to the top, one after the other", function()
		local w = wallet(Upgrades.totalCost("stability", Config))
		for level = 0, Config.tracks.stability.maxLevel - 1 do
			expect((Upgrades.buy(w, "stability", level, Config))).toBe(true)
		end
		expect(w.coins).toBe(0)
		expect(w.upgrades.stability).toBe(Config.tracks.stability.maxLevel)
	end)

	it("refuses what a client should never send", function()
		local w = wallet(1e9)
		for _, case in
			{
				{ "sprinkles", 0, "hidden" },
				{ "sneakers", 0, "unknown" },
				{ "nope", 0, "unknown" },
				{ 42, 0, "unknown" },
				{ "cone", 0 / 0, "stale" },
				{ "cone", math.huge, "stale" },
				{ "cone", -1, "stale" },
				{ "cone", 0.5, "stale" },
				{ "cone", "0", "stale" },
			}
		do
			local ok, reason = Upgrades.buy(w, case[1], case[2], Config)
			expect(ok).toBe(false)
			expect(reason).toBe(case[3])
		end
		expect(w.coins).toBe(1e9)
	end)

	it("a missing level in the save counts as 0", function()
		local w = { coins = 1000, upgrades = {} }
		expect((Upgrades.buy(w, "stability", 0, Config))).toBe(true)
		expect(w.upgrades.stability).toBe(1)
	end)
end)

describe("Upgrades: the highest level per rebirth (prepared, Config/Upgrades.levelCap)", function()
	local capped = table.clone(Config)
	capped.levelCap = { enabled = true, base = 10, perRebirth = 5 }

	it("is off now: every level up to the top can be bought", function()
		expect(Upgrades.top("cone", 0, Config)).toBe(Config.tracks.cone.maxLevel)
		local w = { coins = 1e9, upgrades = { cone = 10 } }
		expect((Upgrades.buy(w, "cone", 10, Config))).toBe(true)
	end)

	it("on: 10 without a rebirth, 5 more for each, never past the top", function()
		expect(Upgrades.top("cone", 0, capped)).toBe(10)
		expect(Upgrades.top("cone", 1, capped)).toBe(15)
		expect(Upgrades.top("cone", 3, capped)).toBe(25)
		expect(Upgrades.top("cone", 9, capped)).toBe(25)
		expect(Upgrades.top("stability", 2, capped)).toBe(20)
		expect(Upgrades.top("slots", 0, capped)).toBe(3) -- fewer levels than the cap: unchanged
		expect(Upgrades.top("cone", 0 / 0, capped)).toBe(10)
	end)

	it("on: buying past the cap is refused as cap, nothing changes; a rebirth lifts it", function()
		local w = { coins = 1e9, upgrades = { cone = 10 } }
		local ok, reason = Upgrades.buy(w, "cone", 10, capped)
		expect(ok).toBe(false)
		expect(reason).toBe("cap")
		expect(w.coins).toBe(1e9)
		expect(w.upgrades.cone).toBe(10)
		local reborn = { coins = 1e9, upgrades = { cone = 10 }, rebirths = 1 }
		expect((Upgrades.buy(reborn, "cone", 10, capped))).toBe(true)
	end)
end)
