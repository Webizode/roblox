local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local TouchLayout = require("../src/shared/TouchLayout")
local Config = require("../src/shared/Config/TouchControls")

-- a 19.5:9 phone in GUI pixels, a 4:3 tablet, a PC
local SCREENS = { { 936, 432 }, { 1024, 768 }, { 1920, 1080 } }

local function allApart(layout, width, height): boolean
	for a, spotA in layout do
		for b, spotB in layout do
			if a < b and TouchLayout.overlaps(spotA, spotB, width, height, Config) then
				return false
			end
		end
	end
	return true
end

local function onScreen(spot, width, height, top): boolean
	local radius = spot.size * height / 2
	local x, y = spot.x * width, spot.y * height
	return x - radius >= -0.001
		and x + radius <= width + 0.001
		and y - radius >= top - 0.001
		and y + radius <= height + 0.001
end

describe("TouchLayout", function()
	it("has every button of the order in the defaults, all apart and on screen, on every screen shape", function()
		for _, screen in SCREENS do
			local width, height = screen[1], screen[2]
			local layout = TouchLayout.resolve(nil, width, height, 40, Config)
			for _, id in Config.order do
				expect(layout[id] ~= nil).toBe(true)
				expect(onScreen(layout[id], width, height, 40)).toBe(true)
			end
			expect(allApart(layout, width, height)).toBe(true)
		end
	end)

	it("keeps the defaults right of the move stick's side (40 % of the width)", function()
		for _, screen in SCREENS do
			local width, height = screen[1], screen[2]
			for _, spot in TouchLayout.defaults(width, height, Config) do
				expect(spot.x * width - spot.size * height / 2 > 0.4 * width).toBe(true)
			end
		end
	end)

	it("sanitizes a saved layout: unknown buttons out, numbers checked and clamped", function()
		local clean = TouchLayout.sanitize({
			jump = { x = 1.4, y = -2, size = 5 },
			dash = { x = 0 / 0, y = 0.5, size = 0.1 },
			sprint = "no",
			hacker = { x = 0.5, y = 0.5, size = 0.1 },
			steady = { x = 0.3, y = 0.6, size = 0.01 },
		}, Config)
		expect(clean.jump.x).toBe(1)
		expect(clean.jump.y).toBe(0)
		expect(clean.jump.size).toBe(Config.maxSize)
		expect(clean.dash).toBe(nil)
		expect(clean.sprint).toBe(nil)
		expect(clean.hacker).toBe(nil)
		expect(clean.steady.size).toBe(Config.minSize)
		expect(next(TouchLayout.sanitize("nothing", Config))).toBe(nil)
	end)

	it("moves a saved button back onto the screen and below the top bar", function()
		local spot = TouchLayout.inside({ x = 1, y = 0, size = 0.2 }, 936, 432, 40)
		expect(onScreen(spot, 936, 432, 40)).toBe(true)
	end)

	it("takes a saved spot that fits and keeps the saved size", function()
		local layout = TouchLayout.resolve({ steady = { x = 0.5, y = 0.5, size = 0.15 } }, 936, 432, 40, Config)
		expect(layout.steady.x).toBe(0.5)
		expect(layout.steady.size).toBe(0.15)
	end)

	it("gives a saved spot on top of another button back its default", function()
		local defaults = TouchLayout.defaults(936, 432, Config)
		local onJump = { x = defaults.jump.x, y = defaults.jump.y, size = 0.12 }
		local layout = TouchLayout.resolve({ steady = onJump }, 936, 432, 40, Config)
		expect(layout.steady.x).toBe(defaults.steady.x)
		expect(allApart(layout, 936, 432)).toBe(true)
	end)

	it("knows when a spot is free", function()
		local layout = TouchLayout.resolve(nil, 936, 432, 40, Config)
		expect(TouchLayout.free(layout, "steady", layout.jump, 936, 432, Config)).toBe(false)
		expect(TouchLayout.free(layout, "jump", layout.jump, 936, 432, Config)).toBe(true)
		expect(TouchLayout.free(layout, "steady", { x = 0.5, y = 0.3, size = 0.1 }, 936, 432, Config)).toBe(true)
	end)
end)

local SettingsRules = require("../src/shared/SettingsRules")
local SettingsConfig = require("../src/shared/Config/Settings")

describe("the saved touch layout (SettingsRules)", function()
	it("knows the same buttons and sizes as Config/TouchControls", function()
		local spec = SettingsConfig.layouts.touchLayout
		expect(table.concat(spec.ids, ",")).toBe(table.concat(Config.order, ","))
		expect(spec.minSize).toBe(Config.minSize)
		expect(spec.maxSize).toBe(Config.maxSize)
	end)

	it("keeps good spots and drops broken ones before saving", function()
		local clean = SettingsRules.value("touchLayout", {
			jump = { x = 0.8, y = 0.7, size = 0.2 },
			dash = { x = "left", y = 0.5, size = 0.1 },
			other = { x = 0.1, y = 0.1, size = 0.1 },
		}, SettingsConfig)
		expect(clean.jump.x).toBe(0.8)
		expect(clean.dash).toBe(nil)
		expect(clean.other).toBe(nil)
		expect(next(SettingsRules.value("touchLayout", 5, SettingsConfig))).toBe(nil)
		expect(type(SettingsRules.sanitize({}, SettingsConfig).touchLayout)).toBe("table")
	end)
end)
