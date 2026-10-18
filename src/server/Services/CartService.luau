-- Gives every player their own cart, spawns them there and turns off jumping (the touch jump button sits
-- exactly where the balance pad goes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Economy"))

local CartService = {}

local SPAWN_DISTANCE = EconomyConfig.serveRadius + 4

local graybox
local owners: { [Instance]: Player } = {}
local assigned: { [Player]: Model } = {}

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
	for _, cart in graybox.carts do
		if not owners[cart] then
			chosen = cart
			break
		end
	end
	if not chosen then
		-- more players than carts: share one rather than leaving someone unable to serve
		chosen = graybox.carts[(#Players:GetPlayers() - 1) % #graybox.carts + 1]
	else
		owners[chosen] = player
		setLabel(chosen, player.DisplayName)
	end
	assigned[player] = chosen
	player:SetAttribute("CartName", chosen.Name)
end

local function release(player: Player)
	local cart = assigned[player]
	assigned[player] = nil
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
	local servePoint = cart and cart:FindFirstChild("ServePoint")
	if servePoint then
		character:WaitForChild("HumanoidRootPart")
		-- wait a frame: the default spawn positions the character after CharacterAdded fires
		task.wait()
		-- spawn a few studs in front of the cart, outside the serve radius, so the first (tutorial) catches are
		-- not served away as one-scoop towers the moment they land
		local lookAt = Vector3.new(graybox.center.X, servePoint.Position.Y, graybox.center.Z)
		local inward = lookAt - servePoint.Position
		inward = if inward.Magnitude > 1e-3 then inward.Unit else Vector3.zero
		local spawnAt = servePoint.Position + inward * SPAWN_DISTANCE + Vector3.new(0, 1, 0)
		character:PivotTo(CFrame.lookAt(spawnAt, lookAt + Vector3.new(0, 1, 0)))
	end
end

function CartService.Init(registry)
	graybox = registry.GrayboxService
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
end

function CartService.servePoint(player: Player): Vector3?
	local cart = assigned[player]
	local servePoint = cart and cart:FindFirstChild("ServePoint")
	return servePoint and servePoint.Position
end

return CartService
