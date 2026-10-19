-- Renders one tower (cone + scoops) from a base CFrame and a tilt. Used for the local tower and for other
-- players' towers. Parts are client-only, anchored and non-colliding; positions come from TowerShape so they
-- match the server's idea of where the top is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TowerShape = require(Shared:WaitForChild("TowerShape"))
local Flavors = require(Config:WaitForChild("Flavors"))
local Palette = require(Config:WaitForChild("Palette"))
local Tuning = require(Config:WaitForChild("Tower"))

local TowerVisual = {}
TowerVisual.__index = TowerVisual

local SCOOP_SIZE = 2.1
local CONE_ROTATION = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X

local visualsRoot: Folder?

local function getVisualsRoot(): Folder
	if visualsRoot and visualsRoot.Parent then
		return visualsRoot
	end
	local folder = Instance.new("Folder")
	folder.Name = "LocalVisuals"
	folder.Parent = workspace
	visualsRoot = folder
	return folder
end
TowerVisual.root = getVisualsRoot

local function makePart(parent: Instance): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end
TowerVisual.makePart = makePart

function TowerVisual.applyFlavor(part: BasePart, flavorId: string)
	local flavor = Flavors.byId[flavorId]
	part.Color = Color3.fromHex(if flavor then flavor.color else Palette.vanilla)
	-- indexing an Enum with an unknown name throws, so a typo in the config must not break rendering
	local ok, material = pcall(function()
		return (Enum.Material :: any)[flavor.material]
	end)
	part.Material = if flavor and ok and material then material else Enum.Material.SmoothPlastic
end

function TowerVisual.new(name: string)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = getVisualsRoot()

	local cone = makePart(model)
	cone.Name = "Cone"
	cone.Shape = Enum.PartType.Cylinder
	cone.Size = Vector3.new(Tuning.coneHeight, 1.4, 1.4)
	cone.Color = Color3.fromHex(Palette.waffle)
	if not Tuning.showCone then
		cone.Transparency = 1 -- the backpack waffle is the cone
		cone.CastShadow = false
	end

	local highlight = Instance.new("Highlight")
	highlight.Adornee = model
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromHex(Palette.awning)
	highlight.Enabled = false
	highlight.Parent = model

	return setmetatable({
		model = model,
		cone = cone,
		highlight = highlight,
		scoops = {} :: { Part },
		flavors = {} :: { string },
		base = Vector3.zero,
		tiltX = 0,
		tiltZ = 0,
		fade = 0,
	}, TowerVisual)
end

function TowerVisual:setFlavors(ids: { string })
	for index, id in ids do
		local part = self.scoops[index]
		if not part then
			part = makePart(self.model)
			part.Name = "Scoop"
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.new(SCOOP_SIZE, SCOOP_SIZE, SCOOP_SIZE)
			part.LocalTransparencyModifier = self.fade
			self.scoops[index] = part
			self.flavors[index] = ""
		end
		if self.flavors[index] ~= id then
			TowerVisual.applyFlavor(part, id)
			self.flavors[index] = id
		end
	end
	for index = #self.scoops, #ids + 1, -1 do
		self.scoops[index]:Destroy()
		self.scoops[index] = nil
		self.flavors[index] = nil
	end
end

function TowerVisual:update(baseCFrame: CFrame, tiltX: number, tiltZ: number)
	local base = baseCFrame.Position
	self.base = base
	self.tiltX, self.tiltZ = tiltX, tiltZ

	local count = #self.scoops
	local parts = table.create(count + 1)
	local cframes = table.create(count + 1)
	table.insert(parts, self.cone)
	table.insert(cframes, CFrame.new(base + Vector3.new(0, Tuning.coneHeight / 2, 0)) * CONE_ROTATION)
	for index, part in self.scoops do
		local ox, oy, oz = TowerShape.offset(index, count, tiltX, tiltZ, Tuning)
		table.insert(parts, part)
		table.insert(cframes, CFrame.new(base.X + ox, base.Y + oy, base.Z + oz))
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function TowerVisual:topPosition(): Vector3
	local ox, oy, oz = TowerShape.top(#self.scoops, self.tiltX, self.tiltZ, Tuning)
	return self.base + Vector3.new(ox, oy, oz)
end

-- See-through for this client only (0 solid, 1 invisible), for the own tower when it covers the screen.
function TowerVisual:setFade(fade: number)
	if math.abs(self.fade - fade) < 1e-3 then
		return
	end
	self.fade = fade
	self.cone.LocalTransparencyModifier = fade
	for _, part in self.scoops do
		part.LocalTransparencyModifier = fade
	end
end

function TowerVisual:setGroan(on: boolean)
	self.highlight.Enabled = on
end

-- Topple: everything above `keep` flies off and rolls away. The kept scoops stay in place.
function TowerVisual:spill(keep: number, groundY: number)
	local random = Random.new()
	for index = #self.scoops, keep + 1, -1 do
		local part = self.scoops[index]
		self.scoops[index] = nil
		self.flavors[index] = nil
		part.Parent = getVisualsRoot()

		local angle = random:NextNumber() * math.pi * 2
		local distance = random:NextNumber(6, 14) + index * 0.3
		local target = part.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		target = Vector3.new(target.X, groundY + SCOOP_SIZE / 2, target.Z)
		local tween = TweenService:Create(
			part,
			TweenInfo.new(0.6 + random:NextNumber() * 0.4, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(target) }
		)
		tween:Play()
		task.delay(2.5, function()
			part:Destroy()
		end)
	end
end

function TowerVisual:destroy()
	self.model:Destroy()
	table.clear(self.scoops)
end

return TowerVisual
