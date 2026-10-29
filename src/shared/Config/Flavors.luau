--!strict
-- Every flavor in the game. Values and physics modifiers live here so a new family is a data change, not a code change.
-- Since 29.10.2026 only the eleven common classics; the rarer flavors (uncommon to legendary) are new designs that
-- come later. The families heavy, sticky and wild stay for them.

export type Family = "classic" | "heavy" | "sticky" | "wild"
-- how rare a flavor is for the player (trail, later the collection book); the launcher odds are `weight`
export type Rarity = "common" | "uncommon" | "rare" | "epic" | "legendary"

export type Flavor = {
	id: string,
	name: string,
	family: Family,
	rarity: Rarity,
	value: number, -- coins before the height multiplier
	mass: number, -- weights the centre of mass: heavy scoops low = stable, heavy scoops high = wobbly
	stiffness: number, -- added to the tower's restoring stiffness
	damping: number, -- added to damping, negative makes the tower bouncier
	jerk: number, -- strength of the random kicks a scoop adds (cursed pickle)
	weight: number, -- launcher spawn weight
	color: string, -- hex, see Palette for the shared tokens
	material: string, -- Enum.Material name, also used so flavors differ for colorblind players
}

local list: { Flavor } = {
	{
		id = "vanilla",
		name = "Vanilla",
		family = "classic",
		rarity = "common",
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#F9DCA8", -- warmer than Palette.vanilla, which reads almost white on the island (29.10.2026)
		material = "SmoothPlastic",
	},
	{
		id = "chocolate",
		name = "Chocolate",
		family = "classic",
		rarity = "common",
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#6A3F2A",
		material = "SmoothPlastic",
	},
	{
		id = "strawberry",
		name = "Strawberry",
		family = "classic",
		rarity = "common",
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#FF8FA3",
		material = "SmoothPlastic",
	},
	{
		id = "mint",
		name = "Mint",
		family = "classic",
		rarity = "common",
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#9DE0C4",
		material = "SmoothPlastic",
	},
	-- the common flavors added on 29.10.2026: classics with the same values and physics as vanilla; each one tells
	-- itself apart by its tower scoop model's details too (assets/TowerScoops), not only by its colour
	{
		id = "lemon",
		name = "Lemon",
		family = "classic",
		rarity = "common",
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#FFD84A", -- stronger than at first, so it does not read as vanilla from afar
		material = "SmoothPlastic",
	},
	{
		id = "bubblegum",
		name = "Bubblegum",
		family = "classic",
		rarity = "common",
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#FF8AD8",
		material = "SmoothPlastic",
	},
	{
		id = "cookie",
		name = "Cookie",
		family = "classic",
		rarity = "common",
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#C9976A",
		material = "SmoothPlastic",
	},
	{
		id = "pistachio",
		name = "Pistachio",
		family = "classic",
		rarity = "common",
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#B9D98C",
		material = "SmoothPlastic",
	},
	{
		id = "mango",
		name = "Mango",
		family = "classic",
		rarity = "common",
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#FFA53D",
		material = "SmoothPlastic",
	},
	{
		id = "stracciatella",
		name = "Stracciatella",
		family = "classic",
		rarity = "common",
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#FFF6E8",
		material = "SmoothPlastic",
	},
	{
		id = "watermelon",
		name = "Watermelon",
		family = "classic",
		rarity = "common",
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#F2545B",
		material = "SmoothPlastic",
	},
}

local byId: { [string]: Flavor } = {}
for _, flavor in list do
	byId[flavor.id] = flavor
end

return {
	list = list,
	byId = byId,
	-- the colour of a rarity, e.g. for the name over a scoop in flight or on the ground (ScoopLabel); golden its own
	rarityColors = {
		common = "#FFFFFF",
		uncommon = "#7CE07C",
		rare = "#5DB4FF",
		epic = "#C77DFF",
		legendary = "#FF9F1C",
		golden = "#FFD23F",
	},
}
