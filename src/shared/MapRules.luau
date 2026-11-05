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
		settleStep: number,
		settleRadius: number,
	},
	throwPassFolders: { string },
	throwPassNames: { string },
	coverFitTolerance: number,
	playersOnlyFolders: { string },
	coverKitNames: { string },
}

local MapRules = {}

-- what MapQuery.folderOf calls the Terrain: part of the map although it is no folder in it
MapRules.terrain = "Terrain"

-- Whether a ball flying into this part stops there. Parts without collision never stop it (zones, trigger volumes,
-- decoration layers), and neither does the thin decoration the config lets through.
function MapRules.blocksThrow(folder: string?, name: string, canCollide: boolean, config: Config): boolean
	if not canCollide or MapRules.playersOnly(folder, config) then
		return false
	end
	if folder and table.find(config.throwPassFolders, folder) then
		return false
	end
	return table.find(config.throwPassNames, name) == nil
end

-- Whether a part only stops players: the invisible walls in config.playersOnlyFolders (the barrier over the arena
-- rim). Throws, aim and the ground and landing checks look through them; walking bodies collide. Needed because
-- Roblox ignores CanQuery = false on parts that collide.
function MapRules.playersOnly(folder: string?, config: Config): boolean
	return folder ~= nil and table.find(config.playersOnlyFolders, folder) ~= nil
end

-- Whether a height lies in the sea: the sea floor under the water is not ground.
function MapRules.belowSea(y: number, config: Config): boolean
	return y < config.waterLevel
end

-- Whether a character's root at height y is in the sea (swimming or on the sea floor).
function MapRules.inSea(rootY: number, config: Config): boolean
	return rootY < config.waterLevel + config.respawnMargin
end
-- Whether a surface a scoop would land on is ground a player could stand on. `folder` is the top-level map folder
-- (MapQuery.folderOf), MapRules.terrain for the Terrain, nil for a part outside the map: that is never ground (cover
-- copied into Workspace instead of Covery had its tops taken for landing spots).
function MapRules.landingSurface(folder: string?, name: string, normalY: number, config: Config): boolean
	local landing = config.landing
	if folder == nil or normalY < landing.minNormalY then
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

-- Whether a free scoop resting on ground of height restY lies where a player can reach it: the surface seen from above
-- there (surfaceY, nil when it is no landing surface: cover, rim, arch, barrier, machine) is that same ground. On top
-- of a pillar the surface is the cover; inside a crate (its ground ray started in the box and found the floor) the
-- surface from above is the crate's top.
function MapRules.restsWell(surfaceY: number?, restY: number, config: Config): boolean
	return surfaceY ~= nil and math.abs(surfaceY - restY) <= config.landing.maxStep
end

-- The offsets round a point in `step` studs out to `radius`, nearest first and the point itself first of all: where
-- MapService.settle looks for free ground.
function MapRules.searchOffsets(step: number, radius: number): { { number } }
	local offsets = {}
	local reach = math.floor(radius / step)
	for i = -reach, reach do
		for j = -reach, reach do
			local dx, dz = i * step, j * step
			if dx * dx + dz * dz <= radius * radius then
				table.insert(offsets, { dx, dz })
			end
		end
	end
	table.sort(offsets, function(a, b)
		local da, db = a[1] * a[1] + a[2] * a[2], b[1] * b[1] + b[2] * b[2]
		if da ~= db then
			return da < db
		end
		if a[1] ~= b[1] then
			return a[1] < b[1]
		end
		return a[2] < b[2]
	end)
	return offsets
end

-- The first point of (x, z) + offsets where `probe` finds free ground (its height), as x, y, z; nil when none does.
function MapRules.nearestFree(
	x: number,
	z: number,
	offsets: { { number } },
	probe: (number, number) -> number?
): (number?, number?, number?)
	for _, offset in offsets do
		local px, pz = x + offset[1], z + offset[2]
		local y = probe(px, pz)
		if y then
			return px, y, pz
		end
	end
	return nil, nil, nil
end

-- Whether a model is one of the arena kit's cover models (config.coverKitNames, by prefix: CoverBlock_10).
function MapRules.isCoverKit(name: string, config: Config): boolean
	for _, prefix in config.coverKitNames do
		if string.sub(name, 1, #prefix) == prefix then
			return true
		end
	end
	return false
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
