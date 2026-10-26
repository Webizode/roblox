-- Gives every player their own cart (a stand on Kornel's map), spawns them in front of it on the ground, turns off
-- jumping (the touch jump button sits exactly where the balance pad goes) and brings back players who end up in the
-- sea: they respawn at their stand, like after any other respawn with an empty cone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local EconomyConfig = require(Config:WaitForChild("Economy"))
local MapConfig = require(Config:WaitForChild("Map"))
local Palette = require(Config:WaitForChild("Palette"))
local MapRules = require(Shared:WaitForChild("MapRules"))

local CartService = {}

local SPAWN_DISTANCE = EconomyConfig.serveRadius + 4
-- the spawn ray starts this far above the ServePoint and reaches this far down
local SPAWN_RAY_UP = 6
local SPAWN_RAY_REACH = 30

local map
local owners: { [Instance]: Player } = {}
local assigned: { [Player]: Model } = {}
local respawning: { [Player]: boolean } = {}

local function setLabel(cart: Model, text: string)
	local body = cart:FindFirstChild("Body")
	local label = body and body:FindFirstChild("Label")
	local textLabel = label and label:FindFirstChildOfClass("TextLabel")
	if textLabel then
		textLabel.Text = text
	end
end

local function assign(player: Player)
	local chosen
	for _, cart in map.carts do
		if not owners[cart] then
			chosen = cart
			break
		end
	end
	if not chosen then
		-- more players than carts: share one rather than leaving someone unable to serve
		chosen = map.carts[(#Players:GetPlayers() - 1) % #map.carts + 1]
	else
		owners[chosen] = player
		setLabel(chosen, player.DisplayName)
	end
	assigned[player] = chosen
	player:SetAttribute("CartName", chosen.Name)
	-- the player's colour follows the cart, so two players never share one unless they share a cart
	local index = table.find(map.carts, chosen) or 1
	player:SetAttribute("PlayerColor", Palette.playerColors[(index - 1) % #Palette.playerColors + 1])
end

local function release(player: Player)
	local cart = assigned[player]
	assigned[player] = nil
	respawning[player] = nil
	if cart and owners[cart] == player then
		owners[cart] = nil
		setLabel(cart, "FREE CART")
	end
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.UseJumpPower = true
	humanoid.JumpPower = EconomyConfig.jumpPower

	local cart = assigned[player]
	local servePoint = cart and cart:FindFirstChild("ServePoint") :: BasePart?
	if servePoint then
		local root = character:WaitForChild("HumanoidRootPart") :: BasePart
		-- wait a frame: the default spawn positions the character after CharacterAdded fires
		task.wait()
		-- spawn a few studs in front of the cart, outside the serve radius, so the first (tutorial) catches are
		-- not served away as one-scoop towers the moment they land
		local lookAt = Vector3.new(map.center.X, servePoint.Position.Y, map.center.Z)
		local inward = lookAt - servePoint.Position
		inward = if inward.Magnitude > 1e-3 then inward.Unit else Vector3.zero
		local spot = servePoint.Position + inward * SPAWN_DISTANCE
		-- on the ground there, whatever its height; the ServePoint's own height when the ray finds nothing
		local ground = map.groundAt(spot.X, spot.Y + SPAWN_RAY_UP, spot.Z, SPAWN_RAY_REACH)
		local feet = ground.y or (servePoint.Position.Y - 3)
		local spawnAt = Vector3.new(spot.X, feet + humanoid.HipHeight + root.Size.Y / 2 + 0.2, spot.Z)
		character:PivotTo(CFrame.lookAt(spawnAt, Vector3.new(lookAt.X, spawnAt.Y, lookAt.Z)))
	end
	respawning[player] = nil
end

-- Players in the sea (fallen or knocked off the island) respawn at their stand.
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

function CartService.Init(registry)
	map = registry.MapService
end

function CartService.Start()
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

function CartService.servePoint(player: Player): Vector3?
	local cart = assigned[player]
	local servePoint = cart and cart:FindFirstChild("ServePoint")
	return servePoint and servePoint.Position
end

return CartService
