--!strict
-- The settings menu (SettingsController) and what each setting may hold. SettingsRules checks every value against
-- this, on the client and on the server, before anything is applied or saved.

return {
	defaults = {
		sfxVolume = 0.8,
		musicVolume = 0.5,
		vfxQuality = "high",
		performanceMode = false,
		cameraShake = true,
		fov = 80,
		motionEffects = true, -- FOV kick on sprint and dash, the zoom while charging a throw
		crosshairStyle = "ring",
		crosshairSize = 1,
		crosshairColor = "vanilla",
		inputMode = "auto",
		controlsHint = true,
	},

	-- numbers: { min, max, step }; the menu's - and + buttons move by one step
	ranges = {
		sfxVolume = { 0, 1, 0.1 },
		musicVolume = { 0, 1, 0.1 },
		fov = { 70, 110, 5 },
		crosshairSize = { 0.5, 2, 0.25 },
	},

	-- choices, in the order the menu's arrows cycle through them
	choices = {
		vfxQuality = { "high", "medium", "low" },
		crosshairStyle = { "ring", "dot", "cross" },
		crosshairColor = { "vanilla", "lemon", "mint", "strawberry", "skyTop" }, -- Palette tokens
		inputMode = { "auto", "touch", "keyboard", "gamepad" },
	},

	toggles = { "performanceMode", "cameraShake", "motionEffects", "controlsHint" },

	-- what the VFX quality means: particle counts scale, the heavy dash effects (afterimages, limb trails) only above
	-- "low". The performance mode is "low" plus no shadows, bloom or sun rays on this device.
	particleScale = { high = 1, medium = 0.5, low = 0.2 },

	-- background music, looped in the Music sound group. Placeholder from Roblox's licensed APM library.
	music = {
		id = "rbxassetid://1839029058", -- "Happyland", APMOfficial
		volume = 0.5, -- multiplied by the musicVolume setting
	},

	saveDelay = 1, -- seconds after the last change before the client sends its settings
	serverInterval = 1, -- the server takes at most one settings update per this many seconds per player
}
