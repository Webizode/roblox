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
		inputMode = "auto",
		-- how fast the camera turns in combat mode only (outside it Roblox's own camera and settings apply), per input;
		-- 1 = as tuned in Config/Combat camera, up to 3 (300 %)
		mouseSensitivity = 1,
		touchSensitivity = 1,
		gamepadSensitivity = 1,
		controlsHint = true,
	},

	-- numbers: { min, max, step }; the menu's - and + buttons move by one step
	ranges = {
		sfxVolume = { 0, 1, 0.1 },
		musicVolume = { 0, 1, 0.1 },
		fov = { 70, 110, 5 },
		mouseSensitivity = { 0.3, 3, 0.1 },
		touchSensitivity = { 0.3, 3, 0.1 },
		gamepadSensitivity = { 0.3, 3, 0.1 },
	},

	-- choices, in the order the menu's arrows cycle through them
	choices = {
		vfxQuality = { "high", "medium", "low" },
		inputMode = { "auto", "touch", "keyboard", "gamepad" },
	},

	toggles = { "performanceMode", "cameraShake", "motionEffects", "controlsHint" },

	-- what the VFX quality means: particle counts scale, the heavy dash effects (afterimages, limb trails) only above
	-- "low". The performance mode is "low" plus no shadows, bloom or sun rays on this device.
	particleScale = { high = 1, medium = 0.5, low = 0.2 },

	-- background music: a playlist in the Music sound group (MusicPlaylist, Sfx). The songs take turns in random order,
	-- never the same one twice in a row, with pauseMin to pauseMax seconds of quiet between them. An entry with an
	-- empty id is a placeholder and is skipped until it gets one. The musicVolume setting covers every song.
	music = {
		tracks = {
			"rbxassetid://1839029058", -- placeholder: "Happyland", APMOfficial (Roblox's licensed APM library)
			"", -- placeholder, the user's audio id follows
			"", -- placeholder
			"", -- placeholder
		},
		pauseMin = 60, -- seconds of quiet between two songs
		pauseMax = 120,
		volume = 0.5, -- multiplied by the musicVolume setting
	},

	saveDelay = 1, -- seconds after the last change before the client sends its settings
	serverInterval = 1, -- the server takes at most one settings update per this many seconds per player
}
