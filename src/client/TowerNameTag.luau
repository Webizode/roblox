-- The short name over a tower scoop: "EPIC Tiramisu" in the rarity's colour (TowerMarks), popping up, rising a little
-- and fading after Config/TowerScoops nameTag.time. Over the own tower's scoop just caught (TowerController) and over a
-- rival's rarest scoop while one aims at their tower (Controllers/TowerPeek). It follows the scoop's shown model; it
-- lives in the PlayerGui, so only this player sees it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Look = require(Config:WaitForChild("TowerScoops"))
local Flavors = require(Config:WaitForChild("Flavors"))
local Vfx = require(Config:WaitForChild("Vfx"))
local UiConfig = require(Config:WaitForChild("Ui"))
local RarityFlight = require(Shared:WaitForChild("RarityFlight"))
local TowerMarks = require(Shared:WaitForChild("TowerMarks"))

local UiKit = require(script.Parent:WaitForChild("UiKit"))
local Theme = UiKit.Theme

local TowerNameTag = {}

local LOOK = Look.nameTag
local player = Players.LocalPlayer
local FONT = Font.fromEnum(Enum.Font.LuckiestGuy)

-- The colour of a rarity's name: the ring's, the landing circle's and the trail's (golden for a legendary); a common
-- one white, its own colour (the light grey of the landing circle reads as dirty on a name).
function TowerNameTag.color(rarity: string): Color3
	local hex = if rarity == "common"
		then Flavors.rarityColors.common
		else RarityFlight.circleColor(rarity, Vfx.flight, Flavors.rarityColors, Flavors.rarityColors.common)
	return Color3.fromHex(hex)
end

export type Tag = { board: BillboardGui, label: TextLabel }

-- Shows the name of `flavorId` over `part` (the scoop's shown model) and returns it, or nil for an unknown flavor.
-- It goes by itself; destroy it earlier with TowerNameTag.hide.
function TowerNameTag.show(part: BasePart, flavorId: string): Tag?
	local flavor = Flavors.byId[flavorId]
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not flavor or not gui then
		return nil
	end
	local board = Instance.new("BillboardGui")
	board.Name = "TowerNameTag"
	board.Adornee = part
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.Size = UDim2.fromOffset(LOOK.width, LOOK.height)
	board.StudsOffsetWorldSpace = Vector3.new(0, LOOK.above, 0)
	board.ResetOnSpawn = false
	board.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = board
	-- the kit's look for a word over the world (LuckyPopup): the main font, the chocolate outline round every letter
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = TowerMarks.tagText(flavor.rarity, flavor.name) -- the font draws capitals only
	label.TextColor3 = TowerNameTag.color(flavor.rarity)
	label.TextScaled = true
	label.Size = UDim2.fromScale(1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = Theme.color("outline")
	stroke.Thickness = UiConfig.textStroke
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	label.Parent = board

	TweenService:Create(scale, TweenInfo.new(LOOK.popTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	TweenService:Create(board, TweenInfo.new(LOOK.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = board.StudsOffsetWorldSpace + Vector3.new(0, LOOK.rise, 0),
	}):Play()
	task.delay(LOOK.time - LOOK.fadeTime, function()
		if not board.Parent then
			return
		end
		local fade = TweenInfo.new(LOOK.fadeTime)
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		end
	end)
	task.delay(LOOK.time + 0.1, function()
		board:Destroy()
	end)
	return { board = board, label = label }
end

function TowerNameTag.hide(tag: Tag?)
	if tag then
		tag.board:Destroy()
	end
end

return TowerNameTag
