--!nocheck
-- Turns imported arena kit models into templates (Edit mode, run through the Studio MCP or the command bar): every
-- Model in Workspace named ArenaKit_<Model> (as the FBX import names it, assets/ArenaKit/export_arenakit.py).
--   * each MeshPart <Model>_<Colour> gets its game colour (GAME_COLOURS below = arenakit.py GAME_COLOURS), the
--     attribute Colour, SmoothPlastic, Anchored, and neither collides nor takes queries or touches
--   * the model gets invisible collision as in ServerStorage.ArenaKit.CoverBlock: a box `Collision` (cylinders for
--     the pillars) as its PrimaryPart, its pivot kept at the bottom centre. The entrance gets one cylinder per
--     pillar (Collision_L, Collision_R) and nothing over the ramp; its PrimaryPart is Collision_L.
--   * the import moves to ServerStorage.ArenaKit.<Model> (a template there is replaced): placed copies are dragged
--     from there (cover into Ice Cream Map.Covery).
-- Run again after a fresh import: it is safe to repeat.

local GAME_COLOURS = {
	Cream = "#FFE9D0",
	Pink = "#F06AAE",
	Waffle = "#E2782C",
	SkyBlue = "#75D6F2",
	Gold = "#F2A83C",
	Cherry = "#E8384F",
}
-- the collision per model: "box" (its bounding box) or a cylinder of the given diameter round the pivot's axis
local COLLISION = {
	CoverBlock = { kind = "box" },
	WaffleCrate = { kind = "box" },
	IcePillar = { kind = "cylinder", diameter = 4.6 },
	ArenaRim = { kind = "box" },
	ArenaRimPillar = { kind = "cylinder", diameter = 4.2 },
	ArenaEntrance = { kind = "pillars", diameter = 5.2, offset = 9.4 },
}

local SS = game:GetService("ServerStorage")
local folder = SS:FindFirstChild("ArenaKit") or Instance.new("Folder")
folder.Name = "ArenaKit"
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
	p.Locked = false
	return p
end

local UP = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis (X) pointing up

local report = {}
for _, model in workspace:GetChildren() do
	if not (model:IsA("Model") and model.Name:sub(1, 9) == "ArenaKit_") then
		continue
	end
	local name = model.Name:sub(10)
	local pivot = model:GetPivot()
	local coloured, unknown = 0, {}
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
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	for _, old in model:GetChildren() do
		if old:IsA("Part") and old.Name:sub(1, 9) == "Collision" then
			old:Destroy()
		end
	end
	local spec = COLLISION[name] or { kind = "box" }
	local cframe, size = model:GetBoundingBox()
	local bottom = pivot.Position.Y
	local primary
	if spec.kind == "box" then
		primary = invisible("Collision", cframe, size)
	elseif spec.kind == "cylinder" then
		local height = cframe.Position.Y + size.Y / 2 - bottom
		local at = CFrame.new(pivot.Position.X, bottom + height / 2, pivot.Position.Z)
		primary =
			invisible("Collision", at * UP, Vector3.new(height, spec.diameter, spec.diameter), Enum.PartType.Cylinder)
	else -- the entrance: one cylinder per pillar, the ramp between them stays free
		local height = cframe.Position.Y + size.Y / 2 - bottom
		for _, side in { { "L", -1 }, { "R", 1 } } do
			local at = pivot * CFrame.new(side[2] * spec.offset, height / 2, 0)
			local p = invisible(
				"Collision_" .. side[1],
				at * UP,
				Vector3.new(height, spec.diameter, spec.diameter),
				Enum.PartType.Cylinder
			)
			p.Parent = model
			primary = primary or p
		end
	end
	primary.Parent = model
	model.PrimaryPart = primary
	primary.PivotOffset = primary.CFrame:ToObjectSpace(pivot)
	local old = folder:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	-- the import itself moves there: left in Workspace it would stand (and now collide) wherever it was dropped
	model.Name = name
	model.Parent = folder
	table.insert(
		report,
		`{name}: {coloured} meshes coloured{#unknown > 0 and " (no colour: " .. table.concat(unknown, ", ") .. ")" or ""}, collision {spec.kind}`
	)
end
return #report > 0 and table.concat(report, "\n") or "no ArenaKit_* model in Workspace"
