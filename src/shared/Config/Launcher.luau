--!strict
-- The Big Swirl: how often it fires, where it aims and how forgiving catching is.

return {
	baseInterval = 1.5, -- seconds between shots with one player
	minInterval = 0.45,

	-- Where scoops land (TargetRules): a random spot of the whole arena, every landing spot (Config/Map landing: ground a
	-- player can stand on, never cover, walls or water) equally likely, so they spread evenly, to the rim and behind
	-- cover too. Since the kill test of 13.11.2026 none are aimed at players any more (nearPlayerShare was 0.2, and the
	-- spots were weighted towards the middle and kept within 100 studs). Only a new player's first tutorialShots still
	-- come down at them, once they are in the arena. A player who has stayed within idleRadius studs for idleSeconds
	-- counts as standing still (for nearPlayerShare above 0).
	nearPlayerShare = 0,
	-- one ring from just outside the machine's trough to the arena's edge: a spot in it, all equally likely
	randomBands = {
		{ inner = 28, outer = 135, share = 1 },
	},
	playerOffset = 9, -- max studs from the player a near shot lands
	idleSeconds = 4,
	idleRadius = 2,
	tutorialShots = 3, -- first shots aim right at a new player, once they are in the arena
	tutorialOffset = 1.5,
	-- landing spots are sampled inside this circle around the machine: the arena only, where all scoops land now
	landingRadius = 135,

	-- the flight: shorter since the kill test of 13.11.2026 (1.7 s + 0.012 per stud, apex 14 + 0.08 per stud): 1.5 s
	-- to a spot 60 studs away instead of 2.4 s, 2.1 s to the arena's edge instead of 3.3 s
	flightBase = 1.0, -- seconds
	flightPerStud = 0.008,
	apexBase = 10, -- studs above the straight line
	apexPerStud = 0.06,

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
