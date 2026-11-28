// Writes the Studio script that builds the Meshy tower scoop templates of one round (node gen_studio_meshy.js <round>
// [<backup folder>]): reads meshy/models_<round>.json ({ flavor: [LOD0 model id, LOD1 model id] }, the Open Cloud
// uploads of build_meshy.py's FBX), meshy/uploaded.json (texture ids, written by the upload step; the model ids are added)
// and meshy/<flavor>_report.json (bounding box centres). Output: studio_meshy_<round>.luau. In Studio (Edit mode) it
// loads each model with InsertService:LoadAsset, makes LOD0/LOD1 with Meshy's maps as a SurfaceAppearance and the
// attribute Centre (Open Cloud turns the FBX half round the up axis like the importer, so X and Z flip), and puts the
// folder into ReplicatedStorage.TowerScoops. The folder it replaces: a non-Meshy one goes to
// ServerStorage.TowerScoopsBefore_Meshy (kept once); a Meshy one goes to the backup folder if one is given (the
// versions with big toppings, kept for icons and the index), else it is dropped.
const fs = require("fs");
const path = require("path");
const dir = path.join(__dirname, "meshy");
const round = process.argv[2];
const backup = process.argv[3] || "";
const models = JSON.parse(fs.readFileSync(path.join(dir, `models_${round}.json`), "utf8"));
const up = JSON.parse(fs.readFileSync(path.join(dir, "uploaded.json"), "utf8"));
const id = (s) => String(s).replace("rbxassetid://", "");
const lines = [];
for (const f of Object.keys(models).sort()) {
	const r = JSON.parse(fs.readFileSync(path.join(dir, `${f}_report.json`), "utf8"));
	const [m0, m1] = models[f];
	up[`${f}_LOD0.fbx`] = `rbxassetid://${m0}`;
	up[`${f}_LOD1.fbx`] = `rbxassetid://${m1}`;
	const maps = ["color", "normal", "rough"].map((k) => {
		const v = up[`${f}_${k}.png`];
		if (!v) throw new Error(`no upload for ${f} ${k}`);
		return `"${id(v)}"`;
	});
	const c0 = r.lods.LOD0.centre.join(", ");
	const c1 = r.lods.LOD1.centre.join(", ");
	lines.push(
		`\t${f} = { maps = { ${maps.join(", ")} }, models = { ${m0}, ${m1} }, LOD0 = Vector3.new(${c0}), LOD1 = Vector3.new(${c1}) },`
	);
}
fs.writeFileSync(path.join(dir, "uploaded.json"), JSON.stringify(up, null, 1) + "\n");
const body = `-- Written by gen_studio_meshy.js (round ${round}), do not edit. Run in Studio, Edit mode, then save the place.
local MAPS = {
${lines.join("\n")}
}
local BACKUP = "${backup}"

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
return \`made \${#made}: \${table.concat(made, ", ")} | failed: \${table.concat(failed, ", ")}\`
`;
fs.writeFileSync(path.join(__dirname, `studio_meshy_${round}.luau`), body);
console.log(`studio_meshy_${round}.luau: ${lines.length} flavors`);
