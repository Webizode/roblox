-- The UI kit's look in one place: colours, font, outline, corners, gloss and shadow (values in Config/Ui), the rarity
-- colours from Config/Flavors. Every kit element is built from these, so a change here changes the whole UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local UiConfig = require(Config:WaitForChild("Ui"))
local Flavors = require(Config:WaitForChild("Flavors"))
local Palette = require(Config:WaitForChild("Palette"))

local Theme = {}

Theme.config = UiConfig
Theme.font = (Enum.Font :: any)[UiConfig.font] :: Enum.Font
Theme.icons = UiConfig.icons

-- the six rarities in order, common to golden (Config/Flavors.rarityColors)
Theme.rarities = { "common", "uncommon", "rare", "epic", "legendary", "golden" }

local cache: { [string]: Color3 } = {}

-- A UI colour (Config/Ui.colors) or, failing that, a world colour (Config/Palette).
function Theme.color(token: string): Color3
	local cached = cache[token]
	if cached then
		return cached
	end
	local hex = UiConfig.colors[token] or Palette[token]
	assert(type(hex) == "string", `Theme: no colour {token}`)
	local color = Color3.fromHex(hex)
	cache[token] = color
	return color
end

function Theme.rarity(rarity: string): Color3
	return Color3.fromHex(Flavors.rarityColors[rarity] or Flavors.rarityColors.common)
end

function Theme.lighter(color: Color3, amount: number?): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount or 0.25)
end

function Theme.darker(color: Color3, amount: number?): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount or 0.2)
end

local function apply(instance: Instance, props: { [string]: any }?)
	if props then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
end
Theme.apply = apply

function Theme.corner(parent: GuiObject, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, UiConfig.corner)
	corner.Parent = parent
	return corner
end

-- The chocolate outline round a frame or button.
function Theme.outline(parent: GuiObject, thickness: number?, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color or Theme.color("outline")
	stroke.Thickness = thickness or UiConfig.stroke
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

-- Top light, bottom dark: the candy body of buttons and bars.
function Theme.shade(parent: GuiObject, color: Color3): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.lighter(color, 0.22)),
		ColorSequenceKeypoint.new(0.55, color),
		ColorSequenceKeypoint.new(1, Theme.darker(color, 0.14)),
	})
	parent.BackgroundColor3 = Color3.new(1, 1, 1)
	gradient.Parent = parent
	return gradient
end

-- The shine at the top left of a candy body.
function Theme.gloss(parent: GuiObject, wide: boolean?)
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.55
	gloss.BorderSizePixel = 0
	gloss.Position = UDim2.fromScale(if wide then 0.05 else 0.1, 0.09)
	gloss.Size = UDim2.fromScale(if wide then 0.32 else 0.34, if wide then 0.16 else 0.11)
	gloss.ZIndex = parent.ZIndex + 1
	gloss.Parent = parent
	Theme.corner(gloss, UDim.new(0.5, 0))
	return gloss
end

-- A word in the kit's style: white with the chocolate outline round every letter.
function Theme.text(props: { [string]: any }?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Theme.font
	label.TextColor3 = Theme.color("text")
	label.TextSize = 22
	label.Text = ""
	apply(label, props)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = Theme.color("outline")
	stroke.Thickness = UiConfig.textStroke
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return label
end

-- A plain container.
function Theme.frame(props: { [string]: any }?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	apply(frame, props)
	return frame
end

export type Skin = { image: ImageLabel, setColor: (color: Color3) -> () }

-- the UI colour token of a colour, to find an image drawn in it
local tokenOfHex: { [string]: string } = {}
for token, hex in UiConfig.colors do
	tokenOfHex[string.upper((string.gsub(hex, "#", "")))] = token
end

-- One of the kit's 9-slice surfaces (Config/Ui.skins): "pill", "square", "info", "window" or "card", filling `parent`.
-- `height` is the surface's height in design pixels: the never-stretched parts are drawn for it, so a pill's ends stay
-- half circles and every corner keeps its shape at any width. `color` picks the image drawn in that colour, else the
-- neutral one tinted with it; `rarity` picks a card's image. setColor swaps the colour later (locked, toggles).
function Theme.skin(parent: GuiObject, kind: string, height: number, color: Color3?, rarity: string?): Skin
	local spec = UiConfig.skins[kind]
	assert(spec, `Theme: no skin {kind}`)
	local image = Instance.new("ImageLabel")
	image.Name = "Skin"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ScaleType = Enum.ScaleType.Slice
	image.ZIndex = 2
	image.Parent = parent
	local inset = spec.inset
	local function setColor(newColor: Color3?)
		local entry = spec.neutral
		local tint = Color3.new(1, 1, 1)
		if rarity and spec.rarities and spec.rarities[rarity] then
			entry = spec.rarities[rarity]
		elseif newColor and spec.colors then
			local token = tokenOfHex[string.upper(newColor:ToHex())]
			local drawn = token and spec.colors[token]
			if drawn then
				entry = drawn
			else
				tint = newColor
			end
		end
		image.Image = entry.id
		image.ImageColor3 = tint
		image.SliceCenter = Rect.new(inset[1], inset[2], entry.w - inset[3], entry.h - inset[4])
		image.SliceScale = spec.scale or height / entry.h
	end
	setColor(color)
	return { image = image, setColor = setColor }
end

-- How many design pixels a skin's never-stretched part is: `side` 1..4 = left, top, right, bottom.
function Theme.skinInset(kind: string, height: number, side: number): number
	local spec = UiConfig.skins[kind]
	local scale = spec.scale or height / spec.neutral.h
	return spec.inset[side] * scale
end

-- The faint waffle pattern (Config/Ui.waffle), repeated, never stretched, over `parent` at `zIndex`; `radius` rounds
-- it off like the surface under it. Returns the label for placing it.
function Theme.waffle(parent: GuiObject, zIndex: number, radius: UDim?): ImageLabel
	local config = UiConfig.waffle
	local waffle = Instance.new("ImageLabel")
	waffle.Name = "Waffle"
	waffle.BackgroundTransparency = 1
	waffle.Image = config.id
	waffle.ImageTransparency = config.transparency
	waffle.ScaleType = Enum.ScaleType.Tile
	waffle.TileSize = UDim2.fromOffset(config.tile, config.tile * 72 / 74)
	waffle.Size = UDim2.fromScale(1, 1)
	waffle.ZIndex = zIndex
	waffle.Parent = parent
	if radius then
		Theme.corner(waffle, radius)
	end
	return waffle
end

-- One sprinkle (Config/Ui.sprinkles) of `color` ("pink", "yellow", "blue"), its middle at `position`, turned by
-- `rotation` degrees.
function Theme.sprinkle(parent: GuiObject, color: string, position: UDim2, rotation: number, zIndex: number): ImageLabel
	local config = UiConfig.sprinkles
	local entry = config.images[color]
	local sprinkle = Instance.new("ImageLabel")
	sprinkle.Name = "Sprinkle"
	sprinkle.BackgroundTransparency = 1
	sprinkle.Image = entry.id
	sprinkle.ScaleType = Enum.ScaleType.Fit
	sprinkle.AnchorPoint = Vector2.new(0.5, 0.5)
	sprinkle.Position = position
	sprinkle.Size = UDim2.fromOffset(config.size, config.size * entry.h / entry.w)
	sprinkle.Rotation = rotation
	sprinkle.ZIndex = zIndex
	sprinkle.Parent = parent
	return sprinkle
end

-- An icon image that never stretches.
function Theme.icon(image: string, props: { [string]: any }?): ImageLabel
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = image
	icon.ScaleType = Enum.ScaleType.Fit
	apply(icon, props)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = icon
	return icon
end

-- The frame a gamepad shows round the selected button: thick, yellow, a little outside the button.
function Theme.selection(radius: UDim?): Frame
	local frame = Theme.frame({
		Name = "Selection",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 12, 1, 12),
	})
	Theme.corner(frame, radius or UDim.new(0, UiConfig.corner + 6))
	local stroke = Theme.outline(frame, 5, Theme.color("select"))
	stroke.Transparency = 0
	return frame
end

return Theme
