--!strict
-- Test aid (Features.debugHitZones, or the attribute HitZones on Workspace while playing): draws the hit zones the server
-- checks round every other player, half transparent, the same geometry as CombatService: the body capsule (hitRadius
-- round the HumanoidRootPart's axis, hitHalfHeight up and down; it grows with the flight, see hitGrowth), the head zone
-- (headRadius times headZoneScale round the Head part's centre, red) and the tower column on the back (the scoops'
-- radius round the line through the scoop centres, towerBack behind and towerUp above the root, scoopSpacing per
-- scoop, blue). The ball's own radius comes on top of every zone. Only for this client, nothing collides or is hit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local CombatConfig = require(Config:WaitForChild("Combat"))
local TowerConfig = require(Config:WaitForChild("Tower"))
local Features = require(Config:WaitForChild("Features"))

local HitZoneDebug = {}

local ATTRIBUTE = "HitZones"
local localPlayer = Players.LocalPlayer

type Zones = {
	folder: Folder,
	body: BasePart,
	head: BasePart,
	tower: BasePart,
	towerTop: BasePart,
	towerBottom: BasePart,
}
local zones: { [Player]: Zones } = {}
local folder: Folder? = nil

local function zonePart(name: string, shape: Enum.PartType, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.ForceField
	part.Color = color
	part.Transparency = 0.3
	part.Parent = parent
	return part
end

local function zonesFor(player: Player): Zones
	local existing = zones[player]
	if existing then
		return existing
	end
	local root = folder :: Folder
	local own = Instance.new("Folder")
	own.Name = player.Name
	own.Parent = root
	local made: Zones = {
		folder = own,
		body = zonePart("Body", Enum.PartType.Cylinder, Color3.fromRGB(255, 220, 80), own),
		head = zonePart("Head", Enum.PartType.Ball, Color3.fromRGB(255, 60, 60), own),
		tower = zonePart("Tower", Enum.PartType.Cylinder, Color3.fromRGB(60, 140, 255), own),
		towerTop = zonePart("TowerTop", Enum.PartType.Ball, Color3.fromRGB(60, 140, 255), own),
		towerBottom = zonePart("TowerBottom", Enum.PartType.Ball, Color3.fromRGB(60, 140, 255), own),
	}
	zones[player] = made
	return made
end

local function drop(player: Player)
	local z = zones[player]
	if z then
		z.folder:Destroy()
		zones[player] = nil
	end
end

local function scoopsOf(character: Model): number
	local flavors = character:GetAttribute("TowerFlavors")
	if type(flavors) ~= "string" or flavors == "" then
		return 0
	end
	return #string.split(flavors, ",")
end

local function enabled(): boolean
	return Features.debugHitZones == true or workspace:GetAttribute(ATTRIBUTE) == true
end

local function step()
	if not enabled() then
		if folder then
			folder:Destroy()
			folder = nil
			table.clear(zones)
		end
		return
	end
	if not folder then
		local made = Instance.new("Folder")
		made.Name = "HitZoneDebug"
		made.Parent = workspace
		folder = made
	end
	for _, player in Players:GetPlayers() do
		local character = player ~= localPlayer and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if not character or not root or not head then
			drop(player)
			continue
		end
		local z = zonesFor(player)
		local p = root.Position
		-- the body capsule's straight part (the round caps are left out to keep it readable)
		local h = CombatConfig.hitHalfHeight
		z.body.Size = Vector3.new(2 * h, 2 * CombatConfig.hitRadius, 2 * CombatConfig.hitRadius)
		z.body.CFrame = CFrame.new(p) * CFrame.Angles(0, 0, math.rad(90))
		z.body.Transparency = 0.75
		local headSize = 2 * CombatConfig.headRadius * CombatConfig.headZoneScale
		z.head.Size = Vector3.new(headSize, headSize, headSize)
		z.head.CFrame = CFrame.new(head.Position)
		local scoops = scoopsOf(character)
		local showTower = scoops > 0
		for _, part in { z.tower, z.towerTop, z.towerBottom } do
			part.Transparency = if showTower then 0.3 else 1
		end
		if showTower then
			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			local back = if flat.Magnitude > 1e-3 then -flat.Unit else Vector3.zero
			local bottom = p + back * CombatConfig.towerBack + Vector3.new(0, CombatConfig.towerUp, 0)
			local height = (scoops - 1) * TowerConfig.scoopSpacing
			local d = 2 * CombatConfig.towerRadius
			z.towerBottom.Size = Vector3.new(d, d, d)
			z.towerBottom.CFrame = CFrame.new(bottom)
			z.towerTop.Size = Vector3.new(d, d, d)
			z.towerTop.CFrame = CFrame.new(bottom + Vector3.new(0, height, 0))
			z.tower.Size = Vector3.new(math.max(height, 0.05), d, d)
			z.tower.CFrame = CFrame.new(bottom + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
	for player in zones do
		if player.Parent == nil then
			drop(player)
		end
	end
end

function HitZoneDebug.Start()
	if not Features.debugHitZones and not RunService:IsStudio() then
		return -- the attribute only works in Studio
	end
	RunService.RenderStepped:Connect(step)
end

return HitZoneDebug
