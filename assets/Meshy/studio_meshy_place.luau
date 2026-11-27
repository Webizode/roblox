-- Puts the Meshy templates (ServerStorage.MeshyKit, studio_meshy_templates.luau) where the old models stand (Studio,
-- Edit; command bar or MCP). The old models move to ServerStorage["MeshyBefore_2026-11-27"] with the attribute
-- `From` (their parent's full name), so they can go back: run the bottom part with BACK = true.
--   every plot (Ice Cream Map.Plots.Plot_NN.PlotKit): ScoopChest, SellCart, WorkingStation -> CraftingStation
--   the hub (Ice Cream Map.Dekoracje.Hub.Shops): UpgradeShop, CosmeticShop, QuestHub (the Shop Kit one -> Meshy v2)
-- Each new model takes the old one's pivot (bottom middle, front -Z), moved to the middle of the old model's box, so it
-- stands on the same footprint.
-- Run again after a new import and studio_meshy_templates.luau: the Meshy models standing there are swapped in place.

local ServerStorage = game:GetService("ServerStorage")

local BACK = false -- true: the old models back, the new ones away

local kit = ServerStorage:WaitForChild("MeshyKit")
local map = workspace:WaitForChild("Ice Cream Map")
local backupName = "MeshyBefore_2026-11-27"
local backup = ServerStorage:FindFirstChild(backupName)

local REPLACE = { ScoopChest = "ScoopChest", SellCart = "SellCart", WorkingStation = "CraftingStation" }
local HUB = { UpgradeShop = "UpgradeShop", CosmeticShop = "CosmeticShop", QuestHub = "QuestHub" }

local function swap(parent: Instance, oldName: string, newName: string, count: { number })
	-- run again (after a new import): a Meshy model already standing there is replaced where it stands
	local current = parent:FindFirstChild(newName)
	if current and current:IsA("Model") and current:FindFirstChild(newName .. "_Body") then
		local new = kit[newName]:Clone()
		new:PivotTo(current:GetPivot())
		current:Destroy()
		new.Parent = parent
		count[1] += 1
		return
	end
	local old = parent:FindFirstChild(oldName)
	if not (old and old:IsA("Model")) then
		return
	end
	local pivot = old:GetPivot()
	local box = old:GetBoundingBox()
	local middle = pivot:PointToObjectSpace(box.Position)
	local new = kit[newName]:Clone()
	new:PivotTo(pivot * CFrame.new(middle.X, 0, middle.Z))
	new.Parent = parent
	old:SetAttribute("From", parent:GetFullName())
	old.Parent = backup
	count[1] += 1
end

if BACK then
	assert(backup, "no backup")
	for _, old in backup:GetChildren() do
		local from = old:GetAttribute("From")
		local parent = game
		for name in string.gmatch(from, "[^%.]+") do
			parent = parent:FindFirstChild(name) or parent
		end
		local newName = REPLACE[old.Name] or HUB[old.Name]
		local new = newName and parent:FindFirstChild(newName)
		if new then
			new:Destroy()
		end
		old.Parent = parent
	end
	return "the old models are back"
end

if not backup then
	backup = Instance.new("Folder")
	backup.Name = backupName
	backup.Parent = ServerStorage
end
local count = { 0 }
for _, plot in map.Plots:GetChildren() do
	local plotKit = plot:FindFirstChild("PlotKit")
	if plotKit then
		for oldName, newName in REPLACE do
			swap(plotKit, oldName, newName, count)
		end
	end
end
local shops = map.Dekoracje.Hub.Shops
for oldName, newName in HUB do
	swap(shops, oldName, newName, count)
end
game:GetService("ChangeHistoryService"):SetWaypoint("Meshy models placed")
return `{count[1]} models replaced`
