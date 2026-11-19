--!strict
-- Luck from several sources (Config/Luck): each source held at its own cap, the sum at the total cap. Pure: no
-- Roblox globals, no requires; the config comes in as an argument. Services/LuckService collects the sources.

local Luck = {}

export type Config = {
	totalCap: number,
	sources: { [string]: { cap: number } },
}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- The luck of a player from the sources' raw values (name -> 0.05 = +5 %): each held at 0..its cap (a source not in
-- the config, or a value that is no number, counts 0), the sum at 0..totalCap. Returns the total and each source as
-- it counted.
function Luck.total(values: { [string]: number }, config: Config): (number, { [string]: number })
	local counted: { [string]: number } = {}
	local sum = 0
	for name, value in values do
		local source = config.sources[name]
		local part = if source and finite(value) then math.clamp(value, 0, source.cap) else 0
		counted[name] = part
		sum += part
	end
	return math.clamp(sum, 0, config.totalCap), counted
end

return Luck
