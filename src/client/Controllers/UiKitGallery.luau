-- The UI kit's test page (Studio only): every building block on one scrolling page, to check the look on every
-- device. It shows with Features.uiGallery, or while the attribute UiGallery on Workspace is true (switchable while
-- playing, e.g. from the command bar on the client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Features = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Features"))
local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local Theme, Screen, Buttons, Window, Widgets, Anim =
	UiKit.Theme, UiKit.Screen, UiKit.Buttons, UiKit.Window, UiKit.Widgets, UiKit.Anim

local UiKitGallery = {}

local WIDTH = 900

local gui: ScreenGui?

local function section(parent: Instance, order: number, title: string, height: number): Frame
	local holder = Theme.frame({
		Name = title,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height + 34),
		Parent = parent,
	})
	local heading = Instance.new("TextLabel")
	heading.BackgroundTransparency = 1
	heading.FontFace = Theme.fontText
	heading.TextSize = 22
	heading.TextColor3 = Theme.color("textDark")
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = title
	heading.Size = UDim2.new(1, 0, 0, 26)
	heading.Parent = holder
	local row = Theme.frame({
		Name = "Row",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, height),
		Parent = holder,
	})
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 16)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Wraps = true
	list.Parent = row
	return row
end

local function build(): ScreenGui
	local screen = Screen.gui("UiKitGallery", 40)
	local panel = Theme.frame({
		Name = "Gallery",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("cream"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WIDTH, 640),
		Parent = screen,
	})
	Theme.corner(panel, UDim.new(0, 22))
	Theme.outline(panel, 4)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	Screen.onChanged(function(plan)
		scale.Scale = math.min(plan.frame.w / (WIDTH + 20), plan.frame.h / 660)
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(20, 16)
	scroll.Size = UDim2.new(1, -40, 1, -32)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Theme.color("outline")
	scroll.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 14)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.Parent = scroll

	-- icon buttons, with key badges
	local icons = section(scroll, 1, "Icon buttons", 90)
	local entries = {
		{ "upgrades", "UPGRADES", "mint" },
		{ "cosmetics", "COSMETICS", "pink" },
		{ "quests", "QUESTS", "sky" },
		{ "index", "INDEX", "purple" },
		{ "scoops", "SCOOPS", "yellow" },
	}
	for order, entry in entries do
		local button = Buttons.icon({
			name = entry[1],
			icon = Theme.icons[entry[1]],
			text = entry[2],
			color = Theme.color(entry[3]),
			action = entry[1],
		})
		button.button.LayoutOrder = order
		button.button.Parent = icons
	end
	local gear = Buttons.icon({
		name = "settings",
		icon = Theme.icons.settings,
		color = Theme.color("silver"),
		size = Theme.config.settingsButton,
		action = "settings",
	})
	gear.button.LayoutOrder = 10
	gear.button.Parent = icons

	-- wide buttons: normal, pressed, locked; the close button
	local wides = section(scroll, 2, "Wide buttons: normal, pressed, locked", 70)
	local plot = Buttons.wide({
		name = "plot",
		text = "MY PLOT",
		color = Theme.color("mint"),
		icon = Theme.icons.plot,
		action = "plot",
	})
	plot.button.LayoutOrder = 1
	plot.button.Parent = wides
	local pressed = Buttons.wide({
		name = "arena",
		text = "ARENA",
		color = Theme.color("red"),
		icon = Theme.icons.arena,
		action = "arena",
	})
	pressed.button.LayoutOrder = 2
	pressed.button.Parent = wides
	Anim.scaleOf(pressed.button).Scale = 0.92
	local locked = Buttons.wide({ name = "locked", text = "LOCKED", color = Theme.color("sky") })
	locked.setLocked(true)
	locked.button.LayoutOrder = 3
	locked.button.Parent = wides
	local close = Buttons.close()
	close.LayoutOrder = 4
	close.Parent = wides

	-- tabs
	local tabRow = section(scroll, 3, "Tabs", 50)
	local tabHolder = Theme.frame({ Size = UDim2.fromOffset(520, 50), Parent = tabRow })
	Window.tabs(tabHolder, { "Audio", "Graphics", "Camera", "Controls" }, Theme.color("sky"), function() end)

	-- item cards: the six rarities, then silhouettes
	local cards = section(scroll, 4, "Item cards: six rarities", 160)
	for order, rarity in Theme.rarities do
		local card = Widgets.itemCard({ rarity = rarity, name = "Vanilla", image = Theme.icons.scoop })
		card.LayoutOrder = order
		card.Parent = cards
	end
	local unknown = section(scroll, 5, "Not discovered yet", 160)
	for order, rarity in { "common", "rare", "legendary" } do
		local card = Widgets.itemCard({ rarity = rarity, name = "Secret", image = Theme.icons.scoops, unknown = true })
		card.LayoutOrder = order
		card.Parent = unknown
	end

	-- coins, progress, the safe sign
	local displays = section(scroll, 6, "Coins, progress, safe zone", 110)
	local coins = Widgets.coins()
	coins.set(7450)
	coins.frame.LayoutOrder = 1
	coins.frame.Parent = displays
	for order, share in { 0.25, 0.7, 1 } do
		local bar = Widgets.progress(180, 30, Theme.color(if share >= 1 then "mint" else "yellow"))
		bar.set(share, string.format("%d/10", math.floor(share * 10)))
		bar.frame.LayoutOrder = 1 + order
		bar.frame.Parent = displays
	end
	local sign = Widgets.safeSign(Theme.config.safeSign.width, Theme.config.safeSign.height)
	sign.LayoutOrder = 9
	sign.Parent = displays

	-- what opens: a window, a popup, a reward message
	local opens = section(scroll, 7, "Window, popup, reward, short messages (press them)", 144)
	local window = Window.message({
		name = "GalleryWindow",
		title = "INDEX",
		color = Theme.color("purple"),
		icon = Theme.icons.index,
		text = "COMING SOON!",
		subtext = "Discover every flavor here.",
	})
	local popup = Window.popup({
		name = "GalleryPopup",
		title = "SERVE?",
		text = "Serve your tower for 120 coins?",
		color = Theme.color("mint"),
		buttons = {
			{ text = "YES", color = Theme.color("mint") },
			{ text = "NO", color = Theme.color("red") },
		},
	})
	local actions = {
		{ "WINDOW", "purple", window.open },
		{ "POPUP", "mint", popup.open },
		{
			"REWARD",
			"yellow",
			function()
				Widgets.reward(screen, { icon = Theme.icons.coin, text = "+250", y = 80 })
			end,
		},
	}
	-- the four kinds of short message (UiKit.Toast)
	for _, entry in
		{
			{ "TOAST", "sky", "SAFE!", "normal", "safe" },
			{ "WARN", "yellow", "CONE FULL!", "warn", "scoops" },
			{ "BAD", "red", "TOPPLED!", "bad", "scoopEmpty" },
			{ "GOOD", "mint", "SERVE! +120", "good", "coin" },
		}
	do
		table.insert(actions, {
			entry[1],
			entry[2],
			function()
				UiKit.Toast.show(entry[3], entry[4], entry[5])
			end,
		})
	end
	for order, entry in actions do
		local button = Buttons.wide({ name = entry[1], text = entry[1], color = Theme.color(entry[2]), width = 170 })
		button.button.LayoutOrder = order
		button.button.Parent = opens
		button.button.Activated:Connect(entry[3])
	end
	return screen
end

local function refresh()
	local wanted = Features.uiGallery == true or workspace:GetAttribute("UiGallery") == true
	if wanted and not gui then
		gui = build()
	end
	if gui then
		gui.Enabled = wanted
	end
end

function UiKitGallery.Start()
	if not RunService:IsStudio() then
		return
	end
	workspace:GetAttributeChangedSignal("UiGallery"):Connect(refresh)
	refresh()
end

return UiKitGallery
