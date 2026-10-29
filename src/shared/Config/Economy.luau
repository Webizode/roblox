--!strict
-- Coins, upgrades and the serve formula. Arrays are indexed by upgrade level + 1 (level 0 is the start).

return {
	heightFactor = 0.04, -- value = sum(scoop values) * (1 + heightFactor * scoops)^2
	goldenMultiplier = 5, -- a golden scoop is worth this many times its flavor (concept: Golden Glow)

	keepOnToppleFraction = 0.3, -- the bottom 30 % stay on the cone
	keepOnToppleMin = 2,
	keepAllBelow = 5, -- towers of fewer scoops lose nothing when they topple (design rule 4)

	baseWalkSpeed = 18,
	walkSpeedPenaltyPerScoop = 0.012,
	minWalkSpeed = 9,
	sprintMultiplier = 1.3, -- Shift (hold), L3 or the Sprint button; also scales what the tower feels and the catch speed cap
	jumpPower = 40, -- Roblox default is 50; a bit lower so a jump with a tower stays a hop

	serveRadius = 8, -- studs around the cart's ServePoint
	serveCooldown = 0.5,

	upgrades = {
		cone = {
			label = "Cone",
			costs = { 25, 200, 900, 3500, 12000 },
			capacity = { 20, 28, 36, 45, 55, 65 },
			stiffness = { 1, 1.1, 1.2, 1.3, 1.45, 1.6 },
		},
		sneakers = {
			label = "Sneakers",
			costs = { 15, 120, 600, 2500, 9000 },
			speed = { 1, 1.08, 1.16, 1.24, 1.32, 1.4 },
			penaltyScale = { 1, 0.9, 0.8, 0.7, 0.6, 0.5 },
		},
		cart = {
			label = "Cart",
			costs = { 40, 300, 1200, 4500, 15000 },
			serveMultiplier = { 1, 1.12, 1.25, 1.38, 1.5, 1.6 },
		},
	},
}
