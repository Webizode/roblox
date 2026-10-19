--!strict
-- Tuning for the wobble tower. Everything the kill test in week 1 might want to change lives here.

return {
	stepRate = 60, -- fixed simulation steps per second

	-- shape
	scoopSpacing = 1.5, -- studs between scoop centres
	coneHeight = 1.6,
	holdUp = 0.6, -- tower base relative to the HumanoidRootPart
	holdForward = 2.2,

	-- tipping
	tipAngle = 0.55, -- radians at the top before the tower is clamped
	groanFraction = 0.8, -- above this share of tipAngle the tower groans
	groanDuration = 0.5, -- seconds of groaning before it topples

	-- dynamics: tilt'' = gravity*sin(tilt) - stiffness*tilt - damping*tilt' - accelGain*accel + padAuthority*pad + drift
	gravityGain = 1.0, -- per centre-of-mass index, so taller towers get more unstable
	baseStiffness = 5.5, -- about where ten classic scoops become self-unstable
	baseDamping = 1.8,
	minDamping = 0.4,
	-- padAuthority = variant.padGain * (padBase + padPerInstability * max(0, gravity - stiffness)), in rad/s^2.
	-- padBase keeps a held key from pushing a short tower past the groan line (steady lean = padBase / restoring
	-- stiffness, e.g. 1.0 / 4.5 = 0.22 rad for one scoop). padPerInstability gives tall towers the leverage they
	-- need: about 9.5 at 20 scoops, as strong as the old fixed pad (9). padMax caps it there so very tall towers
	-- keep a skill ceiling: in simulation no 0.2 s controller holds 40 scoops on a starter cone.
	padBase = 1.0,
	padPerInstability = 1.7,
	padMax = 10,
	-- Share of that authority for input that does not reduce the current lean (pushing an upright tower, pushing
	-- with the lean, sideways). The stabiliser and the rescue act through this, so they cannot push a tower over.
	padWrongWay = 0.35,
	driftStartScoops = 10, -- below this the tower never wanders on its own
	driftPerScoop = 0.12, -- rad/s^2 of slow wandering per scoop above the start
	jerkInterval = 0.9, -- seconds between cursed pickle kicks
	jerkStrength = 0.35, -- rad/s per unit of flavor jerk
	landingKick = 0.12, -- rad/s nudge every time a scoop lands

	steady = {
		minScoops = 10, -- steady time only counts once the tower drifts by itself
		fraction = 0.25, -- tilt below this share of tipAngle counts as steady
		ratePerSecond = 0.05,
		max = 0.25,
	},

	accelSmoothing = 0.25, -- seconds, MoveDirection lerp that feeds the tower instead of raw Humanoid velocity

	-- Physics profile. padGain multiplies the pad authority above (the stabiliser and the rescue act through it),
	-- driftScale the random wandering.
	variant = { accelGain = 0.02, padGain = 1, driftScale = 1 },

	-- Automatic stabiliser (TowerModel.assist), a PD controller on the lean that is deliberately imperfect: it sees
	-- the lean smoothed over `lag` seconds, uses at most `strength` of the pad, gives up between fadeFrom and fadeTo
	-- of the tip angle, and gets weaker from fullUntil scoops to `floor` of its strength at zeroAt scoops.
	-- In simulation (no player input at all): standing still, towers of up to 20 scoops stay up for 60 s; walking
	-- with a full-speed 90 degree turn every 1.5 s peaks at about 30 % of the tip angle up to 9 scoops, 47 % at 11,
	-- risks a topple from 13 and needs rescues from 15.
	assist = {
		kp = 2.0,
		kd = 0.6,
		lag = 0.35,
		strength = 0.35,
		fadeFrom = 0.3,
		fadeTo = 0.6,
		fullUntil = 2,
		zeroAt = 20,
		floor = 0.55,
	},

	-- Rescue (F on PC, Steady button on touch): full pad strength against the real lean, without the stabiliser's
	-- delay, for `duration` seconds. The next one is allowed `cooldown` seconds after it ends; the server checks it.
	-- Its push is capped at `authority` rad/s^2 (tall towers otherwise get up to padMax), so it can fail: in
	-- simulation 60-75 % leans are saved, a tall tower groaning near the tip angle with momentum is not.
	rescue = { duration = 1.5, cooldown = 6, authority = 4 },
	warnFraction = 0.6, -- from this share of the tip angle the HUD warns (the stabiliser has given up by then)

	tiltSendRate = 10, -- Hz, tilt replication for other players

	-- Dash (Q on PC, a dash button on touch): a short burst in the move direction that ends with a hard stop back to
	-- walking (or sprinting) speed, so nothing slides on after it. Distance = speed x duration. The server checks the
	-- cooldown. The cone is yanked forward, so the tower gets a tilt-rate kick against the dash direction that grows
	-- with its height: a tower leaning into the dash is pushed upright, one already leaning back can go over.
	dash = {
		cooldown = 4, -- seconds
		speed = 80, -- studs/s during the burst
		duration = 0.125, -- seconds; 10 studs, the same distance as before
		acceleration = 6000, -- studs/s^2 the burst may push with, so it is at full speed within a frame or two
		kickBase = 0.2, -- rad/s
		kickPerScoop = 0.03, -- rad/s per scoop
		kickMax = 0.9, -- rad/s
		unsteadySeconds = 0.6, -- afterwards pad and walking corrections are weaker for this long
		unsteadyFactor = 0.3, -- share of the normal correction strength during that window
	},
}
