local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local BossRules = require("../src/shared/BossRules")
local Config = require("../src/shared/Config/Bosses")
local Flavors = require("../src/shared/Config/Flavors")
local Upgrades = require("../src/shared/Upgrades")
local UpgradesConfig = require("../src/shared/Config/Upgrades")

local S = Config.schedule
local HOUR = 3600

describe("Bosses: config", function()
	it("has three bosses, each with name, health, attacks, model, in the order", function()
		expect(#Config.order).toBe(3)
		for _, id in Config.order do
			local boss = Config.bosses[id]
			expect(boss ~= nil).toBe(true)
			expect(type(boss.name)).toBe("string")
			expect(boss.health > 0).toBe(true)
			expect(type(boss.model)).toBe("string")
			expect(#boss.attacks > 0).toBe(true)
			for _, attack in boss.attacks do
				expect(attack.warn > 0).toBe(true)
				expect(attack.cooldown > 0).toBe(true)
			end
		end
	end)

	it(
		"the rhythm: a normal boss every 15 to 20 minutes, the big one announced 5 minutes ahead, 3 minutes each",
		function()
			expect(S.normalMin).toBe(15 * 60)
			expect(S.normalMax).toBe(20 * 60)
			expect(S.announce).toBe(5 * 60)
			expect(Config.lifetime).toBe(3 * 60)
			-- a normal boss may never still be alive when the big one comes
			expect(S.blockBefore >= S.announce + Config.lifetime).toBe(true)
		end
	)

	it("the truce is a switch in the config, and on", function()
		expect(Config.truce).toBe(true)
	end)

	it("a boss hit never knocks down: only a shove and 2 to 3 scoops", function()
		expect(Config.hit.dropMin).toBe(2)
		expect(Config.hit.dropMax).toBe(3)
		expect(Config.hit.knockdown).toBe(nil)
	end)

	it("the reward scoop is the owner's for 20 s", function()
		expect(Config.reward.scoop.ownerSeconds).toBe(20)
		expect(Config.reward.scoop.lifetime > Config.reward.scoop.ownerSeconds).toBe(true)
	end)
end)

describe("Bosses: schedule", function()
	it("the full hour at or after a time", function()
		expect(BossRules.hourAtOrAfter(0)).toBe(0)
		expect(BossRules.hourAtOrAfter(1)).toBe(HOUR)
		expect(BossRules.hourAtOrAfter(5 * HOUR - 10)).toBe(5 * HOUR)
		expect(BossRules.hourAtOrAfter(5 * HOUR)).toBe(5 * HOUR)
	end)

	it("a normal boss comes 15 to 20 minutes after the last one", function()
		local from = 10 * HOUR + 60 -- right after a full hour's block? no: 1 minute past, inside blockAfter
		from = 10 * HOUR + 10 * 60
		expect(BossRules.nextNormalAt(from, 0, S)).toBe(from + 15 * 60)
		expect(BossRules.nextNormalAt(from, 1, S)).toBe(from + 20 * 60)
		expect(BossRules.nextNormalAt(from, 0.5, S)).toBe(from + 17.5 * 60)
	end)

	it("the big boss takes the place of a normal one: none within its block round the full hour", function()
		-- 10:40 + 15 min = 10:55, inside the 8 minutes before 11:00: pushed to after the block
		local from = 10 * HOUR + 40 * 60
		local at = BossRules.nextNormalAt(from, 0, S)
		expect(at).toBe(11 * HOUR + S.blockAfter)
		expect(BossRules.blockingHour(11 * HOUR - 60, S)).toBe(11 * HOUR)
		expect(BossRules.blockingHour(11 * HOUR + 60, S)).toBe(11 * HOUR)
		expect(BossRules.blockingHour(11 * HOUR + 30 * 60, S)).toBe(nil)
		-- over a whole day no normal boss start ever falls into a block
		local t = 3 * 60
		for step = 1, 200 do
			t = BossRules.nextNormalAt(t + Config.lifetime, (step * 0.37) % 1, S)
			expect(BossRules.blockingHour(t, S)).toBe(nil)
		end
	end)

	it("the first one after a server start comes sooner", function()
		expect(BossRules.nextNormalAt(20 * 60, 0, S, true)).toBe(20 * 60 + S.firstMin)
	end)

	it("the sign counts down to whichever comes first, the big one when they fall together", function()
		local at, big = BossRules.nextBoss(1000, 3600)
		expect(at).toBe(1000)
		expect(big).toBe(false)
		at, big = BossRules.nextBoss(4000, 3600)
		expect(at).toBe(3600)
		expect(big).toBe(true)
		at, big = BossRules.nextBoss(3600, 3600)
		expect(big).toBe(true)
		expect(string.format(Config.sign.next, BossRules.clock(754))).toBe("BOSS IN 12:34")
		expect(string.format(Config.sign.nextBig, BossRules.clock(299))).toBe("BIG BOSS IN 4:59")
	end)

	it("the clock for the announcement", function()
		expect(BossRules.clock(300)).toBe("5:00")
		expect(BossRules.clock(59.2)).toBe("1:00")
		expect(BossRules.clock(0)).toBe("0:00")
		expect(BossRules.clock(-3)).toBe("0:00")
	end)
end)

describe("Bosses: health and damage", function()
	it("health grows with the players in the arena", function()
		local base = Config.bosses.iceBrute.health
		expect(BossRules.maxHealth(base, 1, false, Config)).toBe(base)
		expect(BossRules.maxHealth(base, 0, false, Config)).toBe(base)
		expect(BossRules.maxHealth(base, 3, false, Config)).toBe(
			math.floor(base * (1 + 2 * Config.health.perPlayer) + 0.5)
		)
		expect(BossRules.maxHealth(base, 1, true, Config)).toBe(base * Config.big.health)
	end)

	it("more players later raise the health by the same amount; fewer never lower it", function()
		local full, current = BossRules.grow(400, 900, 1440)
		expect(full).toBe(1440)
		expect(current).toBe(940)
		full, current = BossRules.grow(400, 900, 600)
		expect(full).toBe(900)
		expect(current).toBe(400)
	end)

	it("damage: per hit x power x Boss Power", function()
		expect(BossRules.damage(1, 1, Config)).toBe(Config.damagePerHit)
		expect(BossRules.damage(0.5, 1, Config)).toBe(Config.damagePerHit / 2)
		expect(BossRules.damage(2, 1, Config)).toBe(Config.damagePerHit)
		expect(BossRules.damage(0 / 0, 1, Config)).toBe(0)
		expect(BossRules.damage(1, 1.5, Config)).toBe(Config.damagePerHit * 1.5)
	end)

	it("Boss Power is prepared as a hidden upgrade the shop does not show", function()
		local track = UpgradesConfig.tracks.bossPower
		expect(track ~= nil).toBe(true)
		expect(track.hidden).toBe(true)
		expect(table.find(Upgrades.visible(UpgradesConfig), "bossPower")).toBe(nil)
		expect(Upgrades.value("bossPower", 0, UpgradesConfig)).toBe(1)
		expect(Upgrades.value("bossPower", 10, UpgradesConfig) > 1).toBe(true)
	end)
end)

describe("Bosses: reward", function()
	it("everybody with damage gets coins, more damage more coins; nobody without damage", function()
		local coins = BossRules.rewards({ a = 300, b = 100, c = 0 }, false, Config)
		expect(coins.c).toBe(nil)
		expect(coins.a > coins.b).toBe(true)
		expect(coins.b >= Config.reward.coinsBase).toBe(true)
		expect(coins.a + coins.b).toBe(2 * Config.reward.coinsBase + Config.reward.coinsPot)
	end)

	it("the big boss pays more", function()
		local normal = BossRules.rewards({ a = 1 }, false, Config)
		local big = BossRules.rewards({ a = 1 }, true, Config)
		expect(big.a).toBe(normal.a * Config.big.coins)
	end)

	it("the reward scoop is at least rare, the big boss has better odds", function()
		local function share(odds, rarity)
			local hits = 0
			for i = 0, 999 do
				local r = BossRules.rollRarity(i / 1000, odds)
				expect(r == "rare" or r == "epic" or r == "legendary").toBe(true)
				if r == rarity then
					hits += 1
				end
			end
			return hits / 1000
		end
		expect(share(Config.reward.odds, "legendary")).toBeCloseTo(0.05, 0.01)
		expect(share(Config.big.odds, "legendary")).toBeCloseTo(0.15, 0.01)
		expect(share(Config.big.odds, "rare") < share(Config.reward.odds, "rare")).toBe(true)
	end)

	it("there are flavors for every reward rarity", function()
		for _, rarity in { "rare", "epic", "legendary" } do
			expect(#BossRules.flavorsOf(rarity, Flavors.list) > 0).toBe(true)
		end
	end)
end)

describe("Bosses: attacks", function()
	it("a disc hits inside, a little smaller in the player's favour", function()
		expect(BossRules.inDisc(5, 0, 0, 0, 10, 1)).toBe(true)
		expect(BossRules.inDisc(9.5, 0, 0, 0, 10, 1)).toBe(false)
		expect(BossRules.inDisc(12, 0, 0, 0, 10, 1)).toBe(false)
	end)

	it("a wave touches only at its ring", function()
		expect(BossRules.waveTouches(20, 0, 0, 0, 20, 3, 1)).toBe(true)
		expect(BossRules.waveTouches(25, 0, 0, 0, 20, 3, 1)).toBe(false)
		expect(BossRules.waveTouches(10, 0, 0, 0, 20, 3, 1)).toBe(false)
	end)

	it("a dash just before the impact dodges, a jump dodges the wave", function()
		expect(BossRules.dodged(10, 10.2, nil, Config)).toBe(true)
		expect(BossRules.dodged(10, 11, nil, Config)).toBe(false)
		expect(BossRules.dodged(-math.huge, 11, Config.hit.jumpClear + 0.1, Config)).toBe(true)
		expect(BossRules.dodged(-math.huge, 11, 0.2, Config)).toBe(false)
	end)

	it("a hit knocks 2 to 3 scoops off, never more than there are", function()
		expect(BossRules.dropCount(10, 0, Config)).toBe(2)
		expect(BossRules.dropCount(10, 0.99, Config)).toBe(3)
		expect(BossRules.dropCount(1, 0.99, Config)).toBe(1)
		expect(BossRules.dropCount(0, 0.5, Config)).toBe(0)
	end)

	it("the boss stays in its ring round the Big Swirl", function()
		local x, z = BossRules.intoRing(0, 5, Config.roam)
		expect(math.sqrt(x * x + z * z)).toBeCloseTo(Config.roam.minRadius, 1e-6)
		x, z = BossRules.moveToward(60, 0, 500, 0, 10, 100, Config.roam)
		expect(x).toBeCloseTo(Config.roam.maxRadius, 1e-6)
		x, z = BossRules.moveToward(60, 0, 70, 0, 6, 0.5, Config.roam)
		expect(x).toBeCloseTo(63, 1e-6)
	end)

	it("picks only attacks whose cooldown is over", function()
		local attacks = { {}, {}, {} }
		expect(BossRules.pickAttack(attacks, { 5, 0, 5 }, 1, 0.9)).toBe(2)
		expect(BossRules.pickAttack(attacks, { 5, 5, 5 }, 1, 0.5)).toBe(nil)
		expect(BossRules.pickAttack(attacks, { 0, 0, 0 }, 1, 0)).toBe(1)
		expect(BossRules.pickAttack(attacks, { 0, 0, 0 }, 1, 0.99)).toBe(3)
	end)

	it("the big boss attacks more often", function()
		expect(BossRules.pause(2, true, Config) < BossRules.pause(2, false, Config)).toBe(true)
	end)
end)
