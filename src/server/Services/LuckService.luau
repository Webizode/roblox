-- Luck in one place (Config/Luck, the sums in Luck.total): every luck source registers here with a function that
-- gives a player's luck from it, and everything that rolls for luck asks here. So far only the Scoop Chest registers
-- ("chest", ChestService); friends, group, upgrade, potion, server luck and events come later the same way.
--   LuckService.register("potion", function(player) return 0.1 end)
-- Luck only changes what the catcher gets: a caught scoop may turn into one of the next rarer rarity
-- (ScoopChest.luckyFlavor). The Big Swirl fires the same for everybody.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Luck = require(Shared:WaitForChild("Luck"))
local ScoopChest = require(Shared:WaitForChild("ScoopChest"))
local LuckConfig = require(Config:WaitForChild("Luck"))
local Flavors = require(Config:WaitForChild("Flavors"))
local Features = require(Config:WaitForChild("Features"))

local LuckService = {}

local sources: { [string]: (Player) -> number } = {}
local forced: { [Player]: number } = {} -- Studio only (StudioLuckTest)
local rng = Random.new()

-- the flavors luck may turn a scoop into: those the Big Swirl fires
local pool: { { id: string, rarity: string, weight: number } } = {}
for _, flavor in Flavors.list do
	if not flavor.placeholder or Features.placeholderRares then
		table.insert(pool, { id = flavor.id, rarity = flavor.rarity, weight = flavor.weight })
	end
end

-- A luck source: `get(player)` gives that player's luck from it (0.05 = +5 %). Its cap is in Config/Luck.sources; a
-- source without one counts nothing (and is reported once).
function LuckService.register(name: string, get: (Player) -> number)
	if not LuckConfig.sources[name] then
		warn(`[Luck] the source {name} has no cap in Config/Luck, it counts nothing`)
	end
	sources[name] = get
end

-- The player's luck from all sources, each at its cap, the sum at the total cap; and each source as it counted.
function LuckService.luck(player: Player): (number, { [string]: number })
	if forced[player] then
		return forced[player], { studio = forced[player] }
	end
	local values = {}
	for name, get in sources do
		local ok, value = pcall(get, player)
		values[name] = if ok and type(value) == "number" then value else 0
	end
	return Luck.total(values, LuckConfig)
end

-- A caught scoop: the id of the rarer flavor luck turns it into, or nil.
function LuckService.luckyFlavor(player: Player, flavorId: string): string?
	local luck = LuckService.luck(player)
	if luck <= 0 then
		return nil
	end
	return ScoopChest.luckyFlavor(
		flavorId,
		luck,
		rng:NextNumber(),
		rng:NextNumber(),
		pool,
		Flavors.byId,
		Flavors.rarities
	)
end

function LuckService.Start()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		forced[player] = nil
	end)
	-- Studio only: ServerStorage.StudioLuckTest(player, luck) sets a player's luck to that value whatever the sources
	-- say (1 = every catch turns rarer), nil goes back to the sources; it returns the luck in use. For playtests.
	if RunService:IsStudio() then
		local test = Instance.new("BindableFunction")
		test.Name = "StudioLuckTest"
		test.OnInvoke = function(player: Player, luck: number?)
			forced[player] = if type(luck) == "number" then math.clamp(luck, 0, 1) else nil
			return (LuckService.luck(player))
		end
		test.Parent = game:GetService("ServerStorage")
	end
end

return LuckService
