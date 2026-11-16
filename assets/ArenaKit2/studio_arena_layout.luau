-- Studio (Edit, through the MCP or the command bar): arena kit 2 into the arena, 14.11.2026 (sketch in the vault:
-- Wobble Scoops/Arena Kit 2 Vorschau/Anordnung Vorschlag 2026-11-14.png).
--
-- The same places in every 60 degree section (fair for all 12 plots), each taken by a different model, so the arena
-- no longer looks like copies; the 12 lanes from the ramps (15 + k * 30 degrees) to the Big Swirl stay free (LANE
-- studs either side of their middle line). Per section k (A = 30 + 60k, B = 60 + 60k degrees):
--   A, r 82: a platform (waffle and cake in turn), its ramp or stairs towards the machine
--   A, r 44 and r 114: middle cover;  B, r 56: high cover;  B, r 78: middle cover
--   B, r 104: a landmark (60, 180, 300 degrees) or special cover (0, 120, 240; the normal state, no logic yet)
--   A -+ 7 degrees, r 100: two more middle cover pieces behind the platform (about 50 pieces in all, the user's choice)
-- Everything faces the machine (front -Z to the centre), its pivot on the arena floor. Cover, landmarks and special
-- cover go to Covery (shaped collision: MapService.prepareCover leaves several collision parts as they are),
-- platforms to Platformy (their tops are ground, scoops land there). The 6 IceKit platforms of 14.11.2026 go.
-- Old cover stays where it blocks no lane and keeps MARGIN studs from every new piece (the user's choice: mixed), up
-- to about TOTAL pieces in all. A copy of Covery and Platformy goes to ServerStorage (BACKUP) first; RESTORE = true
-- puts it back.

local RESTORE = false
local BACKUP = "MapBackup_2026-11-14_ArenaLayout"
local FLOOR = 1.2 -- top of Arena_Boden
local LANE = 6
local MARGIN = 3
local TOTAL = 52

local ServerStorage = game:GetService("ServerStorage")
local map = workspace["Ice Cream Map"]
local kit = ServerStorage:WaitForChild("ArenaKit2")

if RESTORE then
	local copy = ServerStorage:FindFirstChild(BACKUP)
	assert(copy, "no backup " .. BACKUP)
	for _, name in { "Covery", "Platformy" } do
		map[name]:Destroy()
		local restored = copy[name]:Clone()
		restored.Parent = map
	end
	print("[ArenaLayout] restored Covery and Platformy from " .. BACKUP)
	return "restored"
end

if not ServerStorage:FindFirstChild(BACKUP) then
	local copy = Instance.new("Folder")
	copy.Name = BACKUP
	map.Covery:Clone().Parent = copy
	map.Platformy:Clone().Parent = copy
	copy.Parent = ServerStorage
end

-- the plan
local INNER = { "WaffleCrates", "CookieStack", "ChocoBar", "CandyBox", "WaffleCrates", "CookieStack" }
local OUTER = { "FallenCone", "CandyBox_Mint", "FallenCone_Lemon", "ChocoBar", "FallenCone_Mint", "WaffleCrates" }
local BMID = { "CandyBox_Blue", "ChocoBar", "CookieStack", "WaffleCrates", "CandyBox", "ChocoBar" }
-- two more middle cover pieces per section, left and right behind the platform (A -+ 7 degrees, r 100): only the compact
-- ones, so they keep more than 9 studs off the lanes
local EXTRA = {
	"ChocoBar",
	"CookieStack",
	"CandyBox_Mint",
	"WaffleCrates",
	"CookieStack",
	"CandyBox",
	"WaffleCrates",
	"ChocoBar",
	"CandyBox_Blue",
	"CookieStack",
	"ChocoBar",
	"WaffleCrates",
}
local HIGH = {
	[60] = "ChocoWall",
	[120] = "GiantCupcake_Pink",
	[180] = "WaffleWall", -- the WaffleArch until 16.11.2026 (studio_arena_safe_walls.luau)
	[240] = "MacaronStack",
	[300] = "CookieTower",
	[0] = "SundaeCup",
}
local OUTER_B = {
	[60] = "ChocoWall", -- since 16.11.2026: safe walls instead of the GrandSundae, the LollipopTree and the
	-- CreamDispenser (studio_arena_safe_walls.luau)
	[180] = "CreamMountain",
	[300] = "WaffleWall",
	[0] = "WobbleTower",
	[120] = "GummyBouncer_Mint",
	[240] = "GummyPad_Mint",
}
local plan, extras = {}, {}
for k = 0, 5 do
	local a, b = 30 + 60 * k, (60 + 60 * k) % 360
	table.insert(plan, { if k % 2 == 0 then "WafflePlatform" else "CakePlatform", a, 82, "Platformy" })
	table.insert(plan, { INNER[k + 1], a, 44, "Covery" })
	table.insert(plan, { OUTER[k + 1], a, 114, "Covery" })
	table.insert(plan, { HIGH[b], b, 56, "Covery" })
	table.insert(plan, { BMID[k + 1], b, 78, "Covery" })
	table.insert(plan, { OUTER_B[b], b, 104, "Covery" })
	table.insert(extras, { EXTRA[2 * k + 1], a - 7, 100, "Covery" })
	table.insert(extras, { EXTRA[2 * k + 2], a + 7, 100, "Covery" })
end

-- out with the IceKit platforms; the new pieces in (the extra ones come last, round the old pieces that stay)
map.Platformy:ClearAllChildren()
local placed = {}
local newFolder = Instance.new("Folder")
newFolder.Name = "ArenaKit2"
newFolder.Parent = map.Covery
local function place(entry): Model
	local name, deg, r, where = entry[1], entry[2], entry[3], entry[4]
	local template = kit:FindFirstChild(name)
	assert(template, "no template ServerStorage.ArenaKit2." .. name)
	local a = math.rad(deg)
	local at = Vector3.new(math.cos(a) * r, FLOOR, math.sin(a) * r)
	local model = template:Clone()
	model:PivotTo(CFrame.lookAt(at, Vector3.new(0, FLOOR, 0))) -- front (-Z) to the machine
	model:SetAttribute("ArenaKit2Layout", true)
	model.Parent = if where == "Platformy" then map.Platformy else newFolder
	return model
end
for _, entry in plan do
	table.insert(placed, place(entry))
end

-- the new collision parts, for the distance checks
local newParts = {}
for _, model in placed do
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name:sub(1, 9) == "Collision" then
			table.insert(newParts, p)
		end
	end
end

local function nearNew(point: Vector3): boolean
	for _, p in newParts do
		local l = p.CFrame:PointToObjectSpace(Vector3.new(point.X, p.Position.Y, point.Z))
		local hx, hz = p.Size.X / 2 + MARGIN, p.Size.Z / 2 + MARGIN
		if p:IsA("Part") and p.Shape == Enum.PartType.Cylinder then
			-- an upright cylinder (its axis, X, turned up): round, Size.Y across
			local d = Vector3.new(point.X - p.Position.X, 0, point.Z - p.Position.Z).Magnitude
			if d <= p.Size.Y / 2 + MARGIN then
				return true
			end
		elseif math.abs(l.X) <= hx and math.abs(l.Z) <= hz then
			return true
		end
	end
	return false
end

local function onLane(point: Vector3): boolean
	for i = 0, 11 do
		local la = math.rad(15 + 30 * i)
		local along = math.cos(la) * point.X + math.sin(la) * point.Z
		local across = math.abs(-math.sin(la) * point.X + math.cos(la) * point.Z)
		if along > 26 and across < LANE then
			return true
		end
	end
	return false
end

-- every old piece: its collision box sampled over its footprint
local old = {}
for _, d in map.Covery:GetDescendants() do
	if d:IsA("Model") and d:FindFirstChild("Collision") and not d:IsDescendantOf(newFolder) then
		table.insert(old, d)
	end
end
local keep, drop = {}, {}
for _, model in old do
	local box = model.Collision
	local ok = true
	local sx, sz = box.Size.X, box.Size.Z
	if box:IsA("Part") and box.Shape == Enum.PartType.Cylinder then
		sx, sz = box.Size.Y, box.Size.Z
	end
	for u = -0.5, 0.5, 0.125 do
		for v = -0.5, 0.5, 0.125 do
			local point = (box.CFrame * CFrame.new(u * sx, 0, v * sz)).Position
			if box:IsA("Part") and box.Shape == Enum.PartType.Cylinder then
				point = box.Position + Vector3.new(u * sx, 0, v * sz)
			end
			if onLane(point) or nearNew(point) then
				ok = false
				break
			end
		end
		if not ok then
			break
		end
	end
	table.insert(if ok then keep else drop, model)
end
-- no more than TOTAL in all: the farthest from the machine stay first (the inner ring is already busy)
table.sort(keep, function(x, y)
	return x:GetPivot().Position.Magnitude > y:GetPivot().Position.Magnitude
end)
local room = TOTAL - #placed
for i = #keep, room + 1, -1 do
	table.insert(drop, table.remove(keep, i))
end
-- a stacked old piece (its box well above the floor) only stays if what it stands on stays too
local function bottomOf(box: BasePart): number
	local cf, s = box.CFrame, box.Size
	local half = (cf.RightVector * s.X / 2):Abs() + (cf.UpVector * s.Y / 2):Abs() + (cf.LookVector * s.Z / 2):Abs()
	return box.Position.Y - half.Y
end
local changed = true
while changed do
	changed = false
	local keptBoxes = {}
	for _, model in keep do
		table.insert(keptBoxes, model.Collision)
	end
	for i = #keep, 1, -1 do
		local box = keep[i].Collision
		local bottom = bottomOf(box)
		if bottom > FLOOR + 0.5 then
			local others = table.clone(keptBoxes)
			table.remove(others, table.find(others, box) :: number)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = others
			local hit = workspace:Raycast(
				Vector3.new(box.Position.X, bottom + 0.2, box.Position.Z),
				Vector3.new(0, -1, 0),
				params
			)
			if not hit then
				table.insert(drop, table.remove(keep, i))
				changed = true
			end
		end
	end
end
for _, model in drop do
	model:Destroy()
end

-- the extra middle cover last: only where it keeps MARGIN studs from the old pieces that stay, up to TOTAL in all
local oldBoxes = {}
for _, model in keep do
	table.insert(oldBoxes, model.Collision)
end
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = oldBoxes
local skipped = 0
for _, entry in extras do
	if #placed + #keep >= TOTAL then
		skipped += 1
		continue
	end
	local model = place(entry)
	local clear = true
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name:sub(1, 9) == "Collision" then
			local hits =
				workspace:GetPartBoundsInBox(p.CFrame, p.Size + Vector3.new(2 * MARGIN, 0, 2 * MARGIN), overlap)
			if #hits > 0 then
				clear = false
			end
		end
	end
	if clear then
		table.insert(placed, model)
	else
		model:Destroy()
		skipped += 1
	end
end
-- the folders the old pieces were grouped in may be empty now
for _, f in map.Covery:GetDescendants() do
	if (f:IsA("Folder") or f:IsA("Model")) and not f:FindFirstChild("Collision") and #f:GetDescendants() == 0 then
		f:Destroy()
	end
end

local text = string.format(
	"[ArenaLayout] %d arena kit 2 pieces placed (%d platforms, %d extra places left out), %d old cover pieces kept, %d removed; %d in all",
	#placed,
	#map.Platformy:GetChildren(),
	skipped,
	#keep,
	#drop,
	#placed + #keep
)
print(text)
return text
