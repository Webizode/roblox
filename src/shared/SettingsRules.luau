--!strict
-- The rules for player settings (Config/Settings). Pure: the config is passed in, so the client (menu, effects), the
-- server (before saving) and the Lune tests use the same checks.

export type Effective = {
	vfxQuality: string, -- "high", "medium" or "low" ("auto" resolved by the device); the performance mode counts as "low"
	particleScale: number, -- multiplies particle counts
	heavyDashEffects: boolean, -- afterimages and limb trails
	shadows: boolean,
	postEffects: boolean, -- bloom and sun rays
	cameraShake: boolean,
	fov: number,
	motionEffects: boolean,
	aimCamera: boolean,
	aimAssist: boolean,
}

local SettingsRules = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function snap(value: number, range: { number }): number
	local min, max, step = range[1], range[2], range[3]
	local snapped = min + math.floor((value - min) / step + 0.5) * step
	-- keep 0.1 steps clean (0.30000000000000004)
	snapped = math.floor(snapped * 1000 + 0.5) / 1000
	return math.clamp(snapped, min, max)
end

-- One setting checked: the value if it is allowed (numbers snapped into their range), otherwise the default.
-- Unknown keys give nil.
function SettingsRules.value(key: string, raw: any, config: any): any
	local default = config.defaults[key]
	if default == nil then
		return nil
	end
	local range = config.ranges[key]
	if range then
		return if isFinite(raw) then snap(raw, range) else default
	end
	local choices = config.choices[key]
	if choices then
		return if type(raw) == "string" and table.find(choices, raw) then raw else default
	end
	local layout = config.layouts and config.layouts[key]
	if layout then
		-- button spots (TouchLayout): known buttons with finite numbers only, clamped; anything else is left out
		local clean = {}
		if type(raw) == "table" then
			for _, id in layout.ids do
				local spot = raw[id]
				if type(spot) == "table" and isFinite(spot.x) and isFinite(spot.y) and isFinite(spot.size) then
					clean[id] = {
						x = math.clamp(spot.x, 0, 1),
						y = math.clamp(spot.y, 0, 1),
						size = math.clamp(spot.size, layout.minSize, layout.maxSize),
					}
				end
			end
		end
		return clean
	end
	if type(default) == "boolean" then
		return if type(raw) == "boolean" then raw else default
	end
	return default
end

-- A complete, valid settings table from anything (a save, a client's message): every known key, nothing else.
function SettingsRules.sanitize(raw: any, config: any): { [string]: any }
	local source = if type(raw) == "table" then raw else {}
	local clean = {}
	for key in config.defaults do
		clean[key] = SettingsRules.value(key, source[key], config)
	end
	return clean
end

-- The next value for the menu's buttons: numbers move one step (direction -1 or 1, stopping at the ends), choices
-- cycle round, toggles flip.
function SettingsRules.step(key: string, current: any, direction: number, config: any): any
	local range = config.ranges[key]
	if range then
		local value = if isFinite(current) then current else config.defaults[key]
		return snap(value + range[3] * (if direction < 0 then -1 else 1), range)
	end
	local choices = config.choices[key]
	if choices then
		local index = table.find(choices, current) or 1
		return choices[(index - 1 + (if direction < 0 then -1 else 1)) % #choices + 1]
	end
	if type(config.defaults[key]) == "boolean" then
		return not current
	end
	return current
end

-- The VFX quality a setting stands for: "auto" is the device's default (config.autoQuality; `touch`: a touch device),
-- anything else is itself.
function SettingsRules.quality(chosen: any, touch: boolean, config: any): string
	if chosen == "auto" or config.particleScale[chosen] == nil then
		return if touch then config.autoQuality.touch else config.autoQuality.other
	end
	return chosen
end

-- What the settings mean for the game's effects, with the performance mode and the device (`touch`: a touch device,
-- for the "auto" VFX quality) taken into account.
function SettingsRules.effective(settings: { [string]: any }, config: any, touch: boolean?): Effective
	local performance = settings.performanceMode == true
	local quality = if performance then "low" else SettingsRules.quality(settings.vfxQuality, touch == true, config)
	return {
		vfxQuality = quality,
		particleScale = config.particleScale[quality] or 1,
		heavyDashEffects = quality ~= "low",
		shadows = not performance,
		postEffects = not performance,
		cameraShake = settings.cameraShake == true,
		fov = settings.fov,
		motionEffects = settings.motionEffects == true,
		aimCamera = settings.aimCamera == true,
		aimAssist = settings.aimAssist ~= false,
	}
end

-- the order an input is picked in when neither the chosen nor the detected one is on the device
local FALLBACK = { "touch", "gamepad", "keyboard" }

-- The input the hints, the HUD and the combat camera follow: the chosen one if the device has it, else the detected
-- one if the device has it (a phone never keeps "keyboard" from before, so its HUD does not jump at the first tap),
-- else the first the device has (touch, gamepad, keyboard). `available` says which inputs the device has; `detected`
-- is the last one used.
function SettingsRules.inputKind(chosen: string, available: { [string]: boolean }, detected: string): string
	if chosen ~= "auto" and available[chosen] then
		return chosen
	end
	if available[detected] then
		return detected
	end
	for _, kind in FALLBACK do
		if available[kind] then
			return kind
		end
	end
	return detected -- the device reports no input at all: keep what was used
end

return SettingsRules
