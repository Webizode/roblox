-- Written by gen_studio_meshy.js (round neu_8), do not edit. Run in Studio, Edit mode, then save the place.
local MAPS = {
	arctic_coconut = { maps = { "137664846673709", "131257253167056", "83232056825524" }, models = { 99123263229674, 100706872985249 }, LOD0 = Vector3.new(0, -0.0498, 0), LOD1 = Vector3.new(0.0045, -0.0511, 0.0049) },
	cheesecake = { maps = { "140313415207580", "122507313532969", "129606029501095" }, models = { 108133794477197, 106668953868401 }, LOD0 = Vector3.new(0, -0.04, 0), LOD1 = Vector3.new(-0.0126, -0.0313, -0.009) },
	cinnamon_roll = { maps = { "108101745545357", "138846856257600", "98863525506571" }, models = { 100592110990268, 84355923563755 }, LOD0 = Vector3.new(0, -0.0111, 0), LOD1 = Vector3.new(-0.0197, 0.0046, 0.0046) },
	crimson_velvet = { maps = { "100528998307566", "83601983057218", "96260173747857" }, models = { 100404554561971, 90326261786746 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(0.0046, -0.0659, -0.012) },
	mocha = { maps = { "117315285503017", "136685470630106", "126398181520945" }, models = { 78067254998967, 96308535424408 }, LOD0 = Vector3.new(0, 0.0127, 0), LOD1 = Vector3.new(-0.0125, 0.0102, -0.0048) },
	tiramisu = { maps = { "91812708318071", "103197923467524", "86556775293263" }, models = { 76855348892541, 118878686030092 }, LOD0 = Vector3.new(0, -0.003, 0), LOD1 = Vector3.new(0.0015, 0.0079, 0.0019) },
	velvet_dream = { maps = { "70791743494647", "114122322702542", "81721167130879" }, models = { 136704506750068, 99434710150350 }, LOD0 = Vector3.new(0, -0.017, 0), LOD1 = Vector3.new(0.0098, -0.0263, 0.0071) },
	velvet_mocha = { maps = { "112482848704479", "107410244820953", "74743135380239" }, models = { 132076202158949, 73407010604355 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(-0.0005, -0.0841, 0.0011) },
}
local BACKUP = "TowerScoopsMeshy_Beiwerk"

local IS = game:GetService("InsertService")
local root = game.ReplicatedStorage:WaitForChild("TowerScoops")
local function folderIn(name)
	local f = game.ServerStorage:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = game.ServerStorage
	end
	return f
end
local before = folderIn("TowerScoopsBefore_Meshy")
local made, failed = {}, {}
for fid, spec in MAPS do
	local folder = Instance.new("Folder")
	folder.Name = fid
	folder:SetAttribute("Source", "meshy")
	local ok = true
	for i, lod in { "LOD0", "LOD1" } do
		local got, model = pcall(IS.LoadAsset, IS, spec.models[i])
		local source = got and model:FindFirstChildWhichIsA("MeshPart", true)
		if not source then
			ok = false
			table.insert(failed, fid .. " " .. lod)
			break
		end
		local part = source:Clone()
		model:Destroy()
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
	end
	if ok then
		local old = root:FindFirstChild(fid)
		if old then
			if old:GetAttribute("Source") ~= "meshy" and not before:FindFirstChild(fid) then
				old.Parent = before
			elseif old:GetAttribute("Source") == "meshy" and BACKUP ~= "" then
				local keep = folderIn(BACKUP)
				local prev = keep:FindFirstChild(fid)
				if prev then
					prev:Destroy()
				end
				old.Parent = keep
			else
				old:Destroy()
			end
		end
		folder.Parent = root
		table.insert(made, fid)
	end
end
table.sort(made)
return `made ${#made}: ${table.concat(made, ", ")} | failed: ${table.concat(failed, ", ")}`
