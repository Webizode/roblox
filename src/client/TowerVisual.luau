-- Renders one tower (cone + scoops) from a base CFrame and a tilt. Used for the local tower and for other
-- players' towers. Parts are client-only, anchored and non-colliding; positions come from TowerShape so they
-- match the server's idea of where the top is.
-- The scoops are the tower scoop models (ScoopModel): each turned a little further than the one below, the far model
-- for the whole tower once it is far from the camera, and a scoop that just landed on top plops in (ScoopFlight). One
-- Highlight per tower draws the outline (Config/TowerScoops), red while the tower groans.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TowerShape = require(Shared:WaitForChild("TowerShape"))
local ScoopFlight = require(Shared:WaitForChild("ScoopFlight"))
local Palette = require(Config:WaitForChild("Palette"))
local Tuning = require(Config:WaitForChild("Tower"))
local Look = require(Config:WaitForChild("TowerScoops"))

local ScoopModel = require(script.Parent:WaitForChild("ScoopModel"))

local TowerVisual = {}
TowerVisual.__index = TowerVisual

local SCOOP_SIZE = ScoopModel.SIZE
TowerVisual.SCOOP_SIZE = SCOOP_SIZE
local CONE_ROTATION = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X
local OUTLINE = Color3.fromHex(Look.outline)
local GROAN = Color3.fromHex(Palette.awning)
-- a tower growing by more than this at once was loaded or replaced, not caught onto: no plop
local PLOP_MAX_NEW = 2

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

TowerVisual.applyFlavor = ScoopModel.applyFlavor

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
	highlight.OutlineColor = OUTLINE
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model

	return setmetatable({
		model = model,
		cone = cone,
		highlight = highlight,
		scoops = {} :: { ScoopModel.ScoopModel },
		flavors = {} :: { string },
		landedAt = {} :: { [number]: number }, -- os.clock a scoop landed on top, while it plops
		base = Vector3.zero,
		tiltX = 0,
		tiltZ = 0,
	}, TowerVisual)
end

function TowerVisual:setFlavors(ids: { string })
	local before = #self.scoops
	local plop = #ids > before and #ids - before <= PLOP_MAX_NEW
	for index, id in ids do
		if self.flavors[index] ~= id then
			-- a new scoop, or another flavor in this place (a flavor's model is its own mesh)
			local old = self.scoops[index]
			if old then
				old:destroy()
			end
			self.scoops[index] = ScoopModel.new(self.model, id)
			self.flavors[index] = id
			if plop and index > before then
				self.landedAt[index] = os.clock()
			end
		end
	end
	for index = #self.scoops, #ids + 1, -1 do
		self.scoops[index]:destroy()
		self.scoops[index] = nil
		self.flavors[index] = nil
		self.landedAt[index] = nil
	end
end

function TowerVisual:update(baseCFrame: CFrame, tiltX: number, tiltZ: number)
	local base = baseCFrame.Position
	self.base = base
	self.tiltX, self.tiltZ = tiltX, tiltZ

	local camera = workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - base).Magnitude else 0
	local now = os.clock()

	local count = #self.scoops
	local parts = table.create(count + 1)
	local cframes = table.create(count + 1)
	table.insert(parts, self.cone)
	table.insert(cframes, CFrame.new(base + Vector3.new(0, Tuning.coneHeight / 2, 0)) * CONE_ROTATION)
	for index, scoop in self.scoops do
		local ox, oy, oz = TowerShape.offset(index, count, tiltX, tiltZ, Tuning)
		local drop, squashY, widen = 0, 1, 1
		local landed = self.landedAt[index]
		if landed then
			drop, squashY, widen = ScoopFlight.plop(now - landed, Look)
			if now - landed >= Look.catch.plopTime then
				self.landedAt[index] = nil
			end
		end
		scoop:setScale(Vector3.new(widen, squashY, widen))
		table.insert(parts, scoop:updateLod(distance))
		table.insert(
			cframes,
			scoop:at(
				CFrame.new(base.X + ox, base.Y + oy + drop, base.Z + oz) * CFrame.Angles(0, index * Look.stackTwist, 0)
			)
		)
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function TowerVisual:topPosition(): Vector3
	local ox, oy, oz = TowerShape.top(#self.scoops, self.tiltX, self.tiltZ, Tuning)
	return self.base + Vector3.new(ox, oy, oz)
end

-- See-through for this client only (0 solid, 1 invisible), per scoop of the own tower where it covers the screen.
-- The cone follows the bottom scoop.
function TowerVisual:setScoopFade(index: number, fade: number)
	local scoop = self.scoops[index]
	if not scoop or math.abs(scoop.part.LocalTransparencyModifier - fade) < 1e-3 then
		return
	end
	scoop:setFade(fade)
	if index == 1 then
		self.cone.LocalTransparencyModifier = fade
	end
end

function TowerVisual:setGroan(on: boolean)
	self.highlight.OutlineColor = if on then GROAN else OUTLINE
end

-- seconds a spilled scoop stays where it was when no free scoop from the server takes its place
local SPILL_HOLD = 1

-- The scoops above `keep` come off the tower and stay where they are for a moment: the server spills them as free
-- scoops (LootService) that start right there, and clearSpill removes these stand-ins once those arrived.
function TowerVisual:spill(keep: number)
	self.spilled = self.spilled or {}
	for index = #self.scoops, keep + 1, -1 do
		local scoop = self.scoops[index]
		self.scoops[index] = nil
		self.flavors[index] = nil
		self.landedAt[index] = nil
		scoop:setParent(getVisualsRoot())
		table.insert(self.spilled, scoop)
		task.delay(SPILL_HOLD, function()
			scoop:destroy()
		end)
	end
end

function TowerVisual:clearSpill()
	for _, scoop in self.spilled or {} do
		scoop:destroy()
	end
	self.spilled = {}
end

function TowerVisual:destroy()
	self.model:Destroy()
	table.clear(self.scoops)
end

return TowerVisual
