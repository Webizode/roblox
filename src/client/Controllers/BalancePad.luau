-- The right-thumb balance pad. Press anywhere on it and drag against the lean to push the tower back; the knob
-- follows the drag from where you pressed, so a press never jerks the tower by itself. The dot inside shows where
-- the tower leans, the ring turns green/yellow/red with the tilt. In "display" mode (variant A) the pad only shows
-- the level.
--
-- On PC, I/J/K/L work as the pad. They are bound through ContextActionService above the default camera, which
-- otherwise zooms in on I, and they ramp up over Tuning.keyRampTime so a tap is a nudge and holding is a push.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Palette = require(Config:WaitForChild("Palette"))
local Tuning = require(Config:WaitForChild("Tower"))

local BalancePad = {}

export type Mode = "interactive" | "display" | "hidden"

local PAD_SIZE = 150
local KNOB_SIZE = 56
local DOT_SIZE = 16
local KEY_ACTION = "WobbleBalanceKeys"
local KEY_DIRECTIONS = {
	[Enum.KeyCode.L] = Vector2.new(1, 0),
	[Enum.KeyCode.J] = Vector2.new(-1, 0),
	[Enum.KeyCode.I] = Vector2.new(0, 1),
	[Enum.KeyCode.K] = Vector2.new(0, -1),
}

local player = Players.LocalPlayer
local pad: Frame
local knob: Frame
local dot: Frame
local ring: UIStroke
local mode: Mode = "interactive"
local activeInput: InputObject? = nil
local usingMouse = false
local anchor = Vector2.zero
local pointerX, pointerY = 0, 0
local keysDown: { [Enum.KeyCode]: boolean } = {}
local keyX, keyY = 0, 0

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

-- Relative to where the drag started, so screen-inset differences between input and GUI coordinates cancel out.
local function updateFrom(position: Vector3)
	local radius = math.max(pad.AbsoluteSize.X / 2, 1)
	local dx = (position.X - anchor.X) / radius
	local dy = -(position.Y - anchor.Y) / radius
	local length = math.sqrt(dx * dx + dy * dy)
	if length > 1 then
		dx, dy = dx / length, dy / length
	end
	pointerX, pointerY = dx, dy
end

local function begin(input: InputObject)
	anchor = Vector2.new(input.Position.X, input.Position.Y)
	pointerX, pointerY = 0, 0
end

local function release()
	activeInput = nil
	usingMouse = false
	pointerX, pointerY = 0, 0
end

local function approach(current: number, target: number, dt: number): number
	if target == 0 then
		local step = dt / Tuning.keyReleaseTime
		return if current > 0 then math.max(0, current - step) else math.min(0, current + step)
	end
	local step = dt / Tuning.keyRampTime
	return if current < target then math.min(target, current + step) else math.max(target, current - step)
end

local function updateKeys(dt: number)
	local target = Vector2.zero
	-- while typing (chat) the keys belong to the text box; and a release that went to a text box never reached
	-- onKey, so anything that is no longer physically held is dropped here
	if UserInputService:GetFocusedTextBox() then
		table.clear(keysDown)
	end
	for keyCode in keysDown do
		if not UserInputService:IsKeyDown(keyCode) then
			keysDown[keyCode] = nil
		end
	end
	if Tuning.keyboardPad and mode == "interactive" then
		for keyCode in keysDown do
			target += KEY_DIRECTIONS[keyCode]
		end
	end
	keyX = approach(keyX, target.X, dt)
	keyY = approach(keyY, target.Y, dt)
end

local function onKey(_: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		keysDown[input.KeyCode] = true
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		keysDown[input.KeyCode] = nil
	end
	-- always sink: otherwise the default camera zooms on I
	return Enum.ContextActionResult.Sink
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
		if input.UserInputType == Enum.UserInputType.Touch and not activeInput then
			activeInput = input
			begin(input)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			usingMouse = true
			begin(input)
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
	-- key and pointer state can go stale when focus moves mid-press (window or chat), like the default
	-- PlayerModule resets its own key state on the same signals
	local function resetInput()
		table.clear(keysDown)
		release()
	end
	UserInputService.WindowFocusReleased:Connect(resetInput)
	UserInputService.WindowFocused:Connect(resetInput)
	UserInputService.TextBoxFocused:Connect(resetInput)
	UserInputService.TextBoxFocusReleased:Connect(resetInput)

	ContextActionService:BindActionAtPriority(
		KEY_ACTION,
		onKey,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.I,
		Enum.KeyCode.J,
		Enum.KeyCode.K,
		Enum.KeyCode.L
	)
	RunService.RenderStepped:Connect(updateKeys)
end

-- Current pad value in screen space: x to the right, y up, length at most 1.
function BalancePad.get(): (number, number)
	if mode ~= "interactive" then
		return 0, 0
	end
	local x, y
	if activeInput or usingMouse then
		x, y = pointerX, pointerY
	else
		x, y = keyX, keyY
	end
	local length = math.sqrt(x * x + y * y)
	if length > 1 then
		x, y = x / length, y / length
	end
	setKnob(x, y)
	return x, y
end

function BalancePad.setMode(newMode: Mode)
	if newMode == mode then
		return
	end
	mode = newMode
	release()
	keyX, keyY = 0, 0
	setKnob(0, 0)
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
