-- The upgrade shop's window (Config/Upgrades, the rules in Upgrades; the server decides, UpgradeService):
--   Opening    only at the Upgrade shop in the hub: its prompt "Upgrades" (E, a tap, the gamepad's prompt key). The
--              HUD's UPGRADES button teleports there (Navigation, TeleportRules). Walking farther than
--              Config/Upgrades.closeDistance from the shop closes the window.
--   Window     the Scoop Chest's look (its panel picture, Config/Chest.art.window; the title on a pill until the shop
--              has its own plaque) with HudAway. The own coins on top, below one card per upgrade: icon, name, a short
--              line, the level as pips, the effect now and after the purchase ("28 -> 31 scoops") and the buy button
--              with the price. Too few coins: the button is grey with a padlock; at the top it says MAX.
--   Buying     the button sends the level the card shows (UpgradeBuy); while that answer is on its way the card takes
--              no second click. Bought: the card bumps (Anim.bump), flashes in its colour and the sound upgradeBuy
--              plays. The levels come back as the Upgrade_<id> attributes, the coins as leaderstats.Coins.
--   Layouts    "tall" (PC, tablet, console) and "wide" (phones in landscape), both one column of cards. The wide one is
--              flatter, so the phone's short screen holds it bigger (two columns were too narrow, 25.11.2026). In
--              Studio the attribute UpgradeLayout on Workspace ("wide" or "tall") picks one, to look at the phone's on a PC.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))
local UpgradesConfig = require(Config:WaitForChild("Upgrades"))
local ChestConfig = require(Config:WaitForChild("Chest"))

local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local Sfx = require(client:WaitForChild("Sfx"))

local Theme, Window, Widgets, Buttons, Anim, Toast, Screen =
	UiKit.Theme, UiKit.Window, UiKit.Widgets, UiKit.Buttons, UiKit.Anim, UiKit.Toast, UiKit.Screen

local UpgradeController = {}

local PROMPT_NAME = "UpgradeShopPrompt" -- UpgradeService puts it on the shop's Teleport_Upgrade parts
local CLOSE_CHECK = 0.2 -- seconds between two looks whether the player is still at the shop
local ARROW = "  \u{2192}  " -- between the value now and after the purchase
local PENDING_TIMEOUT = 3 -- seconds a card waits for the server's answer before it takes clicks again
-- pips: at most `pip` design pixels each, all of them within `pipRow` (25 levels: 8 pixels and a gap of 4)
local CARD = { height = 136, gap = 12, icon = 96, button = { w = 196, h = 62 }, pip = 14, pipGap = 4, pipRow = 300 }

type Layout = { width: number, height: number, columns: number }
local LAYOUTS: { [string]: Layout } = {
	tall = { width = 900, height = 760, columns = 1 },
	wide = { width = 1000, height = 560, columns = 1 },
}

type Card = {
	id: string,
	frame: Frame,
	stroke: UIStroke,
	level: TextLabel,
	pips: { Frame },
	effect: TextLabel,
	buy: any, -- Buttons.WideButton
	coin: ImageLabel?, -- the coin on the buy button, hidden at MAX
}

local player = Players.LocalPlayer
local layoutName = "tall"
local window: any = nil
local coinCounter: any = nil
local cards: { [string]: Card } = {}
local pending: { [string]: number } = {} -- id -> when the purchase was sent
local shopPart: BasePart? = nil -- the shop the window was opened at

local function levelOf(id: string): number
	return Upgrades.clampLevel(id, player:GetAttribute("Upgrade_" .. id), UpgradesConfig)
end

-- the player's rebirths for Config/Upgrades.levelCap (the attribute Rebirths once the rebirth exists; 0 until then)
local function rebirths(): number
	local value = player:GetAttribute("Rebirths")
	return if type(value) == "number" then value else 0
end

local function coins(): number
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Coins")
	return if value and value:IsA("IntValue") then value.Value else 0
end

-- 12500 -> "12,500"
local function withCommas(value: number): string
	local text = tostring(math.floor(value))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^,", ""))
end

-- The icon of an upgrade: a Config/Ui.icons name or an asset id; nil when it has none yet.
local function iconOf(id: string): string?
	local name = UpgradesConfig.tracks[id].icon
	if not name then
		return nil
	end
	return if string.find(name, "^rbxasset") then name else Theme.icons[name]
end

-- ============================================================================================== the cards ======

local function paint(card: Card)
	local track = UpgradesConfig.tracks[card.id]
	local level = levelOf(card.id)
	local top = track.maxLevel
	card.level.Text = if level >= top then `LV {level} MAX` else `LV {level}/{top}`
	for index, pip in card.pips do
		pip.BackgroundColor3 = if index <= level then Theme.color(track.color) else Theme.color("panel")
	end
	card.effect.Text = Upgrades.change(card.id, level, UpgradesConfig, ARROW)
	local cost = Upgrades.cost(card.id, level, UpgradesConfig)
	local capped = cost ~= nil and level >= Upgrades.top(card.id, rebirths(), UpgradesConfig)
	if card.coin then
		card.coin.Visible = cost ~= nil and not capped
	end
	if not cost then
		card.buy.setLocked(false)
		card.buy.setColor(Theme.color("yellow"))
		card.buy.setText("MAX")
	elseif capped then
		-- the highest level for now (Config/Upgrades.levelCap): more after the next rebirth
		card.buy.setColor(Theme.color("purple"))
		card.buy.setText("REBIRTH")
		card.buy.setLocked(true)
	else
		card.buy.setColor(Theme.color("mint"))
		card.buy.setText(withCommas(cost))
		card.buy.setLocked(coins() < cost)
	end
end

local function paintAll()
	if coinCounter then
		coinCounter.set(coins(), true)
	end
	for _, card in cards do
		paint(card)
	end
end

local function buy(id: string)
	local level = levelOf(id)
	local cost = Upgrades.cost(id, level, UpgradesConfig)
	if not cost then
		return -- MAX
	end
	if level >= Upgrades.top(id, rebirths(), UpgradesConfig) then
		Toast.show("Rebirth to go higher!", "warn")
		return
	end
	if pending[id] and os.clock() - pending[id] < PENDING_TIMEOUT then
		return -- the answer to the last click is still on its way (a double click)
	end
	if coins() < cost then
		Toast.show("Not enough coins!", "warn", "coin")
		return
	end
	pending[id] = os.clock()
	Remotes.UpgradeBuy:FireServer(id, level)
end

-- The flash of a bought card: its rim lights up in the upgrade's colour and fades back.
local function flash(card: Card)
	local track = UpgradesConfig.tracks[card.id]
	card.stroke.Color = Theme.color(track.color)
	card.stroke.Thickness = 6
	TweenService:Create(
		card.stroke,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Color = Theme.color("rim"), Thickness = 3 }
	):Play()
end

local function iconBox(parent: GuiObject, id: string)
	local track = UpgradesConfig.tracks[id]
	local box = Theme.frame({
		Name = "IconBox",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.darker(Theme.color(track.color), 0.35),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(CARD.icon, CARD.icon),
		ZIndex = 5,
		Parent = parent,
	})
	Theme.corner(box, UDim.new(0, 20))
	Theme.outline(box, 3)
	local image = iconOf(id)
	if image then
		Theme.icon(image, {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.86),
			ZIndex = 6,
			Parent = box,
		})
	else
		-- placeholder until its icon is drawn: the first letter in the upgrade's colour
		Theme.text({
			Name = "Placeholder",
			Text = string.sub(track.label, 1, 1),
			TextColor3 = Theme.color(track.color),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.62, 0.62),
			TextScaled = true,
			ZIndex = 6,
			Parent = box,
		})
	end
end

local function makeCard(id: string, order: number, parent: GuiObject): Card
	local track = UpgradesConfig.tracks[id]
	local frame = Theme.frame({
		Name = "Card_" .. id,
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Theme.color("panel"),
		LayoutOrder = order,
		ZIndex = 4,
		Parent = parent,
	})
	Theme.corner(frame, UDim.new(0, 18))
	local stroke = Theme.outline(frame, 3, Theme.color("rim"))
	iconBox(frame, id)

	local left = 16 + CARD.icon + 16
	local right = CARD.button.w + 28
	local function line(name: string, text: string, y: number, height: number, font: Font, color: Color3?): TextLabel
		local label = Theme.text({
			Name = name,
			Text = text,
			FontFace = font,
			TextColor3 = color or Theme.color("text"),
			Position = UDim2.fromOffset(left, y),
			Size = UDim2.new(1, -left - right, 0, height),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
			Parent = frame,
		})
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = height
		limit.Parent = label
		return label
	end
	line("Name", string.upper(track.label), 10, 32, Theme.fontMain)
	line("Text", track.text, 72, 24, Theme.fontText, Theme.color("hint"))
	local effect = line("Effect", "", 100, 28, Theme.fontNumbers, Theme.color(track.color))

	-- the level: one pip per level, filled in the upgrade's colour, and "LV 3/10" after them
	local pipSize = math.min(CARD.pip, math.floor(CARD.pipRow / track.maxLevel) - CARD.pipGap)
	local pipRow = Theme.frame({
		Name = "Pips",
		Position = UDim2.fromOffset(left, 48),
		Size = UDim2.fromOffset(track.maxLevel * (pipSize + CARD.pipGap), CARD.pip),
		ZIndex = 5,
		Parent = frame,
	})
	local pipList = Instance.new("UIListLayout")
	pipList.FillDirection = Enum.FillDirection.Horizontal
	pipList.VerticalAlignment = Enum.VerticalAlignment.Center
	pipList.Padding = UDim.new(0, CARD.pipGap)
	pipList.SortOrder = Enum.SortOrder.LayoutOrder
	pipList.Parent = pipRow
	local pips = {}
	for index = 1, track.maxLevel do
		local pip = Theme.frame({
			Name = "Pip" .. index,
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(pipSize, pipSize),
			LayoutOrder = index,
			ZIndex = 5,
			Parent = pipRow,
		})
		Theme.corner(pip, UDim.new(0.5, 0))
		Theme.outline(pip, 2)
		pips[index] = pip
	end
	local level = Theme.text({
		Name = "Level",
		Text = "",
		FontFace = Theme.fontNumbers,
		Position = UDim2.fromOffset(left + track.maxLevel * (pipSize + CARD.pipGap) + 8, 44),
		Size = UDim2.fromOffset(110, 22),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = frame,
	})

	local button = Buttons.wide({
		name = "Buy_" .. id,
		text = "",
		color = Theme.color("mint"),
		icon = Theme.icons.coin,
		width = CARD.button.w,
		height = CARD.button.h,
	})
	button.button.AnchorPoint = Vector2.new(1, 0.5)
	button.button.Position = UDim2.new(1, -16, 0.5, 0)
	button.button.ZIndex = 6
	button.button.Parent = frame
	button.label.FontFace = Theme.fontNumbers
	button.button.Activated:Connect(function()
		buy(id)
	end)

	local card: Card = {
		id = id,
		frame = frame,
		stroke = stroke,
		level = level,
		pips = pips,
		effect = effect,
		buy = button,
		coin = nil,
	}
	for _, child in button.button:GetDescendants() do
		if child:IsA("ImageLabel") and child.Image == Theme.icons.coin then
			card.coin = child
		end
	end
	paint(card)
	return card
end

-- ============================================================================================= the window ======

local function buildWindow()
	local L = LAYOUTS[layoutName]
	local look = ChestConfig.art.window
	local made = Window.new({
		name = "UpgradeWindow",
		title = "UPGRADES",
		color = Theme.color("mint"),
		width = L.width,
		height = L.height,
		hudAway = true,
		art = {
			panel = look.panel,
			slice = Rect.new(look.slice[1], look.slice[2], look.slice[3], look.slice[4]),
			sliceScale = look.sliceScale,
			titleY = look.titleY,
			inset = look.inset,
		},
	})
	window = made
	local content = made.content

	-- the own coins over the cards, and what upgrades are for
	coinCounter = Widgets.coins()
	coinCounter.frame.Position = UDim2.fromOffset(4, 2)
	coinCounter.frame.ZIndex = 6
	coinCounter.frame.Parent = content
	local hint = Theme.text({
		Name = "Hint",
		Text = "Upgrades help your shop and your tower.",
		FontFace = Theme.fontText,
		TextColor3 = Theme.color("hint"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 10),
		Size = UDim2.new(0.55, 0, 0, 30),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
		Parent = content,
	})
	local hintLimit = Instance.new("UITextSizeConstraint")
	hintLimit.MaxTextSize = 24
	hintLimit.Parent = hint

	local list = Instance.new("ScrollingFrame")
	list.Name = "Cards"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 60)
	list.Size = UDim2.new(1, 0, 1, -60)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Theme.color("creamDark")
	list.Selectable = false
	list.ZIndex = 4
	list.Parent = content
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 14) -- room for the scroll bar
	padding.Parent = list
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / L.columns, -CARD.gap * (L.columns - 1) / L.columns, 0, CARD.height)
	grid.CellPadding = UDim2.fromOffset(CARD.gap, CARD.gap)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list

	table.clear(cards)
	local first: GuiObject? = nil
	for order, id in Upgrades.visible(UpgradesConfig) do
		local card = makeCard(id, order, list)
		cards[id] = card
		first = first or card.buy.button
	end
	made.firstSelection = first
	made.onClosed(function()
		if Screen.input() == "gamepad" then
			GuiService.SelectedObject = nil
		end
	end)
	paintAll()
end

local function onResult(id: any, ok: any, result: any, _cost: any)
	if type(id) ~= "string" then
		return
	end
	pending[id] = nil
	local card = cards[id]
	if ok == true then
		Sfx.play("upgradeBuy")
		local track = UpgradesConfig.tracks[id]
		if card then
			-- the level attribute may arrive just after this answer: paint again on the next frame too
			paint(card)
			task.defer(paint, card)
			Anim.bump(card.frame)
			Anim.bump(card.level)
			flash(card)
		end
		if track then
			Toast.show(`{string.upper(track.label)} LEVEL {result}!`, "good")
		end
	elseif result == "coins" then
		Toast.show("Not enough coins!", "warn", "coin")
	elseif result == "max" then
		Toast.show("Already at the top level!", "warn")
	elseif result == "loading" then
		Toast.show("Your save is still loading...", "warn")
	elseif result == "cap" then
		Toast.show("Rebirth to go higher!", "warn")
	elseif result == "far" then
		Toast.show("Get closer to the shop!", "warn")
	end
	-- "stale" (a double click, or the window was a step behind): nothing to say, the cards show the real level
	paintAll()
end

-- Opens the window at `shop` (the shop's part whose prompt was triggered); it stays open while the player is near it.
function UpgradeController.open(shop: BasePart)
	shopPart = shop
	if window and not window.isOpen() then
		paintAll()
		window.open()
	end
end

-- Farther than Config/Upgrades.closeDistance from the shop (walked or teleported away, or no character): the window
-- closes. On the ground plane, like the server's check.
local function checkDistance()
	if not window or not window.isOpen() then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local shop = shopPart
	if not root or not shop or not shop.Parent then
		window.close()
		return
	end
	local offset = root.Position - shop.Position
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > UpgradesConfig.closeDistance then
		window.close()
	end
end

function UpgradeController.isOpen(): boolean
	return window ~= nil and window.isOpen()
end

function UpgradeController.Start()
	local function layoutFor(plan: any): string
		local forced = if RunService:IsStudio() then workspace:GetAttribute("UpgradeLayout") else nil
		if forced == "wide" or forced == "tall" then
			return forced
		end
		return if plan and plan.device == "phone" then "wide" else "tall"
	end
	layoutName = layoutFor(Screen.plan())
	buildWindow()
	local function relayout()
		local wanted = layoutFor(Screen.plan())
		if wanted == layoutName or not window then
			return
		end
		layoutName = wanted
		local wasOpen = window.isOpen()
		window.close()
		window.gui:Destroy()
		buildWindow()
		if wasOpen then
			window.open()
		end
	end
	Screen.onChanged(relayout)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("UpgradeLayout"):Connect(relayout)
	end

	Remotes.UpgradeResult.OnClientEvent:Connect(onResult)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local shop = prompt:FindFirstAncestorWhichIsA("BasePart")
		if prompt.Name == PROMPT_NAME and shop then
			UpgradeController.open(shop)
		end
	end)
	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceCheck += dt
		if sinceCheck >= CLOSE_CHECK then
			sinceCheck = 0
			checkDistance()
		end
	end)

	-- levels and coins change: the cards follow (only painted, nothing is rebuilt)
	for id in UpgradesConfig.tracks do
		player:GetAttributeChangedSignal("Upgrade_" .. id):Connect(function()
			local card = cards[id]
			if card then
				paint(card)
			end
		end)
	end
	task.spawn(function()
		local stats = player:WaitForChild("leaderstats")
		local value = stats:WaitForChild("Coins") :: IntValue
		value.Changed:Connect(function()
			if window and window.isOpen() then
				paintAll()
			end
		end)
	end)
end

return UpgradeController
