-- Runs in Studio (Studio MCP execute_luau or the command bar, Edit mode), not in the game. Turns a flavor's imported
-- tower scoop meshes into the templates the game draws (ScoopModel, Config/TowerScoops):
--   ReplicatedStorage.TowerScoops.<flavor> (Folder) with the MeshParts LOD0 (close) and LOD1 (far), each with the
--   flavor's detail picture as a SurfaceAppearance in Overlay mode, so the part's Color (the flavor's) shows under it.
-- Before: import <flavor>_LOD0.fbx and <flavor>_LOD1.fbx from Desktop\roblox-assets\TowerScoops (File > Import 3D,
-- written by export_scoops.py) into the Workspace, and upload the picture assets/TowerScoops/textures/
-- <flavor>_details.png (Studio MCP upload_image, served by `lune run scripts/tower-scoops-serve`). Set FLAVOR and DETAILS
-- (nil for a flavor without a picture) and ROUGHNESS. The imported copies are removed from the Workspace afterwards.
-- A flavor with exactly the base shape needs no import: SHAPE = "vanilla" takes the meshes from that template
-- (Roblox keeps one mesh asset for the same geometry anyway). Only a flavor with its own shape (lemon: the slice) is
-- imported.
-- Picture ids so far: vanilla rbxassetid://72113851695295, lemon rbxassetid://138934234671661, pistachio
-- rbxassetid://124468234134547 (roughness rbxassetid://107037254055453), watermelon rbxassetid://100281607998297,
-- chocolate rbxassetid://137837397247322 (roughness rbxassetid://75455599601348), strawberry
-- rbxassetid://123555076432522, mint rbxassetid://81577451475430, bubblegum rbxassetid://75389333694758, cookie
-- rbxassetid://71281576968525, mango rbxassetid://135679861254220, stracciatella rbxassetid://126393649920792

local FLAVOR = "vanilla"
local DETAILS: string? = "rbxassetid://72113851695295"
local ROUGHNESS: string? = nil -- <flavor>_roughness.png, only for a flavor with surface_roughness (pistachio)
local SHAPE: string? = nil -- a flavor of the very same shape to take the meshes from instead of an import

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function imported(lod: string): MeshPart?
	local name = `TS_{FLAVOR:sub(1, 1):upper()}{FLAVOR:sub(2)}_{lod}`
	for _, item in workspace:GetDescendants() do
		if item:IsA("MeshPart") and item.Name == name then
			return item
		end
	end
	return nil
end

local root = ReplicatedStorage:FindFirstChild("TowerScoops") or Instance.new("Folder")
root.Name = "TowerScoops"
local old = root:FindFirstChild(FLAVOR)
local folder = Instance.new("Folder")
folder.Name = FLAVOR
local report = {}
-- A LOD that was neither imported nor taken from SHAPE keeps the template it already has (so LOD1 can follow later);
-- without LOD1 the game draws LOD0 at every distance. LOD0 is needed.
for _, lod in { "LOD0", "LOD1" } do
	local source = imported(lod)
	local shared = SHAPE and root:FindFirstChild(SHAPE) and (root :: any)[SHAPE]:FindFirstChild(lod)
	local fromShape = source == nil and shared ~= nil
	source = source or shared
	local kept = old and old:FindFirstChild(lod)
	if not source then
		assert(lod ~= "LOD0" or kept, `no imported MeshPart for {FLAVOR} {lod} in the Workspace`)
		if kept then
			kept:Clone().Parent = folder
			table.insert(report, `{lod} kept`)
		else
			table.insert(report, `{lod} missing (import it and run again)`)
		end
		continue
	end
	local part = source:Clone()
	for _, child in part:GetChildren() do
		child:Destroy() -- whatever the importer added (a SurfaceAppearance without pictures, attachments)
	end
	part.Name = lod
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = CFrame.identity
	if DETAILS then
		local look = Instance.new("SurfaceAppearance")
		look.ColorMap = DETAILS
		if ROUGHNESS then
			look.RoughnessMap = ROUGHNESS
		end
		look.AlphaMode = Enum.AlphaMode.Overlay
		look.Parent = part
	end
	part.Parent = folder
	table.insert(report, `{lod} {part.MeshId}{if fromShape then ` (from {SHAPE})` else ""} size {part.Size}`)
	if not fromShape then
		local model = source:FindFirstAncestorOfClass("Model")
		if model and model.Parent == workspace then
			model:Destroy()
		else
			source:Destroy()
		end
	end
end
if old then
	old:Destroy()
end
folder.Parent = root
root.Parent = ReplicatedStorage
return `ReplicatedStorage.TowerScoops.{FLAVOR}: {table.concat(report, "; ")}`
