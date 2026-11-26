-- The leaderboard signs in the hub, drawn on this client (since 25.11.2026; before, the server drew a fixed top 10).
-- The server publishes the ranking as JSON in ReplicatedStorage.LeaderboardTop (LeaderboardService.render); here every
-- sign's Display (the deco kit's Leaderboard models under the map, Config/Leaderboard) gets a SurfaceGui in PlayerGui
-- adorned to it: the top `count` in a list that shows `visibleRows` at a time and scrolls with the mouse wheel or a
-- finger, with the kit's scroll bar (UiKit Scroller; on a surface the thumb is not dragged). Signs that stream in later
-- get their board then; the title on the Header stays the server's.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local LeaderboardConfig = require(Config:WaitForChild("Leaderboard"))
local MapConfig = require(Config:WaitForChild("Map"))
local LeaderboardRules = require(Shared:WaitForChild("LeaderboardRules"))

local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local Theme, Scroller = UiKit.Theme, UiKit.Scroller

local LeaderboardBoards = {}

local cfg = LeaderboardConfig
local player = Players.LocalPlayer

type Board = { gui: SurfaceGui, scroller: any, empty: TextLabel, rowHeight: number }
local boards: { [BasePart]: Board } = {}
local rows: { LeaderboardRules.Shown } = {}

local function colour(hex: string): Color3
	return Color3.fromHex(hex)
end

-- One row: the place on a badge (gold, silver, bronze for the first three), the name, the coins.
local function makeRow(row: LeaderboardRules.Shown, height: number): Frame
	local rank = row.rank
	local frame = Instance.new("Frame")
	frame.Name = "Row" .. rank
	frame.LayoutOrder = rank
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundColor3 = colour(cfg.colours.rowStripe)
	frame.BackgroundTransparency = if rank % 2 == 0 then 0.35 else 1
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = frame
	local top = cfg.colours.top[rank]
	local badge = Instance.new("TextLabel")
	badge.Name = "Rank"
	badge.Size = UDim2.fromScale(0.13, 0.9)
	badge.Position = UDim2.fromScale(0.005, 0.05)
	badge.BackgroundColor3 = colour(top or cfg.colours.top[3])
	badge.BackgroundTransparency = if top then 0 else 1
	badge.FontFace = Theme.fontMain
	badge.Text = tostring(rank)
	badge.TextScaled = true
	badge.TextColor3 = if top then colour(cfg.colours.titleStroke) else colour(cfg.colours.dim)
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0.5, 0)
	badgeCorner.Parent = badge
	badge.Parent = frame
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromScale(0.17, 0.08)
	name.Size = UDim2.fromScale(0.5, 0.84)
	name.FontFace = Theme.fontMain
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = colour(cfg.colours.text)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = row.name
	name.Parent = frame
	local coins = Instance.new("TextLabel")
	coins.Name = "Coins"
	coins.BackgroundTransparency = 1
	coins.Position = UDim2.fromScale(0.68, 0.08)
	coins.Size = UDim2.fromScale(0.31, 0.84)
	coins.FontFace = Theme.fontText
	coins.TextScaled = true
	coins.TextXAlignment = Enum.TextXAlignment.Right
	coins.TextColor3 = if top then colour(top) else colour(cfg.colours.text)
	coins.Text = LeaderboardRules.formatCoins(row.coins)
	coins.Parent = frame
	return frame
end

local function fill(board: Board)
	local list = board.scroller.list
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for _, row in rows do
		makeRow(row, board.rowHeight).Parent = list
	end
	board.empty.Visible = #rows == 0
end

local function addBoard(display: BasePart)
	if boards[display] then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardBoard"
	gui.Adornee = display
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = cfg.pixelsPerStud
	gui.LightInfluence = 0.4
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- the list inside a 4 % margin; a row is a visibleRows-th of that height
	local inner = display.Size.Y * cfg.pixelsPerStud * 0.92
	local gap = 3
	local rowHeight = math.floor(inner / cfg.visibleRows) - gap
	local scroller = Scroller.new({
		name = "Rows",
		position = UDim2.fromScale(0.04, 0.04),
		size = UDim2.fromScale(0.92, 0.92),
		zIndex = 1,
		parent = gui,
		draggable = false,
		barWidth = 26,
		barGap = 14,
	})
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = scroller.list

	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.BackgroundTransparency = 1
	empty.Size = UDim2.fromScale(1, 1)
	empty.FontFace = Theme.fontMain
	empty.TextScaled = true
	empty.TextColor3 = colour(cfg.colours.dim)
	empty.Text = cfg.emptyText
	empty.Visible = false
	empty.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
	local board = { gui = gui, scroller = scroller, empty = empty, rowHeight = rowHeight }
	boards[display] = board
	fill(board)
	-- the sign streamed out or was removed: its board goes too (it comes back with the sign)
	display.AncestryChanged:Connect(function(_, parent)
		if parent == nil and boards[display] then
			boards[display].gui:Destroy()
			boards[display] = nil
		end
	end)
end

local function consider(instance: Instance)
	if instance:IsA("BasePart") and instance.Name == "Display" then
		local model = instance.Parent
		if model and model:IsA("Model") and model.Name == cfg.modelName then
			addBoard(instance)
		end
	end
end

local function readRows(value: StringValue)
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(value.Value)
	end)
	rows = LeaderboardRules.shown(if ok then decoded else nil, cfg.count)
	for _, board in boards do
		fill(board)
	end
end

function LeaderboardBoards.Start()
	task.spawn(function()
		local value = ReplicatedStorage:WaitForChild(cfg.publishName, 60)
		if value and value:IsA("StringValue") then
			readRows(value)
			value.Changed:Connect(function()
				readRows(value)
			end)
		end
	end)
	task.spawn(function()
		local map = workspace:WaitForChild(MapConfig.root, 60)
		if not map then
			return
		end
		for _, instance in map:GetDescendants() do
			consider(instance)
		end
		map.DescendantAdded:Connect(consider)
	end)
end

return LeaderboardBoards
