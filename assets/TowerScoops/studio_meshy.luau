-- Runs in Studio (Studio MCP execute_luau or the command bar, Edit mode): turns the imported Meshy scoops
-- (build_meshy.py, FBX from Desktop\roblox-assets\TowerScoops\meshy_scoops\<round>, uploaded as Model assets through
-- Open Cloud and put into the Workspace with InsertService:LoadAsset, or imported by hand; MeshParts TS_<flavor>_<LOD>;
-- the uploaded asset ids are in meshy/uploaded.json)
-- into the templates in ReplicatedStorage.TowerScoops, like studio_rollout.luau: the mesh, Meshy's maps as a
-- SurfaceAppearance (both LODs share them, meshy/uploaded.json), the attribute Centre from meshy/<flavor>_report.json
-- (the importer turns the FBX half round the up axis, so X and Z of the report's centre flip). The flavor's current
-- folder goes to ServerStorage.TowerScoopsBefore_Meshy (kept, never overwritten). Save the place afterwards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- per flavor: ColorMap, NormalMap, RoughnessMap ids and per LOD the report's bounding box centre
local MAPS = {
	royal_cream = {
		maps = { "125950365197995", "125262130829509", "102853723311215" },
		LOD0 = Vector3.new(0.0, -0.06, 0.0),
		LOD1 = Vector3.new(0.0157, 0.0058, 0.0419),
	},
	tiramisu = {
		maps = { "86201900012206", "91585463176402", "122795225560932" },
		LOD0 = Vector3.new(0.0, -0.06, 0.0),
		LOD1 = Vector3.new(0.0052, -0.0798, -0.0294),
	},
}

local found = {}
for _, item in workspace:GetDescendants() do
	if item:IsA("MeshPart") and string.match(item.Name, "^TS_") then
		found[item.Name] = item
	end
end
local root = ReplicatedStorage:WaitForChild("TowerScoops")
local before = ServerStorage:FindFirstChild("TowerScoopsBefore_Meshy")
if not before then
	before = Instance.new("Folder")
	before.Name = "TowerScoopsBefore_Meshy"
	before.Parent = ServerStorage
end
local made, skipped = {}, {}
for flavorId, spec in MAPS do
	local sources = { LOD0 = found[`TS_{flavorId}_LOD0`], LOD1 = found[`TS_{flavorId}_LOD1`] }
	if not sources.LOD0 or not sources.LOD1 then
		table.insert(skipped, flavorId)
		continue
	end
	local folder = Instance.new("Folder")
	folder.Name = flavorId
	folder:SetAttribute("Source", "meshy")
	for _, lod in { "LOD0", "LOD1" } do
		local source = sources[lod]
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
		local c = spec[lod]
		part:SetAttribute("Centre", -Vector3.new(-c.X, c.Y, -c.Z))
		local look = Instance.new("SurfaceAppearance")
		look.ColorMap = "rbxassetid://" .. spec.maps[1]
		look.NormalMap = "rbxassetid://" .. spec.maps[2]
		look.RoughnessMap = "rbxassetid://" .. spec.maps[3]
		look.AlphaMode = Enum.AlphaMode.Overlay
		look.Parent = part
		part.Parent = folder
		-- the import (or InsertService:LoadAsset of the Open Cloud upload) may nest it in models: all of it goes
		local top = source
		while top.Parent and top.Parent ~= workspace do
			top = top.Parent
		end
		top:Destroy()
	end
	local old = root:FindFirstChild(flavorId)
	if old then
		if before:FindFirstChild(flavorId) then
			old:Destroy() -- an earlier Meshy try; the original stays kept
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
