-- The teleport buttons at the top of the screen and the "safe zone" note under them: "my plot" and "arena" big, the
-- three shops ("upgrades", "quests", "cosmetics") in a smaller row under them, as wide as the two. All show only
-- outside the arena; the client asks ArenaZone with the character's position, the same function the server uses,
-- and changes what it shows once the answer has held for Config/Map.arena.displayDelay, so nothing flickers on the
-- line. The buttons are always clickable (mouse, touch, gamepad selection) and only name the target; the server decides
-- (TeleportRules: not in the arena, not knocked down, not right after a hit) and says why when a knockdown or a hit
-- stops it (a toast). Features.debugArenaZone draws the zone half transparent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MapConfig = require(Config:WaitForChild("Map"))
local Features = require(Config:WaitForChild("Features"))
local Palette = require(Config:WaitForChild("Palette"))
local ArenaZone = require(Shared:WaitForChild("ArenaZone"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))

local TeleportMenu = {}

-- the shop row: three buttons as wide together as the two big ones (2 x 150 + 12)
local SHOP_GAP = 6
local SHOP_WIDTH = (2 * 150 + 12 - 2 * SHOP_GAP) / 3
local SHOP_HEIGHT = 42
local ICON = 16

-- A rounded bar of the icon, `w` x `h` pixels, centred at (x, y) in the icon, turned `rotation` degrees.
local function bar(parent: Frame, x: number, y: number, w: number, h: number, rotation: number, color: Color3)
	local piece = Instance.new("Frame")
	piece.AnchorPoint = Vector2.new(0.5, 0.5)
	piece.Position = UDim2.fromOffset(x, y)
	piece.Size = UDim2.fromOffset(w, h)
	piece.Rotation = rotation
	piece.BorderSizePixel = 0
	piece.BackgroundColor3 = color
	piece.Parent = parent
	Ui.corner(piece, UDim.new(0.5, 0))
	return piece
end

-- the shops' symbols, built from frames like every icon (Ui): an arrow up, a gem, an exclamation mark
local SHOPS = {
	{
		where = "upgrades",
		text = "UPGRADES",
		color = "mint",
		icon = function(icon: Frame, color: Color3)
			bar(icon, 8, 10.5, 3.5, 10, 0, color)
			bar(icon, 5.4, 5.4, 3.5, 8.5, 45, color)
			bar(icon, 10.6, 5.4, 3.5, 8.5, -45, color)
		end,
	},
	{
		where = "quests",
		text = "QUESTS",
		color = "skyTop",
		icon = function(icon: Frame, color: Color3)
			bar(icon, 8, 6, 4, 10.5, 0, color)
			bar(icon, 8, 14.2, 4, 4, 0, color)
		end,
	},
	{
		where = "cosmetics",
		text = "COSMETICS",
		color = "strawberry",
		icon = function(icon: Frame, color: Color3)
			local gem = bar(icon, 8, 8, 10, 10, 45, color)
			gem:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 2)
			bar(icon, 6.6, 6.6, 3, 3, 45, Ui.color("vanilla")).BackgroundTransparency = 0.3
		end,
	},
}

-- why the server said no (TeleportDenied), as the player reads it
local DENIED = {
	down = "Can't teleport while knocked down",
	hit = "You just got hit! Walk away first",
}

local registry
local player = Players.LocalPlayer
local zone = MapConfig.arena
local panel: Frame
local shown: boolean? = nil -- what the screen shows: true outside the arena
local pending: boolean? = nil -- what the zone says now
local pendingSince = 0

local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local outside = if root then not ArenaZone.contains(root.Position.X, root.Position.Z, zone) else false
	local now = os.clock()
	if outside ~= pending then
		pending, pendingSince = outside, now
	end
	if pending ~= shown and (shown == nil or now - pendingSince >= zone.displayDelay) then
		shown = pending
		panel.Visible = shown == true
	end
end

-- The zone, half transparent: the floor disc and every ramp up to its top edge (Studio testing only).
local function drawZone()
	local folder = Instance.new("Folder")
	folder.Name = "ArenaZoneDebug"
	local function piece(size: Vector3, cframe: CFrame, shape: Enum.PartType)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromHex("#FF5A6E")
		p.Transparency = 0.75
		p.Shape = shape
		p.Size = size
		p.CFrame = cframe
		p.Parent = folder
	end
	local cx, cz, height = zone.center.x, zone.center.z, 24
	piece(
		Vector3.new(height, zone.radius * 2, zone.radius * 2),
		CFrame.new(cx, height / 2, cz) * CFrame.Angles(0, 0, math.rad(90)),
		Enum.PartType.Cylinder
	)
	for index = 1, zone.ramps do
		local sx, sz = ArenaZone.lane(index, zone)
		local direction = Vector3.new(sx, 0, sz)
		-- from well inside the disc to the ramp's top edge
		local from, to = zone.radius - 10, zone.rampTop
		local middle = Vector3.new(cx, height / 2, cz) + direction * ((from + to) / 2)
		piece(
			Vector3.new(zone.rampHalfWidth * 2, height, to - from),
			CFrame.lookAt(middle, middle + direction),
			Enum.PartType.Block
		)
	end
	folder.Parent = workspace
end

-- the coloured stripe on a button's left edge
local function stripe(button: GuiObject, color: string, x: number, inset: number)
	local frame = Instance.new("Frame")
	frame.Name = "Stripe"
	frame.Size = UDim2.new(0, if inset >= 8 then 8 else 6, 1, -2 * inset)
	frame.Position = UDim2.fromOffset(x, inset)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Ui.color(color)
	frame.Parent = button
	Ui.corner(frame, UDim.new(0.5, 0))
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Teleport"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 12)
	panel.Size = UDim2.fromOffset(0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.Parent = gui
	Ui.list(panel, Enum.FillDirection.Vertical, 6)
	Ui.autoScale(panel)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.LayoutOrder = 1
	bar.Size = UDim2.fromOffset(0, 52)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundTransparency = 1
	bar.Parent = panel
	Ui.list(bar, Enum.FillDirection.Horizontal, 12)

	local buttons = {
		{ where = "plot", text = "MY PLOT", color = "mint" },
		{ where = "arena", text = "ARENA", color = "strawberry" },
	}
	for order, entry in buttons do
		local button = Ui.button({
			Name = entry.where,
			Text = entry.text,
			LayoutOrder = order,
			Size = UDim2.fromOffset(150, 52),
			Selectable = true,
			Parent = bar,
		})
		-- a coloured stripe on the left says which one it is at a glance
		stripe(button, entry.color, 10, 8)
		button.Activated:Connect(function()
			Remotes.TeleportRequest:FireServer(entry.where)
		end)
	end

	-- the shops: a smaller row under the two big buttons, exactly as wide, each with its stripe, a symbol and a word under it
	local shops = Instance.new("Frame")
	shops.Name = "Shops"
	shops.LayoutOrder = 2
	shops.Size = UDim2.fromOffset(0, SHOP_HEIGHT)
	shops.AutomaticSize = Enum.AutomaticSize.X
	shops.BackgroundTransparency = 1
	shops.Parent = panel
	Ui.list(shops, Enum.FillDirection.Horizontal, SHOP_GAP)
	for order, entry in SHOPS do
		local button = Ui.button({
			Name = entry.where,
			LayoutOrder = order,
			Size = UDim2.fromOffset(SHOP_WIDTH, SHOP_HEIGHT),
			Selectable = true,
			Parent = shops,
		})
		local corner = button:FindFirstChildOfClass("UICorner") :: UICorner
		corner.CornerRadius = UDim.new(0, 10)
		stripe(button, entry.color, 7, 6)
		local icon = Instance.new("Frame")
		icon.Name = "Icon"
		-- the symbol on top, the word under it over the whole width right of the stripe
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 4, 0, 5)
		icon.Size = UDim2.fromOffset(ICON, ICON)
		icon.BackgroundTransparency = 1
		icon.Parent = button
		entry.icon(icon, Ui.color(entry.color))
		local label = Ui.text({
			Name = "Label",
			Text = entry.text,
			AutomaticSize = Enum.AutomaticSize.None,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 15, 1, -3),
			Size = UDim2.new(1, -19, 0, 16),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = button,
		})
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 16
		limit.MinTextSize = 11
		limit.Parent = label
		button.Activated:Connect(function()
			Remotes.TeleportRequest:FireServer(entry.where)
		end)
	end

	-- the note that nobody can hit you here
	local note = Ui.card({
		Name = "SafeZone",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = panel,
	}, UDim.new(0.5, 0))
	Ui.padding(note, 14, 0)
	Ui.list(note, Enum.FillDirection.Horizontal, 8)
	local dot = Ui.circle(10, "mint", { LayoutOrder = 1 })
	dot.Parent = note
	Ui.text({ Text = "SAFE ZONE", TextSize = 16, TextColor3 = Ui.color("mint"), LayoutOrder = 2, Parent = note })
end

function TeleportMenu.Init(reg)
	registry = reg
end

function TeleportMenu.Start()
	build()
	Remotes.TeleportDenied.OnClientEvent:Connect(function(reason: string)
		local text = DENIED[reason]
		if text then
			registry.Hud.toast(text, Palette.strawberry)
		end
	end)
	if Features.debugArenaZone then
		drawZone()
	end
	RunService.RenderStepped:Connect(update)
end

return TeleportMenu
