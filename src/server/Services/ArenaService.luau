-- Who is in the arena (ArenaZone with Config/Map.arena: the floor and the ramps up to their top edge) and the teleport
-- buttons outside it.
--
-- The server asks ArenaZone with the character's position whenever it needs to know (inArena), so its answer is never
-- late, and mirrors it as the player attribute InArena every frame. Only players in the arena are hit by ice balls
-- (CombatService) and get scoops aimed at them (LauncherService). Outside it the client shows two buttons, "my plot"
-- and "arena" (TeleportMenu, which asks ArenaZone itself); a TeleportRequest is granted for a living character outside
-- the arena, as often as the player likes. Only requests closer together than Config/Map.teleportMinInterval are
-- dropped, against floods. The target is streamed in first.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MapConfig = require(Config:WaitForChild("Map"))
local ArenaZone = require(Shared:WaitForChild("ArenaZone"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ArenaService = {}

local registry
local lastRequest: { [Player]: number } = {}

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

local function onTeleport(player: Player, where: any)
	if where ~= "plot" and where ~= "arena" then
		return
	end
	local time = os.clock()
	if time - (lastRequest[player] or -math.huge) < MapConfig.teleportMinInterval then
		return
	end
	lastRequest[player] = time
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or ArenaService.inArena(player) then
		return -- no buttons in the arena: getting out alive is the game
	end
	local target = if where == "plot"
		then registry.PlotService.spawnSpot(player)
		else registry.PlotService.arenaEntry(player)
	if not target then
		return
	end
	-- the target may not be streamed in on the client yet
	pcall(function()
		player:RequestStreamAroundAsync(target)
	end)
	if player.Character == character and humanoid.Health > 0 then
		registry.PlotService.placeCharacter(character, target)
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
end

function ArenaService.Start()
	Remotes.TeleportRequest.OnServerEvent:Connect(onTeleport)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
	RunService.Heartbeat:Connect(publish)
end

return ArenaService
