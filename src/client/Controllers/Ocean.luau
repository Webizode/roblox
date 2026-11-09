-- The sea to the horizon, on this client only (Config/Map.ocean). The terrain sea is a 1024 x 1024 square and ends in
-- plain sight; this lays one flat cartoon sea just over it that follows the camera, so wherever one stands or however
-- high one looks there is sea up to the horizon, where the Atmosphere fades it into the sky.
--
-- Why one part: it is a 2048 part drawn `scale` times as wide by a SpecialMesh (about 49,000 studs). A grid of many
-- big parts showed brightness steps at the part borders (the engine lights far parts more simply), one part has none.
-- Why not more terrain water: terrain streams (it would end and pop in at the streaming radius) and a big terrain sea
-- costs memory on phones. This is one part nobody else sees; it moves only when the camera crosses a wave tile
-- (studsPerTile), so the drifting wave picture never jumps.
-- It lies `lift` over the terrain water: lower, the terrain's own waves poke through as dark moving patches.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapConfig = require(Shared:WaitForChild("Config"):WaitForChild("Map"))

local Ocean = {}

local cfg = MapConfig.ocean
local sea: BasePart
local waves: Texture
local centre: Vector3? = nil

local function build()
	sea = Instance.new("Part")
	sea.Name = "Ocean"
	sea.Size = Vector3.new(cfg.tileSize, 1, cfg.tileSize)
	sea.Color = Color3.fromHex(cfg.colour)
	sea.Material = Enum.Material.SmoothPlastic
	sea.TopSurface, sea.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	sea.Anchored, sea.CanCollide, sea.CanQuery, sea.CanTouch = true, false, false, false
	sea.CastShadow = false
	sea.Locked = true
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Brick
	mesh.Scale = Vector3.new(cfg.scale, 1, cfg.scale)
	mesh.Parent = sea
	waves = Instance.new("Texture")
	waves.Face = Enum.NormalId.Top
	waves.Texture = cfg.texture
	waves.StudsPerTileU, waves.StudsPerTileV = cfg.studsPerTile, cfg.studsPerTile
	waves.Transparency = cfg.wavesTransparency
	waves.Parent = sea
	sea.Parent = workspace
end

local function follow()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local at = camera.CFrame.Position
	local step = cfg.studsPerTile
	local snapped = Vector3.new(math.floor(at.X / step + 0.5) * step, 0, math.floor(at.Z / step + 0.5) * step)
	if snapped ~= centre then
		centre = snapped
		-- the top face at waterLevel + lift
		sea.CFrame = CFrame.new(snapped.X, MapConfig.waterLevel + cfg.lift - 0.5, snapped.Z)
	end
end

function Ocean.Start()
	build()
	follow()
	local u, v = 0, 0
	RunService:BindToRenderStep("Ocean", Enum.RenderPriority.Camera.Value + 1, function(dt)
		follow()
		u = (u + cfg.drift.u * dt) % cfg.studsPerTile
		v = (v + cfg.drift.v * dt) % cfg.studsPerTile
		waves.OffsetStudsU, waves.OffsetStudsV = u, v
	end)
end

return Ocean
