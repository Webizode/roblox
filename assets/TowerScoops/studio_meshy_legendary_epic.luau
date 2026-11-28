-- Round legendary_epic (28.11.2026): builds the templates in ReplicatedStorage.TowerScoops for the Meshy scoops of this
-- round straight from the Open Cloud uploads (build_meshy.py FBX -> /assets/v1/assets Model -> InsertService:LoadAsset),
-- like studio_meshy.luau; no import by hand. Old folders go to ServerStorage.TowerScoopsBefore_Meshy (kept once).
-- velvet_dream and arctic_coconut are left out (Meshy made a flat top, kept the old scoops). Run in Edit mode, save.
local MAPS = {
	white_chocolate = { maps = { "76969198256830", "125199477947248", "107042217698435" }, models = { 138756928535099, 108880029467107 }, LOD0 = Vector3.new(0, -0.0344, 0), LOD1 = Vector3.new(-0.0023, -0.0001, 0.0064) },
	black_cherry = { maps = { "132462811896037", "118560023324972", "123891546462388" }, models = { 94247070660087, 79773826510475 }, LOD0 = Vector3.new(0, -0.0213, 0), LOD1 = Vector3.new(0.0037, -0.0313, -0.0032) },
	pistachio_cream = { maps = { "86080972493895", "98362732261145", "135039709913921" }, models = { 136110345876704, 79614136516927 }, LOD0 = Vector3.new(0, 0.0022, 0), LOD1 = Vector3.new(-0.0317, 0.0142, -0.0151) },
	salted_caramel = { maps = { "75922116043504", "98931232603717", "126875274433954" }, models = { 83287263937020, 136301982531723 }, LOD0 = Vector3.new(0, -0.0456, 0), LOD1 = Vector3.new(0.0075, -0.0692, 0.0164) },
	marzipan = { maps = { "110586926052929", "83858096830657", "85220885067377" }, models = { 117416697198311, 80807783164534 }, LOD0 = Vector3.new(0, -0.0491, 0), LOD1 = Vector3.new(-0.0604, -0.0841, -0.0197) },
	cinnamon_roll = { maps = { "93233760098204", "106758919928274", "91256466627507" }, models = { 113150657216309, 108798575288501 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(0.0278, -0.0852, 0.0016) },
	cheesecake = { maps = { "127307860274097", "119601701179361", "138403710554348" }, models = { 100127376855320, 96860096032000 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(0.0456, -0.0856, 0.0094) },
	mocha = { maps = { "131362338299934", "117054001526167", "116571895847689" }, models = { 137126615379412, 111674498813973 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(-0.0196, -0.0848, 0.0008) },
	passion_fruit = { maps = { "98399733989064", "119830389904772", "110139965015147" }, models = { 140317096942398, 75219795626247 }, LOD0 = Vector3.new(0, -0.0468, 0), LOD1 = Vector3.new(-0.0297, -0.051, -0.0029) },
	midnight_berry = { maps = { "134379183112487", "135090481187192", "95459330692851" }, models = { 127837325608052, 120367352439620 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(-0.0173, -0.0344, 0.0199) },
	frosted_melon = { maps = { "75560469613348", "125824296858224", "125465380620723" }, models = { 114939000559511, 99580549337026 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(-0.0121, -0.0538, -0.0265) },
	mystic_plum = { maps = { "125337757164095", "74112310089281", "98479476078636" }, models = { 84753528978940, 81170502977676 }, LOD0 = Vector3.new(0, -0.0534, 0), LOD1 = Vector3.new(0.0114, -0.0569, 0.0048) },
	crimson_velvet = { maps = { "115673237814886", "73517798305122", "121632912000959" }, models = { 102886705007263, 129621813174774 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(-0.0103, -0.035, -0.0132) },
	honey_blossom = { maps = { "72428158760289", "73619217757283", "78591298362027" }, models = { 95297366752581, 117298096867318 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(0.0057, -0.0525, -0.0027) },
	velvet_mocha = { maps = { "137173707771343", "113164353301700", "119621445998595" }, models = { 132481566430144, 102782244870825 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(-0.0108, -0.0757, -0.0618) },
	sapphire_cream = { maps = { "110796233825398", "114427365670337", "135175269226226" }, models = { 72197819309362, 99317221594571 }, LOD0 = Vector3.new(0, -0.06, 0), LOD1 = Vector3.new(0.0597, -0.0436, -0.0066) },
}

local IS = game:GetService("InsertService")
local root = game.ReplicatedStorage:WaitForChild("TowerScoops")
local before = game.ServerStorage:FindFirstChild("TowerScoopsBefore_Meshy")
if not before then
	before = Instance.new("Folder")
	before.Name = "TowerScoopsBefore_Meshy"
	before.Parent = game.ServerStorage
end
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
		-- Open Cloud turns the FBX half round the up axis like the importer: X and Z of the report's centre flip
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
			if before:FindFirstChild(fid) then
				old:Destroy()
			else
				old.Parent = before
			end
		end
		folder.Parent = root
		table.insert(made, fid)
	end
end
table.sort(made)
return `made {#made}: {table.concat(made, ", ")} | failed: {table.concat(failed, ", ")}`
