local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local SettingsRules = require("../src/shared/SettingsRules")
local Config = require("../src/shared/Config/Settings")

describe("Settings: checking values", function()
	it("nothing or garbage gives all defaults", function()
		for _, raw in { nil, 5, "x", {} } do
			local clean = SettingsRules.sanitize(raw, Config)
			for key, default in Config.defaults do
				expect(clean[key]).toBe(default)
			end
		end
	end)

	it("the FOV default is 80 and stays between 70 and 110", function()
		expect(Config.defaults.fov).toBe(80)
		expect(SettingsRules.value("fov", 200, Config)).toBe(110)
		expect(SettingsRules.value("fov", 10, Config)).toBe(70)
		expect(SettingsRules.value("fov", 92, Config)).toBe(90) -- snapped to the 5-step
	end)

	it("volumes stay between 0 and 1 in clean tenths", function()
		expect(SettingsRules.value("sfxVolume", 1.7, Config)).toBe(1)
		expect(SettingsRules.value("sfxVolume", -1, Config)).toBe(0)
		expect(SettingsRules.value("musicVolume", 0.34, Config)).toBe(0.3)
	end)

	it("broken numbers, unknown choices and wrong types fall back to the default", function()
		expect(SettingsRules.value("fov", 0 / 0, Config)).toBe(Config.defaults.fov)
		expect(SettingsRules.value("fov", math.huge, Config)).toBe(Config.defaults.fov)
		expect(SettingsRules.value("vfxQuality", "ultra", Config)).toBe(Config.defaults.vfxQuality)
		expect(SettingsRules.value("inputMode", 3, Config)).toBe(Config.defaults.inputMode)
		expect(SettingsRules.value("cameraShake", "yes", Config)).toBe(Config.defaults.cameraShake)
	end)

	it("keeps valid values and drops unknown keys", function()
		local clean = SettingsRules.sanitize(
			{ vfxQuality = "low", cameraShake = false, inputMode = "gamepad", hacked = 1 },
			Config
		)
		expect(clean.vfxQuality).toBe("low")
		expect(clean.cameraShake).toBe(false)
		expect(clean.inputMode).toBe("gamepad")
		expect(clean.hacked).toBeNil()
		expect(SettingsRules.value("hacked", 1, Config)).toBeNil()
	end)
end)

describe("Settings: the menu buttons", function()
	it("numbers move one step and stop at the ends", function()
		expect(SettingsRules.step("fov", 80, 1, Config)).toBe(85)
		expect(SettingsRules.step("fov", 80, -1, Config)).toBe(75)
		expect(SettingsRules.step("fov", 110, 1, Config)).toBe(110)
		expect(SettingsRules.step("sfxVolume", 0.8, 1, Config)).toBe(0.9)
		expect(SettingsRules.step("sfxVolume", 0, -1, Config)).toBe(0)
	end)

	it("choices cycle round both ways", function()
		expect(SettingsRules.step("vfxQuality", "high", 1, Config)).toBe("medium")
		expect(SettingsRules.step("vfxQuality", "low", 1, Config)).toBe("high")
		expect(SettingsRules.step("vfxQuality", "high", -1, Config)).toBe("low")
	end)

	it("toggles flip", function()
		expect(SettingsRules.step("controlsHint", true, 1, Config)).toBe(false)
		expect(SettingsRules.step("controlsHint", false, -1, Config)).toBe(true)
	end)
end)

describe("Settings: what they mean for the effects", function()
	it("VFX quality scales particles; low drops the heavy dash effects", function()
		local settings = SettingsRules.sanitize({ vfxQuality = "medium" }, Config)
		local effects = SettingsRules.effective(settings, Config)
		expect(effects.vfxQuality).toBe("medium")
		expect(effects.particleScale).toBe(Config.particleScale.medium)
		expect(effects.heavyDashEffects).toBe(true)
		expect(effects.shadows).toBe(true)
		settings.vfxQuality = "low"
		expect(SettingsRules.effective(settings, Config).heavyDashEffects).toBe(false)
	end)

	it("the performance mode means low VFX plus no shadows and post effects, whatever the quality says", function()
		local settings = SettingsRules.sanitize({ vfxQuality = "high", performanceMode = true }, Config)
		local effects = SettingsRules.effective(settings, Config)
		expect(effects.vfxQuality).toBe("low")
		expect(effects.particleScale).toBe(Config.particleScale.low)
		expect(effects.heavyDashEffects).toBe(false)
		expect(effects.shadows).toBe(false)
		expect(effects.postEffects).toBe(false)
	end)

	it("camera settings pass through", function()
		local settings = SettingsRules.sanitize({ cameraShake = false, fov = 100, motionEffects = false }, Config)
		local effects = SettingsRules.effective(settings, Config)
		expect(effects.cameraShake).toBe(false)
		expect(effects.fov).toBe(100)
		expect(effects.motionEffects).toBe(false)
	end)
end)

describe("Settings: input", function()
	local all = { touch = true, keyboard = true, gamepad = true }

	it("automatic follows the input in use", function()
		expect(SettingsRules.inputKind("auto", all, "gamepad")).toBe("gamepad")
	end)

	it("a chosen input wins when the device has it, otherwise the detected one", function()
		expect(SettingsRules.inputKind("touch", all, "keyboard")).toBe("touch")
		expect(SettingsRules.inputKind("gamepad", { touch = true }, "touch")).toBe("touch")
	end)
end)

describe("Settings: camera sensitivity", function()
	local KEYS = { "mouseSensitivity", "touchSensitivity", "gamepadSensitivity" }

	it("one for mouse, touch and controller each, 1 by default, an old save without them gets 1", function()
		local clean = SettingsRules.sanitize({ fov = 90 }, Config)
		for _, key in KEYS do
			expect(Config.defaults[key]).toBe(1)
			expect(clean[key]).toBe(1)
		end
	end)

	it("stays within 0.3 and 3 (300 %) in tenths, and broken values fall back to the default", function()
		for _, key in KEYS do
			expect(SettingsRules.value(key, 10, Config)).toBe(3)
			expect(SettingsRules.value(key, 2.5, Config)).toBeCloseTo(2.5, 1e-9)
			expect(SettingsRules.value(key, 0, Config)).toBe(0.3)
			expect(SettingsRules.value(key, 1.23, Config)).toBeCloseTo(1.2, 1e-9)
			expect(SettingsRules.value(key, 0 / 0, Config)).toBe(1)
			expect(SettingsRules.value(key, "fast", Config)).toBe(1)
		end
	end)

	it("the menu moves it a tenth at a time and stops at the ends", function()
		expect(SettingsRules.step("mouseSensitivity", 1, 1, Config)).toBeCloseTo(1.1, 1e-9)
		expect(SettingsRules.step("touchSensitivity", 3, 1, Config)).toBe(3)
		expect(SettingsRules.step("gamepadSensitivity", 0.3, -1, Config)).toBe(0.3)
	end)
end)

describe("Settings: the crosshair is fixed", function()
	it("an old save with crosshair values still loads; the values are simply dropped", function()
		local clean = SettingsRules.sanitize(
			{ crosshairStyle = "cross", crosshairSize = 1.75, crosshairColor = "mint", fov = 95 },
			Config
		)
		expect(clean.crosshairStyle).toBeNil()
		expect(clean.crosshairSize).toBeNil()
		expect(clean.crosshairColor).toBeNil()
		expect(clean.fov).toBe(95) -- everything else is kept
		expect(Config.defaults.crosshairSize).toBeNil()
		expect(Config.defaults.crosshairColor).toBeNil()
	end)
end)
