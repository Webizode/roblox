-- "LEGENDARY!" at the top of the screen when the Big Swirl announces a legendary (Config/Vfx.flight banner), for
-- everybody in the arena, with the flavor's name under it. Not for epic. Pops in, stays, fades (Config/Vfx.flight.banner).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local VfxConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Vfx"))
local UiKit = require(script.Parent:WaitForChild("UiKit"))
local Theme, Screen = UiKit.Theme, UiKit.Screen

local RarityBanner = {}

local LOOK = VfxConfig.flight.banner
local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local current: Frame? = nil

-- Shows `title` ("LEGENDARY!") in `color` with `line` (the flavor) under it, if the local player is in the arena.
function RarityBanner.show(title: string, line: string, color: Color3)
	if player:GetAttribute("InArena") ~= true then
		return
	end
	if not gui or not gui.Parent then
		gui = Screen.gui("RarityBanner", 40)
		gui.Parent = player:WaitForChild("PlayerGui")
	end
	if current then
		current:Destroy()
	end
	local holder = Theme.frame({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, LOOK.top),
		Size = UDim2.fromScale(LOOK.width / 1080 * 16 / 9, LOOK.height / 1080),
		Parent = gui,
	})
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = LOOK.width / LOOK.height
	ratio.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = holder
	local word = Theme.text({
		Name = "Title",
		Text = title,
		TextColor3 = color,
		TextScaled = true,
		Size = UDim2.fromScale(1, 0.66),
		Parent = holder,
	})
	local small = Theme.text({
		Name = "Flavor",
		Text = line,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Position = UDim2.fromScale(0.15, 0.66),
		Size = UDim2.fromScale(0.7, 0.34),
		Parent = holder,
	})
	current = holder
	TweenService:Create(scale, TweenInfo.new(LOOK.popTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	task.delay(LOOK.time - LOOK.fadeTime, function()
		local fade = TweenInfo.new(LOOK.fadeTime)
		for _, label in { word, small } do
			TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
			end
		end
	end)
	task.delay(LOOK.time, function()
		holder:Destroy()
		if current == holder then
			current = nil
		end
	end)
end

return RarityBanner
