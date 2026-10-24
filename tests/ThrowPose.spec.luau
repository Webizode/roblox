local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local ThrowPose = require("../src/shared/ThrowPose")
local Config = require("../src/shared/Config/Combat")

local poses = Config.throwAnimation.poses

local function same(a, b)
	expect(a.shoulder).toBeCloseTo(b.shoulder, 1e-6)
	expect(a.out).toBeCloseTo(b.out, 1e-6)
	expect(a.elbow).toBeCloseTo(b.elbow, 1e-6)
	expect(a.wrist).toBeCloseTo(b.wrist, 1e-6)
	expect(a.twist).toBeCloseTo(b.twist, 1e-6)
	expect(a.waist).toBeCloseTo(b.waist, 1e-6)
end

-- The R15 hand's flat side faces up when the upper arm, the forearm and the hand together have swung half a turn.
local function palmTilt(pose): number
	return pose.shoulder + pose.elbow + pose.wrist - 180
end

describe("Throw pose", function()
	it("presents the ball on a flat, raised hand", function()
		expect(math.abs(palmTilt(poses.stance))).toBeLessThan(1e-6)
		-- the forearm points up and forward, the upper arm hangs forward
		expect(poses.stance.shoulder + poses.stance.elbow).toBeGreaterThan(90)
		expect(poses.stance.shoulder).toBeLessThan(90)
	end)

	it("keeps the presenting hand through the charge and only coils the waist", function()
		same(ThrowPose.charge(0, Config), poses.stance)
		same(ThrowPose.charge(Config.throwAnimation.windupTime, Config), poses.windup)
		same(ThrowPose.charge(5, Config), poses.windup)
		for held = 0, Config.throwAnimation.windupTime, 0.01 do
			local pose = ThrowPose.charge(held, Config)
			expect(pose.shoulder).toBeCloseTo(poses.stance.shoulder, 1e-6)
			expect(pose.elbow).toBeCloseTo(poses.stance.elbow, 1e-6)
			expect(pose.wrist).toBeCloseTo(poses.stance.wrist, 1e-6)
			expect(pose.twist).toBeCloseTo(poses.stance.twist, 1e-6)
		end
		local halfway = ThrowPose.charge(Config.throwAnimation.windupTime / 2, Config)
		expect(halfway.waist < poses.stance.waist and halfway.waist > poses.windup.waist).toBe(true)
	end)

	it("releases exactly at releaseDelay, when the server starts the ball", function()
		local start, running = ThrowPose.throw(0, Config)
		same(start, poses.windup)
		expect(running).toBe(true)
		same((ThrowPose.throw(Config.releaseDelay, Config)), poses.release)
		-- the push speeds up towards the release: the second half covers more than the first
		local quarter = (ThrowPose.throw(Config.releaseDelay / 2, Config)).shoulder
		expect(quarter - poses.windup.shoulder).toBeLessThan(poses.release.shoulder - quarter)
	end)

	it("pushes the arm forward up to the release, swings through and comes back to the stance", function()
		local last = -math.huge
		for t = 0, Config.releaseDelay, 0.005 do
			local shoulder = (ThrowPose.throw(t, Config)).shoulder
			expect(shoulder >= last - 1e-9).toBe(true)
			last = shoulder
		end
		local follow = Config.releaseDelay + Config.throwAnimation.followTime
		same((ThrowPose.throw(follow, Config)), poses.follow)
		local done, running = ThrowPose.throw(ThrowPose.throwLength(Config) + 0.01, Config)
		same(done, poses.stance)
		expect(running).toBe(false)
	end)

	it("swings R6's one arm between the R15 upper arm and forearm", function()
		local single = ThrowPose.singleArm(poses.stance)
		expect(single).toBeGreaterThan(poses.stance.shoulder)
		expect(single).toBeLessThan(poses.stance.shoulder + poses.stance.elbow)
		expect(ThrowPose.singleArm(poses.release)).toBeGreaterThan(single)
	end)
end)
