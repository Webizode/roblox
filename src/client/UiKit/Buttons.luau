-- The kit's buttons: the square icon button (word over its lower edge, key badge), the wide button (normal, pressed,
-- locked), the red close button, and the badge that shows a shortcut: the key on a keyboard, the controller's own
-- button symbol with a gamepad, nothing on touch screens. All are drawn in design pixels (Config/Ui) and scale with
-- the UIScale of the cluster they sit in.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Anim = require(script.Parent:WaitForChild("Anim"))
local Screen = require(script.Parent:WaitForChild("Screen"))

local Buttons = {}

local DIGITS = {
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
	Zero = "0",
}

local function keyText(key: Enum.KeyCode): string
	return DIGITS[key.Name] or key.Name
end

export type Badge = { frame: Frame, set: (key: Enum.KeyCode?, pad: Enum.KeyCode?) -> () }

-- A small cream badge with the shortcut, `size` design pixels; follows the input in use.
function Buttons.badge(parent: GuiObject, key: Enum.KeyCode?, pad: Enum.KeyCode?, size: number?): Badge
	local side = size or 24
	local frame = Theme.frame({
		Name = "Badge",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("cream"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(side, side),
		ZIndex = 8,
		Parent = parent,
	})
	Theme.corner(frame, UDim.new(0, 7))
	Theme.outline(frame, 2)
	-- the key's letter centred at a fixed size that fits the box with room round it (no TextScaled: its padding
	-- made the letter tiny), never clipped
	local label = Instance.new("TextLabel")
	label.Name = "Key"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.font
	label.TextSize = math.floor(side * 0.7)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextColor3 = Theme.color("textDark")
	label.ClipsDescendants = false
	label.ZIndex = 9
	label.Parent = frame
	local image = Instance.new("ImageLabel")
	image.Name = "Pad"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1.1, 1.1)
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.ScaleType = Enum.ScaleType.Fit
	image.ZIndex = 9
	image.Parent = frame

	local keyCode, padCode = key, pad
	local function refresh()
		local input = Screen.input()
		if input == "keyboard" and keyCode then
			frame.Visible = true
			frame.BackgroundTransparency = 0
			label.Visible = true
			image.Visible = false
			label.Text = keyText(keyCode)
		elseif input == "gamepad" and padCode then
			frame.Visible = true
			frame.BackgroundTransparency = 1
			label.Visible = false
			image.Visible = true
			image.Image = UserInputService:GetImageForKeyCode(padCode)
		else
			frame.Visible = false
		end
	end
	Screen.onChanged(function()
		refresh()
	end)
	return {
		frame = frame,
		set = function(newKey: Enum.KeyCode?, newPad: Enum.KeyCode?)
			keyCode, padCode = newKey, newPad
			refresh()
		end,
	}
end

-- The button (its size is what can be clicked or tapped) and the face its visuals sit on. With `shrink` the face is
-- Config/Ui.touchFace as big on touch screens: the HUD covers less of the screen while the tap area keeps a thumb's
-- size round the smaller picture.
local function baseButton(name: string, width: number, height: number, shrink: boolean?): (TextButton, Frame)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Size = UDim2.fromOffset(width, height)
	button.Selectable = true
	button.SelectionImageObject = Theme.selection()
	Anim.button(button)
	local face = Theme.frame({
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = button,
	})
	if shrink then
		local scale = Instance.new("UIScale")
		scale.Name = "Face"
		scale.Parent = face
		local function update()
			scale.Scale = if Screen.input() == "touch" then Theme.config.touchFace else 1
		end
		Screen.onChanged(update)
		update()
	end
	return button, face
end

export type IconButton = {
	button: TextButton,
	badge: Badge,
	setColor: (color: Color3) -> (),
	setText: (text: string) -> (),
}

-- A square button: a candy body in `color`, the icon on it, the word over its lower edge, the key badge top left.
-- props: name, icon (asset id), text (optional), color (Color3), key, pad (Enum.KeyCode, optional), size (design).
function Buttons.icon(props: {
	name: string,
	icon: string,
	text: string?,
	color: Color3,
	key: Enum.KeyCode?,
	pad: Enum.KeyCode?,
	size: number?,
	shrink: boolean?,
}): IconButton
	local size = props.size or Theme.config.iconButton
	local button, face = baseButton(props.name, size, size, props.shrink)
	local _, gradient = Theme.body(face, props.color, UDim.new(0.24, 0))
	local hasText = props.text ~= nil and props.text ~= ""
	Theme.icon(props.icon, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if hasText then 0.42 else 0.5),
		Size = UDim2.fromScale(if hasText then 0.78 else 0.74, if hasText then 0.78 else 0.74),
		ZIndex = 4,
		Parent = face,
	})
	local label: TextLabel? = nil
	if hasText then
		-- never wider than the button, so the words of buttons side by side never run into each other
		label = Theme.text({
			Name = "Label",
			Text = props.text,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.86),
			Size = UDim2.fromScale(0.98, 0.27),
			TextScaled = true,
			ZIndex = 6,
			Parent = face,
		})
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = math.floor(size * 0.24)
		limit.Parent = label
	end
	local badge = Buttons.badge(face, props.key, props.pad)
	return {
		button = button,
		badge = badge,
		setColor = function(color: Color3)
			Theme.recolor(gradient, color)
		end,
		setText = function(text: string)
			if label then
				label.Text = text
			end
		end,
	}
end

-- Roblox's touch button of a ContextActionService action, after SetTitle: its title on one line, shrunk to fit the
-- button, never broken inside a word ("Stead / y"). Does nothing without a touch button.
function Buttons.touchTitle(action: string)
	local button = ContextActionService:GetButton(action)
	local title = button and button:FindFirstChild("ActionTitle", true)
	if not (title and title:IsA("TextLabel")) then
		return
	end
	local limit = title:FindFirstChildOfClass("UITextSizeConstraint")
	if not limit then
		limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = math.max(8, math.floor(title.TextSize))
		limit.MinTextSize = 6
		limit.Parent = title
	end
	title.TextWrapped = false
	title.TextScaled = true
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.Size = UDim2.fromScale(0.84, 0.42)
end

-- A small padlock built from frames, for locked buttons.
local function padlock(parent: GuiObject, height: number): Frame
	local lock = Theme.frame({
		Name = "Lock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(height * 0.8, height),
		ZIndex = 7,
		Parent = parent,
	})
	local shackle = Theme.frame({
		Name = "Shackle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = 7,
		Parent = lock,
	})
	Theme.corner(shackle, UDim.new(0.5, 0))
	Theme.outline(shackle, math.max(2, height * 0.13), Theme.color("outline"))
	local box = Theme.frame({
		Name = "Box",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("yellow"),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0.58),
		ZIndex = 8,
		Parent = lock,
	})
	Theme.corner(box, UDim.new(0.22, 0))
	Theme.outline(box, 2)
	return lock
end

export type WideButton = {
	button: TextButton,
	label: TextLabel,
	badge: Badge,
	setLocked: (locked: boolean) -> (),
	setText: (text: string) -> (),
	setColor: (color: Color3) -> (),
	locked: () -> boolean,
}

-- A wide button: optional icon on the left, the word beside it. Pressed it sinks in (Anim); locked it turns grey with
-- a padlock and its Activated still fires (the caller decides, e.g. to say why). props: name, text, color, icon,
-- width, height, key, pad, textSize.
function Buttons.wide(props: {
	name: string,
	text: string,
	color: Color3,
	icon: string?,
	width: number?,
	height: number?,
	key: Enum.KeyCode?,
	pad: Enum.KeyCode?,
	textSize: number?,
	shrink: boolean?,
}): WideButton
	local width = props.width or Theme.config.wideButton.width
	local height = props.height or Theme.config.wideButton.height
	local button, face = baseButton(props.name, width, height, props.shrink)
	local _, gradient = Theme.body(face, props.color, UDim.new(0.5, 0), true)
	local iconSize = height * 1.05
	local icon: ImageLabel? = nil
	if props.icon then
		icon = Theme.icon(props.icon, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, height * 0.6, 0.5, -1),
			Size = UDim2.fromOffset(iconSize, iconSize),
			ZIndex = 4,
			Parent = face,
		})
	end
	local left = if props.icon then height * 1.12 else height * 0.3
	local label = Theme.text({
		Name = "Label",
		Text = props.text,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, left, 0.5, -1),
		Size = UDim2.new(1, -left - height * 0.3, 0.6, 0),
		TextScaled = true,
		ZIndex = 5,
		Parent = face,
	})
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = props.textSize or math.floor(height * 0.5)
	limit.Parent = label
	local lock = padlock(face, height * 0.42)
	lock.Position = UDim2.new(1, -height * 0.32, 0.5, 0)
	lock.Visible = false
	local badge = Buttons.badge(face, props.key, props.pad)
	-- fully on the button, not over its top edge: the top row sits right at the screen's edge
	badge.frame.Position = UDim2.fromOffset(height * 0.32, badge.frame.Size.Y.Offset / 2 + 1)

	local isLocked = false
	local color = props.color
	return {
		button = button,
		label = label,
		badge = badge,
		setLocked = function(locked: boolean)
			isLocked = locked
			Theme.recolor(gradient, if locked then Theme.color("locked") else color)
			lock.Visible = locked
			label.TextTransparency = if locked then 0.25 else 0
			if icon then
				icon.ImageColor3 = if locked then Color3.fromRGB(150, 150, 150) else Color3.new(1, 1, 1)
			end
		end,
		setText = function(text: string)
			label.Text = text
		end,
		setColor = function(newColor: Color3)
			color = newColor
			if not isLocked then
				Theme.recolor(gradient, newColor)
			end
		end,
		locked = function()
			return isLocked
		end,
	}
end

-- The red close button with a white cross, `size` design pixels.
function Buttons.close(size: number?): TextButton
	local side = size or 48
	local button = baseButton("Close", side, side)
	Theme.body(button, Theme.color("red"), UDim.new(0.28, 0))
	for _, rotation in { 45, -45 } do
		local bar = Theme.frame({
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.color("text"),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.48),
			Size = UDim2.fromScale(0.62, 0.16),
			Rotation = rotation,
			ZIndex = 5,
			Parent = button,
		})
		Theme.corner(bar, UDim.new(0.5, 0))
	end
	return button
end

return Buttons
