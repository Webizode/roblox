--!strict
-- The rules of the effects (Config/Vfx): how many particles an effect shows at a VFX quality and a distance, within
-- its budget and the cap on all effects together. Pure: the config is passed in, so the client (src/client/Vfx) and
-- the Lune tests use the same numbers.

export type Tier = "full" | "reduced" | "off"
export type Plan = { counts: { number }, total: number }

local VfxRules = {}

-- How much of an effect `distance` studs from the camera still plays. The local player's own effects always play in
-- full. `reach` (an effect's own, default 1) stretches both distances: the Big Swirl's shots read across the arena.
function VfxRules.tier(distance: number, own: boolean, config: any, reach: number?): Tier
	local stretch = reach or 1
	if own or distance <= config.distance.full * stretch then
		return "full"
	elseif distance <= config.distance.reduced * stretch then
		return "reduced"
	end
	return "off"
end

-- The share of every count at this quality and tier, and whether the extras show.
function VfxRules.scale(quality: string, tier: Tier, config: any): (number, boolean)
	if tier == "off" then
		return 0, false
	end
	local level = config.quality[quality] or config.quality.high
	if tier == "reduced" then
		return level.particles * config.distance.reducedScale, false
	end
	return level.particles, level.extras
end

-- How many of `count` things show at this quality and tier, never fewer than `min` (0 when the effect is off).
function VfxRules.items(count: number, min: number, quality: string, tier: Tier, config: any): number
	local share = VfxRules.scale(quality, tier, config)
	if share <= 0 then
		return 0
	end
	return math.max(math.min(min, count), math.floor(count * share + 0.5))
end

-- The particles each layer of `effect` emits: scaled by quality and tier, extras left out where they do not show,
-- never more than the effect's budget, and thinned out to fit `room` (the particles the cap on all effects still
-- allows; math.huge for the local player's own effects). A layer that plays shows at least one particle, unless the
-- room runs out.
function VfxRules.plan(effect: any, quality: string, tier: Tier, room: number, config: any): Plan
	local share, extras = VfxRules.scale(quality, tier, config)
	local counts: { number } = {}
	local total = 0
	for index, layer in effect.layers do
		local count = 0
		if share > 0 and (extras or not layer.extra) then
			count = math.max(1, math.floor(layer.count * share + 0.5))
		end
		counts[index] = count
		total += count
	end
	local limit = math.max(0, math.min(effect.budget.particles, math.floor(room)))
	if total > limit then
		local keep = limit / total
		total = 0
		for index, count in counts do
			counts[index] = math.floor(count * keep)
			total += counts[index]
		end
	end
	return { counts = counts, total = total }
end

-- The most particles of `effect` alive at once at this quality, close by: what its budget is checked against.
function VfxRules.peak(effect: any, quality: string, config: any): number
	return VfxRules.plan(effect, quality, "full", math.huge, config).total
end

-- The longest any particle of `effect` lives, in seconds.
function VfxRules.longest(effect: any): number
	local longest = 0
	for _, layer in effect.layers do
		longest = math.max(longest, layer.lifetime[2])
	end
	return longest
end

-- Particles per second of a steady emitter (a trail's twinkles) at this quality.
function VfxRules.rate(rate: number, quality: string, config: any): number
	local share = VfxRules.scale(quality, "full", config)
	return rate * share
end

-- A lying scoop's blink in its last `span` seconds, `left` seconds before it goes: the blink count so far (a whole
-- number per blink; it changes when the scoop lights up again) and whether it is see-through right now. It blinks
-- `blink.from` times a second at the start and speeds up evenly to `blink.to` at the end.
function VfxRules.blink(left: number, span: number, blink: any): (number, boolean)
	local t = math.clamp(span - left, 0, span)
	-- the blinks so far: the integral of a rate rising evenly from `from` to `to` over the span
	local phase = blink.from * t + (blink.to - blink.from) * t * t / (2 * math.max(span, 1e-3))
	local count = math.floor(phase)
	return count, phase - count >= 0.5
end

-- How many coins fly to the coin counter for a serve of `scoops` (Config/Vfx.uiCoins): one per scoop between min
-- and max, fewer at a lower quality but never fewer than min.
function VfxRules.uiCoins(scoops: number, quality: string, config: any): number
	local coins = config.uiCoins
	local count = math.clamp(scoops, coins.min, coins.max)
	return VfxRules.items(count, coins.min, quality, "full", config)
end

-- The size of a serve's coin fountain for `scoops` served (Config/Vfx.serve).
function VfxRules.serveScale(scoops: number, config: any): number
	local serve = config.serve
	return math.clamp(1 + (math.max(scoops, 1) - 1) * serve.perScoop, 1, serve.maxScale)
end

return VfxRules
