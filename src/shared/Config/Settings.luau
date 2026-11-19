--!strict
-- The settings menu (SettingsController) and what each setting may hold. SettingsRules checks every value against
-- this, on the client and on the server, before anything is applied or saved.

return {
	defaults = {
		sfxVolume = 0.8,
		musicVolume = 0.5,
		vfxQuality = "auto", -- the device decides (autoQuality) until the player picks one
		performanceMode = false,
		cameraShake = true,
		fov = 80,
		motionEffects = true, -- FOV kick on sprint and dash, the narrower view while charging a throw
		aimCamera = true, -- the camera moves over the shoulder and closer while a throw is charged (AimCamera)
		inputMode = "auto",
		-- how fast the camera turns in combat mode only (outside it Roblox's own camera and settings apply), per input;
		-- 1 = as tuned in Config/Combat camera, up to 3 (300 %)
		mouseSensitivity = 1,
		touchSensitivity = 1,
		gamepadSensitivity = 1,
		-- aim help (since the kill test of 13.11.2026): the ball homes in on a rival near the crosshair and the combat
		-- camera slows and draws towards them (Config/Combat homing, aimAssist); off for whoever wants it harder
		aimAssist = true,
		-- the controls overview at the right edge in combat mode: off by default (the tutorial teaches the controls), for
		-- whoever wants it
		controlsHint = false,
		-- the touch action buttons' own places from Edit Controls (TouchControls, TouchLayout): per button its centre as
		-- shares of the screen and its size in screen heights; empty = the default places
		touchLayout = {},
	},

	-- layouts: settings that hold a table of button spots (TouchLayout). Only these buttons, each { x, y, size } with x and
	-- y within 0..1 and size within minSize..maxSize (the same as Config/TouchControls, which the client uses)
	layouts = {
		touchLayout = { ids = { "jump", "throw", "dash", "sprint", "combat", "steady" }, minSize = 0.09, maxSize = 0.3 },
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
		vfxQuality = { "auto", "high", "medium", "low" },
		inputMode = { "auto", "touch", "keyboard", "gamepad" },
	},

	toggles = { "performanceMode", "cameraShake", "motionEffects", "aimCamera", "controlsHint", "aimAssist" },

	-- what the VFX quality means: particle counts scale, the heavy dash effects (afterimages, limb trails) only above
	-- "low". The performance mode is "low" plus no shadows, bloom or sun rays on this device.
	particleScale = { high = 1, medium = 0.5, low = 0.2 },
	-- what "auto" means: medium on a touch device (phones and tablets), high everywhere else
	autoQuality = { touch = "medium", other = "high" },

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
