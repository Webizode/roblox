--!strict
-- Every flavor in the game. Values and physics modifiers live here so a new family is a data change, not a code change.
-- Since 29.10.2026 only the eleven common classics; the rarer flavors (uncommon to legendary) are new designs that
-- come later. The families heavy, sticky and wild stay for them. Until then three placeholders (Rare, Epic,
-- Legendary, `placeholder = true`) stand in for the Scoop Chest; the Big Swirl only fires them with
-- Features.placeholderRares, but they stay known here, so stored ones in a save never break.

export type Family = "classic" | "heavy" | "sticky" | "wild"
-- how rare a flavor is for the player (trail, Scoop Chest, later the collection book); the launcher odds are `weight`.
-- A new rarity (Mythic, Secret and Divine are planned, in that order after Legendary) needs: its name in `rarities`
-- at the end of this file (the order is the rank), a colour in `rarityColors`, and its values in Config/Chest
-- (passives.byRarity, sell.byRarity); the UI kit's card uses the neutral card until it has its own picture (Config/Ui).
export type Rarity = string

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
	model: string?, -- the flavor whose scoop model it borrows (ReplicatedStorage.TowerScoops); default its own id
	passive: string?, -- what it gives equipped in the Scoop Chest (Config/Chest.passives); default defaultPassive there
	placeholder: boolean?, -- a stand-in until the real designs: fired only with Features.placeholderRares
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
	-- Placeholders for the Scoop Chest (17.11.2026) until the real rare flavors are built: the Vanilla model in their own
	-- colour, one passive each, small weights (about 1 shot in 30 is one of them).
	{
		id = "blue_moon",
		name = "Blue Moon",
		family = "classic",
		rarity = "rare",
		value = 12,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 2.5,
		color = "#5DB4FF",
		material = "SmoothPlastic",
		model = "vanilla",
		passive = "coins",
		placeholder = true,
	},
	{
		id = "galaxy_grape",
		name = "Galaxy Grape",
		family = "classic",
		rarity = "epic",
		value = 25,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 1,
		color = "#B07BFF",
		material = "SmoothPlastic",
		model = "vanilla",
		passive = "luck",
		placeholder = true,
	},
	{
		id = "sunset_mango",
		name = "Sunset Mango",
		family = "classic",
		rarity = "legendary",
		value = 50,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 0.4,
		color = "#FF9F1C",
		material = "SmoothPlastic",
		model = "vanilla",
		passive = "catch",
		placeholder = true,
	},
}

local byId: { [string]: Flavor } = {}
for _, flavor in list do
	byId[flavor.id] = flavor
end

return {
	list = list,
	byId = byId,
	-- every rarity from the most common up; the place in this list is its rank (the Scoop Chest's threshold, sorting).
	-- Mythic, Secret and Divine come later, in that order after legendary.
	rarities = { "common", "uncommon", "rare", "epic", "legendary" },
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
