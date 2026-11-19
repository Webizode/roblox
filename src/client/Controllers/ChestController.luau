-- The Scoop Chest on this client (the server decides everything, ChestService; this only shows it):
--   Lids       every plot's chest follows the attribute ChestOpen on its plot (Workspace.Pier.Plots.Plot_NN): the lid
--              turns about its Hinge (soft both ways, Config/Chest.lid), stars rise out of it, a light glows inside and a
--              glint rises now and then while it stands open (Vfx/Effects/Chest). Everybody sees every chest.
--   Prompt     at the own chest while it is open: "Open" (E, DPadRight, a tap) opens the window.
--   Messages   ChestChanged events: rare scoops stored, the chest full, sold, refused; LuckyCatch.
--   Window     the UI kit's window: the three equip slots and the active bonuses on top, the stored scoops as item
--              cards in their rarity's colour below (rarest first), a tap on one opens its details with Equip and
--              Sell (with a confirmation). Empty, it says how rare scoops get in.

local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ChestConfig = require(Config:WaitForChild("Chest"))
local Controls = require(Config:WaitForChild("Controls"))
local Features = require(Config:WaitForChild("Features"))
local Flavors = require(Config:WaitForChild("Flavors"))

local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local Sfx = require(client:WaitForChild("Sfx"))
local ChestVfx = require(client:WaitForChild("Vfx"):WaitForChild("Effects"):WaitForChild("Chest"))
local LuckyVfx = require(client:WaitForChild("Vfx"):WaitForChild("Effects"):WaitForChild("Lucky"))
local LuckyPopup = require(client:WaitForChild("LuckyPopup"))

local Theme, Window, Widgets, Buttons, Anim, Toast, Screen =
	UiKit.Theme, UiKit.Window, UiKit.Widgets, UiKit.Buttons, UiKit.Anim, UiKit.Toast, UiKit.Screen

local ChestController = {}

local player = Players.LocalPlayer
local registry
local LID = ChestConfig.lid
local CARD_W, CARD_H = 144, 161 -- a stored scoop's card (the card pictures are about 458 x 512)
local SLOT_SCALE = 0.8 -- the equipped cards, of a full card
local DETAIL = { pad = 18, cardScale = 1.6 } -- the details: margin, the big card
local ART = ChestConfig.art
-- the bonus rows on the boost panel (210 high): their middle between the title (down to 66) and the inner rim (190),
-- row height and gap, the columns (icon, gap, "Coins +1.5%", "(max 25%)") and the text size
local BOOSTS = { middle = 130, rowHeight = 32, rowGap = 6, icon = 38, gap = 10, value = 140, cap = 118, textSize = 26 }

-- Two arrangements of the same parts (rectangles in design pixels of the window's content). "tall" follows the
-- reference (PC, tablet, console). "wide" is for phones in landscape: there the tall window is held small by the
-- screen's height; the wide one puts slots and bonuses on the left and the grid on the right and comes out about a
-- fifth bigger. The details keep their order and only move up in the wide one, with buttons and question under the
-- right column.
type Rect = { pos: UDim2, size: UDim2 }
type Layout = {
	width: number,
	height: number,
	equippedLabel: UDim2,
	slots: Rect,
	bonuses: Rect,
	storedLabel: UDim2,
	grid: Rect,
	detail: {
		name: number,
		rarity: number,
		count: number,
		passive: number,
		passiveHeight: number,
		hint: number,
		buttons: number,
		confirm: number,
		underRight: boolean, -- buttons and question under the right column (else across the whole width)
	},
}
local LAYOUTS: { [string]: Layout } = {
	tall = {
		width = 880,
		height = 740,
		equippedLabel = UDim2.fromOffset(6, 0),
		slots = { pos = UDim2.fromOffset(0, 24), size = UDim2.fromOffset(400, 186) },
		bonuses = { pos = UDim2.fromOffset(418, 6), size = UDim2.new(1, -418, 0, 210) },
		storedLabel = UDim2.fromOffset(6, 224),
		grid = { pos = UDim2.fromOffset(0, 266), size = UDim2.new(1, 0, 1, -266) },
		detail = {
			name = 14,
			rarity = 78,
			count = 146,
			passive = 200,
			passiveHeight = 100,
			hint = 318,
			buttons = 360,
			confirm = 432,
			underRight = false,
		},
	},
	wide = {
		width = 1180,
		height = 538, -- content 440: the left column (slots and bonuses) exactly, two rows of cards on the right
		equippedLabel = UDim2.fromOffset(6, 0),
		slots = { pos = UDim2.fromOffset(0, 24), size = UDim2.fromOffset(400, 186) },
		bonuses = { pos = UDim2.fromOffset(0, 230), size = UDim2.fromOffset(400, 210) },
		storedLabel = UDim2.fromOffset(424, 0),
		grid = { pos = UDim2.fromOffset(418, 24), size = UDim2.new(1, -418, 1, -24) },
		detail = {
			name = 8,
			rarity = 66,
			count = 130,
			passive = 180,
			passiveHeight = 92,
			hint = 284,
			buttons = 318,
			confirm = 388,
			underRight = true,
		},
	},
}
local layoutName = "tall"
local L: Layout = LAYOUTS.tall

type Entry = {
	plot: Instance,
	chest: Model?,
	lid: Model?,
	closed: CFrame?, -- the lid's pivot (its Hinge) shut, taken when the chest streamed in
	angle: NumberValue,
	tween: Tween?,
	light: PointLight?,
	prompt: ProximityPrompt?,
	open: boolean,
	nextGlint: number,
}

local entries: { [Instance]: Entry } = {}
local latest: { [string]: any }? = nil -- the newest snapshot from the server

-- the window and its parts
local window: any = nil -- UiKit Window
local slotsRow: Frame
local bonusRows: { [string]: { value: TextLabel, cap: TextLabel } } = {}
local fillLabel: TextLabel
local grid: ScrollingFrame
local emptyLabel: TextLabel
local detail: Frame
local detailKey: string? = nil
local confirming = false

-- ===================================================================================================== the lids ===

local function setAngle(entry: Entry, degrees: number)
	local lid, closed = entry.lid, entry.closed
	if lid and closed and lid.Parent then
		lid:PivotTo(closed * CFrame.Angles(math.rad(degrees), 0, 0))
	end
end

local function isOwn(entry: Entry): boolean
	return player:GetAttribute("PlotName") == entry.plot.Name
end

local function chestOf(plot: Instance): Model?
	local area = plot:FindFirstChild("Area")
	local island = area and area:IsA("ObjectValue") and area.Value
	local kit = island and island:FindFirstChild("PlotKit")
	local chest = kit and kit:FindFirstChild("ScoopChest")
	return if chest and chest:IsA("Model") then chest else nil
end

local function openWindow()
	if not window then
		return
	end
	Remotes.ChestAction:FireServer("sync")
	window.open()
end

-- The prompt at the own chest, made once per chest instance; only enabled while it stands open.
local function ensurePrompt(entry: Entry, part: BasePart)
	if entry.prompt and entry.prompt.Parent == part then
		return
	end
	local binding = Controls.chest
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChestPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Scoop Chest"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = ChestConfig.promptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = (Enum.KeyCode :: any)[binding.keys and binding.keys[1] or "E"]
	prompt.GamepadKeyCode = (Enum.KeyCode :: any)[binding.pad and binding.pad[1] or "DPadRight"]
	prompt.Enabled = entry.open
	prompt.Triggered:Connect(openWindow)
	prompt.Parent = part
	entry.prompt = prompt
end

-- Finds the chest of an entry again when it streamed in (or out); a new instance starts shut and then jumps to the
-- entry's state without effects.
local function resolve(entry: Entry)
	local chest = chestOf(entry.plot)
	local lid = chest and chest:FindFirstChild("Lid")
	if not chest or not lid or not lid:IsA("Model") then
		entry.chest, entry.lid, entry.closed, entry.light, entry.prompt = nil, nil, nil, nil, nil
		return
	end
	local part = chest:FindFirstChild("Collision")
	-- the plot can become ours after the chest was found (PlotName comes a moment after joining)
	if part and part:IsA("BasePart") and isOwn(entry) then
		ensurePrompt(entry, part)
	end
	if entry.lid == lid then
		return
	end
	entry.chest, entry.lid = chest, lid
	entry.closed = lid:GetPivot()
	if part and part:IsA("BasePart") then
		entry.light = ChestVfx.light(part, chest)
		entry.light.Brightness = if entry.open then ChestConfig.glow.brightness else 0
	end
	entry.angle.Value = if entry.open then LID.angle else 0
	setAngle(entry, entry.angle.Value)
end

local function setOpen(entry: Entry, open: boolean)
	if entry.open == open then
		return
	end
	entry.open = open
	resolve(entry)
	if entry.tween then
		entry.tween:Cancel()
	end
	local tween = TweenService:Create(entry.angle, ChestVfx.lidTween(open), { Value = if open then LID.angle else 0 })
	entry.tween = tween
	tween:Play()

	local own = isOwn(entry)
	if entry.prompt then
		entry.prompt.Enabled = open
	end
	if entry.light then
		ChestVfx.glow(entry.light, open)
	end
	local chest = entry.chest
	local part = chest and chest:FindFirstChild("Collision")
	if open and chest then
		ChestVfx.open(chest, own)
		entry.nextGlint = os.clock() + ChestConfig.glintEvery
	end
	if part then
		Sfx.at(if open then "chestOpen" else "chestClose", part, ChestConfig.soundHearing)
	end
	if not open and own and window and window.isOpen() then
		window.close() -- walked away from the chest
	end
end

local function watchPlot(plot: Instance)
	if entries[plot] then
		return
	end
	local angle = Instance.new("NumberValue")
	local entry: Entry = {
		plot = plot,
		angle = angle,
		open = false,
		nextGlint = 0,
	}
	entries[plot] = entry
	angle.Changed:Connect(function(value: number)
		setAngle(entry, value)
	end)
	resolve(entry)
	plot:GetAttributeChangedSignal("ChestOpen"):Connect(function()
		setOpen(entry, plot:GetAttribute("ChestOpen") == true)
	end)
	if plot:GetAttribute("ChestOpen") == true then
		setOpen(entry, true)
	end
end

-- ================================================================================================ the window =====
-- Laid out after the reference "Bunter Scoop-Chest-Spielbildschirm" and drawn from its cut-out pictures
-- (Config/Chest.art, 17.11.2026): the window and its title plaque, the EQUIPPED plaque over the slots' panel, the
-- bonuses on the glazed boost panel under "ACTIVE BOOSTS" with an icon per passive, the item cards per rarity with
-- the green EQUIPPED tag, and the rarity plaques in the details. "STORED n/50" stays drawn (its number changes).

-- A picture of Config/Chest.art; `aspect` keeps its proportions (nil: it fills its size).
local function picture(image: string, props: { [string]: any }, aspect: number?): ImageLabel
	local label = Theme.icon(image, props)
	local ratio = label:FindFirstChildOfClass("UIAspectRatioConstraint")
	if ratio and aspect then
		ratio.AspectRatio = aspect
	elseif ratio then
		ratio:Destroy()
	end
	return label
end

-- The icon of a passive kind: the kit's coin for coins, the chest's own for the others.
local function passiveIcon(kind: string): string?
	if kind == "coins" then
		return Theme.icons.coin
	end
	return ART.passiveIcons[kind]
end

local function rarityLabel(rarity: string): string
	return string.upper(string.sub(rarity, 1, 1)) .. string.sub(rarity, 2)
end

local function mutationSpec(mutation: string): { label: string, color: string }?
	return if mutation ~= "" then ChestConfig.mutations.kinds[mutation] else nil
end

local function percent(amount: number): string
	local value = amount * 100
	return if math.abs(value - math.floor(value + 0.5)) < 0.05
		then `{math.floor(value + 0.5)}%`
		else string.format("%.1f%%", value)
end

local function itemByKey(key: string?): { [string]: any }?
	if not latest or not key then
		return nil
	end
	for _, item in latest.items do
		if item.key == key then
			return item
		end
	end
	return nil
end

-- "+5% Luck: chance for a rarer scoop when catching", the bonus in its kind's colour (RichText)
local function passiveRich(item: { [string]: any }): string
	local kind = ChestConfig.passives.kinds[item.passive]
	if not kind then
		return ""
	end
	return `<font color="{kind.color}">+{percent(item.amount)} {kind.label}:</font> {kind.text}`
end

-- An inset panel on the window: darker chocolate inside a caramel rim.
local function panel(props: { [string]: any }): Frame
	local frame = Theme.frame(props)
	frame.BackgroundTransparency = 0.15
	frame.BackgroundColor3 = Theme.color("panel")
	Theme.corner(frame, UDim.new(0, 18))
	Theme.outline(frame, 3, Theme.color("rim"))
	return frame
end

-- A waffle label over a panel ("EQUIPPED", "STORED 4/50"); returns its word.
local function waffleLabel(parent: GuiObject, name: string, position: UDim2, width: number, height: number): TextLabel
	local tag = Theme.frame({
		Name = name,
		BackgroundTransparency = 0,
		Position = position,
		Size = UDim2.fromOffset(width, height),
		ZIndex = 6,
		Parent = parent,
	})
	Theme.shade(tag, Theme.color("waffleLabel"))
	Theme.corner(tag, UDim.new(0, 10))
	Theme.outline(tag, 3)
	Theme.waffle(tag, 7, UDim.new(0, 10))
	return Theme.text({
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -18, 0.74, 0),
		TextScaled = true,
		ZIndex = 8,
		Parent = tag,
	})
end

-- The kit's two little stars, as decoration.
local function sparkle(parent: GuiObject, position: UDim2, size: number, zIndex: number): ImageLabel
	return Theme.icon(Theme.icons.sparkle, {
		Name = "Sparkle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		ZIndex = zIndex,
		Parent = parent,
	})
end

-- A pill whose width follows its word (rarity, count).
local function pill(
	parent: GuiObject,
	name: string,
	text: string,
	color: Color3,
	position: UDim2,
	height: number,
	font: Font?
)
	-- Its width comes from the number of letters, the word is scaled into it: no fixed text size, so the word never
	-- runs out of the pill whatever size a device draws text at (phone test 17.11.2026).
	local width = math.max(height * 2.4, #text * height * 0.42 + height * 1.1)
	local frame = Theme.frame({
		Name = name,
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		Position = position,
		Size = UDim2.fromOffset(width, height),
		ZIndex = 24,
		Parent = parent,
	})
	Theme.corner(frame, UDim.new(0.5, 0))
	local label = Theme.text({
		Name = "Label",
		Text = text,
		FontFace = font or Theme.fontMain,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -height * 0.9, 0.62, 0),
		TextScaled = true,
		ZIndex = 25,
		Parent = frame,
	})
	return frame, label
end

-- A stored scoop's card: the kit's item card in its rarity's colour, the scoop tinted in its flavor's colour, the
-- count, its mutation and whether it is equipped.
local function card(item: { [string]: any }, scale: number?): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Card_" .. item.key
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromOffset(CARD_W * (scale or 1), CARD_H * (scale or 1))
	button.Selectable = true
	button.SelectionImageObject = Theme.selection(UDim.new(0, 16))
	button.ZIndex = 4
	Anim.button(button)

	-- the face in design pixels of a full card, scaled down for the slots
	local face = Theme.frame({ Name = "Face", Size = UDim2.fromOffset(CARD_W, CARD_H), ZIndex = 4, Parent = button })
	if scale and scale ~= 1 then
		local size = Instance.new("UIScale")
		size.Scale = scale
		size.Parent = face
	end
	local tint = Color3.fromHex(item.color):Lerp(Color3.new(1, 1, 1), 0.3)
	local cardImage = ART.cards[item.rarity]
	if cardImage then
		-- the rarity's card picture (its word is in it), the scoop big in the middle, the name on the bar
		picture(cardImage, { Name = "Card", Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = face })
		-- a mutation gilds or colours the card picture (6), under the scoop (7) and the words (8)
		Widgets.mutationOverlay(face, item.mutation, { image = cardImage, zIndex = 6 })
		if ART.cardsWithoutWord[item.rarity] then
			Theme.text({
				Name = "Rarity",
				Text = string.upper(item.rarity),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.1),
				Size = UDim2.new(0.6, 0, 0, 22),
				TextScaled = true,
				ZIndex = 8,
				Parent = face,
			})
		end
		picture(Theme.icons.scoop, {
			Name = "Scoop",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(88, 88),
			ImageColor3 = tint,
			ZIndex = 7,
			Parent = face,
		}, 1)
		Theme.text({
			Name = "Name",
			Text = string.upper(item.name),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.775),
			Size = UDim2.new(0.78, 0, 0, 18),
			TextScaled = true,
			ZIndex = 8,
			Parent = face,
		})
	else
		-- a rarity without its own picture yet: the kit's card
		local kit = Widgets.itemCard({ rarity = item.rarity, name = item.name, image = Theme.icons.scoop })
		kit.Position = UDim2.fromOffset(0, 0)
		kit.ZIndex = 5
		local fit = Instance.new("UIScale")
		fit.Scale = CARD_H / 156
		fit.Parent = kit
		kit.Parent = face
		local framed = kit:FindFirstChild("Picture")
		local image = framed and framed:FindFirstChildOfClass("ImageLabel")
		if image then
			image.ImageColor3 = tint
		end
		Widgets.mutationOverlay(face, item.mutation, { zIndex = 6 })
	end

	if item.count > 1 then
		local count = Theme.text({
			Name = "Count",
			Text = `x{item.count}`,
			FontFace = Theme.fontNumbers,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0.2, 0),
			Size = UDim2.fromOffset(44, 26),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 9,
			Parent = face,
		})
		count.TextColor3 = Theme.color("yellow")
	end
	-- a mutation shows only as the card's look (Widgets.mutationOverlay), no word on the card (17.11.2026)
	if item.equipped then
		picture(ART.equippedTag, {
			Name = "Equipped",
			Position = UDim2.new(0, 8, 0.19, 0),
			Size = UDim2.fromOffset(76, 27),
			ZIndex = 9,
			Parent = face,
		}, 640 / 226)
	end
	return button
end

local function showDetail(key: string?)
	detailKey = key
	confirming = false
	local item = itemByKey(key)
	detail.Visible = item ~= nil
	if not item then
		return
	end
	for _, child in detail:GetChildren() do
		local keep = child.Name == "Back" or child.Name == "DetailWaffle"
		if not keep and not child:IsA("UICorner") and not child:IsA("UIStroke") then
			child:Destroy()
		end
	end

	local big = card(item, DETAIL.cardScale)
	big.Name = "BigCard"
	big.Selectable = false
	big.Position = UDim2.fromOffset(DETAIL.pad, DETAIL.pad)
	big.Parent = detail

	local left = DETAIL.pad + CARD_W * DETAIL.cardScale + 26
	local right = UDim2.new(1, -left - DETAIL.pad, 0, 0)
	local mutation = mutationSpec(item.mutation)
	Theme.text({
		Name = "Name",
		Text = string.upper(if mutation then `{mutation.label} {item.name}` else item.name),
		Position = UDim2.fromOffset(left, L.detail.name),
		Size = right + UDim2.fromOffset(0, 50),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 24,
		Parent = detail,
	})
	-- the rarity's plaque (its word is in the picture), or a drawn pill for a rarity without one
	local badge = ART.badges[item.rarity]
	if badge then
		picture(badge, {
			Name = "Rarity",
			Position = UDim2.fromOffset(left - 6, L.detail.rarity),
			Size = UDim2.fromOffset(math.floor(58 * ART.badgeAspect), 58),
			ZIndex = 24,
			Parent = detail,
		}, ART.badgeAspect)
	else
		local rarityPill = pill(
			detail,
			"Rarity",
			string.upper(item.rarity),
			Theme.rarity(item.rarity),
			UDim2.fromOffset(left, L.detail.rarity + 8),
			40
		)
		Theme.outline(rarityPill, 3)
	end
	local countPill = pill(
		detail,
		"Count",
		`{item.count} in your chest`,
		Theme.color("panel"),
		UDim2.fromOffset(left, L.detail.count),
		36,
		Theme.fontText
	)
	countPill.BackgroundTransparency = 0.2
	Theme.outline(countPill, 3, Theme.color("rim"))

	-- the passive: its icon (coin, clover, stacked cone), the bonus and what it does
	local kind = ChestConfig.passives.kinds[item.passive]
	local icon = passiveIcon(item.passive)
	local box = Theme.frame({
		Name = "Passive",
		BackgroundTransparency = 0.2,
		BackgroundColor3 = Theme.color("panel"),
		Position = UDim2.fromOffset(left, L.detail.passive),
		Size = right + UDim2.fromOffset(0, L.detail.passiveHeight),
		ZIndex = 24,
		Parent = detail,
	})
	Theme.corner(box, UDim.new(0, 18))
	Theme.outline(box, 3, Theme.color("creamDark"))
	if icon then
		picture(icon, {
			Name = "PassiveIcon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 46, 0.5, 0),
			Size = UDim2.fromOffset(64, 64),
			ZIndex = 25,
			Parent = box,
		}, 1)
	elseif kind then
		local dot = Theme.frame({
			Name = "Dot",
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromHex(kind.color),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 46, 0.5, 0),
			Size = UDim2.fromOffset(34, 34),
			ZIndex = 25,
			Parent = box,
		})
		Theme.corner(dot, UDim.new(0.5, 0))
		Theme.outline(dot, 3)
	end
	local passive = Theme.text({
		Name = "Text",
		Text = passiveRich(item),
		RichText = true,
		FontFace = Theme.fontText,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 90, 0.5, 0),
		Size = UDim2.new(1, -104, 0.8, 0),
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 25,
		Parent = box,
	})
	local passiveLimit = Instance.new("UITextSizeConstraint")
	passiveLimit.MaxTextSize = 26
	passiveLimit.Parent = passive
	sparkle(box, UDim2.new(1, -6, 0, 4), 28, 26)
	sparkle(box, UDim2.new(0, 6, 1, -4), 22, 26)

	-- the hint between two thin lines
	local hintRow = Theme.frame({
		Name = "HintRow",
		Position = UDim2.fromOffset(left - 24, L.detail.hint),
		Size = right + UDim2.fromOffset(24, 26),
		ZIndex = 24,
		Parent = detail,
	})
	local hintList = Instance.new("UIListLayout")
	hintList.FillDirection = Enum.FillDirection.Horizontal
	hintList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hintList.VerticalAlignment = Enum.VerticalAlignment.Center
	hintList.Padding = UDim.new(0, 10)
	hintList.SortOrder = Enum.SortOrder.LayoutOrder
	hintList.Parent = hintRow
	for order = 1, 3, 2 do
		local rule = Theme.frame({
			Name = "Line",
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.color("rim"),
			Size = UDim2.fromOffset(10, 2),
			LayoutOrder = order,
			ZIndex = 24,
			Parent = hintRow,
		})
		local flex = Instance.new("UIFlexItem")
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = rule
	end
	local hint = Theme.text({
		Name = "Hint",
		Text = "Equipped scoops add up. Each bonus has a cap.",
		FontFace = Theme.fontText,
		Size = UDim2.new(0.8, 0, 0, 22),
		TextScaled = true,
		LayoutOrder = 2,
		ZIndex = 24,
		Parent = hintRow,
	})
	hint.TextColor3 = Theme.color("hint")
	local hintLimit = Instance.new("UITextSizeConstraint")
	hintLimit.MaxTextSize = 18
	hintLimit.Parent = hint

	local row = Theme.frame({
		Name = "Buttons",
		Position = UDim2.fromOffset(if L.detail.underRight then left else 0, L.detail.buttons),
		Size = if L.detail.underRight then right + UDim2.fromOffset(0, 62) else UDim2.new(1, 0, 0, 62),
		ZIndex = 24,
		Parent = detail,
	})
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 18)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row

	local function wide(name: string, color: Color3, order: number, width: number, icon: string?)
		local button = Buttons.wide({ name = name, text = "", color = color, width = width, height = 58, icon = icon })
		button.button.LayoutOrder = order
		button.button.Parent = row
		return button
	end
	local equipButton = wide("Equip", Theme.color("mint"), 1, 220)
	local sellButton = wide("Sell", Theme.color("yellow"), 2, 250, Theme.icons.coin)
	local question = Theme.text({
		Name = "Confirm",
		Text = "",
		FontFace = Theme.fontText,
		Position = UDim2.fromOffset(if L.detail.underRight then left else 0, L.detail.confirm),
		Size = if L.detail.underRight then right + UDim2.fromOffset(0, 26) else UDim2.new(1, 0, 0, 26),
		TextScaled = true,
		ZIndex = 24,
		Parent = detail,
	})
	question.TextColor3 = Theme.color("yellow")

	local function paint()
		local current = itemByKey(detailKey)
		if not current then
			return
		end
		if confirming then
			equipButton.setLocked(false)
			equipButton.setText("CANCEL")
			equipButton.setColor(Theme.color("sky"))
			sellButton.setText(`YES, +{current.sellValue}`)
			sellButton.setColor(Theme.color("red"))
			question.Text = `Sell 1 {current.name} for {current.sellValue} coins?`
		else
			equipButton.setText(if current.equipped then "UNEQUIP" else "EQUIP")
			equipButton.setColor(Theme.color(if current.equipped then "pink" else "mint"))
			local full = not current.equipped and latest and #latest.equipped >= latest.slots
			equipButton.setLocked(full == true)
			sellButton.setText(`SELL 1 ({current.sellValue})`)
			sellButton.setColor(Theme.color("yellow"))
			question.Text = ""
		end
	end

	equipButton.button.Activated:Connect(function()
		local current = itemByKey(detailKey)
		if not current then
			return
		end
		if confirming then
			confirming = false
			paint()
			return
		end
		if equipButton.locked() then
			Toast.show(`All {latest and latest.slots or 3} slots are taken!`, "warn")
			return
		end
		Remotes.ChestAction:FireServer(if current.equipped then "unequip" else "equip", current.key)
	end)
	sellButton.button.Activated:Connect(function()
		local current = itemByKey(detailKey)
		if not current then
			return
		end
		if not confirming then
			confirming = true
			paint()
			return
		end
		confirming = false
		paint()
		Remotes.ChestAction:FireServer("sell", current.key, 1)
	end)
	paint()
	if Screen.input() == "gamepad" then
		GuiService.SelectedObject = equipButton.button
	end
end

local function render()
	if not window then
		return
	end
	local snapshot = latest
	local items = if snapshot then snapshot.items else {}

	-- the slots: an equipped scoop's small card, or an empty frame
	for _, child in slotsRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local slots = if snapshot then snapshot.slots else ChestConfig.equipSlots
	for slot = 1, slots do
		local key = snapshot and snapshot.equipped[slot]
		local item = itemByKey(key)
		local cell
		if item then
			cell = card(item, SLOT_SCALE)
			cell.Activated:Connect(function()
				showDetail(item.key)
			end)
		else
			-- an empty slot: a dark rounded place with a cream rim and a plus, no rarity (the empty card picture has
			-- "COMMON" drawn in, phone test 17.11.2026)
			cell = Theme.frame({
				Name = "EmptySlot",
				BackgroundTransparency = 0.35,
				BackgroundColor3 = Theme.color("chocolate"),
				Size = UDim2.fromOffset(CARD_W * SLOT_SCALE, CARD_H * SLOT_SCALE),
				ZIndex = 4,
			})
			Theme.corner(cell, UDim.new(0, 18))
			Theme.outline(cell, 3, Theme.color("creamDark")).Transparency = 0.35
			Theme.text({
				Text = "+",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.52),
				Size = UDim2.fromScale(0.4, 0.4),
				TextScaled = true,
				TextTransparency = 0.25,
				ZIndex = 5,
				Parent = cell,
			})
		end
		cell.LayoutOrder = slot
		cell.Parent = slotsRow
	end

	-- the active bonuses
	for _, kind in ChestConfig.passives.order do
		local labels = bonusRows[kind]
		local spec = ChestConfig.passives.kinds[kind]
		local amount = if snapshot then snapshot.bonuses[kind] or 0 else 0
		if labels and spec then
			labels.value.Text = `{spec.label} +{percent(amount)}`
			labels.cap.Text = `(max {percent(spec.cap)})`
			local faint = if amount > 0 then 0 else 0.45
			labels.value.TextTransparency = faint
			labels.cap.TextTransparency = faint
		end
	end

	local used = if snapshot then snapshot.used else 0
	local capacity = if snapshot then snapshot.capacity else ChestConfig.capacity
	fillLabel.Text = `STORED {used}/{capacity}`
	fillLabel.TextColor3 = if used >= capacity then Theme.color("red") else Theme.color("text")

	-- the grid
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local first: GuiObject? = nil
	for order, item in items do
		local cell = card(item)
		cell.LayoutOrder = order
		cell.Parent = grid
		cell.Activated:Connect(function()
			showDetail(item.key)
		end)
		first = first or cell
	end
	emptyLabel.Visible = #items == 0
	window.firstSelection = first

	if detail.Visible then
		if itemByKey(detailKey) then
			showDetail(detailKey)
		else
			showDetail(nil) -- the last one was sold
		end
	end
end

local function buildWindow()
	L = LAYOUTS[layoutName]
	local look = ART.window
	local made = Window.new({
		name = "ChestWindow",
		title = "SCOOP CHEST",
		color = Theme.color("pink"),
		width = L.width,
		height = L.height,
		hudAway = true,
		art = {
			panel = look.panel,
			slice = Rect.new(look.slice[1], look.slice[2], look.slice[3], look.slice[4]),
			sliceScale = look.sliceScale,
			title = look.title,
			titleSize = Vector2.new(look.titleSize[1], look.titleSize[2]),
			titleY = look.titleY,
			inset = look.inset,
		},
	})
	window = made
	local content = made.content

	-- the equip slots: a panel with the EQUIPPED plaque on its top left corner
	local slotsPanel = panel({
		Name = "SlotsPanel",
		Position = L.slots.pos,
		Size = L.slots.size,
		ZIndex = 4,
		Parent = content,
	})
	picture(ART.equippedLabel, {
		Name = "EquippedLabel",
		Position = L.equippedLabel,
		Size = UDim2.fromOffset(176, 47),
		ZIndex = 6,
		Parent = content,
	}, 768 / 203)
	slotsRow = Theme.frame({
		Name = "Slots",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 34),
		Size = UDim2.new(1, -24, 0, CARD_H * SLOT_SCALE),
		ZIndex = 5,
		Parent = slotsPanel,
	})
	local slotList = Instance.new("UIListLayout")
	slotList.FillDirection = Enum.FillDirection.Horizontal
	slotList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotList.Padding = UDim.new(0, 12)
	slotList.SortOrder = Enum.SortOrder.LayoutOrder
	slotList.Parent = slotsRow

	-- the active bonuses: the glazed boost panel, "ACTIVE BOOSTS" on its glaze, a row with an icon per passive
	local bonuses = picture(ART.boostPanel, {
		Name = "Bonuses",
		Position = L.bonuses.pos,
		Size = L.bonuses.size,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 4,
		Parent = content,
	})
	picture(ART.boostTitle, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 34),
		Size = UDim2.fromOffset(250, 65),
		ZIndex = 6,
		Parent = bonuses,
	}, 1024 / 266)
	-- the rows as one block in the middle of the panel: between the title's lower edge and the panel's inner rim, in
	-- three columns of fixed width (icon, "Coins +1.5%", "(max 25%)") so icons, values and caps line up
	local rows = Theme.frame({
		Name = "Rows",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, BOOSTS.middle),
		Size = UDim2.fromOffset(
			BOOSTS.icon + BOOSTS.gap + BOOSTS.value + BOOSTS.cap,
			BOOSTS.rowHeight * 3 + BOOSTS.rowGap * 2
		),
		ZIndex = 5,
		Parent = bonuses,
	})
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Vertical
	rowList.VerticalAlignment = Enum.VerticalAlignment.Center
	rowList.Padding = UDim.new(0, BOOSTS.rowGap)
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = rows
	for order, kind in ChestConfig.passives.order do
		local spec = ChestConfig.passives.kinds[kind]
		local row = Theme.frame({
			Name = "Row_" .. kind,
			Size = UDim2.new(1, 0, 0, BOOSTS.rowHeight),
			LayoutOrder = order,
			ZIndex = 5,
			Parent = rows,
		})
		local icon = passiveIcon(kind)
		if icon then
			picture(icon, {
				Name = "Icon",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, BOOSTS.icon / 2, 0.5, 0),
				Size = UDim2.fromOffset(BOOSTS.icon, BOOSTS.icon),
				ZIndex = 5,
				Parent = row,
			}, 1)
		else
			local dot = Theme.frame({
				Name = "Dot",
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromHex(spec.color),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, BOOSTS.icon / 2, 0.5, 0),
				Size = UDim2.fromOffset(26, 26),
				ZIndex = 5,
				Parent = row,
			})
			Theme.corner(dot, UDim.new(0.5, 0))
			Theme.outline(dot, 3)
		end
		-- scaled into its column (at most BOOSTS.textSize), never a fixed text size: on a phone the value and the cap
		-- ran into each other ("Coins +((max 25%)", phone test 17.11.2026)
		local function column(name: string, x: number, width: number): TextLabel
			local label = Theme.text({
				Name = name,
				Text = "",
				FontFace = Theme.fontText,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, x, 0.5, 0),
				Size = UDim2.new(0, width - 4, 0.82, 0),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 5,
				Parent = row,
			})
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = BOOSTS.textSize
			limit.Parent = label
			return label
		end
		bonusRows[kind] = {
			value = column("Value", BOOSTS.icon + BOOSTS.gap, BOOSTS.value),
			cap = column("Cap", BOOSTS.icon + BOOSTS.gap + BOOSTS.value, BOOSTS.cap),
		}
	end

	-- the stored scoops: the waffle label with the count and the grid in its panel (how rare scoops get in is said in
	-- the empty grid; the line beside the label ran through it on a phone)
	fillLabel = waffleLabel(content, "StoredLabel", L.storedLabel, 214, 42)

	local gridPanel = panel({
		Name = "GridPanel",
		Position = L.grid.pos,
		Size = L.grid.size,
		ZIndex = 3,
		Parent = content,
	})
	grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(4, 4)
	grid.Size = UDim2.new(1, -8, 1, -8)
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 8
	grid.ScrollBarImageColor3 = Theme.color("creamDark")
	grid.ZIndex = 4
	grid.Selectable = false
	grid.Parent = gridPanel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = grid
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	layout.CellPadding = UDim2.fromOffset(12, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	emptyLabel = Theme.text({
		Name = "Empty",
		Text = `Your chest is empty!\nCatch {rarityLabel(ChestConfig.minRarity)}, Epic or Legendary scoops and serve them at your cart: they land here instead of being sold.`,
		FontFace = Theme.fontText,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -80, 0, 110),
		TextScaled = true,
		TextWrapped = true,
		ZIndex = 5,
		Visible = false,
		Parent = gridPanel,
	})
	local emptyLimit = Instance.new("UITextSizeConstraint")
	emptyLimit.MaxTextSize = 26
	emptyLimit.Parent = emptyLabel

	-- the details over the window's content
	detail = Theme.frame({
		Name = "Detail",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("chocolate"),
		-- a little over the top, so the bonus panel's title pill (half above its panel) is covered too
		Position = UDim2.fromOffset(0, -6),
		Size = UDim2.new(1, 0, 1, 6),
		ZIndex = 20,
		Visible = false,
		Active = true,
		Parent = content,
	})
	Theme.corner(detail, UDim.new(0, 18))
	Theme.outline(detail, 3, Theme.color("rim"))
	Theme.waffle(detail, 21, UDim.new(0, 18)).Name = "DetailWaffle"
	local back = Buttons.wide({ name = "Back", text = "BACK", color = Theme.color("sky"), width = 170, height = 56 })
	back.button.AnchorPoint = Vector2.new(1, 1)
	back.button.Position = UDim2.new(1, -DETAIL.pad, 1, -DETAIL.pad)
	back.button.ZIndex = 24
	back.button.Parent = detail
	back.button.Activated:Connect(function()
		showDetail(nil)
		if Screen.input() == "gamepad" and window then
			GuiService.SelectedObject = window.firstSelection or window.closeButton
		end
	end)
	made.onClosed(function()
		showDetail(nil)
	end)
	render()
end

-- ============================================================================================= the messages =====

local function onChanged(snapshot: any, event: any)
	if type(snapshot) ~= "table" or type(snapshot.items) ~= "table" then
		return
	end
	latest = snapshot
	render()
	if type(event) ~= "table" then
		return
	end
	if event.kind == "stored" then
		local stored = if type(event.stored) == "table" then event.stored else {}
		local overflow = if type(event.overflow) == "number" then event.overflow else 0
		if #stored > 0 then
			-- the rarest of them names the message
			local best, bestRank, mutated = nil, -1, nil
			for _, entry in stored do
				local flavor = Flavors.byId[entry.flavor]
				local rank = flavor and table.find(Flavors.rarities, flavor.rarity) or 0
				if rank > bestRank then
					best, bestRank = flavor, rank
				end
				if entry.mutation ~= "" then
					mutated = entry
				end
			end
			local text
			if #stored == 1 and mutated then
				local spec = mutationSpec(mutated.mutation)
				local flavor = Flavors.byId[mutated.flavor]
				text = `{spec and spec.label or ""} {flavor and flavor.name or ""} added to your chest!`
			elseif #stored == 1 then
				text = `{rarityLabel(best and best.rarity or "rare")} scoop added to your chest!`
			else
				text = `{#stored} rare scoops added to your chest!`
			end
			Toast.show(text, "good", "scoops")
			Sfx.play("chestStored")
		end
		if overflow > 0 then
			task.delay(if #stored > 0 then 1.8 else 0, function()
				Toast.show("Chest full! Sold instead.", "warn")
			end)
		end
	elseif event.kind == "sold" and type(event.coins) == "number" then
		Toast.show(`Sold for {event.coins} coins!`, "good", "coin")
	elseif event.kind == "refused" then
		if event.reason == "full" then
			Toast.show(`All {snapshot.slots} slots are taken!`, "warn")
		elseif event.reason == "far" then
			Toast.show("Get closer to your chest!", "warn")
		end
	end
end

-- Luck turned the scoop just caught rarer: it changes on the tower with a flash, "LUCKY!" pops up in the new rarity's
-- colour and the sound plays. Only the catcher gets this event.
local function onLucky(from: any, to: any)
	local before = type(from) == "string" and Flavors.byId[from]
	local after = type(to) == "string" and Flavors.byId[to]
	if not before or not after then
		return
	end
	local look = ChestConfig.luckyPopup
	local color = Theme.rarity(after.rarity)
	local rarity = rarityLabel(after.rarity)
	local function changed(at: Vector3)
		LuckyVfx.play(at, color)
		LuckyPopup.show(at, color, `{string.upper(rarity)} {string.upper(after.name)}`)
		Sfx.play("lucky", look.pitch)
	end
	if not registry.TowerController.lucky(before.id, after.id, look.delay, changed) then
		-- the tower does not show that catch (served or toppled already): the message alone
		local top = registry.TowerController.topPosition()
		if top then
			changed(top)
		end
	end
end

function ChestController.Init(reg)
	registry = reg
end

function ChestController.Start()
	if not Features.scoopChest then
		return
	end
	-- The arrangement follows the device; a change (a phone turned into a tablet in the emulator) builds it anew. In
	-- Studio the attribute ChestLayout on Workspace ("wide" or "tall") picks one, to look at the phone's on a PC.
	local function layoutFor(plan: any): string
		local forced = if RunService:IsStudio() then workspace:GetAttribute("ChestLayout") else nil
		if forced == "wide" or forced == "tall" then
			return forced
		end
		return if plan and plan.device == "phone" then "wide" else "tall"
	end
	layoutName = layoutFor(Screen.plan())
	buildWindow()
	-- the window's pictures load now, not on the first open (else plaques and cards pop in a moment late)
	task.spawn(function()
		local list = { ART.window.panel, ART.window.title, ART.cardEmpty, ART.equippedLabel, ART.equippedTag }
		table.insert(list, ART.boostPanel)
		table.insert(list, ART.boostTitle)
		for _, group in { ART.cards, ART.badges, ART.passiveIcons } do
			for _, image in group do
				table.insert(list, image)
			end
		end
		ContentProvider:PreloadAsync(list)
	end)
	local function relayout()
		local wanted = layoutFor(Screen.plan())
		if wanted == layoutName or not window then
			return
		end
		layoutName = wanted
		local old = window
		old.close()
		old.gui:Destroy()
		table.clear(bonusRows)
		buildWindow()
	end
	Screen.onChanged(relayout)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("ChestLayout"):Connect(relayout)
	end
	Remotes.ChestChanged.OnClientEvent:Connect(onChanged)
	Remotes.LuckyCatch.OnClientEvent:Connect(onLucky)
	Remotes.ChestAction:FireServer("sync")

	local plots = workspace:WaitForChild("Pier"):WaitForChild("Plots")
	for _, plot in plots:GetChildren() do
		watchPlot(plot)
	end
	plots.ChildAdded:Connect(watchPlot)

	-- chests streaming in and out, and the glints of the open ones
	local sinceResolve = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceResolve += dt
		local check = sinceResolve >= LID.resolveInterval
		if check then
			sinceResolve = 0
		end
		local now = os.clock()
		for _, entry in entries do
			if check then
				resolve(entry)
			end
			if entry.open and entry.chest and now >= entry.nextGlint then
				entry.nextGlint = now + ChestConfig.glintEvery
				ChestVfx.glint(entry.chest)
			end
		end
	end)
end

return ChestController
