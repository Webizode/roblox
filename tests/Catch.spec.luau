local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local ShotMath = require("../src/shared/ShotMath")
local TowerShape = require("../src/shared/TowerShape")
local CatchRules = require("../src/shared/CatchRules")
local TowerTuning = require("../src/shared/Config/Tower")
local Launcher = require("../src/shared/Config/Launcher")

-- Graybox numbers: nozzle at (0, 26, 0), deck top at y = 1, HumanoidRootPart centre 3 studs above the deck.
local NOZZLE_Y = 26
local GROUND_Y = 1
local ROOT_HEIGHT = 3

local function makeShot(targetX: number, targetZ: number)
	local distance = math.sqrt(targetX * targetX + targetZ * targetZ)
	return {
		fx = 0,
		fy = NOZZLE_Y,
		fz = 0,
		tx = targetX,
		ty = GROUND_Y,
		tz = targetZ,
		apex = ShotMath.apex(distance, Launcher),
		t0 = 100,
		flight = ShotMath.flightTime(distance, Launcher),
	}
end

-- Tower base for a player standing at (x, z) and facing the machine at the origin.
local function baseFacingMachine(x: number, z: number): (number, number, number)
	local length = math.sqrt(x * x + z * z)
	local dirX, dirZ = -x / length, -z / length
	return x + dirX * TowerTuning.catchForward,
		GROUND_Y + ROOT_HEIGHT + TowerTuning.catchUp,
		z + dirZ * TowerTuning.catchForward
end

local function worldColumn(baseX: number, baseY: number, baseZ: number, count: number, tiltX: number, tiltZ: number)
	local offsets = TowerShape.column(count, tiltX, tiltZ, TowerTuning)
	local points = {}
	for index = 1, #offsets, 3 do
		points[index] = baseX + offsets[index]
		points[index + 1] = baseY + offsets[index + 1]
		points[index + 2] = baseZ + offsets[index + 2]
	end
	return points
end

-- The client's catch loop: one sweep per rendered frame from the previous frame's alpha to the current one.
local function clientContact(shot, points, fps: number): number?
	local apexAlpha = ShotMath.apexAlpha(shot.fy, shot.ty, shot.apex)
	local lastAlpha = 0
	local time = shot.t0
	while true do
		time += 1 / fps
		local alpha = (time - shot.t0) / shot.flight
		local from = math.max(lastAlpha, apexAlpha - Launcher.apexSlack)
		local to = math.min(alpha, Launcher.catchWindowEnd)
		local hit = ShotMath.firstContact(shot, from, to, points, Launcher.catchRadius, Launcher.contactStep)
		if hit then
			return hit
		end
		lastAlpha = alpha
		if alpha > Launcher.catchWindowEnd then
			return nil
		end
	end
end

local function towerFor(shot, count: number)
	local baseX, baseY, baseZ = baseFacingMachine(shot.tx, shot.tz)
	return { baseX = baseX, baseY = baseY, baseZ = baseZ, count = count, speed = 0 }
end

describe("Catch geometry", function()
	it("finds the apex of the arc", function()
		local shot = makeShot(60, 0)
		local apexAlpha = ShotMath.apexAlpha(shot.fy, shot.ty, shot.apex)
		local _, atApex = ShotMath.position(shot.fx, shot.fy, shot.fz, shot.tx, shot.ty, shot.tz, shot.apex, apexAlpha)
		for _, delta in { -0.05, 0.05 } do
			local _, around =
				ShotMath.position(shot.fx, shot.fy, shot.fz, shot.tx, shot.ty, shot.tz, shot.apex, apexAlpha + delta)
			expect(atApex).toBeGreaterThan(around)
		end
	end)

	it("rests the bottom scoop in a round opening, neither floating nor sinking through", function()
		local radius = 1.05
		for _, ring in { 0.5, 0.95, 1.2 } do
			local x, y, z = TowerShape.restingBase(4, 10, -2, radius, ring, TowerTuning)
			local ox, oy, oz = TowerShape.offset(1, 1, 0, 0, TowerTuning)
			expect(x + ox).toBeCloseTo(4)
			expect(z + oz).toBeCloseTo(-2)
			-- a ball on a ring touches it: the ring's edge is exactly one radius from the ball's centre
			local seat = y + oy - 10
			if ring < radius then
				expect(math.sqrt(seat * seat + ring * ring)).toBeCloseTo(radius)
				expect(seat).toBeGreaterThan(0)
			else
				expect(seat).toBeCloseTo(0)
			end
		end
		-- the rest of the tower stacks straight up from the bottom scoop
		local _, y = TowerShape.restingBase(0, 0, 0, radius, 0.95, TowerTuning)
		local _, first = TowerShape.offset(1, 3, 0, 0, TowerTuning)
		local _, third = TowerShape.offset(3, 3, 0, 0, TowerTuning)
		expect(third - first).toBeCloseTo(2 * TowerTuning.scoopSpacing)
		expect(y + first).toBeCloseTo(math.sqrt(radius * radius - 0.95 * 0.95))
	end)

	it("builds the column from the cone tip to the free slot", function()
		for _, count in { 0, 1, 2, 7, 20 } do
			local points = TowerShape.column(count, 0.2, -0.1, TowerTuning)
			expect(#points % 3).toBe(0)
			expect(points[2]).toBeCloseTo(TowerTuning.coneHeight)
			local tx, ty, tz = TowerShape.top(count, 0.2, -0.1, TowerTuning)
			expect(points[#points - 2]).toBeCloseTo(tx)
			expect(points[#points - 1]).toBeCloseTo(ty)
			expect(points[#points]).toBeCloseTo(tz)
		end
	end)

	it("measures the distance to a polyline", function()
		local points = { 0, 0, 0, 0, 10, 0 }
		expect(ShotMath.distanceToPolyline(3, 5, 0, points)).toBeCloseTo(3)
		expect(ShotMath.distanceToPolyline(0, 13, 4, points)).toBeCloseTo(5)
		expect(ShotMath.distanceToPolyline(1, 1, 1, { 1, 1, 1 })).toBeCloseTo(0)
	end)

	it("catches scoops that fly into the side of a tower while standing in the landing circle", function()
		-- regression: only the free slot used to count, so from about 4 scoops on the scoop passed through the tower
		for _, distance in { 20, 40, 60, 80 } do
			for _, angle in { 0, 1.1, 2.5 } do
				local shot = makeShot(math.cos(angle) * distance, math.sin(angle) * distance)
				for count = 0, 20, 2 do
					local tower = towerFor(shot, count)
					local points = worldColumn(tower.baseX, tower.baseY, tower.baseZ, count, 0, 0)
					local hit = clientContact(shot, points, 60)
					if not hit then
						error(`no catch at distance {distance}, angle {angle}, {count} scoops`)
					end
				end
			end
		end
	end)

	it("catches the same scoop at 20, 30 and 60 fps", function()
		local shot = makeShot(70, 20)
		local tower = towerFor(shot, 12)
		local points = worldColumn(tower.baseX, tower.baseY, tower.baseZ, 12, 0.15, -0.1)
		local reference = clientContact(shot, points, 240)
		expect(reference ~= nil).toBe(true)
		for _, fps in { 20, 30, 60 } do
			local hit = clientContact(shot, points, fps)
			expect(hit ~= nil).toBe(true)
			-- the sweep samples within each frame, so the touch time does not depend on the frame rate
			expect(math.abs((hit :: number) - (reference :: number)) * shot.flight).toBeLessThan(0.02)
		end
	end)

	it("does not catch a scoop that passes 8 studs beside the tower", function()
		local shot = makeShot(80, 0)
		local tower = towerFor(shot, 10)
		local points = worldColumn(tower.baseX, tower.baseY, tower.baseZ + 8, 10, 0, 0)
		expect(clientContact(shot, points, 60)).toBeNil()
	end)
end)

describe("CatchRules", function()
	local function honestClaim(shot, count: number)
		local tower = towerFor(shot, count)
		local points = worldColumn(tower.baseX, tower.baseY, tower.baseZ, count, 0, 0)
		local hit = clientContact(shot, points, 60)
		assert(hit, "the honest client should catch this scoop")
		return { claimTime = shot.t0 + hit * shot.flight, tiltX = 0, tiltZ = 0 }, tower
	end

	local function check(claim, shot, tower, now)
		return CatchRules.check(claim, shot, tower, now, Launcher, TowerTuning, ShotMath, TowerShape)
	end

	it("accepts honest claims that arrive up to 0.35 s late", function()
		for _, count in { 0, 5, 12, 20 } do
			local shot = makeShot(75, -15)
			local claim, tower = honestClaim(shot, count)
			for _, delay in { 0, 0.1, 0.2, 0.35 } do
				local result = check(claim, shot, tower, claim.claimTime + delay)
				if not result.ok then
					error(`honest claim rejected ({count} scoops, {delay} s late): {result.reason}`)
				end
			end
		end
	end)

	it("accepts a moving player whose replicated position is slightly off", function()
		local shot = makeShot(60, 30)
		local claim, tower = honestClaim(shot, 8)
		tower.speed = 16
		tower.baseX += 1.5 -- replication jitter of the root while walking
		expect(check(claim, shot, tower, claim.claimTime + 0.15).ok).toBe(true)
	end)

	it("rejects a claim from a tower that was nowhere near the scoop", function()
		local shot = makeShot(80, 0)
		local claim, tower = honestClaim(shot, 10)
		tower.baseZ += 10
		local result = check(claim, shot, tower, claim.claimTime + 0.1)
		expect(result.ok).toBe(false)
		expect(result.reason).toBe("too far from the tower")
	end)

	it("caps the replicated speed at 1.25 x WalkSpeed and ignores garbage", function()
		expect(CatchRules.cappedSpeed(3, 4, 18)).toBeCloseTo(5)
		expect(CatchRules.cappedSpeed(1000, 0, 18)).toBeCloseTo(22.5)
		expect(CatchRules.cappedSpeed(0 / 0, 0, 18)).toBe(0)
		expect(CatchRules.cappedSpeed(math.huge, 0, 18)).toBe(0)
		expect(CatchRules.cappedSpeed(10, 0, 0 / 0)).toBe(0)
		expect(CatchRules.cappedSpeed(10, 0, -5)).toBe(0)
	end)

	it("does not let a spoofed speed widen the tolerance beyond the walk-speed cap", function()
		-- an exploiter reporting a velocity of 1000 studs/s, through the same cap LauncherService uses
		local shot = makeShot(80, 0)
		local claim, tower = honestClaim(shot, 10)
		tower.baseZ += 10
		tower.speed = CatchRules.cappedSpeed(1000, 0, 18)
		expect(check(claim, shot, tower, claim.claimTime + 0.1).ok).toBe(false)
	end)

	it("accepts a claim while the server already counts one more scoop than the client", function()
		-- a TowerChanged for the previous catch is still on its way to the client
		local shot = makeShot(70, -25)
		local count = 10
		local tower = towerFor(shot, count)
		local points = worldColumn(tower.baseX, tower.baseY, tower.baseZ, count, 0.2, -0.1)
		local hit = clientContact(shot, points, 60)
		assert(hit, "the honest client should catch this scoop")
		local claim = { claimTime = shot.t0 + hit * shot.flight, tiltX = 0.2, tiltZ = -0.1 }
		tower.count = count + 1
		expect(check(claim, shot, tower, claim.claimTime + 0.15).ok).toBe(true)
	end)

	it("accepts claims exactly at the start of the window with real server clock values", function()
		-- regression: at t0 around 1.76e9 s, t0 + alpha * flight loses precision and came back below the window
		for distance = 20, 80, 5 do
			local shot = makeShot(distance, 0)
			shot.t0 = 1.76e9 + distance * 0.37
			local windowStart = ShotMath.apexAlpha(shot.fy, shot.ty, shot.apex) - Launcher.apexSlack
			local x, y, z =
				ShotMath.position(shot.fx, shot.fy, shot.fz, shot.tx, shot.ty, shot.tz, shot.apex, windowStart)
			local _, slotY = TowerShape.top(0, 0, 0, TowerTuning)
			local tower = { baseX = x, baseY = y - slotY, baseZ = z, count = 0, speed = 0 }
			local claim = { claimTime = shot.t0 + windowStart * shot.flight, tiltX = 0, tiltZ = 0 }
			local result = check(claim, shot, tower, claim.claimTime + 0.1)
			if not result.ok then
				error(`claim at the window start rejected for distance {distance}: {result.reason}`)
			end
		end
	end)

	it("rejects claim times from the future or too far in the past", function()
		local shot = makeShot(80, 0)
		local claim, tower = honestClaim(shot, 6)
		local future = check(claim, shot, tower, claim.claimTime - 0.2)
		expect(future.ok).toBe(false)
		expect(future.reason).toBe("claim time in the future")
		local old = check(claim, shot, tower, claim.claimTime + Launcher.maxClaimAge + 0.05)
		expect(old.ok).toBe(false)
		expect(old.reason).toBe("claim too old")
	end)

	it("rejects claims while the scoop is still rising", function()
		local shot = makeShot(80, 0)
		local claimTime = shot.t0 + 0.1 * shot.flight
		local tower = towerFor(shot, 0)
		local result = check({ claimTime = claimTime, tiltX = 0, tiltZ = 0 }, shot, tower, claimTime + 0.05)
		expect(result.ok).toBe(false)
		expect(result.reason).toBe("scoop still rising")
	end)

	it("rejects malformed arguments", function()
		local shot = makeShot(80, 0)
		local tower = towerFor(shot, 0)
		local now = shot.t0 + shot.flight
		for _, claim in
			{
				{ claimTime = 0 / 0, tiltX = 0, tiltZ = 0 },
				{ claimTime = now, tiltX = math.huge, tiltZ = 0 },
				{ claimTime = "soon", tiltX = 0, tiltZ = 0 },
				{ claimTime = now, tiltX = 0, tiltZ = {} },
			}
		do
			local result = check(claim, shot, tower, now)
			expect(result.ok).toBe(false)
			expect(result.reason).toBe("bad arguments")
		end
	end)

	it("clamps a forged tilt so it cannot stretch the tower towards a far scoop", function()
		-- a 20-scoop tower 25 studs beside the path: only a tilt far past the tip angle would reach the scoop
		local shot = makeShot(80, 0)
		local tower = towerFor(shot, 20)
		tower.baseZ += 25
		local claimTime = shot.t0 + 0.9 * shot.flight
		local result = check({ claimTime = claimTime, tiltX = 0, tiltZ = -5 }, shot, tower, claimTime + 0.05)
		expect(result.ok).toBe(false)
	end)
end)
