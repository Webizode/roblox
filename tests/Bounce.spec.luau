local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local Bounce = require("../src/shared/Bounce")
local Economy = require("../src/shared/Economy")
local TowerModel = require("../src/shared/TowerModel")
local Config = require("../src/shared/Config/Bounce")
local EconomyConfig = require("../src/shared/Config/Economy")
local Flavors = require("../src/shared/Config/Flavors")
local Tuning = require("../src/shared/Config/Tower")

local GRAVITY = 196.2 -- Roblox's default workspace.Gravity
local HIGH_COVER = 10.85 -- the lowest high cover (docs/projektstand.md, 14.11.2026)
local DT = 1 / Tuning.stepRate

-- the feet's highest point above the floor when launched from feetY (the pad's top) with that height share
local function apex(kind, feetY: number, heightScale: number): number
	local _, up = Bounce.launch(kind, GRAVITY, 0, feetY, heightScale, 0, 1)
	return Bounce.apexOf(up, GRAVITY, 0, feetY)
end

-- a standing tower of `count` scoops, kicked once like a landing after a jump, with only the automatic stabiliser
-- (nobody balancing) for `seconds`: whether it stays up
local function standsAfterKick(count: number, seed: number, kick: number, seconds: number): boolean
	local state = TowerModel.newState(seed)
	local params = TowerModel.params(table.create(count, "vanilla"), Flavors.byId, Tuning, 1)
	local angle = seed * 1.7
	TowerModel.impulse(state, math.cos(angle) * kick, math.sin(angle) * kick)
	for _ = 1, seconds / DT do
		local px, pz = TowerModel.assist(state, params, Tuning.variant, Tuning, DT)
		TowerModel.step(state, params, { ax = 0, az = 0, padX = px, padZ = pz }, Tuning.variant, Tuning, DT)
		if state.toppled then
			return false
		end
	end
	return true
end

describe("Bounce pads", function()
	it("knows the pads by their names, colour variants and pressed state included", function()
		expect(Bounce.kindOf("GummyPad_Mint", Config)).toBe("pad")
		expect(Bounce.kindOf("GummyPadPressed_Lemon", Config)).toBe("pad")
		expect(Bounce.kindOf("GummyBouncer_Mint", Config)).toBe("bouncer")
		expect(Bounce.kindOf("CoverBlock_10", Config)).toBeNil()
		expect(Bounce.kindOf("WobbleTower", Config)).toBeNil()
	end)

	it("throws high enough for the high covers from the pad, also with a full tower", function()
		local full = Economy.jumpScale(20, 20, EconomyConfig)
		expect(apex(Config.pad, 1.15, 1)).toBeCloseTo(Config.pad.apex, 1e-6)
		expect(apex(Config.pad, 1.15, full)).toBeGreaterThan(HIGH_COVER + 2)
		expect(apex(Config.pad, 1.15, full)).toBeLessThan(apex(Config.pad, 1.15, 1))
		-- standing on the bear's head (6.3) still ends at the same height
		expect(apex(Config.pad, 6.3, 1)).toBeCloseTo(Config.pad.apex, 1e-6)
	end)

	it(
		"throws from the bouncer onto the high covers too, but less high than the pad, also with a full tower",
		function()
			local full = Economy.jumpScale(65, 65, EconomyConfig)
			expect(apex(Config.bouncer, 1.5, full)).toBeGreaterThan(HIGH_COVER + 1.5)
			expect(apex(Config.bouncer, 1.5, 1)).toBeLessThan(apex(Config.pad, 1.15, 1))
		end
	)

	it("makes a fuller tower jump lower, an empty one full height", function()
		expect(Economy.jumpScale(0, 20, EconomyConfig)).toBe(1)
		expect(Economy.jumpScale(20, 20, EconomyConfig)).toBeCloseTo(1 - EconomyConfig.towerSlow.jump, 1e-9)
		expect(Economy.jumpScale(10, 20, EconomyConfig)).toBeGreaterThan(Economy.jumpScale(20, 20, EconomyConfig))
	end)

	it("pushes a little along the way the player looks, and only up when there is no way", function()
		local vx, vy, vz = Bounce.launch(Config.pad, GRAVITY, 0, 1, 1, 3, 4)
		expect(vx).toBeCloseTo(Config.pad.forward * 0.6, 1e-9)
		expect(vz).toBeCloseTo(Config.pad.forward * 0.8, 1e-9)
		expect(vy).toBeGreaterThan(0)
		local sx, _, sz = Bounce.launch(Config.pad, GRAVITY, 0, 1, 1, 0, 0)
		expect(sx).toBe(0)
		expect(sz).toBe(0)
	end)

	it("lets a player bounce again only after the cooldown", function()
		expect(Bounce.ready(nil, 5, Config.cooldown)).toBe(true)
		expect(Bounce.ready(5, 5.5, Config.cooldown)).toBe(false)
		expect(Bounce.ready(5, 5 + Config.cooldown, Config.cooldown)).toBe(true)
		expect(Bounce.ready(5, 7, Config.cooldown)).toBe(true)
	end)

	it("squashes the pad down, springs it back past rest once and ends at rest", function()
		local h0 = Bounce.squashAt(0, 0.55, Config)
		local hDeep, wDeep = Bounce.squashAt(Config.squashTime, 0.55, Config)
		local lowest = 1
		local highest = 0
		for t = Config.squashTime, Config.squashTime + Config.springTime, 0.01 do
			local h = Bounce.squashAt(t, 0.55, Config)
			lowest = math.min(lowest, h)
			highest = math.max(highest, h)
		end
		local hEnd, wEnd = Bounce.squashAt(Config.squashTime + Config.springTime + 0.01, 0.55, Config)
		expect(h0).toBe(1)
		expect(hDeep).toBeCloseTo(0.55, 1e-6)
		expect(wDeep).toBeCloseTo(1 + Config.spread, 1e-6)
		expect(highest).toBeGreaterThan(1) -- the overshoot
		expect(highest).toBeLessThan(1.2)
		expect(hEnd).toBe(1)
		expect(wEnd).toBe(1)
	end)

	it("kicks a landing tower harder than a dash does, more with more scoops up to a point", function()
		expect(Bounce.towerKick(Config.pad, 0)).toBe(0)
		local dash = math.min(Tuning.dash.kickMax, Tuning.dash.kickBase + Tuning.dash.kickPerScoop * 10)
		expect(Bounce.towerKick(Config.pad, 10)).toBeGreaterThan(dash)
		expect(Bounce.towerKick(Config.pad, 10)).toBeGreaterThan(Bounce.towerKick(Config.pad, 3))
		expect(Bounce.towerKick(Config.bouncer, 10)).toBeLessThan(Bounce.towerKick(Config.pad, 10))
	end)

	it("never topples a standing tower by the landing alone, from 1 to 40 scoops", function()
		for _, kind in { Config.pad, Config.bouncer } do
			for count = 1, 40 do
				for seed = 1, 6 do
					local stands = standsAfterKick(count, seed, Bounce.towerKick(kind, count), 8)
					if not stands then
						error(`a tower of {count} scoops (seed {seed}) toppled after the landing kick`)
					end
				end
			end
		end
	end)

	it("from 41 scoops topples a standing tower only where it would fall without the jump too", function()
		for count = 41, 65 do
			for seed = 1, 6 do
				if standsAfterKick(count, seed, 0, 8) then
					expect(standsAfterKick(count, seed, Bounce.towerKick(Config.pad, count), 8)).toBe(true)
				end
			end
		end
	end)
end)

describe("Bounce pads, the server's check", function()
	local function claim(fields)
		local base = {
			now = 10,
			lastAt = nil,
			alive = true,
			inArena = true,
			distance = 1,
			radius = 3.9,
			height = 5,
			tall = 6.3,
		}
		for key, value in fields do
			base[key] = value
		end
		return base
	end

	it("accepts a player standing on the pad", function()
		expect(Bounce.check(claim({}), Config)).toBe(true)
		expect(Bounce.check(claim({ height = 6.3 + Config.server.above - 1 }), Config)).toBe(true) -- already rising
		expect(Bounce.check(claim({ distance = 3.9 + Config.server.reach - 0.5 }), Config)).toBe(true) -- lag
	end)

	it("refuses a player away from the pad, too high or too low", function()
		local ok, why = Bounce.check(claim({ distance = 3.9 + Config.server.reach + 1 }), Config)
		expect(ok).toBe(false)
		expect(why).toBe("far")
		ok, why = Bounce.check(claim({ height = 6.3 + Config.server.above + 1 }), Config)
		expect(ok).toBe(false)
		expect(why).toBe("height")
		ok, why = Bounce.check(claim({ height = -Config.server.below - 1 }), Config)
		expect(ok).toBe(false)
		expect(why).toBe("height")
	end)

	it("refuses bouncing again within the server's cooldown, a bit shorter than the client's for lag", function()
		expect(Config.server.cooldown).toBeLessThan(Config.cooldown)
		local ok, why = Bounce.check(claim({ lastAt = 9.7 }), Config)
		expect(ok).toBe(false)
		expect(why).toBe("cooldown")
		expect(Bounce.check(claim({ lastAt = 10 - Config.cooldown }), Config)).toBe(true)
	end)

	it("refuses the dead and players outside the arena", function()
		local ok, why = Bounce.check(claim({ alive = false }), Config)
		expect(ok).toBe(false)
		expect(why).toBe("dead")
		ok, why = Bounce.check(claim({ inArena = false }), Config)
		expect(ok).toBe(false)
		expect(why).toBe("arena")
	end)
end)

-- Team test of 20.11.2026: a bouncer stayed bigger for good after being jumped on. The client works every frame of a
-- squash out from the mesh's size at rest (Bounce.poseSize with Bounce.squashAt), like BounceController.step does; this
-- runs that loop with many players landing at once and in quick succession.
describe("A bounce pad's squash always comes back to its size at rest", function()
	local REST = { 4.2, 1.3, 4.2 }

	-- BounceController's loop: a squash restarts at every landing (squashFrom), each frame poses from the rest size,
	-- and when the squash is over it is posed at 1, 1. Returns the size after `seconds`, and the largest seen.
	local function run(landings: { number }, seconds: number, depth: number)
		local squashFrom: number? = nil
		local size = { REST[1], REST[2], REST[3] }
		local widest = 0
		local next = 1
		table.sort(landings)
		local dt = 1 / 60
		for frame = 0, math.floor(seconds / dt) do
			local now = frame * dt
			while landings[next] and landings[next] <= now do
				squashFrom = landings[next] -- several in one frame: the last one counts, nothing adds up
				next += 1
			end
			if squashFrom then
				local t = now - squashFrom
				local height, width = Bounce.squashAt(t, depth, Config)
				size[1], size[2], size[3] = Bounce.poseSize(REST[1], REST[2], REST[3], height, width)
				if t > Config.squashTime + Config.springTime then
					squashFrom = nil
					size[1], size[2], size[3] = Bounce.poseSize(REST[1], REST[2], REST[3], 1, 1)
				end
			end
			widest = math.max(widest, size[1])
		end
		return size, widest
	end

	it("is back at exactly its rest size after 200 landings of many players, also several in one frame", function()
		for _, kind in { "pad", "bouncer" } do
			local depth = (Config :: any)[kind].squash
			local landings = {}
			local seed = 7
			for _ = 1, 200 do
				seed = (seed * 1103515245 + 12345) % 2147483648
				table.insert(landings, (seed % 3000) / 100) -- 200 landings in 30 s, many overlapping
			end
			for _ = 1, 5 do
				table.insert(landings, 12.5) -- five players in the same frame
			end
			local size, widest = run(landings, 32, depth)
			expect(size[1]).toBe(REST[1])
			expect(size[2]).toBe(REST[2])
			expect(size[3]).toBe(REST[3])
			-- and never wider than one squash makes it, however they overlap
			expect(widest <= REST[1] * (1 + Config.spread) + 1e-9).toBe(true)
		end
	end)

	it("a squash ends exactly at rest, and starts from it", function()
		local height, width = Bounce.squashAt(0, 0.55, Config)
		expect(height).toBe(1)
		expect(width).toBe(1)
		height, width = Bounce.squashAt(Config.squashTime + Config.springTime, 0.55, Config)
		expect(height).toBe(1)
		expect(width).toBe(1)
		local x, y, z = Bounce.poseSize(2, 3, 4, 1, 1)
		expect(x).toBe(2)
		expect(y).toBe(3)
		expect(z).toBe(4)
	end)
end)
