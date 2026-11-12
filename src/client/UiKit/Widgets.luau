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

-- A chocolate bar with the gold coin on its left end and the amount; `animate` counts up to a new value.
function Widgets.coins(width: number, height: number): CoinCounter
	local frame = Theme.frame({ Name = "Coins", Size = UDim2.fromOffset(width, height) })
	local bar = Theme.frame({
		Name = "Bar",
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(1, -height * 0.45, 0.8, 0),
		ZIndex = 1,
		Parent = frame,
	})
	Theme.corner(bar, UDim.new(0.5, 0))
	Theme.shade(bar, Theme.color("chocolate"))
	Theme.outline(bar)
	Theme.icon(Theme.icons.coin, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(height * 1.08, height * 1.08),
		ZIndex = 3,
		Parent = frame,
	})
	local amount = Theme.text({
		Name = "Amount",
		Text = "0",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, height * 1.12, 0.5, 0),
		Size = UDim2.new(1, -height * 1.3, 0.62, 0),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		Parent = frame,
	})
	local shown = 0
	local counter = Instance.new("NumberValue")
	counter.Changed:Connect(function(value)
		amount.Text = withCommas(value)
	end)
	local tween: Tween? = nil
	return {
		frame = frame,
		set = function(value: number, animate: boolean?)
			if tween then
				tween:Cancel()
			end
			if animate and value > shown then
				counter.Value = shown
				tween = TweenService:Create(counter, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Value = value });
				(tween :: Tween):Play()
				Anim.tap(frame)
			else
				counter.Value = value
				amount.Text = withCommas(value)
			end
			shown = value
		end,
	}
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
	Theme.body(card, rarityColor, UDim.new(0, 16))
	local window = Theme.frame({
		Name = "Picture",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("cream"),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		Size = UDim2.new(1, -18, 0, 92),
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
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(1, -14, 0, 15),
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
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(1, -height * 0.3, 1, 0),
		Parent = sign,
	})
	Theme.corner(pill, UDim.new(0.5, 0))
	Theme.shade(pill, Color3.fromHex("#CFE9FF"))
	Theme.outline(pill)
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
