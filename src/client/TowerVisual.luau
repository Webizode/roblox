-- Renders one tower (cone + scoops) from a base CFrame and a tilt. Used for the local tower and for other
-- players' towers. Parts are client-only, anchored and non-colliding; positions come from TowerShape so they
-- match the server's idea of where the top is.
-- The scoops are the tower scoop models (ScoopModel): each turned a little further than the one below, the far model
-- for the whole tower once it is far from the camera, and a scoop that just landed on top plops in (ScoopFlight). One
-- Highlight per tower draws the outline (Config/TowerScoops), red while the tower groans.
-- Under every scoop from uncommon on sits a thin ring in its rarity's colour (Config/TowerScoops rarityRing,
-- TowerMarks.ring): plain, glowing from epic, glinting for a legendary; it follows the VFX quality as it changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TowerShape = require(Shared:WaitForChild("TowerShape"))
local ScoopFlight = require(Shared:WaitForChild("ScoopFlight"))
local RarityFlight = require(Shared:WaitForChild("RarityFlight"))
local TowerMarks = require(Shared:WaitForChild("TowerMarks"))
local Flavors = require(Config:WaitForChild("Flavors"))
local Vfx = require(Config:WaitForChild("Vfx"))
local Palette = require(Config:WaitForChild("Palette"))
local Tuning = require(Config:WaitForChild("Tower"))
local Look = require(Config:WaitForChild("TowerScoops"))

local ScoopModel = require(script.Parent:WaitForChild("ScoopModel"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local TowerVisual = {}
TowerVisual.__index = TowerVisual

local SCOOP_SIZE = ScoopModel.SIZE
TowerVisual.SCOOP_SIZE = SCOOP_SIZE
local CONE_ROTATION = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X
local GROAN = Color3.fromHex(Palette.awning)
-- a tower growing by more than this at once was loaded or replaced, not caught onto: no plop
local PLOP_MAX_NEW = 2
local RING = Look.rarityRing

type Ring = { part: BasePart, size: Vector3, scale: Vector3, sparkle: ParticleEmitter?, glinting: boolean }

-- The ring under a scoop of `flavorId` at the VFX quality, or nil (a common one, or the ring's model missing from
-- ReplicatedStorage: then no rings at all, with one warning).
local warnedRing = false
local function makeRing(parent: Instance, flavorId: string, quality: string): Ring?
	local flavor = Flavors.byId[flavorId]
	local rarity = flavor and flavor.rarity
	if not rarity or rarity == "common" then
		return nil
	end
	local color = RarityFlight.circleColor(rarity, Vfx.flight, Flavors.rarityColors, Look.landingCircle.common)
	local style = TowerMarks.ring(rarity, quality, RING, Flavors.rarities, color)
	if not style then
		return nil
	end
	local template = ReplicatedStorage:FindFirstChild(RING.part)
	if not (template and template:IsA("BasePart")) then
		if not warnedRing then
			warnedRing = true
			warn("TowerVisual: ReplicatedStorage." .. RING.part .. " is missing, the towers show no rarity rings")
		end
		return nil
	end
	local part = template:Clone()
	part.Name = "RarityRing"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = Color3.fromHex(style.color)
	part.Material = if style.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Transparency = if style.glow then RING.glowTransparency else RING.transparency
	local sparkle: ParticleEmitter? = nil
	if style.sparkle then
		local look = RING.sparkle
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = Vfx.textures[look.texture]
		emitter.Color = ColorSequence.new(Color3.fromHex(style.color):Lerp(Color3.new(1, 1, 1), 0.4))
		emitter.Rate = look.rate
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, look.size[2]),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Lifetime = NumberRange.new(look.lifetime[1], look.lifetime[2])
		emitter.LightEmission = look.lightEmission
		emitter.LightInfluence = 0
		emitter.Speed = NumberRange.new(0, 0.2)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Shape = Enum.ParticleEmitterShape.Cylinder
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Enabled = false -- update turns it on near the camera
		emitter.Parent = part
		sparkle = emitter
	end
	part.Parent = parent
	return { part = part, size = template.Size, scale = Vector3.one, sparkle = sparkle, glinting = false }
end

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

-- alwaysNear: draw every scoop with its close model (LOD0) at any distance: the local player's own tower (user
-- 28.11.2026: from the player's view the own tower always shows LOD0; tall towers reached the far model at the top).
function TowerVisual.new(name: string, alwaysNear: boolean?)
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
	highlight.OutlineColor = GROAN
	-- no outline while all is well (kill test 13.11.2026: the dark outline round every scoop looked like a black border);
	-- only a groaning tower shows it, red, as the tipping warning (setGroan)
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model

	return setmetatable({
		model = model,
		cone = cone,
		highlight = highlight,
		scoops = {} :: { ScoopModel.ScoopModel },
		rings = {} :: { [number]: Ring | false }, -- per place: its ring, false for none (common)
		ringQuality = Settings.effective().vfxQuality,
		flavors = {} :: { string },
		landedAt = {} :: { [number]: number }, -- os.clock a scoop landed on top, while it plops
		base = Vector3.zero,
		tiltX = 0,
		tiltZ = 0,
		yaw = 0, -- the way the stack faces (radians about +Y), following its carrier (update)
		yawSpeed = 0,
		turnAt = nil :: number?, -- os.clock of the last update; nil until the first
		alwaysNear = alwaysNear == true,
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
			self:setRing(index, id)
			self.flavors[index] = id
			if plop and index > before then
				self.landedAt[index] = os.clock()
			end
		end
	end
	for index = #self.scoops, #ids + 1, -1 do
		self.scoops[index]:destroy()
		self.scoops[index] = nil
		self:setRing(index, nil)
		self.flavors[index] = nil
		self.landedAt[index] = nil
	end
end

-- Puts the ring for `flavorId` under the scoop at `index` (none for nil or a common one).
function TowerVisual:setRing(index: number, flavorId: string?)
	local old = self.rings[index]
	if old then
		old.part:Destroy()
	end
	self.rings[index] = if flavorId then makeRing(self.model, flavorId, self.ringQuality) or false else nil
end

-- baseCFrame: where the tower stands and, by its look vector, the way its carrier faces; the stack turns after that
-- on a spring (Config/TowerScoops turn). The lean stays in world space.
function TowerVisual:update(baseCFrame: CFrame, tiltX: number, tiltZ: number)
	local base = baseCFrame.Position
	self.base = base
	self.tiltX, self.tiltZ = tiltX, tiltZ

	local camera = workspace.CurrentCamera
	local trueDistance = if camera then (camera.CFrame.Position - base).Magnitude else 0
	local distance = if self.alwaysNear then 0 else trueDistance
	local now = os.clock()

	local quality = Settings.effective().vfxQuality
	if quality ~= self.ringQuality then
		-- the player changed the VFX quality: the rings glow and glint as it allows now
		self.ringQuality = quality
		for index, id in self.flavors do
			self:setRing(index, id)
		end
	end
	local glint = trueDistance <= RING.sparkle.maxDistance

	local look = baseCFrame.LookVector
	local target = ScoopFlight.yawOf(look.X, look.Z)
	if self.turnAt == nil then
		self.yaw, self.yawSpeed = target, 0 -- a new tower starts facing the right way
	else
		self.yaw, self.yawSpeed = ScoopFlight.followYaw(self.yaw, self.yawSpeed, target, now - self.turnAt, Look)
	end
	self.turnAt = now
	local turn = CFrame.Angles(0, self.yaw, 0)

	local count = #self.scoops
	local parts = table.create(count + 1)
	local cframes = table.create(count + 1)
	table.insert(parts, self.cone)
	table.insert(cframes, CFrame.new(base + Vector3.new(0, Tuning.coneHeight / 2, 0)) * turn * CONE_ROTATION)
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
		local yaw, poseX, poseZ, size = ScoopFlight.stackPose(index, Look)
		local scale = Vector3.new(widen * size, squashY * size, widen * size)
		scoop:setScale(scale)
		local centre = CFrame.new(base.X + ox, base.Y + oy + drop, base.Z + oz)
			* turn
			* CFrame.Angles(poseX, 0, poseZ)
			* CFrame.Angles(0, yaw, 0)
		table.insert(parts, scoop:updateLod(distance))
		table.insert(cframes, scoop:at(centre))
		local ring = self.rings[index]
		if ring then
			if ring.scale ~= scale then
				ring.scale = scale
				ring.part.Size = ring.size * scale
			end
			table.insert(parts, ring.part)
			table.insert(cframes, centre * CFrame.new(0, RING.height * scale.Y, 0))
			if ring.sparkle and ring.glinting ~= glint then
				ring.glinting = glint
				ring.sparkle.Enabled = glint
			end
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Plays the landing plop of the scoop at `index` again (a scoop that just changed, Luck).
function TowerVisual:replop(index: number)
	if self.scoops[index] then
		self.landedAt[index] = os.clock()
	end
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
	local ring = self.rings[index]
	if ring then
		ring.part.LocalTransparencyModifier = fade
	end
	if index == 1 then
		self.cone.LocalTransparencyModifier = fade
	end
end

function TowerVisual:setGroan(on: boolean)
	self.highlight.OutlineTransparency = if on then 0 else 1
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
		self:setRing(index, nil)
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

-- The shown model of the scoop at `index` (for a name over it, TowerNameTag), or nil.
function TowerVisual:scoopPart(index: number): BasePart?
	local scoop = self.scoops[index]
	return if scoop then scoop.part else nil
end

function TowerVisual:destroy()
	self.model:Destroy()
	table.clear(self.scoops)
	table.clear(self.rings)
end

return TowerVisual
