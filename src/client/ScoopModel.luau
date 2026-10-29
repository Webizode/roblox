-- One drawn tower scoop on this client: a copy of its flavor's model from ReplicatedStorage.TowerScoops (the close
-- LOD0 and the far LOD1 from assets/TowerScoops), or the plain ball while a flavor has no model yet. Only the shown
-- model is in the world; `part` is always that one. Client-only, anchored, non-colliding, like everything in
-- LocalVisuals. TowerVisual (towers) and ShotRenderer (scoops in flight) draw with it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Flavors = require(Config:WaitForChild("Flavors"))
local Palette = require(Config:WaitForChild("Palette"))
local Look = require(Config:WaitForChild("TowerScoops"))
local ScoopFlight = require(Shared:WaitForChild("ScoopFlight"))

local ScoopModel = {}
ScoopModel.__index = ScoopModel

ScoopModel.SIZE = 2.1 -- studs across, the plain ball and the reference the models are scaled against

export type ScoopModel = typeof(setmetatable(
	{} :: {
		near: BasePart,
		far: BasePart?,
		part: BasePart, -- the one shown
		isFar: boolean,
		parent: Instance,
		nearSize: Vector3,
		nearLift: number,
		farLift: number,
		farSize: Vector3?,
		scale: Vector3,
		sign: BillboardGui?, -- the name sign (ScoopSign), kept on the shown part
	},
	ScoopModel
))

local function prepare(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
end

local function applyFlavor(part: BasePart, flavorId: string)
	local flavor = Flavors.byId[flavorId]
	part.Color = Color3.fromHex(if flavor then flavor.color else Palette.vanilla)
	-- indexing an Enum with an unknown name throws, so a typo in the config must not break rendering
	local ok, material = pcall(function()
		return (Enum.Material :: any)[flavor.material]
	end)
	part.Material = if flavor and ok and material then material else Enum.Material.SmoothPlastic
end
ScoopModel.applyFlavor = applyFlavor

local function ball(): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * ScoopModel.SIZE
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function template(flavorId: string, lod: string): BasePart?
	local root = ReplicatedStorage:FindFirstChild(Look.folder)
	local folder = root and root:FindFirstChild(flavorId)
	local found = folder and folder:FindFirstChild(lod)
	return if found and found:IsA("BasePart") then found else nil
end

-- How far the part's centre sits above the scoop's centre: the importer centres a mesh on its bounding box, which for
-- a scoop model runs from its lowest drip (Config/TowerScoops dripDepth below the scoop's centre) up to its top.
-- The ball is centred on the scoop's centre.
local function lift(part: BasePart, isModel: boolean): number
	return if isModel then part.Size.Y / 2 - Look.dripDepth else 0
end

function ScoopModel.new(parent: Instance, flavorId: string): ScoopModel
	local nearTemplate = template(flavorId, "LOD0")
	local farTemplate = nearTemplate and template(flavorId, "LOD1")
	local near: BasePart = if nearTemplate then nearTemplate:Clone() else ball()
	local far: BasePart? = if farTemplate then farTemplate:Clone() else nil
	for _, part in { near, far } do
		prepare(part)
		part.Name = "Scoop"
		applyFlavor(part, flavorId)
	end
	near.Parent = parent
	return setmetatable({
		near = near,
		far = far,
		part = near,
		isFar = false,
		parent = parent,
		nearSize = near.Size,
		farSize = if far then far.Size else nil,
		nearLift = lift(near, nearTemplate ~= nil),
		farLift = if far then lift(far, true) else 0,
		scale = Vector3.one,
	}, ScoopModel)
end

-- The CFrame for the shown part when the scoop's centre is at `centre` (turned as `centre` is).
function ScoopModel:at(centre: CFrame): CFrame
	local up = (if self.isFar then self.farLift else self.nearLift) * self.scale.Y
	return if up == 0 then centre else centre * CFrame.new(0, up, 0)
end

-- How far below the scoop's centre its lowest point is (the drips; for the ball its radius), at the current scale:
-- the height of the centre above the ground for a scoop lying on it.
function ScoopModel:restHeight(): number
	local size = if self.isFar and self.farSize then self.farSize else self.nearSize
	local up = if self.isFar then self.farLift else self.nearLift
	return (size.Y / 2 - up) * self.scale.Y
end

-- Shows the far model from Config/TowerScoops farDistance studs from the camera on (with a little hysteresis).
-- Returns the part that shows now.
function ScoopModel:updateLod(distance: number): BasePart
	local far = self.far
	if not far then
		return self.part
	end
	local wantFar = ScoopFlight.useFar(distance, self.isFar, Look)
	if wantFar ~= self.isFar then
		local from, to = self.part, if wantFar then far else self.near
		to.CFrame = from.CFrame
		to.Transparency = from.Transparency
		to.LocalTransparencyModifier = from.LocalTransparencyModifier
		to.Parent = from.Parent
		from.Parent = nil
		self.part, self.isFar = to, wantFar
		if self.sign then
			self.sign.Adornee = to
		end
	end
	return self.part
end

-- Scales the model (1 = as built: 2.1 studs across, the size a tower scoop has); x and z sideways, y up.
function ScoopModel:setScale(scale: Vector3)
	if scale == self.scale then
		return
	end
	self.scale = scale
	self.near.Size = self.nearSize * scale
	if self.far and self.farSize then
		self.far.Size = self.farSize * scale
	end
end

function ScoopModel:setTransparency(value: number)
	self.near.Transparency = value
	if self.far then
		self.far.Transparency = value
	end
end

function ScoopModel:setFade(value: number)
	self.near.LocalTransparencyModifier = value
	if self.far then
		self.far.LocalTransparencyModifier = value
	end
end

function ScoopModel:setParent(parent: Instance)
	self.parent = parent
	self.part.Parent = parent
end

-- Puts a name sign (ScoopSign) over the scoop, or takes it away with nil; it follows the model that shows.
function ScoopModel:setSign(sign: BillboardGui?)
	if self.sign and self.sign ~= sign then
		self.sign:Destroy()
	end
	self.sign = sign
	if sign then
		sign.Adornee = self.part
	end
end

function ScoopModel:destroy()
	self:setSign(nil)
	self.near:Destroy()
	if self.far then
		self.far:Destroy()
	end
end

return ScoopModel
