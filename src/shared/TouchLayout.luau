--!strict
-- Where the touch action buttons and the movable displays sit (client TouchControls and its Edit Controls mode, Hud;
-- the saved layout in the settings, SettingsRules). Pure: the config (Config/TouchControls) is passed in.
--
-- A button's spot is its centre as a share of the screen's width (x) and height (y) and its diameter in screen
-- heights (size). A display's spot (the dash bar, the ice balls, the balance gauge: config.panels) is its centre the
-- same way and its scale against the size the HUD's plan gives it on that screen (scale). So a saved layout fits any
-- phone. Screens are given in pixels (width, height) with `top`, the pixels at the top nothing may reach (Roblox's
-- top bar). Displays need their default rectangles from the plan (`panels`, in the same pixels); without them only the
-- buttons are laid out.

export type Spot = { x: number, y: number, size: number }
export type PanelSpot = { x: number, y: number, scale: number }
export type Layout = { [string]: any } -- id -> Spot (a button) or PanelSpot (a display)
export type Rect = { x: number, y: number, w: number, h: number }
export type Panels = { [string]: Rect }
export type Config = {
	order: { string },
	gap: number,
	minSize: number,
	maxSize: number,
	buttons: { [string]: { right: number, bottom: number, size: number } },
	panels: { order: { string }, minScale: number, maxScale: number }?,
}

-- A spot in pixels: a circle (buttons) or a rectangle (displays), both by their centre.
type Shape = { x: number, y: number, r: number?, hw: number?, hh: number? }

local TouchLayout = {}

-- how a spot that does not fit looks for room: rings of RING_STEP screen heights round it, up to RING_MAX, in
-- DIRECTIONS directions each
local RING_STEP = 0.025
local RING_MAX = 1.2 -- far enough to reach any free corner of a phone
local DIRECTIONS = 16

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function panelOrder(config: Config): { string }
	return if config.panels then config.panels.order else {}
end

-- Whether `id` names a display (config.panels) rather than a button.
function TouchLayout.isPanel(id: string, config: Config): boolean
	return table.find(panelOrder(config), id) ~= nil
end

-- Every element in the order it is laid out: the buttons first (they keep their places), then the displays.
function TouchLayout.ids(config: Config): { string }
	local ids = table.clone(config.order)
	for _, id in panelOrder(config) do
		table.insert(ids, id)
	end
	return ids
end

-- The default spots on a screen of width x height pixels; displays only where `panels` gives their rectangle.
function TouchLayout.defaults(width: number, height: number, config: Config, panels: Panels?): Layout
	local layout: Layout = {}
	for _, id in config.order do
		local button = config.buttons[id]
		if button then
			layout[id] = {
				x = (width - button.right * height) / width,
				y = (height - button.bottom * height) / height,
				size = button.size,
			}
		end
	end
	if panels then
		for _, id in panelOrder(config) do
			local rect = panels[id]
			if rect then
				layout[id] = { x = (rect.x + rect.w / 2) / width, y = (rect.y + rect.h / 2) / height, scale = 1 }
			end
		end
	end
	return layout
end

-- A saved layout from anything (a save, a client's message, an old save from before the displays): only known
-- elements, finite numbers, x and y within 0..1, sizes and scales within their ranges. Missing or broken ones are left
-- out (they take their default).
function TouchLayout.sanitize(raw: any, config: Config): Layout
	local clean: Layout = {}
	if type(raw) ~= "table" then
		return clean
	end
	for _, id in config.order do
		local spot = raw[id]
		if type(spot) == "table" and finite(spot.x) and finite(spot.y) and finite(spot.size) then
			clean[id] = {
				x = math.clamp(spot.x, 0, 1),
				y = math.clamp(spot.y, 0, 1),
				size = math.clamp(spot.size, config.minSize, config.maxSize),
			}
		end
	end
	local panels = config.panels
	if panels then
		for _, id in panels.order do
			local spot = raw[id]
			if type(spot) == "table" and finite(spot.x) and finite(spot.y) and finite(spot.scale) then
				clean[id] = {
					x = math.clamp(spot.x, 0, 1),
					y = math.clamp(spot.y, 0, 1),
					scale = math.clamp(spot.scale, panels.minScale, panels.maxScale),
				}
			end
		end
	end
	return clean
end

-- A display's rectangle in pixels (top left corner, size) at `spot`, from its default rectangle.
function TouchLayout.panelRect(spot: PanelSpot, default: Rect, width: number, height: number): Rect
	local w, h = default.w * spot.scale, default.h * spot.scale
	return { x = spot.x * width - w / 2, y = spot.y * height - h / 2, w = w, h = h }
end

local function shape(id: string, spot: any, width: number, height: number, config: Config, panels: Panels?): Shape?
	if TouchLayout.isPanel(id, config) then
		local default = panels and panels[id]
		if not default then
			return nil
		end
		return {
			x = spot.x * width,
			y = spot.y * height,
			hw = default.w * spot.scale / 2,
			hh = default.h * spot.scale / 2,
		}
	end
	return { x = spot.x * width, y = spot.y * height, r = spot.size * height / 2 }
end

-- The spot moved just as far as the whole element stays on the screen and below `top`. A display may go as high as
-- the HUD's plan puts it by default (the balance gauge can sit up in the top bar's free part).
function TouchLayout.inside(
	spot: any,
	width: number,
	height: number,
	top: number,
	id: string?,
	config: Config?,
	panels: Panels?
): any
	local halfW, halfH
	if id and config and TouchLayout.isPanel(id, config) then
		local default = panels and panels[id]
		if not default then
			return spot
		end
		halfW, halfH = default.w * spot.scale / 2, default.h * spot.scale / 2
		top = math.min(top, default.y)
	else
		halfW = spot.size * height / 2
		halfH = halfW
	end
	local x = math.clamp(spot.x * width, halfW, math.max(halfW, width - halfW))
	local y = math.clamp(spot.y * height, top + halfH, math.max(top + halfH, height - halfH))
	local moved = table.clone(spot)
	moved.x, moved.y = x / width, y / height
	return moved
end

local function shapesOverlap(a: Shape, b: Shape, gap: number): boolean
	if a.r and b.r then
		local reach = a.r + b.r + gap
		return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 < reach * reach
	end
	if a.hw and b.hw then
		-- two displays: nothing to tap between them, so they may touch (the plan stacks the ice balls right on the
		-- dash bar); only a real overlap (more than half a pixel) counts
		return math.abs(a.x - b.x) < a.hw + b.hw - 0.5 and math.abs(a.y - b.y) < (a.hh :: number) + b.hh - 0.5
	end
	-- a circle and a rectangle: the nearest point of the rectangle to the circle's centre
	local circle, box = if a.r then a else b, if a.r then b else a
	local nx = math.clamp(circle.x, box.x - (box.hw :: number), box.x + (box.hw :: number))
	local ny = math.clamp(circle.y, box.y - (box.hh :: number), box.y + (box.hh :: number))
	local reach = (circle.r :: number) + gap
	return (circle.x - nx) ^ 2 + (circle.y - ny) ^ 2 < reach * reach
end

-- Whether two elements touch, with the config's gap between them. Without ids both are buttons.
function TouchLayout.overlaps(
	a: any,
	b: any,
	width: number,
	height: number,
	config: Config,
	idA: string?,
	idB: string?,
	panels: Panels?
): boolean
	local shapeA = shape(idA or "", a, width, height, config, panels)
	local shapeB = shape(idB or "", b, width, height, config, panels)
	if not shapeA or not shapeB then
		return false
	end
	return shapesOverlap(shapeA, shapeB, config.gap * height)
end

-- Whether `spot` for element `id` stays clear of every other element of `layout` and of the `blocked` rectangles
-- (pixels: the HUD's fixed buttons and the move stick's zone, which a moved element must not cover).
function TouchLayout.free(
	layout: Layout,
	id: string,
	spot: any,
	width: number,
	height: number,
	config: Config,
	panels: Panels?,
	blocked: { Rect }?
): boolean
	for other, otherSpot in layout do
		if other ~= id and TouchLayout.overlaps(spot, otherSpot, width, height, config, id, other, panels) then
			return false
		end
	end
	if blocked then
		local own = shape(id, spot, width, height, config, panels)
		if own then
			for _, rect in blocked do
				local box = { x = rect.x + rect.w / 2, y = rect.y + rect.h / 2, hw = rect.w / 2, hh = rect.h / 2 }
				if shapesOverlap(own, box, 0) then
					return false
				end
			end
		end
	end
	return true
end

-- The free spot nearest to `spot` (itself if it is free): rings round it, closest first. nil when there is none.
function TouchLayout.nearestFree(
	placed: Layout,
	id: string,
	spot: any,
	width: number,
	height: number,
	top: number,
	config: Config,
	panels: Panels?,
	blocked: { Rect }?
): any?
	local start = TouchLayout.inside(spot, width, height, top, id, config, panels)
	if TouchLayout.free(placed, id, start, width, height, config, panels, blocked) then
		return start
	end
	local ring = RING_STEP
	while ring <= RING_MAX + 1e-9 do
		local best, bestDistance = nil, math.huge
		for step = 0, DIRECTIONS - 1 do
			local angle = step / DIRECTIONS * 2 * math.pi
			local moved = table.clone(start)
			moved.x = start.x + math.cos(angle) * ring * height / width
			moved.y = start.y + math.sin(angle) * ring
			local candidate = TouchLayout.inside(moved, width, height, top, id, config, panels)
			if TouchLayout.free(placed, id, candidate, width, height, config, panels, blocked) then
				local distance = ((candidate.x - start.x) * width) ^ 2 + ((candidate.y - start.y) * height) ^ 2
				if distance < bestDistance then
					best, bestDistance = candidate, distance
				end
			end
		end
		if best then
			return best
		end
		ring += RING_STEP
	end
	return nil
end

-- The spots to show: each element where the player put it (saved), else its default. One that does not fit on this
-- screen (another phone, a tablet, the other orientation: it would leave the screen or touch an element placed before
-- it) moves to the nearest free spot instead of being thrown away; buttons go first, so they keep their places. Its
-- size stays. A saved element also keeps clear of `blocked` (the HUD's fixed buttons, the move stick's zone). Only
-- when nothing near is free does it go to its default (or the free spot nearest to that); defaults are planned clear
-- of the HUD already and are only checked against the elements placed before them.
function TouchLayout.resolve(
	saved: Layout?,
	width: number,
	height: number,
	top: number,
	config: Config,
	panels: Panels?,
	blocked: { Rect }?
): Layout
	local defaults = TouchLayout.defaults(width, height, config, panels)
	local placed: Layout = {}
	for _, id in TouchLayout.ids(config) do
		local default = defaults[id]
		if default then
			local own = saved and saved[id]
			local spot = own and TouchLayout.nearestFree(placed, id, own, width, height, top, config, panels, blocked)
			if not spot and own then
				-- no room near where it was put: its own size near its default place
				local sized = table.clone(default)
				sized.size, sized.scale = own.size, own.scale
				spot = TouchLayout.nearestFree(placed, id, sized, width, height, top, config, panels, blocked)
			end
			if not spot then
				spot = TouchLayout.nearestFree(placed, id, default, width, height, top, config, panels)
					or TouchLayout.inside(default, width, height, top, id, config, panels)
			end
			placed[id] = spot
		end
	end
	return placed
end

-- What Save stores: only the elements the player moved or sized (`moved`), so everything else keeps following the
-- defaults (and the balance gauge its two places).
function TouchLayout.toSave(layout: Layout, moved: { [string]: boolean }): Layout
	local stored: Layout = {}
	for id, spot in layout do
		if moved[id] then
			stored[id] = table.clone(spot)
		end
	end
	return stored
end

return TouchLayout
