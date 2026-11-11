-- Who is in the arena (ArenaZone with Config/Map.arena: the floor and the ramps up to their top edge) and the teleport
-- buttons outside it.
--
-- The server asks ArenaZone with the character's position whenever it needs to know (inArena), so its answer is never
-- late, and mirrors it as the player attribute InArena every frame. Only players in the arena are hit by ice balls
-- (CombatService) and get scoops aimed at them (LauncherService). Outside it the client shows the teleport buttons
-- (TeleportMenu, which asks ArenaZone itself): "my plot", "arena" and the three shops. The client only names the
-- target; TeleportRules decides, the same for all five: a living character outside the arena, not knocked down and
-- not hit for Config/Map.teleportHitLock seconds. Requests closer together than teleportMinInterval are dropped
-- against floods. A refusal for a knockdown or a recent hit is told to the client (TeleportDenied), the others are
-- silent (the buttons do not show in the arena). The target is streamed in first.
--
-- The shops' targets are invisible parts under Ice Cream Map.Dekoracje.Hub (Config/Map.teleportTargets), found once at
-- the start; with several of one name the nearest is taken. Players land on the first free spot round it
-- (teleportSlots), looking at the counter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MapConfig = require(Config:WaitForChild("Map"))
local ArenaZone = require(Shared:WaitForChild("ArenaZone"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TeleportRules = require(Shared:WaitForChild("TeleportRules"))

local ArenaService = {}

local registry
local lastRequest: { [Player]: number } = {}
-- request name ("upgrades", ...) -> its target parts in the map
local shopTargets: { [string]: { BasePart } } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Whether the player is in the arena right now (false without a character). `slack` widens the zone (studs), for
-- decisions that must not trip over the position arriving a little late (combat mode, Config/Map.arena.serverSlack).
function ArenaService.inArena(player: Player, slack: number?): boolean
	local root = rootOf(player)
	return root ~= nil and ArenaZone.contains(root.Position.X, root.Position.Z, MapConfig.arena, slack)
end

local function publish()
	for _, player in Players:GetPlayers() do
		if rootOf(player) then
			local inside = ArenaService.inArena(player)
			if player:GetAttribute("InArena") ~= inside then
				player:SetAttribute("InArena", inside)
			end
		end
	end
end

-- Where a shop button brings the player: the nearest target part of that shop, on its first free spot, and the point
-- the player looks at (the counter, ahead of the part).
local function shopSpot(player: Player, where: string, from: Vector3): (Vector3?, Vector3?)
	local parts = shopTargets[where]
	if not parts or #parts == 0 then
		return nil, nil
	end
	local points = {}
	for index, target in parts do
		points[index] = { target.Position.X, target.Position.Z }
	end
	local target = parts[TeleportRules.nearest(points, from.X, from.Z) or 1]
	local frame = target.CFrame
	local spots = {}
	for index, slot in MapConfig.teleportSlots do
		-- right, and back: away from the counter (the part's front is -Z)
		local world = frame:PointToWorldSpace(Vector3.new(slot[1], 0, slot[2]))
		spots[index] = { world.X, world.Z }
	end
	local others = {}
	for _, other in Players:GetPlayers() do
		local root = if other ~= player then rootOf(other) else nil
		if root then
			table.insert(others, { root.Position.X, root.Position.Z })
		end
	end
	local chosen = spots[TeleportRules.spot(spots, others, MapConfig.teleportSlotGap)]
	local spot = Vector3.new(chosen[1], target.Position.Y, chosen[2])
	return spot, spot + frame.LookVector * 10
end

local function onTeleport(player: Player, where: any)
	local time = os.clock()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local refusal = TeleportRules.refusal({
		where = where,
		alive = character ~= nil and humanoid ~= nil and humanoid.Health > 0,
		inArena = ArenaService.inArena(player), -- no buttons in the arena: getting out alive is the game
		down = registry.CombatService.isDown(player),
		sinceHit = registry.CombatService.sinceHit(player),
		sinceRequest = time - (lastRequest[player] or -math.huge),
	}, MapConfig)
	if refusal ~= "unknown" and refusal ~= "flood" then
		lastRequest[player] = time
	end
	if refusal then
		if refusal == "down" or refusal == "hit" then
			Remotes.TeleportDenied:FireClient(player, refusal)
		end
		return
	end
	local root = rootOf(player)
	if not character or not humanoid or not root then
		return
	end
	local target: Vector3?, facing: Vector3? = nil, nil
	if where == "plot" then
		target = registry.PlotService.spawnSpot(player)
	elseif where == "arena" then
		target = registry.PlotService.arenaEntry(player)
	else
		target, facing = shopSpot(player, where, root.Position)
	end
	if not target then
		return
	end
	-- the target may not be streamed in on the client yet
	pcall(function()
		player:RequestStreamAroundAsync(target)
	end)
	if player.Character == character and humanoid.Health > 0 then
		registry.PlotService.placeCharacter(character, target, facing)
	end
end

-- The shops' target parts, by request name; a warning for each one the map lacks (its button then does nothing).
local function findShopTargets()
	local map = registry.MapService.map
	local deco = map and map:FindFirstChild("Dekoracje")
	local hub = deco and deco:FindFirstChild("Hub")
	for where, name in MapConfig.teleportTargets do
		local parts = {}
		if hub then
			for _, descendant in hub:GetDescendants() do
				if descendant.Name == name and descendant:IsA("BasePart") then
					table.insert(parts, descendant)
				end
			end
		end
		shopTargets[where] = parts
		if #parts == 0 then
			warn(`[Arena] no teleport target Dekoracje.Hub.{name} in the map: the "{where}" button does nothing`)
		end
	end
end

function ArenaService.Init(reg)
	registry = reg
	local center = reg.MapService.center
	local zone = MapConfig.arena.center
	if math.abs(center.X - zone.x) > 1 or math.abs(center.Z - zone.z) > 1 then
		warn(
			string.format(
				"[Arena] the Big Swirl's marker is at (%.1f, %.1f) but Config/Map.arena.center is (%.1f, %.1f): the arena zone is off",
				center.X,
				center.Z,
				zone.x,
				zone.z
			)
		)
	end
	findShopTargets()
end

function ArenaService.Start()
	Remotes.TeleportRequest.OnServerEvent:Connect(onTeleport)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
	RunService.Heartbeat:Connect(publish)
end

return ArenaService
