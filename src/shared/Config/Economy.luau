--!strict
-- Coins, walking with a tower and the serve formula. The sneakers arrays are indexed by level + 1 (level 0 is the start).

return {
	heightFactor = 0.04, -- value = sum(scoop values) * (1 + heightFactor * scoops)^2
	goldenMultiplier = 5, -- a golden scoop is worth this many times its flavor (concept: Golden Glow)

	-- what falls when a tower topples or its carrier is knocked down (since the kill test of 13.11.2026, design rule 4):
	-- towers of up to spillAllUpTo scoops lose everything, taller ones spillShare of their scoops from the top (rounded
	-- to the nearest scoop; 6 lose 4, 7 lose 4, 10 lose 6), the rest stays on the cone.
	-- Before: towers under 5 lost nothing, the bottom 30 % (at least 2) stayed.
	spillShare = 0.6,
	spillAllUpTo = 5,
	knockSpillGuard = 1, -- seconds after a knockdown spill in which a topple report spills nothing more (TowerService)

	baseWalkSpeed = 18,
	-- The tower slows its carrier by how full the waffle is, not by the bare count (test of 14.11.2026: nimble players far
	-- away were hardly hit; more aim help was not wanted). Load = (scoops / capacity) ^ curve, a soft curve: a quarter
	-- full costs 3 %, half 9 %, three quarters 16 %, full `walk` (25 %) of the walking and sprinting speed and `dash`
	-- (20 %) of the dash's distance; the sneakers' penaltyScale shrinks both. Before: 18 / (1 + 0.012 per scoop), 19 %
	-- slower with 20 scoops, 44 % with 65, at least minWalkSpeed.
	-- jump: a gummy pad throws a full tower's carrier this much less high (Config/Bounce)
	towerSlow = { walk = 0.25, dash = 0.2, jump = 0.07, curve = 1.5 },
	minWalkSpeed = 9,
	sprintMultiplier = 1.3, -- Shift (hold), L3 or the Sprint button; also scales what the tower feels and the catch speed cap
	jumpPower = 40, -- Roblox default is 50; a bit lower so a jump with a tower stays a hop

	serveRadius = 8, -- studs around the cart's ServePoint
	serveCooldown = 0.5,

	-- The cone (capacity) and the cart (serve multiplier) are in the upgrade shop since 25.11.2026 (Config/Upgrades).
	-- The sneakers stay here but are not sold: walking speed helps in the fight too (basic rule, vault Upgrades.md).
	-- Every save has them at 0; the values only keep Economy.walkSpeed's sneakersLevel working.
	upgrades = {
		sneakers = {
			label = "Sneakers",
			costs = { 15, 120, 600, 2500, 9000 },
			speed = { 1, 1.08, 1.16, 1.24, 1.32, 1.4 },
			penaltyScale = { 1, 0.9, 0.8, 0.7, 0.6, 0.5 },
		},
	},
}
