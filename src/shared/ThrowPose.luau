--!strict
-- Pure maths for the throw pose: the angles of the right shoulder (forward swing and out to the side), the right
-- elbow, the right wrist and the waist over a charge and a throw, from the poses in Config/Combat (throwAnimation).
-- The stance presents the ball: the forearm raised, the hand flat with its palm up, the ball floating above it.
-- ThrowAnimator draws them on every character while no animation ids are set (R15 with all joints, R6 with its one
-- shoulder, see singleArm), and scripts/throw-animation.luau bakes the same poses into keyframes. No Roblox globals.

export type Pose = { shoulder: number, out: number, elbow: number, wrist: number, twist: number, waist: number }

export type Config = {
	releaseDelay: number,
	throwAnimation: {
		windupTime: number,
		followTime: number,
		recoverTime: number,
		poses: { stance: Pose, windup: Pose, release: Pose, follow: Pose },
	},
}

local ThrowPose = {}

local function easeOut(alpha: number): number
	local inverse = 1 - alpha
	return 1 - inverse * inverse
end

local function easeIn(alpha: number): number
	return alpha * alpha
end

function ThrowPose.blend(from: Pose, to: Pose, alpha: number): Pose
	alpha = math.clamp(alpha, 0, 1)
	return {
		shoulder = from.shoulder + (to.shoulder - from.shoulder) * alpha,
		out = from.out + (to.out - from.out) * alpha,
		elbow = from.elbow + (to.elbow - from.elbow) * alpha,
		wrist = from.wrist + (to.wrist - from.wrist) * alpha,
		twist = from.twist + (to.twist - from.twist) * alpha,
		waist = from.waist + (to.waist - from.waist) * alpha,
	}
end

-- Holding the throw button for `held` seconds: from the stance into the wind-up, then held there.
function ThrowPose.charge(held: number, config: Config): Pose
	local animation = config.throwAnimation
	return ThrowPose.blend(
		animation.poses.stance,
		animation.poses.windup,
		easeOut(math.clamp(held / animation.windupTime, 0, 1))
	)
end

-- `since` seconds after the button-up: the explosive swing from the wind-up to the release (reached exactly at
-- releaseDelay, when the ball leaves the hand), the follow-through, and back to the stance. The second value is
-- false once the throw is over.
function ThrowPose.throw(since: number, config: Config): (Pose, boolean)
	local animation = config.throwAnimation
	local poses = animation.poses
	if since < config.releaseDelay then
		return ThrowPose.blend(poses.windup, poses.release, easeIn(math.max(0, since) / config.releaseDelay)), true
	end
	since -= config.releaseDelay
	if since < animation.followTime then
		return ThrowPose.blend(poses.release, poses.follow, easeOut(since / animation.followTime)), true
	end
	since -= animation.followTime
	if since < animation.recoverTime then
		return ThrowPose.blend(poses.follow, poses.stance, easeOut(since / animation.recoverTime)), true
	end
	return poses.stance, false
end

-- The whole throw, from the button-up to the stance again.
function ThrowPose.throwLength(config: Config): number
	local animation = config.throwAnimation
	return config.releaseDelay + animation.followTime + animation.recoverTime
end

-- R6 has one stiff arm without an elbow: its forward swing points the whole arm halfway between the upper arm and
-- the forearm of the R15 pose, so the hand end lands about where the R15 hand is.
function ThrowPose.singleArm(pose: Pose): number
	return pose.shoulder + pose.elbow / 2
end

return ThrowPose
