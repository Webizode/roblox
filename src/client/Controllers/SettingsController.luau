-- The settings menu: a gear button top right (touch and mouse), the D-pad up on a gamepad. A kit window (UiKit) with
-- four tabs (audio, graphics, camera, controls); every value changes with big - / + or arrow buttons, which work the
-- same with a thumb, a mouse and a gamepad. Changes apply at once (Settings) and are saved with the player's save. B
-- or the red button closes it.
--
-- Also here, because nothing else owns them: the performance mode's local lighting (no shadows, bloom or sun rays on
-- this device) and the small controls overview at the right edge in combat mode.

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsRules = require(Shared:WaitForChild("SettingsRules"))
local SettingsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Settings"))

local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local Keys = require(client:WaitForChild("Keys"))
local Theme, Screen, Buttons, Window = UiKit.Theme, UiKit.Screen, UiKit.Buttons, UiKit.Window
local Settings = require(client:WaitForChild("Settings"))

local SettingsController = {}

local OPEN_ACTION = "WobbleSettings"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 100
local ROW_HEIGHT = 54
local WINDOW_WIDTH = 600
local WINDOW_HEIGHT = 470
local BUTTON = 48 -- square buttons, big enough for a thumb

type Row = { key: string, label: string }

local TABS: { { title: string, rows: { Row } } } = {
	{
		title = "Audio",
		rows = {
			{ key = "sfxVolume", label = "Effects" },
			{ key = "musicVolume", label = "Music" },
		},
	},
	{
		title = "Graphics",
		rows = {
			{ key = "vfxQuality", label = "VFX quality" },
			{ key = "performanceMode", label = "Performance mode" },
		},
	},
	{
		title = "Camera",
		rows = {
			{ key = "cameraShake", label = "Camera shake" },
			{ key = "fov", label = "Field of view" },
			{ key = "motionEffects", label = "Sprint, dash and aim effects" },
			{ key = "aimCamera", label = "Aim camera" },
		},
	},
	{
		title = "Controls",
		rows = {
			{ key = "inputMode", label = "Input" },
			{ key = "mouseSensitivity", label = "Mouse sensitivity" },
			{ key = "touchSensitivity", label = "Touch sensitivity" },
			{ key = "gamepadSensitivity", label = "Controller sensitivity" },
			{ key = "controlsHint", label = "Show controls in combat" },
		},
	},
}

local NAMES: { [string]: string } = {
	high = "High",
	medium = "Medium",
	low = "Low",
	ring = "Ring",
	dot = "Dot",
	cross = "Cross",
	vanilla = "Vanilla",
	lemon = "Lemon",
	mint = "Mint",
	strawberry = "Strawberry",
	skyTop = "Sky",
	auto = "Automatic",
	touch = "Phone",
	keyboard = "PC",
	gamepad = "Controller",
}

local HINTS: { [string]: { string } } = {
	keyboard = {
		"LMB  Throw (hold to charge)",
		"R  Leave combat",
		"Q  Dash   F  Steady",
		"Shift  Sprint",
	},
	gamepad = { "R2  Throw (hold to charge)", "Y  Leave combat", "X  Dash   L3  Sprint" },
	touch = { "Hold Throw to charge" },
}

local player = Players.LocalPlayer
local gui: ScreenGui
local window: any -- UiKit.Window
local tabs: any -- UiKit.Window.tabs
local content: Frame
local refreshers: { () -> () } = {}
local hint: Frame
local hintLines: TextLabel
local currentTab = 1
local originalLighting: { shadows: boolean, effects: { [Instance]: boolean } }? = nil

local function display(key: string, value: any): string
	if
		key == "sfxVolume"
		or key == "musicVolume"
		or key == "mouseSensitivity"
		or key == "touchSensitivity"
		or key == "gamepadSensitivity"
	then
		return string.format("%d%%", math.floor(value * 100 + 0.5))
	elseif key == "fov" then
		return tostring(value)
	elseif type(value) == "boolean" then
		return if value then "ON" else "OFF"
	end
	return NAMES[value] or tostring(value)
end

local function smallButton(text: string, parent: Instance, order: number): TextButton
	local button = Buttons.wide({
		name = text,
		text = text,
		color = Theme.color("sky"),
		width = BUTTON,
		height = BUTTON,
		textSize = 28,
	})
	button.button.LayoutOrder = order
	button.button.Parent = parent
	return button.button
end

-- Dark text on the cream window.
local function plainText(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Theme.font
	label.TextColor3 = Theme.color("textDark")
	label.TextSize = 22
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.ZIndex = 5
	Theme.apply(label, props)
	return label
end

-- One row: the label on the left, the control on the right. Toggles are one wide button, numbers and choices a
-- value between - / + or arrows.
local function makeRow(row: Row, order: number): Frame
	local frame = Theme.frame({
		Name = row.key,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = order,
		ZIndex = 4,
	})
	plainText({
		Text = row.label,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Parent = frame,
	})

	local control = Theme.frame({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, BUTTON + 6),
		Parent = frame,
	})
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = control

	local isToggle = type(SettingsConfig.defaults[row.key]) == "boolean"
	if isToggle then
		local toggle = Buttons.wide({
			name = "Toggle",
			text = "",
			color = Theme.color("mint"),
			width = 120,
			height = BUTTON,
			textSize = 24,
		})
		toggle.button.Parent = control
		toggle.button.Activated:Connect(function()
			Settings.set(row.key, SettingsRules.step(row.key, Settings.get()[row.key], 1, SettingsConfig))
		end)
		table.insert(refreshers, function()
			local on = Settings.get()[row.key]
			toggle.setText(display(row.key, on))
			toggle.setColor(if on then Theme.color("mint") else Theme.color("locked"))
		end)
		return frame
	end

	local isChoice = SettingsConfig.choices[row.key] ~= nil
	local less = smallButton(if isChoice then "<" else "-", control, 1)
	local value = plainText({
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromOffset(130, BUTTON),
		LayoutOrder = 2,
		Parent = control,
	})
	local more = smallButton(if isChoice then ">" else "+", control, 3)
	less.Activated:Connect(function()
		Settings.set(row.key, SettingsRules.step(row.key, Settings.get()[row.key], -1, SettingsConfig))
	end)
	more.Activated:Connect(function()
		Settings.set(row.key, SettingsRules.step(row.key, Settings.get()[row.key], 1, SettingsConfig))
	end)
	table.insert(refreshers, function()
		value.Text = display(row.key, Settings.get()[row.key])
	end)
	return frame
end

local function refresh()
	for _, refresher in refreshers do
		refresher()
	end
end

local function showTab(index: number)
	currentTab = index
	for _, child in content:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	table.clear(refreshers)
	for order, row in TABS[index].rows do
		makeRow(row, order).Parent = content
	end
	refresh()
end

local function close()
	window.close()
end

local function open()
	if window.isOpen() then
		return
	end
	showTab(currentTab)
	window.firstSelection = tabs.buttons[currentTab]
	window.open()
end

local function build()
	gui = Screen.gui("Settings", 20)

	-- the gear: a silver icon button, top right; with a gamepad the D-pad symbol shows on it
	local gear = Buttons.icon({
		name = "Gear",
		icon = Theme.icons.settings,
		color = Theme.color("silver"),
		size = Theme.config.settingsButton,
		shrink = true,
		action = "settings",
	})
	gear.button.Selectable = false
	local holder = Theme.frame({ Name = "GearHolder", Parent = gui })
	gear.button.Parent = holder
	Screen.onChanged(function(plan)
		Screen.place(holder, plan.settings, plan.scale)
	end)
	gear.button.Activated:Connect(function()
		if window.isOpen() then
			close()
		else
			open()
		end
	end)

	window = Window.new({
		name = "SettingsWindow",
		title = "SETTINGS",
		color = Theme.color("sky"),
		width = WINDOW_WIDTH,
		height = WINDOW_HEIGHT,
	})
	window.onClosed(function()
		Settings.flush()
	end)
	local names = {}
	for index, tab in TABS do
		names[index] = tab.title
	end
	tabs = Window.tabs(window.content, names, Theme.color("sky"), showTab)

	content = Theme.frame({
		Name = "Rows",
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		ZIndex = 4,
		Parent = window.content,
	})
	local rows = Instance.new("UIListLayout")
	rows.FillDirection = Enum.FillDirection.Vertical
	rows.Padding = UDim.new(0, 4)
	rows.SortOrder = Enum.SortOrder.LayoutOrder
	rows.Parent = content
end

-- The controls overview at the right edge, for the input in use; only in combat mode and if switched on.
local function buildHint()
	local holder = Theme.frame({ Name = "HintHolder", Parent = gui })
	hint = Theme.frame({
		Name = "ControlsHint",
		BackgroundTransparency = 0.08,
		BackgroundColor3 = Theme.color("cream"),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		Parent = holder,
	})
	Theme.corner(hint, UDim.new(0, 14))
	Theme.outline(hint)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = hint
	hintLines = plainText({
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		LineHeight = 1.15,
		Parent = hint,
	})
	-- right edge, a little above the middle
	Screen.onChanged(function(plan)
		Screen.place(holder, {
			x = plan.frame.x + plan.frame.w - 1,
			y = plan.frame.y + plan.frame.h * 0.42,
			w = 1,
			h = 1,
		}, plan.scale)
	end)
end

local function updateHint()
	local lines = HINTS[Settings.inputKind()] or HINTS.keyboard
	hintLines.Text = table.concat(lines, "\n")
	hint.Visible = Settings.get().controlsHint and player:GetAttribute("CombatMode") == true
end

-- The performance mode turns off shadows, bloom and sun rays on this device only; off again, they come back as the
-- place has them.
local function applyLighting()
	local effects = Settings.effective()
	if not originalLighting then
		local saved = { shadows = Lighting.GlobalShadows, effects = {} }
		for _, child in Lighting:GetChildren() do
			if child:IsA("BloomEffect") or child:IsA("SunRaysEffect") then
				saved.effects[child] = child.Enabled
			end
		end
		originalLighting = saved
	end
	local saved = originalLighting :: { shadows: boolean, effects: { [Instance]: boolean } }
	Lighting.GlobalShadows = saved.shadows and effects.shadows
	for effect, enabled in saved.effects do
		(effect :: any).Enabled = enabled and effects.postEffects
	end
end

function SettingsController.Start()
	build()
	buildHint()
	ContextActionService:BindActionAtPriority(OPEN_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			if window.isOpen() then
				close()
			else
				open()
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, ACTION_PRIORITY, table.unpack(Keys.inputs("settings")))
	Settings.onChanged(function()
		if window.isOpen() then
			refresh()
		end
		applyLighting()
		updateHint()
	end)
	player:GetAttributeChangedSignal("CombatMode"):Connect(updateHint)
end

return SettingsController
