-- The Scoop Chest on every plot (Config/Chest, the rules in ScoopChest): the server decides everything, the client
-- only shows it.
--   Opening   the owner's chest opens when they come within openRadius of it and shuts beyond closeRadius. The
--             server publishes it as the attribute ChestOpen on their plot (Workspace.Pier.Plots.Plot_NN, always
--             streamed); every client turns the lid and plays the sparkle from it, so others see it open but cannot
--             open it.
--   Storing   at a serve TowerService asks `serve`: the rare scoops (and every one with a mutation) go into the save's
--             chest while there is room, the rest is sold.
--   Window    ChestAction (sync, equip, unequip, sell), checked and rate-limited; every change answers with
--             ChestChanged (the whole chest as the window shows it).
--   Passives  the bonuses of the equipped scoops, summed and capped (ScoopChest.bonuses), published as the attributes
--             Passive<Kind> (PassiveCoins, PassiveLuck, PassiveTower); TowerService reads coins and tower through
--             `bonus`, the luck goes to LuckService as the source "chest".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ScoopChest = require(Shared:WaitForChild("ScoopChest"))
local SaveData = require(Shared:WaitForChild("SaveData"))
local ChestConfig = require(Config:WaitForChild("Chest"))
local UpgradesConfig = require(Config:WaitForChild("Upgrades"))
local Flavors = require(Config:WaitForChild("Flavors"))
local Features = require(Config:WaitForChild("Features"))

local ChestService = {}

-- the attribute of every passive kind: Passive<Kind>
local ATTRIBUTES: { [string]: string } = {}
for kind in ChestConfig.passives.kinds do
	ATTRIBUTES[kind] = "Passive" .. string.upper(string.sub(kind, 1, 1)) .. string.sub(kind, 2)
end
local ACTIONS = { sync = true, equip = true, unequip = true, sell = true, sellMany = true }
local MAX_KEY_LENGTH = 80
local MAX_SELL = 1000

local registry
local lastActionAt: { [Player]: number } = {}
local bonuses: { [Player]: { [string]: number } } = {}

local function chestData(player: Player): ScoopChest.Chest?
	local data = registry.DataService.data(player)
	return data and data.chest
end

-- How many scoops the player may equip: Config/Chest.equipSlots at the start, more with the Equip Slots upgrade
-- (Config/Upgrades tracks.slots, SaveData.equipSlots).
local function slotsOf(player: Player): number
	local data = registry.DataService.data(player)
	return if data then SaveData.equipSlots(data, UpgradesConfig) else ChestConfig.equipSlots
end

-- Config/Chest with the player's own number of slots (one copy per slot count).
local slotConfigs: { [number]: any } = {}
local function configFor(player: Player): any
	local slots = slotsOf(player)
	if slots == ChestConfig.equipSlots then
		return ChestConfig
	end
	local config = slotConfigs[slots]
	if not config then
		config = table.clone(ChestConfig)
		config.equipSlots = slots
		slotConfigs[slots] = config
	end
	return config
end

-- The chest as the window shows it: the stacks in display order with everything the window prints, the equipped keys,
-- the room and the bonuses with their caps. Everything is worked out here, the client does no sums.
function ChestService.snapshot(player: Player): { [string]: any }?
	local chest = chestData(player)
	if not chest then
		return nil
	end
	local items = {}
	for _, item in ScoopChest.sorted(chest, Flavors.byId, Flavors.rarities, ChestConfig) do
		local flavor = Flavors.byId[item.flavor]
		local key = ScoopChest.key(item.flavor, item.mutation)
		local kind, amount = ScoopChest.passiveOf(item, Flavors.byId, ChestConfig)
		table.insert(items, {
			key = key,
			flavor = item.flavor,
			name = if flavor then flavor.name else item.flavor,
			color = if flavor then flavor.color else "#FFFFFF",
			rarity = ScoopChest.rarityOf(item, Flavors.byId),
			mutation = item.mutation,
			count = item.count,
			passive = kind,
			amount = amount,
			sellValue = ScoopChest.sellValue(item, Flavors.byId, ChestConfig),
			equipped = table.find(chest.equipped, key) ~= nil,
		})
	end
	return {
		items = items,
		equipped = table.clone(chest.equipped),
		used = ScoopChest.used(chest),
		capacity = ChestConfig.capacity,
		slots = slotsOf(player),
		bonuses = ScoopChest.bonuses(chest, Flavors.byId, configFor(player)),
		minRarity = ChestConfig.minRarity,
	}
end

local function publishBonuses(player: Player)
	local chest = chestData(player)
	local totals = if chest then ScoopChest.bonuses(chest, Flavors.byId, configFor(player)) else {}
	bonuses[player] = totals
	for kind, attribute in ATTRIBUTES do
		player:SetAttribute(attribute, totals[kind] or 0)
	end
end

local function send(player: Player, event: { [string]: any }?)
	local snapshot = ChestService.snapshot(player)
	if snapshot then
		Remotes.ChestChanged:FireClient(player, snapshot, event)
	end
end

local function nearOwnChest(player: Player, radius: number): boolean
	local plot = registry.PlotService.ownedPlot(player)
	local chest = plot and registry.PlotService.chestOf(plot)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not chest or not root then
		return false
	end
	local at = chest:GetPivot().Position
	return Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z).Magnitude <= radius
end

-- The window's sell filter, checked: known rarities only, two flags; nil when it is anything else.
local function readFilter(value: any): ScoopChest.SellFilter?
	if type(value) ~= "table" or type(value.rarities) ~= "table" then
		return nil
	end
	local rarities = {}
	local count = 0
	for _, rarity in value.rarities do
		count += 1
		if count > #Flavors.rarities or type(rarity) ~= "string" or not table.find(Flavors.rarities, rarity) then
			return nil
		end
		rarities[rarity] = true
	end
	return {
		rarities = rarities,
		mutations = value.mutations == true,
		keepOne = value.keepOne ~= false,
	}
end

local function onAction(player: Player, action: any, key: any, amount: any)
	if type(action) ~= "string" or not ACTIONS[action] then
		return
	end
	local now = os.clock()
	if now - (lastActionAt[player] or -math.huge) < ChestConfig.actionInterval then
		return
	end
	lastActionAt[player] = now
	local chest = chestData(player)
	if not chest or not Features.scoopChest then
		return
	end
	if action == "sync" then
		send(player, nil)
		return
	end
	if action == "sellMany" then
		-- selling by a filter (the window's SELL...): { rarities = { "rare", ... }, mutations = bool, keepOne = bool }
		local filter = readFilter(key)
		if not filter then
			return
		end
		if not nearOwnChest(player, ChestConfig.actionRadius) then
			send(player, { kind = "refused", reason = "far" })
			return
		end
		local coins, count = ScoopChest.sellFiltered(chest, filter, Flavors.byId, ChestConfig)
		if count <= 0 then
			send(player, { kind = "refused", reason = "nothing" })
			return
		end
		registry.TowerService.addCoins(player, coins)
		publishBonuses(player)
		send(player, { kind = "sold", coins = coins, count = count })
		return
	end
	if type(key) ~= "string" or #key == 0 or #key > MAX_KEY_LENGTH then
		return
	end
	if not nearOwnChest(player, ChestConfig.actionRadius) then
		send(player, { kind = "refused", reason = "far" })
		return
	end

	if action == "equip" then
		local ok, reason = ScoopChest.equip(chest, key, configFor(player))
		if ok then
			publishBonuses(player)
		end
		send(player, if ok then { kind = "equipped", key = key } else { kind = "refused", reason = reason })
	elseif action == "unequip" then
		local ok = ScoopChest.unequip(chest, key)
		if ok then
			publishBonuses(player)
		end
		send(player, if ok then { kind = "unequipped", key = key } else { kind = "refused", reason = "unknown" })
	elseif action == "sell" then
		local count = if amount == nil then 1 else amount
		if type(count) ~= "number" or count ~= count or count < 1 or count > MAX_SELL then
			return
		end
		local coins, reason = ScoopChest.sell(chest, key, math.floor(count), Flavors.byId, ChestConfig)
		if not coins then
			send(player, { kind = "refused", reason = reason })
			return
		end
		registry.TowerService.addCoins(player, coins)
		publishBonuses(player) -- the last one of an equipped stack leaves its slot
		send(player, { kind = "sold", coins = coins })
	end
end

-- Opens and shuts every owner's chest by how close they stand (hysteresis between openRadius and closeRadius).
local function checkOpen()
	for _, player in Players:GetPlayers() do
		local plot = registry.PlotService.ownedPlot(player)
		if not plot then
			continue
		end
		local open = plot:GetAttribute("ChestOpen") == true
		local wanted = if open
			then nearOwnChest(player, ChestConfig.closeRadius)
			else nearOwnChest(player, ChestConfig.openRadius)
		if wanted ~= open then
			plot:SetAttribute("ChestOpen", wanted)
		end
	end
end

-- A served tower: the scoops that go into the chest (ScoopChest.store) and what was stored, for TowerService; tells the
-- owner. Returns nil when the chest is off or the save is not loaded (everything is sold then).
function ChestService.serve(
	player: Player,
	scoops: { string },
	mutations: { [number]: string }?
): ScoopChest.StoreResult?
	local chest = chestData(player)
	if not chest or not Features.scoopChest then
		return nil
	end
	-- the flavors served before count as had (the save's flavorServes; this serve is recorded after the chest)
	local data = registry.DataService.data(player)
	local seen = if data then data.flavorServes else nil
	local result = ScoopChest.store(chest, scoops, mutations, Flavors.byId, Flavors.rarities, ChestConfig, seen)
	if #result.stored > 0 or result.overflow > 0 or #result.capped > 0 then
		send(player, { kind = "stored", stored = result.stored, overflow = result.overflow, capped = result.capped })
	end
	return result
end

-- The player's slots changed (Equip Slots bought or reset): bonuses and the window again.
function ChestService.refresh(player: Player)
	publishBonuses(player)
	send(player, nil)
end

-- The player's bonus of a passive kind ("coins", "luck", "tower"), 0..its cap.
function ChestService.bonus(player: Player, kind: string): number
	if not Features.scoopChest then
		return 0
	end
	local totals = bonuses[player]
	return totals and totals[kind] or 0
end

function ChestService.Init(reg)
	registry = reg
	-- the equipped luck scoops are one of the luck sources
	reg.LuckService.register("chest", function(player: Player): number
		return ChestService.bonus(player, "luck")
	end)
end

function ChestService.Start()
	registry.DataService.onLoaded(function(player)
		publishBonuses(player)
		send(player, nil)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastActionAt[player] = nil
		bonuses[player] = nil
		local plot = registry.PlotService.ownedPlot(player)
		if plot then
			plot:SetAttribute("ChestOpen", false)
		end
	end)
	Remotes.ChestAction.OnServerEvent:Connect(onAction)

	if Features.scoopChest then
		local since = 0
		RunService.Heartbeat:Connect(function(dt)
			since += dt
			if since >= ChestConfig.checkInterval then
				since = 0
				checkOpen()
			end
		end)
	end

	-- Studio only: ServerStorage.StudioChestTest lets a playtest (Studio MCP, command bar) look into a chest and fill
	-- it without serving: ("add", player, flavorId, mutation, count) puts scoops in (also with a mutation, which the
	-- Big Swirl does not fire yet), ("clear", player) empties it, ("get", player) returns the snapshot.
	if RunService:IsStudio() then
		local test = Instance.new("BindableFunction")
		test.Name = "StudioChestTest"
		test.OnInvoke = function(action: string, player: Player, flavorId: string?, mutation: string?, count: number?)
			local chest = chestData(player)
			if not chest then
				return nil
			end
			if action == "add" and flavorId then
				for _ = 1, count or 1 do
					ScoopChest.add(chest, flavorId, mutation, Flavors.byId, ChestConfig)
				end
			elseif action == "clear" then
				table.clear(chest.items)
				table.clear(chest.equipped)
			end
			publishBonuses(player)
			send(player, nil)
			return ChestService.snapshot(player)
		end
		test.Parent = game:GetService("ServerStorage")
	end
end

return ChestService
