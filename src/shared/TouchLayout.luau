--!strict
-- Where the touch action buttons sit (client TouchControls and its Edit Controls mode; the saved layout in the
-- settings, SettingsRules). Pure: the config (Config/TouchControls) is passed in.
--
-- A spot is a button's centre as a share of the screen's width (x) and height (y) and its diameter in screen heights
-- (size), so a saved layout fits any phone. Screens are given in pixels (width, height) with `top`, the pixels at the
-- top no button may reach (Roblox's top bar).

export type Spot = { x: number, y: number, size: number }
export type Layout = { [string]: Spot }
export type Config = {
	order: { string },
	gap: number,
	minSize: number,
	maxSize: number,
	buttons: { [string]: { right: number, bottom: number, size: number } },
}

local TouchLayout = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- The default spots on a screen of width x height pixels.
function TouchLayout.defaults(width: number, height: number, config: Config): Layout
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
	return layout
end

-- A saved layout from anything (a save, a client's message): only known buttons, finite numbers, x and y within 0..1,
-- sizes within minSize..maxSize. Missing or broken buttons are left out (they take their default).
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
	return clean
end

-- The spot moved just as far as the whole button stays on the screen and below `top`.
function TouchLayout.inside(spot: Spot, width: number, height: number, top: number): Spot
	local radius = spot.size * height / 2
	local x = math.clamp(spot.x * width, radius, math.max(radius, width - radius))
	local y = math.clamp(spot.y * height, top + radius, math.max(top + radius, height - radius))
	return { x = x / width, y = y / height, size = spot.size }
end

-- Whether two buttons touch, with the config's gap between them.
function TouchLayout.overlaps(a: Spot, b: Spot, width: number, height: number, config: Config): boolean
	local dx = (a.x - b.x) * width
	local dy = (a.y - b.y) * height
	local reach = (a.size + b.size) / 2 * height + config.gap * height
	return dx * dx + dy * dy < reach * reach
end

-- Whether `spot` for button `id` stays clear of every other button of `layout`.
function TouchLayout.free(
	layout: Layout,
	id: string,
	spot: Spot,
	width: number,
	height: number,
	config: Config
): boolean
	for other, otherSpot in layout do
		if other ~= id and TouchLayout.overlaps(spot, otherSpot, width, height, config) then
			return false
		end
	end
	return true
end

-- The spots to show: the defaults, with each saved spot in their place where it fits (inside the screen, clear of the
-- buttons placed before it in config.order); a saved spot that does not fit gives way to its default.
function TouchLayout.resolve(saved: Layout?, width: number, height: number, top: number, config: Config): Layout
	local defaults = TouchLayout.defaults(width, height, config)
	local placed: Layout = {}
	for _, id in config.order do
		local default = defaults[id]
		if default then
			local spot = TouchLayout.inside(default, width, height, top)
			local own = saved and saved[id]
			if own then
				local candidate = TouchLayout.inside(own, width, height, top)
				if TouchLayout.free(placed, id, candidate, width, height, config) then
					spot = candidate
				end
			end
			placed[id] = spot
		end
	end
	return placed
end

return TouchLayout
