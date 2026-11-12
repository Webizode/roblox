local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local UiLayout = require("../src/shared/UiLayout")
local Config = require("../src/shared/Config/Ui")

-- screens as the HUD's ScreenGui sees them: inside the device's safe area, with the free part of Roblox's top bar
-- (menu and chat on the left, sometimes more on the right)
local SCREENS = {
	{
		name = "small phone",
		width = 667,
		height = 375,
		input = "touch",
		bar = { left = 120, right = 667, height = 58 },
	},
	{ name = "phone", width = 844, height = 390, input = "touch", bar = { left = 120, right = 790, height = 58 } },
	{ name = "big phone", width = 932, height = 430, input = "touch", bar = { left = 120, right = 932, height = 58 } },
	{ name = "tablet", width = 1024, height = 768, input = "touch", bar = { left = 120, right = 1024, height = 58 } },
	{
		name = "big tablet",
		width = 1366,
		height = 1024,
		input = "touch",
		bar = { left = 120, right = 1300, height = 58 },
	},
	{
		name = "laptop",
		width = 1280,
		height = 720,
		input = "keyboard",
		bar = { left = 160, right = 1280, height = 58 },
	},
	{ name = "pc", width = 1920, height = 1080, input = "keyboard", bar = { left = 160, right = 1860, height = 58 } },
	{
		name = "pc with gamepad",
		width = 1920,
		height = 1080,
		input = "gamepad",
		bar = { left = 160, right = 1920, height = 58 },
	},
	{ name = "tv", width = 1920, height = 1080, input = "gamepad", tenFoot = true },
}

local CLUSTERS = { "top", "quick", "column", "settings", "coins", "bottom", "dash", "ammo", "balance", "balanceLow" }
-- what shows at once: in combat mode, and without it
local TOGETHER = {
	{ "quick", "settings", "coins", "bottom", "dash", "ammo", "balance" },
	{ "top", "column", "settings", "coins", "bottom", "dash", "balanceLow" },
}
-- what may go up into the free part of Roblox's top bar
local UP_TOP = { top = true, quick = true, settings = true, balance = true, balanceLow = true }

local function planFor(screen)
	local device = UiLayout.device(screen.width, screen.height, screen.input, screen.tenFoot == true, Config)
	return UiLayout.plan(screen.width, screen.height, device, Config, screen.bar)
end

describe("UI layout: devices", function()
	it("tells phones, tablets, PCs and TVs apart", function()
		expect(UiLayout.device(844, 390, "touch", false, Config)).toBe("phone")
		expect(UiLayout.device(1024, 768, "touch", false, Config)).toBe("tablet")
		expect(UiLayout.device(1920, 1080, "keyboard", false, Config)).toBe("pc")
		expect(UiLayout.device(1920, 1080, "gamepad", false, Config)).toBe("pc")
		expect(UiLayout.device(1920, 1080, "gamepad", true, Config)).toBe("console")
	end)

	it("scales with the screen, within bounds", function()
		local small = UiLayout.scale(1280, 720, "pc", Config)
		local big = UiLayout.scale(1920, 1080, "pc", Config)
		expect(small).toBe(1)
		expect(big).toBe(1.5)
		expect(UiLayout.scale(7680, 4320, "pc", Config)).toBe(Config.scale.max)
		expect(UiLayout.scale(400, 200, "pc", Config)).toBe(Config.scale.min)
	end)
end)

describe("UI layout: every screen", function()
	it("keeps every cluster inside the safe frame and apart from the others", function()
		for _, screen in SCREENS do
			local plan = planFor(screen)
			local tv = if screen.tenFoot then Config.tvMargin else 0
			local screenRect = {
				x = screen.width * tv,
				y = screen.height * tv,
				w = screen.width * (1 - 2 * tv),
				h = screen.height * (1 - 2 * tv),
			}
			local bar = plan.topbar
			for _, name in CLUSTERS do
				local cluster = plan[name]
				if not UiLayout.inside(cluster, screenRect) then
					error(`{screen.name}: {name} leaves the screen`)
				end
				-- up in the top bar only within its free part, never over Roblox's menu, chat or leaderboard
				if cluster.y < bar.height and (cluster.x < bar.left or cluster.x + cluster.w > bar.right) then
					error(`{screen.name}: {name} covers Roblox's top bar`)
				end
				if not UP_TOP[name] and cluster.y < bar.height then
					error(`{screen.name}: {name} reaches into the top bar`)
				end
			end
			for _, shown in TOGETHER do
				for index, name in shown do
					for other = index + 1, #shown do
						if UiLayout.overlaps(plan[name], plan[shown[other]]) then
							error(`{screen.name}: {name} overlaps {shown[other]}`)
						end
					end
				end
			end
		end
	end)

	it("leaves the thumbstick and the jump and action buttons free on touch screens", function()
		for _, screen in SCREENS do
			local plan = planFor(screen)
			expect(#plan.zones).toBe(if screen.input == "touch" then 2 else 0)
			for _, zone in plan.zones do
				for _, name in CLUSTERS do
					if UiLayout.overlaps(plan[name], zone) then
						error(`{screen.name}: {name} covers a touch control`)
					end
				end
			end
		end
	end)

	it("makes every touch target at least a thumb wide", function()
		for _, screen in SCREENS do
			local plan = planFor(screen)
			if plan.touch then
				expect(Config.iconButton * plan.scale >= Config.thumb - 1e-6).toBe(true)
				expect(Config.wideButton.height * plan.scale >= Config.thumb - 1e-6).toBe(true)
				expect(Config.settingsButton * plan.scale >= Config.thumb * 0.9).toBe(true)
			end
		end
	end)

	it("keeps a TV's overscan margin and the hint between the touch zones", function()
		local tv = planFor(SCREENS[#SCREENS])
		expect(tv.frame.x >= 1920 * Config.tvMargin).toBe(true)
		expect(tv.frame.y >= 1080 * Config.tvMargin).toBe(true)
		for _, screen in SCREENS do
			local plan = planFor(screen)
			expect(plan.hintWidth > 0).toBe(true)
			expect(plan.columns <= 5).toBe(true) -- the smallest phones get one row under the coins
			-- the gauge stays readable
			expect(Config.balance.width * math.min(plan.balanceScale, plan.balanceLowScale) >= 60).toBe(true)
		end
	end)

	it("puts the coins top left on touch screens and bottom left elsewhere", function()
		local phone, pc = planFor(SCREENS[2]), planFor(SCREENS[7])
		expect(phone.coins.y).toBe(phone.frame.y)
		expect(pc.coins.y + pc.coins.h).toBe(pc.frame.y + pc.frame.h)
	end)
end)

describe("UI layout: the top row and the ice balls", function()
	it("puts MY PLOT, ARENA and the gear close to the top, in the top bar's free part", function()
		for _, screen in SCREENS do
			local plan = planFor(screen)
			local tv = if screen.tenFoot then screen.height * Config.tvMargin else 0
			expect(plan.top.y <= tv + Config.topEdge * plan.scale + 1e-6).toBe(true)
			expect(plan.settings.y).toBe(plan.top.y)
			expect(plan.settings.x + plan.settings.w <= plan.topbar.right).toBe(true)
		end
	end)

	it("puts the small MY PLOT button of combat mode up in the top bar's free part, a thumb wide", function()
		for _, screen in SCREENS do
			local plan = planFor(screen)
			local quick, bar = plan.quick, plan.topbar
			expect(UiLayout.inside(quick, plan.top)).toBe(true)
			expect(quick.x >= bar.left and quick.x + quick.w <= bar.right).toBe(true)
			if plan.touch then
				expect(quick.w >= Config.thumb - 1e-6).toBe(true)
			end
			for _, name in { "column", "settings", "coins", "bottom", "dash", "ammo", "balance", "balanceLow" } do
				if UiLayout.overlaps(quick, plan[name]) then
					error(`{screen.name}: the MY PLOT button overlaps {name}`)
				end
			end
		end
	end)

	it("makes the icon buttons bigger on touch screens", function()
		for _, screen in SCREENS do
			local plan = planFor(screen)
			local button = Config.iconButton * plan.scale * plan.columnScale
			if plan.touch then
				expect(button >= 60).toBe(true) -- big enough for a readable label
			else
				expect(plan.columnScale).toBe(1)
			end
		end
	end)

	it("puts the dash bar bottom right with the ice balls on it, over the action buttons on touch screens", function()
		local function near(a, b)
			return math.abs(a - b) < 1e-6
		end
		for _, screen in SCREENS do
			local plan = planFor(screen)
			local ammo, dash = plan.ammo, plan.dash
			expect(near(dash.x + dash.w, plan.frame.x + plan.frame.w)).toBe(true)
			expect(near(dash.x, ammo.x) and near(dash.w, ammo.w)).toBe(true) -- as wide as the row
			expect(near(ammo.y + ammo.h, dash.y)).toBe(true)
			if plan.touch then
				expect(dash.y + dash.h <= plan.zones[2].y).toBe(true)
			else
				expect(near(dash.y + dash.h, plan.frame.y + plan.frame.h)).toBe(true)
			end
			-- big enough to count at a glance
			expect(Config.ammo.ball * plan.scale >= 44).toBe(true)
		end
	end)

	it(
		"puts the balance gauge over the ice balls, or beside them on touch screens, and in their place without them",
		function()
			for _, screen in SCREENS do
				local plan = planFor(screen)
				local balance, low, ammo = plan.balance, plan.balanceLow, plan.ammo
				local dash = plan.dash
				if plan.touch then
					-- one block: right beside the ice balls and the dash bar, its foot level with the dash bar's
					expect(balance.x + balance.w <= ammo.x).toBe(true)
					expect(ammo.x - (balance.x + balance.w) <= Config.gap * plan.scale + 1e-6).toBe(true)
					expect(math.abs(balance.y + balance.h - (dash.y + dash.h)) < 1e-6).toBe(true)
				else
					expect(balance.y + balance.h <= ammo.y).toBe(true)
				end
				-- without combat mode: in the ice balls' place right over the dash bar, or (touch screens) where it is in
				-- combat mode
				local inPlace = math.abs(low.y + low.h - dash.y) < 1e-6
					and math.abs(low.x + low.w - (ammo.x + ammo.w)) < 1e-6
				expect(inPlace or (plan.touch and low == balance)).toBe(true)
				expect(low.y >= 0).toBe(true)
				for _, zone in plan.zones do
					expect(UiLayout.overlaps(low, zone)).toBe(false)
				end
				for _, name in { "top", "column", "settings", "coins", "bottom", "dash" } do
					if UiLayout.overlaps(low, plan[name]) then
						error(`{screen.name}: the gauge without combat mode overlaps {name}`)
					end
				end
			end
		end
	)
end)
