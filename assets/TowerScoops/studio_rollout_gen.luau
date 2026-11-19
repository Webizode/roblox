-- Lune, not Studio: writes assets/TowerScoops/studio_rollout.luau, the Studio script that turns the imported rollout
-- scoops (build_rollout.py) into templates, the same way studio_proto.luau does for the prototypes.
--   lune run assets/TowerScoops/studio_rollout_gen.luau
-- Reads proto2/<flavor>_report.json (the bounding box centres) and proto2/uploaded.json (the texture ids from the
-- Studio MCP upload_image: { "<flavor>_<LOD>_<color|normal|rough>.png": "rbxassetid://..." }).
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local dir = "assets/TowerScoops/proto2"
local uploaded = serde.decode("json", fs.readFile(dir .. "/uploaded.json"))

local flavors = {}
for _, name in fs.readDir(dir) do
	local id = string.match(name, "^(.+)_report%.json$")
	if id and uploaded[`{id}_LOD0_color.png`] then
		table.insert(flavors, id)
	end
end
table.sort(flavors)

local function num(x: number): string
	return string.format("%.4f", x)
end

local lines = {}
for _, id in flavors do
	local report = serde.decode("json", fs.readFile(`{dir}/{id}_report.json`))
	local parts = {}
	for _, lod in { "LOD0", "LOD1" } do
		local c = report.lods[lod].centre
		local function tex(kind)
			local value = uploaded[`{id}_{lod}_{kind}.png`]
			assert(value, `no upload for {id} {lod} {kind}`)
			return string.match(value, "%d+")
		end
		table.insert(
			parts,
			`{lod} = \{ "{tex("color")}", "{tex("normal")}", "{tex("rough")}", Vector3.new({num(c[1])}, {num(c[2])}, {num(c[3])}) \}`
		)
	end
	table.insert(lines, `\t{id} = \{ {table.concat(parts, ", ")} \},`)
end

local source = [[
-- Written by studio_rollout_gen.luau, do not edit. Runs in Studio (Studio MCP execute_luau or the command bar, Edit
-- mode): turns the imported rollout scoops (build_rollout.py, FBX from Desktop\roblox-assets\TowerScoops\proto2,
-- imported into the Workspace as TS_<flavor>_<LOD>) into the templates in ReplicatedStorage.TowerScoops, like
-- studio_proto.luau: the mesh, the baked maps as a SurfaceAppearance, the attribute Centre (the importer turns the FBX
-- half round the up axis, so X and Z of the report's centre flip). A flavor's old folder goes to
-- ServerStorage.TowerScoopsBefore_Proto2 (once). Flavors not imported yet are skipped. Save the place afterwards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- per flavor and LOD: ColorMap, NormalMap, RoughnessMap ids and the report's bounding box centre
local MAPS = {
%s
}

local found = {}
for _, item in workspace:GetDescendants() do
	if item:IsA("MeshPart") and string.match(item.Name, "^TS_") then
		found[item.Name] = item
	end
end
local root = ReplicatedStorage:WaitForChild("TowerScoops")
local before = ServerStorage:FindFirstChild("TowerScoopsBefore_Proto2")
if not before then
	before = Instance.new("Folder")
	before.Name = "TowerScoopsBefore_Proto2"
	before.Parent = ServerStorage
end
local made, skipped = {}, {}
for flavorId, lods in MAPS do
	local sources = { LOD0 = found[`TS_{flavorId}_LOD0`], LOD1 = found[`TS_{flavorId}_LOD1`] }
	if not sources.LOD0 or not sources.LOD1 then
		table.insert(skipped, flavorId)
		continue
	end
	local folder = Instance.new("Folder")
	folder.Name = flavorId
	for _, lod in { "LOD0", "LOD1" } do
		local source = sources[lod]
		local maps = lods[lod]
		local part = source:Clone()
		for _, child in part:GetChildren() do
			child:Destroy()
		end
		part.Name = lod
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Material = Enum.Material.SmoothPlastic
		part.CFrame = CFrame.identity
		local c = maps[4]
		part:SetAttribute("Centre", -Vector3.new(-c.X, c.Y, -c.Z))
		local look = Instance.new("SurfaceAppearance")
		look.ColorMap = "rbxassetid://" .. maps[1]
		look.NormalMap = "rbxassetid://" .. maps[2]
		look.RoughnessMap = "rbxassetid://" .. maps[3]
		look.AlphaMode = Enum.AlphaMode.Overlay
		look.Parent = part
		part.Parent = folder
		local model = source:FindFirstAncestorOfClass("Model")
		if model and model.Parent == workspace then
			model:Destroy()
		else
			source:Destroy()
		end
	end
	local old = root:FindFirstChild(flavorId)
	if old then
		if before:FindFirstChild(flavorId) then
			old:Destroy()
		else
			old.Parent = before
		end
	end
	folder.Parent = root
	table.insert(made, flavorId)
end
table.sort(made)
table.sort(skipped)
return `made {#made}: {table.concat(made, ", ")}; skipped {#skipped}: {table.concat(skipped, ", ")}`
]]

fs.writeFile("assets/TowerScoops/studio_rollout.luau", string.format(source, table.concat(lines, "\n")))
print(`studio_rollout.luau: {#flavors} flavors`)
