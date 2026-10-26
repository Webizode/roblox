-- Raycasts against Kornel's map with the rules of MapRules, shared by server and client. Like Remotes this one needs
-- the Roblox runtime; the decisions themselves stay in the pure MapRules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapRules = require(Shared:WaitForChild("MapRules"))
local MapConfig = require(Shared:WaitForChild("Config"):WaitForChild("Map"))

local MapQuery = {}

-- parts a ray may pass before giving up; decoration layers and garlands can stack up
local MAX_SKIPS = 12

export type Ground = {
	y: number?, -- nil: no ground (water, nothing, or a surface nobody stands on)
	water: boolean,
	hit: RaycastResult?,
}

-- The map folder a part belongs to: the top-level folder under the map or under the Pier helpers, nil elsewhere.
function MapQuery.folderOf(instance: Instance): string?
	local current = instance
	while current.Parent do
		local parent = current.Parent
		if parent == workspace then
			return nil
		end
		if parent.Parent == workspace and (parent.Name == MapConfig.root or parent.Name == MapConfig.pier) then
			return current.Name
		end
		current = parent
	end
	return nil
end

local function isWater(result: RaycastResult): boolean
	return result.Material == Enum.Material.Water
		or result.Instance.Name == "Water"
		or (result.Instance:IsA("BasePart") and result.Instance.Material == Enum.Material.Water)
		or MapRules.belowSea(result.Position.Y, MapConfig)
end

-- Looks straight down from (x, fromY, z) for `reach` studs. Parts without collision are looked through (the map has
-- non-colliding sand and path layers just above its real floor, and garlands), water ends the search.
function MapQuery.ground(x: number, fromY: number, z: number, reach: number, ignore: { Instance }): Ground
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skipped = table.clone(ignore)
	local origin = Vector3.new(x, fromY, z)
	local direction = Vector3.new(0, -reach, 0)
	for _ = 1, MAX_SKIPS do
		params.FilterDescendantsInstances = skipped
		local result = workspace:Raycast(origin, direction, params)
		if not result then
			return { y = nil, water = false, hit = nil }
		end
		if isWater(result) then
			return { y = nil, water = true, hit = result }
		end
		if result.Instance:IsA("Terrain") or (result.Instance :: BasePart).CanCollide then
			return { y = result.Position.Y, water = false, hit = result }
		end
		table.insert(skipped, result.Instance)
	end
	return { y = nil, water = false, hit = nil }
end

-- A raycast that only stops where a thrown ball stops (MapRules.blocksThrow): parts without collision and the thin
-- decoration from Config/Map are flown through. Server and client aim use the same rule.
function MapQuery.throwRaycast(origin: Vector3, direction: Vector3, ignore: { Instance }): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skipped = table.clone(ignore)
	for _ = 1, MAX_SKIPS do
		params.FilterDescendantsInstances = skipped
		local result = workspace:Raycast(origin, direction, params)
		if not result then
			return nil
		end
		local instance = result.Instance
		local canCollide = instance:IsA("Terrain") or (instance :: BasePart).CanCollide
		if MapRules.blocksThrow(MapQuery.folderOf(instance), instance.Name, canCollide, MapConfig) then
			return result
		end
		table.insert(skipped, instance)
	end
	return nil
end

return MapQuery
