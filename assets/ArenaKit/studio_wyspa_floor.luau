--!nocheck
-- Paves the strip (r 135-171) and the hub ring (r 171-232) in Studio (Edit mode, run through the Studio MCP or the
-- command bar): rounded pink-cream paving stones like the plot paths (reference "Bonbon-Wege für Eiscremewelten"),
-- calm so the decoration placed on them later reads.
--
-- Only looks change: the visible walkable parts get the MaterialVariant WS_Pavers (Wyspa_Pavers, 12 studs per tile,
-- stones of 4 x 3 studs) and TINT as their colour (the part colour multiplies the picture: untinted, the pale stones
-- read as plain white under the island's sun and bloom, as the arena plates once did). Size, position, CanCollide and
-- CanQuery stay as they are, so landing rules, throws and walking are untouched. The invisible collision blocks
-- (Pas, transparency 1) are skipped. Everything paved is Locked against stray drags.
--   Wyspa.Ring          the hub ring, 90 blocks
--   Wyspa.Pas.Pas_Zewn  the strip's outer blocks
--   Wyspa.Pas.Pas_Bok   the strip beside the ramps
--   Wyspa.Brzeg         the strip's rounded edge meshes
-- The colours before are kept in ServerStorage."MapBackup_2026-11-04_WyspaFloor" (a copy of Wyspa without the core).
-- Picture: assets/ArenaKit/make_floor_textures.py (PAVERS).

local PAVERS = { name = "WS_Pavers", picture = "rbxassetid://135223614271030", studs = 12 }
local TINT = Color3.fromHex("#F2C2CB")

local wyspa = workspace["Ice Cream Map"].Wyspa
local SS = game:GetService("ServerStorage")
local MS = game:GetService("MaterialService")

local backupName = "MapBackup_2026-11-04_WyspaFloor"
if not SS:FindFirstChild(backupName) then
	local backup = Instance.new("Folder")
	backup.Name = backupName
	local copy = wyspa:Clone()
	local core = copy:FindFirstChild("Wyspa_Kern")
	if core then
		core:Destroy()
	end
	copy.Parent = backup
	backup.Parent = SS
end

local v = MS:FindFirstChild(PAVERS.name) or Instance.new("MaterialVariant")
v.Name = PAVERS.name
v.BaseMaterial = Enum.Material.SmoothPlastic
v.ColorMap = PAVERS.picture
v.StudsPerTile = PAVERS.studs
v.Parent = MS

local paved = {}
local function pave(part)
	if not part:IsA("BasePart") or part.Transparency >= 1 then
		return
	end
	part.Material = Enum.Material.SmoothPlastic
	part.MaterialVariant = PAVERS.name
	part.Color = TINT
	part.Locked = true
	paved[part.Name] = (paved[part.Name] or 0) + 1
end

for _, child in wyspa:GetChildren() do
	if child.Name == "Ring" then
		pave(child)
	end
end
for _, child in wyspa.Pas:GetChildren() do
	if child.Name == "Pas_Zewn" or child.Name == "Pas_Bok" then
		pave(child)
	end
end
for _, child in wyspa.Brzeg:GetChildren() do
	pave(child)
end

local out = {}
for name, n in paved do
	table.insert(out, `{name} {n}`)
end
table.sort(out)
return "paved: " .. table.concat(out, ", ")
