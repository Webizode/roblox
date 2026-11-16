-- Studio (Edit, through the MCP or the command bar): safe walls in the arena, 16.11.2026 (the user's approval of the
-- preview Wobble Scoops/Arena Kit 2 Vorschau/Deckung_*.png). Walls of 11.5 studs and more hide a standing player's
-- body and head from every throw (CombatService's rules simulated for every angle, speed and distance; a tower above
-- the wall is seen but is no target). Changes, in the layout's angles (x = cos, z = sin, like studio_arena_layout):
--   out:  LollipopTree, GrandSundae, CreamDispenser (r 104 at 300, 60 and 120 degrees)
--   180, r 56:  WaffleArch -> WaffleWall (the arch shows the player through its opening)
--   60,  r 104: ChocoWall (where the GrandSundae stood)
--   300, r 104: WaffleWall (where the LollipopTree stood)
--   120, r 104: GummyBouncer_Mint, the small bouncer (where the CreamDispenser stood; no bounce logic yet)
-- With the ChocoWall at 60, r 56 and the two old ice pillars that makes 6 safe spots. A copy of Covery goes to
-- ServerStorage (BACKUP) first, RESTORE = true puts it back. Running it again changes nothing more; a template that is
-- not imported yet (assets/ArenaKit2/README.md) is skipped with a note, run it again after the import.

local RESTORE = false
local BACKUP = "MapBackup_2026-11-16_SafeWalls"
local FLOOR = 1.2 -- top of Arena_Boden
local SLOT = 4 -- studs: a model whose pivot lies this close to a slot stands on it

local ServerStorage = game:GetService("ServerStorage")
local map = workspace["Ice Cream Map"]
local kit = ServerStorage:WaitForChild("ArenaKit2")

if RESTORE then
	local copy = ServerStorage:FindFirstChild(BACKUP)
	assert(copy, "no backup " .. BACKUP)
	map.Covery:Destroy()
	copy.Covery:Clone().Parent = map
	print("[SafeWalls] restored Covery from " .. BACKUP)
	return "restored"
end

if not ServerStorage:FindFirstChild(BACKUP) then
	local copy = Instance.new("Folder")
	copy.Name = BACKUP
	map.Covery:Clone().Parent = copy
	copy.Parent = ServerStorage
end

local function slotPoint(deg: number, r: number): Vector3
	local a = math.rad(deg)
	return Vector3.new(math.cos(a) * r, FLOOR, math.sin(a) * r)
end

-- the model of `name` standing on the slot (by its pivot), if any
local function onSlot(name: string, deg: number, r: number): Model?
	local at = slotPoint(deg, r)
	for _, d in map.Covery:GetDescendants() do
		if d:IsA("Model") and d.Name == name then
			local p = d:GetPivot().Position
			if Vector3.new(p.X - at.X, 0, p.Z - at.Z).Magnitude <= SLOT then
				return d
			end
		end
	end
	return nil
end

local notes = {}
local folder = map.Covery:FindFirstChild("ArenaKit2") or map.Covery

for _, out in { { "LollipopTree", 300, 104 }, { "GrandSundae", 60, 104 }, { "CreamDispenser", 120, 104 } } do
	local model = onSlot(out[1], out[2], out[3])
	if model then
		model:Destroy()
		table.insert(notes, "removed " .. out[1])
	end
end

local CHANGES = {
	{ new = "WaffleWall", old = "WaffleArch", deg = 180, r = 56 },
	{ new = "ChocoWall", deg = 60, r = 104 },
	{ new = "WaffleWall", deg = 300, r = 104 },
	{ new = "GummyBouncer_Mint", deg = 120, r = 104 },
}
for _, change in CHANGES do
	if onSlot(change.new, change.deg, change.r) then
		continue -- already there
	end
	local template = kit:FindFirstChild(change.new)
	if not template then
		table.insert(notes, `skipped {change.new} at {change.deg}: no template ServerStorage.ArenaKit2.{change.new} yet`)
		continue
	end
	if change.old then
		local old = onSlot(change.old, change.deg, change.r)
		if old then
			old:Destroy()
			table.insert(notes, "removed " .. change.old)
		end
	end
	local model = template:Clone()
	model:PivotTo(CFrame.lookAt(slotPoint(change.deg, change.r), Vector3.new(0, FLOOR, 0))) -- front (-Z) to the machine
	model:SetAttribute("ArenaKit2Layout", true)
	model.Parent = folder
	table.insert(notes, `placed {change.new} at {change.deg} degrees, r {change.r}`)
end

local text = "[SafeWalls] " .. (if #notes > 0 then table.concat(notes, "; ") else "nothing to do")
print(text)
return text
