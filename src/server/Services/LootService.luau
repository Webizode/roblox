-- Spilled scoops (design rules 1, 2 and 4). The server owns every free scoop: where it falls and rolls, whether it
-- sinks, who may pick it up and when it disappears. Clients only draw them (LootRenderer) and claim the ones their
-- player walks over; a claim is checked like a catch (Loot.inReach with the catch tolerances) and lands on the
-- claimant's tower through TowerService.addScoop.

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
	groundY: number, -- the ground under the landing point
	t0: number, -- server time of the topple
	landedAt: number,
	ownerUntil: number,
	expiresAt: number,
	endAt: number, -- expiresAt, or earlier when it rolls into the water
	sinks: boolean,
}

-- how far below the tower base the server looks for ground under a scoop
local GROUND_REACH = 40

local registry
local free: { [number]: Free } = {}
local order: { number } = {} -- ids, oldest first
local nextId = 0
local claimBudget: { [Player]: { since: number, count: number } } = {}
local lastRejectLog: { [Player]: number } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isWater(result: RaycastResult): boolean
	return result.Material == Enum.Material.Water
		or result.Instance.Name == "Water"
		or result.Instance.Material == Enum.Material.Water
end

-- The ground height under (x, z) looking down from `fromY`, or nil over water or nothing.
local function groundAt(x: number, fromY: number, z: number): number?
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = characters
	local result = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -GROUND_REACH, 0), rayParams)
	if not result or isWater(result) then
		return nil
	end
	return result.Position.Y
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
		start = Vector3.new(path.sx, path.sy, path.sz),
		land = Vector3.new(path.lx, 0, path.lz),
		roll = Vector3.new(path.rx, 0, path.rz),
		t0 = scoop.t0,
		ownerUntil = scoop.ownerUntil,
		endAt = scoop.endAt,
		sinks = scoop.sinks,
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

	local x, _, z = Loot.position(scoop.path, time - scoop.t0, LootConfig)
	local position = root.Position
	local velocity = root.AssemblyLinearVelocity
	local speed = CatchRules.cappedSpeed(velocity.X, velocity.Z, humanoid.WalkSpeed)
	if
		not Loot.inReach(
			position.X - (scoop.baseX + x),
			position.Y - scoop.groundY - humanoid.HipHeight - root.Size.Y / 2,
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
	registry.KillTestLog.pickup(player, scoop.owner)
	remove(id, player, "caught")
end

-- Drops the oldest free scoops until everything fits and the newest are never lost.
local function makeRoom(incoming: number): number
	local excess, kept = Loot.makeRoom(#order, incoming, LootConfig)
	for _ = 1, excess do
		remove(order[1], nil, "room")
	end
	return kept
end

local function expire()
	local time = now()
	for index = #order, 1, -1 do
		local scoop = free[order[index]]
		if scoop and time >= scoop.endAt then
			remove(scoop.id, nil, if scoop.sinks then "water" else "gone")
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
		-- the ground under the landing point, and the first point along the roll without ground: there it sinks
		local fromY = base.Y + 2
		local groundY = groundAt(base.X + path.lx, fromY, base.Z + path.lz)
		local endAt = time + LootConfig.lifetime
		local sinks = false
		for _, sample in Loot.groundSamples(path, LootConfig) do
			if not groundAt(base.X + sample.x, fromY, base.Z + sample.z) then
				endAt, sinks = math.min(endAt, time + sample.t), true
				break
			end
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
			groundY = groundY or (base.Y - 3),
			t0 = time,
			landedAt = landedAt,
			ownerUntil = ownerUntil,
			expiresAt = time + LootConfig.lifetime,
			endAt = endAt,
			sinks = sinks,
		}
		free[scoop.id] = scoop
		table.insert(order, scoop.id)
		table.insert(list, wire(scoop))
	end
	if #list > 0 then
		Remotes.LootSpawned:FireAllClients(list)
	end
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
