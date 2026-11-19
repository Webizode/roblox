-- Runs in Studio (Studio MCP execute_luau or the command bar, Edit mode, Rojo connected), not in the game. Builds the
-- templates of the rarer tower scoops (18.11.2026) in ReplicatedStorage.TowerScoops: one folder per flavor of
-- Config/ScoopPictures with LOD0 and LOD1, copies of the vanilla template's meshes (every rarer flavor has exactly the
-- base shape, build_rarities.py) with the flavor's own detail picture as a SurfaceAppearance in Overlay mode (and its
-- RoughnessMap for the glossy ones). The part's Color comes from Config/Flavors at runtime (ScoopModel). A flavor's
-- folder is replaced when it is there already, so it can run again after new pictures. Nothing is imported.
-- Afterwards save the place (File > Save), the templates live in the place, not in the repo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local pictures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ScoopPictures"))
local root = ReplicatedStorage:WaitForChild("TowerScoops")
local vanilla = root:WaitForChild("vanilla")

local made = 0
for flavorId, picture in pictures do
	local folder = Instance.new("Folder")
	folder.Name = flavorId
	for _, lod in { "LOD0", "LOD1" } do
		local source = vanilla:FindFirstChild(lod)
		if source then
			local part = source:Clone()
			for _, child in part:GetChildren() do
				child:Destroy() -- vanilla's own picture
			end
			local look = Instance.new("SurfaceAppearance")
			look.ColorMap = picture.details
			if picture.roughness then
				look.RoughnessMap = picture.roughness
			end
			look.AlphaMode = Enum.AlphaMode.Overlay
			look.Parent = part
			part.Parent = folder
		end
	end
	local old = root:FindFirstChild(flavorId)
	if old then
		old:Destroy()
	end
	folder.Parent = root
	made += 1
end
return `ReplicatedStorage.TowerScoops: {made} rarer flavors from the vanilla meshes`
