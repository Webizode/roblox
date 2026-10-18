--!strict
-- Secret Stacks (exact bottom-to-top order inside a tower) and Churn swirls (two flavors in, one swirl out).
-- Both are deterministic on purpose: nothing a player can buy ever rolls a random result.

export type StackEffect = {
	kind: "valueMultiplier" | "rigid",
	scope: ("match" | "tower")?,
	factor: number?,
	seconds: number?,
}

export type SecretStack = {
	id: string,
	name: string,
	sequence: { string }, -- bottom to top
	effect: StackEffect,
	rumor: string, -- chalkboard hint shown once per day
}

export type Swirl = {
	id: string,
	name: string,
	inputs: { string }, -- two flavor ids, order does not matter
	minutes: number,
}

local secretStacks: { SecretStack } = {
	{
		id = "neapolitan",
		name = "Neapolitan",
		sequence = { "vanilla", "chocolate", "strawberry" },
		effect = { kind = "valueMultiplier", scope = "match", factor = 3 },
		rumor = "White, then brown, then pink. Grandma swore by it.",
	},
	{
		id = "rocky_mountain",
		name = "Rocky Mountain",
		sequence = { "rocky_road", "rocky_road", "mochi" },
		effect = { kind = "rigid", seconds = 20 },
		rumor = "Two rocks and something sticky on top. Nothing moves a mountain.",
	},
	{
		id = "pickle_party",
		name = "Pickle Party",
		sequence = { "cursed_pickle", "chili_lava", "cursed_pickle" },
		effect = { kind = "valueMultiplier", scope = "tower", factor = 2 },
		rumor = "Put the fire between two curses and the whole tower pays double.",
	},
}

local swirls: { Swirl } = {
	{ id = "vanilla_berry_swirl", name = "Berry Swirl", inputs = { "vanilla", "strawberry" }, minutes = 20 },
	{ id = "choco_mint_twist", name = "Choco-Mint Twist", inputs = { "chocolate", "mint" }, minutes = 20 },
	{ id = "cookie_crunch", name = "Cookie Crunch", inputs = { "cookie_dough", "chocolate" }, minutes = 120 },
	{ id = "rocky_mochi", name = "Rocky Mochi", inputs = { "rocky_road", "mochi" }, minutes = 120 },
	{ id = "mint_jelly_fizz", name = "Mint Jelly Fizz", inputs = { "jelly", "mint" }, minutes = 360 },
	{ id = "spicy_pickle", name = "Spicy Pickle Swirl", inputs = { "chili_lava", "cursed_pickle" }, minutes = 360 },
}

return {
	secretStacks = secretStacks,
	swirls = swirls,
}
