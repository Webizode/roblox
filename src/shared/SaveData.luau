--!strict
-- What a player's save holds and how it changes. Pure: the upgrade config and the flavor list are passed in, so the
-- rules run in the Lune tests. DataService keeps the data in a ProfileStore profile.
--
-- Every save carries `version`. A new field gets a default in template() and, if old saves need more than that
-- default, a step in MIGRATIONS that lifts version n to n + 1. Saves are never thrown away: missing or broken
-- fields are repaired from the template.

-- an upgrade's level by its id (Config/Upgrades tracks and legacy: cone, stability, cart, luck, slots, sprinkles, bossPower,
-- sneakers); 0 is the start
export type Upgrades = { [string]: number }

export type Data = {
	version: number,
	coins: number,
	upgrades: Upgrades,
	flavorServes: { [string]: number }, -- scoops of each flavor ever served; an entry means "in the flavor book"
	scoopsServed: number, -- all scoops ever served, the base of the Cone Rank
	bestTower: number, -- the tallest tower ever served
	settings: { [string]: any }, -- the settings menu (since version 2); checked against Config/Settings by DataService
	-- the chest window's AUTO SELL (since 25.11.2026, no version step): {} or missing means the defaults; always read
	-- through ScoopChest.readAutoSell, which fills and checks every field
	autoSell: { [string]: any },
	-- the Scoop Chest (since version 3, ScoopChest): stacks of stored scoops and the keys of the equipped ones
	chest: {
		items: { { flavor: string, rarity: string, mutation: string, count: number } },
		equipped: { string },
	},
}

-- Config/Upgrades as far as the save needs it (the levels' range, the equip slots and the cone and cart values for
-- lifting version 3 saves). Pure modules do not require each other, so the few sums needed here are written out.
export type Track = { start: number, perLevel: number, maxLevel: number }
export type UpgradesConfig = {
	tracks: { [string]: Track },
	legacy: { [string]: number }?,
}

local SaveData = {}

SaveData.VERSION = 4

-- equipped slots kept when a save is repaired and no chest config is passed (Config/Chest.equipSlots)
local DEFAULT_EQUIP_SLOTS = 3

-- what the cone and cart levels gave before the shop (Config/Economy until 25.11.2026); a version 3 save's levels are
-- lifted to the lowest new level that gives at least as much
local OLD_CONE_CAPACITY = { 20, 28, 36, 45, 55, 65 }
local OLD_CART_MULTIPLIER = { 1, 1.12, 1.25, 1.38, 1.5, 1.6 }

local function trackValue(track: Track, level: number): number
	return track.start + track.perLevel * level
end

-- The lowest level of `track` whose value reaches `value`, at most its top.
local function levelReaching(track: Track?, value: number): number
	if not track then
		return 0
	end
	for level = 0, track.maxLevel do
		if trackValue(track, level) >= value - 1e-9 then
			return level
		end
	end
	return track.maxLevel
end

local function liftOld(data: { [string]: any }, field: string, old: { number }, upgrades: UpgradesConfig)
	local levels = data.upgrades
	local level = if type(levels) == "table" then levels[field] else nil
	if type(level) ~= "number" or level ~= level or level < 1 then
		return
	end
	local was = old[math.clamp(math.floor(level), 0, #old - 1) + 1]
	levels[field] = levelReaching(upgrades.tracks[field], was)
end

-- Steps from version n to n + 1, run in order on older saves.
local MIGRATIONS: { [number]: (data: { [string]: any }, upgrades: UpgradesConfig) -> () } = {
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
	-- 3 -> 4: the upgrade shop. The cone (capacity) and cart (coins) tracks got new steps: an old level becomes the
	-- lowest new one worth at least as much. The new upgrades start at 0 (filled in by the repair in migrate). The
	-- sneakers (walking speed) were never sold and help in the fight (basic rule): back to 0 (a Studio save had 2).
	[3] = function(data, upgrades)
		liftOld(data, "cone", OLD_CONE_CAPACITY, upgrades)
		liftOld(data, "cart", OLD_CART_MULTIPLIER, upgrades)
		if type(data.upgrades) == "table" then
			data.upgrades.sneakers = 0
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
		upgrades = {
			cone = 0,
			stability = 0,
			cart = 0,
			luck = 0,
			slots = 0,
			sprinkles = 0,
			bossPower = 0,
			sneakers = 0,
		},
		flavorServes = {},
		scoopsServed = 0,
		bestTower = 0,
		settings = {},
		autoSell = {},
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

-- The highest level of an upgrade (Config/Upgrades tracks, or a legacy field); 0 for an unknown one.
function SaveData.maxLevel(path: string, upgrades: UpgradesConfig): number
	local track = upgrades.tracks[path]
	if track then
		return track.maxLevel
	end
	return if upgrades.legacy and upgrades.legacy[path] then upgrades.legacy[path] else 0
end

-- Every upgrade field the save keeps: the shop's tracks and the legacy ones.
local function upgradeFields(upgrades: UpgradesConfig): { string }
	local fields = {}
	for id in upgrades.tracks do
		table.insert(fields, id)
	end
	for id in upgrades.legacy or {} do
		table.insert(fields, id)
	end
	table.sort(fields)
	return fields
end

-- How many Scoop Chest slots the save's Equip Slots level gives (Config/Upgrades tracks.slots; without that track the
-- default 3).
function SaveData.equipSlots(data: { [string]: any }, upgrades: UpgradesConfig): number
	local track = upgrades.tracks.slots
	if not track then
		return DEFAULT_EQUIP_SLOTS
	end
	local level = if type(data.upgrades) == "table" then count(data.upgrades.slots) else 0
	return math.floor(trackValue(track, math.min(level, track.maxLevel)))
end

-- Brings any loaded table to the current version and repairs what is broken: unknown versions are treated as the
-- oldest, numbers become finite and non-negative, levels stay within the config. Returns the data (the same table,
-- changed in place) and whether it had to be repaired or migrated, for the log. `upgrades`: Config/Upgrades (the
-- equipped scoops kept follow the save's Equip Slots level).
function SaveData.migrate(raw: any, upgrades: UpgradesConfig): (Data, boolean)
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
			step(data, upgrades)
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
	for _, path in upgradeFields(upgrades) do
		local level = math.clamp(count(data.upgrades[path]), 0, SaveData.maxLevel(path, upgrades))
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
	-- an old save has none: {} means the defaults (ScoopChest.readAutoSell checks the fields when it is read)
	if type(data.autoSell) ~= "table" then
		data.autoSell = {}
		changed = true
	end

	if repairChest(data, SaveData.equipSlots(data, upgrades)) then
		changed = true
	end

	for _, field in { "scoopsServed", "bestTower" } do
		local value = count(data[field])
		changed = changed or value ~= data[field]
		data[field] = value
	end

	return data :: Data, changed
end

-- Every upgrade back to level 0, for the rebirth (UpgradeService.resetAll applies it to a player). The chest keeps
-- its scoops; only equipped ones beyond the slots left are taken off. Returns whether anything changed.
function SaveData.resetUpgrades(data: Data, upgrades: UpgradesConfig): boolean
	local changed = false
	for id, level in data.upgrades do
		if level ~= 0 then
			data.upgrades[id] = 0
			changed = true
		end
	end
	local slots = SaveData.equipSlots(data, upgrades)
	while #data.chest.equipped > slots do
		table.remove(data.chest.equipped)
		changed = true
	end
	return changed
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
