-- Reads Kornel's ice cream island and puts our Big Swirl on it. The map itself is never changed: the game finds its
-- way around it through invisible helpers in Workspace.Pier and the rules in Config/Map.
--
-- Map contract (the place must follow it, the server stops with an error otherwise):
--   Workspace."Ice Cream Map"           Kornel's map (Config/Map.root), with the Big Swirl's spot
--     .Plac.Arena_Znacznik              BasePart in the middle of the plaza (Config/Map.machineMarker)
--   Workspace.Pier                      Folder with the invisible helpers
--     .Carts.<Name>                     one Model per stand, each with
--       .ServePoint                     BasePart (invisible, no collision or queries), about 3 studs above the ground
--                                       in front of the stand: where the player serves and spawns
--       .Body.Label                     optional BillboardGui with a TextLabel, shows the owner
--       .Stand                          optional ObjectValue, the stand model in the map it belongs to
--       .Spawn                          optional SpawnLocation (invisible, no collision) on the ground there, so
--                                       Roblox never spawns a character at the origin inside the Big Swirl before
--                                       CartService moves it to its own stand
--     .BigSwirl.Nozzle                  built here on the marker when missing; scoops launch from the Nozzle
--   Water                               Terrain water, a part named "Water", Water material, or anything below
--                                       Config/Map.waterLevel: spilled scoops sink there, players respawn

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Palette = require(Config:WaitForChild("Palette"))
local MapConfig = require(Config:WaitForChild("Map"))
local LauncherConfig = require(Config:WaitForChild("Launcher"))
local MapRules = require(Shared:WaitForChild("MapRules"))
local MapQuery = require(Shared:WaitForChild("MapQuery"))

local MapService = {}

-- how high above the machine's base the landing rays start, so they begin above every roof and palm
local RAY_START = 80
local RAY_REACH = 160

local function part(props: { [string]: any }): Part
	local instance = Instance.new("Part")
	instance.Anchored = true
	instance.Material = Enum.Material.SmoothPlastic
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		instance[key] = value
	end
	return instance
end

-- The highest point of a part, whatever way it is turned (the marker is a cylinder lying on its side).
local function topOf(base: BasePart): number
	local cframe, size = base.CFrame, base.Size
	local halfY = math.abs(cframe.RightVector.Y) * size.X / 2
		+ math.abs(cframe.UpVector.Y) * size.Y / 2
		+ math.abs(cframe.LookVector.Y) * size.Z / 2
	return base.Position.Y + halfY
end

-- Our Big Swirl (the machine of the graybox days), standing on the marker.
local function buildMachine(pier: Instance, marker: BasePart): Model
	local look = MapConfig.machine
	local baseY = topOf(marker)
	local x, z = marker.Position.X, marker.Position.Z
	local machine = Instance.new("Model")
	machine.Name = "BigSwirl"
	part({
		Name = "Body",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(look.bodyHeight, look.bodyDiameter, look.bodyDiameter),
		CFrame = CFrame.new(x, baseY + look.bodyHeight / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromHex(Palette.strawberry),
		Parent = machine,
	})
	local nozzle = part({
		Name = "Nozzle",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * look.nozzleSize,
		CFrame = CFrame.new(x, baseY + look.bodyHeight + look.nozzleGap, z),
		Color = Color3.fromHex(Palette.vanilla),
		Parent = machine,
	})
	machine.PrimaryPart = nozzle
	machine.Parent = pier
	return machine
end

local function find(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, name in path do
		current = current and current:FindFirstChild(name)
	end
	return current
end

local function characters(): { Instance }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

-- The ground under (x, z) where a scoop may land, or nil (water, nothing, or a surface nobody stands on).
local function landingHeight(x: number, z: number, fromY: number, ignore: { Instance }): number?
	local ground = MapQuery.ground(x, fromY, z, RAY_REACH, ignore)
	local hit = ground.hit
	if ground.y == nil or not hit then
		return nil
	end
	if not MapRules.landingSurface(MapQuery.folderOf(hit.Instance), hit.Instance.Name, hit.Normal.Y, MapConfig) then
		return nil
	end
	return ground.y
end

-- Every spot inside the landing circle where a player could stand, sampled once: a flat array x, y, z, ...
local function sampleLandingSpots(center: Vector3): { number }
	local landing = MapConfig.landing
	local step, foot = landing.gridStep, landing.footprint
	local radius = LauncherConfig.landingRadius
	local fromY = center.Y + RAY_START
	local spots = {}
	local heights = table.create(5)
	local offsets = { { 0, 0 }, { foot, 0 }, { -foot, 0 }, { 0, foot }, { 0, -foot } }
	-- in Studio a player can already stand on the plaza when the server starts; their body is not the map
	local ignore = characters()
	for dx = -radius, radius, step do
		for dz = -radius, radius, step do
			if dx * dx + dz * dz <= radius * radius then
				local x, z = center.X + dx, center.Z + dz
				for index, offset in offsets do
					heights[index] = landingHeight(x + offset[1], z + offset[2], fromY, ignore)
				end
				if MapRules.flatFootprint(heights, #offsets, MapConfig) then
					table.insert(spots, x)
					table.insert(spots, heights[1] :: number)
					table.insert(spots, z)
				end
			end
		end
	end
	return spots
end

function MapService.Init()
	local missing = {}
	local root = workspace:FindFirstChild(MapConfig.root)
	local pier = workspace:FindFirstChild(MapConfig.pier)
	local marker = root and find(root, MapConfig.machineMarker)
	local carts = pier and pier:FindFirstChild("Carts")
	if not root then
		table.insert(missing, `Workspace.{MapConfig.root}`)
	end
	if not (marker and marker:IsA("BasePart")) then
		table.insert(missing, `the Big Swirl marker {table.concat(MapConfig.machineMarker, ".")}`)
	end
	if not carts then
		table.insert(missing, `Workspace.{MapConfig.pier}.Carts`)
	else
		for _, cart in carts:GetChildren() do
			if not cart:FindFirstChild("ServePoint") then
				table.insert(missing, `ServePoint in Carts.{cart.Name}`)
			end
		end
		if #carts:GetChildren() == 0 then
			table.insert(missing, "at least one cart in Carts")
		end
	end
	if #missing > 0 then
		error(`The place does not follow the map contract (top of MapService): missing {table.concat(missing, ", ")}.`)
	end
	assert(pier and carts and marker and marker:IsA("BasePart"), "map contract checked above")

	local machine = pier:FindFirstChild("BigSwirl") or buildMachine(pier, marker)
	local nozzle = machine:FindFirstChild("Nozzle") :: BasePart?
	if not nozzle then
		error("Workspace.Pier.BigSwirl has no Nozzle (map contract, top of MapService).")
	end

	MapService.map = root
	MapService.pier = pier
	MapService.nozzle = nozzle
	MapService.center = Vector3.new(marker.Position.X, topOf(marker), marker.Position.Z)
	MapService.carts = carts:GetChildren()
	table.sort(MapService.carts, function(a, b)
		return a.Name < b.Name
	end)
	MapService.landingSpots = sampleLandingSpots(MapService.center)
	print(
		string.format(
			"[Map] %d stands, Big Swirl at (%.0f, %.1f, %.0f), %d landing spots",
			#MapService.carts,
			MapService.center.X,
			MapService.center.Y,
			MapService.center.Z,
			#MapService.landingSpots // 3
		)
	)
end

-- The ground under (x, z) seen from `fromY` (characters ignored), or nil over water or nothing.
function MapService.groundAt(x: number, fromY: number, z: number, reach: number): MapQuery.Ground
	return MapQuery.ground(x, fromY, z, reach, characters())
end

-- Any landing spot, all equally likely.
function MapService.randomLanding(rng: Random): Vector3?
	local spots = MapService.landingSpots
	local count = #spots // 3
	if count == 0 then
		return nil
	end
	local index = rng:NextInteger(1, count)
	return Vector3.new(spots[index * 3 - 2], spots[index * 3 - 1], spots[index * 3])
end

-- A random landing spot near (x, z): one within `radius`, or the nearest spot when none is.
function MapService.landingNear(x: number, z: number, radius: number, rng: Random): Vector3?
	local spots = MapService.landingSpots
	local near = MapRules.spotsNear(spots, x, z, radius)
	if #near == 0 then
		return nil
	end
	local index = near[rng:NextInteger(1, #near)]
	return Vector3.new(spots[index * 3 - 2], spots[index * 3 - 1], spots[index * 3])
end

return MapService
