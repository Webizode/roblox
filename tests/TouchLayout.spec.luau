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

	it("moves a saved spot on top of another button to the nearest free spot (not back to its default)", function()
		local defaults = TouchLayout.defaults(936, 432, Config)
		local onJump = { x = defaults.jump.x, y = defaults.jump.y, size = 0.12 }
		local layout = TouchLayout.resolve({ steady = onJump }, 936, 432, 40, Config)
		expect(layout.steady.size).toBe(0.12) -- its size stays
		expect(math.abs(layout.steady.x - defaults.steady.x) > 0.01).toBe(true)
		expect(allApart(layout, 936, 432)).toBe(true)
		-- nearer to where it was put than its default is
		local function from(spot)
			return math.sqrt(((spot.x - onJump.x) * 936) ^ 2 + ((spot.y - onJump.y) * 432) ^ 2)
		end
		expect(from(layout.steady) < from(defaults.steady)).toBe(true)
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

-- Phone test of 20.11.2026: Edit Controls did not keep the layout, and the dash bar, the ice balls and the balance gauge
-- are now movable too. The displays' default rectangles come from the HUD's real plan (UiLayout) on each screen.
local UiLayout = require("../src/shared/UiLayout")
local UiConfig = require("../src/shared/Config/Ui")
local SaveData = require("../src/shared/SaveData")
local EconomyConfig = require("../src/shared/Config/Economy")

-- GUI pixels of real devices (Studio's emulator, landscape) and the same phone held upright
local DEVICES = {
	{ name = "Galaxy A06", width = 705, height = 338 },
	{ name = "iPhone 16 Pro", width = 750, height = 343 },
	{ name = "iPad 10", width = 1180, height = 762 },
	{ name = "phone upright", width = 343, height = 750 },
}

local function setup(device)
	local kind = UiLayout.device(device.width, device.height, "touch", false, UiConfig)
	local bar = { left = 160, right = device.width, height = 58 }
	local plan = UiLayout.plan(device.width, device.height, kind, UiConfig, bar)
	local panels = { dashBar = plan.dash, ammo = plan.ammo, balance = plan.balance }
	local blocked = { plan.top, plan.quick, plan.column, plan.settings, plan.coins, plan.bottom, plan.zones[1] }
	return plan, panels, blocked
end

local function everythingApart(layout, width, height, panels): boolean
	local ids = TouchLayout.ids(Config)
	for i, a in ids do
		for j = i + 1, #ids do
			local b = ids[j]
			if TouchLayout.overlaps(layout[a], layout[b], width, height, Config, a, b, panels) then
				return false
			end
		end
	end
	return true
end

local function everythingOnScreen(layout, width, height, top, panels): boolean
	for _, id in TouchLayout.ids(Config) do
		local spot = layout[id]
		local moved = TouchLayout.inside(spot, width, height, top, id, Config, panels)
		if math.abs(moved.x - spot.x) > 1e-6 or math.abs(moved.y - spot.y) > 1e-6 then
			return false
		end
	end
	return true
end

-- What a player on the iPhone saved: jump bigger and further in, dash bar and balance gauge moved, ice balls bigger.
local function phoneLayout()
	local plan, panels, blocked = setup(DEVICES[2])
	local width, height, top = DEVICES[2].width, DEVICES[2].height, plan.topbar.height
	local working = TouchLayout.resolve(nil, width, height, top, Config, panels, blocked)
	working.jump = { x = 0.86, y = 0.74, size = 0.24 }
	working.balance = { x = 0.55, y = 0.5, scale = 1.2 }
	working.ammo.scale = 1.1
	return TouchLayout.toSave(working, { jump = true, balance = true, ammo = true })
end

describe("Movable displays and a layout that survives (phone test 20.11.2026)", function()
	it("lays out every button and display apart and on the screen on every device, upright too", function()
		for _, device in DEVICES do
			local plan, panels, blocked = setup(device)
			local layout =
				TouchLayout.resolve(nil, device.width, device.height, plan.topbar.height, Config, panels, blocked)
			for _, id in TouchLayout.ids(Config) do
				expect(layout[id] ~= nil).toBe(true)
			end
			expect(everythingOnScreen(layout, device.width, device.height, plan.topbar.height, panels)).toBe(true)
			expect(everythingApart(layout, device.width, device.height, panels)).toBe(true)
		end
	end)

	it("the displays' defaults are exactly the HUD's plan (nothing moves for a player who never edited)", function()
		local plan, panels, blocked = setup(DEVICES[2])
		local layout = TouchLayout.resolve(nil, 750, 343, plan.topbar.height, Config, panels, blocked)
		for id, rect in panels do
			local placed = TouchLayout.panelRect(layout[id], rect, 750, 343)
			expect(placed.x).toBeCloseTo(rect.x, 1e-6)
			expect(placed.y).toBeCloseTo(rect.y, 1e-6)
			expect(placed.w).toBeCloseTo(rect.w, 1e-6)
		end
	end)

	it("a layout saved on one phone keeps every moved element on another phone, a tablet and upright", function()
		local saved = phoneLayout()
		for _, device in DEVICES do
			local plan, panels, blocked = setup(device)
			local top = plan.topbar.height
			local layout = TouchLayout.resolve(saved, device.width, device.height, top, Config, panels, blocked)
			expect(everythingOnScreen(layout, device.width, device.height, top, panels)).toBe(true)
			expect(everythingApart(layout, device.width, device.height, panels)).toBe(true)
			-- sizes stay as saved in landscape; held upright the screen is too full for everything at its size (buttons
			-- are measured in screen heights), so there only the room counts
			if device.width > device.height then
				expect(layout.jump.size).toBe(saved.jump.size)
				expect(layout.balance.scale).toBe(saved.balance.scale)
				expect(layout.ammo.scale).toBe(saved.ammo.scale)
			end
		end
		-- on the phone it was made on, exactly where it was put
		local plan, panels, blocked = setup(DEVICES[2])
		local layout = TouchLayout.resolve(saved, 750, 343, plan.topbar.height, Config, panels, blocked)
		expect(layout.jump.x).toBeCloseTo(saved.jump.x, 1e-9)
		expect(layout.balance.y).toBeCloseTo(saved.balance.y, 1e-9)
	end)

	it("a moved element keeps clear of the HUD's fixed buttons and the move stick", function()
		local plan, panels, blocked = setup(DEVICES[2])
		-- dropped right on the coins (top left) and on the move stick (bottom left)
		local saved = {
			steady = {
				x = (plan.coins.x + plan.coins.w / 2) / 750,
				y = (plan.coins.y + plan.coins.h / 2) / 343,
				size = 0.12,
			},
			dashBar = { x = 0.1, y = 0.85, scale = 1 },
		}
		local layout = TouchLayout.resolve(saved, 750, 343, plan.topbar.height, Config, panels, blocked)
		expect(TouchLayout.free({}, "steady", layout.steady, 750, 343, Config, panels, blocked)).toBe(true)
		expect(TouchLayout.free({}, "dashBar", layout.dashBar, 750, 343, Config, panels, blocked)).toBe(true)
	end)

	it("Save stores only what was moved; Reset (nothing saved) gives the defaults back", function()
		local saved = phoneLayout()
		expect(saved.jump ~= nil and saved.balance ~= nil and saved.ammo ~= nil).toBe(true)
		expect(saved.dash).toBe(nil)
		expect(saved.dashBar).toBe(nil)
		local plan, panels, blocked = setup(DEVICES[2])
		local reset =
			TouchLayout.resolve(TouchLayout.toSave(saved, {}), 750, 343, plan.topbar.height, Config, panels, blocked)
		local defaults = TouchLayout.resolve(nil, 750, 343, plan.topbar.height, Config, panels, blocked)
		for _, id in TouchLayout.ids(Config) do
			expect(reset[id].x).toBe(defaults[id].x)
			expect(reset[id].y).toBe(defaults[id].y)
		end
	end)

	it("saving and loading through the server's checks gives the same layout back", function()
		local saved = phoneLayout()
		-- the client's message checked by the server, stored, sent back and checked again by the client
		local stored = SettingsRules.value("touchLayout", saved, SettingsConfig)
		local loaded = SettingsRules.sanitize({ touchLayout = stored }, SettingsConfig).touchLayout
		expect(SettingsRules.same(loaded, saved)).toBe(true)
		expect(SettingsRules.same(TouchLayout.sanitize(loaded, Config), saved)).toBe(true)
	end)

	it("loads old and broken saves as far as they are good", function()
		-- a save from before the displays (buttons only), one with a broken display, one with garbage
		local old = SettingsRules.value("touchLayout", { jump = { x = 0.8, y = 0.7, size = 0.2 } }, SettingsConfig)
		expect(old.jump.x).toBe(0.8)
		expect(old.ammo).toBe(nil)
		local broken = SettingsRules.value("touchLayout", {
			ammo = { x = 0.5, y = 0.5, scale = 0 / 0 },
			balance = { x = 2, y = -1, scale = 9 },
			dashBar = { x = 0.5, y = 0.5, size = 0.1 }, -- a button's fields on a display
			jump = { x = 0.5, y = 0.5, scale = 1 }, -- a display's fields on a button
		}, SettingsConfig)
		expect(broken.ammo).toBe(nil)
		expect(broken.balance.x).toBe(1)
		expect(broken.balance.y).toBe(0)
		expect(broken.balance.scale).toBe(Config.panels.maxScale)
		expect(broken.dashBar).toBe(nil)
		expect(broken.jump).toBe(nil)
		for _, garbage in { "x", 7, { jump = "left" }, { [1] = { x = 1 } } } do
			expect(next(SettingsRules.value("touchLayout", garbage, SettingsConfig))).toBe(nil)
		end
		-- a whole old save (version 1, no settings) and one whose settings are garbage still load with an empty layout
		for _, raw in { { version = 1, coins = 5 }, { version = 2, settings = "broken" } } do
			local data = SaveData.migrate(raw, EconomyConfig)
			local settings = SettingsRules.sanitize(data.settings, SettingsConfig)
			expect(type(settings.touchLayout)).toBe("table")
			expect(next(settings.touchLayout)).toBe(nil)
		end
	end)

	it("the settings know the same displays and scales as Config/TouchControls", function()
		local spec = SettingsConfig.layouts.touchLayout
		expect(table.concat(spec.panels, ",")).toBe(table.concat(Config.panels.order, ","))
		expect(spec.minScale).toBe(Config.panels.minScale)
		expect(spec.maxScale).toBe(Config.panels.maxScale)
	end)

	it("compares settings values the way the save confirmation needs it", function()
		expect(SettingsRules.same({ a = { x = 0.1 } }, { a = { x = 0.1 + 1e-9 } })).toBe(true)
		expect(SettingsRules.same({ a = { x = 0.1 } }, { a = { x = 0.2 } })).toBe(false)
		expect(SettingsRules.same({ a = 1 }, { a = 1, b = 2 })).toBe(false)
		expect(SettingsRules.same({}, {})).toBe(true)
		expect(SettingsRules.same("auto", "auto")).toBe(true)
	end)
end)
