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
		expect(SettingsRules.value("crosshairColor", 3, Config)).toBe(Config.defaults.crosshairColor)
		expect(SettingsRules.value("cameraShake", "yes", Config)).toBe(Config.defaults.cameraShake)
	end)

	it("keeps valid values and drops unknown keys", function()
		local clean = SettingsRules.sanitize(
			{ vfxQuality = "low", cameraShake = false, crosshairColor = "mint", hacked = 1 },
			Config
		)
		expect(clean.vfxQuality).toBe("low")
		expect(clean.cameraShake).toBe(false)
		expect(clean.crosshairColor).toBe("mint")
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
		expect(effects.particleScale).toBe(Config.particleScale.medium)
		expect(effects.heavyDashEffects).toBe(true)
		expect(effects.shadows).toBe(true)
		settings.vfxQuality = "low"
		expect(SettingsRules.effective(settings, Config).heavyDashEffects).toBe(false)
	end)

	it("the performance mode means low VFX plus no shadows and post effects, whatever the quality says", function()
		local settings = SettingsRules.sanitize({ vfxQuality = "high", performanceMode = true }, Config)
		local effects = SettingsRules.effective(settings, Config)
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
