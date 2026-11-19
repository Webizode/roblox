-- "LUCKY!" over the own tower when luck turned a caught scoop rarer (ChestController): the word in the new rarity's
-- colour pops up, rises a little and fades, the rarity and the flavor under it. Only the catcher sees it (it lives in
-- their PlayerGui). Values in Config/Chest.luckyPopup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ChestConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Chest"))
local UiKit = require(script.Parent:WaitForChild("UiKit"))
local Theme = UiKit.Theme

local LuckyPopup = {}

local LOOK = ChestConfig.luckyPopup
local player = Players.LocalPlayer

-- `at`: where the scoop sits (world); `color`: the new rarity's colour; `line`: the small text under the word.
function LuckyPopup.show(at: Vector3, color: Color3, line: string)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not root or not gui then
		return
	end
	local board = Instance.new("BillboardGui")
	board.Name = "LuckyPopup"
	board.Adornee = root
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.Size = UDim2.fromOffset(LOOK.width, LOOK.height)
	board.StudsOffsetWorldSpace = at - root.Position + Vector3.new(0, LOOK.above, 0)
	board.ResetOnSpawn = false
	board.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = board
	local word = Theme.text({
		Name = "Word",
		Text = "LUCKY!",
		TextColor3 = color,
		TextScaled = true,
		Size = UDim2.fromScale(1, 0.68),
	})
	word.Parent = board
	local small = Theme.text({
		Name = "Line",
		Text = line,
		TextColor3 = Theme.lighter(color, 0.25),
		TextScaled = true,
		Position = UDim2.fromScale(0.1, 0.68),
		Size = UDim2.fromScale(0.8, 0.32),
	})
	small.Parent = board

	TweenService:Create(scale, TweenInfo.new(LOOK.popTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	TweenService:Create(board, TweenInfo.new(LOOK.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = board.StudsOffsetWorldSpace + Vector3.new(0, LOOK.rise, 0),
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
	task.delay(LOOK.time + 0.1, function()
		board:Destroy()
	end)
end

return LuckyPopup
