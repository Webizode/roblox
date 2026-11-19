-- Runs in Studio (Studio MCP execute_luau or the command bar, Edit mode), not in the game. Puts the prototype-2 tower
-- scoops (build_proto.py, 18.11.2026) into ReplicatedStorage.TowerScoops, so the game draws them.
-- Before: import the FBX files from Desktop\roblox-assets\TowerScoops\proto2 (<flavor>_LOD0.fbx and
-- <flavor>_LOD1.fbx, written by build_proto.py) into the Workspace: File > Import 3D, or Asset Manager > Importieren >
-- Import starten and then right-click > Einfügen on each mesh (done like that on 18.11.2026). The importer names
-- each MeshPart TS_<flavor>_<LOD>. (The Studio MCP cannot do this step: it can upload pictures, but publishing a mesh
-- through AssetService:CreateAssetAsync is refused, "not available yet", tested 18.11.2026.)
-- Then for each flavor in PICTURES this makes the folder with LOD0 and LOD1: the imported mesh, the baked maps as a
-- SurfaceAppearance (ColorMap with the AO baked in, NormalMap, RoughnessMap, uploaded from proto2/textures) and the
-- attribute Centre: the scoop's centre from the part's centre (the importer centres a mesh on its bounding box,
-- CENTRES is that box's centre from build_proto.py's report), ScoopModel places the scoop by it.
-- The folder a flavor had before goes to ServerStorage.TowerScoopsBefore_Proto2 (once); to go back, move it back
-- into ReplicatedStorage.TowerScoops. The imported copies are removed from the Workspace. Save the place afterwards.
-- A flavor whose import is missing is skipped and named in the report.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- the baked maps (Studio MCP upload_image from assets/TowerScoops/proto2/textures); mesh: the same LOD as a mesh
-- picture (proto2/meshes, build_proto.py mesh_png), for a later way in without the importer
local PICTURES: { [string]: { [string]: { mesh: string, color: string, normal: string, rough: string } } } = {
	vanilla = {
		LOD0 = {
			mesh = "rbxassetid://101684851791557",
			color = "rbxassetid://100545954489630",
			normal = "rbxassetid://99310944395368",
			rough = "rbxassetid://84843174757447",
		},
		LOD1 = {
			mesh = "rbxassetid://115440094113302",
			color = "rbxassetid://82247606454022",
			normal = "rbxassetid://132829084931890",
			rough = "rbxassetid://136937314564273",
		},
	},
	cookie = {
		LOD0 = {
			mesh = "rbxassetid://132088134129409",
			color = "rbxassetid://105971091558539",
			normal = "rbxassetid://77906272084201",
			rough = "rbxassetid://86840424470495",
		},
		LOD1 = {
			mesh = "rbxassetid://140527270455337",
			color = "rbxassetid://103407650035780",
			normal = "rbxassetid://137966166467066",
			rough = "rbxassetid://133758414330224",
		},
	},
	cherry = {
		LOD0 = {
			mesh = "rbxassetid://81154693498379",
			color = "rbxassetid://118966783657754",
			normal = "rbxassetid://125633841021570",
			rough = "rbxassetid://78479383246316",
		},
		LOD1 = {
			mesh = "rbxassetid://118397064232825",
			color = "rbxassetid://129204304374441",
			normal = "rbxassetid://88079230748407",
			rough = "rbxassetid://115621459188123",
		},
	},
	cookies_cream = {
		LOD0 = {
			mesh = "rbxassetid://75138858017936",
			color = "rbxassetid://134936457932106",
			normal = "rbxassetid://106249468431974",
			rough = "rbxassetid://106023364971655",
		},
		LOD1 = {
			mesh = "rbxassetid://122616127765716",
			color = "rbxassetid://132231220690060",
			normal = "rbxassetid://106883459012053",
			rough = "rbxassetid://84068751363574",
		},
	},
	royal_cream = {
		LOD0 = {
			mesh = "rbxassetid://125917413748781",
			color = "rbxassetid://83467895456062",
			normal = "rbxassetid://117610187636926",
			rough = "rbxassetid://86440078376730",
		},
		LOD1 = {
			mesh = "rbxassetid://125744254577361",
			color = "rbxassetid://80575747539502",
			normal = "rbxassetid://113869146285666",
			rough = "rbxassetid://122332497870998",
		},
	},
}

-- the centre of each LOD's bounding box from the scoop's centre, in build_proto.py's Roblox axes (x, z, -y)
-- (proto2/<flavor>_report.json). The 3D importer turns the FBX half round the up axis (tested 18.11.2026: the
-- imported cherry's toppings lie at -x and +z where the json has them at +x and -z), so X and Z flip below.
local CENTRES: { [string]: { [string]: Vector3 } } = {
	vanilla = { LOD0 = Vector3.new(0.0162, 0.0786, 0.0054), LOD1 = Vector3.new(0.0206, 0.0835, 0.0006) },
	cookie = { LOD0 = Vector3.new(-0.0283, 0.0721, 0.0163), LOD1 = Vector3.new(-0.027, 0.0587, 0.0447) },
	cherry = { LOD0 = Vector3.new(0.0083, 0.0746, 0.0981), LOD1 = Vector3.new(0.0117, 0.0845, 0.0908) },
	cookies_cream = { LOD0 = Vector3.new(0.0020, 0.0777, 0.0507), LOD1 = Vector3.new(0.0138, 0.0699, -0.0028) },
	royal_cream = { LOD0 = Vector3.new(0.0051, 0.3026, 0.0126), LOD1 = Vector3.new(0.002, 0.2708, 0.0026) },
}

local function imported(name: string): MeshPart?
	for _, item in workspace:GetDescendants() do
		if item:IsA("MeshPart") and item.Name == name then
			return item
		end
	end
	return nil
end

local root = ReplicatedStorage:WaitForChild("TowerScoops")
local before = ServerStorage:FindFirstChild("TowerScoopsBefore_Proto2")
if not before then
	before = Instance.new("Folder")
	before.Name = "TowerScoopsBefore_Proto2"
	before.Parent = ServerStorage
end

local report = {}
for flavorId, lods in PICTURES do
	local sources = { LOD0 = imported(`TS_{flavorId}_LOD0`), LOD1 = imported(`TS_{flavorId}_LOD1`) }
	if not sources.LOD0 or not sources.LOD1 then
		table.insert(report, `{flavorId}: not imported yet, skipped`)
		continue
	end
	local folder = Instance.new("Folder")
	folder.Name = flavorId
	for _, lod in { "LOD0", "LOD1" } do
		local source = sources[lod] :: MeshPart
		local part = source:Clone()
		for _, child in part:GetChildren() do
			child:Destroy() -- whatever the importer added
		end
		part.Name = lod
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Material = Enum.Material.SmoothPlastic
		part.CFrame = CFrame.identity
		local c = CENTRES[flavorId][lod]
		part:SetAttribute("Centre", -Vector3.new(-c.X, c.Y, -c.Z))
		local look = Instance.new("SurfaceAppearance")
		look.ColorMap = lods[lod].color
		look.NormalMap = lods[lod].normal
		look.RoughnessMap = lods[lod].rough
		look.AlphaMode = Enum.AlphaMode.Overlay
		look.Parent = part
		part.Parent = folder
		table.insert(report, `{flavorId} {lod}: {part.MeshId} size {part.Size}`)
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
end
return table.concat(report, "\n")
