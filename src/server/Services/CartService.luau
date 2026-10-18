-- Gives every player their own cart, spawns them there and turns off jumping (the touch jump button sits
-- exactly where the balance pad goes).

local Players = game:GetService("Players")

local CartService = {}

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
	humanoid.JumpPower = 0

	local cart = assigned[player]
	local servePoint = cart and cart:FindFirstChild("ServePoint")
	if servePoint then
		character:WaitForChild("HumanoidRootPart")
		-- wait a frame: the default spawn positions the character after CharacterAdded fires
		task.wait()
		local lookAt = Vector3.new(graybox.center.X, servePoint.Position.Y, graybox.center.Z)
		character:PivotTo(CFrame.lookAt(servePoint.Position + Vector3.new(0, 1, 0), lookAt + Vector3.new(0, 1, 0)))
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
