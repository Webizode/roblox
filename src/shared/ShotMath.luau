--!strict
-- Flight path of a scoop from the Big Swirl, and where it touches a tower. Server and clients evaluate the same
-- parabola from the same start time, so a catch can be validated without replicating positions.

export type LauncherTuning = {
	flightBase: number,
	flightPerStud: number,
	apexBase: number,
	apexPerStud: number,
}

-- Start, target and arc height of one shot, as plain numbers.
export type Path = {
	fx: number,
	fy: number,
	fz: number,
	tx: number,
	ty: number,
	tz: number,
	apex: number,
}

local ShotMath = {}

-- alpha is the share of the flight time, clamped to [0, 1].
function ShotMath.position(
	fx: number,
	fy: number,
	fz: number,
	tx: number,
	ty: number,
	tz: number,
	apex: number,
	alpha: number
): (number, number, number)
	local a = math.clamp(alpha, 0, 1)
	local x = fx + (tx - fx) * a
	local z = fz + (tz - fz) * a
	local y = fy + (ty - fy) * a + 4 * apex * a * (1 - a)
	return x, y, z
end

function ShotMath.flightTime(distance: number, tuning: LauncherTuning): number
	return tuning.flightBase + distance * tuning.flightPerStud
end

function ShotMath.apex(distance: number, tuning: LauncherTuning): number
	return tuning.apexBase + distance * tuning.apexPerStud
end

-- Share of the flight time at which the scoop is highest. From here on it only falls, so catches count.
function ShotMath.apexAlpha(fy: number, ty: number, apex: number): number
	if apex <= 0 then
		return 0
	end
	return math.clamp(0.5 + (ty - fy) / (8 * apex), 0, 1)
end

local function distanceToSegment(
	px: number,
	py: number,
	pz: number,
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number
): number
	local dx, dy, dz = bx - ax, by - ay, bz - az
	local lengthSquared = dx * dx + dy * dy + dz * dz
	local t = 0
	if lengthSquared > 1e-9 then
		t = math.clamp(((px - ax) * dx + (py - ay) * dy + (pz - az) * dz) / lengthSquared, 0, 1)
	end
	local cx, cy, cz = ax + dx * t - px, ay + dy * t - py, az + dz * t - pz
	return math.sqrt(cx * cx + cy * cy + cz * cz)
end

-- Distance from a point to a polyline given as a flat x, y, z list (at least one point).
function ShotMath.distanceToPolyline(px: number, py: number, pz: number, points: { number }): number
	if #points < 6 then
		return distanceToSegment(px, py, pz, points[1], points[2], points[3], points[1], points[2], points[3])
	end
	local best = math.huge
	for index = 1, #points - 5, 3 do
		local distance = distanceToSegment(
			px,
			py,
			pz,
			points[index],
			points[index + 1],
			points[index + 2],
			points[index + 3],
			points[index + 4],
			points[index + 5]
		)
		best = math.min(best, distance)
	end
	return best
end

-- First alpha in [alphaFrom, alphaTo] at which the scoop centre is within `radius` of the polyline, or nil.
-- Samples the path so that two samples are never more than `maxStep` studs apart, so a fast scoop or a slow
-- frame cannot skip over a tower.
function ShotMath.firstContact(
	path: Path,
	alphaFrom: number,
	alphaTo: number,
	points: { number },
	radius: number,
	maxStep: number
): number?
	if alphaTo < alphaFrom then
		return nil
	end
	-- upper bound of the distance travelled per unit of alpha: horizontal is constant, vertical is largest
	-- at the start or the end of the arc
	local horizontal = math.sqrt((path.tx - path.fx) ^ 2 + (path.tz - path.fz) ^ 2)
	local vertical = math.abs(path.ty - path.fy) + 4 * math.abs(path.apex)
	local speed = math.sqrt(horizontal * horizontal + vertical * vertical)
	local samples = math.max(1, math.ceil((alphaTo - alphaFrom) * speed / maxStep))
	for sample = 0, samples do
		local alpha = alphaFrom + (alphaTo - alphaFrom) * sample / samples
		local x, y, z = ShotMath.position(path.fx, path.fy, path.fz, path.tx, path.ty, path.tz, path.apex, alpha)
		if ShotMath.distanceToPolyline(x, y, z, points) <= radius then
			return alpha
		end
	end
	return nil
end

return ShotMath
