-- What the local player sees of their own hits (Config/Combat feedback): a red X on the crosshair when their ball hits
-- somebody (AimHud.mark), the number of scoops a victim lost rising over the victim, and a line in the feed at the
-- bottom of the screen: "YOU KNOCKED DOWN Name" when their hit knocks somebody down, "YOU TOPPLED Name (+X)" when a
-- tower falls soon after their hit (the server credits it, CombatService.toppled).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))

local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))

local HitFeedback = {}

local Look = CombatConfig.feedback
local player = Players.LocalPlayer
local registry
local feed: Frame
local lines: { TextLabel } = {}

local function fadeOut(label: TextLabel, after: number)
	task.delay(after, function()
		if not label.Parent then
			return
		end
		local tween = TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		local index = table.find(lines, label)
		if index then
			table.remove(lines, index)
		end
		label:Destroy()
	end)
end

-- One line in the feed; the oldest goes once there are more than feedLines.
local function say(text: string)
	local label = Ui.text({ Text = text, TextSize = 22, LayoutOrder = os.clock() * 1000 // 1 })
	label.TextColor3 = Color3.new(1, 1, 1)
	local rim = Ui.stroke(label, "ink", 2, 0.1)
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	label.Parent = feed
	table.insert(lines, label)
	while #lines > Look.feedLines do
		table.remove(lines, 1):Destroy()
	end
	fadeOut(label, Look.feedTime)
end

-- "-X" over the victim, rising and fading.
local function number(victim: Player, lost: number)
	local head = victim.Character and victim.Character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local sign = Instance.new("BillboardGui")
	sign.Name = "LostScoops"
	sign.Adornee = head
	sign.Size = UDim2.fromOffset(120, 40)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	sign.LightInfluence = 0
	sign.AlwaysOnTop = true -- the thrower must see it even behind the victim's tower
	sign.ResetOnSpawn = false
	local label = Ui.text({ Text = `-{lost}`, TextSize = 30, AnchorPoint = Vector2.new(0.5, 0.5) })
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.TextColor3 = Ui.color("awning")
	local rim = Ui.stroke(label, "ink", 2.5, 0)
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	label.Parent = sign
	sign.Parent = player:WaitForChild("PlayerGui")
	local info = TweenInfo.new(Look.numberTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(sign, info, { StudsOffsetWorldSpace = Vector3.new(0, 2 + Look.numberRise, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	TweenService:Create(rim, info, { Transparency = 1 }):Play()
	task.delay(Look.numberTime, function()
		sign:Destroy()
	end)
end

local function onResolved(_: number, thrower: Player, victim: Player?, ...)
	local shielded, headshot = select(6, ...)
	if thrower == player and victim and not shielded then
		registry.AimHud.mark(headshot == true)
	end
end

local function onFeedback(kind: string, victim: Player, lost: number)
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") then
		return
	end
	if kind == "knockdown" then
		say(`YOU KNOCKED DOWN {victim.DisplayName}`)
	elseif kind == "toppled" and type(lost) == "number" and lost > 0 then
		say(`YOU TOPPLED {victim.DisplayName} (+{lost})`)
		number(victim, lost)
	end
end

function HitFeedback.Init(reg)
	registry = reg
	local gui = Instance.new("ScreenGui")
	gui.Name = "HitFeed"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	-- the middle of the screen near the bottom, above the tower card
	feed = Instance.new("Frame")
	feed.Name = "Feed"
	feed.BackgroundTransparency = 1
	feed.AnchorPoint = Vector2.new(0.5, 1)
	feed.Position = UDim2.new(0.5, 0, 1, -120)
	feed.Size = UDim2.fromOffset(600, 100)
	local list = Ui.list(feed, Enum.FillDirection.Vertical, 2)
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	feed.Parent = gui
	Ui.autoScale(feed)
end

function HitFeedback.Start()
	Remotes.IceBallResolved.OnClientEvent:Connect(onResolved)
	Remotes.HitFeedback.OnClientEvent:Connect(onFeedback)
end

return HitFeedback
