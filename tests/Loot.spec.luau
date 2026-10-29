local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Loot = require("../src/shared/Loot")
local TowerShape = require("../src/shared/TowerShape")
local Economy = require("../src/shared/Economy")
local Config = require("../src/shared/Config/Loot")
local EconomyConfig = require("../src/shared/Config/Economy")
local Tuning = require("../src/shared/Config/Tower")

local function tower(count: number): { string }
	return table.create(count, "vanilla")
end

local function spill(count: number, tiltX: number, tiltZ: number, seed: number?)
	local keep = Economy.keepOnTopple(count, EconomyConfig)
	return Loot.spill(tower(count), keep, tiltX, tiltZ, seed or 1, Config, Tuning, TowerShape), keep
end

local function scoop(owner: number, landedAt: number, ownerDownUntil: number?): Loot.Scoop
	return {
		owner = owner,
		landedAt = landedAt,
		ownerFrom = Loot.ownerFrom(landedAt, Config),
		ownerUntil = Loot.ownerUntil(landedAt, ownerDownUntil or 0, Config),
		expiresAt = landedAt - Config.fallTime + Config.lifetime,
	}
end

describe("Spilled scoops: what falls", function()
	it("towers under 5 scoops lose nothing, taller ones keep 30 % (at least 2)", function()
		for count = 1, 4 do
			local paths, keep = spill(count, Tuning.tipAngle, 0)
			expect(keep).toBe(count)
			expect(#paths).toBe(0)
		end
		local paths, keep = spill(5, Tuning.tipAngle, 0)
		expect(keep).toBe(2)
		expect(#paths).toBe(3)
		paths, keep = spill(20, Tuning.tipAngle, 0)
		expect(keep).toBe(6)
		expect(#paths).toBe(14)
	end)

	it("drops the scoops above the kept ones, with their flavors, the top one first", function()
		local flavors = { "vanilla", "mint", "chocolate", "strawberry", "vanilla", "lemon" }
		local paths = Loot.spill(flavors, 2, 0.5, 0, 1, Config, Tuning, TowerShape)
		expect(#paths).toBe(4)
		expect(paths[1].flavorId).toBe("lemon")
		expect(paths[4].flavorId).toBe("chocolate")
	end)

	it("lands where the scoop sat in the leaning tower and rolls on only a few studs, away from the tower", function()
		local paths = spill(20, Tuning.tipAngle, 0)
		local previous = math.huge
		for _, path in paths do
			-- the tower leaned towards +X: higher scoops land further out
			expect(path.lx).toBeGreaterThan(0)
			expect(path.lx).toBeLessThan(previous + 1e-9)
			previous = path.lx
			local roll = math.sqrt(path.rx * path.rx + path.rz * path.rz)
			expect(roll).toBeGreaterThan(Config.rollMin - 1e-9)
			expect(roll).toBeLessThan(Config.rollMax + 1e-9)
			-- within rollSpread of the lean
			expect(math.abs(math.atan2(path.rz, path.rx))).toBeLessThan(Config.rollSpread + 1e-9)
		end
		expect(paths[1].lx).toBeGreaterThan(10) -- the top of a toppled 20-scoop tower lands well away
	end)

	it("falls to the ground in fallTime, then slows down and comes to rest after about a second", function()
		local path = spill(10, Tuning.tipAngle, 0)[1]
		local x0, y0 = Loot.position(path, 0, Config)
		expect(x0).toBeCloseTo(path.sx, 1e-9)
		expect(y0).toBeCloseTo(path.sy, 1e-9)
		local _, yLanded = Loot.position(path, Config.fallTime, Config)
		expect(yLanded).toBe(0)
		local early = Loot.rollShare(Config.fallTime + 0.2, Config)
		local late = Loot.rollShare(Config.fallTime + 1, Config)
		expect(early).toBeGreaterThan(0.4)
		expect(late).toBeGreaterThan(0.97)
		expect(Loot.rollShare(Config.fallTime + 10, Config)).toBeLessThan(1 + 1e-9)
	end)

	it("is the same spill wherever it is computed, and a different one for another topple", function()
		local a, b, c = spill(12, 0.3, 0.4, 7), spill(12, 0.3, 0.4, 7), spill(12, 0.3, 0.4, 8)
		expect(a[1].rx).toBe(b[1].rx)
		expect(a[1].rz).toBe(b[1].rz)
		expect(a[1].rx == c[1].rx and a[1].rz == c[1].rz).toBe(false)
	end)

	it("scatters the scoops of one spill: neighbours roll different ways and different distances", function()
		local paths = spill(20, Tuning.tipAngle, 0, 5)
		local minAngle, maxAngle, minRoll, maxRoll = math.huge, -math.huge, math.huge, -math.huge
		for _, path in paths do
			local angle = math.atan2(path.rz, path.rx)
			local roll = math.sqrt(path.rx * path.rx + path.rz * path.rz)
			minAngle, maxAngle = math.min(minAngle, angle), math.max(maxAngle, angle)
			minRoll, maxRoll = math.min(minRoll, roll), math.max(maxRoll, roll)
		end
		-- 14 scoops use most of the +-50 degree fan and most of the 2 to 4 studs
		expect(maxAngle - minAngle).toBeGreaterThan(Config.rollSpread * 1.2)
		expect(maxRoll - minRoll).toBeGreaterThan((Config.rollMax - Config.rollMin) * 0.6)
		-- and even without a lean, an upright tower's scoops do not all go the same way
		local upright = spill(8, 0, 0, 5)
		local first = math.atan2(upright[1].rz, upright[1].rx)
		local differs = false
		for _, path in upright do
			differs = differs or math.abs(math.atan2(path.rz, path.rx) - first) > 0.5
		end
		expect(differs).toBe(true)
	end)

	it("an upright tower that toppled anyway spills in some direction, still only a short roll", function()
		for _, path in spill(8, 0, 0, 3) do
			local roll = math.sqrt(path.rx * path.rx + path.rz * path.rz)
			expect(roll).toBeLessThan(Config.rollMax + 1e-9)
		end
	end)

	it("checks the ground at the landing point and along the roll, in time order", function()
		local path = spill(10, Tuning.tipAngle, 0)[1]
		local samples = Loot.groundSamples(path, Config)
		expect(#samples).toBe(Config.waterSamples + 1)
		expect(samples[1].t).toBe(Config.fallTime)
		for index = 2, #samples do
			expect(samples[index].t).toBeGreaterThan(samples[index - 1].t)
			-- each sample lies on the drawn path at its time
			local x, _, z = Loot.position(path, samples[index].t, Config)
			expect(x).toBeCloseTo(samples[index].x, 1e-6)
			expect(z).toBeCloseTo(samples[index].z, 1e-6)
		end
	end)
end)

describe("Spilled scoops: real ground along the roll", function()
	local function samples()
		return Loot.groundSamples(spill(10, Tuning.tipAngle, 0)[1], Config)
	end

	it("on flat ground it rolls all the way at that height", function()
		local list = samples()
		local profile = Loot.rollProfile(list, { 8.4, 8.4, 8.4, 8.4, 8.4 }, Config)
		expect(profile.stopShare).toBe(1)
		expect(profile.sinkAt).toBeNil()
		expect(Loot.groundHeight(profile, 0)).toBe(8.4)
		expect(Loot.groundHeight(profile, 1)).toBe(8.4)
	end)

	it("follows a step down: off a platform it comes down to the floor", function()
		local list = samples()
		local profile = Loot.rollProfile(list, { 17, 17, 5.9, 5.9, 5.9 }, Config)
		expect(profile.stopShare).toBe(1)
		expect(Loot.groundHeight(profile, list[2].share)).toBe(17)
		expect(Loot.groundHeight(profile, list[3].share)).toBe(5.9)
		-- in between it is on the way down
		local middle = Loot.groundHeight(profile, (list[2].share + list[3].share) / 2) :: number
		expect(middle).toBeLessThan(17)
		expect(middle).toBeGreaterThan(5.9)
	end)

	it("stops against a step up higher than maxRollStep, rolls over a lower one", function()
		local list = samples()
		local blocked = Loot.rollProfile(list, { 8.4, 8.4, 8.4 + Config.maxRollStep + 0.5, 12, 12 }, Config)
		expect(blocked.stopShare).toBe(list[2].share)
		expect(#blocked.heights).toBe(2)
		local path = spill(10, Tuning.tipAngle, 0)[1]
		local x, _, z = Loot.position(path, 10, Config, blocked.stopShare)
		expect(x).toBeCloseTo(path.lx + path.rx * blocked.stopShare, 1e-6)
		expect(z).toBeCloseTo(path.lz + path.rz * blocked.stopShare, 1e-6)

		local over = Loot.rollProfile(list, { 8.4, 8.4, 9.2, 9.2, 9.2 }, Config) -- onto the river edge
		expect(over.stopShare).toBe(1)
	end)

	it("sinks at the first point without ground and never rolls past it", function()
		local list = samples()
		local profile = Loot.rollProfile(list, { 8.4, 8.4, 8.4, nil, 8.4 }, Config)
		expect(profile.sinkAt).toBe(list[4].t)
		expect(profile.stopShare).toBe(list[4].share)
	end)

	it("landing in the water sinks at once and has no ground", function()
		local list = samples()
		local profile = Loot.rollProfile(list, {}, Config)
		expect(profile.sinkAt).toBe(Config.fallTime)
		expect(profile.stopShare).toBe(0)
		expect(Loot.groundHeight(profile, 0.5)).toBeNil()
	end)
end)

describe("Spilled scoops: who may pick up", function()
	it("nobody picks it up at once: the owner after 2 s, everybody else after 3 s, set in the config", function()
		expect(Config.ownerLock).toBe(2)
		expect(Config.ownerSeconds).toBe(3)
		local s = scoop(1, 100)
		-- the owner, right where the tower fell, has to wait too: shooting a tower down is worth something
		local ok, reason = Loot.canCollect(s, 1, 100)
		expect(ok).toBe(false)
		expect(reason).toBe("not yet for the owner")
		expect((Loot.canCollect(s, 1, 100 + Config.ownerLock - 0.01))).toBe(false)
		expect((Loot.canCollect(s, 1, 100 + Config.ownerLock))).toBe(true)
		-- everybody else a second later
		expect((Loot.canCollect(s, 2, 100 + Config.ownerLock))).toBe(false)
		expect((Loot.canCollect(s, 2, 100 + Config.ownerSeconds - 0.01))).toBe(false)
		expect((Loot.canCollect(s, 2, 100 + Config.ownerSeconds))).toBe(true)
		expect((Loot.canCollect(s, 1, 100 + Config.ownerSeconds))).toBe(true)
	end)

	it("lights up for each player the moment they may pick it up", function()
		local s = scoop(1, 100)
		expect(Loot.collectableFrom(s, 1)).toBe(100 + Config.ownerLock)
		expect(Loot.collectableFrom(s, 2)).toBe(100 + Config.ownerSeconds)
		-- a knocked-down owner moves the others' moment, not the owner's own
		local down = scoop(1, 100, 101.5)
		expect(Loot.collectableFrom(down, 2)).toBe(101.5 + Config.ownerSeconds)
		expect(Loot.collectableFrom(down, 1)).toBe(100 + Config.ownerLock)
	end)

	it("spreads the scoops out round the tower, not all at the owner's feet", function()
		expect(Config.rollMin >= 4).toBe(true)
		for seed = 1, 20 do
			local paths = spill(12, 0.3, 0.1, seed)
			for _, path in paths do
				local roll = math.sqrt(path.rx * path.rx + path.rz * path.rz)
				expect(roll >= Config.rollMin - 1e-6 and roll <= Config.rollMax + 1e-6).toBe(true)
			end
		end
	end)

	it("starts the head start only once a knocked-down owner is up again", function()
		local s = scoop(1, 100, 101.5)
		expect(s.ownerUntil).toBe(101.5 + Config.ownerSeconds)
		expect(Loot.canCollect(s, 2, 100 + Config.ownerSeconds + 0.5)).toBe(false)
		expect(Loot.canCollect(s, 2, 101.5 + Config.ownerSeconds)).toBe(true)
		-- a knockdown that is already over changes nothing
		expect(scoop(1, 100, 50).ownerUntil).toBe(100 + Config.ownerSeconds)
	end)

	it("nobody picks up a scoop still falling or one that is gone after its lifetime", function()
		local s = scoop(1, 100)
		local ok, reason = Loot.canCollect(s, 2, 99.9)
		expect(ok).toBe(false)
		expect(reason).toBe("still falling")
		local t0 = 100 - Config.fallTime
		expect((Loot.canCollect(s, 1, t0 + Config.lifetime - 0.01))).toBe(true)
		ok, reason = Loot.canCollect(s, 2, t0 + Config.lifetime)
		expect(ok).toBe(false)
		expect(reason).toBe("gone")
	end)

	it("lets an honest player walking over it take it, also with lag, but not from afar", function()
		-- right on top, at the edge, and at the edge with a lagging root at walking speed
		expect(Loot.inReach(0, 0, 0, 0, false, Config)).toBe(true)
		expect(Loot.inReach(Config.pickupRadius, 0, 0, 0, false, Config)).toBe(true)
		expect(Loot.inReach(Config.pickupRadius + 1.5, 0, 0, 18, true, Config)).toBe(true)
		expect(Loot.inReach(Config.pickupRadius + 1.5, 0, 0, 18, false, Config)).toBe(false)
		-- the server's tolerance stays small
		expect(Loot.inReach(Config.pickupRadius + 6, 0, 0, 22.5, true, Config)).toBe(false)
		expect(Loot.inReach(0, Config.pickupHeight + 1, 0, 0, true, Config)).toBe(false)
		expect(Loot.inReach(30, 0, 30, 0, true, Config)).toBe(false)
	end)

	it("never trusts NaN or infinite offsets", function()
		local nan = 0 / 0
		expect(Loot.inReach(nan, 0, 0, 0, true, Config)).toBe(false)
		expect(Loot.inReach(0, math.huge, 0, 0, true, Config)).toBe(false)
		expect(Loot.inReach(0, 0, -math.huge, 0, true, Config)).toBe(false)
	end)
end)

describe("Spilled scoops: at most 40 per server", function()
	it("makes room by dropping the oldest, and never keeps more than 40 of one spill", function()
		local drop, kept = Loot.makeRoom(0, 14, Config)
		expect(drop).toBe(0)
		expect(kept).toBe(14)
		drop, kept = Loot.makeRoom(30, 14, Config)
		expect(drop).toBe(4)
		expect(kept).toBe(14)
		drop, kept = Loot.makeRoom(40, 1, Config)
		expect(drop).toBe(1)
		expect(kept).toBe(1)
		drop, kept = Loot.makeRoom(10, 60, Config)
		expect(drop).toBe(10)
		expect(kept).toBe(Config.maxFree)
	end)
end)

describe("Safe zone at the own cart", function()
	it("protects a player near their own cart from ice-ball harm", function()
		expect(Loot.isShielded(0, 10, 0, Config)).toBe(true)
		expect(Loot.isShielded(Config.safeRadius, 10, 0, Config)).toBe(true)
		expect(Loot.isShielded(Config.safeRadius + 0.1, 10, 0, Config)).toBe(false)
		expect(Loot.isShielded(nil, 10, 0, Config)).toBe(false) -- no cart, no zone
	end)

	it("no camping: a throw from inside the zone lifts the protection for 5 s", function()
		local unshielded = Loot.afterThrow(5, 100, 0, Config)
		expect(unshielded).toBe(100 + Config.unshieldSeconds)
		expect(Loot.isShielded(5, 100 + Config.unshieldSeconds - 0.01, unshielded, Config)).toBe(false)
		expect(Loot.isShielded(5, 100 + Config.unshieldSeconds, unshielded, Config)).toBe(true)
		-- throwing again from the zone starts the 5 s anew
		expect(Loot.afterThrow(5, 103, unshielded, Config)).toBe(103 + Config.unshieldSeconds)
	end)

	it("a throw from outside the zone changes nothing", function()
		expect(Loot.afterThrow(Config.safeRadius + 1, 100, 0, Config)).toBe(0)
		expect(Loot.afterThrow(nil, 100, 42, Config)).toBe(42)
	end)
end)
