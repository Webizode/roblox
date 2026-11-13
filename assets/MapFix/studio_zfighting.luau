-- Studio command bar / MCP (Edit mode): finds flat visible slabs in Workspace."Ice Cream Map" whose top faces lie on
-- the same height and overlap seen from above, and raises some of them in small steps, so no two overlapping tops are
-- level any more. Level overlapping tops flicker (z-fighting): kill test of 13.11.2026, the path crossings in the hub.
--
-- A slab: an upright Part or MeshPart, at most MAX_THICK studs thick and at least MIN_WIDE across, not see-through.
-- Overlapping slabs within LEVEL studs of each other form groups; in each group the slabs get levels by a greedy
-- colouring (the biggest first, each the lowest level none of its overlapping neighbours has), level k is raised by
-- k x STEP. So a chain of path pieces only alternates between two levels instead of climbing ever higher, and the
-- biggest slab of a crossing stays where it was. Raised, not lowered: a lowered plate could sink into the ground under
-- it and flicker with that instead. Each moved part keeps the offset in its attribute ZFightOffset; a
-- second run skips them (run DRY_RUN = true first to see what it would do). Undo: lower every part with the attribute
-- by its value and remove the attribute.

local DRY_RUN = false
local LEVEL = 0.05 -- studs: tops closer than this count as level
local STEP = 0.04 -- studs per level
local MAX_THICK = 1.2
local MIN_WIDE = 1.5
local OVERLAP = 0.05 -- studs both ways an overlap must have to count

local map = workspace:FindFirstChild("Ice Cream Map")
assert(map, "no Ice Cream Map")

local slabs = {}
for _, part in map:GetDescendants() do
	if
		part:IsA("BasePart")
		and part.Transparency < 0.95
		and math.abs(part.CFrame.UpVector.Y) > 0.999
		and not (part:IsA("Part") and part.Shape ~= Enum.PartType.Block)
		and part.Size.Y <= MAX_THICK
		and math.min(part.Size.X, part.Size.Z) >= MIN_WIDE
		and part:GetAttribute("ZFightOffset") == nil
	then
		table.insert(slabs, part)
	end
end

local function top(part: BasePart): number
	return part.Position.Y + part.Size.Y / 2
end

local function corners(part: BasePart): { Vector2 }
	local cf, half = part.CFrame, part.Size / 2
	local out = {}
	for _, o in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		local w = cf:PointToWorldSpace(Vector3.new(half.X * o[1], 0, half.Z * o[2]))
		table.insert(out, Vector2.new(w.X, w.Z))
	end
	return out
end

local function overlaps(a: BasePart, b: BasePart): boolean
	local ca, cb = corners(a), corners(b)
	local axes = {}
	for _, part in { a, b } do
		local r, l = part.CFrame.RightVector, part.CFrame.LookVector
		table.insert(axes, Vector2.new(r.X, r.Z).Unit)
		table.insert(axes, Vector2.new(l.X, l.Z).Unit)
	end
	for _, axis in axes do
		local amin, amax, bmin, bmax = math.huge, -math.huge, math.huge, -math.huge
		for _, c in ca do
			local v = c:Dot(axis)
			amin, amax = math.min(amin, v), math.max(amax, v)
		end
		for _, c in cb do
			local v = c:Dot(axis)
			bmin, bmax = math.min(bmin, v), math.max(bmax, v)
		end
		if math.min(amax, bmax) - math.max(amin, bmin) < OVERLAP then
			return false
		end
	end
	return true
end

-- the overlapping level pairs, through buckets of the top height
local buckets = {}
for index, part in slabs do
	local key = math.floor(top(part) / LEVEL)
	buckets[key] = buckets[key] or {}
	table.insert(buckets[key], index)
end
local neighbours: { [number]: { number } } = {}
local pairs_ = 0
local function link(i: number, j: number)
	local a, b = slabs[i], slabs[j]
	if math.abs(top(a) - top(b)) < LEVEL and overlaps(a, b) then
		neighbours[i] = neighbours[i] or {}
		neighbours[j] = neighbours[j] or {}
		table.insert(neighbours[i], j)
		table.insert(neighbours[j], i)
		pairs_ += 1
	end
end
-- every pair once: within a bucket, and each bucket with the next one up
for key, list in buckets do
	for n, i in list do
		for m = n + 1, #list do
			link(i, list[m])
		end
		for _, j in buckets[key + 1] or {} do
			link(i, j)
		end
	end
end

-- the levels: biggest first, each the lowest level its neighbours do not have
local order = {}
for index in neighbours do
	table.insert(order, index)
end
table.sort(order, function(a, b)
	local sa, sb = slabs[a].Size, slabs[b].Size
	return sa.X * sa.Z > sb.X * sb.Z
end)
local levels: { [number]: number } = {}
local deepest = 0
for _, index in order do
	local taken = {}
	for _, other in neighbours[index] do
		if levels[other] then
			taken[levels[other]] = true
		end
	end
	local level = 0
	while taken[level] do
		level += 1
	end
	levels[index] = level
	deepest = math.max(deepest, level)
end

local moved = 0
for index, level in levels do
	if level > 0 then
		moved += 1
		if not DRY_RUN then
			local part = slabs[index]
			local offset = level * STEP
			part.CFrame = part.CFrame + Vector3.new(0, offset, 0)
			part:SetAttribute("ZFightOffset", offset)
		end
	end
end
-- Second pass, over every slab (the ones moved before too): a raised slab can come close to one that was not level
-- with it before (0.06 apart, now 0.02). Every overlapping pair closer than SETTLE gets the smaller slab raised to
-- STEP over the bigger one, until no pair is left (the run of 13.11.2026: 94 raises in 4 passes, at most 0.18 studs
-- in all).
local SETTLE = 0.035
local settled = 0
if not DRY_RUN then
	local all = {}
	for _, part in map:GetDescendants() do
		if
			part:IsA("BasePart")
			and part.Transparency < 0.95
			and math.abs(part.CFrame.UpVector.Y) > 0.999
			and not (part:IsA("Part") and part.Shape ~= Enum.PartType.Block)
			and part.Size.Y <= MAX_THICK
			and math.min(part.Size.X, part.Size.Z) >= MIN_WIDE
		then
			table.insert(all, part)
		end
	end
	local close = {}
	for i = 1, #all do
		for j = i + 1, #all do
			if math.abs(top(all[i]) - top(all[j])) < 0.2 and overlaps(all[i], all[j]) then
				table.insert(close, { all[i], all[j] })
			end
		end
		if i % 300 == 0 then
			task.wait()
		end
	end
	for _ = 1, 8 do
		local changed = false
		for _, pair in close do
			local a, b = pair[1], pair[2]
			if math.abs(top(a) - top(b)) < SETTLE then
				local small, big = a, b
				if a.Size.X * a.Size.Z > b.Size.X * b.Size.Z then
					small, big = b, a
				end
				local lift = top(big) + STEP - top(small)
				small.CFrame = small.CFrame + Vector3.new(0, lift, 0)
				small:SetAttribute("ZFightOffset", (small:GetAttribute("ZFightOffset") or 0) + lift)
				settled += 1
				changed = true
			end
		end
		if not changed then
			break
		end
	end
end

return string.format(
	"%d slabs, %d level overlapping pairs, %d parts %s by up to %.2f studs, %d more raises settling the rest",
	#slabs,
	pairs_,
	moved,
	if DRY_RUN then "would be raised" else "raised",
	deepest * STEP,
	settled
)
