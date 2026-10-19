local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local ThrowPose = require("../src/shared/ThrowPose")
local Config = require("../src/shared/Config/Combat")

local poses = Config.throwAnimation.poses

local function same(a, b)
	expect(a.shoulder).toBeCloseTo(b.shoulder, 1e-6)
	expect(a.elbow).toBeCloseTo(b.elbow, 1e-6)
	expect(a.waist).toBeCloseTo(b.waist, 1e-6)
end

describe("Throw pose", function()
	it("winds up from the stance and holds the wind-up while charging", function()
		same(ThrowPose.charge(0, Config), poses.stance)
		same(ThrowPose.charge(Config.throwAnimation.windupTime, Config), poses.windup)
		same(ThrowPose.charge(5, Config), poses.windup)
		local halfway = ThrowPose.charge(Config.throwAnimation.windupTime / 2, Config)
		expect(halfway.shoulder > poses.stance.shoulder and halfway.shoulder < poses.windup.shoulder).toBe(true)
	end)

	it("releases exactly at releaseDelay, when the server starts the ball", function()
		local start, running = ThrowPose.throw(0, Config)
		same(start, poses.windup)
		expect(running).toBe(true)
		same((ThrowPose.throw(Config.releaseDelay, Config)), poses.release)
		-- the swing speeds up towards the release: the second half covers more than the first
		local quarter = (ThrowPose.throw(Config.releaseDelay / 2, Config)).shoulder
		expect(poses.windup.shoulder - quarter).toBeLessThan(quarter - poses.release.shoulder)
	end)

	it("swings through and comes back to the stance, then ends", function()
		local follow = Config.releaseDelay + Config.throwAnimation.followTime
		same((ThrowPose.throw(follow, Config)), poses.follow)
		local done, running = ThrowPose.throw(ThrowPose.throwLength(Config) + 0.01, Config)
		same(done, poses.stance)
		expect(running).toBe(false)
		-- the arm keeps moving forward through the release (no snap back)
		local last = math.huge
		for t = 0, follow, 0.01 do
			local shoulder = (ThrowPose.throw(t, Config)).shoulder
			expect(shoulder <= last + 1e-9).toBe(true)
			last = shoulder
		end
	end)
end)
