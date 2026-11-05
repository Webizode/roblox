--!nocheck
-- Turns imported plot kit models into templates (Edit mode, run in the command bar or through the Studio MCP): every
-- Model in Workspace named PlotKit_<Model> (as the 3D importer names PlotKit_<Model>.fbx from
-- Desktop\roblox-assets\PlotKit, assets/PlotKit/README.md).
--   * each MeshPart <Model>_<Colour> (and <Model>_Lid_<Colour>, <Model>_Face_<Colour>) gets its game colour
--     (GAME_COLOURS = plotkit.py GAME_COLOURS), the attribute Colour, SmoothPlastic, Anchored, and neither collides nor
--     takes queries or touches. The glass (Colour Glass) is SkyBlue and GLASS_TRANSPARENCY see-through.
--   * the model gets the simple collision of COLLISION below: invisible Parts `Collision` (the first, the PrimaryPart),
--     `Collision_<Name>` for more; the pivot stays at the bottom centre. Path stones get none (walkable decoration).
--   * the Scoop Chest's lid parts go into a Model `Lid` with a Part `Hinge` (invisible, no collision) on the hinge
--     line, so code can turn the lid about the hinge's X axis later.
--   * the Plot Sign's face (PlotSign_Face_Cream) gets the attribute TextFace = "Front": the SurfaceGui for name and
--     level goes there later (by code).
--   * the import moves to ServerStorage.PlotKit.<Model> (a template there is replaced).
-- Coordinates below are Roblox studs in the model's frame (x right, y up, z towards the back; the front, where a
-- player stands, is -Z), measured from the pivot. Run again after a fresh import: it is safe to repeat.

local GAME_COLOURS = {
	Cream = "#FFE9D0",
	Pink = "#F06AAE",
	Waffle = "#E2782C",
	SkyBlue = "#75D6F2",
	Gold = "#F2A83C",
	Cherry = "#E8384F",
	Glass = "#75D6F2",
	Stone = "#E2A4B4",
}
local GLASS_TRANSPARENCY = 0.55

-- per model: boxes or upright cylinders, { kind, size = Vector3 (x, y, z; a cylinder: height, diameter, diameter),
-- centre = Vector3 }; none for the paths
-- (assets/PlotKit/plotkit_models.json, Blender x y z turned into Roblox x z y; Sell Cart, Working Station and Scoop
-- Chest built 1.5 times, the Plot Sign 1.3 times the first size; the counters of cart and station at 3.5)
local COLLISION = {
	SellCart = { { kind = "box", size = Vector3.new(17.4, 3.525, 9.3), centre = Vector3.new(0, 1.7625, 0) } },
	WorkingStation = {
		{ kind = "box", name = "Counter", size = Vector3.new(16.8, 3.525, 2.85), centre = Vector3.new(0, 1.7625, -3.0) },
		{ kind = "box", name = "Wall", size = Vector3.new(17.7, 14.1, 1.2), centre = Vector3.new(0, 7.05, 4.8) },
		{
			kind = "box",
			name = "SideL",
			size = Vector3.new(9.45, 13.95, 10.2),
			centre = Vector3.new(-12.675, 6.975, 0.3),
		},
		{ kind = "box", name = "SideR", size = Vector3.new(9.45, 13.95, 10.2), centre = Vector3.new(12.675, 6.975, 0.3) },
	},
	ScoopChest = { { kind = "box", size = Vector3.new(13.95, 9.9, 7.95), centre = Vector3.new(0, 4.95, 0) } },
	PlotSign = { { kind = "box", size = Vector3.new(11.18, 8.97, 1.56), centre = Vector3.new(0, 4.485, 0) } },
	-- the same post in both fence pieces: in a FenceSection it stands at its left end (x -4)
	FencePost = { { kind = "box", size = Vector3.new(1.65, 4.05, 1.65), centre = Vector3.new(0, 2.025, 0) } },
	FenceSection = {
		{ kind = "box", name = "Post", size = Vector3.new(1.65, 4.05, 1.65), centre = Vector3.new(-4, 2.025, 0) },
		{ kind = "box", name = "Rails", size = Vector3.new(7.55, 3.375, 0.6), centre = Vector3.new(0.225, 1.6875, 0) },
	},
	PathStraight = {},
	PathCurve = {},
	PathRound = {},
}
-- the Scoop Chest's hinge line (along X), from the pivot
local HINGE = { ScoopChest = Vector3.new(0, 9.0, 2.55) }

local SS = game:GetService("ServerStorage")
local folder = SS:FindFirstChild("PlotKit") or Instance.new("Folder")
folder.Name = "PlotKit"
folder.Parent = SS

local function invisible(name, cframe, size, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cframe
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local UP = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis (X) pointing up

local report = {}
for _, model in workspace:GetChildren() do
	if not (model:IsA("Model") and model.Name:sub(1, 8) == "PlotKit_") then
		continue
	end
	local name = model.Name:sub(9)
	local pivot = model:GetPivot()
	local coloured, unknown = 0, {}
	local lidParts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("MeshPart") then
			local colour = part.Name:match("_(%a+)$")
			local hex = colour and GAME_COLOURS[colour]
			if hex then
				part.Color = Color3.fromHex(hex)
				part:SetAttribute("Colour", colour)
				coloured += 1
			else
				table.insert(unknown, part.Name)
			end
			part.Material = Enum.Material.SmoothPlastic
			part.Transparency = if colour == "Glass" then GLASS_TRANSPARENCY else 0
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			if part.Name:find("_Lid_") then
				table.insert(lidParts, part)
			end
			if part.Name:find("_Face_") then
				part:SetAttribute("TextFace", "Front")
			end
		end
	end
	for _, old in model:GetChildren() do
		if old:IsA("Part") and old.Name:sub(1, 9) == "Collision" then
			old:Destroy()
		end
	end
	local primary
	for i, spec in COLLISION[name] or {} do
		local at = pivot * CFrame.new(spec.centre)
		local part
		if spec.kind == "cylinder" then
			part = invisible("Collision", at * UP, spec.size, Enum.PartType.Cylinder)
		else
			part = invisible("Collision", at, spec.size)
		end
		if i > 1 or spec.name then
			part.Name = if i == 1 then "Collision" else "Collision_" .. (spec.name or tostring(i))
		end
		part.Parent = model
		primary = primary or part
	end
	if #lidParts > 0 then
		local lid = model:FindFirstChild("Lid") or Instance.new("Model")
		lid.Name = "Lid"
		lid.Parent = model
		for _, part in lidParts do
			part.Parent = lid
		end
		local hinge = lid:FindFirstChild("Hinge") or invisible("Hinge", CFrame.new(), Vector3.new(0.2, 0.2, 0.2))
		hinge.CFrame = pivot * CFrame.new(HINGE[name] or Vector3.zero)
		hinge.CanCollide = false
		hinge.CanQuery = false
		hinge.Parent = lid
		lid.PrimaryPart = hinge
	end
	if primary then
		model.PrimaryPart = primary
		primary.PivotOffset = primary.CFrame:ToObjectSpace(pivot)
	else
		model.WorldPivot = pivot
	end
	local old = folder:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	model.Name = name
	model.Parent = folder
	table.insert(
		report,
		`{name}: {coloured} meshes coloured{#unknown > 0 and " (no colour: " .. table.concat(unknown, ", ") .. ")" or ""}, {#(COLLISION[name] or {})} collision parts{#lidParts > 0 and ", lid with hinge" or ""}`
	)
end
return #report > 0 and table.concat(report, "\n") or "no PlotKit_* model in Workspace"
