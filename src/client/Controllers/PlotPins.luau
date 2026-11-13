-- The pins over the other players' plots (Config/Ui.plotPins), so every base on the map shows whose it is: over each
-- plot that has an owner (their PlotName attribute, set by PlotService) floats the owner's head shot in a round bubble
-- with a tip in their player colour, and their name under it. Like the own YOU pin (PlotGuide) the pins are drawn in a
-- ScreenGui at the plot's projected point, so they keep their size on screen at any distance and show through
-- everything (a BillboardGui with AlwaysOnTop was not drawn at all in the Studio playtest); fainter and smaller in
-- combat mode, fading out near the plot (the name stands on the plot sign there), gone behind the camera. Free plots
-- and the own plot (it has the YOU pin) get none. A serve at a plot makes a coin glint at its pin. Head shots are
-- loaded once per player and kept. In Studio the workspace attribute PlotPinsPreview shows a pin over every plot but
-- the own one, all with the local player as the owner, for screenshots without a second player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GuideRules = require(Shared:WaitForChild("GuideRules"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UiConfig = require(Shared:WaitForChild("Config"):WaitForChild("Ui"))
local MapConfig = require(Shared:WaitForChild("Config"):WaitForChild("Map"))

local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local Theme, Screen = UiKit.Theme, UiKit.Screen

local PlotPins = {}

local Look = UiConfig.plotPins
local player = Players.LocalPlayer

type Pin = {
	owner: Player,
	group: CanvasGroup,
	scale: UIScale,
	head: ImageLabel,
	name: TextLabel,
	tip: Frame,
	outline: UIStroke,
	transparency: number, -- eased towards GuideRules.pinLook
	size: number,
}

local gui: ScreenGui
local pins: { [string]: Pin } = {} -- by plot name
local headShots: { [number]: string } = {} -- user id -> loaded head shot
local loading: { [number]: boolean } = {}

-- The owner's head shot, loaded once (in the background; the bubble shows the house until it is there).
local function headShot(owner: Player, image: ImageLabel)
	local id = owner.UserId
	local cached = headShots[id]
	if cached then
		image.Image = cached
		return
	end
	if loading[id] or id <= 0 then
		return -- Studio's test players have no thumbnail
	end
	loading[id] = true
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(id, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		loading[id] = nil
		if ok and type(content) == "string" then
			headShots[id] = content
			for _, pin in pins do
				if pin.owner == owner then
					pin.head.Image = content
				end
			end
		end
	end)
end

local function colorOf(owner: Player): Color3
	local hex = owner:GetAttribute("PlayerColor")
	return if type(hex) == "string" then Color3.fromHex(hex) else Theme.color("cream")
end

local function build(owner: Player): Pin
	local size = Look.pin
	local group = Instance.new("CanvasGroup")
	group.Name = "Pin_" .. owner.Name
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 1) -- its bottom middle sits on the projected point
	group.Size = UDim2.fromOffset(size * 4, size * 1.7 + Look.nameSize + 6)
	group.GroupTransparency = 1
	group.Visible = false
	group.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = group

	-- the tip under the bubble, in the owner's colour
	local tip = Theme.frame({
		Name = "Tip",
		BackgroundTransparency = 0,
		BackgroundColor3 = colorOf(owner),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, size * 1.02),
		Size = UDim2.fromOffset(size * 0.5, size * 0.5),
		Rotation = 45,
		ZIndex = 1,
		Parent = group,
	})
	Theme.corner(tip, UDim.new(0.18, 0))
	Theme.outline(tip, 2)
	-- the bubble: the house until the head shot is there, a ring in the owner's colour round it
	local bubble = Theme.frame({
		Name = "Bubble",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("cream"),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 2,
		Parent = group,
	})
	Theme.corner(bubble, UDim.new(0.5, 0))
	local outline = Theme.outline(bubble, 3, colorOf(owner))
	-- the head shot sits in a round mask inside the ring with a margin, so nothing of it sticks out of the circle (a
	-- CanvasGroup with round corners clips what is in it; a UICorner on the image alone let the hair stick out at the
	-- top, kill test 13.11.2026)
	local mask = Instance.new("CanvasGroup")
	mask.Name = "Mask"
	mask.AnchorPoint = Vector2.new(0.5, 0.5)
	mask.Position = UDim2.fromScale(0.5, 0.5)
	mask.Size = UDim2.fromScale(Look.headMask, Look.headMask)
	mask.BackgroundColor3 = Theme.color("cream")
	mask.BorderSizePixel = 0
	mask.ZIndex = 3
	mask.Parent = bubble
	Theme.corner(mask, UDim.new(0.5, 0))
	local head = Instance.new("ImageLabel")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.Image = Theme.icons.plot -- the house until the head shot is there
	head.ScaleType = Enum.ScaleType.Fit
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	-- a little smaller than the mask and a little low, so the top of the head keeps room under the ring
	head.Position = UDim2.fromScale(0.5, 0.5 + Look.headDrop)
	head.Size = UDim2.fromScale(Look.headScale, Look.headScale)
	head.ZIndex = 3
	head.Parent = mask
	local name = Theme.text({
		Name = "Name",
		Text = owner.DisplayName,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, size * 1.32),
		Size = UDim2.new(1, 0, 0, Look.nameSize),
		TextScaled = true,
		ZIndex = 4,
		Parent = group,
	})
	local pin: Pin = {
		owner = owner,
		group = group,
		scale = scale,
		head = head,
		name = name,
		tip = tip,
		outline = outline,
		transparency = 1,
		size = 1,
	}
	headShot(owner, head)
	return pin
end

local function drop(key: string)
	local pin = pins[key]
	if pin then
		pin.group:Destroy()
		pins[key] = nil
	end
end

local function plotsFolder(): Instance?
	local pier = workspace:FindFirstChild(MapConfig.pier)
	return pier and pier:FindFirstChild("Plots")
end

local function servePointIn(plot: Instance?): BasePart?
	local servePoint = plot and plot:FindFirstChild("ServePoint")
	return if servePoint and servePoint:IsA("BasePart") then servePoint else nil
end

-- The pins wanted now: plot name -> its owner and serve point. Every other player's plot; in Studio with the
-- workspace attribute PlotPinsPreview every plot but the own one, all with the local player as the owner (for looking
-- at them and for screenshots without a second player).
local function wanted(): { [string]: { owner: Player, servePoint: BasePart } }
	local plots = plotsFolder()
	local out = {}
	if not plots then
		return out
	end
	local ownPlot = player:GetAttribute("PlotName")
	if RunService:IsStudio() and workspace:GetAttribute("PlotPinsPreview") == true then
		for _, plot in plots:GetChildren() do
			local servePoint = servePointIn(plot)
			if servePoint and plot.Name ~= ownPlot then
				out[plot.Name] = { owner = player, servePoint = servePoint }
			end
		end
		return out
	end
	local count = 0
	for _, owner in Players:GetPlayers() do
		local plotName = owner:GetAttribute("PlotName")
		local servePoint = owner ~= player
			and type(plotName) == "string"
			and servePointIn(plots:FindFirstChild(plotName))
		if servePoint and count < Look.maxPins then
			count += 1
			out[plotName :: string] = { owner = owner, servePoint = servePoint }
		end
	end
	return out
end

-- A coin pops out of the pin and floats up, with a little sparkle: somebody served there.
local function glint(owner: Player)
	local plotName = owner:GetAttribute("PlotName")
	local pin = type(plotName) == "string" and pins[plotName]
	if not pin or not pin.group.Visible then
		return
	end
	local size = Look.pin * 0.7
	local coin = Theme.icon(Theme.icons.coin, {
		Name = "Glint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, Look.pin * 0.55, 0, Look.pin * 0.2),
		Size = UDim2.fromOffset(size * 0.4, size * 0.4),
		ZIndex = 6,
		Parent = pin.group,
	})
	local sparkle = Theme.icon(Theme.icons.sparkle, {
		Name = "Sparkle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, Look.pin * 0.55, 0, Look.pin * 0.2),
		Size = UDim2.fromOffset(size, size),
		ImageTransparency = 0.1,
		ZIndex = 5,
		Parent = pin.group,
	})
	local pop = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(coin, pop, { Size = UDim2.fromOffset(size, size) }):Play()
	local rise = TweenInfo.new(Look.glint, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(coin, rise, {
		Position = UDim2.new(0.5, Look.pin * 0.55, 0, -Look.pin * 0.3),
		ImageTransparency = 1,
	}):Play()
	TweenService:Create(sparkle, rise, { Size = UDim2.fromOffset(size * 1.8, size * 1.8), ImageTransparency = 1 })
		:Play()
	task.delay(Look.glint + 0.05, function()
		coin:Destroy()
		sparkle:Destroy()
	end)
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local combat = player:GetAttribute("CombatMode") == true
	local want = wanted()
	for key, pin in pins do
		local entry = want[key]
		if not entry or entry.owner ~= pin.owner then
			drop(key)
		end
	end
	for key, entry in want do
		local pin = pins[key]
		if not pin then
			pin = build(entry.owner)
			pins[key] = pin
		end
		local servePoint = entry.servePoint
		local point = camera and camera:WorldToViewportPoint(servePoint.Position + Vector3.new(0, Look.pinHeight, 0))
		if not root or not point or point.Z <= 0 then
			pin.group.Visible = false
			continue
		end
		pin.group.Position = UDim2.fromOffset(point.X, point.Y)
		local distance = (root.Position - servePoint.Position).Magnitude
		local wantTransparency, wantScale = GuideRules.pinLook(distance, false, combat, Look)
		local ease = math.clamp(dt * 6, 0, 1)
		pin.transparency += (wantTransparency - pin.transparency) * ease
		pin.size += (wantScale - pin.size) * ease
		pin.group.GroupTransparency = pin.transparency
		pin.group.Visible = pin.transparency < 0.99
		pin.scale.Scale = pin.size * Screen.plan().scale
		-- the owner's colour can come in after the pin was built
		local color = colorOf(entry.owner)
		pin.tip.BackgroundColor3 = color
		pin.outline.Color = color
	end
end

function PlotPins.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "PlotPins"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- drawn at viewport points
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 1 -- under the HUD and the own pin
	gui.Parent = player:WaitForChild("PlayerGui")
	Remotes.Served.OnClientEvent:Connect(function(who: Player)
		if typeof(who) == "Instance" and who:IsA("Player") and who ~= player then
			glint(who)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return PlotPins
