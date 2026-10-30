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

	-- Studio test mode for the 12-player map (DebugDummies, Studio only): this many players in all, you included; the
	-- rest are simulated. They take the last plots, count for the fire rate and the near shots, run for scoops they
	-- can reach in time and serve at their plot. Landings show as discs, a summary goes to the output every 30 s and
	-- to ServerStorage.DebugDummiesLog. 0 is off.
	debugPlayers = 0,
	-- the name, tower and catches over every dummy; also switchable while playing (attribute Labels on
	-- Workspace.DebugDummies)
	debugDummyLabels = true,

	-- Draws the arena zone (ArenaZone, Config/Map.arena: the floor and the ramps up to their top edge) half transparent,
	-- to check where the safe zone starts. Client only, for testing.
	debugArenaZone = false,

	-- Studio stopwatch (WalkTimer, Studio only): prints the time from your last pickup to your own plot, and once at
	-- the start walks test figures from their plot out to the Big Swirl (sprint) and from set and random landing spots
	-- home (without a tower and with 36 scoops; ServerStorage.WalkTimerLog).
	debugWalkTimer = false,

	-- Temporary diagnostics for the dash: client and server print each step (request or why none was sent, the
	-- server's grant or reason for a reject, the burst and why it ended). Turn off once the dash works in Studio.
	debugDash = true,
}
