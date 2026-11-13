-- The kit's buttons: the square icon button (word over its lower edge, key badge), the wide button (normal, pressed,
-- locked), the red close button, and the badge that shows a shortcut: the key on a keyboard, the controller's own
-- button symbol with a gamepad, nothing on touch screens. All are drawn in design pixels (Config/Ui) and scale with
-- the UIScale of the cluster they sit in.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Anim = require(script.Parent:WaitForChild("Anim"))
local Screen = require(script.Parent:WaitForChild("Screen"))
local Keys = require(script.Parent.Parent:WaitForChild("Keys"))

local Buttons = {}

-- What a key cap says: digits as digits, long keys as words (those get the wide cap)
local KEY_TEXT = {
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
	LeftShift = "SHIFT",
	RightShift = "SHIFT",
	LeftControl = "CTRL",
	RightControl = "CTRL",
	Space = "SPACE",
	Return = "ENTER",
	Escape = "ESC",
	Tab = "TAB",
	MouseButton1 = "LMB",
	MouseButton2 = "RMB",
}

local function keyText(key: EnumItem): string
	return KEY_TEXT[key.Name] or key.Name
end

-- the key cap images (Config/Ui badgeStyles, the style badgeStyle picks): their width over their height, and how far
-- down the cap's top face (where the letter goes) has its middle
local CAP_RATIO, WIDE_RATIO = 470 / 410, 1020 / 410
local FACE_Y, FACE_Y_PRESSED = 0.4, 0.47
local PRESS_MIN = 0.12 -- seconds the pressed cap shows at least
local STYLE = Theme.config.badgeStyles[Theme.config.badgeStyle] or Theme.config.badgeStyles.chocolate

-- the caps load at the start, so the first press already shows the pressed one
task.spawn(function()
	local caps = {}
	for _, name in { "cap", "pressed", "wide" } do
		local label = Instance.new("ImageLabel")
		label.Image = STYLE[name]
		table.insert(caps, label)
	end
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(caps)
	end)
end)

export type Badge = { frame: Frame, set: (action: string?) -> () }

-- The key badge of an action (Config/Controls, through Keys), the same everywhere: on a keyboard the key cap from the
-- reference ("Glänzende Cartoon-Tastenkappen", in the colours of Config/Ui.badgeStyle) with the key on it, centred, never cut (the wide cap
-- for long keys like SHIFT); while the key is held the pressed cap. With a gamepad Roblox's own button symbol. On
-- touch screens nothing. `height` in design pixels (default Config/Ui.badge), the cluster's UIScale scales it.
function Buttons.badge(parent: GuiObject, action: string?, height: number?): Badge
	local side = height or Theme.config.badge
	local frame = Theme.frame({
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(side * CAP_RATIO, side),
		ZIndex = 8,
		Parent = parent,
	})
	local cap = Instance.new("ImageLabel")
	cap.Name = "Cap"
	cap.BackgroundTransparency = 1
	cap.Size = UDim2.fromScale(1, 1)
	cap.ScaleType = Enum.ScaleType.Stretch
	cap.Image = STYLE.cap
	cap.ZIndex = 8
	cap.Parent = frame
	local label = Instance.new("TextLabel")
	label.Name = "Key"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.new(1, -side * 0.3, 0, side * 0.6)
	label.Font = Theme.font
	label.TextColor3 = Color3.fromHex(STYLE.text)
	if STYLE.stroke then
		-- a fine dark edge so the cream letter reads on the chocolate
		local edge = Instance.new("UIStroke")
		edge.Color = Theme.color("outline")
		edge.Thickness = 1.5
		edge.Parent = label
	end
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 9
	label.Parent = frame
	local image = Instance.new("ImageLabel")
	image.Name = "Pad"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromOffset(side * 1.1, side * 1.1)
	image.ScaleType = Enum.ScaleType.Fit
	image.ZIndex = 9
	image.Parent = frame

	local current = action
	local pressed = false
	local pressedAt = 0
	local wide = false

	local function look()
		cap.Image = if wide then STYLE.wide elseif pressed then STYLE.pressed else STYLE.cap
		label.Position = UDim2.fromScale(0.5, if pressed and not wide then FACE_Y_PRESSED else FACE_Y)
		-- the wide cap has no pressed picture: it sinks a little instead
		cap.Position = UDim2.fromOffset(0, if pressed and wide then side * 0.06 else 0)
	end

	local function refresh()
		local input = Screen.input()
		local key = if current then Keys.key(current) else nil
		local pad = if current then Keys.pad(current) else nil
		if input == "keyboard" and key then
			local text = keyText(key)
			wide = #text > 2
			frame.Size = UDim2.fromOffset(side * (if wide then WIDE_RATIO else CAP_RATIO), side)
			label.Text = text
			-- a size that surely fits the face: smaller for words
			label.TextSize = math.floor(side * (if wide then 0.4 else 0.5))
			frame.Visible = true
			cap.Visible, label.Visible, image.Visible = true, true, false
			look()
		elseif input == "gamepad" and pad then
			frame.Size = UDim2.fromOffset(side * CAP_RATIO, side)
			frame.Visible = true
			cap.Visible, label.Visible, image.Visible = false, false, true
			image.Image = UserInputService:GetImageForKeyCode(pad)
		else
			frame.Visible = false
		end
	end
	Screen.onChanged(function()
		refresh()
	end)

	-- the pressed cap while the key is down, at least PRESS_MIN
	UserInputService.InputBegan:Connect(function(input)
		if current and Keys.matches(current, input) then
			pressed, pressedAt = true, os.clock()
			look()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if current and Keys.matches(current, input) then
			local wait = math.max(0, PRESS_MIN - (os.clock() - pressedAt))
			task.delay(wait, function()
				pressed = false
				look()
			end)
		end
	end)

	return {
		frame = frame,
		set = function(newAction: string?)
			current = newAction
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
-- props: name, icon (asset id), text (optional), color (Color3), action (its key badge, optional), size (design).
function Buttons.icon(
	props: {
		name: string,
		icon: string,
		text: string?,
		color: Color3,
		action: string?, -- its key badge (Config/Controls)
		size: number?,
		shrink: boolean?,
	}
): IconButton
	local size = props.size or Theme.config.iconButton
	local button, face = baseButton(props.name, size, size, props.shrink)
	local skin = Theme.skin(face, "square", size, props.color)
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
	local badge = Buttons.badge(face, props.action)
	return {
		button = button,
		badge = badge,
		setColor = function(color: Color3)
			skin.setColor(color)
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
-- width, height, action (its key badge), textSize, sprinkles (Config/Ui.sprinkles placements, on the top edge, clear
-- of icon and word). A button too narrow for the pill's round ends gets the square surface.
function Buttons.wide(
	props: {
		name: string,
		text: string,
		color: Color3,
		icon: string?,
		width: number?,
		height: number?,
		action: string?, -- its key badge (Config/Controls)
		textSize: number?,
		shrink: boolean?,
		sprinkles: { { any } }?,
	}
): WideButton
	local width = props.width or Theme.config.wideButton.width
	local height = props.height or Theme.config.wideButton.height
	local button, face = baseButton(props.name, width, height, props.shrink)
	local pill = width >= Theme.skinInset("pill", height, 1) * 2 + 4
	local skin = Theme.skin(face, if pill then "pill" else "square", height, props.color)
	for _, place in props.sprinkles or {} do
		Theme.sprinkle(face, place[1], UDim2.new(place[2], 0, 0, place[3]), place[4], 5)
	end
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
	local badge = Buttons.badge(face, props.action)
	-- the same corner as on every button: half over the top and the left edge, clear of the icon
	badge.frame.Position = UDim2.fromOffset(height * 0.05, 4)

	local isLocked = false
	local color = props.color
	return {
		button = button,
		label = label,
		badge = badge,
		setLocked = function(locked: boolean)
			isLocked = locked
			skin.setColor(if locked then Theme.color("locked") else color)
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
				skin.setColor(newColor)
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
	Theme.skin(button, "square", side, Theme.color("red"))
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
