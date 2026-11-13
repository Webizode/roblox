-- Reuses what the effects are made of instead of creating and destroying it on every hit: an effect takes its
-- instances from here and gives them back when it is over. Everything sits in LocalVisuals (attachments on one
-- invisible part there), so nothing collides, is hit by a ray or pushes the camera.

local TowerVisual = require(script.Parent.Parent:WaitForChild("TowerVisual"))

local Pool = {}

local free: { [string]: { any } } = {}
local made: { [string]: number } = {}
local anchorPart: Part? = nil

-- One of `key` from the pool, or a new one from `build`.
function Pool.take<T>(key: string, build: () -> T): T
	local list = free[key]
	if list and #list > 0 then
		return table.remove(list) :: T
	end
	made[key] = (made[key] or 0) + 1
	return build()
end

function Pool.give(key: string, item: any)
	local list = free[key]
	if not list then
		list = {}
		free[key] = list
	end
	table.insert(list, item)
end

-- The folder the effects' instances live in.
function Pool.folder(): Folder
	return TowerVisual.root()
end

-- The invisible part every effect attachment sits on (they are placed by their world position). Should it ever be
-- gone, everything that sat on it is gone with it and the pools start over.
function Pool.anchor(): Part
	local part = anchorPart
	if part and part.Parent then
		return part
	end
	table.clear(free)
	local created = Instance.new("Part")
	created.Name = "VfxAnchor"
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	created.CanTouch = false
	created.CastShadow = false
	created.Transparency = 1
	created.Size = Vector3.one * 0.1
	created.CFrame = CFrame.identity
	created.Parent = Pool.folder()
	anchorPart = created
	return created
end

-- For checks: how many of each kind were ever built and how many lie unused right now.
function Pool.stats(): { [string]: { made: number, free: number } }
	local stats = {}
	for key, count in made do
		stats[key] = { made = count, free = if free[key] then #free[key] else 0 }
	end
	return stats
end

return Pool
