--!strict
-- What tells the rarities apart on a stacked tower (user 28.11.2026: in the stack one could not see which scoop has
-- which rarity): the thin ring under a scoop (TowerVisual, Config/TowerScoops rarityRing), the name over a scoop just
-- caught and over a rival's tower one aims at (TowerNameTag, Controllers/TowerPeek). Pure: no Roblox globals, no
-- requires; the configs come in as arguments.

local TowerMarks = {}

export type Ring = {
	color: string, -- hex
	glow: boolean, -- Neon, a little see-through
	sparkle: boolean, -- a few glints round it (legendary)
}

local function rank(rarity: string, rarities: { string }): number
	return table.find(rarities, rarity) or 0
end
TowerMarks.rank = rank

-- The ring under a scoop of `rarity` at the VFX quality ("high", "medium", "low"; unknown counts as high), or nil: a
-- common one (and an unknown rarity) has none. Its colour is the landing circle's and the trail's (`color`, from
-- RarityFlight.circleColor: the rarity's, golden for a legendary). From `config.glowFrom` on it glows, from
-- `config.sparkleFrom` on it glints; low quality neither, medium no glints.
function TowerMarks.ring(rarity: string?, quality: string, config: any, rarities: { string }, color: string): Ring?
	if not rarity or rarity == "common" then
		return nil
	end
	local r = rank(rarity, rarities)
	if r == 0 then
		return nil
	end
	local glow = quality ~= "low" and r >= rank(config.glowFrom, rarities)
	local sparkle = quality ~= "low" and quality ~= "medium" and r >= rank(config.sparkleFrom, rarities)
	return { color = color, glow = glow, sparkle = sparkle }
end

-- The place (1 = bottom) of the rarest scoop on a tower, the highest of them when several share that rarity; nil for
-- an empty tower or one of unknown flavors only.
function TowerMarks.rarest(ids: { string }, byId: { [string]: any }, rarities: { string }): number?
	local best, bestRank = nil, 0
	for index, id in ids do
		local flavor = byId[id]
		local r = if flavor then rank(flavor.rarity, rarities) else 0
		if r > 0 and r >= bestRank then
			best, bestRank = index, r
		end
	end
	return best
end

-- "EPIC Tiramisu": the rarity in capitals, then the flavor's name.
function TowerMarks.tagText(rarity: string, name: string): string
	return `{string.upper(rarity)} {name}`
end

-- Where a ray (origin o, unit direction d) passes a tower's column, the segment a to b, closer than `radius`: the
-- distance along the ray, or nil when it misses, runs past maxDistance or the column lies behind the origin.
function TowerMarks.rayHitsColumn(
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	radius: number,
	maxDistance: number
): number?
	local ux, uy, uz = bx - ax, by - ay, bz - az
	local wx, wy, wz = ox - ax, oy - ay, oz - az
	local a = dx * dx + dy * dy + dz * dz
	local b = dx * ux + dy * uy + dz * uz
	local c = ux * ux + uy * uy + uz * uz
	local d = dx * wx + dy * wy + dz * wz
	local e = ux * wx + uy * wy + uz * wz
	local denominator = a * c - b * b
	local s, t -- along the ray, along the segment (0..1)
	if c < 1e-9 or denominator < 1e-9 then
		-- a point, or parallel to the ray: the end of the segment the ray reaches first
		local atFoot, atTop = -d / a, (b - d) / a
		t = if atTop >= 0 and (atTop < atFoot or atFoot < 0) then 1 else 0
		s = if t == 1 then atTop else atFoot
	else
		s = (b * e - c * d) / denominator
		t = (a * e - b * d) / denominator
	end
	if c >= 1e-9 then
		t = math.clamp(t, 0, 1)
		s = (b * t - d) / a -- the ray's closest point to the clamped segment point
	end
	if s < 0 or s > maxDistance then
		return nil
	end
	local px, py, pz = ox + dx * s, oy + dy * s, oz + dz * s
	local qx, qy, qz = ax + ux * t, ay + uy * t, az + uz * t
	local gap = math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2 + (pz - qz) ^ 2)
	if gap > radius then
		return nil
	end
	return s
end

return TowerMarks
