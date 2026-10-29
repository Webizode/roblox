--!strict
-- The Big Swirl: how often it fires, where it aims and how forgiving catching is.

return {
	baseInterval = 1.5, -- seconds between shots with one player
	minInterval = 0.45,

	-- Where scoops land (TargetRules): most at a random spot in the arena and the inner ring, so nobody gets scoops
	-- thrown at them just for standing around; nearPlayerShare of them near a player who is on the move. A player who
	-- has stayed within idleRadius studs for idleSeconds counts as standing still and gets none aimed at them.
	nearPlayerShare = 0.2,
	-- studs from the machine for the random spots: the plaza (the arena, out to 62) and the light path ring round it
	-- (out to the river at 68); the river, the sand ring and the stands only get scoops aimed near a player
	randomRadius = 68,
	playerOffset = 9, -- max studs from the player a near shot lands
	idleSeconds = 4,
	idleRadius = 2,
	tutorialShots = 3, -- first shots aim right at a new player
	tutorialOffset = 1.5,
	-- random targets stay inside this circle around the machine; it reaches past the spawns in front of the stands
	-- (about 83 studs out), so the tutorial shots land right at a new player
	landingRadius = 90,

	flightBase = 1.7, -- seconds
	flightPerStud = 0.012,
	apexBase = 14, -- studs above the straight line
	apexPerStud = 0.08,

	-- Catching: a scoop is caught when its centre comes within catchRadius of the tower column (cone tip to the
	-- free slot on top, see TowerShape.column), checked on the swept path between frames (ShotMath.firstContact).
	-- 3.5 = scoop radius 1 + stack radius 1.05 + 1.45 of forgiveness.
	catchRadius = 3.5,
	contactStep = 0.5, -- studs between path samples, well below the radius so nothing tunnels through

	-- Server check (CatchRules): replays the scoop at the claimed time with the claimed tilt.
	-- serverTolerance only covers what still differs between client and server: the clock estimate of
	-- GetServerTimeNow (~30 ms, about 1.2 studs at scoop speed) and jitter of the replicated root.
	serverTolerance = 1.5,
	serverSpeedLead = 0.15, -- seconds of root speed (capped at 1.25 x WalkSpeed) added for physics replication jitter
	maxClaimAge = 0.4, -- seconds; uplink latency plus a frame for pings up to about 300 ms
	maxClaimLead = 0.05, -- seconds a claim may lie in the future (clock estimate error)
	claimSweep = 0.03, -- seconds around the claimed time the server re-checks
	apexSlack = 0.02, -- catches count from just before the highest point of the arc on
	catchWindowEnd = 1.15, -- share of flight time; a little after landing so a slow claim still counts
	-- seconds between the claimed times of two catches of one player: a sanity bound only, the geometry check is
	-- the real guard, and two scoops can legitimately touch a tower within a fraction of a second
	minCatchGap = 0.05,
	resolveAfter = 1.2, -- share of flight time after which an uncaught scoop splats

	goldenChance = 1 / 40, -- used once Features.goldenScoops is on
}
