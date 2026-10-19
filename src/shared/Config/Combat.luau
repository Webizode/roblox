--!strict
-- Ice-ball throw: the only normal attack. Tuning for ammo, flight, hits and the knockdown threshold.

return {
	-- combat mode (R): only in it can a player charge and throw. Switching on is rate-limited, off always works.
	combatModeInterval = 0.2, -- seconds

	-- ammo: three throws per load; once all three are gone the load refills after reloadTime. The server owns it.
	ammo = 3,
	reloadTime = 7, -- seconds
	throwInterval = 0.4, -- seconds between two throws, so a macro cannot fire a whole load at once

	-- throw strength: holding the throw button charges a bar that runs from 0 up to 1 in chargeRise seconds, back
	-- down in the same time, and so on while held. Releasing throws with the bar's value: 0 is the weakest throw,
	-- 1 the strongest. The server measures the hold itself and only accepts a bar value that fits it.
	chargeRise = 0.9, -- seconds
	chargeTolerance = 0.1, -- seconds of network jitter between the server's measured hold and the client's bar
	minSpeed = 55, -- studs/s at release with the bar at 0
	maxSpeed = 90, -- and at 1
	powerAtMinCharge = 0.6, -- hit power factor of an uncharged throw; a full charge hits with factor 1

	-- aiming: the ball leaves the right hand and flies on an arc through the point under the crosshair
	aimDistance = 400, -- studs the client looks for that point along the crosshair ray
	handReach = 4, -- studs; a hand farther from the HumanoidRootPart is not trusted as the release point

	-- the ball in the hand (HeldBalls), drawn for every player in combat mode; purely visual
	held = {
		popIn = 0.2, -- seconds for the next ball to appear after a throw or a refill
		popOut = 0.08, -- seconds for the last ball to vanish from the hand
		frostMax = 0.85, -- share of the ball size a refilling frost ball reaches; it grows from zero over the reload
		frostTransparency = 0.55,
		drawDistance = 200, -- studs from the camera
	},

	-- flight, simulated by the server; clients draw the same curve
	lift = 0.12, -- a target out of reach gets a straight aim plus this much upward, so it arcs a little
	gravity = 60, -- studs/s^2
	maxFlight = 1.2, -- seconds
	ballRadius = 0.6,

	-- the target: a vertical capsule around the HumanoidRootPart
	hitRadius = 2.2,
	hitHalfHeight = 2.6,

	-- hit power: a centred hit at full charge is 1, a grazing, slowed-down or uncharged one less
	minPower = 0.5,

	-- player reaction
	knockbackSpeed = 26, -- studs/s away from the thrower, times the hit power (so a charged throw pushes harder)
	knockbackUp = 9, -- studs/s
	knockbackTime = 0.15, -- seconds

	-- tower reaction (TowerModel.hitKick): pushed along the ball's flight, corrections weaker for a moment
	towerKickBase = 0.25, -- rad/s at power 1
	towerKickPerScoop = 0.03,
	towerKickMax = 1.0,
	unsteadySeconds = 0.5,
	unsteadyFactor = 0.5,

	-- knockdown: every hit adds its power to a stagger value that drains by staggerDecay per second. A single hit
	-- (power <= 1) never reaches knockdownAt; two solid, well-charged hits in quick succession do.
	staggerDecay = 0.6,
	knockdownAt = 1.5,
	knockdownTime = 1.5, -- seconds on the ground; no further hits land meanwhile
	knockdownBoost = 1.5, -- knockback and tower kick multiplier for the hit that knocks down
}
