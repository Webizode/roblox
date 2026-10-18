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

	-- dynamics: tilt'' = gravity*sin(tilt) - stiffness*tilt - damping*tilt' - accelGain*accel + padGain*pad + drift
	gravityGain = 1.0, -- per centre-of-mass index, so taller towers get more unstable
	baseStiffness = 5.5, -- about where ten classic scoops become self-unstable
	baseDamping = 1.8,
	minDamping = 0.4,
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

	variants = {
		A = { label = "Joystick", accelGain = 0.05, padGain = 0, usesPad = false, usesGyro = false },
		B = { label = "Balance Pad", accelGain = 0.02, padGain = 9, usesPad = true, usesGyro = false },
		C = { label = "Gyro", accelGain = 0.02, padGain = 7, usesPad = false, usesGyro = true },
	},
	defaultVariant = "B",

	gyroGain = 2.5, -- device gravity delta to pad units
	keyboardPad = true, -- I/J/K/L drive the pad on PC

	tiltSendRate = 10, -- Hz, tilt replication for other players
}
