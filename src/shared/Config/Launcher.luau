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

	catchRadius = 3.5, -- client: horizontal distance from the tower top
	catchHeight = 2.5, -- client: vertical distance from the tower top
	serverTolerance = 4, -- server: extra studs on top of catchRadius for latency
	serverSpeedLead = 0.15, -- server: seconds of root velocity added to the tolerance
	serverHeightTolerance = 8,
	catchWindow = { 0.45, 1.15 }, -- share of flight time in which a catch counts
	minCatchGap = 0.2, -- seconds between two catches of one player
	resolveAfter = 1.2, -- share of flight time after which an uncaught scoop splats

	goldenChance = 1 / 40, -- used once Features.goldenScoops is on
}
