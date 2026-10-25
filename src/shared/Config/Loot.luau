--!strict
-- Spilled scoops: what a toppled tower drops, who may pick it up, for how long, and the safe zone at the own cart.
-- The server owns all of it (LootService); clients draw the scoops with the same numbers (Loot.position).

return {
	-- who may pick up: for ownerSeconds only the owner, counted from the moment the owner can act again (landing,
	-- or the end of a knockdown that is still running), then everybody
	ownerSeconds = 3,
	lifetime = 12, -- seconds from the topple until an uncollected scoop disappears
	blinkSeconds = 2, -- it blinks for this long before it disappears
	maxFree = 40, -- free scoops per server; a new spill pushes the oldest ones out

	-- the way down: from where the scoop sat in the toppled tower to the ground, then a short roll away from it
	fallTime = 0.35, -- seconds; picking up starts once it landed
	rollMin = 2, -- studs
	rollMax = 4,
	rollSpread = math.rad(50), -- the roll leaves along the lean, give or take this much
	rollDecay = 4, -- 1/s; the roll slows down exponentially, 98 % done after a second
	waterSamples = 4, -- points along the roll the server checks for ground, so a scoop rolling off the pier sinks

	-- picking up: walking over a scoop, measured from the character's root on the ground plane
	pickupRadius = 3,
	pickupHeight = 6, -- studs above or below the root still counted (a scoop on a step)
	-- the server's check adds what differs between client and server, like the catch check (Config/Launcher)
	serverTolerance = 1.5,
	serverSpeedLead = 0.15, -- seconds of root speed (capped at 1.25 x WalkSpeed)
	maxClaimsPerSecond = 20, -- per player; more are dropped unread (a spam guard, walking through a heap needs a few)

	scoopRadius = 1, -- drawn scoop, a little smaller than one on a tower
	ringSize = 3.2, -- the owner's glow under a reserved scoop

	-- the safe zone around the own cart: ice-ball hits there do no harm. A player who throws from inside it loses the
	-- protection for unshieldSeconds, so nobody camps at the cart and shoots out of it.
	safeRadius = 14, -- studs around the cart's ServePoint (the serve radius is 8)
	unshieldSeconds = 5,
}
