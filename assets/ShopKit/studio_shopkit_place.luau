--!nocheck
-- Studio command bar / MCP: the shop buildings on the hub's three shop squares (10.11.2026). Each placeholder plate
-- Dekoracje.Hub.Platzhalter.Platzhalter_<Shop> (44 x 30, its front to the hub's middle, with the name written on
-- top) gets its building from ServerStorage.ShopKit: turned like the plate, standing on the ground, BACK studs back
-- from the plate's middle, so the forecourt and the path onto the square stay free. The name goes on the sign's
-- invisible NameField as a SurfaceGui (no text in the model). The terrain grass under the building goes. The plates
-- move to ServerStorage."MapBackup_2026-11-10_ShopPlatzhalter". Safe to run again. RESTORE = true puts them back.

local RESTORE = false
local BACK = 5.5 -- studs from the square's middle to the building's pivot, away from the front
local GROUND = 9.0 -- the hub's paving

local SHOPS = {
	UpgradeShop = { title = "UPGRADE SHOP", ink = "#2E7D5B" },
	CosmeticShop = { title = "COSMETIC SHOP", ink = "#A8327A" },
	QuestHub = { title = "QUEST HUB", ink = "#2C5E9C" },
}

local SS = game:GetService("ServerStorage")
local hub = workspace["Ice Cream Map"].Dekoracje.Hub
local holder = hub.Platzhalter
local backupName = "MapBackup_2026-11-10_ShopPlatzhalter"
local backup = SS:FindFirstChild(backupName) or Instance.new("Folder")
backup.Name = backupName
backup.Parent = SS
for name in SHOPS do
	local plate = holder:FindFirstChild("Platzhalter_" .. name)
	if plate then
		plate.Parent = backup
	end
end
local folder = hub:FindFirstChild("Shops")
if folder then
	folder:Destroy()
end
if RESTORE then
	for _, p in backup:GetChildren() do
		p.Parent = holder
	end
	return "placeholders back"
end
folder = Instance.new("Folder")
folder.Name = "Shops"
folder.Parent = hub

local function nameSign(field, spec)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Name"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.5
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.92, 0.8)
	label.Position = UDim2.fromScale(0.04, 0.1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = spec.title
	label.TextColor3 = Color3.fromHex(spec.ink)
	label.Parent = gui
	gui.Parent = field
end

local T = workspace.Terrain
local report = {}
for name, spec in SHOPS do
	local plate = backup:FindFirstChild("Platzhalter_" .. name)
	local template = SS.ShopKit:FindFirstChild(name)
	if not (plate and template) then
		table.insert(report, name .. ": missing " .. (plate and "template" or "placeholder"))
		continue
	end
	local rot = plate.CFrame.Rotation
	local at = plate.Position - plate.CFrame.LookVector * BACK
	local shop = template:Clone()
	shop:PivotTo(CFrame.new(at.X, GROUND, at.Z) * rot)
	shop.Parent = folder
	nameSign(shop.NameField, spec)
	-- no terrain grass under it
	local cf, size = shop:GetBoundingBox()
	local half = math.max(size.X, size.Z) / 2
	local region = Region3.new(
		Vector3.new(cf.Position.X - half, GROUND - 6, cf.Position.Z - half),
		Vector3.new(cf.Position.X + half, GROUND, cf.Position.Z + half)
	):ExpandToGrid(4)
	local mats, occs = T:ReadVoxels(region, 4)
	local cleared = 0
	for x = 1, mats.Size.X do
		for y = 1, mats.Size.Y do
			for z = 1, mats.Size.Z do
				if mats[x][y][z] == Enum.Material.Grass then
					mats[x][y][z] = Enum.Material.Air
					occs[x][y][z] = 0
					cleared += 1
				end
			end
		end
	end
	if cleared > 0 then
		T:WriteVoxels(region, 4, mats, occs)
	end
	table.insert(report, string.format("%s at (%.0f, %.0f), %d grass voxels cleared", name, at.X, at.Z, cleared))
end
return table.concat(report, "\n")
