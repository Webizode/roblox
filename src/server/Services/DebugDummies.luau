-- Studio test mode for the 12-player map (Features.debugPlayers): simulated players, so the Big Swirl's spread and
-- the scoops per player can be seen without 12 people. Studio only; off, every hook below does nothing.
--
-- A dummy takes a plot from the back of the list (Plot_12 downwards; real players take theirs from the front),
-- runs straight for a shot it can reach before it lands and nobody closer runs for (ignoring cover and the rim, so
-- this is the best case for the dummies), catches it if it stands there when it lands, and after a few scoops walks
-- out of the arena along its own lane, as slow as the tower makes it (Economy.walkSpeed). Out of the arena it serves
-- (as if the "my plot" button took it home) and comes back in from its ArenaEntry. It counts for the fire rate and for
-- the near shots like a real player in the arena. Every landing spot gets a disc: white in the
-- air, green caught by a dummy, blue caught by a player, red not caught. A summary goes to the output every 30 s and
-- to ServerStorage.DebugDummiesLog as JSON.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Economy = require(Shared:WaitForChild("Economy"))
local TargetRules = require(Shared:WaitForChild("TargetRules"))
local ArenaZone = require(Shared:WaitForChild("ArenaZone"))
local EconomyConfig = require(Config:WaitForChild("Economy"))
local Features = require(Config:WaitForChild("Features"))
local Launcher = require(Config:WaitForChild("Launcher"))
local MapConfig = require(Config:WaitForChild("Map"))
local Palette = require(Config:WaitForChild("Palette"))

local DebugDummies = {}

local REPORT_EVERY = 30 -- seconds
local MAX_MARKERS = 400
local SERVE_MIN, SERVE_MAX = 6, 14 -- scoops a dummy carries before it walks home
local WANDER_SECONDS = 3
local RINGS = { 25, 55, 80, 100 } -- studs from the machine (Config/Launcher randomBands); then everything further out
local RAISED = 2 -- studs above the arena floor (the Big Swirl's marker): a landing in the arena this high is on a plateau
local ARENA = MapConfig.arena.radius -- studs from the machine to the arena's rim
-- a dummy leaves the arena up its own ramp and serves once it is out of the arena zone (ArenaZone), this far out on
-- its lane: just past the ramp's top edge
local OUT = MapConfig.arena.rampTop + 1

local COLOR = {
	flying = Color3.new(1, 1, 1),
	dummy = Color3.fromRGB(70, 200, 90),
	player = Color3.fromRGB(60, 130, 255),
	missed = Color3.fromRGB(230, 60, 60),
}

type Dummy = {
	name: string,
	exit: Vector3, -- where it leaves the arena: on its own lane, just past the rim
	entry: Vector3, -- where it comes back in: the plot's ArenaEntry on the strip
	angle: number, -- the plot's direction from the machine (radians)
	position: Vector3,
	carrying: number,
	serveAt: number,
	goingHome: boolean,
	shotId: number?,
	wanderTo: Vector3?,
	wanderUntil: number,
	track: TargetRules.Track,
	body: Part,
	label: TextLabel,
	catches: number,
	serves: number,
	scoopsServed: number,
}

type Pending = { to: Vector3, landAt: number, takenBy: Dummy?, marker: Part? }

local registry
local map
local enabled = false
local dummies: { Dummy } = {}
local pending: { [number]: Pending } = {}
local markers: { Part } = {}
local folder: Folder
local rng = Random.new()
local startedAt = 0
local playerCatches: { [string]: number } = {}
local stats = {
	fired = 0,
	skipped = 0,
	byDummy = 0,
	byPlayer = 0,
	missed = 0,
	raised = 0,
	rings = table.create(#RINGS + 1, 0),
	sectors = {}, -- one per plot, filled in Start
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function groundY(x: number, z: number, fallback: number): number
	return map.groundAt(x, 40, z, 80).y or fallback
end

local function marker(to: Vector3): Part
	local disc = Instance.new("Part")
	disc.Name = "Landing"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.15, 1.8, 1.8)
	disc.CFrame = CFrame.new(to + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.Material = Enum.Material.Neon
	disc.Color = COLOR.flying
	disc.Parent = folder
	table.insert(markers, disc)
	if #markers > MAX_MARKERS then
		table.remove(markers, 1):Destroy()
	end
	return disc
end

local function paint(entry: Pending?, color: Color3)
	if entry and entry.marker and entry.marker.Parent then
		entry.marker.Color = color
	end
end

local function makeDummy(index: number, plot: Model): Dummy?
	local servePoint = plot:FindFirstChild("ServePoint") :: BasePart?
	if not servePoint then
		return nil
	end
	local home = servePoint.Position
	local outward = flat(home - map.center).Unit
	local exit = map.center + outward * (OUT + 1)
	local entryPart = plot:FindFirstChild("ArenaEntry")
	local start = if entryPart and entryPart:IsA("BasePart") then entryPart.Position else exit

	local body = Instance.new("Part")
	body.Name = "Dummy_" .. plot.Name
	body.Size = Vector3.new(2, 5, 1)
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Material = Enum.Material.Neon
	body.Color = Color3.fromHex(Palette.playerColors[(index - 1) % #Palette.playerColors + 1])
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(110, 34)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = body
	body.Parent = folder

	local now = workspace:GetServerTimeNow()
	return {
		name = plot.Name,
		exit = exit,
		entry = start,
		angle = math.atan2(home.X - map.center.X, home.Z - map.center.Z),
		position = Vector3.new(start.X, groundY(start.X, start.Z, home.Y - 3), start.Z),
		carrying = 0,
		serveAt = rng:NextInteger(SERVE_MIN, SERVE_MAX),
		goingHome = false,
		shotId = nil,
		wanderTo = nil,
		wanderUntil = 0,
		track = TargetRules.track(nil, start.X, start.Z, now, Launcher),
		body = body,
		label = label,
		catches = 0,
		serves = 0,
		scoopsServed = 0,
	}
end

-- The closest shot this dummy reaches before it lands and nobody closer runs for. A dummy closer to a shot takes it
-- over from the one running for it (that one looks for another), so the order the dummies are stepped in does not
-- decide who gets the scoops.
local function pickShot(dummy: Dummy, speed: number, now: number): number?
	local best, bestDistance = nil, math.huge
	for id, entry in pending do
		if entry.landAt > now then
			local distance = (flat(entry.to) - flat(dummy.position)).Magnitude
			local rival = entry.takenBy
			local closer = rival == nil or (flat(entry.to) - flat(rival.position)).Magnitude > distance
			if closer and distance <= speed * (entry.landAt - now) and distance < bestDistance then
				best, bestDistance = id, distance
			end
		end
	end
	return best
end

-- A spot in the arena on the dummy's own side, for when no shot is in reach.
local function wanderSpot(dummy: Dummy): Vector3
	local angle = dummy.angle + rng:NextNumber(-0.9, 0.9)
	local radius = rng:NextNumber(25, Launcher.randomBands[#Launcher.randomBands].outer - 5)
	return map.center + Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
end

local function step(dummy: Dummy, dt: number, now: number)
	local speed = Economy.walkSpeed(dummy.carrying, 0, EconomyConfig)
	local goal: Vector3

	if not dummy.goingHome and dummy.carrying >= dummy.serveAt then
		dummy.goingHome = true
		local entry = dummy.shotId and pending[dummy.shotId]
		if entry and entry.takenBy == dummy then
			entry.takenBy = nil
		end
		dummy.shotId = nil
	end

	if dummy.goingHome then
		goal = dummy.exit
		if not ArenaZone.contains(dummy.position.X, dummy.position.Z, MapConfig.arena) then
			-- out alive: home with the button, serve, and back in from the arena entry
			dummy.serves += 1
			dummy.scoopsServed += dummy.carrying
			dummy.carrying = 0
			dummy.serveAt = rng:NextInteger(SERVE_MIN, SERVE_MAX)
			dummy.goingHome = false
			dummy.position =
				Vector3.new(dummy.entry.X, groundY(dummy.entry.X, dummy.entry.Z, dummy.entry.Y), dummy.entry.Z)
			goal = dummy.position
		end
	else
		local entry = dummy.shotId and pending[dummy.shotId]
		if dummy.shotId and (not entry or entry.takenBy ~= dummy) then
			dummy.shotId, entry = nil, nil -- caught, over, or a closer dummy took it over
		end
		if entry and now >= entry.landAt then
			if
				(flat(entry.to) - flat(dummy.position)).Magnitude <= Launcher.catchRadius
				and registry.LauncherService.takeByDummy(dummy.shotId)
			then
				pending[dummy.shotId :: number] = nil
				paint(entry, COLOR.dummy)
				stats.byDummy += 1
				dummy.catches += 1
				dummy.carrying += 1
			else
				entry.takenBy = nil
			end
			dummy.shotId, entry = nil, nil
		end
		if not dummy.shotId then
			dummy.shotId = pickShot(dummy, speed, now)
			entry = dummy.shotId and pending[dummy.shotId]
			if entry then
				entry.takenBy = dummy
			end
		end
		if entry then
			goal = entry.to
		else
			if not dummy.wanderTo or now >= dummy.wanderUntil then
				dummy.wanderTo = wanderSpot(dummy)
				dummy.wanderUntil = now + WANDER_SECONDS
			end
			goal = dummy.wanderTo :: Vector3
		end
	end

	local offset = flat(goal) - flat(dummy.position)
	local distance = offset.Magnitude
	if distance > 1e-3 then
		local move = offset.Unit * math.min(distance, speed * dt)
		local x, z = dummy.position.X + move.X, dummy.position.Z + move.Z
		dummy.position = Vector3.new(x, groundY(x, z, dummy.position.Y), z)
	end
	dummy.track = TargetRules.track(dummy.track, dummy.position.X, dummy.position.Z, now, Launcher)
	dummy.body.CFrame = CFrame.new(dummy.position + Vector3.new(0, 2.5, 0))
	-- the label can be switched off while playing: attribute Labels on Workspace.DebugDummies
	local showLabel = folder:GetAttribute("Labels") ~= false
	local gui = dummy.label.Parent :: BillboardGui
	gui.Enabled = showLabel
	if showLabel then
		dummy.label.Text =
			string.format("%s  %d/%d  ✓%d", string.sub(dummy.name, -2), dummy.carrying, dummy.serveAt, dummy.catches)
	end
end

local function summary(): { [string]: any }
	local minutes = math.max(1e-3, (workspace:GetServerTimeNow() - startedAt) / 60)
	local perDummy = {}
	local low, high, sum = math.huge, -math.huge, 0
	for _, dummy in dummies do
		local rate = dummy.catches / minutes
		low, high, sum = math.min(low, rate), math.max(high, rate), sum + rate
		perDummy[dummy.name] = { catches = dummy.catches, perMinute = rate, scoopsServed = dummy.scoopsServed }
	end
	local perPlayer = {}
	for name, catches in playerCatches do
		perPlayer[name] = { catches = catches, perMinute = catches / minutes }
	end
	local tried = stats.fired + stats.skipped
	return {
		seconds = minutes * 60,
		players = #Players:GetPlayers() + #dummies,
		dummies = #dummies,
		fired = stats.fired,
		firedPerSecond = stats.fired / (minutes * 60),
		skippedByArms = stats.skipped,
		skippedShare = if tried > 0 then stats.skipped / tried else 0,
		caughtByDummies = stats.byDummy,
		caughtByPlayers = stats.byPlayer,
		notCaught = stats.missed,
		onPlateaus = stats.raised,
		rings = stats.rings,
		sectors = stats.sectors,
		dummyPerMinute = {
			min = if #dummies > 0 then low else 0,
			max = if #dummies > 0 then high else 0,
			average = if #dummies > 0 then sum / #dummies else 0,
		},
		perDummy = perDummy,
		perPlayer = perPlayer,
	}
end

local function report()
	local s = summary()
	local log = ServerStorage:FindFirstChild("DebugDummiesLog") :: StringValue?
	if not log then
		local value = Instance.new("StringValue")
		value.Name = "DebugDummiesLog"
		value.Parent = ServerStorage
		log = value
	end
	(log :: StringValue).Value = HttpService:JSONEncode(s)

	local ringText = {}
	local inner = 0
	for index, count in s.rings do
		local outer = RINGS[index]
		local share = if s.fired > 0 then count / s.fired * 100 else 0
		table.insert(ringText, string.format("%s %.0f%%", if outer then `{inner}-{outer}` else `>{inner}`, share))
		inner = outer or inner
	end
	local you = {}
	for name, entry in s.perPlayer do
		table.insert(you, string.format("%s %.1f", name, entry.perMinute))
	end
	print(
		string.format(
			"[Dummies] %.0f s, %d players (%d simulated): fired %d (%.2f/s), lost to busy arms %d (%.0f%%); caught by dummies %d, by players %d, not caught %d",
			s.seconds,
			s.players,
			s.dummies,
			s.fired,
			s.firedPerSecond,
			s.skippedByArms,
			s.skippedShare * 100,
			s.caughtByDummies,
			s.caughtByPlayers,
			s.notCaught
		)
	)
	print(
		string.format(
			"[Dummies] catches per minute: dummies %.1f on average (%.1f to %.1f)%s",
			s.dummyPerMinute.average,
			s.dummyPerMinute.min,
			s.dummyPerMinute.max,
			if #you > 0 then "; players: " .. table.concat(you, ", ") else ""
		)
	)
	print(
		string.format(
			"[Dummies] landings by distance: %s; on plateaus %d; per plot sector from Plot_01 on: %s",
			table.concat(ringText, ", "),
			s.onPlateaus,
			table.concat(s.sectors, " ")
		)
	)
end

-- How many simulated players there are (0 when the test mode is off).
function DebugDummies.count(): number
	return #dummies
end

-- Where the dummies are that are in the arena and on the move (not standing still, TargetRules), for the near shots.
function DebugDummies.movingPositions(now: number): { Vector3 }
	local list = {}
	for _, dummy in dummies do
		local inArena = ArenaZone.contains(dummy.position.X, dummy.position.Z, MapConfig.arena)
		if inArena and not TargetRules.isIdle(dummy.track, now, Launcher) then
			table.insert(list, dummy.position)
		end
	end
	return list
end

function DebugDummies.shotFired(id: number, to: Vector3, landAt: number)
	if not enabled then
		return
	end
	stats.fired += 1
	local distance = flat(to - map.center).Magnitude
	local ring = #RINGS + 1
	for index, outer in RINGS do
		if distance <= outer then
			ring = index
			break
		end
	end
	stats.rings[ring] += 1
	local angle = math.deg(math.atan2(to.X - map.center.X, to.Z - map.center.Z)) % 360
	local sector = math.floor(angle / (360 / #stats.sectors)) % #stats.sectors + 1
	stats.sectors[sector] += 1
	if to.Y > map.center.Y + RAISED and distance <= ARENA then
		stats.raised += 1
	end
	pending[id] = { to = to, landAt = landAt, takenBy = nil, marker = marker(to) }
end

function DebugDummies.shotSkipped()
	if enabled then
		stats.skipped += 1
	end
end

-- A shot is over: caught by a real player, or not caught at all.
function DebugDummies.shotResolved(id: number, catcher: Player?)
	if not enabled then
		return
	end
	local entry = pending[id]
	pending[id] = nil
	if catcher then
		stats.byPlayer += 1
		playerCatches[catcher.Name] = (playerCatches[catcher.Name] or 0) + 1
		paint(entry, COLOR.player)
	else
		stats.missed += 1
		paint(entry, COLOR.missed)
	end
end

function DebugDummies.Init(reg)
	registry = reg
	map = reg.MapService
end

function DebugDummies.Start()
	local wanted = Features.debugPlayers or 0
	if wanted <= 1 or not RunService:IsStudio() then
		return
	end
	enabled = true
	local old = workspace:FindFirstChild("DebugDummies")
	if old then
		old:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "DebugDummies"
	folder:SetAttribute("Labels", Features.debugDummyLabels ~= false)
	folder.Parent = workspace

	-- you are one of the players; the dummies take the plots from the back
	local plots = map.plots
	stats.sectors = table.create(#plots, 0)
	for index = 1, math.min(wanted - 1, #plots) do
		local dummy = makeDummy(#plots - index + 1, plots[#plots - index + 1])
		if dummy then
			table.insert(dummies, dummy)
		end
	end
	startedAt = workspace:GetServerTimeNow()
	print(
		`[Dummies] Studio test mode: {#dummies} simulated players on {dummies[#dummies] and dummies[#dummies].name or "-"} to {dummies[1] and dummies[1].name or "-"}`
	)

	RunService.Heartbeat:Connect(function(dt)
		local now = workspace:GetServerTimeNow()
		for _, dummy in dummies do
			step(dummy, dt, now)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(REPORT_EVERY)
			report()
		end
	end)
end

return DebugDummies
