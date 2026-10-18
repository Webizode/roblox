--!strict
-- Flight path of a scoop from the Big Swirl. Server and clients evaluate the same parabola from the same
-- start time, so a catch can be validated without replicating positions.

export type LauncherTuning = {
	flightBase: number,
	flightPerStud: number,
	apexBase: number,
	apexPerStud: number,
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

return ShotMath
