-- Reads the ice cream island and puts our Big Swirl on it. The map itself is never changed: the game finds its
-- way around it through invisible helpers in Workspace.Pier and the rules in Config/Map.
--
-- Map contract (the place must follow it, the server stops with an error otherwise):
--   Workspace."Ice Cream Map"           the hub island with the arena (Config/Map.root, arena size in Config/Map.arena)
--                                       and the plot islands, with the Big Swirl's spot
--     .Plac.Arena_Znacznik              BasePart in the middle of the plaza (Config/Map.machineMarker)
--     .Covery                           optional: the arena cover. Every Model in it is cover and collides only
--                                       through one invisible box named Collision (prepareCover makes it when
--                                       missing), e.g. copies of ServerStorage.ArenaKit.CoverBlock
--     .Sperre                           optional: invisible walls that only stop players (Config/Map.playersOnlyFolders),
--                                       over the arena rim and along the ramps' edges; rays look through them
--   Workspace.Pier                      Folder with the invisible helpers
--     .Plots.<Name>                     one Model per player plot (Plot_01, ...; ModelStreamingMode Persistent, so
--                                       every client has every ServePoint), each with
--       .ServePoint                     BasePart (invisible, no collision or queries), about 3 studs above the ground
--                                       on the plot island at its bridgehead, in the Sell Cart zone: where the player
--                                       serves (the old safe zone is around it)
--       .Body.Label                     optional BillboardGui with a TextLabel, shows the owner (over the plot sign)
--       .Area                           optional ObjectValue, the plot island in the map (Ice Cream Map.Plots)
--       .Spawn                          optional SpawnLocation (invisible, no collision) in the middle of the plot
--                                       island: where the player spawns and the "my plot" button brings them; without
--                                       it they spawn a few studs in front of the ServePoint
--                                       ServePoint, Spawn and Body sit where PlotLayout (Config/Map.plot: 110 x 60
--                                       islands with four zones) puts them; MapService warns when they do not
--       .ArenaEntry                     optional BasePart (invisible, no collision or queries) on the strip above the
--                                       plot's ramp: where the "arena" button brings the player
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
local PlotLayout = require(Shared:WaitForChild("PlotLayout"))

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

-- Grows a cover model's box over its visible parts when they stick out of it (MapRules.coverBoxFit): scaling the whole
-- model in Studio scales the box with it, resizing only the meshes does not, and then scoops landed under the overhang
-- and throws flew through its edge. The box keeps its turn; only its centre and size change.
local function fitCoverBox(model: Model, box: BasePart)
	local frame = box.CFrame
	local low, high = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	local any = false
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= box then
			any = true
			local half = part.Size / 2
			for _, corner in
				{
					Vector3.new(-1, -1, -1),
					Vector3.new(1, -1, -1),
					Vector3.new(-1, 1, -1),
					Vector3.new(1, 1, -1),
					Vector3.new(-1, -1, 1),
					Vector3.new(1, -1, 1),
					Vector3.new(-1, 1, 1),
					Vector3.new(1, 1, 1),
				}
			do
				local p = frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(corner * half))
				low = { math.min(low[1], p.X), math.min(low[2], p.Y), math.min(low[3], p.Z) }
				high = { math.max(high[1], p.X), math.max(high[2], p.Y), math.max(high[3], p.Z) }
			end
		end
	end
	if not any then
		return
	end
	local half = box.Size / 2
	local centre, size = MapRules.coverBoxFit({ half.X, half.Y, half.Z }, { min = low, max = high }, MapConfig)
	if centre and size then
		box.CFrame = frame * CFrame.new(centre[1], centre[2], centre[3])
		box.Size = Vector3.new(size[1], size[2], size[3])
		warn(`[Map] {model:GetFullName()}: its meshes stuck out of {MapConfig.coverCollision}; made the box fit them`)
	end
end

-- Every Model in the cover folder (Config/Map.coverFolder) collides through exactly one invisible box: its part
-- named coverCollision, made from the model's bounding box when missing (a fresh import dragged in). All its other
-- parts are anchored and neither collide, nor take queries or touches, so only the box stops players, thrown balls
-- and the landing rays (the folder name keeps scoops from landing on it). Loose parts directly in the folder (the
-- old graybox walls with their *_Kolizja boxes) are left as they are. Returns how many models it prepared and how
-- many boxes it had to make.
function MapService.prepareCover(root: Instance): (number, number)
	local folder = root:FindFirstChild(MapConfig.coverFolder)
	if not folder then
		return 0, 0
	end
	local prepared, made = 0, 0
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local box = model:FindFirstChild(MapConfig.coverCollision)
		if not (box and box:IsA("BasePart")) then
			local cframe, size = model:GetBoundingBox()
			local part = Instance.new("Part")
			part.Name = MapConfig.coverCollision
			part.CFrame = cframe
			part.Size = size
			part.Transparency = 1
			part.CastShadow = false
			part.Parent = model
			box = part
			made += 1
			warn(`[Map] {model:GetFullName()} had no {MapConfig.coverCollision} box; made one from its bounding box`)
		end
		assert(box and box:IsA("BasePart"), "cover box ensured above")
		fitCoverBox(model, box)
		box.Anchored = true
		box.CanCollide = true
		box.CanQuery = true
		box.CanTouch = false
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= box then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
		prepared += 1
	end
	return prepared, made
end

-- Warns when a plot's helpers are not where PlotLayout puts them (Config/Map.plot): a place built for another plot
-- size still runs, but serving, spawning and the sign would sit off their zones.
local PLOT_TOLERANCE = 2 -- studs
local function checkPlots(plots: { Instance })
	local plot = MapConfig.plot
	local problems = {}
	for _, model in plots do
		local index = PlotLayout.indexOf(model.Name)
		if not index then
			table.insert(problems, `{model.Name}: not named Plot_NN`)
			continue
		end
		local frame = PlotLayout.frame(PlotLayout.laneAngle(index, MapConfig), MapConfig)
		local expected = {
			ServePoint = { PlotLayout.servePoint(plot) },
			Spawn = { PlotLayout.spawn(plot) },
			Body = { PlotLayout.sign(plot) },
		}
		for name, spot in expected do
			local helper = model:FindFirstChild(name)
			if helper and helper:IsA("BasePart") then
				local x, z = PlotLayout.toWorld(frame, spot[1], spot[2])
				local off = Vector2.new(helper.Position.X - x, helper.Position.Z - z).Magnitude
				if off > PLOT_TOLERANCE then
					table.insert(problems, string.format("%s.%s %.1f studs off", model.Name, name, off))
				end
			end
		end
	end
	if #problems > 0 then
		warn(`[Map] plot helpers do not match Config/Map.plot (PlotLayout): {table.concat(problems, ", ")}`)
	end
end

function MapService.Init()
	local missing = {}
	local root = workspace:FindFirstChild(MapConfig.root)
	local pier = workspace:FindFirstChild(MapConfig.pier)
	local marker = root and find(root, MapConfig.machineMarker)
	local plots = pier and pier:FindFirstChild("Plots")
	if not root then
		table.insert(missing, `Workspace.{MapConfig.root}`)
	end
	if not (marker and marker:IsA("BasePart")) then
		table.insert(missing, `the Big Swirl marker {table.concat(MapConfig.machineMarker, ".")}`)
	end
	if not plots then
		table.insert(missing, `Workspace.{MapConfig.pier}.Plots`)
	else
		for _, plot in plots:GetChildren() do
			if not plot:FindFirstChild("ServePoint") then
				table.insert(missing, `ServePoint in Plots.{plot.Name}`)
			end
		end
		if #plots:GetChildren() == 0 then
			table.insert(missing, "at least one plot in Plots")
		end
	end
	if #missing > 0 then
		error(`The place does not follow the map contract (top of MapService): missing {table.concat(missing, ", ")}.`)
	end
	assert(pier and plots and marker and marker:IsA("BasePart"), "map contract checked above")

	local machine = pier:FindFirstChild("BigSwirl") or buildMachine(pier, marker)
	local nozzle = machine:FindFirstChild("Nozzle") :: BasePart?
	if not nozzle then
		error("Workspace.Pier.BigSwirl has no Nozzle (map contract, top of MapService).")
	end

	MapService.map = root
	MapService.pier = pier
	MapService.nozzle = nozzle
	MapService.center = Vector3.new(marker.Position.X, topOf(marker), marker.Position.Z)
	MapService.plots = plots:GetChildren()
	table.sort(MapService.plots, function(a, b)
		return a.Name < b.Name
	end)
	checkPlots(MapService.plots)
	-- before the landing spots are sampled: they must see the cover boxes, not the meshes
	local coverModels = MapService.prepareCover(root)
	MapService.landingSpots = sampleLandingSpots(MapService.center)
	print(
		string.format(
			"[Map] %d plots, %d cover models, Big Swirl at (%.0f, %.1f, %.0f), %d landing spots",
			#MapService.plots,
			coverModels,
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

-- the landing spots in a ring round the machine, worked out once per ring
local inRing: { [string]: { number } } = {}

-- A random landing spot between `inner` and `outer` studs from the machine (one of Config/Launcher randomBands), all
-- equally likely; the spot nearest that ring when none lies in it.
function MapService.landingBetween(inner: number, outer: number, rng: Random): Vector3?
	local spots = MapService.landingSpots
	local key = `{inner}:{outer}`
	local between = inRing[key]
	if not between then
		between = MapRules.spotsBetween(spots, MapService.center.X, MapService.center.Z, inner, outer)
		inRing[key] = between
	end
	if #between == 0 then
		return nil
	end
	local index = between[rng:NextInteger(1, #between)]
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
