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
local map
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

-- Every target is one of the map's landing spots (MapService): ground a player can stand on inside the landing
-- circle, never water, a roof, a palm or a railing. Near a player means a spot within `radius` of them, or the
-- nearest spot when they stand where nothing may land.
local function pickTarget(): Vector3?
	local candidates = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			if (tutorialLeft[player] or 0) > 0 then
				tutorialLeft[player] -= 1
				return map.landingNear(root.Position.X, root.Position.Z, Tuning.tutorialOffset, rng)
			end
			table.insert(candidates, root)
		end
	end

	if #candidates > 0 and rng:NextNumber() < Tuning.targetPlayerChance then
		local root = candidates[rng:NextInteger(1, #candidates)]
		return map.landingNear(root.Position.X, root.Position.Z, Tuning.playerOffset, rng)
	end

	return map.randomLanding(rng)
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
	local from = map.nozzle.Position
	local to = pickTarget()
	if not to then
		return -- a map without a single landing spot; MapService said so at the start
	end
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

-- Turns a claim down. The claimant already shows the scoop on its tower, so it is told right away (only that
-- client; for everyone else the scoop keeps flying and can still be caught).
local function reject(player: Player, id: number, reason: string, distance: number?)
	logRejection(player, id, reason, distance)
	Remotes.ShotResolved:FireClient(player, id, nil)
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

	local root = rootOf(player)
	local base = registry.TowerService.towerBase(player)
	if not root or not base then
		reject(player, id, "no character")
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local humanoid = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	local result = CatchRules.check({ claimTime = claimTime, tiltX = tiltX, tiltZ = tiltZ }, shot, {
		baseX = base.X,
		baseY = base.Y,
		baseZ = base.Z,
		count = registry.TowerService.count(player),
		speed = CatchRules.cappedSpeed(velocity.X, velocity.Z, if humanoid then humanoid.WalkSpeed else 0),
	}, workspace:GetServerTimeNow(), Tuning, TowerTuning, ShotMath, TowerShape)
	if not result.ok then
		reject(player, id, result.reason, result.distance)
		return
	end

	-- compared on the claimed times, so claims that arrive bunched up after a lag spike still count
	if math.abs(claimTime - (lastCatchAt[player] or -math.huge)) < Tuning.minCatchGap then
		reject(player, id, "caught another scoop at the same moment")
		return
	end

	if registry.TowerService.addScoop(player, shot.flavorId) then
		lastCatchAt[player] = claimTime
		resolve(shot, player)
	else
		reject(player, id, "cone is full")
	end
end

local function interval(): number
	local playerCount = math.max(1, #Players:GetPlayers())
	return math.max(Tuning.minInterval, Tuning.baseInterval / math.sqrt(playerCount))
end

function LauncherService.Init(reg)
	registry = reg
	map = reg.MapService
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
