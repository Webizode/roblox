--!strict
-- A scoop's rarity in flight (Config/Vfx.flight): its trail, glow, sparks, highlight and sound at a VFX quality, the
-- Big Swirl's announcement before it fires and whether everybody gets a banner. Pure: no Roblox globals, no requires;
-- the configs come in as arguments.

local RarityFlight = {}

export type Trail = { width: number, lifetime: number, transparency: number, lightEmission: number }
export type Announce = { kind: string, time: number, delay: number, brightness: number, range: number }
export type Style = {
	color: string, -- hex
	trail: Trail?,
	glow: { brightness: number, range: number }?,
	sparks: number, -- per second
	highlight: boolean,
	sound: string?,
	announce: Announce?,
	banner: boolean,
}

-- A rarity's own entry, following `like` (at most a few steps, so a loop in the config cannot hang).
local function entryOf(rarity: string, config: any): { [string]: any }
	local entry = config.byRarity[rarity]
	for _ = 1, 4 do
		if entry and entry.like then
			entry = config.byRarity[entry.like]
		else
			break
		end
	end
	return entry or {}
end

-- The look of a scoop of `rarity` at the VFX quality ("high", "medium", "low"; unknown counts as high). Low keeps
-- only the trail: no sparks, light or highlight.
function RarityFlight.style(rarity: string, quality: string, config: any, rarityColors: { [string]: string }): Style
	local entry = entryOf(rarity, config)
	local scale = config.quality[quality] or config.quality.high
	local trail: Trail? = nil
	if entry.trail then
		trail = {
			width = entry.trail.width,
			lifetime = entry.trail.lifetime * scale.lifetime,
			transparency = entry.trail.transparency,
			lightEmission = entry.trail.lightEmission,
		}
	end
	local announce: Announce? = nil
	if entry.announce then
		local a = entry.announce
		announce = {
			kind = a.kind,
			time = a.time or 0,
			delay = a.delay or 0,
			brightness = a.brightness or 0,
			range = a.range or 0,
		}
	end
	return {
		color = entry.color or rarityColors[rarity] or "#FFFFFF",
		trail = trail,
		glow = if scale.light then entry.glow else nil,
		sparks = (entry.sparks or 0) * scale.sparks,
		highlight = scale.light and entry.highlight == true,
		sound = entry.sound,
		announce = announce,
		banner = entry.banner == true,
	}
end

-- How much later the server lets a shot of `rarity` leave: its announcement's delay (a legendary's glow), else 0.
function RarityFlight.delay(rarity: string, config: any): number
	local announce = entryOf(rarity, config).announce
	return if announce then announce.delay or 0 else 0
end

-- The landing circle's colour (ShotRenderer, Config/TowerScoops.landingCircle): from uncommon on the colour of the
-- scoop's trail (`style` colour: the rarity's, golden for a legendary); a common one (or none or an unknown rarity) the
-- circle's own light grey `common`, since pure white glares on the light arena floor.
function RarityFlight.circleColor(
	rarity: string?,
	config: any,
	rarityColors: { [string]: string },
	common: string
): string
	if not rarity or rarity == "common" or not rarityColors[rarity] then
		return common
	end
	return RarityFlight.style(rarity, "high", config, rarityColors).color
end

return RarityFlight
