--!strict
-- Every flavor in the game. Values and physics modifiers live here so a new family is a data change, not a code change.

export type Family = "classic" | "heavy" | "sticky" | "wild"

export type Flavor = {
	id: string,
	name: string,
	family: Family,
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
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#FFF3D6",
		material = "SmoothPlastic",
	},
	{
		id = "chocolate",
		name = "Chocolate",
		family = "classic",
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
		value = 5,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 10,
		color = "#9DE0C4",
		material = "SmoothPlastic",
	},
	{
		id = "rocky_road",
		name = "Rocky Road",
		family = "heavy",
		value = 7.5,
		mass = 2,
		stiffness = 0.3,
		damping = 0,
		jerk = 0,
		weight = 6,
		color = "#8B5A3C",
		material = "Pebble",
	},
	{
		id = "cookie_dough",
		name = "Cookie Dough",
		family = "heavy",
		value = 7.5,
		mass = 1.8,
		stiffness = 0.2,
		damping = 0,
		jerk = 0,
		weight = 6,
		color = "#E8C9A0",
		material = "Sand",
	},
	{
		id = "mochi",
		name = "Mochi",
		family = "sticky",
		value = 10,
		mass = 1,
		stiffness = 0.6,
		damping = 0,
		jerk = 0,
		weight = 4,
		color = "#F5D0E6",
		material = "SmoothPlastic",
	},
	{
		id = "jelly",
		name = "Jelly",
		family = "wild",
		value = 10,
		mass = 0.8,
		stiffness = 0,
		damping = -0.5,
		jerk = 0,
		weight = 4,
		color = "#7FD6FF",
		material = "Glass",
	},
	{
		id = "chili_lava",
		name = "Chili Lava",
		family = "wild",
		value = 15,
		mass = 1,
		stiffness = 0,
		damping = 0,
		jerk = 0,
		weight = 2,
		color = "#FF5A1F",
		material = "Neon",
	},
	{
		id = "cursed_pickle",
		name = "Cursed Pickle",
		family = "wild",
		value = 25,
		mass = 1.2,
		stiffness = 0,
		damping = 0,
		jerk = 1.2,
		weight = 1.5,
		color = "#6BBF3A",
		material = "Grass",
	},
}

local byId: { [string]: Flavor } = {}
for _, flavor in list do
	byId[flavor.id] = flavor
end

return {
	list = list,
	byId = byId,
}
