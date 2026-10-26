-- Saves every player's progress (SaveData) in a ProfileStore profile with a session lock: a profile is open on one
-- server at a time, so a quick server switch neither duplicates nor loses anything. The server is the only one that
-- changes the data; clients get display values (TowerService's leaderstats and the attributes set here).
--
-- Loading fails: the player is kicked with a clear message and nothing is written. Another server takes the profile
-- over: the player is kicked here, that server has the save now.
--
-- In Studio the data goes to its own store (Config/Save.studioSuffix). Without "Enable Studio Access to API
-- Services" ProfileStore keeps it in memory only and says so in the output.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local SaveData = require(Shared:WaitForChild("SaveData"))
local SaveConfig = require(Config:WaitForChild("Save"))
local EconomyConfig = require(Config:WaitForChild("Economy"))
local ProfileStore = require(script.Parent.Parent:WaitForChild("Packages"):WaitForChild("ProfileStore"))

local DataService = {}

local store
local profiles: { [Player]: any } = {}
local loadedCallbacks: { (player: Player, data: SaveData.Data) -> () } = {}

local function storeName(): string
	return SaveConfig.storeName .. (if RunService:IsStudio() then SaveConfig.studioSuffix else "")
end

-- Display values for the client; the leaderstats (coins, best tower) are TowerService's.
local function publish(player: Player, data: SaveData.Data)
	player:SetAttribute("ConeLevel", data.upgrades.cone)
	player:SetAttribute("SneakersLevel", data.upgrades.sneakers)
	player:SetAttribute("CartLevel", data.upgrades.cart)
	player:SetAttribute("ScoopsServed", data.scoopsServed)
	player:SetAttribute("FlavorsCollected", SaveData.flavorsCollected(data))
end

local function loaded(player: Player, data: SaveData.Data)
	publish(player, data)
	player:SetAttribute("SaveState", "loaded")
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, data)
	end
end

local function onPlayer(player: Player)
	player:SetAttribute("SaveState", "loading")
	local profile = store:StartSessionAsync(SaveConfig.keyPrefix .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if not profile then
		if player.Parent == Players then
			warn(`[Data] could not load {player.Name}'s save; kicked, nothing written`)
			player:Kick(SaveConfig.loadFailedMessage)
		end
		return
	end

	profile:AddUserId(player.UserId) -- GDPR: the profile can be found and erased by UserId
	profile:Reconcile()
	local _, repaired = SaveData.migrate(profile.Data, EconomyConfig)
	if repaired then
		print(`[Data] {player.Name}'s save was repaired or migrated to version {SaveData.VERSION}`)
	end

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick(SaveConfig.sessionEndedMessage)
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession() -- left while loading
		return
	end
	profiles[player] = profile
	loaded(player, profile.Data)
end

local function isAdmin(userId: number): boolean
	return table.find(SaveConfig.admins, userId) ~= nil
end

-- /resetsave: an admin's own save back to the template, Studio only.
local function setUpResetCommand()
	if not RunService:IsStudio() then
		return
	end
	local command = Instance.new("TextChatCommand")
	command.Name = "ResetSaveCommand"
	command.PrimaryAlias = SaveConfig.resetCommand
	command.Parent = TextChatService
	command.Triggered:Connect(function(source: TextSource)
		local player = Players:GetPlayerByUserId(source.UserId)
		if not player then
			return
		end
		if not isAdmin(player.UserId) then
			print(`[Data] {player.Name} ({player.UserId}) may not reset saves; add the UserId to Config/Save.admins`)
			return
		end
		if DataService.reset(player) then
			print(`[Data] {player.Name}'s save was reset`)
		end
	end)
end

function DataService.Init()
	store = ProfileStore.New(storeName(), SaveData.template())
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		profiles[player] = nil
		if profile then
			profile:EndSession()
		end
	end)
	setUpResetCommand()

	task.spawn(function()
		while ProfileStore.DataStoreState == "NotReady" do
			task.wait()
		end
		if ProfileStore.DataStoreState == "Access" then
			print(`[Data] saving to the DataStore "{storeName()}"`)
		else
			warn(
				`[Data] no DataStore access ({ProfileStore.DataStoreState}): saves stay in memory and are lost when `
					.. "the server stops. In Studio: Game Settings > Security > Enable Studio Access to API Services"
			)
		end
	end)
end

-- Runs `callback(player, data)` once a player's save is loaded (also for players whose save loaded earlier).
function DataService.onLoaded(callback: (player: Player, data: SaveData.Data) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile.Data)
	end
end

-- The player's save, or nil while it is loading (or never loaded).
function DataService.data(player: Player): SaveData.Data?
	local profile = profiles[player]
	return if profile and profile:IsActive() then profile.Data else nil
end

-- A served tower: coins, scoop count, flavors and record. Returns false when the save is not loaded.
function DataService.recordServe(player: Player, scoops: { string }, value: number): boolean
	local data = DataService.data(player)
	if not data then
		return false
	end
	SaveData.recordServe(data, scoops, value)
	publish(player, data)
	return true
end

-- Back to the template, saved right away, and every listener hears it like a fresh load.
function DataService.reset(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end
	local fresh = SaveData.template()
	for key in profile.Data do
		profile.Data[key] = nil
	end
	for key, value in fresh do
		profile.Data[key] = value
	end
	profile:Save()
	loaded(player, profile.Data)
	return true
end

return DataService
