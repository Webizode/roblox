-- The kit's small animations: a button sinks in while pressed, grows a little under the mouse, and windows, popups
-- and rewards pop up. Short and quiet (Config/Ui.anim); they only touch a UIScale named "Anim" on the element, never its
-- size or position, so layouts stay put.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ui"))

local Anim = {}

local PRESSED = 0.92
local HOVER = 1.05

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
	TweenService:Create(
		Anim.scaleOf(element),
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = value }
	):Play()
end

-- Press, hover and release on a button (mouse, touch and gamepad A all press it).
function Anim.button(button: GuiButton)
	local hovered = false
	local held = false
	local function settle()
		to(button, if held then PRESSED elseif hovered then HOVER else 1, UiConfig.anim.press)
	end
	button.MouseEnter:Connect(function()
		hovered = true
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
	scale.Scale = PRESSED
	to(element, 1, UiConfig.anim.press * 1.6)
end

-- Grows from small to full size with a little overshoot.
function Anim.pop(element: GuiObject)
	local scale = Anim.scaleOf(element)
	scale.Scale = 0.6
	to(element, 1, UiConfig.anim.pop, Enum.EasingStyle.Back)
end

return Anim
