--!strict
-- Ice-ball throw: the only normal attack. Tuning for ammo, flight, hits and the knockdown threshold.

return {
	-- ammo: three throws per load; once all three are gone the load refills after reloadTime. The server owns it.
	ammo = 3,
	reloadTime = 7, -- seconds
	throwInterval = 0.4, -- seconds between two throws, so a macro cannot fire a whole load at once

	-- flight, simulated by the server; clients draw the same curve
	speed = 75, -- studs/s at release
	lift = 0.12, -- added to the aim's vertical part so a straight aim arcs a little
	gravity = 60, -- studs/s^2
	maxFlight = 1.2, -- seconds, about 85 studs of range
	ballRadius = 0.6,

	-- the target: a vertical capsule around the HumanoidRootPart
	hitRadius = 2.2,
	hitHalfHeight = 2.6,

	-- hit power in [minPower, 1]: a centred hit at full speed is 1, a grazing one at the end of its range less
	minPower = 0.5,

	-- player reaction
	knockbackSpeed = 26, -- studs/s away from the thrower, times the hit power
	knockbackUp = 9, -- studs/s
	knockbackTime = 0.15, -- seconds

	-- tower reaction (TowerModel.hitKick): pushed along the ball's flight, corrections weaker for a moment
	towerKickBase = 0.25, -- rad/s at power 1
	towerKickPerScoop = 0.03,
	towerKickMax = 1.0,
	unsteadySeconds = 0.5,
	unsteadyFactor = 0.5,

	-- knockdown: every hit adds its power to a stagger value that drains by staggerDecay per second. A single hit
	-- (power <= 1) never reaches knockdownAt; two solid hits in quick succession do.
	staggerDecay = 0.6,
	knockdownAt = 1.5,
	knockdownTime = 1.5, -- seconds on the ground; no further hits land meanwhile
	knockdownBoost = 1.5, -- knockback and tower kick multiplier for the hit that knocks down
}
