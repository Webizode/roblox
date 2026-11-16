-- "Wanted" for stolen scoops (Config/Wanted, rules in Wanted). The server alone decides: LootService marks a player
-- who picked up somebody else's spilled scoop (Big Swirl scoops never count), every further one starts the time over.
-- While wanted the player may not teleport (ArenaService, TeleportRules "wanted"), not serve (TowerService) and not
-- leave the arena: their own client pushes them back softly short of the ramps' top edge (the Wanted controller), and
-- this service puts the character back inside when the position it sees is clearly past the line anyway. It ends
-- when the time runs out, when the player loses scoops to a knockdown or a topple (TowerService), on respawn and on
-- leaving.
--
-- Everybody sees it through the player attribute WantedUntil (server time; 0 = not wanted): the badge over the head,
-- the glow at the tower, the own countdown. WantedNotice tells the wanted player why something was refused.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Wanted = require(Shared:WaitForChild("Wanted"))
local WantedConfig = require(Config:WaitForChild("Wanted"))
local MapConfig = require(Config:WaitForChild("Map"))

local WantedService = {}

local ATTRIBUTE = "WantedUntil"

local untilAt: { [Player]: number } = {}
local lastNotice: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function set(player: Player, value: number?)
	untilAt[player] = value
	player:SetAttribute(ATTRIBUTE, value or 0)
end

-- Whether the player is wanted right now.
function WantedService.isWanted(player: Player): boolean
	local value = untilAt[player]
	return value ~= nil and now() < value
end

-- The player just picked up a stolen scoop: wanted for the full time from now on.
function WantedService.stole(player: Player)
	local again = WantedService.isWanted(player)
	set(player, Wanted.untilAfterSteal(now(), WantedConfig))
	print(
		string.format(
			"[Wanted] %s %s %.0f s",
			player.Name,
			if again then "stole more:" else "is wanted for",
			WantedConfig.duration
		)
	)
end

-- Ends it early (the stolen scoops are gone again). `why` only goes to the output.
function WantedService.clear(player: Player, why: string)
	if untilAt[player] == nil then
		return
	end
	set(player, nil)
	print(`[Wanted] {player.Name} is no longer wanted: {why}`)
end

-- Tells the wanted player why something was refused ("edge", "serve", "teleport"), at most every hintEvery seconds
-- for the same player.
function WantedService.notice(player: Player, what: string)
	local clock = os.clock()
	if clock - (lastNotice[player] or -math.huge) < WantedConfig.hintEvery then
		return
	end
	lastNotice[player] = clock
	Remotes.WantedNotice:FireClient(player, what)
end

local function step()
	local time = now()
	for player, value in untilAt do
		if time >= value then
			set(player, nil)
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then
			continue
		end
		local position = root.Position
		local x, z = Wanted.pullBackTo(
			position.X,
			position.Z,
			MapConfig.arena,
			WantedConfig,
			WantedConfig.serverSlack,
			WantedConfig.pullBack,
			WantedConfig.maxPull
		)
		if x and z then
			-- inwards a ramp only goes down, so the same height never ends up under the ground
			local back = Vector3.new(x, position.Y, z)
			character:PivotTo(CFrame.new(back) * root.CFrame.Rotation)
			root.AssemblyLinearVelocity = Vector3.zero
			WantedService.notice(player, "edge")
		end
	end
end

function WantedService.Start()
	local function onPlayer(player: Player)
		player:SetAttribute(ATTRIBUTE, 0)
		player.CharacterAdded:Connect(function()
			WantedService.clear(player, "respawn") -- a new character starts with an empty cone
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		untilAt[player] = nil
		lastNotice[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return WantedService
