-- Written by gen_studio_meshy.js (round fix_18), do not edit. Run in Studio, Edit mode, then save the place.
local MAPS = {
	black_cherry = { maps = { "137338928798130", "118560023324972", "123891546462388" }, models = { 123530356586500, 116008661991035 }, LOD0 = Vector3.new(0, -0.04, 0), LOD1 = Vector3.new(-0.0107, -0.0406, -0.0096) },
	frosted_melon = { maps = { "111739325805401", "125824296858224", "125465380620723" }, models = { 129613583434870, 98719259563351 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(-0.0072, -0.0566, -0.0234) },
	honey_blossom = { maps = { "133866304717276", "73619217757283", "78591298362027" }, models = { 135332284682522, 134697068523657 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(0.0169, -0.048, 0.0007) },
	marzipan = { maps = { "113843608970819", "83858096830657", "85220885067377" }, models = { 80621062305368, 137361427060476 }, LOD0 = Vector3.new(0, -0.0359, 0), LOD1 = Vector3.new(-0.0133, -0.0589, 0) },
	midnight_berry = { maps = { "88364277451593", "135090481187192", "95459330692851" }, models = { 133599083730857, 84618940354787 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(-0.0169, -0.0494, -0.0031) },
	mystic_plum = { maps = { "83637674980978", "74112310089281", "98479476078636" }, models = { 117838443180593, 122722660581419 }, LOD0 = Vector3.new(0, -0.0157, 0), LOD1 = Vector3.new(0.0103, -0.0109, 0.032) },
	passion_fruit = { maps = { "105697092981189", "119830389904772", "110139965015147" }, models = { 75200053018746, 111123454104201 }, LOD0 = Vector3.new(0, 0.0147, 0), LOD1 = Vector3.new(0.0046, 0.0329, -0.009) },
	pistachio_cream = { maps = { "119772466799209", "98362732261145", "135039709913921" }, models = { 117880709292288, 98704851478655 }, LOD0 = Vector3.new(0, 0.0219, 0), LOD1 = Vector3.new(0.0152, 0.0227, 0.0043) },
	royal_cream = { maps = { "129799197156295", "125262130829509", "102853723311215" }, models = { 101416665188876, 85855050998974 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(0.0017, -0.0545, 0.0129) },
	salted_caramel = { maps = { "135715996988087", "98931232603717", "87398522738661" }, models = { 71633031088299, 107691337329848 }, LOD0 = Vector3.new(0, 0.0058, 0), LOD1 = Vector3.new(-0.0099, -0.0101, -0.0247) },
	sapphire_cream = { maps = { "107014069072446", "114427365670337", "135175269226226" }, models = { 110042564856011, 133453259193182 }, LOD0 = Vector3.new(0, -0.0404, 0), LOD1 = Vector3.new(0.0183, -0.0406, 0.0112) },
	white_chocolate = { maps = { "128128084178439", "125199477947248", "107042217698435" }, models = { 101404570641348, 85959408888545 }, LOD0 = Vector3.new(0, -0.0362, 0), LOD1 = Vector3.new(0.0082, -0.0432, -0.0104) },
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
