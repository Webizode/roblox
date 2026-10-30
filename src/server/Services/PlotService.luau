-- Gives every player their own plot (Workspace.Pier.Plots), spawns them on it (its Spawn, the middle of the plot
-- island), sets the jump power (Config/Economy.jumpPower; jumping is on since the dash came in) and brings back players
-- who end up in the sea: they respawn at their plot, like after any other respawn with an empty cone. ArenaService
-- uses the same spots for the teleport buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local EconomyConfig = require(Config:WaitForChild("Economy"))
local MapConfig = require(Config:WaitForChild("Map"))
local Palette = require(Config:WaitForChild("Palette"))
local MapRules = require(Shared:WaitForChild("MapRules"))

local PlotService = {}

local SPAWN_DISTANCE = EconomyConfig.serveRadius + 4
-- the spawn ray starts this far above the ServePoint and reaches this far down
local SPAWN_RAY_UP = 6
local SPAWN_RAY_REACH = 30

local map
local owners: { [Instance]: Player } = {}
local assigned: { [Player]: Model } = {}
local respawning: { [Player]: boolean } = {}

-- Where a new character of the player appears: the plot's Spawn (the middle of the island), or on a map without one
-- serveRadius + 4 in front of the ServePoint, outside the serve radius, so the first catches are not served away as
-- one-scoop towers the moment they land.
function PlotService.spawnSpot(player: Player): Vector3?
	local plot = assigned[player]
	local spawn = plot and plot:FindFirstChild("Spawn")
	if spawn and spawn:IsA("BasePart") then
		return spawn.Position
	end
	local servePoint = plot and plot:FindFirstChild("ServePoint") :: BasePart?
	if not servePoint then
		return nil
	end
	local inward = Vector3.new(map.center.X - servePoint.Position.X, 0, map.center.Z - servePoint.Position.Z)
	inward = if inward.Magnitude > 1e-3 then inward.Unit else Vector3.zero
	return servePoint.Position + inward * SPAWN_DISTANCE
end

-- The player's way into the arena: the plot's ArenaEntry on the strip above its ramp, nil on a map without one.
function PlotService.arenaEntry(player: Player): Vector3?
	local plot = assigned[player]
	local entry = plot and plot:FindFirstChild("ArenaEntry")
	return if entry and entry:IsA("BasePart") then entry.Position else nil
end

-- Puts a character on the ground at (and under) `spot`, standing still and looking towards the Big Swirl.
function PlotService.placeCharacter(character: Model, spot: Vector3)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	-- on the ground there, whatever its height; the spot's own height when the ray finds nothing
	local ground = map.groundAt(spot.X, spot.Y + SPAWN_RAY_UP, spot.Z, SPAWN_RAY_REACH)
	local feet = ground.y or spot.Y
	local at = Vector3.new(spot.X, feet + humanoid.HipHeight + root.Size.Y / 2 + 0.2, spot.Z)
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.lookAt(at, Vector3.new(map.center.X, at.Y, map.center.Z)))
end

-- The name over a taken plot; a free plot shows nothing (text nil).
local function setLabel(plot: Model, text: string?)
	local body = plot:FindFirstChild("Body")
	local label = body and body:FindFirstChild("Label")
	local textLabel = label and label:FindFirstChildOfClass("TextLabel")
	if label and label:IsA("BillboardGui") then
		label.Enabled = text ~= nil
	end
	if textLabel then
		textLabel.Text = text or ""
	end
end

local function assign(player: Player)
	local chosen
	for _, plot in map.plots do
		if not owners[plot] then
			chosen = plot
			break
		end
	end
	if not chosen then
		-- more players than plots: share one rather than leaving someone unable to serve
		chosen = map.plots[(#Players:GetPlayers() - 1) % #map.plots + 1]
	else
		owners[chosen] = player
		setLabel(chosen, player.DisplayName)
	end
	assigned[player] = chosen
	player:SetAttribute("PlotName", chosen.Name)
	-- the player's colour follows the plot, so two players never share one unless they share a plot
	local index = table.find(map.plots, chosen) or 1
	player:SetAttribute("PlayerColor", Palette.playerColors[(index - 1) % #Palette.playerColors + 1])
end

local function release(player: Player)
	local plot = assigned[player]
	assigned[player] = nil
	respawning[player] = nil
	if plot and owners[plot] == player then
		owners[plot] = nil
		setLabel(plot, nil)
	end
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.UseJumpPower = true
	humanoid.JumpPower = EconomyConfig.jumpPower

	local spot = PlotService.spawnSpot(player)
	if spot then
		character:WaitForChild("HumanoidRootPart")
		-- wait a frame: the default spawn positions the character after CharacterAdded fires
		task.wait()
		PlotService.placeCharacter(character, spot)
	end
	respawning[player] = nil
end

-- Players in the sea (fallen or knocked off the island) respawn at their plot.
local function checkSea()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			root
			and humanoid
			and humanoid.Health > 0
			and not respawning[player]
			and MapRules.inSea(root.Position.Y, MapConfig)
		then
			respawning[player] = true
			task.spawn(function()
				player:LoadCharacter()
			end)
		end
	end
end

function PlotService.Init(registry)
	map = registry.MapService
end

function PlotService.Start()
	for _, plot in map.plots do
		setLabel(plot, nil) -- every plot starts free
	end
	local function onPlayer(player: Player)
		assign(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(release)

	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceCheck += dt
		if sinceCheck >= MapConfig.waterCheckInterval then
			sinceCheck = 0
			checkSea()
		end
	end)
end

function PlotService.servePoint(player: Player): Vector3?
	local plot = assigned[player]
	local servePoint = plot and plot:FindFirstChild("ServePoint")
	return servePoint and servePoint.Position
end

return PlotService
