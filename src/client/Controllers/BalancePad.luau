-- The right-thumb balance pad. Drag against the lean to push the tower back. The dot inside shows where the
-- tower leans, the ring turns green/yellow/red with the tilt. In "display" mode (variant A) the pad only
-- shows the level; on PC, I/J/K/L work as a pad too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Palette = require(Config:WaitForChild("Palette"))
local Tuning = require(Config:WaitForChild("Tower"))

local BalancePad = {}

export type Mode = "interactive" | "display" | "hidden"

local PAD_SIZE = 150
local KNOB_SIZE = 56
local DOT_SIZE = 16

local player = Players.LocalPlayer
local pad: Frame
local knob: Frame
local dot: Frame
local ring: UIStroke
local mode: Mode = "interactive"
local activeInput: InputObject? = nil
local usingMouse = false
local valueX, valueY = 0, 0

local function circle(parent: Instance, size: number, color: string, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = Color3.fromHex(color)
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function setKnob(x: number, y: number)
	local radius = (PAD_SIZE - KNOB_SIZE) / 2
	knob.Position = UDim2.new(0.5, x * radius, 0.5, -y * radius)
end

local function updateFrom(position: Vector3)
	local center = pad.AbsolutePosition + pad.AbsoluteSize / 2
	local radius = pad.AbsoluteSize.X / 2
	local dx = (position.X - center.X) / radius
	local dy = -(position.Y - center.Y) / radius
	local length = math.sqrt(dx * dx + dy * dy)
	if length > 1 then
		dx, dy = dx / length, dy / length
	end
	valueX, valueY = dx, dy
	setKnob(dx, dy)
end

local function release()
	activeInput = nil
	usingMouse = false
	valueX, valueY = 0, 0
	setKnob(0, 0)
end

function BalancePad.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BalancePad"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	pad = circle(gui, PAD_SIZE, Palette.vanilla, 0.45)
	pad.Name = "Pad"
	pad.AnchorPoint = Vector2.new(1, 1)
	pad.Position = UDim2.new(1, -36, 1, -36)
	pad.Active = true -- keeps drags on the pad from turning the camera
	ring = Instance.new("UIStroke")
	ring.Thickness = 4
	ring.Color = Color3.fromHex(Palette.mint)
	ring.Parent = pad

	dot = circle(pad, DOT_SIZE, Palette.ink, 0.1)
	dot.Name = "LeanDot"
	knob = circle(pad, KNOB_SIZE, Palette.strawberry, 0.15)
	knob.Name = "Knob"

	pad.InputBegan:Connect(function(input)
		if mode ~= "interactive" then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			activeInput = input
			updateFrom(input.Position)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			usingMouse = true
			updateFrom(input.Position)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input == activeInput or (usingMouse and input.UserInputType == Enum.UserInputType.MouseMovement) then
			updateFrom(input.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == activeInput or (usingMouse and input.UserInputType == Enum.UserInputType.MouseButton1) then
			release()
		end
	end)
end

local function keyboard(): (number, number)
	if not Tuning.keyboardPad or UserInputService:GetFocusedTextBox() then
		return 0, 0
	end
	local x, y = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.L) then
		x += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.J) then
		x -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.I) then
		y += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.K) then
		y -= 1
	end
	return x, y
end

-- Current pad value in screen space: x to the right, y up, both in [-1, 1].
function BalancePad.get(): (number, number)
	if mode ~= "interactive" then
		return 0, 0
	end
	if activeInput or usingMouse then
		return valueX, valueY
	end
	local x, y = keyboard()
	if x ~= 0 or y ~= 0 then
		local length = math.sqrt(x * x + y * y)
		setKnob(x / length, y / length)
		return x / length, y / length
	end
	setKnob(0, 0)
	return 0, 0
end

function BalancePad.setMode(newMode: Mode)
	if newMode == mode then
		return
	end
	mode = newMode
	release()
	pad.Visible = newMode ~= "hidden"
	pad.Active = newMode == "interactive"
	knob.Visible = newMode == "interactive"
end

-- tilt is the share of the tip angle; leanX/leanY is the lean direction in screen space.
function BalancePad.setLevel(tilt: number, groaning: boolean, leanX: number, leanY: number)
	local color = if groaning or tilt >= Tuning.groanFraction
		then Palette.awning
		elseif tilt >= 0.5 then Palette.lemon
		else Palette.mint
	ring.Color = Color3.fromHex(color)
	local radius = (PAD_SIZE - DOT_SIZE) / 2
	dot.Position = UDim2.new(0.5, math.clamp(leanX, -1, 1) * radius, 0.5, -math.clamp(leanY, -1, 1) * radius)
end

return BalancePad
