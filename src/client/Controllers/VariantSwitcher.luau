-- Kill test only: three buttons to switch between control variant A (joystick), B (balance pad) and
-- C (gyro). Hidden when Features.variantSwitcher is off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Features = require(Config:WaitForChild("Features"))
local Palette = require(Config:WaitForChild("Palette"))
local Tuning = require(Config:WaitForChild("Tower"))

local VariantSwitcher = {}

local KEYS = { "A", "B", "C" }

local player = Players.LocalPlayer
local buttons: { [string]: TextButton } = {}

local function refresh()
	local current = player:GetAttribute("ControlVariant")
	for key, button in buttons do
		local active = key == current
		button.BackgroundColor3 = Color3.fromHex(if active then Palette.lemon else Palette.vanilla)
		button.TextColor3 = Color3.fromHex(Palette.ink)
	end
end

function VariantSwitcher.Start()
	if not Features.variantSwitcher then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "VariantSwitcher"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromOffset(12, 60)
	frame.Size = UDim2.fromOffset(150, 3 * 36 + 2 * 6)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	for index, key in KEYS do
		local button = Instance.new("TextButton")
		button.Name = key
		button.LayoutOrder = index
		button.Size = UDim2.new(1, 0, 0, 36)
		button.Font = Enum.Font.FredokaOne
		button.TextScaled = true
		button.Text = string.format("%s  %s", key, Tuning.variants[key].label)
		button.AutoButtonColor = true
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = button
		button.Activated:Connect(function()
			Remotes.SetVariant:FireServer(key)
		end)
		button.Parent = frame
		buttons[key] = button
	end

	player:GetAttributeChangedSignal("ControlVariant"):Connect(refresh)
	refresh()
end

return VariantSwitcher
