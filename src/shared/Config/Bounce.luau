--!strict
-- The gummy bounce pads in the arena (Arena Kit 2, in Ice Cream Map.Covery): step on one and it throws you up. The
-- client launches at once (Controllers/BounceController) and tells the server, which checks it roughly
-- (Services/BounceService, Bounce.check). Logic in src/shared/Bounce.luau, with tests.
--
-- Heights are where the feet get to, in studs above the floor the pad stands on: the user wanted them much higher
-- (19.11.2026): the GummyPad is a real catapult (22), the GummyBouncer reaches the high covers (from 10.85,
-- Config/Map) too (14). Walking onto a bouncer from its side throws as well. A tower makes it lower
-- (Config/Economy towerSlow.jump, by how full the waffle is). There is no fall damage in the game.

return {
	-- what the pads are: a Model in the cover folder whose name starts like this (the colour variant follows, e.g.
	-- GummyPad_Mint); its parts called Collision or Collision_* are what one stands on
	kinds = {
		{
			prefix = "GummyPad",
			kind = "pad",
		},
		{
			prefix = "GummyBouncer",
			kind = "bouncer",
		},
	},

	pad = {
		apex = 22, -- feet this high above the floor (the pad's pivot) at the top of the jump
		forward = 10, -- studs/s along the way the player looks (or walks), so one can aim the jump
		-- the tower: when a tower lands after this jump it gets a kick in a random direction, kickBase + kickPerScoop
		-- per scoop, at most kickMax (rad/s). Strong, but a standing tower never topples from the jump alone
		-- (tests/Bounce.spec, with the automatic stabiliser only)
		kickBase = 0.3,
		kickPerScoop = 0.03,
		kickMax = 0.9,
		-- tall towers are touchier (the stabiliser holds less), so above tallFrom scoops the kick shrinks by tallFade per
		-- scoop down to tallFloor of it; from about 45 scoops a standing tower needs the steady stance anyway
		tallFrom = 16,
		tallFade = 0.035,
		tallFloor = 0.1,
		squash = 0.55, -- the pad's height share at the deepest point of its squash
	},

	bouncer = {
		apex = 14,
		forward = 6,
		kickBase = 0.15,
		kickPerScoop = 0.015,
		kickMax = 0.45,
		tallFrom = 16,
		tallFade = 0.035,
		tallFloor = 0.1,
		squash = 0.6,
	},

	cooldown = 0.8, -- seconds between two bounces of one player (client)

	-- the look: the pad squashes (its meshes only, the collision stays) and springs back
	squashTime = 0.08, -- seconds down
	springTime = 0.45, -- seconds back up, with an overshoot
	spread = 0.12, -- how much wider it gets at the deepest point
	hearing = 70, -- studs other players hear the boing
	-- placeholder sound (Config/Sounds bounce)

	-- the server's rough check of a bounce the client reports (positions arrive late, so it is generous)
	server = {
		cooldown = 0.6, -- seconds; a bit under the client's, for lag
		reach = 6, -- studs the root may be away from the pad's rim, on the ground plane
		below = 1, -- studs the root may be under the floor the pad stands on
		above = 24, -- studs the root may already be over the pad's top (it rises fast after the launch)
		arenaSlack = 8, -- studs outside the arena that still count (Config/Map arena)
	},
}
