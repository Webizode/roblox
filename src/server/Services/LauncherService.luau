-- The Big Swirl. Fires scoops on a parabola, announces where they land, and validates catch claims.
-- The server knows every scoop it fired, so a client can only catch scoops that exist, after their highest
-- point, at a recent time, close to its own tower (CatchRules).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ShotMath = require(Shared:WaitForChild("ShotMath"))
local TowerShape = require(Shared:WaitForChild("TowerShape"))
local CatchRules = require(Shared:WaitForChild("CatchRules"))
local Flavors = require(Config:WaitForChild("Flavors"))
local Tuning = require(Config:WaitForChild("Launcher"))
local TowerTuning = require(Config:WaitForChild("Tower"))
local Features = require(Config:WaitForChild("Features"))

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
	-- the same path as plain numbers, for ShotMath/CatchRules
	fx: number,
	fy: number,
	fz: number,
	tx: number,
	ty: number,
	tz: number,
}

local registry
local graybox
local shots: { [number]: Shot } = {}
local nextId = 0
local tutorialLeft: { [Player]: number } = {}
local lastCatchAt: { [Player]: number } = {}
local lastRejectLog: { [Player]: number } = {}
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
		fx = from.X,
		fy = from.Y,
		fz = from.Z,
		tx = to.X,
		ty = to.Y,
		tz = to.Z,
	}
	shots[shot.id] = shot
	Remotes.ShotFired:FireAllClients(shot.id, shot.flavorId, shot.from, shot.to, shot.apex, shot.t0, shot.flight)

	task.delay(shot.flight * Tuning.resolveAfter, resolve, shot, nil)
end

local function logRejection(player: Player, id: number, reason: string, distance: number?)
	if not Features.debugCatch then
		return
	end
	local time = os.clock()
	if time - (lastRejectLog[player] or 0) < 1 then
		return
	end
	lastRejectLog[player] = time
	local detail = if distance then string.format(" (%.1f studs from the tower)", distance) else ""
	print(string.format("[Catch] rejected shot %d for %s: %s%s", id, player.Name, reason, detail))
end

-- Horizontal root speed, capped by what the Humanoid may actually walk. A spoofed velocity must not widen
-- the catch tolerance.
local function cappedSpeed(root: BasePart): number
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if flat ~= flat then
		return 0
	end
	local humanoid = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	local walkSpeed = if humanoid then humanoid.WalkSpeed else 18
	return math.min(flat, walkSpeed * 1.25)
end

-- claimTime: server time (GetServerTimeNow on the client) at which the scoop touched the tower.
-- tiltX/tiltZ: the client's tower tilt at that moment.
local function onCatchClaim(player: Player, id: any, claimTime: any, tiltX: any, tiltZ: any)
	if type(id) ~= "number" then
		return
	end
	local shot = shots[id]
	if not shot or shot.resolved then
		return
	end

	local time = workspace:GetServerTimeNow()
	if time - (lastCatchAt[player] or 0) < Tuning.minCatchGap then
		logRejection(player, id, "caught another scoop just before")
		return
	end

	local root = rootOf(player)
	local base = registry.TowerService.towerBase(player)
	if not root or not base then
		return
	end

	local result = CatchRules.check({ claimTime = claimTime, tiltX = tiltX, tiltZ = tiltZ }, shot, {
		baseX = base.X,
		baseY = base.Y,
		baseZ = base.Z,
		count = registry.TowerService.count(player),
		speed = cappedSpeed(root),
	}, time, Tuning, TowerTuning, ShotMath, TowerShape)
	if not result.ok then
		logRejection(player, id, result.reason, result.distance)
		return
	end

	if registry.TowerService.addScoop(player, shot.flavorId) then
		lastCatchAt[player] = time
		resolve(shot, player)
	else
		logRejection(player, id, "cone is full")
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
		lastRejectLog[player] = nil
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
