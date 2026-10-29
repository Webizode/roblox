-- The settings menu: a gear button top left (touch and mouse), the D-pad up on a gamepad. Five tabs (audio, graphics,
-- camera, controls); every value changes with big - / + or arrow buttons, which work the same with a
-- thumb, a mouse and a gamepad. Changes apply at once (Settings) and are saved with the player's save.
--
-- Also here, because nothing else owns them: the performance mode's local lighting (no shadows, bloom or sun rays on
-- this device) and the small controls overview at the right edge in combat mode.
--
-- Placeholder look until the designer's UI: cream cards with an ink outline.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsRules = require(Shared:WaitForChild("SettingsRules"))
local SettingsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Settings"))

local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))
local Settings = require(client:WaitForChild("Settings"))

local SettingsController = {}

local OPEN_ACTION = "WobbleSettings"
local CLOSE_ACTION = "WobbleSettingsClose"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 100
local PANEL_WIDTH = 560
local ROW_HEIGHT = 52
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
		"Q  Dash   E  Power dash",
		"F  Steady   Shift  Sprint",
	},
	gamepad = { "R2  Throw (hold to charge)", "Y  Leave combat", "L3  Sprint" },
	touch = { "Hold Throw to charge" },
}

local player = Players.LocalPlayer
local gui: ScreenGui
local panel: Frame
local content: Frame
local tabButtons: { TextButton } = {}
local refreshers: { () -> () } = {}
local hint: Frame
local hintLines: TextLabel
local currentTab = 1
local isOpen = false
local originalLighting: { shadows: boolean, effects: { [Instance]: boolean } }? = nil

local function ink(): Color3
	return Ui.color("ink")
end

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
	return Ui.button({
		Text = text,
		Size = UDim2.fromOffset(BUTTON, BUTTON),
		TextSize = 26,
		LayoutOrder = order,
		Selectable = true,
		Parent = parent,
	})
end

-- One row: the label on the left, the control on the right. Toggles are one wide button, numbers and choices a
-- value between - / + or arrows.
local function makeRow(row: Row, order: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = row.key
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	frame.LayoutOrder = order
	Ui.text({
		Text = row.label,
		TextColor3 = ink(),
		TextSize = 22,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Parent = frame,
	})

	local control = Instance.new("Frame")
	control.BackgroundTransparency = 1
	control.AnchorPoint = Vector2.new(1, 0.5)
	control.Position = UDim2.fromScale(1, 0.5)
	control.AutomaticSize = Enum.AutomaticSize.X
	control.Size = UDim2.fromOffset(0, BUTTON)
	control.Parent = frame
	Ui.list(control, Enum.FillDirection.Horizontal, 8)

	local isToggle = type(SettingsConfig.defaults[row.key]) == "boolean"
	if isToggle then
		local toggle = Ui.button({
			Size = UDim2.fromOffset(110, BUTTON),
			TextSize = 22,
			Selectable = true,
			Parent = control,
		})
		toggle.Activated:Connect(function()
			Settings.set(row.key, SettingsRules.step(row.key, Settings.get()[row.key], 1, SettingsConfig))
		end)
		table.insert(refreshers, function()
			local on = Settings.get()[row.key]
			toggle.Text = display(row.key, on)
			toggle.BackgroundColor3 = if on then Ui.color("mint") else Color3.fromRGB(200, 200, 200)
			toggle.TextColor3 = ink()
		end)
		return frame
	end

	local isChoice = SettingsConfig.choices[row.key] ~= nil
	local less = smallButton(if isChoice then "<" else "-", control, 1)
	local value = Ui.text({
		TextColor3 = ink(),
		TextSize = 22,
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
		local current = Settings.get()[row.key]
		value.Text = display(row.key, current)
	end)
	return frame
end

local function refresh()
	for _, refresher in refreshers do
		refresher()
	end
	for index, button in tabButtons do
		local selected = index == currentTab
		button.BackgroundColor3 = if selected then Ui.color("lemon") else Color3.new(1, 1, 1)
		button.TextColor3 = ink()
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
	if not isOpen then
		return
	end
	isOpen = false
	panel.Visible = false
	ContextActionService:UnbindAction(CLOSE_ACTION)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
	Settings.flush()
end

local function open(withGamepad: boolean)
	if isOpen then
		return
	end
	isOpen = true
	showTab(currentTab)
	panel.Visible = true
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			close()
		end
		return Enum.ContextActionResult.Sink
	end, false, ACTION_PRIORITY, Enum.KeyCode.ButtonB)
	if withGamepad then
		GuiService.SelectedObject = tabButtons[currentTab]
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Settings"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")

	-- the gear: a ring with four teeth, built from frames like every icon of the game
	local gear = Ui.button({
		Name = "Gear",
		Size = UDim2.fromOffset(52, 52),
		Position = UDim2.fromOffset(12, 12),
		Selectable = false,
		Parent = gui,
	})
	Ui.autoScale(gear)
	for index = 0, 3 do
		local tooth = Instance.new("Frame")
		tooth.AnchorPoint = Vector2.new(0.5, 0.5)
		tooth.Position = UDim2.fromScale(0.5, 0.5)
		tooth.Size = UDim2.fromOffset(30, 8)
		tooth.Rotation = index * 45
		tooth.BackgroundColor3 = Ui.color("vanilla")
		tooth.BorderSizePixel = 0
		Ui.corner(tooth, UDim.new(0, 2))
		tooth.Parent = gear
	end
	local hub = Ui.circle(20, "vanilla", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	hub.Parent = gear
	local hole = Ui.circle(8, "ink", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	hole.Parent = hub
	gear.Activated:Connect(function()
		if isOpen then
			close()
		else
			open(false)
		end
	end)

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Ui.color("vanilla")
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	Ui.corner(panel, UDim.new(0, 20))
	Ui.stroke(panel, "ink", 3)
	Ui.padding(panel, 18, 14)
	local layout = Ui.list(panel, Enum.FillDirection.Vertical, 12)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	Ui.autoScale(panel)

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 44)
	header.LayoutOrder = 1
	header.Parent = panel
	Ui.text({
		Text = "SETTINGS",
		TextColor3 = ink(),
		TextSize = 32,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Parent = header,
	})
	local closeButton = Ui.button({
		Name = "Close",
		Text = "X",
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Selectable = true,
		Parent = header,
	})
	closeButton.Activated:Connect(close)

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, 0, 0, 44)
	tabs.LayoutOrder = 2
	tabs.Parent = panel
	local tabLayout = Ui.list(tabs, Enum.FillDirection.Horizontal, 6)
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	for index, tab in TABS do
		local button = Ui.button({
			Text = tab.title,
			Size = UDim2.fromOffset((PANEL_WIDTH - 36 - 24) / #TABS, 44),
			TextSize = 18,
			LayoutOrder = index,
			Selectable = true,
			Parent = tabs,
		})
		button.Activated:Connect(function()
			showTab(index)
		end)
		table.insert(tabButtons, button)
	end

	content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.LayoutOrder = 3
	content.Parent = panel
	local rows = Ui.list(content, Enum.FillDirection.Vertical, 6)
	rows.HorizontalAlignment = Enum.HorizontalAlignment.Left
end

-- The controls overview at the right edge, for the input in use; only in combat mode and if switched on.
local function buildHint()
	hint = Ui.card({
		Name = "ControlsHint",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.42, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		Parent = gui,
	})
	Ui.padding(hint, 12, 8)
	Ui.autoScale(hint)
	hintLines = Ui.text({
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		LineHeight = 1.15,
		Parent = hint,
	})
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
			if isOpen then
				close()
			else
				open(true)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, ACTION_PRIORITY, Enum.KeyCode.DPadUp)
	Settings.onChanged(function()
		if isOpen then
			refresh()
		end
		applyLighting()
		updateHint()
	end)
	player:GetAttributeChangedSignal("CombatMode"):Connect(updateHint)
end

return SettingsController
