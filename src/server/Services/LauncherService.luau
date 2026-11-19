-- The Big Swirl. Fires scoops on a parabola, announces where they land, and validates catch claims.
-- With the arm rig (Config/BigSwirl) each scoop leaves from the arm that points its way: the arm's cycle starts now
-- (every client turns its bones from the shot's times), the scoop shows in its cup from scoopAt and flies from the
-- release point at t0, so the landing circle appears a couple of seconds ahead. An arm is only picked again once its
-- cycle is over. Without the rig the scoop leaves from the Nozzle right away.
-- The server knows every scoop it fired, so a client can only catch scoops that exist, after their highest
-- point, at a recent time, close to its own tower (CatchRules).
-- The Studio test mode (DebugDummies, Features.debugPlayers) adds simulated players: they count for the fire rate and
-- the near shots, hear of every shot and catch some of them (takeByDummy). Off, its hooks do nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ShotMath = require(Shared:WaitForChild("ShotMath"))
local TowerShape = require(Shared:WaitForChild("TowerShape"))
local CatchRules = require(Shared:WaitForChild("CatchRules"))
local LaunchArms = require(Shared:WaitForChild("LaunchArms"))
local TargetRules = require(Shared:WaitForChild("TargetRules"))
local FlavorOdds = require(Shared:WaitForChild("FlavorOdds"))
local RarityFlight = require(Shared:WaitForChild("RarityFlight"))
local Flavors = require(Config:WaitForChild("Flavors"))
local VfxConfig = require(Config:WaitForChild("Vfx"))
local Tuning = require(Config:WaitForChild("Launcher"))
local ArmConfig = require(Config:WaitForChild("BigSwirl"))
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
local tracks: { [Player]: TargetRules.Track } = {} -- where each player last moved, for the near shots
local lastCatchAt: { [Player]: number } = {}
local lastRejectLog: { [Player]: number } = {}
local rng = Random.new()

-- the arm rig, when the machine has one: its root part, how many arms, when each arm is free again
type Arms = { root: BasePart, count: number, freeAt: { number } }
local arms: Arms? = nil

-- what the Big Swirl fires: a rarity by Config/Flavors.rarityChances, then one of its flavors (FlavorOdds); the
-- placeholder rares only with Features.placeholderRares
local pools = FlavorOdds.pools(Flavors.list, function(flavor)
	return not flavor.placeholder or Features.placeholderRares
end)

-- Studio only: the Workspace attribute ForceRarity ("epic", "legendary", ...) makes the Big Swirl fire only flavors of
-- that rarity, to look at them (set it in Edit mode before Play; remove it afterwards). Ignored outside Studio and for
-- a rarity without flavors.
local function forcedPool(): { string }?
	if not RunService:IsStudio() then
		return nil
	end
	local rarity = workspace:GetAttribute("ForceRarity")
	local pool = if type(rarity) == "string" then pools[string.lower(rarity)] else nil
	return if pool and #pool > 0 then pool else nil
end

local function pickFlavor(): string
	local forced = forcedPool()
	if forced then
		return forced[rng:NextInteger(1, #forced)]
	end
	return FlavorOdds.pick(rng:NextNumber(), rng:NextNumber(), Flavors, pools)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Keeps every player's track (TargetRules): where they last moved to and since when they stand still.
local function trackPlayers()
	local now = workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			tracks[player] = TargetRules.track(tracks[player], root.Position.X, root.Position.Z, now, Tuning)
		end
	end
end

-- Every target is one of the map's landing spots (MapService): ground a player can stand on, never water, a roof, a
-- palm or a railing. Only players in the arena (ArenaService) count: a new one's first shots land right at them
-- (tutorial), otherwise to a random spot of the whole arena, all equally likely (randomBands), and nearPlayerShare
-- (0 since 13.11.2026) near a player who is on the move (TargetRules): a spot within playerOffset of them, or the
-- nearest spot when they stand where nothing may land.
local function pickTarget(): Vector3?
	local now = workspace:GetServerTimeNow()
	local moving = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		-- players on the strip, the hub or their plot get nothing aimed at them; the tutorial waits for the arena
		if root and registry.ArenaService.inArena(player) then
			if (tutorialLeft[player] or 0) > 0 then
				tutorialLeft[player] -= 1
				return map.landingNear(root.Position.X, root.Position.Z, Tuning.tutorialOffset, rng)
			end
			local track = tracks[player]
			if track and not TargetRules.isIdle(track, now, Tuning) then
				table.insert(moving, root.Position)
			end
		end
	end
	-- the simulated players of the Studio test mode (DebugDummies) count like real ones
	for _, position in registry.DebugDummies.movingPositions(now) do
		table.insert(moving, position)
	end

	local index = TargetRules.choose(rng:NextNumber(), rng:NextNumber(), #moving, Tuning)
	if index then
		local position = moving[index]
		return map.landingNear(position.X, position.Z, Tuning.playerOffset, rng)
	end
	local band = TargetRules.band(rng:NextNumber(), Tuning.randomBands)
	return map.landingBetween(band.inner, band.outer, rng)
end

local function resolve(shot: Shot, catcher: Player?)
	if shot.resolved then
		return
	end
	shot.resolved = true
	shots[shot.id] = nil
	registry.DebugDummies.shotResolved(shot.id, catcher)
	-- nobody caught it: it lies where it came down for a few seconds (LootService.landed), unless that is the water.
	-- The free scoop is announced first, so clients swap the shot for it without a gap.
	local landed = catcher == nil and registry.LootService.landed(shot.flavorId, shot.to, shot.t0 + shot.flight)
	Remotes.ShotResolved:FireAllClients(shot.id, catcher, landed)
end

-- A simulated player of the Studio test mode caught the shot: it is gone without a free scoop and without a splash
-- (clients read `landed` as "a free scoop takes its place" and just drop the shot). False when it is already gone.
function LauncherService.takeByDummy(id: number): boolean
	local shot = shots[id]
	if not shot or shot.resolved then
		return false
	end
	shot.resolved = true
	shots[id] = nil
	Remotes.ShotResolved:FireAllClients(id, nil, true)
	return true
end

-- interval: seconds until the next shot, which sets how fast the arms play
local function fire(interval: number)
	local to = pickTarget()
	if not to then
		return -- a map without a single landing spot; MapService said so at the start
	end

	local now = workspace:GetServerTimeNow()
	local flavorId = pickFlavor()
	local flavor = Flavors.byId[flavorId]
	-- a legendary is announced: the Big Swirl glows first and only this shot leaves that much later (Config/Vfx.flight);
	-- the beat of the others stays, the loop below keeps its pace
	local hold = RarityFlight.delay(flavor and flavor.rarity or "common", VfxConfig.flight)
	local from, t0, arm, scoopAt, speed = map.nozzle.Position, now + hold, nil, nil, nil
	if arms then
		local base = arms.root.Position
		arm = LaunchArms.pick(to.X - base.X, to.Z - base.Z, arms.freeAt, now, ArmConfig)
		if not arm then
			registry.DebugDummies.shotSkipped()
			return -- the arms that point that way are all busy; the next tick picks again
		end
		local timing = LaunchArms.timing(LaunchArms.playSpeed(interval, ArmConfig), ArmConfig)
		local point = ArmConfig.releasePoints[arm]
		from = arms.root.CFrame:PointToWorldSpace(Vector3.new(point[1], point[2], point[3]))
		t0 = now + hold + timing.releaseLead
		scoopAt = t0 - timing.scoopLead
		arms.freeAt[arm] = now + hold + timing.busyFor -- never reused before its motion is over
		speed = timing.speed
	end
	local distance = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude

	nextId += 1
	local shot: Shot = {
		id = nextId,
		flavorId = flavorId,
		from = from,
		to = to,
		apex = ShotMath.apex(distance, Tuning),
		t0 = t0,
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
	Remotes.ShotFired:FireAllClients(
		shot.id,
		shot.flavorId,
		shot.from,
		shot.to,
		shot.apex,
		shot.t0,
		shot.flight,
		arm,
		scoopAt,
		speed
	)
	registry.DebugDummies.shotFired(shot.id, to, t0 + shot.flight)

	task.delay(t0 - now + shot.flight * Tuning.resolveAfter, resolve, shot, nil)
end

-- The arm rig of the machine the Nozzle sits in, if it has one (a RootPart and the bones of every arm in
-- Config/BigSwirl). The server only schedules the arms; every client turns their bones (BigSwirlArms). Nil keeps the
-- Nozzle launcher.
local function setUpArms(): Arms?
	local machine = map.nozzle.Parent
	local root = machine and machine:FindFirstChild("RootPart")
	if not machine or not root or not root:IsA("BasePart") then
		return nil
	end
	-- only bones count: the imported model also keeps values named after them (InitialPoses)
	local bones = {}
	for _, item in machine:GetDescendants() do
		if item:IsA("Bone") then
			bones[item.Name] = true
		end
	end
	for arm = 1, #ArmConfig.releasePoints do
		for _, name in { ArmConfig.shoulderBone, ArmConfig.cupBone } do
			if not bones[string.format(name, arm)] then
				return nil -- an arm without its bones: the Nozzle fires
			end
		end
	end
	return { root = root, count = #ArmConfig.releasePoints, freeAt = {} }
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

	-- luck (LuckService: the Scoop Chest and later other sources) may turn the caught scoop into a rarer one (only the
	-- catcher's tower changes; the shot itself stays what everybody saw fly)
	local lucky = registry.LuckService.luckyFlavor(player, shot.flavorId)
	if registry.TowerService.addScoop(player, lucky or shot.flavorId) then
		lastCatchAt[player] = claimTime
		resolve(shot, player)
		if lucky then
			Remotes.LuckyCatch:FireClient(player, shot.flavorId, lucky)
		end
	else
		reject(player, id, "cone is full")
	end
end

local function interval(): number
	local playerCount = math.max(1, #Players:GetPlayers() + registry.DebugDummies.count())
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
		tracks[player] = nil
	end)

	Remotes.CatchClaim.OnServerEvent:Connect(onCatchClaim)
	RunService.Heartbeat:Connect(trackPlayers)

	arms = setUpArms()
	print(
		if arms
			then `[Launcher] the Big Swirl fires from its {arms.count} arms`
			else "[Launcher] the Big Swirl fires from its Nozzle"
	)
	while true do
		local pause = interval()
		if #Players:GetPlayers() > 0 then
			fire(pause)
		end
		task.wait(pause)
	end
end

return LauncherService
