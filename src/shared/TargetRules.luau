--!strict
-- Where the Big Swirl aims (Config/Launcher): most scoops go to a random spot in the arena and the inner ring, the
-- rest (nearPlayerShare) near one of the players who are on the move. Standing still for idleSeconds (within
-- idleRadius) takes a player out of the near shots, so standing around grows no tower. Pure: the config is passed in;
-- the launcher keeps a Track per player and feeds it the player's position.

export type Track = {
	x: number, -- where the player last moved to (the anchor)
	z: number,
	since: number, -- server time they have been within idleRadius of the anchor
}

local TargetRules = {}

-- The player's track after seeing them at (x, z) at `now`: a new anchor once they left idleRadius of the old one.
function TargetRules.track(track: Track?, x: number, z: number, now: number, config: any): Track
	if track then
		local dx, dz = x - track.x, z - track.z
		if dx * dx + dz * dz <= config.idleRadius * config.idleRadius then
			return track
		end
	end
	return { x = x, z = z, since = now }
end

-- Whether the player has been standing still for idleSeconds.
function TargetRules.isIdle(track: Track, now: number, config: any): boolean
	return now - track.since >= config.idleSeconds
end

-- Which player a shot goes near, as an index into `moving` (the players not standing still), or nil for a random
-- spot. `roll` decides near or random (below nearPlayerShare: near), `pick` which player; both in [0, 1).
function TargetRules.choose(roll: number, pick: number, moving: number, config: any): number?
	if moving <= 0 or roll >= config.nearPlayerShare then
		return nil
	end
	return math.clamp(1 + math.floor(pick * moving), 1, moving)
end

return TargetRules
