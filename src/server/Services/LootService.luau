-- Spilled scoops (design rules 1, 2 and 4). The server owns every free scoop: where it falls and rolls, whether it
-- sinks, who may pick it up and when it disappears. Clients only draw them (LootRenderer) and claim the ones their
-- player walks over; a claim is checked like a catch (Loot.inReach with the catch tolerances) and lands on the
-- claimant's tower through TowerService.addScoop.
-- Scoops from the Big Swirl that nobody caught (LootService.landed) lie on the ground the same way for a few seconds,
-- free for anybody.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Loot = require(Shared:WaitForChild("Loot"))
local TowerShape = require(Shared:WaitForChild("TowerShape"))
local CatchRules = require(Shared:WaitForChild("CatchRules"))
local LootConfig = require(Config:WaitForChild("Loot"))
local TowerTuning = require(Config:WaitForChild("Tower"))
local Features = require(Config:WaitForChild("Features"))

local LootService = {}

type Free = {
	id: number,
	ownerPlayer: Player?, -- nil once the owner left
	owner: number, -- UserId, what Loot.canCollect compares with
	path: Loot.Path,
	baseX: number,
	baseY: number,
	baseZ: number,
	groundY: number, -- the ground under the landing point (a guess below the tower when it lands in water)
	profile: Loot.Profile, -- the ground along the roll, and where the roll stops or sinks
	t0: number, -- server time of the topple
	landedAt: number,
	ownerFrom: number, -- the owner may pick it up from then on
	ownerUntil: number,
	expiresAt: number,
	endAt: number, -- expiresAt, or earlier when it rolls into the water
	sinks: boolean,
	landed: boolean, -- from the Big Swirl, nobody caught it (Loot.landed); otherwise spilled from a tower
}

-- how far below the tower base the server looks for ground under a scoop
local GROUND_REACH = 40

local registry
local free: { [number]: Free } = {}
local order: { number } = {} -- ids, oldest first
local nextId = 0
local claimBudget: { [Player]: { since: number, count: number } } = {}
local lastRejectLog: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The ground height under (x, z) looking down from `fromY`, or nil over water or nothing.
local function groundAt(x: number, fromY: number, z: number): number?
	return registry.MapService.groundAt(x, fromY, z, GROUND_REACH).y
end

-- The ground under a scoop right now: where it lies along its roll.
local function groundNow(scoop: Free, elapsed: number): number
	local roll = math.min(Loot.rollShare(elapsed, LootConfig), scoop.profile.stopShare)
	return Loot.groundHeight(scoop.profile, roll) or scoop.groundY
end

-- What clients get for one scoop: enough to draw the same path and to know who may claim it.
local function wire(scoop: Free)
	local path = scoop.path
	return {
		id = scoop.id,
		flavorId = path.flavorId,
		owner = scoop.owner,
		base = Vector3.new(scoop.baseX, scoop.baseY, scoop.baseZ),
		groundY = scoop.groundY,
		shares = scoop.profile.shares,
		heights = scoop.profile.heights,
		stopShare = scoop.profile.stopShare,
		start = Vector3.new(path.sx, path.sy, path.sz),
		land = Vector3.new(path.lx, 0, path.lz),
		roll = Vector3.new(path.rx, 0, path.rz),
		t0 = scoop.t0,
		ownerFrom = scoop.ownerFrom,
		ownerUntil = scoop.ownerUntil,
		endAt = scoop.endAt,
		sinks = scoop.sinks,
		landed = scoop.landed,
	}
end

local function remove(id: number, catcher: Player?, reason: string)
	if not free[id] then
		return
	end
	free[id] = nil
	local index = table.find(order, id)
	if index then
		table.remove(order, index)
	end
	Remotes.LootRemoved:FireAllClients(id, catcher, reason)
end

local function logRejection(player: Player, id: number, reason: string)
	if not Features.debugCatch then
		return
	end
	local time = os.clock()
	if time - (lastRejectLog[player] or 0) < 1 then
		return
	end
	lastRejectLog[player] = time
	print(string.format("[Loot] rejected scoop %d for %s: %s", id, player.Name, reason))
end

local function reject(player: Player, id: number, reason: string)
	logRejection(player, id, reason)
	Remotes.LootRejected:FireClient(player, id)
end

local function onClaim(player: Player, id: any)
	if type(id) ~= "number" then
		return
	end
	-- a spam guard only: walking through a heap legitimately claims several scoops in the same frame
	local clock = os.clock()
	local budget = claimBudget[player]
	if not budget or clock - budget.since >= 1 then
		budget = { since = clock, count = 0 }
		claimBudget[player] = budget
	end
	budget.count += 1
	if budget.count > LootConfig.maxClaimsPerSecond then
		return
	end
	local scoop = free[id]
	if not scoop then
		return -- already gone; the client heard or will hear LootRemoved
	end
	local time = now()
	local ok, reason = Loot.canCollect(scoop, player.UserId, time)
	if not ok then
		return reject(player, id, reason)
	end
	local root = rootOf(player)
	local humanoid = root and root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return reject(player, id, "no character")
	end
	if registry.CombatService.isDown(player) then
		return reject(player, id, "knocked down")
	end

	local elapsed = time - scoop.t0
	local x, _, z = Loot.position(scoop.path, elapsed, LootConfig, scoop.profile.stopShare)
	local position = root.Position
	local velocity = root.AssemblyLinearVelocity
	local speed = CatchRules.cappedSpeed(velocity.X, velocity.Z, humanoid.WalkSpeed)
	if
		not Loot.inReach(
			position.X - (scoop.baseX + x),
			position.Y - groundNow(scoop, elapsed) - humanoid.HipHeight - root.Size.Y / 2,
			position.Z - (scoop.baseZ + z),
			speed,
			true,
			LootConfig
		)
	then
		return reject(player, id, "too far away")
	end

	if not registry.TowerService.addScoop(player, scoop.path.flavorId) then
		return reject(player, id, "cone is full")
	end
	if not scoop.landed then
		registry.KillTestLog.pickup(player, scoop.owner) -- the kill test counts spilled scoops taken back or stolen
	end
	remove(id, player, "caught")
end

-- Drops the oldest free scoops until everything fits and the newest are never lost.
-- The ids of the free scoops of one kind (landed from the Big Swirl, or spilled), oldest first.
local function ofKind(landed: boolean): { number }
	local ids = {}
	for _, id in order do
		if free[id].landed == landed then
			table.insert(ids, id)
		end
	end
	return ids
end

-- Drops the oldest spilled scoops until everything fits and the newest are never lost. Landed scoops have their own
-- limit (LootService.landed) and are not counted here.
local function makeRoom(incoming: number): number
	local spilled = ofKind(false)
	local excess, kept = Loot.makeRoom(#spilled, incoming, LootConfig)
	for index = 1, excess do
		remove(spilled[index], nil, "room")
	end
	return kept
end

local function expire()
	local time = now()
	for index = #order, 1, -1 do
		local scoop = free[order[index]]
		if scoop and time >= scoop.endAt then
			remove(scoop.id, nil, if scoop.sinks then "water" else "puff")
		end
	end
end

function LootService.Init(reg)
	registry = reg
end

function LootService.Start()
	Players.PlayerAdded:Connect(function(player)
		local list = {}
		for _, id in order do
			table.insert(list, wire(free[id]))
		end
		if #list > 0 then
			Remotes.LootSpawned:FireClient(player, list)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		claimBudget[player] = nil
		lastRejectLog[player] = nil
		-- an owner who left reserves nothing any more
		local ids = {}
		local time = now()
		for _, scoop in free do
			if scoop.ownerPlayer == player then
				scoop.ownerPlayer = nil
				if scoop.ownerUntil > time then
					scoop.ownerUntil = time
					table.insert(ids, scoop.id)
				end
			end
		end
		if #ids > 0 then
			Remotes.LootUpdated:FireAllClients(ids, time)
		end
	end)
	Remotes.LootClaim.OnServerEvent:Connect(onClaim)
	RunService.Heartbeat:Connect(expire)
end

-- A tower toppled: the scoops above `keep` fall off. flavorIds is the tower before the topple (bottom to top),
-- tiltX/tiltZ its last known lean. Nothing happens when nothing falls (small towers keep everything).
function LootService.spill(player: Player, flavorIds: { string }, keep: number, tiltX: number, tiltZ: number)
	local base = registry.TowerService.towerBase(player)
	if not base or keep >= #flavorIds then
		return
	end
	local tilt = math.sqrt(tiltX * tiltX + tiltZ * tiltZ)
	if tilt > 1e-3 then
		-- it toppled: it leans as far as it can, whatever the last 10 Hz report said
		tiltX, tiltZ = tiltX / tilt * TowerTuning.tipAngle, tiltZ / tilt * TowerTuning.tipAngle
	end
	nextId += 1
	local paths = Loot.spill(flavorIds, keep, tiltX, tiltZ, nextId, LootConfig, TowerTuning, TowerShape)
	local kept = makeRoom(#paths)

	local time = now()
	local landedAt = time + LootConfig.fallTime
	local ownerUntil = Loot.ownerUntil(landedAt, registry.CombatService.downUntil(player), LootConfig)
	local list = {}
	for index = 1, kept do
		local path = paths[index]
		-- the ground under the landing point and along the roll: it follows steps down, stops at steps up and sinks
		-- at the first point without ground
		local fromY = base.Y + 2
		local samples = Loot.groundSamples(path, LootConfig)
		local heights = {}
		for index, sample in samples do
			heights[index] = groundAt(base.X + sample.x, fromY, base.Z + sample.z)
		end
		local profile = Loot.rollProfile(samples, heights, LootConfig)
		local endAt = time + LootConfig.lifetime
		local sinks = profile.sinkAt ~= nil
		if profile.sinkAt then
			endAt = math.min(endAt, time + profile.sinkAt)
		end
		nextId += 1
		local scoop: Free = {
			id = nextId,
			ownerPlayer = player,
			owner = player.UserId,
			path = path,
			baseX = base.X,
			baseY = base.Y,
			baseZ = base.Z,
			groundY = profile.heights[1] or (base.Y - 3),
			profile = profile,
			t0 = time,
			landedAt = landedAt,
			ownerFrom = Loot.ownerFrom(landedAt, LootConfig),
			ownerUntil = ownerUntil,
			expiresAt = time + LootConfig.lifetime,
			endAt = endAt,
			sinks = sinks,
			landed = false,
		}
		free[scoop.id] = scoop
		table.insert(order, scoop.id)
		table.insert(list, wire(scoop))
	end
	if #list > 0 then
		Remotes.LootSpawned:FireAllClients(list)
	end
end

-- A scoop from the Big Swirl came down at `position` (its landing point) at server time `landedAt` and nobody caught
-- it: it lies there for landedLifetime seconds, anybody may pick it up (Loot.landed). Returns false when there is no
-- ground under it (the water): then it is simply gone.
function LootService.landed(flavorId: string, position: Vector3, landedAt: number): boolean
	local groundY = groundAt(position.X, position.Y + 2, position.Z)
	if not groundY then
		return false
	end
	local landed = ofKind(true)
	for index = 1, Loot.landedRoom(#landed, LootConfig) do
		remove(landed[index], nil, "room")
	end
	local made = Loot.landed(flavorId, landedAt, groundY, LootConfig)
	nextId += 1
	local scoop: Free = {
		id = nextId,
		ownerPlayer = nil,
		owner = made.rule.owner,
		path = made.path,
		baseX = position.X,
		baseY = groundY,
		baseZ = position.Z,
		groundY = groundY,
		profile = made.profile,
		t0 = made.t0,
		landedAt = made.rule.landedAt,
		ownerFrom = made.rule.ownerFrom,
		ownerUntil = made.rule.ownerUntil,
		expiresAt = made.rule.expiresAt,
		endAt = made.endAt,
		sinks = false,
		landed = true,
	}
	free[scoop.id] = scoop
	table.insert(order, scoop.id)
	Remotes.LootSpawned:FireAllClients({ wire(scoop) })
	return true
end

-- The player was knocked down until `downUntil`: their head start on their own spilled scoops only begins after it.
function LootService.ownerDown(player: Player, downUntil: number)
	local ids = {}
	local time = now()
	local ownerUntil = downUntil + LootConfig.ownerSeconds
	for _, scoop in free do
		if scoop.ownerPlayer == player and scoop.ownerUntil > time and scoop.ownerUntil < ownerUntil then
			scoop.ownerUntil = ownerUntil
			table.insert(ids, scoop.id)
		end
	end
	if #ids > 0 then
		Remotes.LootUpdated:FireAllClients(ids, ownerUntil)
	end
end

return LootService
