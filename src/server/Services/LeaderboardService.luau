-- The leaderboard signs in the hub: the global top players by coins (Config/Leaderboard).
--
-- The coins are saved by DataService (ProfileStore). This service keeps a copy of every player's coins in an
-- OrderedDataStore (key: the user id), at most every writeSeconds and when they leave, and reads the top list every
-- refreshSeconds, one GetSortedAsync for all signs. Every call is protected: a failed read keeps the last list on
-- the boards, a failed write is tried again later; after a failure the next try waits retrySeconds, doubling up to
-- four times. Before anything was read (or when the store cannot be reached at all, e.g. Studio without API access)
-- the boards show the players on this server.
--
-- The signs are the deco kit's Leaderboard models anywhere under the map, each with the invisible parts Display
-- (the board) and Header (the plank). The server puts a SurfaceGui on their Front face; it replicates to every
-- client that has the sign streamed in.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local LeaderboardConfig = require(Config:WaitForChild("Leaderboard"))
local MapConfig = require(Config:WaitForChild("Map"))
local LeaderboardRules = require(Shared:WaitForChild("LeaderboardRules"))

local LeaderboardService = {}

local cfg = LeaderboardConfig
local data -- DataService
local store: OrderedDataStore?
local names: { [number]: string } = {}
local written: { [Player]: { coins: number, at: number } } = {}
local boards: { { display: BasePart, header: BasePart? } } = {}
local haveGlobal = false
local readFailures, writeFailures = 0, 0
local nextReadAt, nextWriteAt = 0, 0

local function colour(hex: string): Color3
	return Color3.fromHex(hex)
end

local function backoff(failures: number): number
	return cfg.retrySeconds * 2 ^ math.min(failures - 1, 2)
end

-- names: the player's display name when they are here, otherwise one lookup per new user id (cached)
local function resolveNames(rows: { LeaderboardRules.Row })
	local missing = {}
	for _, row in rows do
		local player = Players:GetPlayerByUserId(row.userId)
		if player then
			names[row.userId] = player.DisplayName
		elseif not names[row.userId] then
			table.insert(missing, row.userId)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info.Id) == "number" and type(info.DisplayName) == "string" then
				names[info.Id] = info.DisplayName
			end
		end
	end
	for _, id in missing do
		if not names[id] then
			local found, name = pcall(function()
				return Players:GetNameFromUserIdAsync(id)
			end)
			names[id] = if found and type(name) == "string" then name else "Player"
		end
	end
end

-- the board's SurfaceGui with `count` empty rows (made once per sign, filled by fill)
local function makeBoard(display: BasePart): Frame
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = cfg.pixelsPerStud
	gui.LightInfluence = 0.4
	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0.04, 0.04)
	list.Size = UDim2.fromScale(0.92, 0.92)
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.008, 0)
	layout.Parent = list
	for rank = 1, cfg.count do
		local row = Instance.new("Frame")
		row.Name = "Row" .. rank
		row.LayoutOrder = rank
		row.Size = UDim2.new(1, 0, 1 / cfg.count, -3)
		row.BackgroundColor3 = colour(cfg.colours.rowStripe)
		row.BackgroundTransparency = if rank % 2 == 0 then 0.35 else 1
		row.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = row
		local badge = Instance.new("TextLabel")
		badge.Name = "Rank"
		badge.Size = UDim2.fromScale(0.13, 0.9)
		badge.Position = UDim2.fromScale(0.005, 0.05)
		badge.BackgroundColor3 = colour(cfg.colours.top[math.min(rank, 3)])
		badge.BackgroundTransparency = if rank <= 3 then 0 else 1
		badge.Font = Enum.Font.FredokaOne
		badge.Text = tostring(rank)
		badge.TextScaled = true
		badge.TextColor3 = if rank <= 3 then colour(cfg.colours.titleStroke) else colour(cfg.colours.dim)
		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0.5, 0)
		badgeCorner.Parent = badge
		badge.Parent = row
		local name = Instance.new("TextLabel")
		name.Name = "Name"
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromScale(0.17, 0.08)
		name.Size = UDim2.fromScale(0.5, 0.84)
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = colour(cfg.colours.text)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = ""
		name.Parent = row
		local coins = Instance.new("TextLabel")
		coins.Name = "Coins"
		coins.BackgroundTransparency = 1
		coins.Position = UDim2.fromScale(0.68, 0.08)
		coins.Size = UDim2.fromScale(0.31, 0.84)
		coins.Font = Enum.Font.FredokaOne
		coins.TextScaled = true
		coins.TextXAlignment = Enum.TextXAlignment.Right
		coins.TextColor3 = if rank <= 3 then colour(cfg.colours.top[rank]) else colour(cfg.colours.text)
		coins.Text = ""
		coins.Parent = row
		row.Parent = list
	end
	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.BackgroundTransparency = 1
	empty.Size = UDim2.fromScale(1, 1)
	empty.Font = Enum.Font.FredokaOne
	empty.TextScaled = true
	empty.TextColor3 = colour(cfg.colours.dim)
	empty.Text = cfg.emptyText
	empty.Visible = false
	empty.Parent = gui
	gui.Parent = display
	return list
end

local function makeHeader(header: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "TitleGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = cfg.pixelsPerStud
	gui.LightInfluence = 0.4
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 1)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = cfg.title
	title.TextColor3 = colour(cfg.colours.titleText)
	local stroke = Instance.new("UIStroke")
	stroke.Color = colour(cfg.colours.titleStroke)
	stroke.Thickness = 4
	stroke.Parent = title
	title.Parent = gui
	gui.Parent = header
end

-- Draws `rows` on every sign (names from the cache; unknown ids show "Player").
function LeaderboardService.render(rows: { LeaderboardRules.Row }, nameOf: { [number]: string }?)
	for _, board in boards do
		local gui = board.display:FindFirstChild("LeaderboardGui")
		local list = gui and gui:FindFirstChild("Rows")
		if not list then
			continue
		end
		for rank = 1, cfg.count do
			local frame = list:FindFirstChild("Row" .. rank) :: Frame
			local row = rows[rank]
			frame.Visible = row ~= nil
			if row then
				local label = (nameOf and nameOf[row.userId]) or names[row.userId] or "Player"
				(frame:FindFirstChild("Name") :: TextLabel).Text = label;
				(frame:FindFirstChild("Coins") :: TextLabel).Text = LeaderboardRules.formatCoins(row.coins)
			end
		end
		(gui:FindFirstChild("Empty") :: TextLabel).Visible = #rows == 0
	end
end

-- the players on this server, as rows (before the first global read, or without store access)
local function serverRows(): { LeaderboardRules.Row }
	local entries = {}
	for _, player in Players:GetPlayers() do
		local save = data.data(player)
		if save then
			table.insert(entries, { key = tostring(player.UserId), value = save.coins })
		end
	end
	table.sort(entries, function(a, b)
		return a.value > b.value
	end)
	return LeaderboardRules.rows(entries, cfg.count)
end

local function read()
	if not store then
		return
	end
	local ok, result = pcall(function()
		local pages = (store :: OrderedDataStore):GetSortedAsync(false, cfg.count * 2)
		return pages:GetCurrentPage()
	end)
	if not ok then
		readFailures += 1
		nextReadAt = os.clock() + backoff(readFailures)
		if readFailures == 1 then
			warn(`[Leaderboard] reading the top list failed, the boards keep the last one: {result}`)
		end
		return
	end
	readFailures = 0
	local rows = LeaderboardRules.rows(result :: { LeaderboardRules.Entry }, cfg.count)
	resolveNames(rows)
	haveGlobal = true
	LeaderboardService.render(rows)
end

local function write(player: Player, force: boolean)
	local save = store and data.data(player)
	if not save then
		return
	end
	local coins = LeaderboardRules.storedCoins(save.coins)
	local last = written[player]
	local now = os.clock()
	if
		not force and not LeaderboardRules.dueWrite(coins, last and last.coins, last and last.at, now, cfg.writeSeconds)
	then
		return
	end
	if force and last and last.coins == coins then
		return
	end
	local ok, err = pcall(function()
		(store :: OrderedDataStore):SetAsync(tostring(player.UserId), coins)
	end)
	if ok then
		writeFailures = 0
		written[player] = { coins = coins, at = now }
	else
		writeFailures += 1
		nextWriteAt = now + backoff(writeFailures)
		if writeFailures == 1 then
			warn(`[Leaderboard] saving {player.Name}'s coins for the ranking failed, will retry: {err}`)
		end
	end
end

local function findBoards()
	local map = workspace:FindFirstChild(MapConfig.root)
	for _, model in (map and map:GetDescendants() or {}) do
		if model:IsA("Model") and model.Name == cfg.modelName then
			local display = model:FindFirstChild("Display")
			if display and display:IsA("BasePart") then
				local header = model:FindFirstChild("Header")
				local board = { display = display, header = if header and header:IsA("BasePart") then header else nil }
				if not display:FindFirstChild("LeaderboardGui") then
					makeBoard(display)
				end
				if board.header and not board.header:FindFirstChild("TitleGui") then
					makeHeader(board.header)
				end
				table.insert(boards, board)
			end
		end
	end
end

function LeaderboardService.Init(registry)
	data = registry.DataService
end

function LeaderboardService.Start()
	findBoards()
	if #boards == 0 then
		return
	end
	local name = cfg.storeName .. (if RunService:IsStudio() then cfg.studioSuffix else "")
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if ok then
		store = result
	else
		warn(`[Leaderboard] no OrderedDataStore "{name}" ({result}): the boards show this server's players`)
	end
	print(`[Leaderboard] {#boards} boards, ranking in "{name}", top {cfg.count} every {cfg.refreshSeconds} s`)

	Players.PlayerRemoving:Connect(function(player)
		write(player, true)
		written[player] = nil
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(write, player, true)
		end
		task.wait(2)
	end)

	task.spawn(function()
		while true do
			local now = os.clock()
			if store and now >= nextWriteAt then
				for _, player in Players:GetPlayers() do
					write(player, false)
				end
			end
			if not haveGlobal then
				LeaderboardService.render(serverRows())
				for _, player in Players:GetPlayers() do
					names[player.UserId] = player.DisplayName
				end
			end
			if store and now >= nextReadAt then
				nextReadAt = now + cfg.refreshSeconds
				read()
			end
			task.wait(5)
		end
	end)
end

return LeaderboardService
