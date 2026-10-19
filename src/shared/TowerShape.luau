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

-- The base for a tower whose bottom scoop rests in a round opening centred at (x, y, z), like the waffle backpack:
-- a ball of scoopRadius on a ring of ringRadius sits sqrt(scoopRadius^2 - ringRadius^2) above the ring's centre, or
-- right in its middle when the ring is wider than the ball. The rest of the tower grows up from that scoop.
function TowerShape.restingBase(
	x: number,
	y: number,
	z: number,
	scoopRadius: number,
	ringRadius: number,
	tuning: ShapeTuning
): (number, number, number)
	local seat = if ringRadius < scoopRadius then math.sqrt(scoopRadius * scoopRadius - ringRadius * ringRadius) else 0
	local _, bottom = TowerShape.offset(1, 1, 0, 0, tuning)
	return x, y + seat - bottom, z
end

-- The tower as a polyline (flat x, y, z list, bottom to top): the cone tip, the middle scoop, the top scoop and
-- the free slot. A scoop that comes within the catch radius of this line touches the tower, wherever it hits
-- it, and is stacked on top. Checking only the free slot let scoops fly straight through taller towers.
function TowerShape.column(count: number, tiltX: number, tiltZ: number, tuning: ShapeTuning): { number }
	local points = { 0, tuning.coneHeight, 0 }
	local function add(index: number)
		local x, y, z = TowerShape.offset(index, count, tiltX, tiltZ, tuning)
		table.insert(points, x)
		table.insert(points, y)
		table.insert(points, z)
	end
	if count >= 3 then
		add(math.ceil(count / 2))
	end
	if count >= 1 then
		add(count)
	end
	add(count + 1)
	return points
end

return TowerShape
