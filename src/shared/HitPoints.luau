--!strict
-- Knockdown points (Config/Combat knock). Every hit is worth points by what it was: a normal hit, a grazing one, a
-- perfect throw, a headshot or a perfect headshot. At knockdownAt points the victim goes down. The count drops to 0
-- after resetAfter seconds without a hit; hits within multiWindow of each other (only several players can land
-- those, one player's throws are throwInterval apart) count once, the strongest; after getting up the player has
-- `protection` seconds in which hits give no points. Pure: CombatService keeps one State per player, the HUD reads
-- display(), tests/HitPoints.spec.luau covers every combination.

export type Config = {
	points: { normal: number, graze: number, perfect: number, headshot: number, headshotPerfect: number },
	grazeBelow: number,
	knockdownAt: number,
	resetAfter: number,
	multiWindow: number,
	protection: number,
}

export type State = {
	points: number,
	lastHitAt: number, -- the last hit that counted for the reset (any hit outside the protection)
	windowAt: number, -- when the current window of near-simultaneous hits opened
	windowBest: number, -- the most points a hit in that window was worth
	protectedUntil: number, -- hits until then give no points (the get-up protection)
}

local HitPoints = {}

function HitPoints.new(): State
	return { points = 0, lastHitAt = -math.huge, windowAt = -math.huge, windowBest = 0, protectedUntil = -math.huge }
end

-- What a hit is worth: a perfect headshot, a headshot, a perfect throw, a normal hit, or a grazing one (a normal
-- hit with power below grazeBelow). Power still decides knockback and the tower shove; here it only marks grazes.
function HitPoints.value(headshot: boolean, perfect: boolean, power: number, config: Config): number
	local points = config.points
	if headshot then
		return if perfect then points.headshotPerfect else points.headshot
	end
	if perfect then
		return points.perfect
	end
	return if power < config.grazeBelow then points.graze else points.normal
end

-- Adds a hit worth `value` points at `now`. Returns the points it added (0 inside the protection, and for the part a
-- stronger hit in the same window already counted) and whether it knocks the victim down. A knockdown empties the
-- count and protects the victim until `downUntil` plus `protection` (no hits land while they are down anyway).
function HitPoints.add(state: State, now: number, value: number, downUntil: number, config: Config): (number, boolean)
	if now < state.protectedUntil then
		return 0, false
	end
	if now - state.lastHitAt >= config.resetAfter then
		state.points = 0
	end
	state.lastHitAt = now
	local added
	if now - state.windowAt < config.multiWindow then
		added = math.max(0, value - state.windowBest)
		state.windowBest = math.max(state.windowBest, value)
	else
		added = value
		state.windowAt, state.windowBest = now, value
	end
	state.points += added
	if state.points >= config.knockdownAt then
		state.points = 0
		state.windowAt, state.windowBest = -math.huge, 0
		state.protectedUntil = downUntil + config.protection
		return added, true
	end
	return added, false
end

-- What the own knockdown meter shows from the replicated values: the points (0 once resetAt has passed) and whether
-- the get-up protection is on. Inputs come from attributes, so anything odd is clamped.
function HitPoints.display(
	points: number,
	resetAt: number,
	protectedUntil: number,
	now: number,
	config: Config
): (number, boolean)
	local shown = if points == points then math.clamp(points, 0, config.knockdownAt) else 0
	if resetAt ~= resetAt or now >= resetAt then
		shown = 0
	end
	return shown, protectedUntil == protectedUntil and now < protectedUntil
end

return HitPoints
