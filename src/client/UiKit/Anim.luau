-- The kit's small animations: a button sinks in while pressed, grows a little under the mouse, and windows, popups
-- and rewards pop up. Short and quiet (Config/Ui.anim); they only touch a UIScale named "Anim" on the element, never its
-- size or position, so layouts stay put.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ui"))

local Anim = {}

local PRESSED = 0.92 -- a pressed button, never smaller
local HOVER = 1.04 -- under the mouse (PC only)

-- the running tween of each Anim scale: a new one cancels it, so quick presses never stack
local running: { [UIScale]: Tween } = setmetatable({}, { __mode = "k" }) :: any

function Anim.scaleOf(element: GuiObject): UIScale
	local scale = element:FindFirstChild("Anim") :: UIScale?
	if not scale then
		local created = Instance.new("UIScale")
		created.Name = "Anim"
		created.Parent = element
		scale = created
	end
	return scale :: UIScale
end

local function to(element: GuiObject, value: number, time: number, style: Enum.EasingStyle?)
	local scale = Anim.scaleOf(element)
	local previous = running[scale]
	if previous then
		previous:Cancel()
	end
	local tween =
		TweenService:Create(scale, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = value,
		})
	running[scale] = tween
	tween:Play()
end

-- Whether the pointer is a real mouse (touch screens fire MouseEnter too, and never MouseLeave after a tap).
local function mouse(): boolean
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.MouseMovement
		or last == Enum.UserInputType.MouseButton1
		or last == Enum.UserInputType.MouseButton2
		or last == Enum.UserInputType.MouseWheel
end

-- Press, hover and release on a button (mouse, touch and gamepad A all press it): pressed it sinks to PRESSED fast,
-- released it eases back; under a mouse it grows to HOVER. It only ever moves between these, never smaller.
function Anim.button(button: GuiButton)
	local hovered = false
	local held = false
	local function settle()
		local target = if held then PRESSED elseif hovered then HOVER else 1
		to(button, target, if held then UiConfig.anim.press else UiConfig.anim.release)
	end
	button.MouseEnter:Connect(function()
		hovered = mouse()
		settle()
	end)
	button.MouseLeave:Connect(function()
		hovered, held = false, false
		settle()
	end)
	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if
			kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			held = true
			settle()
		end
	end)
	button.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if
			kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			held = false
			settle()
		end
	end)
	-- a shortcut key or a gamepad press without the pointer: a short dip
	button.Activated:Connect(function()
		if not held then
			Anim.tap(button)
		end
	end)
end

-- A short dip, for a button pressed by its shortcut.
function Anim.tap(element: GuiObject)
	local scale = Anim.scaleOf(element)
	local previous = running[scale]
	if previous then
		previous:Cancel()
	end
	scale.Scale = PRESSED
	to(element, 1, UiConfig.anim.release)
end

-- A little pop for a number that changed: a moment Config/Ui.anim.bump times as big, then smoothly back.
function Anim.bump(element: GuiObject)
	local scale = Anim.scaleOf(element)
	local previous = running[scale]
	if previous then
		previous:Cancel()
	end
	scale.Scale = UiConfig.anim.bump
	to(element, 1, UiConfig.anim.count * 0.75)
end

-- Grows from small to full size with a little overshoot.
function Anim.pop(element: GuiObject)
	local scale = Anim.scaleOf(element)
	scale.Scale = 0.6
	to(element, 1, UiConfig.anim.pop, Enum.EasingStyle.Back)
end

return Anim
