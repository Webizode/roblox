-- The settings panel, opened from the button under the coins. Two options for now: the balance pad (off by
-- default; it never shows unless switched on here) and tilt controls (on by default, only listed on devices with a
-- motion sensor). TowerController reads them every frame to pick the control scheme. Values last for the session;
-- saving them comes with the data store.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))

local Settings = {}

type Option = { key: string, title: string, detail: string }

local OPTIONS: { Option } = {
	{ key = "balancePad", title = "Balance pad", detail = "A thumb pad to push the tower back" },
	{ key = "tiltControls", title = "Tilt controls", detail = "Tilt your device to balance the tower" },
}

local player = Players.LocalPlayer
local values: { [string]: boolean } = { balancePad = false, tiltControls = true }
local gui: ScreenGui

local function switch(key: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Switch"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.fromScale(1, 0.5)
	button.Size = UDim2.fromOffset(58, 32)
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	Ui.corner(button, UDim.new(0.5, 0))
	local knob = Ui.circle(24, "vanilla", { Name = "Knob", AnchorPoint = Vector2.new(0, 0.5) })
	knob.Parent = button

	local function render()
		local on = values[key]
		button.BackgroundColor3 = Ui.color(if on then "mint" else "vanilla")
		button.BackgroundTransparency = if on then 0 else 0.75
		knob.Position = if on then UDim2.new(1, -28, 0.5, 0) else UDim2.new(0, 4, 0.5, 0)
	end
	button.Activated:Connect(function()
		values[key] = not values[key]
		render()
	end)
	render()
	return button
end

local function row(option: Option, order: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = option.key
	frame.LayoutOrder = order
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y

	local texts = Instance.new("Frame")
	texts.BackgroundTransparency = 1
	texts.Size = UDim2.new(1, -70, 0, 0)
	texts.AutomaticSize = Enum.AutomaticSize.Y
	texts.Parent = frame
	local layout = Ui.list(texts, Enum.FillDirection.Vertical, 2)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	for index, props in
		{
			{ Text = option.title, TextSize = 21 },
			{ Text = option.detail, TextSize = 15, TextTransparency = 0.3 },
		}
	do
		local label = Ui.text(props)
		label.LayoutOrder = index
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = UDim2.fromScale(1, 0)
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = texts
	end

	switch(option.key).Parent = frame
	return frame
end

function Settings.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Settings"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10 -- above the HUD and the balance pad
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- tapping next to the panel closes it
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Ui.color("ink")
	backdrop.BackgroundTransparency = 0.6
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Parent = gui
	backdrop.Activated:Connect(Settings.close)

	local panel = Ui.card({
		Name = "Panel",
		Active = true, -- clicks on the panel must not reach the backdrop
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(330, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.04,
	})
	Ui.padding(panel, 20, 18)
	Ui.list(panel, Enum.FillDirection.Vertical, 14)
	Ui.autoScale(panel)
	Ui.text({ Name = "Title", Text = "Settings", TextSize = 30, LayoutOrder = 0 }).Parent = panel

	for index, option in OPTIONS do
		-- without a motion sensor tilt controls cannot work, so the option is not offered at all
		if option.key == "tiltControls" and not UserInputService.AccelerometerEnabled then
			continue
		end
		row(option, index).Parent = panel
	end

	local done = Ui.button({
		Name = "Done",
		LayoutOrder = #OPTIONS + 1,
		Size = UDim2.new(1, 0, 0, 42),
		Text = "Done",
		BackgroundColor3 = Ui.color("lemon"),
		BackgroundTransparency = 0,
		TextColor3 = Ui.color("ink"),
	})
	done.Activated:Connect(Settings.close)
	done.Parent = panel
	panel.Parent = gui
end

function Settings.get(key: string): boolean
	return values[key] == true
end

function Settings.toggle()
	gui.Enabled = not gui.Enabled
end

function Settings.close()
	gui.Enabled = false
end

return Settings
