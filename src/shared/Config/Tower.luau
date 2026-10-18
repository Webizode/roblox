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

	-- Physics profile per variant. padGain multiplies the pad authority above, driftScale the random wandering.
	-- accelSmoothing overrides the movement smoothing per variant.
	-- A balances by walking only. Simulated through the real input path (capped walk speed, 0.25 s reaction) it
	-- held at most 11 scoops with the shared 0.25 s smoothing; with 0.08 s smoothing and extra leverage on
	-- unstable towers it holds about 15, and a full-speed reversal stays below the groan line up to 8 scoops.
	variants = {
		A = { accelGain = 0.025, accelPerInstability = 3, accelSmoothing = 0.08, padGain = 0, driftScale = 0.6 },
		B = { accelGain = 0.02, padGain = 1, driftScale = 1 },
		C = { accelGain = 0.02, padGain = 0.8, driftScale = 1 },
	},

	-- There is no control switch in the HUD. The client picks the scheme by itself, first match wins:
	-- pad (balance pad switched on in Settings), keys (a keyboard is connected), gyro (the device reports
	-- gravity and tilt controls are on in Settings), walk (everything else, e.g. phones without a sensor).
	-- Each scheme runs the physics variant named here.
	controlSchemes = { pad = "B", keys = "B", gyro = "C", walk = "A" },

	-- gyro: device gravity is measured in the phone's own axes. In landscape the long axis runs along the screen,
	-- and LandscapeLeft/Right are 180 degrees apart. The signs below are a best guess and must be checked on a
	-- real phone before the kill test.
	gyroGain = 2.5, -- unit-gravity delta to pad units
	gyroSignX = 1,
	gyroSignY = 1,

	-- keyboard on PC: I/J/K/L push like the pad. Keys ramp up so a tap is a nudge and holding is a full push.
	keyboardPad = true,
	keyRampTime = 0.2, -- seconds from 0 to full deflection
	keyReleaseTime = 0.06, -- seconds from full deflection back to 0

	tiltSendRate = 10, -- Hz, tilt replication for other players
}
