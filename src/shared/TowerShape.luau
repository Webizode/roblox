--!strict
-- Where each scoop sits for a given tilt. Shared by the client visuals and the server's catch check, so both
-- agree on where the top of a tower is. Offsets are in studs relative to the tower base, world-axis aligned.

export type ShapeTuning = {
	scoopSpacing: number,
	coneHeight: number,
}

local TowerShape = {}

local BEND = 1.5 -- >1 bends the tower like a noodle instead of rotating it like a stick

-- index 1 is the bottom scoop. index count + 1 is the free slot on top, where the next scoop lands.
function TowerShape.offset(
	index: number,
	count: number,
	tiltX: number,
	tiltZ: number,
	tuning: ShapeTuning
): (number, number, number)
	local height = tuning.coneHeight + (index - 0.5) * tuning.scoopSpacing
	local reference = tuning.coneHeight + math.max(count, 1) * tuning.scoopSpacing
	local fraction = math.min(height / reference, 1.25)

	local tilt = math.sqrt(tiltX * tiltX + tiltZ * tiltZ)
	local sinOverTilt = if tilt > 1e-6 then math.sin(tilt) / tilt else 1
	local bend = fraction ^ BEND

	local ox = tiltX * sinOverTilt * reference * bend
	local oz = tiltZ * sinOverTilt * reference * bend
	local oy = height * math.cos(tilt * math.min(fraction, 1))
	return ox, oy, oz
end

function TowerShape.top(count: number, tiltX: number, tiltZ: number, tuning: ShapeTuning): (number, number, number)
	return TowerShape.offset(count + 1, count, tiltX, tiltZ, tuning)
end

return TowerShape
