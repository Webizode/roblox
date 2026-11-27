-- Makes the templates ServerStorage.MeshyKit.<Name> from the Meshy models imported into Workspace (Studio, Edit;
-- command bar or MCP). Before: import assets/Meshy/export/<Name>.glb with Studio's 3D importer (each arrives as a Model
-- "Scene" with one Model per piece, e.g. ScoopChest_Body or ScoopChest_Body_Node, ScoopChest_Body2_Node, ScoopChest_Lid_Node). Then studio_meshy_place.luau puts them on the
-- map. The numbers below come from assets/Meshy/export/<Name>.json (build.py, Blender coordinates, 1 unit = 1 stud).
--
-- Blender -> Roblox (the importer's turn already makes the front -Z): x -> -x, z (up) -> y, y (depth) -> z.
-- Every template: the meshes anchored, no collision, no queries (like the PlotKit meshes), a SurfaceAppearance with the
-- baked maps (assets/Meshy/maps.json), one invisible box `Collision` (the PrimaryPart, pivot at the bottom middle).
-- ScoopChest besides: `Lid` (a Model, PrimaryPart `Hinge` on the hinge axis, turns about its X like the PlotKit lid,
-- ChestController) and six attachments `ScoopSlot1`..`ScoopSlot6` on the body, one in each cup, numbered from the
-- player's left (seen from the front) for the equipped scoops.

local ServerStorage = game:GetService("ServerStorage")

local MAPS = {
	-- v2 (build_v2.py): Meshy's own colour and normal map, one flat roughness (0.8, the same image for every model), no
	-- metalness; the same maps on every piece of a model (two or three pieces, each under 20,000 triangles)
	ScoopChest_Body = {
		color = "rbxassetid://115926909588437",
		normal = "rbxassetid://77907438784258",
		rough = "rbxassetid://138538507465564",
	},
	ScoopChest_Body2 = {
		color = "rbxassetid://115926909588437",
		normal = "rbxassetid://77907438784258",
		rough = "rbxassetid://138538507465564",
	},
	ScoopChest_Lid = {
		color = "rbxassetid://115926909588437",
		normal = "rbxassetid://77907438784258",
		rough = "rbxassetid://138538507465564",
	},
	SellCart_Body = {
		color = "rbxassetid://96701779237747",
		normal = "rbxassetid://93216886852342",
		rough = "rbxassetid://138538507465564",
	},
	SellCart_Body2 = {
		color = "rbxassetid://96701779237747",
		normal = "rbxassetid://93216886852342",
		rough = "rbxassetid://138538507465564",
	},
	CraftingStation_Body = {
		color = "rbxassetid://117525937256746",
		normal = "rbxassetid://135341385859845",
		rough = "rbxassetid://138538507465564",
	},
	CraftingStation_Body2 = {
		color = "rbxassetid://117525937256746",
		normal = "rbxassetid://135341385859845",
		rough = "rbxassetid://138538507465564",
	},
	UpgradeShop_Body = {
		color = "rbxassetid://89487602286372",
		normal = "rbxassetid://139283367725078",
		rough = "rbxassetid://138538507465564",
	},
	UpgradeShop_Body2 = {
		color = "rbxassetid://89487602286372",
		normal = "rbxassetid://139283367725078",
		rough = "rbxassetid://138538507465564",
	},
	CosmeticShop_Body = {
		color = "rbxassetid://129152965669313",
		normal = "rbxassetid://114447792948551",
		rough = "rbxassetid://138538507465564",
	},
	CosmeticShop_Body2 = {
		color = "rbxassetid://129152965669313",
		normal = "rbxassetid://114447792948551",
		rough = "rbxassetid://138538507465564",
	},
	QuestHub_Body = {
		color = "rbxassetid://139572259598456",
		normal = "rbxassetid://114955266871531",
		rough = "rbxassetid://138538507465564",
	},
	QuestHub_Body2 = {
		color = "rbxassetid://139572259598456",
		normal = "rbxassetid://114955266871531",
		rough = "rbxassetid://138538507465564",
	},
}

-- the collision box (Blender min/max) and the chest's hinge and cups (Blender points), from build_v2.py's JSON
local DATA = {
	ScoopChest = { -- v2: export/ScoopChest_v2.json
		collision = { min = { -7.000, -3.254, 0 }, max = { 6.998, 3.270, 3.441 } },
		hinge = { 0, 1.707, 3.949 },
		cups = {
			{ -4.489, -0.514, 5.033 },
			{ -2.618, -0.512, 4.995 },
			{ -0.923, -0.460, 4.979 },
			{ 0.879, -0.506, 4.975 },
			{ 2.716, -0.511, 4.966 },
			{ 4.489, -0.531, 4.959 },
		},
	},
	SellCart = { collision = { min = { -9.750, -3.781, 0.000 }, max = { 6.179, 3.493, 6.136 } } },
	CraftingStation = { collision = { min = { -13.369, -6.000, 0.000 }, max = { 13.369, 5.988, 7.563 } } },
	UpgradeShop = { collision = { min = { -11.360, -9.450, 0.000 }, max = { 11.360, 9.450, 14.258 } } },
	CosmeticShop = { collision = { min = { -12.128, -9.450, 0.000 }, max = { 12.128, 9.450, 19.115 } } },
	QuestHub = { collision = { min = { -12.146, -9.450, 0.000 }, max = { 12.146, 9.450, 18.814 } } },
}
-- an equipped scoop sits this far below the top of the cup's own modelled scoop (studs)
local SLOT_DROP = 0.6

local function toRoblox(v: { number }): Vector3
	return Vector3.new(-v[1], v[3], v[2])
end

local kit = ServerStorage:FindFirstChild("MeshyKit")
if not kit then
	kit = Instance.new("Folder")
	kit.Name = "MeshyKit"
	kit.Parent = ServerStorage
end

local function dress(part: MeshPart, key: string)
	part.Name = key
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.RenderFidelity = Enum.RenderFidelity.Automatic
	for _, old in part:GetChildren() do
		if old:IsA("SurfaceAppearance") then
			old:Destroy()
		end
	end
	local maps = MAPS[key]
	local look = Instance.new("SurfaceAppearance")
	look.ColorMap = maps.color
	look.NormalMap = maps.normal
	look.RoughnessMap = maps.rough
	if maps.metal then
		look.MetalnessMap = maps.metal
	end
	look.Parent = part
end

local made = {}
for _, scene in workspace:GetChildren() do
	if not (scene:IsA("Model") and scene.Name == "Scene") then
		continue
	end
	local name
	for _, child in scene:GetChildren() do
		name = name or string.match(child.Name, "^(%a+)_Body$") or string.match(child.Name, "^(%a+)_Body_Node$")
	end
	local data = name and DATA[name]
	if not data then
		continue
	end
	local old = kit:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = name

	-- the meshes, their box's bottom middle moved to the world origin (the model's origin, as build.py placed it; the
	-- scene's own GetBoundingBox is turned and gives the wrong bottom)
	local meshes = {}
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, piece in scene:GetChildren() do
		local mesh = piece:FindFirstChildWhichIsA("MeshPart", true)
		if mesh then
			local key = string.gsub(piece.Name, "_Node$", "")
			dress(mesh, key)
			meshes[key] = mesh
			lo = lo:Min(mesh.Position - mesh.Size / 2)
			hi = hi:Max(mesh.Position + mesh.Size / 2)
		end
	end
	local shift = -Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)

	local collision = Instance.new("Part")
	collision.Name = "Collision"
	collision.Anchored = true
	collision.CanCollide = true
	collision.CanQuery = true
	collision.CanTouch = false
	collision.CastShadow = false
	collision.Transparency = 1
	local a, b = toRoblox(data.collision.min), toRoblox(data.collision.max)
	local low = Vector3.new(math.min(a.X, b.X), 0, math.min(a.Z, b.Z))
	local high = Vector3.new(math.max(a.X, b.X), b.Y, math.max(a.Z, b.Z))
	collision.Size = high - low
	collision.CFrame = CFrame.new((low + high) / 2)
	collision.PivotOffset = collision.CFrame:Inverse() -- the model's pivot: the bottom middle
	collision.Parent = model
	model.PrimaryPart = collision

	local body
	for key, mesh in meshes do
		mesh.CFrame += shift
		if key == name .. "_Lid" then
			local lid = Instance.new("Model")
			lid.Name = "Lid"
			local hinge = Instance.new("Part")
			hinge.Name = "Hinge"
			hinge.Size = Vector3.new(0.2, 0.2, 0.2)
			hinge.Anchored = true
			hinge.CanCollide = false
			hinge.CanQuery = false
			hinge.CanTouch = false
			hinge.CastShadow = false
			hinge.Transparency = 1
			hinge.CFrame = CFrame.new(toRoblox(data.hinge))
			hinge.Parent = lid
			lid.PrimaryPart = hinge
			mesh.Parent = lid
			lid.Parent = model
		else
			mesh.Parent = model
			if key == name .. "_Body" then
				body = mesh -- the scoop slots hang on the first body piece
			end
		end
	end

	if data.cups and body then
		for index, cup in data.cups do
			-- numbered from the player's left: DATA lists them by Blender X from low, which is Roblox X from high
			local slot = Instance.new("Attachment")
			slot.Name = "ScoopSlot" .. index
			slot.Parent = body
			slot.WorldCFrame = CFrame.new(toRoblox(cup) - Vector3.new(0, SLOT_DROP, 0))
		end
	end

	model.Parent = kit
	scene:Destroy()
	table.insert(made, name)
end

-- The names (Luckiest Guy, a SurfaceGui on an invisible plate `NameField` facing front). UpgradeShop and
-- CraftingStation have theirs painted in the model. SellCart: on its empty cream plate below the counter (the cone's
-- tip reaches into the plate's top middle). CosmeticShop has no plate: on the awning, tilted back like it.
local SIGNS = {
	SellCart = {
		text = "SELL",
		at = Vector3.new(0.7, 3.2, -3.42),
		size = Vector2.new(5.6, 1.25),
		tilt = 0,
		color = "#5A2E1C",
	},
	CosmeticShop = {
		text = "COSMETICS",
		at = Vector3.new(0, 13.75, -9.12),
		size = Vector2.new(11.5, 1.9),
		tilt = 27,
		color = "#FFFFFF",
		stroke = "#3B2016",
	},
	-- QuestHub (v2): on the awning's upright front edge (13.5 wide, 1.3 high, Blender y -9.43); the awning's top slopes
	-- back too steeply to be read from the ground
	QuestHub = {
		text = "QUESTS",
		at = Vector3.new(0, 11.95, -9.48),
		size = Vector2.new(7.0, 1.2),
		tilt = 0,
		color = "#FFFFFF",
		stroke = "#1E3F6E",
	},
}
for name, spec in SIGNS do
	local model = kit:FindFirstChild(name)
	if not model then
		continue
	end
	local old = model:FindFirstChild("NameField")
	if old then
		old:Destroy()
	end
	local part = Instance.new("Part")
	part.Name = "NameField"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(spec.size.X, spec.size.Y, 0.05)
	part.CFrame = model:GetPivot() * CFrame.new(spec.at) * CFrame.Angles(math.rad(spec.tilt), 0, 0)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Name"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.5
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.96, 0.86)
	label.FontFace = Font.new("rbxasset://fonts/families/LuckiestGuy.json")
	label.TextScaled = true
	label.Text = spec.text
	label.TextColor3 = Color3.fromHex(spec.color)
	if spec.stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromHex(spec.stroke)
		stroke.Thickness = 4
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = label
	end
	label.Parent = gui
	part.Parent = model
end

game:GetService("ChangeHistoryService"):SetWaypoint("Meshy templates")
return "templates: " .. table.concat(made, ", ")
