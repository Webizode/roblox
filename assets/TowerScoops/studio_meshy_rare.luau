-- Written by gen_studio_meshy.js (round rare), do not edit. Run in Studio, Edit mode, then save the place.
local MAPS = {
	birthday_cake = { maps = { "86065330213755", "89615914969476", "101536160799792" }, models = { 78684833048516, 111428181214985 }, LOD0 = Vector3.new(0, 0.0032, 0), LOD1 = Vector3.new(0.0184, -0.0128, -0.0192) },
	brownie = { maps = { "84485279724512", "91073649930657", "113033687588157" }, models = { 129057692249105, 116300849960997 }, LOD0 = Vector3.new(0, 0.0012, 0), LOD1 = Vector3.new(-0.0028, 0.0026, 0.0032) },
	coffee = { maps = { "76697611922048", "123069948083816", "108639941222276" }, models = { 89783069355553, 80705931723338 }, LOD0 = Vector3.new(0, -0.0177, 0), LOD1 = Vector3.new(-0.0138, -0.0324, -0.0044) },
	cookies_cream = { maps = { "97857043610279", "137527035922751", "112840134845497" }, models = { 132282513431962, 72028078014142 }, LOD0 = Vector3.new(0, -0.0114, 0), LOD1 = Vector3.new(0.0043, -0.0006, -0.0055) },
	cotton_candy = { maps = { "104807922692466", "93693479760408", "123726265419363" }, models = { 85909680425514, 131121114657338 }, LOD0 = Vector3.new(0, -0.0134, 0), LOD1 = Vector3.new(0.0052, -0.0204, 0.0141) },
	dragon_fruit = { maps = { "118244983261053", "89329045932115", "122000862778173" }, models = { 75975280636005, 124001031175773 }, LOD0 = Vector3.new(0, -0.0273, 0), LOD1 = Vector3.new(-0.0004, -0.0255, -0.0127) },
	honey = { maps = { "100392572673813", "116477722110557", "95259852799990" }, models = { 128626513125309, 114668050166868 }, LOD0 = Vector3.new(0, -0.0309, 0), LOD1 = Vector3.new(-0.0098, -0.0321, 0.0052) },
	maple_syrup = { maps = { "124295821519932", "75834630172779", "134805776749586" }, models = { 124185251602438, 77297511543146 }, LOD0 = Vector3.new(0, -0.0344, 0), LOD1 = Vector3.new(-0.0019, -0.0398, -0.0098) },
	pomegranate = { maps = { "96612651773143", "92157466534586", "76574180722413" }, models = { 130130302923153, 98168346677869 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(0.0008, -0.0452, 0.0029) },
	red_velvet = { maps = { "117785613228186", "110864106016110", "70569577352356" }, models = { 120113598981432, 118659880627710 }, LOD0 = Vector3.new(0, 0.0234, 0), LOD1 = Vector3.new(-0.0091, -0.0077, 0.0038) },
}
local BACKUP = ""

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
