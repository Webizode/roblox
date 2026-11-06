--!nocheck
-- Gives each plot sector a flavour colour (Studio command bar, Edit mode). Only recolours existing parts.
-- A sector k is Plot_k, Rampa_k, Wejscie_k, Most_k (bridge, accent colour), the rim pieces on both sides of that
-- ramp, the strip side walls (Pas) and all arena cover within ramp angle +-15 degrees.
-- NEUTRALS recolours the shared surfaces: hub ring (Wyspa.Ring), strip with its brick wall towards the arena
-- (Wyspa.Brzeg_01..12) and the floor edge (Plac.Arena_Rand). Big Swirl and Emblem always stay.
-- Every changed part keeps its first colour in the attribute "FlavorOrigColor"; RESTORE = true puts it back.
-- The rules go by the colour name at the end of the part name, so running again with new values is safe.
-- Usage: set SECTORS ({ 1, 2 } or "all") and WALL, paste everything into the command bar, Enter.

local SECTORS = "all"
local RESTORE = false
local NEUTRALS = true
local WALL = "Vanille" -- "Vanille" or "Karamell": strip and brick wall towards the arena

local FLAVORS = {
	Mint = { main = "#7FE0B8", accent = "#2E9E78" },
	Zitrone = { main = "#FFE15A", accent = "#E0A21C" },
	Blaubeere = { main = "#6F7BEA", accent = "#3A3F9E" },
	Erdbeere = { main = "#FF7480", accent = "#C93A4E" },
	Lavendel = { main = "#BB9CF0", accent = "#7A55C4" },
	Mango = { main = "#FF6F12", accent = "#C2410C" },
	Schoko = { main = "#9A6244", accent = "#5A3320" },
	Pistazie = { main = "#B4D46A", accent = "#6F9132" },
	Bubblegum = { main = "#F06AAE", accent = "#A8327A" },
	Kirsche = { main = "#D7304E", accent = "#7E1631" },
	Karamell = { main = "#E8B877", accent = "#9C5A22" },
	Himmelblau = { main = "#75D6F2", accent = "#2C8FC9" },
}
-- Plot_01 .. Plot_12 in ring order; neighbours alternate warm and cool.
local PLOT_FLAVOR = {
	"Mint",
	"Mango",
	"Blaubeere",
	"Zitrone",
	"Lavendel",
	"Erdbeere",
	"Pistazie",
	"Bubblegum",
	"Karamell",
	"Himmelblau",
	"Schoko",
	"Kirsche",
}
-- Cover cycles through all flavours (step 5 is coprime with 12, so neighbours differ).
local COVER_ORDER = {}
for i = 0, 11 do
	COVER_ORDER[i + 1] = PLOT_FLAVOR[(i * 5) % 12 + 1]
end

local DARK_POST = Color3.fromHex("#6E4029") -- Schoko: posts, entrance and rim feet
local SOCKEL = Color3.fromHex("#A8683F") -- Karamell: island sides, strip side walls
local CREAM = Color3.fromHex("#FFE9D0")
-- The paver MaterialVariant looks white under sun and bloom, so the tints stay a bit stronger than they look.
local RING = Color3.fromHex("#F6DFB2") -- Vanille-Creme
local WALLS = {
	Vanille = { wall = Color3.fromHex("#F6DFB2"), edge = Color3.fromHex("#E8C690") },
	Karamell = { wall = Color3.fromHex("#D9A066"), edge = Color3.fromHex("#A8683F") },
}

local map = workspace["Ice Cream Map"]
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local changed, restored = 0, 0

local function rampAngle(k)
	return 75 - 30 * (k - 1)
end
local function angleOf(pos)
	return math.deg(math.atan2(pos.Z, pos.X)) % 360
end
local function angleDiff(a, b)
	return math.abs((a - b + 180) % 360 - 180)
end
local function sectorOf(pos)
	local a = angleOf(pos)
	for k = 1, 12 do
		if angleDiff(a, rampAngle(k)) < 15 then
			return k
		end
	end
	return 1
end
local function colorKey(name)
	return name:match("_([%a]+)$")
end

local function paint(part, color)
	if not color then
		return
	end
	if part:GetAttribute("FlavorOrigColor") == nil then
		part:SetAttribute("FlavorOrigColor", part.Color)
	end
	part.Color = color
	changed += 1
end
local function restore(root)
	local parts = root:GetDescendants()
	table.insert(parts, root)
	for _, d in parts do
		if d:IsA("BasePart") and d:GetAttribute("FlavorOrigColor") ~= nil then
			d.Color = d:GetAttribute("FlavorOrigColor")
			d:SetAttribute("FlavorOrigColor", nil)
			restored += 1
		end
	end
end

-- rule(part, key) returns the new colour or nil (keep)
local function apply(root, rule)
	local parts = root:IsA("BasePart") and { root } or root:GetDescendants()
	for _, d in parts do
		if d:IsA("BasePart") and d.Transparency < 1 then
			paint(d, rule(d, colorKey(d.Name)))
		end
	end
end

local function flavorColors(name)
	local f = FLAVORS[name]
	local m, a = Color3.fromHex(f.main), Color3.fromHex(f.accent)
	return m, a, m:Lerp(CREAM, 0.35)
end

local function plotRule(m, a, path)
	return function(part, key)
		local n = part.Name
		if n:match("^Wyspa_") then
			return SOCKEL
		elseif key == "Pink" then
			if n == "PathRound_Pink" then
				return a
			end
			return m
		elseif key == "Stone" then
			return path
		elseif key == "Cherry" then
			return a
		elseif key == "Waffle" and (n:match("^Fence") or n:match("^PlotSign")) then
			return DARK_POST
		elseif key == "Gold" and n:match("^PlotSign") then
			return a
		end
		return nil
	end
end
local function entranceRule(m, a)
	return function(_, key)
		if key == "Pink" then
			return m
		elseif key == "Gold" or key == "Cherry" then
			return a
		elseif key == "Waffle" then
			return DARK_POST
		end
		return nil
	end
end
local function rimRule(m, a)
	return function(_, key)
		if key == "Pink" then
			return m
		elseif key == "SkyBlue" then
			return a
		elseif key == "Waffle" then
			return DARK_POST
		end
		return nil
	end
end
local function coverRule(m, a)
	return function(_, key)
		if key == "Pink" then
			return m
		elseif key == "SkyBlue" or key == "Cherry" then
			return a
		end
		return nil
	end
end

local list = {}
if SECTORS == "all" then
	for k = 1, 12 do
		list[k] = true
	end
else
	for _, k in SECTORS do
		list[k] = true
	end
end

local function sectorRoots(k)
	local id = string.format("%02d", k)
	local prev = string.format("%02d", (k - 2) % 12 + 1)
	local rim = map.Dekoracje.ArenaRand
	return {
		plot = map.Plots["Plot_" .. id],
		ramp = map.Schody["Rampa_" .. id],
		entrance = map.Dekoracje.Wejscia["Wejscie_" .. id],
		bridge = map.Mosty["Most_" .. id],
		rim = {
			rim["RandSaeule_" .. id .. "a"],
			rim["RandWand_" .. id .. "a"],
			rim["RandSaeule_" .. prev .. "b"],
			rim["RandWand_" .. prev .. "b"],
		},
	}
end

-- every kit model is one cover (groups and subfolders are searched, like MapService does);
-- stable order by angle, then radius, over the whole arena, so a partial run matches the full one
local covers = {}
for _, c in map.Covery:GetDescendants() do
	if c:IsA("Model") and c:FindFirstChild("Collision") then
		table.insert(covers, c)
	end
end
table.sort(covers, function(x, y)
	local px, py = x:GetPivot().Position, y:GetPivot().Position
	local ax, ay = angleOf(px), angleOf(py)
	if math.abs(ax - ay) > 0.01 then
		return ax < ay
	end
	return px.Magnitude < py.Magnitude
end)

local neutrals = { map.Plac.Arena_Rand }
for _, d in map.Wyspa:GetDescendants() do
	if d:IsA("BasePart") and (d.Name == "Ring" or d.Name:match("^Brzeg_%d+$")) then
		table.insert(neutrals, d)
	end
end

local recording = ChangeHistoryService:TryBeginRecording("MapFlavors")

if RESTORE then
	for k in list do
		local r = sectorRoots(k)
		restore(r.plot)
		restore(r.ramp)
		restore(r.entrance)
		restore(r.bridge)
		for _, x in r.rim do
			restore(x)
		end
	end
	for _, d in map.Wyspa.Pas:GetChildren() do
		if list[sectorOf(d.Position)] then
			restore(d)
		end
	end
	for _, c in covers do
		if list[sectorOf(c:GetPivot().Position)] then
			restore(c)
		end
	end
	if NEUTRALS then
		for _, d in neutrals do
			restore(d)
		end
	end
else
	for k in list do
		local m, a, path = flavorColors(PLOT_FLAVOR[k])
		local r = sectorRoots(k)
		apply(r.plot, plotRule(m, a, path))
		paint(r.ramp, m)
		apply(r.entrance, entranceRule(m, a))
		apply(r.bridge, function()
			return a
		end)
		for _, x in r.rim do
			apply(x, rimRule(m, a))
		end
	end
	for _, d in map.Wyspa.Pas:GetChildren() do
		if d:IsA("BasePart") and d.Transparency < 1 and list[sectorOf(d.Position)] then
			paint(d, SOCKEL)
		end
	end
	for i, c in covers do
		if list[sectorOf(c:GetPivot().Position)] then
			local m, a = flavorColors(COVER_ORDER[(i - 1) % 12 + 1])
			apply(c, coverRule(m, a))
		end
	end
	if NEUTRALS then
		local w = WALLS[WALL]
		for _, d in neutrals do
			if d.Name == "Ring" then
				paint(d, RING)
			elseif d.Name == "Arena_Rand" then
				paint(d, w.edge)
			else
				paint(d, w.wall)
			end
		end
	end
end

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print(("MapFlavors: %d parts recoloured, %d restored"):format(changed, restored))
