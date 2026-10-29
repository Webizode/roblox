-- The shared look of all 2D UI: ink cards with a soft cream outline, FredokaOne, rounded corners. The HUD and the
-- settings are built from these helpers so every screen reads as one style. Icons are built from frames, not
-- images or emoji.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Palette"))

local Ui = {}

Ui.FONT = Enum.Font.FredokaOne
Ui.CARD_TRANSPARENCY = 0.15

local scales: { UIScale } = {}
local currentScale = 1

local function apply(instance: Instance, props: { [string]: any }?)
	if props then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
end

function Ui.color(token: string): Color3
	return Color3.fromHex(Palette[token])
end

function Ui.corner(parent: GuiObject, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 12)
	corner.Parent = parent
	return corner
end

-- An outline around the element's border (not around its text).
function Ui.stroke(parent: GuiObject, token: string, thickness: number, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Ui.color(token)
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

function Ui.padding(parent: GuiObject, horizontal: number, vertical: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, horizontal)
	padding.PaddingRight = UDim.new(0, horizontal)
	padding.PaddingTop = UDim.new(0, vertical)
	padding.PaddingBottom = UDim.new(0, vertical)
	padding.Parent = parent
end

function Ui.list(parent: GuiObject, direction: Enum.FillDirection, gap: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = parent
	return layout
end

-- A dark card with the cream outline. Returns the outline too, for elements that recolor it.
function Ui.card(props: { [string]: any }?, radius: UDim?): (Frame, UIStroke)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Ui.color("ink")
	frame.BackgroundTransparency = Ui.CARD_TRANSPARENCY
	frame.BorderSizePixel = 0
	apply(frame, props)
	Ui.corner(frame, radius)
	return frame, Ui.stroke(frame, "vanilla", 2, 0.6)
end

function Ui.button(props: { [string]: any }?): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = Ui.color("ink")
	button.BackgroundTransparency = Ui.CARD_TRANSPARENCY
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Ui.FONT
	button.TextColor3 = Ui.color("vanilla")
	button.TextSize = 22
	button.Text = ""
	apply(button, props)
	Ui.corner(button)
	Ui.stroke(button, "vanilla", 2, 0.6)
	return button
end

-- Text that sizes itself to its content.
function Ui.text(props: { [string]: any }?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Ui.FONT
	label.TextColor3 = Ui.color("vanilla")
	label.TextSize = 22
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	apply(label, props)
	return label
end

function Ui.circle(size: number, token: string, props: { [string]: any }?): Frame
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = Ui.color(token)
	frame.BorderSizePixel = 0
	apply(frame, props)
	Ui.corner(frame, UDim.new(0.5, 0))
	return frame
end

-- The coin, the game's currency symbol (the HUD's coin counter, the name signs over scoops): a lemon disc with a waffle
-- rim and an inner ring, `size` pixels across.
function Ui.coinIcon(size: number, props: { [string]: any }?): Frame
	local coin = Ui.circle(size, "lemon", props)
	Ui.stroke(coin, "waffle", math.max(1, size / 14))
	local inner =
		Ui.circle(size / 2, "lemon", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	Ui.stroke(inner, "waffle", math.max(1, size / 14), 0.35)
	inner.Parent = coin
	return coin
end

-- Scales a cluster with the screen: smaller on phones (short viewports), a little larger on big monitors. The
-- scale works around the cluster's anchor point, so a cluster pinned to an edge stays on that edge.
function Ui.autoScale(target: GuiObject)
	local scale = Instance.new("UIScale")
	scale.Scale = currentScale
	scale.Parent = target
	table.insert(scales, scale)
end

local function updateScale()
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 720
	currentScale = math.clamp(height / 640, 0.8, 1.15)
	for _, scale in scales do
		scale.Scale = currentScale
	end
end

local viewportConnection: RBXScriptConnection? = nil
local function watchCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	updateScale()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

return Ui
