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
-- (the board) and Header (the plank). The server puts the title on the Header's Front face (it replicates to every
-- client that has the sign streamed in) and publishes the ranking (render); each client draws the board itself as a
-- scrolling list of the top `count` (Controllers/LeaderboardBoards, since 25.11.2026: before, a fixed top 10 drawn
-- here could not scroll).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local LeaderboardConfig = require(Config:WaitForChild("Leaderboard"))
local MapConfig = require(Config:WaitForChild("Map"))
local UiConfig = require(Config:WaitForChild("Ui"))
local LeaderboardRules = require(Shared:WaitForChild("LeaderboardRules"))

-- the game's main font (Config/Ui.fonts) for the title
local FONT_MAIN = Font.fromEnum((Enum.Font :: any)[UiConfig.fonts.main])

local LeaderboardService = {}

local cfg = LeaderboardConfig
local data -- DataService
local store: OrderedDataStore?
local names: { [number]: string } = {}
local written: { [Player]: { coins: number, at: number } } = {}
local boards: { { display: BasePart, header: BasePart? } } = {}
local published: StringValue? = nil -- ReplicatedStorage.LeaderboardTop
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
	title.FontFace = FONT_MAIN
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

-- Publishes `rows` for the signs (names from the cache; unknown ids show "Player"): the ranking as JSON in
-- ReplicatedStorage.LeaderboardTop, [{ r = rank, n = name, c = coins }, ...]. Every client draws the boards from it
-- (Controllers/LeaderboardBoards), as a list that scrolls: a board on the server could not take the mouse wheel or a
-- finger.
function LeaderboardService.render(rows: { LeaderboardRules.Row }, nameOf: { [number]: string }?)
	local list = {}
	for _, row in rows do
		table.insert(list, {
			r = row.rank,
			n = (nameOf and nameOf[row.userId]) or names[row.userId] or "Player",
			c = row.coins,
		})
	end
	local text = HttpService:JSONEncode(list)
	if published and published.Value ~= text then
		published.Value = text
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
	local value = Instance.new("StringValue")
	value.Name = cfg.publishName
	value.Value = "[]"
	value.Parent = ReplicatedStorage
	published = value
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
