-- Studio stopwatch for the way home (Features.debugWalkTimer). Studio only; off, it does nothing.
--
-- Live: every pickup (the tower grows) starts the clock where the player stands; reaching the own plot (within
-- serveRadius of its ServePoint) stops it and prints the time, the straight distance and the tower.
--
-- Measured: once at the start, test figures (plain R15 rigs, server-owned) walk from set landing spots to their
-- plot with Roblox pathfinding (no jumping, so over the best rim ramp), first at the walk speed without a tower,
-- then at the walk speed with 36 scoops (Economy.walkSpeed, no sneakers, no sprint). Plots 02 to 04 stand for all
-- 12 (the arena repeats every 90 degrees). The tower's balance is not simulated, only its speed. Results go to the
-- output and to ServerStorage.WalkTimerLog as JSON.

local HttpService = game:GetService("HttpService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Economy = require(Shared:WaitForChild("Economy"))
local TargetRules = require(Shared:WaitForChild("TargetRules"))
local EconomyConfig = require(Config:WaitForChild("Economy"))
local Features = require(Config:WaitForChild("Features"))
local Launcher = require(Config:WaitForChild("Launcher"))

local WalkTimer = {}

local TOWER = 36 -- scoops for the loaded run
-- a quarter of the arena; Plot_01 is left out, the first real player stands there in a Studio test
local PLOTS = { "Plot_02", "Plot_03", "Plot_04" }
local GROUP = "WalkTimerFigures"
local GIVE_UP = 60 -- seconds per run
local START_DELAY = 15 -- seconds after the server start, so the map, the navigation mesh and the server have settled
local RIM = 135 -- studs from the machine to the arena's rim
local MACHINE = 34 -- studs from the machine's centre where the run out to the Big Swirl ends (it reaches out to 28)
local RANDOM_STARTS = 6 -- per plot: landing spots drawn like the Big Swirl's random shots (randomBands), any side

-- where a run home starts, from the plot's own direction: an angle off it and a distance from the machine
local SPOTS = {
	{ name = "arena rim, own side", turn = 0, radius = 125 },
	{ name = "arena middle, own side", turn = 0, radius = 80 },
	{ name = "next to the Big Swirl, own side", turn = 0, radius = MACHINE },
	{ name = "arena middle, 90 degrees off", turn = 90, radius = 80 },
	{ name = "arena rim, opposite side", turn = 180, radius = 125 },
	{ name = "random landing spot (weighted)" },
}

local registry
local map
local clocks: { [Player]: { at: number, from: Vector3, count: number } } = {}
local lastCount: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function live()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local home = registry.PlotService.servePoint(player)
		local count = registry.TowerService.count(player)
		if root and home then
			local clock = clocks[player]
			if clock and flatDistance(root.Position, home) <= EconomyConfig.serveRadius then
				print(
					string.format(
						"[Stoppuhr] %s: %.1f s from the last pickup to the plot, %.0f studs straight, tower %d",
						player.Name,
						os.clock() - clock.at,
						flatDistance(clock.from, home),
						count
					)
				)
				clocks[player] = nil
			elseif count > (lastCount[player] or 0) then
				clocks[player] = { at = os.clock(), from = root.Position, count = count }
			elseif count == 0 then
				clocks[player] = nil -- toppled or served away from the plot
			end
		end
		lastCount[player] = count
	end
end

local function figure(start: Vector3, speed: number): (Model, Humanoid)
	local rig =
		Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	rig.Name = "WalkTimerFigure"
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = speed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = GROUP
		end
	end
	rig:PivotTo(CFrame.new(start + Vector3.new(0, humanoid.HipHeight + 1.5, 0)))
	rig.Parent = workspace
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	root:SetNetworkOwner(nil)
	return rig, humanoid
end

-- The foot and the top of the rim ramp (Schody) with the shortest way from `start` over it to `home`. Pathfinding
-- takes the arena's rim for a step it can walk up, but it needs a jump, so a run out of the arena is led over a ramp.
local function viaRamp(start: Vector3, home: Vector3): { Vector3 }
	local center = map.center
	if flatDistance(start, center) > RIM then
		return { home }
	end
	local ramps = map.map:FindFirstChild("Schody")
	local best, bestCost = nil, math.huge
	for _, ramp in if ramps then ramps:GetChildren() else {} do
		if ramp:IsA("BasePart") then
			local out = Vector3.new(ramp.Position.X - center.X, 0, ramp.Position.Z - center.Z).Unit
			-- the ramp runs along its longest side (Z on the old wedges, X on the rounded IceKit ramp)
			local reach = math.max(ramp.Size.X, ramp.Size.Z) / 2 + 3
			local foot = ramp.Position - out * reach
			local top = ramp.Position + out * reach
			local cost = flatDistance(start, foot) + flatDistance(top, home)
			if cost < bestCost then
				best, bestCost = { foot, top, home }, cost
			end
		end
	end
	return best or { home }
end

-- The waypoints from `from` to `goal` (empty when pathfinding finds none: the leg is walked straight).
local function plan(from: Vector3, goal: Vector3): { PathWaypoint }
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
	local ok = pcall(function()
		path:ComputeAsync(from, goal)
	end)
	return if ok and path.Status == Enum.PathStatus.Success then path:GetWaypoints() else {}
end

-- Walks a planned leg; true once within `near` of `goal`.
local function walkLeg(
	humanoid: Humanoid,
	root: BasePart,
	waypoints: { PathWaypoint },
	goal: Vector3,
	near: number,
	deadline: number
): boolean
	local index = 2
	while os.clock() < deadline do
		if flatDistance(root.Position, goal) <= near then
			return true
		end
		local target = if waypoints[index] then waypoints[index].Position else goal
		humanoid:MoveTo(target)
		if waypoints[index] and flatDistance(root.Position, target) < 2.5 then
			index += 1
		end
		task.wait()
	end
	return false
end

-- Walks a figure from `start` to the ServePoint; seconds and the walked path length, or nil when it gets stuck.
local function run(start: Vector3, home: Vector3, speed: number, arriveWithin: number): (number?, number?)
	local rig, humanoid = figure(start, speed)
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	task.wait(0.5) -- land on the ground
	-- every leg is planned before the clock starts, so the time is walking only
	local legs = viaRamp(root.Position, home)
	local plans = {}
	local from = root.Position
	for index, goal in legs do
		plans[index] = plan(from, goal)
		from = goal
	end
	local began = os.clock()
	local deadline = began + GIVE_UP
	local walked, last = 0, root.Position
	local tracking = RunService.Heartbeat:Connect(function()
		walked += flatDistance(root.Position, last)
		last = root.Position
	end)
	local arrived = true
	for index, goal in legs do
		local near = if index == #legs then arriveWithin else 2
		if not walkLeg(humanoid, root, plans[index], goal, near, deadline) then
			arrived = false
			break
		end
	end
	local seconds = os.clock() - began
	tracking:Disconnect()
	rig:Destroy()
	if not arrived then
		return nil, walked
	end
	return seconds, walked
end

local function measure()
	local speeds = {
		{ label = "no tower", speed = Economy.walkSpeed(0, 0, EconomyConfig) },
		{ label = `{TOWER} scoops`, speed = Economy.walkSpeed(TOWER, 0, EconomyConfig) },
	}
	-- the start spots, the same for both paces: landing spots near each set point, and some drawn like random shots
	local rng = Random.new(7)
	local starts = {}
	local outbound = {} -- from the spawn in front of the plot out to the Big Swirl
	for _, plotName in PLOTS do
		local plot
		for _, candidate in map.plots do
			if candidate.Name == plotName then
				plot = candidate
			end
		end
		local servePoint = plot and plot:FindFirstChild("ServePoint") :: BasePart?
		if servePoint then
			local home = servePoint.Position
			local own = math.atan2(home.X - map.center.X, home.Z - map.center.Z)
			local function add(name: string, start: Vector3?)
				if start then
					table.insert(
						starts,
						{ plot = plotName, spot = name, from = start, to = home, within = EconomyConfig.serveRadius }
					)
				end
			end
			for _, spot in SPOTS do
				if spot.radius then
					local angle = own + math.rad(spot.turn)
					local x = map.center.X + math.sin(angle) * spot.radius
					local z = map.center.Z + math.cos(angle) * spot.radius
					add(spot.name, map.landingNear(x, z, 3, rng))
				else
					for _ = 1, RANDOM_STARTS do
						local band = TargetRules.band(rng:NextNumber(), Launcher.randomBands)
						add(spot.name, map.landingBetween(band.inner, band.outer, rng))
					end
				end
			end
			-- where PlotService puts a new character: serveRadius + 4 in front of the ServePoint, on the ground
			local inward = Vector3.new(map.center.X - home.X, 0, map.center.Z - home.Z).Unit
			local spawnSpot = home + inward * (EconomyConfig.serveRadius + 4)
			local feet = map.groundAt(spawnSpot.X, spawnSpot.Y + 6, spawnSpot.Z, 30).y or spawnSpot.Y - 3
			local machine = map.center - inward * MACHINE
			table.insert(outbound, {
				plot = plotName,
				spot = "plot to the Big Swirl",
				from = Vector3.new(spawnSpot.X, feet, spawnSpot.Z),
				to = Vector3.new(machine.X, map.center.Y + 0.3, machine.Z),
				within = 3,
			})
		end
	end

	-- the first round of figures runs slow (the server is still busy loading them), so a warm-up round goes first and
	-- is not counted
	local rounds = { { label = "warm-up", speed = speeds[1].speed, counted = false, starts = starts } }
	for _, pace in speeds do
		table.insert(rounds, { label = pace.label, speed = pace.speed, counted = true, starts = starts })
	end
	local sprint = Economy.walkSpeed(0, 0, EconomyConfig, true)
	table.insert(rounds, { label = "sprint, no tower", speed = sprint, counted = true, starts = outbound })
	local results = {}
	for _, round in rounds do
		print(string.format("[Stoppuhr] test walks at %.1f studs/s (%s) ...", round.speed, round.label))
		local jobs, done = {}, 0
		for _, start in round.starts do
			local job = { plot = start.plot, spot = start.spot, pace = round.label }
			table.insert(jobs, job)
			task.spawn(function()
				job.seconds, job.studs = run(start.from, start.to, round.speed, start.within)
				done += 1
			end)
		end
		while done < #jobs do
			task.wait(0.5)
		end
		if round.counted then
			for _, job in jobs do
				table.insert(results, job)
			end
		end
	end

	-- average over the three plots, per start spot and pace
	print("[Stoppuhr] walks out to the Big Swirl and home to the own plot (average of plots 02-04):")
	local rows = { "plot to the Big Swirl" }
	for _, spot in SPOTS do
		table.insert(rows, spot.name)
	end
	local paces = { { label = "sprint, no tower" } }
	for _, pace in speeds do
		table.insert(paces, pace)
	end
	for _, row in rows do
		local spot = { name = row }
		local parts = {}
		for _, pace in paces do
			local sum, studs, count, stuck = 0, 0, 0, 0
			for _, job in results do
				if job.spot == spot.name and job.pace == pace.label then
					if job.seconds then
						sum += job.seconds
						studs += job.studs
						count += 1
					else
						stuck += 1
					end
				end
			end
			if count + stuck > 0 then
				table.insert(
					parts,
					if count > 0
						then string.format(
							"%s %.1f s (%.0f studs)%s",
							pace.label,
							sum / count,
							studs / count,
							if stuck > 0 then `, {stuck} stuck` else ""
						)
						else `{pace.label}: all stuck`
				)
			end
		end
		print(string.format("[Stoppuhr]   %-34s %s", spot.name, table.concat(parts, " | ")))
	end
	local log = Instance.new("StringValue")
	log.Name = "WalkTimerLog"
	log.Value = HttpService:JSONEncode(results)
	local old = ServerStorage:FindFirstChild("WalkTimerLog")
	if old then
		old:Destroy()
	end
	log.Parent = ServerStorage
end

function WalkTimer.Init(reg)
	registry = reg
	map = reg.MapService
end

function WalkTimer.Start()
	if not Features.debugWalkTimer or not RunService:IsStudio() then
		return
	end
	PhysicsService:RegisterCollisionGroup(GROUP)
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	RunService.Heartbeat:Connect(live)
	task.delay(START_DELAY, measure)
end

return WalkTimer
