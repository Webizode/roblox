-- The name sign over a scoop in flight or lying on the ground: "Vanilla (5 [coin])", the name in its rarity's colour,
-- the coin the same as the HUD's (Ui.coinIcon), a fixed size on screen so it reads on a phone, and only drawn up to
-- Config/TowerScoops label.maxDistance studs from the camera (Roblox skips the rest, so many scoops cost little).
-- What it says comes from ScoopLabel. ScoopModel keeps it on whichever of its models shows.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ScoopLabel = require(Shared:WaitForChild("ScoopLabel"))
local Flavors = require(Config:WaitForChild("Flavors"))
local Economy = require(Config:WaitForChild("Economy"))
local Look = require(Config:WaitForChild("TowerScoops"))

local Ui = require(script.Parent:WaitForChild("Ui"))

local ScoopSign = {}

local folder: Folder?

-- The signs live in the PlayerGui (a BillboardGui there draws over its Adornee), so swapping the scoop's model only
-- moves the Adornee.
local function root(): Folder
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "ScoopSigns"
	made.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	folder = made
	return made
end

local function piece(text: string, order: number, color: Color3?): TextLabel
	local label = Ui.text({ Text = text, TextSize = Look.label.textSize, LayoutOrder = order })
	label.TextColor3 = color or Color3.new(1, 1, 1)
	-- a dark rim round the letters keeps it readable over sky, sand and ice cream
	Ui.stroke(label, "ink", 2, 0.1).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	return label
end

-- A sign for a scoop of `flavorId` (golden: worth goldenMultiplier times as much), nil for an unknown flavor.
function ScoopSign.new(flavorId: string, golden: boolean): BillboardGui?
	local flavor = Flavors.byId[flavorId]
	if not flavor then
		return nil
	end
	local label = ScoopLabel.text(flavor, golden, Flavors, Economy)

	local sign = Instance.new("BillboardGui")
	sign.Name = "ScoopSign"
	sign.Size = UDim2.fromOffset(260, Look.label.textSize + 12)
	sign.StudsOffsetWorldSpace = Vector3.new(0, Look.label.height, 0) -- above it whichever way it is turned
	sign.MaxDistance = Look.label.maxDistance
	sign.LightInfluence = 0
	sign.ResetOnSpawn = false

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Size = UDim2.fromScale(0, 1)
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	Ui.list(row, Enum.FillDirection.Horizontal, 6)
	piece(label.name, 1, Color3.fromHex(label.color)).Parent = row
	piece(`({label.value}`, 2).Parent = row
	Ui.coinIcon(Look.label.iconSize, { LayoutOrder = 3 }).Parent = row
	piece(")", 4).Parent = row
	row.Parent = sign

	sign.Parent = root()
	return sign
end

return ScoopSign
