--!strict
-- "Wanted" (stolen goods, since the multi-player test of 16.11.2026): picking up scoops another player spilled (a
-- topple or a knockdown) makes the picker wanted for `duration` seconds; Big Swirl scoops never do. Every further
-- stolen scoop starts the time over. While wanted: no leaving the arena (the ramps stop short of their top edge), no
-- teleport, no serving. Getting knocked down or toppling with scoops lost ends it. WantedService decides, Wanted holds
-- the rules, the Wanted controller draws it.

return {
	duration = 10, -- seconds, from the last stolen scoop

	-- The edge: up a ramp the wanted player is pushed back stopShort studs before the ramp's top edge (rampTop), at
	-- pushSpeed studs/s towards the nearest allowed point (their own client, so it feels soft). The server sees the
	-- position a little late and trusts no client: beyond serverSlack studs past that line it puts the character back
	-- pullBack studs inside it. Farther out than maxPull it leaves them be (not something a ramp run can do).
	stopShort = 4, -- studs before rampTop
	pushSpeed = 22, -- studs/s, a little faster than a sprint, so walking on gets nowhere
	serverSlack = 6, -- studs
	pullBack = 3, -- studs
	maxPull = 40, -- studs

	-- the hint to the wanted player while pushed back or turned away (a toast), at most every hintEvery seconds
	hintEvery = 1.5,

	-- what everybody sees over a wanted player: a red badge with the seconds left, always on top
	badge = {
		height = 4.2, -- studs above the head's centre
		width = 3.4, -- studs (BillboardGui size in studs, so it shrinks with distance)
		maxDistance = 250, -- studs from the camera
		pulse = 2.2, -- pulses per second
	},
	-- and the soft red glow at their tower
	glow = { color = "#FF2E3B", brightness = 2.2, range = 9, up = 3, back = 2.2, pulse = 1.6 },

	-- the wanted player's own HUD line "WANTED 7"
	hud = { textSize = 40, fromTop = 0.2 }, -- design pixels; share of the screen height from the top
}
