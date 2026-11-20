--!strict
-- Spilled scoops: what a toppled or knocked-down tower drops, who may pick it up, for how long, and the safe zone at the own cart.
-- The server owns all of it (LootService); clients draw the scoops with the same numbers (Loot.position).

return {
	-- who may pick up, in seconds after the landing: the owner from ownerLock on (0: at once, as soon as they are up
	-- again), everybody else from othersLock on. Test of 14.11.2026: with no wait at all the others took a knocked-down
	-- player's scoops before they could even get up; 13.11.2026 both were 0, before that owner 2 s, others 3 s.
	ownerLock = 0,
	othersLock = 0.5,
	-- seconds from the topple until an uncollected scoop disappears with a puff. 20 since the team test of 20.11.2026
	-- (10 before: even with two dashes one hardly got there in time)
	lifetime = 20,
	blinkSeconds = 3, -- it blinks for this long before it disappears, so one sees it is about to go (1 until 20.11.2026)
	-- a client that has not heard of the removal this long after the end removes the scoop itself (it can no longer be
	-- picked up anyway, Loot.canCollect), so no scoop stays lying around for good
	expireGrace = 1, -- seconds
	fullNotice = 3, -- seconds between two "cone full" notes while standing on scoops the full cone cannot take
	maxFree = 40, -- free scoops per server; a new spill pushes the oldest ones out

	-- A scoop from the Big Swirl that nobody caught lies where it landed for landedLifetime seconds and anybody may pick
	-- it up (no owner), blinks for the last landedBlinkSeconds and goes with a puff. One that lands in the water is
	-- gone at once. These never push spilled scoops out: they have their own limit.
	landedLifetime = 3,
	landedBlinkSeconds = 1,
	maxLanded = 16,

	-- the way down: from where the scoop sat in the toppled tower to the ground, then a short roll away from it
	fallTime = 0.35, -- seconds; picking up starts once it landed
	-- spread out round the toppled tower, so the owner cannot gather everything from where they stand
	rollMin = 4, -- studs
	rollMax = 8,
	rollSpread = math.rad(50), -- the roll leaves along the lean, give or take this much
	rollDecay = 4, -- 1/s; the roll slows down exponentially, 98 % done after a second
	waterSamples = 4, -- points along the roll the server checks for ground, so a scoop rolling into the sea sinks
	-- a scoop rolls down steps (off a platform, a bridge or the river edge) but stops against one higher than this
	maxRollStep = 1, -- studs

	-- picking up: walking over a scoop, measured from the character's root on the ground plane
	pickupRadius = 3,
	pickupHeight = 6, -- studs above or below the root still counted (a scoop on a step)
	-- the server's check adds what differs between client and server, like the catch check (Config/Launcher)
	serverTolerance = 1.5,
	serverSpeedLead = 0.15, -- seconds of root speed (capped at 1.25 x WalkSpeed)
	maxClaimsPerSecond = 45, -- per player; more are dropped unread (a spam guard: a sweep claims a whole heap at once)
	-- walking over one of the own spilled scoops picks up every own spilled scoop within this many studs of the root
	-- at once (on the ground plane, pickupHeight still counts). Test of 20.11.2026: gathering a spilled tower one by
	-- one was slow stop-and-go walking. Others and Big Swirl scoops still need pickupRadius.
	ownSweepRadius = 6,

	scoopRadius = 1, -- drawn scoop, a little smaller than one on a tower
	ringSize = 3.2, -- the owner's glow under a reserved scoop
	-- the moment a scoop may be picked up by the local player it pops and a light ring flashes under it
	readyPop = 1.3, -- times its size at the top of the pop
	readyTime = 0.35, -- seconds

	-- the safe zone around the own cart: ice-ball hits there do no harm. A player who throws from inside it loses the
	-- protection for unshieldSeconds, so nobody camps at the cart and shoots out of it.
	safeRadius = 14, -- studs around the cart's ServePoint (the serve radius is 8)
	unshieldSeconds = 5,
}
