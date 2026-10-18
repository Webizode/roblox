--!strict
-- The Big Swirl: how often it fires, where it aims and how forgiving catching is.

return {
	baseInterval = 1.5, -- seconds between shots with one player
	minInterval = 0.45,

	targetPlayerChance = 0.6, -- otherwise a random spot on the pier
	playerOffset = 9, -- max studs from the targeted player
	tutorialShots = 3, -- first shots aim right at a new player
	tutorialOffset = 1.5,
	landingRadius = 80, -- random targets stay inside this circle around the machine

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
