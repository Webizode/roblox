-- Written by gen_studio_meshy.js (round uncommon), do not edit. Run in Studio, Edit mode, then save the place.
local MAPS = {
	blue_raspberry = { maps = { "105388355095447", "79233721006606", "139848943180073" }, models = { 133101812629359, 114014320148077 }, LOD0 = Vector3.new(0, 0.0012, 0), LOD1 = Vector3.new(-0.0134, 0.0126, 0.0038) },
	blueberry = { maps = { "137599134105766", "135084090990591", "98415953777919" }, models = { 130867952481736, 76919206401517 }, LOD0 = Vector3.new(0, -0.0297, 0), LOD1 = Vector3.new(0.0081, -0.028, 0.0042) },
	caramel = { maps = { "123797952682189", "138764040794553", "114533432586655" }, models = { 106902023174833, 100361748230512 }, LOD0 = Vector3.new(0, -0.0203, 0), LOD1 = Vector3.new(0.0113, -0.0227, -0.0001) },
	cherry = { maps = { "95005784121955", "87161886575995", "138748894960475" }, models = { 105075712150035, 83654866756390 }, LOD0 = Vector3.new(0, -0.0455, 0), LOD1 = Vector3.new(0.003, -0.056, -0.0117) },
	coconut = { maps = { "131803484594915", "73773835563885", "119808951514410" }, models = { 97113110920568, 115615567628898 }, LOD0 = Vector3.new(0, -0.0121, 0), LOD1 = Vector3.new(0.0005, 0.0043, -0.0006) },
	grape = { maps = { "85212541749587", "103416513750372", "126884436277783" }, models = { 70407019921292, 121003989117141 }, LOD0 = Vector3.new(0, -0.0228, 0), LOD1 = Vector3.new(0.0045, -0.0188, 0.004) },
	lime = { maps = { "118746457861156", "123392876013371", "88797716105269" }, models = { 71628497579885, 86584948016315 }, LOD0 = Vector3.new(0, -0.0255, 0), LOD1 = Vector3.new(-0.01, -0.0265, -0.0033) },
	orange = { maps = { "103812832769237", "123701304990275", "106913028622367" }, models = { 78451524714295, 139201019445005 }, LOD0 = Vector3.new(0, 0.0203, 0), LOD1 = Vector3.new(0.0023, 0.0164, 0.0131) },
	peach = { maps = { "104545315657085", "135305672363803", "129674402882917" }, models = { 126219827619629, 89080175744461 }, LOD0 = Vector3.new(0, -0.0176, 0), LOD1 = Vector3.new(0.0038, -0.0277, -0.002) },
	pineapple = { maps = { "105906484594278", "99837144602190", "138349383162153" }, models = { 95396334041723, 114801324928516 }, LOD0 = Vector3.new(0, -0.0164, 0), LOD1 = Vector3.new(0.0081, -0.03, 0.0159) },
	raspberry = { maps = { "83916017510611", "78391205400686", "72791554736976" }, models = { 136663046454419, 81251503271035 }, LOD0 = Vector3.new(0, 0.0009, 0), LOD1 = Vector3.new(0.001, -0.0039, 0.0044) },
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
