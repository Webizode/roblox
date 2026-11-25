--!strict
-- The upgrade shop (UpgradeService, Upgrades, UpgradeController). Basic rule (vault: Upgrades.md): upgrades only help
-- the economy and the own tower, never the fight against others. No speed, damage, ammo, protection against hits or
-- extra dashes. That is why the sneakers (walking speed, Config/Economy upgrades.sneakers) are not sold here, and why
-- a bigger cone no longer makes the tower stiffer (stiffness also softens hits): cone.stiffnessPerLevel is 0.
--
-- Steps and prices from the progression simulation (scripts/progression, 25.11.2026; vault: Progression und Liegezeit
-- 2026-11-25). Goals for a typical player: the first upgrade after 2 to 3 minutes, every upgrade at about level 5
-- after 1 hour, half the levels after about 10 hours, everything at the top after 30 to 50 hours. The simulation
-- gives 3 min, 1.0 h, 9.8 h and 43.6 h (tests/Progression.spec keeps it there). Change prices, then rerun
-- `lune run scripts/progression`; `scripts/progression-fit` searches new ones.
--
-- An upgrade's value at level L (0 = the start): start + perLevel * L, for L from 0 to maxLevel.
-- The price of the step from level L to L + 1 (Upgrades.cost): cost.base * cost.growth ^ L, from level `bend` on
-- lateGrowth per level instead (steep in the middle, flatter towards the top), rounded to `priceDigits` leading
-- digits (1234 -> 1200 with 2).
--
-- The keys are the save's fields (SaveData upgrades): `cone` (capacity) and `cart` (coin multiplier) are the old
-- tracks of the same name, merged into the shop on 25.11.2026 (SaveData version 4 lifts old levels).
--   label, text    the card's name and one short line (English, Roblox translates)
--   icon           Config/Ui.icons name or an rbxassetid; nil draws a placeholder with the first letter
--   color          the card's accent (UiKit Theme token)
--   format         how the card shows the value: "count" (28 scoops), "times" (x1.2), "percent" (+4.5%)
--   unit           after a count ("scoops", "slots")
--   hidden         prepared but not sold yet: not in the shop, the server refuses it

-- the prices of every upgrade with many levels: 43, 75, 130, ... 19,000 (level 12), 33,000, 35,000, ... 75,000
local PRICE = { base = 43, growth = 1.74, bend = 12, lateGrowth = 1.07 }

return {
	order = { "cone", "stability", "cart", "luck", "slots", "sprinkles" },
	priceDigits = 2,

	-- The highest level per rebirth (Upgrades.top): `base` without a rebirth, `perRebirth` more for each. Prepared for
	-- the rebirth, which does not exist yet; off until then (on, everybody would stop at level 10, about 3 hours in).
	-- The rebirths come from the save's field `rebirths` once it exists (0 without it).
	levelCap = { enabled = false, base = 10, perRebirth = 5 },

	-- the server takes one purchase per player at most this often (against spam; a double click is caught by the level
	-- the client buys from, UpgradeService)
	buyInterval = 0.25,
	-- a purchase is saved this many seconds after it at the latest (several quick purchases share one save)
	saveDelay = 4,
	-- the prompt at the Upgrade shop in the hub (on the Teleport_Upgrade parts, Config/Map.teleportTargets.upgrades)
	-- The window opens only there (the HUD's UPGRADES button teleports to the shop, like the other shop buttons).
	promptDistance = 12,
	promptHeight = 3.5, -- studs above that part (it lies at the feet)
	-- walking farther than this from the shop's part closes the window (a little more than the prompt's reach, so it
	-- does not flutter at the edge); the server takes purchases only within buyDistance (a little more again, for the
	-- position it sees late)
	closeDistance = 18,
	buyDistance = 24,

	-- save fields from before the shop that are not sold (any more), with their highest level; kept and repaired, and
	-- reset with the rest
	legacy = { sneakers = 5 },

	tracks = {
		-- Tragkraft: the cone holds more scoops (TowerService.addScoop, the HUD's tower count, the load on walking)
		cone = {
			label = "Big Cone",
			text = "Carry more scoops in your tower.",
			icon = "scoops",
			color = "pink",
			format = "count",
			unit = "scoops",
			start = 20,
			perLevel = 1,
			maxLevel = 25,
			-- the tower's stiffness per level (TowerModel.params); 0: it would also soften ice-ball hits (basic rule)
			stiffnessPerLevel = 0,
			cost = PRICE,
		},
		-- Stabilität: walking tips the tower harder only from this many scoops (Config/Tower.walkHeavyFrom, which
		-- `start` must equal). Only walking: hits, dashes and standing do not see it.
		stability = {
			label = "Stability",
			text = "Walk with a taller tower before it gets wobbly.",
			icon = nil,
			color = "sky",
			format = "count",
			unit = "scoops",
			start = 10,
			perLevel = 1,
			maxLevel = 20,
			cost = PRICE,
		},
		-- Geld-Multiplikator: the coins of a serve (Economy.serveValue serveMultiplier). Was the cart track (x1.12 ...).
		cart = {
			label = "Coin Boost",
			text = "More coins for every tower you serve.",
			icon = "coin",
			color = "yellow",
			format = "times",
			start = 1,
			perLevel = 0.04,
			maxLevel = 25,
			cost = PRICE,
		},
		-- Luck: the luck source "upgrade" (LuckService, its own cap in Config/Luck.sources.upgrade)
		luck = {
			label = "Luck",
			text = "Chance that a caught scoop turns rarer.",
			icon = "rbxassetid://122651245550491", -- the clover of the Scoop Chest (Config/Chest.art.passiveIcons.luck)
			color = "mint",
			format = "percent",
			start = 0,
			perLevel = 0.006,
			maxLevel = 25,
			cost = PRICE,
		},
		-- Ausrüst-Plätze: equip slots in the Scoop Chest (`start` must equal Config/Chest.equipSlots)
		slots = {
			label = "Equip Slots",
			text = "Equip more scoops in your chest at once.",
			icon = nil,
			color = "purple",
			format = "count",
			unit = "slots",
			start = 3,
			perLevel = 1,
			maxLevel = 3,
			-- at the price of level 6, 13 and 23 of the others: 690, 33,000, 65,000
			cost = { base = 690, growth = 48, bend = 1, lateGrowth = 1.97 },
		},
		-- Streusel-Multiplikator: prepared, sprinkles do not exist yet (vault: Streusel und Angriffs-Kugeln)
		sprinkles = {
			label = "Sprinkle Boost",
			text = "More sprinkles for every scoop you serve.",
			icon = nil,
			color = "pink",
			format = "times",
			start = 1,
			perLevel = 0.04,
			maxLevel = 25,
			cost = PRICE,
			hidden = true,
		},
	},
}
