-- The upgrade shop (Config/Upgrades, the rules in Upgrades): the server decides every purchase, the client only shows.
--   Buying     UpgradeBuy(id, fromLevel): at the shop (buyDistance), a known, sold upgrade, the level still
--              `fromLevel`, not at the top, enough coins. Then the coins go, the level rises, everything that depends
--              on it is applied and the save is written within Config/Upgrades.saveDelay. The answer is
--              UpgradeResult; the levels are the player's Upgrade_<id> attributes (DataService).
--              A double click sends the same fromLevel twice: the second finds the level raised and is refused as
--              "stale". Requests closer together than buyInterval are dropped (spam).
--   Effects    cone and cart: TowerService (capacity, serve multiplier); stability: the client's tower model reads
--              Upgrade_stability; luck: the luck source "upgrade" (LuckService, its cap in Config/Luck); slots:
--              ChestService.
--   Shop       a prompt "Upgrades" on the Teleport_Upgrade parts in the hub (ArenaService.shopParts); the client
--              opens the window when it is triggered, and only there (the HUD's UPGRADES button teleports to the shop
--              by the rules of every teleport, TeleportRules; walking away closes the window).
--   Rebirth    UpgradeService.resetAll(player) puts every level back to 0 in one call (SaveData.resetUpgrades).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))
local SaveData = require(Shared:WaitForChild("SaveData"))
local UpgradesConfig = require(Config:WaitForChild("Upgrades"))

local UpgradeService = {}

local PROMPT_NAME = "UpgradeShopPrompt"

local registry
local lastBuyAt: { [Player]: number } = {}

-- Everything that depends on the levels follows the save again.
local function apply(player: Player)
	registry.DataService.publish(player)
	registry.TowerService.refresh(player)
	registry.ChestService.refresh(player)
end

-- Whether the player stands within `radius` studs of an Upgrade shop (its Teleport_Upgrade parts, on the ground plane).
function UpgradeService.atShop(player: Player, radius: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, part in registry.ArenaService.shopParts("upgrades") do
		local offset = root.Position - part.Position
		if Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius then
			return true
		end
	end
	return false
end

local function onBuy(player: Player, id: any, fromLevel: any)
	local now = os.clock()
	if now - (lastBuyAt[player] or -math.huge) < UpgradesConfig.buyInterval then
		return -- spam: dropped without an answer
	end
	lastBuyAt[player] = now
	if type(id) ~= "string" or #id > 40 then
		return
	end
	local data = registry.DataService.data(player)
	if not data then
		Remotes.UpgradeResult:FireClient(player, id, false, "loading")
		return
	end
	if not UpgradeService.atShop(player, UpgradesConfig.buyDistance) then
		Remotes.UpgradeResult:FireClient(player, id, false, "far")
		return
	end
	local ok, result, cost = Upgrades.buy(data, id, fromLevel, UpgradesConfig)
	if not ok then
		Remotes.UpgradeResult:FireClient(player, id, false, result)
		return
	end
	apply(player)
	registry.DataService.saveSoon(player, UpgradesConfig.saveDelay)
	print(`[Upgrade] {player.Name} bought {id} level {result} for {cost} coins`)
	Remotes.UpgradeResult:FireClient(player, id, true, result, cost)
end

-- Every upgrade of the player back to level 0 (for the rebirth), applied at once and saved soon. Returns whether the
-- save was loaded.
function UpgradeService.resetAll(player: Player): boolean
	local data = registry.DataService.data(player)
	if not data then
		return false
	end
	SaveData.resetUpgrades(data, UpgradesConfig)
	apply(player)
	registry.DataService.saveSoon(player, UpgradesConfig.saveDelay)
	return true
end

-- The player's level of an upgrade (0 while the save loads).
function UpgradeService.level(player: Player, id: string): number
	local data = registry.DataService.data(player)
	return Upgrades.levelOf(data and data.upgrades, id, UpgradesConfig)
end

-- The prompt at the Upgrade shop: on every target part of the shop's teleport (in front of its counter), on an
-- attachment Config/Upgrades.promptHeight studs above it (the part lies at the feet, the prompt hid behind them).
local function addPrompts()
	for _, part in registry.ArenaService.shopParts("upgrades") do
		if part:FindFirstChild(PROMPT_NAME, true) then
			continue
		end
		local holder = Instance.new("Attachment")
		holder.Name = "UpgradeShopPromptAt"
		holder.Position = Vector3.new(0, UpgradesConfig.promptHeight, 0)
		holder.Parent = part
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.ActionText = "Upgrades"
		prompt.ObjectText = "Upgrade Shop"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = UpgradesConfig.promptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = holder
	end
end

function UpgradeService.Init(reg)
	registry = reg
	-- the luck upgrade is one of the luck sources (its cap: Config/Luck.sources.upgrade)
	reg.LuckService.register("upgrade", function(player: Player): number
		return Upgrades.value("luck", UpgradeService.level(player, "luck"), UpgradesConfig)
	end)
end

function UpgradeService.Start()
	Remotes.UpgradeBuy.OnServerEvent:Connect(onBuy)
	Players.PlayerRemoving:Connect(function(player)
		lastBuyAt[player] = nil
	end)
	addPrompts()

	-- Studio only: ServerStorage.StudioUpgradeTest for playtests (Studio MCP, command bar): ("coins", player, n) gives
	-- coins, ("reset", player) runs resetAll, ("get", player) returns the levels and the coins.
	if RunService:IsStudio() then
		local test = Instance.new("BindableFunction")
		test.Name = "StudioUpgradeTest"
		test.OnInvoke = function(action: string, player: Player, amount: number?)
			local data = registry.DataService.data(player)
			if not data then
				return nil
			end
			if action == "coins" and amount then
				registry.TowerService.addCoins(player, amount)
			elseif action == "reset" then
				UpgradeService.resetAll(player)
			end
			return { coins = data.coins, upgrades = table.clone(data.upgrades), equipped = #data.chest.equipped }
		end
		test.Parent = game:GetService("ServerStorage")
	end
end

return UpgradeService
