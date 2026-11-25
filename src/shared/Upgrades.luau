--!strict
-- The upgrade shop's rules (Config/Upgrades): an upgrade's value at a level, the price of the next level, whether a
-- purchase goes through (resetting every level for the rebirth: SaveData.resetUpgrades). Pure: the config comes in as an
-- argument, so the rules run in the Lune tests. UpgradeService applies them to the save, the client only shows them.

export type Track = {
	label: string,
	text: string,
	icon: string?,
	color: string,
	format: string,
	unit: string?,
	start: number,
	perLevel: number,
	maxLevel: number,
	-- price of level L -> L + 1: base x growth ^ L; with `bend`, from that level on lateGrowth per level instead
	cost: { base: number, growth: number, bend: number?, lateGrowth: number? },
	hidden: boolean?,
	stiffnessPerLevel: number?,
}

export type Config = {
	order: { string },
	priceDigits: number,
	legacy: { [string]: number }?,
	tracks: { [string]: Track },
	levelCap: { enabled: boolean, base: number, perRebirth: number }?,
}

-- What a purchase reads and changes: the save's coins and levels (SaveData.Data has both), and the rebirths for the
-- level cap (none yet: 0)
export type Wallet = { coins: number, upgrades: { [string]: number }, rebirths: number? }

local Upgrades = {}

local function isWhole(value: any): boolean
	return type(value) == "number" and value == value and value == math.floor(value) and math.abs(value) < 1e9
end

-- The upgrades the shop shows, in order (hidden ones left out).
function Upgrades.visible(config: Config): { string }
	local list = {}
	for _, id in config.order do
		local track = config.tracks[id]
		if track and not track.hidden then
			table.insert(list, id)
		end
	end
	return list
end

-- The highest level of an upgrade (also of a legacy save field); 0 for an unknown one.
function Upgrades.maxLevel(id: string, config: Config): number
	local track = config.tracks[id]
	if track then
		return track.maxLevel
	end
	return if config.legacy and config.legacy[id] then config.legacy[id] else 0
end

-- A level held within 0..maxLevel (anything that is no whole number counts 0).
function Upgrades.clampLevel(id: string, level: any, config: Config): number
	local whole = if type(level) == "number" and level == level then math.floor(level) else 0
	return math.clamp(whole, 0, Upgrades.maxLevel(id, config))
end

-- The level of `id` in a save's upgrade table, clamped.
function Upgrades.levelOf(levels: { [string]: number }?, id: string, config: Config): number
	return Upgrades.clampLevel(id, if levels then levels[id] else 0, config)
end

-- The upgrade's value at `level` (clamped): start + perLevel * level, free of float dust (0.1 * 3 = 0.3).
function Upgrades.value(id: string, level: number, config: Config): number
	local track = config.tracks[id]
	if not track then
		return 0
	end
	local raw = track.start + track.perLevel * Upgrades.clampLevel(id, level, config)
	return math.round(raw * 1e6) / 1e6
end

-- `value` rounded to `digits` leading digits (1234 -> 1200 with 2), at least 1.
function Upgrades.roundPrice(value: number, digits: number): number
	if value ~= value or value <= 1 then
		return 1
	end
	local magnitude = 10 ^ math.max(0, math.floor(math.log10(value)) - (digits - 1))
	return math.max(1, math.round(value / magnitude) * magnitude)
end

-- The price of the step from `level` to level + 1, or nil when the upgrade is maxed (or unknown).
function Upgrades.cost(id: string, level: number, config: Config): number?
	local track = config.tracks[id]
	if not track or not isWhole(level) or level < 0 or level >= track.maxLevel then
		return nil
	end
	local cost = track.cost
	local raw = cost.base * cost.growth ^ level
	if cost.bend and cost.lateGrowth and level > cost.bend then
		-- past the bend the price rises by lateGrowth per level instead
		raw = cost.base * cost.growth ^ cost.bend * cost.lateGrowth ^ (level - cost.bend)
	end
	return Upgrades.roundPrice(raw, config.priceDigits)
end

-- Coins to take an upgrade from level 0 to its top.
function Upgrades.totalCost(id: string, config: Config): number
	local total = 0
	for level = 0, Upgrades.maxLevel(id, config) - 1 do
		total += Upgrades.cost(id, level, config) or 0
	end
	return total
end

-- The highest level of `id` a player with `rebirths` rebirths may buy: maxLevel, or with Config.levelCap enabled
-- levelCap.base + levelCap.perRebirth x rebirths, whichever is lower.
function Upgrades.top(id: string, rebirths: number, config: Config): number
	local top = Upgrades.maxLevel(id, config)
	local cap = config.levelCap
	if not cap or not cap.enabled then
		return top
	end
	local count = if type(rebirths) == "number" and rebirths == rebirths then math.max(0, math.floor(rebirths)) else 0
	return math.min(top, cap.base + cap.perRebirth * count)
end

-- Whether the step of `id` from `fromLevel` may be bought with `coins`: the price, or nil and why:
--   "unknown"  no such upgrade      "hidden"  prepared, not sold yet
--   "stale"    the level is no longer `fromLevel` (a double click, or the window was behind)
--   "max"      already at the top   "coins"   not enough coins
--   "cap"      at the highest level for the player's rebirths (Upgrades.top), below the top
function Upgrades.check(wallet: Wallet, id: any, fromLevel: any, config: Config): (number?, string?)
	if type(id) ~= "string" or not config.tracks[id] then
		return nil, "unknown"
	end
	if config.tracks[id].hidden then
		return nil, "hidden"
	end
	local level = Upgrades.levelOf(wallet.upgrades, id, config)
	if not isWhole(fromLevel) or fromLevel ~= level then
		return nil, "stale"
	end
	local cost = Upgrades.cost(id, level, config)
	if not cost then
		return nil, "max"
	end
	if level >= Upgrades.top(id, wallet.rebirths or 0, config) then
		return nil, "cap"
	end
	if not (wallet.coins >= cost) then
		return nil, "coins"
	end
	return cost, nil
end

-- Buys the next level of `id`, bought from `fromLevel`: takes the coins and raises the level in `wallet`. Returns
-- whether it went through, and the new level and the price, or the reason (Upgrades.check). Nothing changes when it
-- is refused.
function Upgrades.buy(wallet: Wallet, id: any, fromLevel: any, config: Config): (boolean, number | string, number?)
	local cost, reason = Upgrades.check(wallet, id, fromLevel, config)
	if not cost then
		return false, reason or "unknown", nil
	end
	wallet.coins -= cost
	local level = fromLevel + 1
	wallet.upgrades[id] = level
	return true, level, cost
end

-- The lowest level whose value is at least `value` (capped at the top), for lifting old saves.
function Upgrades.levelForAtLeast(id: string, value: number, config: Config): number
	for level = 0, Upgrades.maxLevel(id, config) do
		if Upgrades.value(id, level, config) >= value - 1e-9 then
			return level
		end
	end
	return Upgrades.maxLevel(id, config)
end

-- The cone's stiffness multiplier at a capacity level (TowerModel.params): 1 + stiffnessPerLevel * level.
function Upgrades.stiffness(level: number, config: Config): number
	local track = config.tracks.cone
	local per = if track then track.stiffnessPerLevel or 0 else 0
	return 1 + per * Upgrades.clampLevel("cone", level, config)
end

local function trim(value: number, places: number): string
	local text = string.format(`%.{places}f`, value)
	if string.find(text, "%.") then
		text = string.gsub(string.gsub(text, "0+$", ""), "%.$", "")
	end
	return text
end

-- The value as the card shows it, without its unit: "28", "x1.2", "+4.5%".
function Upgrades.format(id: string, value: number, config: Config): string
	local track = config.tracks[id]
	local format = if track then track.format else "count"
	if format == "times" then
		return "x" .. trim(value, 2)
	elseif format == "percent" then
		return "+" .. trim(value * 100, 1) .. "%"
	end
	return trim(value, 0)
end

-- The card's effect line: "28 -> 31 scoops" (now and after the next purchase), or "50 scoops" at the top. `arrow` is
-- what stands between the two.
function Upgrades.change(id: string, level: number, config: Config, arrow: string?): string
	local track = config.tracks[id]
	local unit = if track and track.unit then " " .. track.unit else ""
	local now = Upgrades.format(id, Upgrades.value(id, level, config), config)
	if Upgrades.clampLevel(id, level, config) >= Upgrades.maxLevel(id, config) then
		return now .. unit
	end
	local after = Upgrades.format(id, Upgrades.value(id, level + 1, config), config)
	return now .. (arrow or " -> ") .. after .. unit
end

return Upgrades
