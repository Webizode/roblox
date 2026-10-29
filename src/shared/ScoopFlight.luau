--!strict
-- How a tower scoop looks on its way from the Big Swirl to a tower (Config/TowerScoops): its turn and tip in flight,
-- the swing back upright when it is caught, the plop onto the tower, its trail and when the far model takes over.
-- Pure: the config is passed in. Only looks; the flight path itself is ShotMath's, the server's.

export type TrailStyle = {
	lifetime: number,
	width: number,
	transparency: number,
	lightEmission: number,
	sparkles: number, -- per second, 0 = none
	color: string?, -- nil: the flavor's own colour
}

local ScoopFlight = {}

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Its turn about its own axis, `elapsed` seconds into the flight.
function ScoopFlight.spin(elapsed: number, config: any): number
	return elapsed * config.flight.spinRate
end

-- How far it has tipped (0 upright, 1 dome first) at flight share `alpha`: upright on the way up, then turning over
-- tipSpan of the flight from the apex on.
function ScoopFlight.tip(alpha: number, apexAlpha: number, config: any): number
	return smoothstep((alpha - apexAlpha) / config.flight.tipSpan)
end

-- The angle (radians) to turn its dome (up) towards the direction it flies (vx, vy, vz) at tip `tip`: none upright,
-- the whole angle between up and the flight direction (times tipLead) when tipped. A scoop flying straight up does
-- not turn.
function ScoopFlight.tipAngle(tip: number, vx: number, vy: number, vz: number, config: any): number
	local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
	if speed < 1e-6 then
		return 0
	end
	local between = math.acos(math.clamp(vy / speed, -1, 1))
	return between * tip * config.flight.tipLead
end

-- Back upright after a catch: the share of its tip still to undo is 1 - righting. It runs from 0 past 1 (the swing,
-- by `overshoot`) and settles at 1 after rightTime.
function ScoopFlight.righting(elapsed: number, config: any): number
	local t = math.clamp(elapsed / config.catch.rightTime, 0, 1)
	local c = config.catch.overshoot
	local u = t - 1
	return 1 + (c + 1) * u * u * u + c * u * u
end

-- The new top scoop of a tower, `elapsed` seconds after it landed: how far above its place it is and how it is
-- scaled (up, sideways). It drops in during the first 40 % and squashes once, flatter and wider, then rests.
function ScoopFlight.plop(elapsed: number, config: any): (number, number, number)
	local t = elapsed / config.catch.plopTime
	if t >= 1 or t < 0 then
		return 0, 1, 1
	end
	local fall = 0.4
	if t < fall then
		local u = t / fall
		return config.catch.plopDrop * (1 - u * u), 1, 1
	end
	local bump = math.sin((t - fall) / (1 - fall) * math.pi) * config.catch.squash
	return 0, 1 - bump, 1 + bump * 0.5
end

-- The trail tier of a flavor of rarity `rarity` (Config/Flavors); golden scoops have their own, an unknown rarity the
-- plain one.
function ScoopFlight.trailTier(rarity: string, golden: boolean, config: any): string
	if golden then
		return "golden"
	end
	return config.trail.tiers[rarity] or "common"
end

-- The trail of a tier at a VFX quality ("high", "medium", "low"; the performance mode counts as "low").
function ScoopFlight.trailStyle(tier: string, quality: string, config: any): TrailStyle
	local style = config.trail.styles[tier] or config.trail.styles.common
	local scale = config.trail.quality[quality] or config.trail.quality.high
	return {
		lifetime = style.lifetime * scale.lifetime,
		width = style.width,
		transparency = style.transparency,
		lightEmission = style.lightEmission,
		sparkles = style.sparkles * scale.sparkles,
		color = style.color,
	}
end

-- Whether the far model (LOD1) shows at `distance` studs from the camera, given what showed before: it takes over
-- from farDistance on and hands back below farDistance - hysteresis, so a scoop at the border does not flicker.
function ScoopFlight.useFar(distance: number, wasFar: boolean, config: any): boolean
	if wasFar then
		return distance >= config.farDistance - config.hysteresis
	end
	return distance >= config.farDistance
end

return ScoopFlight
