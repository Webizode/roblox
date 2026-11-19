--!strict
-- Luck: the chance that a caught scoop turns into one of the next rarer rarity (ScoopChest.luckyFlavor). It is the
-- catcher's own: the Big Swirl fires the same for everybody, only the catcher's tower changes.
--
-- Luck comes from several sources, each added up in one place (Services/LuckService, the sums in Luck.total): every
-- source registers there with a function that gives a player's luck from it (0.05 = +5 %). Each source is held at its
-- own cap here, the sum at totalCap. A source without a line here counts nothing. So far only the Scoop Chest
-- registers (19.11.2026); the others are planned, their caps placeholders.

return {
	totalCap = 0.5,
	sources = {
		chest = { cap = 0.25 }, -- the equipped luck scoops (Config/Chest passives.kinds.luck, also capped there)
		-- planned, nothing registers them yet
		friends = { cap = 0.1 }, -- friends on the server
		group = { cap = 0.05 }, -- member of the game's group
		upgrade = { cap = 0.15 }, -- a luck upgrade
		potion = { cap = 0.25 }, -- a luck potion while it lasts
		server = { cap = 0.25 }, -- server luck (somebody bought it for everyone)
		event = { cap = 0.25 }, -- an event
	},
}
