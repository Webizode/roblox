-- Studio (Edit, command bar or MCP), after Import 3D of Backpack_Waffle.fbx (assets/Backpack/README.md): makes the
-- waffle backpack's templates. Takes the four MeshParts Waffle, Lines, Rim and Glaze from the imported model in
-- Workspace (or wherever the import put them), makes them anchored, not colliding, not queried, and moves them to
-- ReplicatedStorage.BackpackKit, where Backpacks (client) finds them. The colours are set here for the look in Studio;
-- the client sets them again from Config/Backpack (the glaze per plot). Running it again replaces the kit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = { "Waffle", "Lines", "Rim", "Glaze" }
local COLOURS = { Waffle = "#E2AE62", Lines = "#A8692E", Rim = "#6A3F2A", Glaze = "#FFFFFF" }

local found = {}
for _, d in workspace:GetDescendants() do
	if d:IsA("MeshPart") and COLOURS[d.Name] and not found[d.Name] then
		local model = d:FindFirstAncestorWhichIsA("Model")
		if model and string.find(model.Name, "Backpack") then
			found[d.Name] = d
		end
	end
end
for _, name in NAMES do
	assert(found[name], "no MeshPart " .. name .. " in an imported Backpack model in Workspace")
end

local old = ReplicatedStorage:FindFirstChild("BackpackKit")
if old then
	old:Destroy()
end
local kit = Instance.new("Folder")
kit.Name = "BackpackKit"
local imported
for _, name in NAMES do
	local mesh = found[name]
	imported = imported or mesh:FindFirstAncestorWhichIsA("Model")
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.Massless = true
	mesh.Material = Enum.Material.SmoothPlastic
	mesh.Color = Color3.fromHex(COLOURS[name])
	for _, child in mesh:GetChildren() do
		if child:IsA("SurfaceAppearance") or child:IsA("Texture") or child:IsA("Decal") then
			child:Destroy() -- one colour per mesh, set by the client
		end
	end
	mesh.Parent = kit
end
kit.Parent = ReplicatedStorage
if imported and #imported:GetDescendants() == 0 then
	imported:Destroy()
end
local text = "[BackpackKit] " .. #kit:GetChildren() .. " meshes in ReplicatedStorage.BackpackKit"
print(text)
return text
