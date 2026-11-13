--!strict
-- Where the HUD's clusters go on a screen (client/UiKit, HUD): pure, so the Lune tests can lay out every device.
--
-- All sizes in Config/Ui are design pixels at the reference screen (1280 x 720). A screen gets one scale: its size
-- over the reference (the smaller of width and height share), within Config/Ui.scale, and on touch screens never so
-- small that an icon button is smaller than a thumb. Every cluster is a rectangle in screen pixels of the ScreenGui
-- (inside the device's safe area, Roblox's top bar included), already scaled:
--   top       MY PLOT and ARENA with the safe-zone sign under them, top centre, up in the top bar's free part
--   quick     the small MY PLOT button in combat mode, where MY PLOT and ARENA are otherwise (top centre)
--   column    the icon buttons (Upgrades, Cosmetics, Quests, Index, Scoops), left; more columns if one is too tall;
--             on touch screens bigger (Config/Ui.touchIconScale, columnScale) so their labels can be read
--   settings  the gear, top right, also in the top bar's free part (never over Roblox's menu, chat or leaderboard)
--   coins     bottom left; on touch screens top left, the thumbstick sits bottom left
--   bottom    the tower pill, bottom centre
--   dash      the dash bar (the arena): bottom right, as wide as the ice balls' row; on touch screens above the jump
--             and action buttons
--   ammo      the three ice balls (combat mode): right on top of the dash bar
--   balance   the balance gauge (the arena) in combat mode: over the ice balls; on touch screens, where the height is
--             short, left of them (smaller where it would reach the MY PLOT button: balanceScale)
--   balanceLow  the gauge without combat mode: where the ice balls are, so no gap opens over the dash bar (smaller
--             where it would reach the gear or Roblox's buttons: balanceLowScale); on touch screens where that is
--             smaller than in combat mode and the top row leaves room, it stays where it is in combat mode
-- What shows at once: in combat mode quick, settings, coins, bottom, dash, ammo and balance; without it top, column,
-- settings, coins, bottom, dash and balanceLow. Only these must stay apart.
-- On touch screens nothing may reach into Roblox's thumbstick and button zones (Config/Ui.touchZones); a TV gets an
-- extra margin (Config/Ui.tvMargin).

export type Rect = { x: number, y: number, w: number, h: number }
export type Device = "phone" | "tablet" | "pc" | "console"

export type Config = {
	reference: { width: number, height: number },
	margin: number,
	gap: number,
	columnGap: number,
	touchColumnGap: number,
	thumb: number,
	iconButton: number,
	wideButton: { width: number, height: number },
	safeSign: { width: number, height: number },
	settingsButton: number,
	coins: { width: number, height: number },
	bottom: { width: number, height: number },
	ammo: { width: number, height: number },
	dash: { height: number },
	topEdge: number,
	balance: { width: number, height: number },
	quickButton: number,
	touchIconScale: number,
	touchFace: number,
	scale: { min: number, max: number },
	tvMargin: number,
	phoneMaxSide: number,
	touchZones: { [string]: { x: number, y: number, w: number, h: number } },
}

export type Plan = {
	device: Device,
	touch: boolean,
	scale: number,
	frame: Rect, -- the area the HUD may use
	top: Rect,
	quick: Rect,
	column: Rect,
	columns: number, -- how many columns the icon buttons take
	columnScale: number, -- the icon buttons' scale over `scale` (bigger on touch screens)
	groupScale: number, -- the ice balls, the dash bar and the gauge (smaller on touch screens: Config/Ui.touchFace)
	settings: Rect,
	coins: Rect,
	bottom: Rect,
	ammo: Rect,
	dash: Rect,
	balance: Rect,
	balanceLow: Rect,
	balanceScale: number, -- the gauge in combat mode may be smaller than the rest on small touch screens
	balanceLowScale: number, -- and without it, under the gear
	zones: { Rect }, -- what stays free (touch screens)
	topbar: { left: number, right: number, height: number },
	hintWidth: number, -- the widest a hint over the bottom cluster may be
	toastY: number, -- where a toast's top goes
}

-- the icon buttons in the left column
local COLUMN_BUTTONS = 5
-- between the big buttons and the sign under them, design pixels
local TOP_GAP = 8

local UiLayout = {}

-- What kind of screen this is: a TV (ten-foot interface) is a console, a touch screen a phone or a tablet by its
-- shorter side, everything else a PC (also with a gamepad plugged in: the input only changes the badges).
function UiLayout.device(width: number, height: number, input: string, tenFoot: boolean, config: Config): Device
	if tenFoot then
		return "console"
	elseif input == "touch" then
		return if math.min(width, height) <= config.phoneMaxSide then "phone" else "tablet"
	end
	return "pc"
end

function UiLayout.isTouch(device: Device): boolean
	return device == "phone" or device == "tablet"
end

-- The scale from design pixels to screen pixels.
function UiLayout.scale(width: number, height: number, device: Device, config: Config): number
	local scale = math.min(width / config.reference.width, height / config.reference.height)
	if UiLayout.isTouch(device) then
		scale = math.max(scale, config.thumb / math.min(config.iconButton, config.wideButton.height))
	end
	return math.clamp(scale, config.scale.min, config.scale.max)
end

function UiLayout.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function UiLayout.inside(inner: Rect, outer: Rect): boolean
	local epsilon = 1e-6
	return inner.x >= outer.x - epsilon
		and inner.y >= outer.y - epsilon
		and inner.x + inner.w <= outer.x + outer.w + epsilon
		and inner.y + inner.h <= outer.y + outer.h + epsilon
end

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

-- The space between two icon buttons, design pixels: smaller on touch screens, where each button's tap area is already
-- bigger than its picture (touchFace), so the pictures sit close and leave more of the picture free.
function UiLayout.columnGap(touch: boolean, config: Config): number
	return if touch then config.touchColumnGap else config.columnGap
end

-- The size of the icon buttons' block in `columns` columns, screen pixels.
function UiLayout.columnSize(columns: number, scale: number, config: Config, touch: boolean?): (number, number)
	local rows = math.ceil(COLUMN_BUTTONS / columns)
	local button, gap = config.iconButton * scale, UiLayout.columnGap(touch == true, config) * scale
	return columns * button + (columns - 1) * gap, rows * button + (rows - 1) * gap
end

-- The free part of Roblox's top bar (GuiService.TopbarInset, in the ScreenGui's pixels): from `left` to `right`, `height`
-- tall. Without a top bar (a TV, hidden core UI) it is the whole width and 0 high.
export type Topbar = { left: number, right: number, height: number }

function UiLayout.plan(width: number, height: number, device: Device, config: Config, topbar: Topbar?): Plan
	local bar: Topbar = topbar or { left = 0, right = width, height = 0 }
	local touch = UiLayout.isTouch(device)
	local scale = UiLayout.scale(width, height, device, config)
	local gap = config.gap * scale
	local marginX, marginY = config.margin * scale, config.margin * scale
	local tvX, tvY = 0, 0
	if device == "console" then
		tvX, tvY = width * config.tvMargin, height * config.tvMargin
		marginX += tvX
		marginY += tvY
	end
	-- everything but the top row stays under the top bar
	local frameTop = math.max(marginY, bar.height + config.margin * scale)
	local frame = rect(marginX, frameTop, width - 2 * marginX, height - frameTop - marginY)
	local right, bottomEdge = frame.x + frame.w, frame.y + frame.h

	local zones: { Rect } = {}
	if touch then
		for _, name in { "stick", "buttons" } do
			local zone = config.touchZones[name]
			table.insert(zones, rect(zone.x * width, zone.y * height, zone.w * width, zone.h * height))
		end
	end

	-- the top row (MY PLOT, ARENA, the gear) sits up in the top bar's free middle, close to the screen's edge
	local topY = math.max(tvY, 0) + config.topEdge * scale
	local barLeft, barRight = bar.left + gap, math.min(bar.right - gap, width - marginX)

	local settingsSize = config.settingsButton * scale
	local settings = rect(barRight - settingsSize, topY, settingsSize, settingsSize)

	local topW = (2 * config.wideButton.width + config.gap) * scale
	local topH = (config.wideButton.height + TOP_GAP + config.safeSign.height) * scale
	-- the dash bar bottom right (on touch screens above the jump and action buttons), the ice balls right on it; the
	-- group is drawn smaller on touch screens (Config/Ui.touchFace)
	local groupScale = if touch then scale * config.touchFace else scale
	local ammoW, ammoH = config.ammo.width * groupScale, config.ammo.height * groupScale
	local dashH = config.dash.height * groupScale
	local dashBottom = if touch then zones[2].y - gap else bottomEdge
	local dash = rect(right - ammoW, dashBottom - dashH, ammoW, dashH)
	local ammo = rect(right - ammoW, dash.y - ammoH, ammoW, ammoH)

	local topX = math.clamp((width - topW) / 2, barLeft, math.max(barLeft, settings.x - gap - topW))
	local top = rect(topX, topY, topW, topH)
	local quickSize = config.quickButton * scale -- a thumb wide on touch screens
	local quick = rect(top.x + (top.w - quickSize) / 2, topY, quickSize, quickSize)

	-- the balance gauge. In combat mode (only the small MY PLOT button is up top then) over the ice balls; on touch
	-- screens, where the height is short, right beside the ice balls and the dash bar as one block, shrunk where it
	-- would reach the MY PLOT button. Without combat mode (the top row is up, the ice balls are gone) in their place,
	-- shrunk where it would reach the gear.
	local function gauge(atScale: number, rightEdge: number, bottomY: number): Rect
		local w, h = config.balance.width * atScale, config.balance.height * atScale
		return rect(rightEdge - w, bottomY - h, w, h)
	end
	local balanceScale = groupScale
	local balance
	if touch then
		local gap2 = gap * config.touchFace
		local floor = dash.y + dash.h
		local roomX = ammo.x - gap2 - (quick.x + quick.w + gap)
		local roomY = floor - (math.max(topY + quickSize, if ammo.x > bar.right then bar.height else 0) + gap)
		if config.balance.height * groupScale > roomY and config.balance.width * groupScale > roomX then
			balanceScale = math.max(roomX / config.balance.width, roomY / config.balance.height)
		end
		balance = gauge(balanceScale, ammo.x - gap2, floor)
	else
		balance = gauge(scale, right, ammo.y - gap)
	end
	-- right of the top bar's free part (Roblox's own buttons) it stays under the bar
	local ceiling = math.max(settings.y + settings.h, if right > bar.right then bar.height else 0) + gap
	local balanceLowScale = math.min(groupScale, (ammo.y + ammo.h - ceiling) / config.balance.height)
	local balanceLow = gauge(balanceLowScale, right, ammo.y + ammo.h)
	-- where that makes it smaller than in combat mode, it stays where it is in combat mode, if the top row allows
	if
		touch
		and balanceScale > balanceLowScale
		and not UiLayout.overlaps(balance, rect(top.x - gap, top.y, top.w + 2 * gap, top.h + gap))
	then
		balanceLow, balanceLowScale = balance, balanceScale
	end

	local coinsW, coinsH = config.coins.width * scale, config.coins.height * scale
	local coins = if touch
		then rect(frame.x, frame.y, coinsW, coinsH)
		else rect(frame.x, bottomEdge - coinsH, coinsW, coinsH)

	-- the icon buttons: between the coins and the thumbstick on touch screens, else centred above the coins
	local columnScale = if touch then config.touchIconScale else 1
	local spaceTop = if touch then coins.y + coins.h + gap else frame.y
	local spaceBottom = if touch then zones[1].y - gap else coins.y - gap
	local columns, columnW, columnH = 1, 0, 0
	for count = 1, COLUMN_BUTTONS do
		columns = count
		columnW, columnH = UiLayout.columnSize(count, scale * columnScale, config, touch)
		if columnH <= spaceBottom - spaceTop then
			break
		end
	end
	local columnY = if touch then spaceTop else spaceTop + math.max(0, (spaceBottom - spaceTop - columnH) / 2)
	local column = rect(frame.x, columnY, columnW, columnH)

	local bottomW, bottomH = config.bottom.width * scale, config.bottom.height * scale
	local bottom = rect(frame.x + (frame.w - bottomW) / 2, bottomEdge - bottomH, bottomW, bottomH)

	-- a hint is as wide as the space between the touch zones allows, else up to half the screen
	local centre = frame.x + frame.w / 2
	local hintWidth = frame.w / 2
	if touch then
		local stickRight = zones[1].x + zones[1].w
		local buttonsLeft = zones[2].x
		hintWidth = math.min(hintWidth, 2 * math.min(centre - stickRight, buttonsLeft - centre) - 2 * gap)
	end

	return {
		device = device,
		touch = touch,
		scale = scale,
		frame = frame,
		top = top,
		quick = quick,
		column = column,
		columns = columns,
		columnScale = columnScale,
		groupScale = groupScale,
		settings = settings,
		coins = coins,
		bottom = bottom,
		ammo = ammo,
		dash = dash,
		balance = balance,
		balanceLow = balanceLow,
		balanceScale = balanceScale,
		balanceLowScale = balanceLowScale,
		zones = zones,
		topbar = bar,
		hintWidth = hintWidth,
		toastY = top.y + top.h + gap,
	}
end

return UiLayout
