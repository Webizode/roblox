-- Scoops are served (Config/Vfx.effects.serve, Config/Vfx.serve, uiCoins): spinning coins spring up out of the player
-- and rain back down with a little confetti, bigger the more scoops; everybody sees it. For the local player the
-- coins also fly from the character to the HUD's coin counter while it counts up, and the counter pops as they land.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Vfx = require(script.Parent.Parent)
local Screen = require(script.Parent.Parent:WaitForChild("Screen"))
local Ui = require(script.Parent.Parent.Parent:WaitForChild("Ui"))
local VfxRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VfxRules"))

local Serve = {}

local Config = Vfx.Config
local player = Players.LocalPlayer

-- The HUD's coin counter: its coin sits at the left end of the cluster.
local function counterTarget(): (GuiObject?, Vector2?)
	local hud = player:FindFirstChildOfClass("PlayerGui") and player.PlayerGui:FindFirstChild("Hud")
	local cluster = hud and hud:FindFirstChild("CoinsCluster", true)
	if not cluster or not cluster:IsA("GuiObject") or not cluster.Visible then
		return nil, nil
	end
	local size = cluster.AbsoluteSize
	local coin = cluster.AbsolutePosition + Vector2.new(size.Y / 2, size.Y / 2)
	return cluster, Screen.fromAbsolute(coin)
end

-- A quick ring that pops out of the counter's coin.
local function pop(at: Vector2, size: number)
	local ring = Instance.new("Frame")
	ring.Name = "CoinPop"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromOffset(at.X, at.Y)
	ring.Size = UDim2.fromOffset(size, size)
	ring.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex(Config.colors.coinLight)
	stroke.Thickness = math.max(2, size / 10)
	stroke.Parent = ring
	ring.Parent = Screen.gui()
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, { Size = UDim2.fromOffset(size * 2.4, size * 2.4) }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	task.delay(0.35, function()
		ring:Destroy()
	end)
end

-- The coins from the character to the counter, one after the other on a little arc.
local function flyToCounter(from: Vector3, scoops: number)
	local _, target = counterTarget()
	local start, visible = Screen.fromWorld(from)
	if not target or not visible then
		return
	end
	local look = Config.uiCoins
	local size = math.floor(look.size * Screen.height() / 720 + 0.5)
	local count = VfxRules.uiCoins(scoops, Vfx.quality(), Config)
	local rng = Random.new()
	for index = 1, count do
		task.delay((index - 1) * look.gap, function()
			local coin = Ui.coinIcon(size, {
				Name = "FlyingCoin",
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = 2,
			})
			local scatter = Vector2.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 0.3)) * size * 1.5
			local from2 = start + scatter
			coin.Position = UDim2.fromOffset(from2.X, from2.Y)
			coin.Parent = Screen.gui()
			-- along a curve: straight to the counter, bowed upwards by `arc` of the way
			local mid = (from2 + target) / 2 + Vector2.new(0, -(target - from2).Magnitude * look.arc)
			local alpha = Instance.new("NumberValue")
			alpha.Changed:Connect(function(t: number)
				local a = from2:Lerp(mid, t)
				local b = mid:Lerp(target, t)
				local at = a:Lerp(b, t)
				coin.Position = UDim2.fromOffset(at.X, at.Y)
				coin.Size = UDim2.fromOffset(size * (1 - 0.35 * t), size * (1 - 0.35 * t))
			end)
			local tween =
				TweenService:Create(alpha, TweenInfo.new(look.time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Value = 1,
				})
			tween.Completed:Connect(function()
				coin:Destroy()
				alpha:Destroy()
				if index == 1 or index == count then
					pop(target, size)
				end
			end)
			tween:Play()
		end)
	end
end

-- `character` served `scoops` scoops; `own`: the local player.
function Serve.play(character: Model, scoops: number, own: boolean)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	Vfx.burst("serve", Vfx.upAt(feet + Vector3.new(0, Config.serve.lift, 0)), {
		scale = VfxRules.serveScale(scoops, Config),
		own = own,
	})
	if own then
		flyToCounter(root.Position + Vector3.new(0, 1, 0), scoops)
	end
end

return Serve
