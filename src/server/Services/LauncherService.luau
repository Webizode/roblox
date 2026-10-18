-- The Big Swirl. Fires scoops on a parabola, announces where they land, and validates catch claims.
-- The server knows every scoop it fired, so a client can only catch scoops that exist, inside their flight
-- window, near its own tower top.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ShotMath = require(Shared:WaitForChild("ShotMath"))
local Flavors = require(Config:WaitForChild("Flavors"))
local Tuning = require(Config:WaitForChild("Launcher"))

local LauncherService = {}

type Shot = {
	id: number,
	flavorId: string,
	from: Vector3,
	to: Vector3,
	apex: number,
	t0: number,
	flight: number,
	resolved: boolean,
}

local registry
local graybox
local shots: { [number]: Shot } = {}
local nextId = 0
local tutorialLeft: { [Player]: number } = {}
local lastCatchAt: { [Player]: number } = {}
local rng = Random.new()

local totalWeight = 0
for _, flavor in Flavors.list do
	totalWeight += flavor.weight
end

local function pickFlavor(): string
	local roll = rng:NextNumber() * totalWeight
	for _, flavor in Flavors.list do
		roll -= flavor.weight
		if roll <= 0 then
			return flavor.id
		end
	end
	return Flavors.list[#Flavors.list].id
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function onGround(x: number, z: number): Vector3
	-- keep every target inside the landing circle around the machine
	local center = graybox.center
	local offset = Vector3.new(x - center.X, 0, z - center.Z)
	if offset.Magnitude > Tuning.landingRadius then
		offset = offset.Unit * Tuning.landingRadius
	end
	return Vector3.new(center.X + offset.X, graybox.groundY, center.Z + offset.Z)
end

local function randomOffset(radius: number): (number, number)
	local angle = rng:NextNumber() * math.pi * 2
	local distance = math.sqrt(rng:NextNumber()) * radius
	return math.cos(angle) * distance, math.sin(angle) * distance
end

local function pickTarget(): Vector3
	local candidates = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			if (tutorialLeft[player] or 0) > 0 then
				tutorialLeft[player] -= 1
				local dx, dz = randomOffset(Tuning.tutorialOffset)
				return onGround(root.Position.X + dx, root.Position.Z + dz)
			end
			table.insert(candidates, root)
		end
	end

	if #candidates > 0 and rng:NextNumber() < Tuning.targetPlayerChance then
		local root = candidates[rng:NextInteger(1, #candidates)]
		local dx, dz = randomOffset(Tuning.playerOffset)
		return onGround(root.Position.X + dx, root.Position.Z + dz)
	end

	local dx, dz = randomOffset(Tuning.landingRadius)
	return onGround(graybox.center.X + dx, graybox.center.Z + dz)
end

local function resolve(shot: Shot, catcher: Player?)
	if shot.resolved then
		return
	end
	shot.resolved = true
	shots[shot.id] = nil
	Remotes.ShotResolved:FireAllClients(shot.id, catcher)
end

local function fire()
	local from = graybox.nozzle.Position
	local to = pickTarget()
	local distance = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude

	nextId += 1
	local shot: Shot = {
		id = nextId,
		flavorId = pickFlavor(),
		from = from,
		to = to,
		apex = ShotMath.apex(distance, Tuning),
		t0 = workspace:GetServerTimeNow(),
		flight = ShotMath.flightTime(distance, Tuning),
		resolved = false,
	}
	shots[shot.id] = shot
	Remotes.ShotFired:FireAllClients(shot.id, shot.flavorId, shot.from, shot.to, shot.apex, shot.t0, shot.flight)

	task.delay(shot.flight * Tuning.resolveAfter, resolve, shot, nil)
end

local function shotPosition(shot: Shot, alpha: number): Vector3
	local x, y, z =
		ShotMath.position(shot.from.X, shot.from.Y, shot.from.Z, shot.to.X, shot.to.Y, shot.to.Z, shot.apex, alpha)
	return Vector3.new(x, y, z)
end

local function onCatchClaim(player: Player, id: any)
	if type(id) ~= "number" then
		return
	end
	local shot = shots[id]
	if not shot or shot.resolved then
		return
	end

	local time = workspace:GetServerTimeNow()
	if time - (lastCatchAt[player] or 0) < Tuning.minCatchGap then
		return
	end
	local alpha = (time - shot.t0) / shot.flight
	if alpha < Tuning.catchWindow[1] or alpha > Tuning.catchWindow[2] then
		return
	end

	local root = rootOf(player)
	local top = registry.TowerService.topPosition(player)
	if not root or not top then
		return
	end

	local scoop = shotPosition(shot, alpha)
	local horizontal = Vector3.new(scoop.X - top.X, 0, scoop.Z - top.Z).Magnitude
	local tolerance = Tuning.catchRadius
		+ Tuning.serverTolerance
		+ root.AssemblyLinearVelocity.Magnitude * Tuning.serverSpeedLead
	if horizontal > tolerance or math.abs(scoop.Y - top.Y) > Tuning.serverHeightTolerance then
		return
	end

	if registry.TowerService.addScoop(player, shot.flavorId) then
		lastCatchAt[player] = time
		resolve(shot, player)
	end
end

local function interval(): number
	local playerCount = math.max(1, #Players:GetPlayers())
	return math.max(Tuning.minInterval, Tuning.baseInterval / math.sqrt(playerCount))
end

function LauncherService.Init(reg)
	registry = reg
	graybox = reg.GrayboxService
end

function LauncherService.Start()
	Players.PlayerAdded:Connect(function(player)
		tutorialLeft[player] = Tuning.tutorialShots
	end)
	for _, player in Players:GetPlayers() do
		tutorialLeft[player] = Tuning.tutorialShots
	end
	Players.PlayerRemoving:Connect(function(player)
		tutorialLeft[player] = nil
		lastCatchAt[player] = nil
	end)

	Remotes.CatchClaim.OnServerEvent:Connect(onCatchClaim)

	while true do
		if #Players:GetPlayers() > 0 then
			fire()
		end
		task.wait(interval())
	end
end

return LauncherService
