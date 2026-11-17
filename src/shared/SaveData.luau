--!strict
-- What a player's save holds and how it changes. Pure: the economy config and the flavor list are passed in, so the
-- rules run in the Lune tests. DataService keeps the data in a ProfileStore profile.
--
-- Every save carries `version`. A new field gets a default in template() and, if old saves need more than that
-- default, a step in MIGRATIONS that lifts version n to n + 1. Saves are never thrown away: missing or broken
-- fields are repaired from the template.

export type Upgrades = { cone: number, sneakers: number, cart: number }

export type Data = {
	version: number,
	coins: number,
	upgrades: Upgrades,
	flavorServes: { [string]: number }, -- scoops of each flavor ever served; an entry means "in the flavor book"
	scoopsServed: number, -- all scoops ever served, the base of the Cone Rank
	bestTower: number, -- the tallest tower ever served
	settings: { [string]: any }, -- the settings menu (since version 2); checked against Config/Settings by DataService
	-- the Scoop Chest (since version 3, ScoopChest): stacks of stored scoops and the keys of the equipped ones
	chest: {
		items: { { flavor: string, rarity: string, mutation: string, count: number } },
		equipped: { string },
	},
}

export type EconomyConfig = {
	upgrades: { [string]: { costs: { number } } },
}

local SaveData = {}

SaveData.VERSION = 3

-- equipped slots kept when a save is repaired and no chest config is passed (Config/Chest.equipSlots)
local DEFAULT_EQUIP_SLOTS = 3

local UPGRADES = { "cone", "sneakers", "cart" }

-- Steps from version n to n + 1, run in order on older saves.
local MIGRATIONS: { [number]: (data: { [string]: any }) -> () } = {
	-- 1 -> 2: the settings menu. An empty table means "all defaults"; DataService fills it in from Config/Settings.
	[1] = function(data)
		if type(data.settings) ~= "table" then
			data.settings = {}
		end
	end,
	-- 2 -> 3: the Scoop Chest, empty
	[2] = function(data)
		if type(data.chest) ~= "table" then
			data.chest = { items = {}, equipped = {} }
		end
	end,
}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function count(value: any): number
	return if isFinite(value) then math.max(0, math.floor(value)) else 0
end

function SaveData.template(): Data
	return {
		version = SaveData.VERSION,
		coins = 0,
		upgrades = { cone = 0, sneakers = 0, cart = 0 },
		flavorServes = {},
		scoopsServed = 0,
		bestTower = 0,
		settings = {},
		chest = { items = {}, equipped = {} },
	}
end

-- Repairs the chest in place: valid stacks only (a flavor, a rarity, a mutation string, a whole count of at least 1;
-- stacks of the same flavor and mutation merged), equipped keys only for stacks that exist, each once, at most
-- `slots`. Flavors that left the game stay, like in flavorServes. Nothing is cut for the capacity: a smaller capacity
-- only stops new scoops. Returns whether anything changed.
local function repairChest(data: { [string]: any }, slots: number): boolean
	local changed = false
	if type(data.chest) ~= "table" then
		data.chest = {}
		changed = true
	end
	local chest = data.chest
	if type(chest.items) ~= "table" then
		chest.items = {}
		changed = true
	end
	if type(chest.equipped) ~= "table" then
		chest.equipped = {}
		changed = true
	end

	local items = {}
	local byKey: { [string]: any } = {}
	for _, item in chest.items do
		local ok = type(item) == "table"
			and type(item.flavor) == "string"
			and item.flavor ~= ""
			and type(item.rarity) == "string"
			and isFinite(item.count)
			and item.count >= 1
		if not ok then
			changed = true
			continue
		end
		local mutation = if type(item.mutation) == "string" then item.mutation else ""
		local amount = math.floor(item.count)
		if mutation ~= item.mutation or amount ~= item.count then
			changed = true
		end
		local key = item.flavor .. "|" .. mutation
		local existing = byKey[key]
		if existing then
			existing.count += amount
			changed = true
		else
			local clean = { flavor = item.flavor, rarity = item.rarity, mutation = mutation, count = amount }
			byKey[key] = clean
			table.insert(items, clean)
		end
	end
	if #items ~= #chest.items then
		changed = true
	end
	chest.items = items

	local equipped = {}
	for _, key in chest.equipped do
		if type(key) == "string" and byKey[key] and not table.find(equipped, key) and #equipped < slots then
			table.insert(equipped, key)
		else
			changed = true
		end
	end
	chest.equipped = equipped
	return changed
end

-- The highest level of an upgrade path (Config/Economy: one cost per level after 0).
function SaveData.maxLevel(path: string, economy: EconomyConfig): number
	local upgrade = economy.upgrades[path]
	return if upgrade then #upgrade.costs else 0
end

-- Brings any loaded table to the current version and repairs what is broken: unknown versions are treated as the
-- oldest, numbers become finite and non-negative, levels stay within the config. Returns the data (the same table,
-- changed in place) and whether it had to be repaired or migrated, for the log. `chestSlots`: Config/Chest.equipSlots.
function SaveData.migrate(raw: any, economy: EconomyConfig, chestSlots: number?): (Data, boolean)
	local data: { [string]: any } = if type(raw) == "table" then raw else {}
	local changed = type(raw) ~= "table"

	local version = if isFinite(data.version) then math.floor(data.version) else 1
	if version > SaveData.VERSION then
		-- written by a newer game version: keep every field, only make sure the known ones are usable
		version = SaveData.VERSION
	end
	while version < SaveData.VERSION do
		local step = MIGRATIONS[version]
		if step then
			step(data)
		end
		version += 1
		changed = true
	end
	if data.version ~= version then
		changed = true
	end
	data.version = version

	local coins = if isFinite(data.coins) then math.max(0, data.coins) else 0
	changed = changed or coins ~= data.coins
	data.coins = coins

	if type(data.upgrades) ~= "table" then
		data.upgrades = {}
		changed = true
	end
	for _, path in UPGRADES do
		local level = math.clamp(count(data.upgrades[path]), 0, SaveData.maxLevel(path, economy))
		changed = changed or level ~= data.upgrades[path]
		data.upgrades[path] = level
	end

	if type(data.flavorServes) ~= "table" then
		data.flavorServes = {}
		changed = true
	end
	for flavorId, served in data.flavorServes do
		-- flavors that left the game stay in the save, so they come back if the flavor does
		if type(flavorId) ~= "string" or count(served) == 0 then
			data.flavorServes[flavorId] = nil
			changed = true
		elseif served ~= count(served) then
			data.flavorServes[flavorId] = count(served)
			changed = true
		end
	end

	if type(data.settings) ~= "table" then
		data.settings = {}
		changed = true
	end

	if repairChest(data, chestSlots or DEFAULT_EQUIP_SLOTS) then
		changed = true
	end

	for _, field in { "scoopsServed", "bestTower" } do
		local value = count(data[field])
		changed = changed or value ~= data[field]
		data[field] = value
	end

	return data :: Data, changed
end

-- A tower of `scoops` (flavor ids, bottom to top) was served for `value` coins.
function SaveData.recordServe(data: Data, scoops: { string }, value: number)
	if isFinite(value) and value > 0 then
		data.coins += value
	end
	for _, flavorId in scoops do
		data.flavorServes[flavorId] = (data.flavorServes[flavorId] or 0) + 1
	end
	data.scoopsServed += #scoops
	data.bestTower = math.max(data.bestTower, #scoops)
end

-- How many different flavors were ever served.
function SaveData.flavorsCollected(data: Data): number
	local total = 0
	for _ in data.flavorServes do
		total += 1
	end
	return total
end

return SaveData
