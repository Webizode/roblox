--!strict
-- How a tower scoop looks on its way from the Big Swirl to a tower (Config/TowerScoops): its turn and tip in flight,
-- the swing back upright when it is caught, the plop onto the tower and when the far model takes over
-- (the trail by rarity is RarityFlight, Config/Vfx.flight).
-- Pure: the config is passed in. Only looks; the flight path itself is ShotMath's, the server's.

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

-- Whether the far model (LOD1) shows at `distance` studs from the camera, given what showed before: it takes over
-- from farDistance on and hands back below farDistance - hysteresis, so a scoop at the border does not flicker.
function ScoopFlight.useFar(distance: number, wasFar: boolean, config: any): boolean
	if wasFar then
		return distance >= config.farDistance - config.hysteresis
	end
	return distance >= config.farDistance
end

-- A number in [0, 1) that is always the same for the same place and salt (no Random: the pose must not change
-- between two frames or two clients).
local function hash(index: number, salt: number): number
	local x = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- How the scoop in place `index` (1 = bottom) sits on a tower (Config/TowerScoops stack): turned about its own axis by
-- a random yaw, tilted a little (radians about X and Z) and a little bigger or smaller, so a stack looks hand-made,
-- not like stacked discs. The same for the same place.
function ScoopFlight.stackPose(index: number, config: any): (number, number, number, number)
	local stack = config.stack
	-- the golden angle from place to place plus up to 30 degrees either way: random-looking, but never two neighbours
	-- turned alike (they would line their drips up)
	local yaw = (index * math.rad(137.5) + (hash(index, 1) - 0.5) * math.rad(60)) % (2 * math.pi)
	local tiltX = (hash(index, 2) * 2 - 1) * stack.tilt
	local tiltZ = (hash(index, 3) * 2 - 1) * stack.tilt
	local scale = stack.scaleMin + hash(index, 4) * (stack.scaleMax - stack.scaleMin)
	return yaw, tiltX, tiltZ, scale
end

return ScoopFlight
