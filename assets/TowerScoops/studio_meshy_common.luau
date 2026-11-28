-- Written by gen_studio_meshy.js (round common), do not edit. Run in Studio, Edit mode, then save the place.
local MAPS = {
	bubblegum = { maps = { "72692554927433", "103651657605922", "72351959108700" }, models = { 123008349390857, 136151599056152 }, LOD0 = Vector3.new(0, 0.0034, 0), LOD1 = Vector3.new(0.0146, 0.0035, 0.0045) },
	chocolate = { maps = { "123814087528431", "129344793214896", "120194003811500" }, models = { 94094085645128, 90260039133191 }, LOD0 = Vector3.new(0, 0.0054, 0), LOD1 = Vector3.new(-0.0104, -0.008, -0.0027) },
	cookie = { maps = { "90595717045074", "137735390622801", "120035240903280" }, models = { 95185998432615, 118935787943107 }, LOD0 = Vector3.new(0, -0.0558, 0), LOD1 = Vector3.new(-0.0006, -0.0564, 0.0172) },
	lemon = { maps = { "123390653606023", "79465598379255", "140421825630680" }, models = { 103521301160148, 108152057398991 }, LOD0 = Vector3.new(0, 0.0124, 0), LOD1 = Vector3.new(-0.0113, 0.0146, 0.0035) },
	mango = { maps = { "98855540643743", "70864779866543", "78142261999625" }, models = { 125958987473730, 113887786466427 }, LOD0 = Vector3.new(0, -0.0125, 0), LOD1 = Vector3.new(-0.0001, -0.0144, -0.0002) },
	mint = { maps = { "84673118532879", "136726510811288", "85505865689801" }, models = { 80469681398113, 93997871069948 }, LOD0 = Vector3.new(0, 0.0917, 0), LOD1 = Vector3.new(0.0047, 0.0951, -0.0047) },
	pistachio = { maps = { "99928643986079", "107507874863571", "73176928470654" }, models = { 89200388141349, 92061364347038 }, LOD0 = Vector3.new(0, -0.0504, 0), LOD1 = Vector3.new(-0.0122, -0.0649, 0.0046) },
	stracciatella = { maps = { "133994136150816", "138375748628619", "135577951416819" }, models = { 94822503018392, 106811918793753 }, LOD0 = Vector3.new(0, -0.0262, 0), LOD1 = Vector3.new(-0.0122, -0.0269, -0.006) },
	strawberry = { maps = { "108958876749723", "93371792841655", "106555377753657" }, models = { 139807452906002, 103053730566767 }, LOD0 = Vector3.new(0, -0.0207, 0), LOD1 = Vector3.new(-0.0028, -0.0185, 0.0047) },
	vanilla = { maps = { "125397310391379", "89246353207300", "109037231667727" }, models = { 88217945976056, 92568530868513 }, LOD0 = Vector3.new(0, -0.0121, 0), LOD1 = Vector3.new(-0.0037, -0.0079, -0.0067) },
	watermelon = { maps = { "120478613806402", "74456167315949", "99173458508029" }, models = { 109176223120494, 116507243951247 }, LOD0 = Vector3.new(0, 0.1252, 0), LOD1 = Vector3.new(0.0078, 0.1249, 0.0038) },
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
