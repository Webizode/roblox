--!strict
-- Bosses in the arena (BossService, BossRules, BossController). Placeholders throughout: names, numbers and the simple
-- part models are for the first team test.
--
-- Rhythm: a normal boss every normalMin to normalMax seconds after the last one ended; a big boss at every full hour
-- (server clock), announced `announce` seconds before. The big boss takes the place of a normal one: no normal boss
-- starts within blockBefore seconds before a full hour or blockAfter seconds after it. Never two at once.
-- A boss leaves after `lifetime` seconds without a reward. While one is alive there is a truce (when `truce` is on):
-- ice balls fly through players, nobody takes damage or is knocked down, nobody picks up another player's spilled
-- scoops. The Big Swirl and catching go on as normal.

local MINUTE = 60

return {
	enabled = true,
	truce = true,

	schedule = {
		normalMin = 15 * MINUTE,
		normalMax = 20 * MINUTE,
		firstMin = 5 * MINUTE, -- the first normal boss after a server starts
		firstMax = 8 * MINUTE,
		announce = 5 * MINUTE, -- the big boss's announcement
		blockBefore = 8 * MINUTE, -- announcement plus a normal boss's lifetime: it never overlaps the big one
		blockAfter = 4 * MINUTE,
	},
	lifetime = 3 * MINUTE,

	-- where a boss roams: a ring round the Big Swirl in the arena's middle (studs from the centre)
	roam = { minRadius = 32, maxRadius = 105, spawnRadius = 60 },
	tickRate = 15, -- server updates per second (movement, attacks, the published state)

	-- health: base x (1 + perPlayer x (players in the arena - 1)); more players coming in raise it, it never sinks
	health = { perPlayer = 0.6 },
	-- the boss's body for ice balls: an upright capsule round its centre (scaled with the boss)
	hitbox = { radius = 4, halfHeight = 5 },
	-- one ice ball: damage x hit power (0..1, Combat.hitPower) x the thrower's Boss Power (Config/Upgrades bossPower)
	damagePerHit = 10,

	-- what a boss attack does to a player it hits: never a knockdown and never a topple (only players topple towers).
	-- A strong shove (rad/s of lean speed) the tower cannot fall from (the client holds it like in the grace for
	-- protectSeconds), and dropMin to dropMax scoops fall off the top as loot for the owner.
	hit = {
		kick = 1.6,
		protectSeconds = 1.5,
		dropMin = 2,
		dropMax = 3,
		-- a dash this shortly before the impact dodges it (server time of the granted dash)
		dashDodge = 0.35,
		-- a ground wave misses a player whose feet are this high above the ground
		jumpClear = 1.2,
		-- the server sees players a little late: the danger areas count this much smaller for the check
		tolerance = 1,
	},

	-- the reward when a boss is defeated: everybody who did damage gets coins
	-- (base, plus their share of the pot) and one scoop of at least rare, lying where the boss fell with a light pillar.
	-- Only its owner may pick it up for ownerSeconds, after that anybody (stealing it makes them wanted). It lies for
	-- lifetime seconds. odds: weights per rarity.
	reward = {
		coinsBase = 150,
		coinsPot = 1200,
		odds = { rare = 70, epic = 25, legendary = 5 },
		scoop = { ownerSeconds = 20, lifetime = 90, spread = 6 },
	},

	-- the big boss: these multiply the normal values
	big = {
		health = 3,
		scale = 1.6,
		attackSpeed = 1.35, -- shorter pauses between attacks
		hitKick = 1.25,
		coins = 3,
		odds = { rare = 40, epic = 45, legendary = 15 },
		title = "BIG BOSS",
	},

	-- what everybody reads (English, Roblox translates)
	text = {
		truce = "TRUCE! Defeat the boss together!",
		pvpBack = "PvP is back!",
		announce = "BIG BOSS in %s",
		arrived = "%s appeared in the arena!",
		defeated = "%s defeated!",
		escaped = "%s got away...",
		reward = "+%d coins! A reward scoop waits where it fell.",
		hitByBoss = "SPLAT! Scoops fell off!",
		sticky = "STUCK!",
	},

	-- The danger areas: a red disc fills during `warn` seconds, then it strikes. Kinds:
	--   stomp  a disc round the boss (radius); dash out of it
	--   wave   a ring that runs out from the boss (speed studs/s, width, reach); jump over it
	--   leap   the boss jumps onto a player's spot (radius at the landing); dash away
	--   puddle `count` sticky spots near players (radius) that last `duration` s: slow (slowFactor) and no dash
	-- every attack waits `cooldown` seconds before it is picked again; the boss pauses `pause` seconds between attacks
	bosses = {
		iceBrute = {
			name = "Frost Brute",
			model = "iceBrute",
			health = 900,
			speed = 6, -- studs/s
			scale = 1,
			pause = 2.6,
			attacks = {
				{ kind = "stomp", warn = 1.4, radius = 14, cooldown = 6 },
				{ kind = "wave", warn = 1.0, speed = 26, width = 3, reach = 60, cooldown = 9 },
			},
		},
		gummyBear = {
			name = "Gummy Grizzly",
			model = "gummyBear",
			health = 650,
			speed = 13,
			scale = 1,
			pause = 1.8,
			attacks = {
				{ kind = "leap", warn = 1.1, radius = 10, cooldown = 3.5 },
				{ kind = "stomp", warn = 1.0, radius = 9, cooldown = 7 },
			},
		},
		creamGhost = {
			name = "Cream Phantom",
			model = "creamGhost",
			health = 750,
			speed = 9,
			scale = 1,
			pause = 2.2,
			hover = 3, -- studs above the ground
			attacks = {
				{
					kind = "puddle",
					warn = 1.2,
					radius = 7,
					count = 4,
					duration = 8,
					slowFactor = 0.45,
					cooldown = 8,
				},
				{ kind = "stomp", warn = 1.3, radius = 11, cooldown = 7 },
			},
		},
	},
	order = { "iceBrute", "gummyBear", "creamGhost" },

	-- the look on the clients (BossController)
	look = {
		warnColor = "#FF4D6D",
		warnTransparency = 0.55,
		stickyColor = "#FFF3D6",
		barWidth = 560, -- design pixels of the health bar at the top
		barHeight = 34,
	},
}
