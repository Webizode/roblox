--!strict
-- What the name sign over a scoop in flight or on the ground says (Config/TowerScoops label): the flavor's name in its
-- rarity's colour and its value in coins, e.g. "Vanilla (5 [coin])". A golden scoop is "Golden ..." in gold and shows
-- what it is really worth. Pure: the configs are passed in.

export type Label = {
	name: string,
	value: string, -- the number only; the coin symbol is drawn next to it
	color: string, -- hex
}

local ScoopLabel = {}

-- "5", "7.5", "37.5": whole numbers without decimals, the rest with one.
function ScoopLabel.number(value: number): string
	if math.abs(value - math.round(value)) < 1e-6 then
		return tostring(math.round(value))
	end
	return string.format("%.1f", value)
end

function ScoopLabel.text(flavor: any, golden: boolean, flavors: any, economy: any): Label
	local value = flavor.value * (if golden then economy.goldenMultiplier else 1)
	local color = flavors.rarityColors[if golden then "golden" else flavor.rarity] or flavors.rarityColors.common
	return {
		name = if golden then `Golden {flavor.name}` else flavor.name,
		value = ScoopLabel.number(value),
		color = color,
	}
end

return ScoopLabel
