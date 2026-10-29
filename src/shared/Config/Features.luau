--!strict
-- Feature flags that follow the roadmap. Week 1 only needs the core loop.

return {
	secretStacks = false, -- week 3
	goldenScoops = false, -- week 3
	bump = false, -- week 2
	greg = false, -- week 3
	churn = false, -- week 5
	-- the tower scoops' flight looks (Config/TowerScoops): turning and tipping in flight, the swing back upright when
	-- caught, the trail. Off: a scoop flies upright without a trail (the model and the plop onto the tower stay)
	towerScoopFlight = false,

	-- Temporary diagnostics for the catch fix: the server prints rejected catch claims with the reason (at most one
	-- line per player per second). Turn off once catching is confirmed in Studio.
	debugCatch = true,

	-- Temporary diagnostics for the throw: client and server print each step of a throw (release, accept or the
	-- reason for a reject, start point and speed, and what the ball hit). Turn off once throwing works in Studio.
	debugThrow = true,

	-- Temporary diagnostics for the dash: client and server print each step (request or why none was sent, the
	-- server's grant or reason for a reject, the burst and why it ended). Turn off once the dash works in Studio.
	debugDash = true,
}
