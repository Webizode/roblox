--!strict
-- Every flavor in the game. Values and physics modifiers live here so a new family is a data change, not a code change.
-- The eleven common classics (29.10.2026) and since 18.11.2026 the rarer flavors from the user's designs: uncommon 11,
-- rare, epic and legendary 10 each; Mythic, Secret and Divine come later. The families heavy, sticky and wild stay for
-- later. The three placeholders of the Scoop Chest (17.11.2026, `placeholder = true`) are not fired any more
-- (Features.placeholderRares is off) but stay known here, so stored ones in a save never break.

export type Family = "classic" | "heavy" | "sticky" | "wild"
-- how rare a flavor is for the player (trail, Scoop Chest, later the collection book); the launcher odds are
-- `rarityChances`. A rarity (Mythic, Secret and Divine have no flavors yet) needs: its name in `rarities` at the end
-- of this file (the order is the rank), a colour in `rarityColors`, and its values in Config/Chest
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

-- What a scoop is worth: BASE_VALUE coins times its rarity's factor (Sorten-Katalog, decided 18.11.2026); mutations
-- (Golden, Rainbow, later the World Events) multiply on top.
local BASE_VALUE = 5
local VALUE_FACTORS: { [string]: number } = {
	common = 1,
	uncommon = 2,
	rare = 4,
	epic = 10,
	legendary = 30,
	mythic = 100,
	secret = 500,
	divine = 1500,
}

-- The rarer flavors (18.11.2026) all share the commons' physics and the base scoop shape; they differ in colour,
-- picture (assets/TowerScoops/build_rarities.py, which holds the same colours) and what they give in the Scoop Chest.
local function scoop(id: string, name: string, rarity: string, color: string, passive: string): Flavor
	return {
		id = id,
		name = name,
		family = "classic",
		rarity = rarity,
		value = BASE_VALUE * VALUE_FACTORS[rarity],
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 1, -- within its rarity every flavor is as likely as the others (FlavorOdds)
		color = color,
		material = "SmoothPlastic",
		passive = passive,
	}
end

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

-- Uncommon 11, rare, epic and legendary 10 each (18.11.2026, designs from the vault; Lime and Red Velvet too).
-- Passives: fruit gives Luck, cream and desserts Coins, the cold and candy ones Catch.
for _, flavor in
	{
		scoop("blueberry", "Blueberry", "uncommon", "#8E92EE", "luck"),
		scoop("raspberry", "Raspberry", "uncommon", "#E8557E", "luck"),
		scoop("peach", "Peach", "uncommon", "#FFBE8A", "luck"),
		scoop("grape", "Grape", "uncommon", "#A65BE0", "luck"),
		scoop("coconut", "Coconut", "uncommon", "#F3E6D6", "catch"),
		scoop("cherry", "Cherry", "uncommon", "#FAC6CE", "luck"),
		scoop("pineapple", "Pineapple", "uncommon", "#FFEAA0", "luck"),
		scoop("orange", "Orange", "uncommon", "#FF7F30", "luck"),
		scoop("lime", "Lime", "uncommon", "#A9DE3E", "catch"),
		scoop("caramel", "Caramel", "uncommon", "#E8933C", "coins"),
		scoop("blue_raspberry", "Blue Raspberry", "uncommon", "#33B5F2", "catch"),
		scoop("cotton_candy", "Cotton Candy", "rare", "#96D6FF", "catch"),
		scoop("red_velvet", "Red Velvet", "rare", "#B0243E", "coins"),
		scoop("birthday_cake", "Birthday Cake", "rare", "#FFF3DE", "coins"),
		scoop("brownie", "Brownie", "rare", "#A3744E", "coins"),
		scoop("cookies_cream", "Cookies and Cream", "rare", "#EEE8E1", "coins"),
		scoop("coffee", "Coffee", "rare", "#D6B089", "catch"),
		scoop("dragon_fruit", "Dragon Fruit", "rare", "#E62E9E", "luck"),
		scoop("pomegranate", "Pomegranate", "rare", "#E86F90", "luck"),
		scoop("honey", "Honey", "rare", "#FFCC66", "coins"),
		scoop("maple_syrup", "Maple Syrup", "rare", "#F5D5A2", "coins"),
		scoop("tiramisu", "Tiramisu", "epic", "#E8CCA4", "coins"),
		scoop("white_chocolate", "White Chocolate", "epic", "#FFF3D8", "coins"),
		scoop("black_cherry", "Black Cherry", "epic", "#B83D6A", "luck"),
		scoop("pistachio_cream", "Pistachio Cream", "epic", "#D2E69A", "catch"),
		scoop("salted_caramel", "Salted Caramel", "epic", "#F3C58E", "coins"),
		scoop("marzipan", "Marzipan", "epic", "#F2CBB2", "coins"),
		scoop("cinnamon_roll", "Cinnamon Roll", "epic", "#E8B87C", "coins"),
		scoop("cheesecake", "Cheesecake", "epic", "#FFF0C6", "coins"),
		scoop("mocha", "Mocha", "epic", "#9A6A4C", "catch"),
		scoop("passion_fruit", "Passion Fruit", "epic", "#FFB830", "luck"),
		scoop("royal_cream", "Royal Cream", "legendary", "#F6DFB8", "coins"),
		scoop("midnight_berry", "Midnight Berry", "legendary", "#6A2FA0", "luck"),
		scoop("frosted_melon", "Frosted Melon", "legendary", "#FFA766", "catch"),
		scoop("velvet_dream", "Velvet Dream", "legendary", "#C23A64", "coins"),
		scoop("mystic_plum", "Mystic Plum", "legendary", "#C25AB8", "luck"),
		scoop("arctic_coconut", "Arctic Coconut", "legendary", "#F0F7FF", "catch"),
		scoop("crimson_velvet", "Crimson Velvet", "legendary", "#7E0F24", "coins"),
		scoop("honey_blossom", "Honey Blossom", "legendary", "#FFEBC2", "luck"),
		scoop("velvet_mocha", "Velvet Mocha", "legendary", "#5E3422", "catch"),
		scoop("sapphire_cream", "Sapphire Cream", "legendary", "#F4F6FF", "catch"),
	}
do
	table.insert(list, flavor)
end

local byId: { [string]: Flavor } = {}
for _, flavor in list do
	byId[flavor.id] = flavor
end

return {
	list = list,
	byId = byId,
	-- every rarity from the most common up; the place in this list is its rank (the Scoop Chest's threshold, sorting).
	-- Mythic, Secret and Divine have no flavors yet (they come one by one with auras and effects).
	rarities = { "common", "uncommon", "rare", "epic", "legendary", "mythic", "secret", "divine" },
	-- the colour of a rarity, e.g. for the name over a scoop in flight or on the ground (ScoopLabel); golden its own
	rarityColors = {
		common = "#FFFFFF",
		uncommon = "#7CE07C",
		rare = "#5DB4FF",
		epic = "#C77DFF",
		legendary = "#FF9F1C",
		mythic = "#FF4F9A",
		secret = "#B8F5FF",
		divine = "#FFF1A6",
		golden = "#FFD23F",
	},
	-- How often the Big Swirl fires each rarity, in percent (Sorten-Katalog, 18.11.2026; together 100). Within a
	-- rarity every flavor is as likely as the others. A rarity without flavors gives its share to common
	-- (FlavorOdds), so until Mythic, Secret and Divine exist common fires 52.5 %.
	rarityChances = {
		common = 50.94,
		uncommon = 25,
		rare = 12,
		epic = 7,
		legendary = 3.5,
		mythic = 1.5,
		secret = 0.05,
		divine = 0.01,
	},
	baseValue = BASE_VALUE,
	valueFactors = VALUE_FACTORS,
}
