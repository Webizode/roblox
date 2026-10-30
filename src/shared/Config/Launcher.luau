--!strict
-- The Big Swirl: how often it fires, where it aims and how forgiving catching is.

return {
	baseInterval = 1.5, -- seconds between shots with one player
	minInterval = 0.45,

	-- Where scoops land (TargetRules): most at a random spot in the arena, so nobody gets scoops
	-- thrown at them just for standing around; nearPlayerShare of them near a player who is on the move. A player who
	-- has stayed within idleRadius studs for idleSeconds counts as standing still and gets none aimed at them. Only
	-- players in the arena (Config/Map.arena) get near shots and tutorial shots.
	nearPlayerShare = 0.2,
	-- the random spots, weighted towards the middle: a ring (studs from the machine) is picked by its share, then a spot
	-- in it, all equally likely. No further than about 75 % of the arena radius (135), so the outer arena and the rim
	-- stay the way out
	randomBands = {
		{ inner = 25, outer = 55, share = 0.35 },
		{ inner = 55, outer = 80, share = 0.35 },
		{ inner = 80, outer = 100, share = 0.30 },
	},
	playerOffset = 9, -- max studs from the player a near shot lands
	idleSeconds = 4,
	idleRadius = 2,
	tutorialShots = 3, -- first shots aim right at a new player, once they are in the arena
	tutorialOffset = 1.5,
	-- landing spots are sampled inside this circle around the machine: the arena only, where all scoops land now
	landingRadius = 135,

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
