--!strict
-- How the game reads Kornel's map (Config/Map). Pure: the callers describe a hit by its top-level map folder, its
-- name and its numbers, so the rules run in the Lune tests. The raycasts themselves are in MapQuery.

export type Config = {
	waterLevel: number,
	respawnMargin: number,
	landing: {
		gridStep: number,
		footprint: number,
		maxStep: number,
		minNormalY: number,
		blockedFolders: { string },
		blockedNamePrefixes: { string },
	},
	throwPassFolders: { string },
	throwPassNames: { string },
	coverFitTolerance: number,
}

local MapRules = {}

-- Whether a ball flying into this part stops there. Parts without collision never stop it (zones, trigger volumes,
-- decoration layers), and neither does the thin decoration the config lets through.
function MapRules.blocksThrow(folder: string?, name: string, canCollide: boolean, config: Config): boolean
	if not canCollide then
		return false
	end
	if folder and table.find(config.throwPassFolders, folder) then
		return false
	end
	return table.find(config.throwPassNames, name) == nil
end

-- Whether a height lies in the sea: the sea floor under the water is not ground.
function MapRules.belowSea(y: number, config: Config): boolean
	return y < config.waterLevel
end

-- Whether a character's root at height y is in the sea (swimming or on the sea floor).
function MapRules.inSea(rootY: number, config: Config): boolean
	return rootY < config.waterLevel + config.respawnMargin
end
-- Whether a surface a scoop would land on is ground a player could stand on.
function MapRules.landingSurface(folder: string?, name: string, normalY: number, config: Config): boolean
	local landing = config.landing
	if normalY < landing.minNormalY then
		return false
	end
	if folder and table.find(landing.blockedFolders, folder) then
		return false
	end
	for _, prefix in landing.blockedNamePrefixes do
		if string.sub(name, 1, #prefix) == prefix then
			return false
		end
	end
	return true
end

-- Whether a landing spot is flat enough: `heights` holds the ground under the spot and around it (nil where there is
-- none, water or a blocked surface). One missing point or a step higher than maxStep and it is no spot.
function MapRules.flatFootprint(heights: { number? }, count: number, config: Config): boolean
	local low, high = math.huge, -math.huge
	for index = 1, count do
		local height = heights[index]
		if height == nil then
			return false
		end
		low, high = math.min(low, height), math.max(high, height)
	end
	return count > 0 and high - low <= config.landing.maxStep
end

-- The spots of `spots` (flat arrays of x, y, z) within `radius` of (x, z); when none is, the nearest one.
-- Returns indices into the spot list (1-based spot numbers, not array positions).
function MapRules.spotsNear(spots: { number }, x: number, z: number, radius: number): { number }
	local near = {}
	local best, bestDistance = nil, math.huge
	local radiusSquared = radius * radius
	for index = 1, #spots // 3 do
		local dx, dz = spots[index * 3 - 2] - x, spots[index * 3] - z
		local distance = dx * dx + dz * dz
		if distance <= radiusSquared then
			table.insert(near, index)
		end
		if distance < bestDistance then
			best, bestDistance = index, distance
		end
	end
	if #near == 0 and best then
		table.insert(near, best)
	end
	return near
end

-- The spots of `spots` between `inner` and `outer` (inclusive) from (x, z); when none is, the one closest to that ring.
-- Returns indices into the spot list (1-based spot numbers, not array positions).
function MapRules.spotsBetween(spots: { number }, x: number, z: number, inner: number, outer: number): { number }
	local between = {}
	local best, bestMiss = nil, math.huge
	for index = 1, #spots // 3 do
		local dx, dz = spots[index * 3 - 2] - x, spots[index * 3] - z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance >= inner and distance <= outer then
			table.insert(between, index)
		end
		local miss = math.max(inner - distance, distance - outer)
		if miss < bestMiss then
			best, bestMiss = index, miss
		end
	end
	if #between == 0 and best then
		table.insert(between, best)
	end
	return between
end

export type Bounds = { min: { number }, max: { number } } -- {x, y, z} each, in the cover box's own frame

-- The box a cover model must collide with when its visible parts stick out of its Collision box by more than
-- config.coverFitTolerance on any side (only the meshes resized in Studio, not the whole model): the union of the box
-- (centred at the origin, `half` its half size) and `visible`, as a centre offset and a full size in the box's frame.
-- nil when the box already covers the model.
function MapRules.coverBoxFit(half: { number }, visible: Bounds, config: Config): ({ number }?, { number }?)
	local tolerance = config.coverFitTolerance
	local outside = false
	for axis = 1, 3 do
		if visible.min[axis] < -half[axis] - tolerance or visible.max[axis] > half[axis] + tolerance then
			outside = true
		end
	end
	if not outside then
		return nil, nil
	end
	local centre, size = table.create(3), table.create(3)
	for axis = 1, 3 do
		local low = math.min(-half[axis], visible.min[axis])
		local high = math.max(half[axis], visible.max[axis])
		centre[axis] = (low + high) / 2
		size[axis] = high - low
	end
	return centre, size
end

return MapRules
