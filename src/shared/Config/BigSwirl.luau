--!strict
-- The Big Swirl's six launcher arms (Workspace.Pier.BigSwirl, the model from assets/BigSwirl): every scoop leaves
-- from the arm that points its way. An arm dives into the trough, scoops, swings up, pulls back and whips forward;
-- the scoop shows in the cup from scoopedAt and flies from releaseAt. Every client turns the arms' bones itself, from
-- the cycle baked in Blender (Config/BigSwirlCycle) and the server time a shot leaves, so all players see the same
-- motion and arms moving at once never blend into each other. Times and release points come from the Blender bake
-- (assets/BigSwirl/arm_cycle.json). Without the rig (the bones below) the launcher fires from the Nozzle as before.

return {
	shoulderBone = "Arm%d", -- the bone an arm turns about at the hub
	cycleLength = 3.0, -- seconds at play speed 1
	scoopedAt = 31 / 30, -- the cup leaves the mix with the scoop in it
	releaseAt = 69 / 30, -- the fastest point of the whip: the scoop leaves the cup

	-- where each arm's scoop sits at Release, in the machine's RootPart space (studs); one entry per arm
	releasePoints = {
		{ -24.128, 21.556, 0 },
		{ -12.064, 21.556, 20.896 },
		{ 12.064, 21.556, 20.896 },
		{ 24.128, 21.556, 0 },
		{ 12.064, 21.556, -20.896 },
		{ -12.064, 21.556, -20.896 },
	},
	cupBone = "Arm%d_Cup", -- the bone the scoop rides on until Release
	scoopOffset = { 0, 0, -0.9 }, -- the scoop's centre in that bone's animated space (measured in Studio, all six arms)
	-- the scoop looks this much bigger while it rides in the cup (the cups are built for it, so from afar it reads),
	-- and shrinks to its flying size over shrinkTime after the release
	scoopInCupScale = 1.8,
	shrinkTime = 0.15, -- seconds

	-- an arm only fires the way it points: a target more than maxAngle off its direction waits for another tick
	maxAngle = math.rad(70),
	-- when the launcher fires faster than the arms manage at their own speed, the animation plays faster
	minPlaySpeed = 1,
	maxPlaySpeed = 2,
	speedSlack = 1.15, -- a little quicker than just enough, so an arm is ready again in time
	busyMargin = 0.1, -- seconds an arm rests after its cycle before it scoops again
}
