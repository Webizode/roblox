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
}

local swirls: { Swirl } = {
	{ id = "vanilla_berry_swirl", name = "Berry Swirl", inputs = { "vanilla", "strawberry" }, minutes = 20 },
	{ id = "choco_mint_twist", name = "Choco-Mint Twist", inputs = { "chocolate", "mint" }, minutes = 20 },
}

return {
	secretStacks = secretStacks,
	swirls = swirls,
}
