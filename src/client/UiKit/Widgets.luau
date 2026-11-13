-- The kit's display pieces: the coin counter, the progress bar, the item card (six rarities, or a silhouette with
-- ???), the reward message that pops up and fades, and the safe-zone sign. Drawn in design pixels like the buttons.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Anim = require(script.Parent:WaitForChild("Anim"))

local Widgets = {}

local function withCommas(value: number): string
	local digits = tostring(math.max(0, math.floor(value)))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", ""))
end
Widgets.withCommas = withCommas

export type CoinCounter = { frame: Frame, set: (value: number, animate: boolean?) -> () }
export type Counter = { set: (value: number, animate: boolean?) -> (), refresh: () -> () }

-- A number display that counts smoothly up or down to each new value (Config/Ui.anim.count seconds, from the number
-- it shows right then) and pops `pill` a little (Anim.bump); `show(whole number)` writes it. Setting the value it
-- already heads for does nothing, so it may be called every frame. Without `animate` it jumps (the first value).
function Widgets.counter(show: (value: number) -> (), pill: GuiObject?): Counter
	local holder = Instance.new("NumberValue")
	local target: number? = nil
	local tween: Tween? = nil
	holder.Changed:Connect(function(value)
		show(math.round(value))
	end)
	return {
		set = function(value: number, animate: boolean?)
			if value == target then
				return
			end
			target = value
			if tween then
				tween:Cancel()
				tween = nil
			end
			if animate then
				local running = TweenService:Create(
					holder,
					TweenInfo.new(Theme.config.anim.count, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Value = value }
				)
				tween = running
				running:Play()
				if pill then
					Anim.bump(pill)
				end
			else
				holder.Value = value
				show(math.round(value))
			end
		end,
		-- writes the number it shows now again (when what goes round it changed)
		refresh = function()
			show(math.round(holder.Value))
		end,
	}
end

-- The faint waffle inside an info pill `height` high, below its cream glaze and inside its rim.
function Widgets.infoWaffle(pill: GuiObject, height: number)
	local waffle = Theme.waffle(pill, 3, UDim.new(0.5, 0))
	local rim = height * 0.1
	waffle.Position = UDim2.fromOffset(rim * 2, height * 0.34)
	waffle.Size = UDim2.new(1, -rim * 4, 1, -height * 0.34 - rim)
	return waffle
end

export type InfoPill = { frame: Frame, pill: Frame, row: Frame }

-- An info pill (Config/Ui.infoPill), the one look of coins and tower: `icon` overhanging the chocolate pill's left end,
-- then one row of parts `gap` apart under the cream glaze. The pill is exactly as long as its row, so it never shows
-- much empty room. `frame` holds icon and pill and is as wide as both.
function Widgets.infoPill(name: string, icon: string): InfoPill
	local L = Theme.config.infoPill
	local h = L.height
	local inset = L.icon * 0.45 -- the pill starts under the icon's middle
	local frame = Theme.frame({ Name = name, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, h) })
	local pill = Theme.frame({
		Name = "Pill",
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromOffset(inset, 0),
		Size = UDim2.fromOffset(0, h),
		ZIndex = 1,
		Parent = frame,
	})
	Theme.skin(pill, "info", h)
	Widgets.infoWaffle(pill, h)
	local row = Theme.frame({
		Name = "Row",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, h),
		ZIndex = 4,
		Parent = pill,
	})
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, L.icon - inset + L.gap) -- the parts start a gap after the icon
	padding.PaddingRight = UDim.new(0, L.padRight)
	padding.PaddingTop = UDim.new(0, h * L.glaze) -- nothing reaches under the glaze
	padding.PaddingBottom = UDim.new(0, h * 0.06)
	padding.Parent = row
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, L.gap)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row

	Theme.icon(icon, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(L.icon, L.icon),
		ZIndex = 5,
		Parent = frame,
	})
	return { frame = frame, pill = pill, row = row }
end

-- A number in an info pill's row: Theme.fontNumbers at `size`, as wide as it reads.
function Widgets.pillNumber(row: Frame, name: string, size: number, order: number): TextLabel
	return Theme.text({
		Name = name,
		FontFace = Theme.fontNumbers,
		TextSize = size,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size + 4),
		LayoutOrder = order,
		Parent = row,
	})
end

-- The coin counter: the gold coin on the info pill and the amount centred after it; the pill grows and shrinks with the
-- amount, and an amount longer than Config/Ui.infoPill.maxChars gets smaller instead. `animate` counts up or down to a
-- new value and pops the pill.
function Widgets.coins(): CoinCounter
	local L = Theme.config.infoPill
	local pill = Widgets.infoPill("Coins", Theme.icons.coin)
	local amount = Widgets.pillNumber(pill.row, "Amount", L.text, 1)
	-- as wide as the number reads, at least coinsMinRow (a small amount sits centred in it): sized from TextBounds, as
	-- a UISizeConstraint on an automatically sized row kept the pill from ever getting shorter again
	amount.AutomaticSize = Enum.AutomaticSize.None
	amount.TextXAlignment = Enum.TextXAlignment.Center
	local function fit()
		amount.Size = UDim2.fromOffset(math.max(amount.TextBounds.X + 2, L.coinsMinRow), L.text + 4)
	end
	amount:GetPropertyChangedSignal("TextBounds"):Connect(fit)
	amount.Text = "0"
	fit()
	local counter = Widgets.counter(function(value)
		local text = withCommas(value)
		amount.Text = text
		amount.TextSize = math.floor(L.text * math.min(1, L.maxChars / math.max(#text, 1)))
	end, pill.frame)
	return { frame = pill.frame, set = counter.set }
end
export type ProgressBar = { frame: Frame, set: (share: number, text: string?) -> () }

-- A rounded track with a candy fill from the left and a text over it.
function Widgets.progress(width: number, height: number, color: Color3): ProgressBar
	local frame = Theme.frame({
		Name = "Progress",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.darker(Theme.color("chocolate"), 0.2),
		Size = UDim2.fromOffset(width, height),
	})
	Theme.corner(frame, UDim.new(0.5, 0))
	Theme.outline(frame)
	local fill = Theme.frame({
		Name = "Fill",
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(0.5, 1),
		ZIndex = 2,
		Parent = frame,
	})
	Theme.corner(fill, UDim.new(0.5, 0))
	Theme.shade(fill, color)
	Theme.gloss(fill, true)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.Parent = fill
	local label = Theme.text({
		Name = "Text",
		FontFace = Theme.fontText,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -16, 0.7, 0),
		TextScaled = true,
		ZIndex = 4,
		Parent = frame,
	})
	return {
		frame = frame,
		set = function(share: number, text: string?)
			local clamped = math.clamp(share, 0, 1)
			fill.Visible = clamped > 0
			-- never thinner than its own rounding
			fill.Size = UDim2.fromScale(clamped, 1)
			sizeLimit.MinSize = Vector2.new(if clamped > 0 then height else 0, 0)
			label.Text = text or ""
		end,
	}
end

-- A card for an item: framed and shaded in its rarity's colour, the picture, its name and rarity. `unknown` shows the
-- picture as a black silhouette and ??? for the name (not discovered yet).
function Widgets.itemCard(props: { rarity: string, name: string, image: string, unknown: boolean? }): Frame
	local rarityColor = Theme.rarity(props.rarity)
	local card = Theme.frame({ Name = "Item_" .. props.name, Size = UDim2.fromOffset(124, 156) })
	Theme.skin(card, "card", 156, rarityColor, props.rarity)
	local window = Theme.frame({
		Name = "Picture",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("cream"),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 27),
		Size = UDim2.new(1, -18, 0, 89),
		ZIndex = 4,
		Parent = card,
	})
	Theme.corner(window, UDim.new(0, 12))
	Theme.outline(window, 2)
	local glow = Instance.new("UIGradient")
	glow.Rotation = 90
	glow.Color = ColorSequence.new(Color3.new(1, 1, 1), Theme.lighter(rarityColor, 0.55))
	glow.Parent = window
	local picture = Theme.icon(props.image, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		ZIndex = 5,
		Parent = window,
	})
	if props.unknown then
		picture.ImageColor3 = Color3.new(0, 0, 0)
		picture.ImageTransparency = 0.15
	end
	Theme.text({
		Name = "Rarity",
		Text = string.upper(props.rarity),
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- clear of the card's dark rim, on its light inner edge
		Position = UDim2.new(0.5, 0, 0, 17),
		Size = UDim2.new(1, -24, 0, 13),
		TextScaled = true,
		ZIndex = 6,
		Parent = card,
	})
	Theme.text({
		Name = "Name",
		Text = if props.unknown then "???" else props.name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -21),
		Size = UDim2.new(1, -12, 0, 22),
		TextScaled = true,
		ZIndex = 6,
		Parent = card,
	})
	return card
end

-- A reward message: a cream card with an icon and a text (e.g. "+250"), popping up under `parent`'s top and fading
-- after `duration` seconds. `y` is its top in pixels of the parent.
function Widgets.reward(parent: GuiObject, props: { icon: string, text: string, y: number, duration: number? })
	local card = Theme.frame({
		Name = "Reward",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("cream"),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, props.y),
		Size = UDim2.fromOffset(0, 58),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 20,
		Parent = parent,
	})
	Theme.corner(card, UDim.new(0.5, 0))
	local stroke = Theme.outline(card, 4)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 22)
	padding.Parent = card
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = card
	local icon =
		Theme.icon(props.icon, { Size = UDim2.fromOffset(46, 46), LayoutOrder = 1, ZIndex = 21, Parent = card })
	local label = Theme.text({
		Text = props.text,
		FontFace = Theme.fontText,
		TextSize = 34,
		TextColor3 = Theme.color("yellow"),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
		ZIndex = 21,
		Parent = card,
	})
	Anim.pop(card)
	task.delay(props.duration or 1.6, function()
		local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(card, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		TweenService:Create(icon, fade, { ImageTransparency = 1 }):Play()
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		local labelStroke = label:FindFirstChildOfClass("UIStroke")
		if labelStroke then
			TweenService:Create(labelStroke, fade, { Transparency = 1 }):Play()
		end
		task.wait(0.4)
		card:Destroy()
	end)
	return card
end

-- The safe-zone sign: a pale blue pill with the shield and SAFE ZONE.
function Widgets.safeSign(width: number, height: number): Frame
	local sign = Theme.frame({ Name = "SafeZone", Size = UDim2.fromOffset(width, height) })
	local pill = Theme.frame({
		Name = "Pill",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(1, -height * 0.3, 1, 0),
		Parent = sign,
	})
	Theme.skin(pill, "pill", height, Color3.fromHex("#CFE9FF"))
	Theme.icon(Theme.icons.safe, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(height * 1.3, height * 1.3),
		ZIndex = 3,
		Parent = sign,
	})
	Theme.text({
		Text = "SAFE ZONE",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, height * 1.25, 0.5, 0),
		Size = UDim2.new(1, -height * 1.45, 0.66, 0),
		TextScaled = true,
		ZIndex = 4,
		Parent = sign,
	})
	return sign
end

return Widgets
