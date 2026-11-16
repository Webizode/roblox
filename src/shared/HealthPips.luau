--!strict
-- The life bar (Config/Combat healthBar): the knockdown points (HitPoints) shown the other way round, as the share of
-- lives left, in one segment per normal hit up to the knockdown. Pure: it only turns the values the server replicates
-- into what to draw and decides which rivals get a bar; EnemyHealthBars and KnockMeter draw it,
-- tests/HealthPips.spec.luau covers it.

export type Knock = {
	points: { normal: number },
	knockdownAt: number,
	resetAfter: number,
}

export type Bar = {
	yellowAt: number,
	redAt: number,
	refill: number,
	near: number,
	aimAngle: number,
	aimRange: number,
	afterHit: number,
	max: number,
}

export type Tone = "full" | "mid" | "low" | "down" | "protected"

export type Candidate = {
	id: number,
	distance: number, -- studs from the camera
	angle: number, -- degrees from the crosshair
	sinceHit: number, -- seconds since their last hit (math.huge if none)
}

local HealthPips = {}

-- How many segments the bar has: the normal hits a knockdown takes (6 / 2 = 3).
function HealthPips.segments(knock: Knock): number
	return math.max(1, math.ceil(knock.knockdownAt / knock.points.normal))
end

-- The share of the bar left (1 full, 0 empty) for `points` counted (HitPoints.display's value).
function HealthPips.left(points: number, knock: Knock): number
	if points ~= points then
		return 1
	end
	return math.clamp(1 - points / knock.knockdownAt, 0, 1)
end

-- Each segment's fill (0 to 1) for `share` of the bar left, the first segment on the left.
function HealthPips.fills(share: number, segments: number): { number }
	local fills = table.create(segments)
	for index = 1, segments do
		fills[index] = math.clamp(share * segments - (index - 1), 0, 1)
	end
	return fills
end

-- The bar's colour: grey while knocked down, blue during the get-up protection, otherwise by the share left.
function HealthPips.tone(share: number, down: boolean, protected: boolean, bar: Bar): Tone
	if down then
		return "down"
	elseif protected then
		return "protected"
	elseif share <= bar.redAt + 1e-6 then
		return "low"
	elseif share <= bar.yellowAt + 1e-6 then
		return "mid"
	end
	return "full"
end

-- The share drawn after `dt` seconds: it drops to `target` at once (a hit) and rises to it at one full bar per
-- `refill` seconds (the count dropping back to 0).
function HealthPips.approach(shown: number, target: number, dt: number, refill: number): number
	if target <= shown or refill <= 0 then
		return target
	end
	return math.min(target, shown + dt / refill)
end

-- The server time of the last hit that counted, from the replicated KnockResetAt (0 before any hit).
function HealthPips.hitAt(resetAt: number, knock: Knock): number
	if resetAt ~= resetAt or resetAt <= 0 then
		return -math.huge
	end
	return resetAt - knock.resetAfter
end

-- Whether a rival in plain sight gets a bar: just hit, near, or close to the crosshair and in range.
function HealthPips.wanted(candidate: Candidate, bar: Bar): boolean
	if candidate.sinceHit < bar.afterHit then
		return true
	end
	if candidate.distance <= bar.near then
		return true
	end
	return candidate.angle <= bar.aimAngle and candidate.distance <= bar.aimRange
end

-- The rivals that get a bar, at most bar.max: of those wanted, the ones hit last first, then the nearest. Returns
-- their ids as a set.
function HealthPips.pick(candidates: { Candidate }, bar: Bar): { [number]: boolean }
	local wanted = {}
	for _, candidate in candidates do
		if HealthPips.wanted(candidate, bar) then
			table.insert(wanted, candidate)
		end
	end
	table.sort(wanted, function(a, b)
		local aHit, bHit = a.sinceHit < bar.afterHit, b.sinceHit < bar.afterHit
		if aHit ~= bHit then
			return aHit
		end
		if aHit and a.sinceHit ~= b.sinceHit then
			return a.sinceHit < b.sinceHit
		end
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.id < b.id
	end)
	local picked = {}
	for index = 1, math.min(#wanted, bar.max) do
		picked[wanted[index].id] = true
	end
	return picked
end

return HealthPips
