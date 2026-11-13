--!strict
-- The plot guide's rules (client/Controllers/PlotGuide, Config/Ui.guide): when the light over the own serve point
-- shows, when a player carrying scoops counts as arrived there, and where the arrow at the screen's edge goes for a
-- serve point outside the picture. Pure: numbers in, numbers out.

local GuideRules = {}

export type Config = { showShare: number, arriveRadius: number }

-- The light shows while the cone is at least `showShare` full and the player is not at the plot yet.
function GuideRules.showLight(count: number, capacity: number, distance: number, config: Config): boolean
	if count <= 0 or capacity <= 0 then
		return false
	end
	return count / capacity >= config.showShare - 1e-9 and distance > config.arriveRadius
end

-- Whether the player is at the plot: within `arriveRadius` of the serve point.
function GuideRules.near(distance: number, config: Config): boolean
	return distance <= config.arriveRadius
end

-- The moment to light up the serve point: carrying scoops, and near now but not the frame before.
function GuideRules.arrived(count: number, wasNear: boolean, distance: number, config: Config): boolean
	return count > 0 and not wasNear and GuideRules.near(distance, config)
end

export type PinConfig = {
	pinFade: number,
	pinHide: number,
	pinTransparency: number,
	pinStrongTransparency: number,
	pinCombatTransparency: number,
	pinCombatScale: number,
	pinStrongScale: number,
}

-- How the pin over the own plot shows: its transparency (0 solid .. 1 gone) and its scale. Faint all the time,
-- solid and a little bigger once the cone is `strong` (showLight's share), fainter and smaller in combat mode (where it
-- must not distract); it fades out from `pinFade` studs to `pinHide` studs and is gone on the plot itself.
function GuideRules.pinLook(distance: number, strong: boolean, combat: boolean, config: PinConfig): (number, number)
	local base = config.pinTransparency
	local scale = 1
	if strong then
		base, scale = config.pinStrongTransparency, config.pinStrongScale
	end
	if combat then
		base = math.max(base, config.pinCombatTransparency)
		scale *= config.pinCombatScale
	end
	local span = math.max(config.pinFade - config.pinHide, 1e-6)
	local seen = math.clamp((distance - config.pinHide) / span, 0, 1)
	return 1 - (1 - base) * seen, scale
end

-- The arrow for a target whose viewport point is (x, y), `inFront` of the camera or behind it, on a screen
-- `width` x `height`: nil while the target is in the picture (at least `margin` from every edge); else the arrow's
-- middle on the rectangle `margin` inside the screen, in the direction of the target as seen from the screen's
-- middle, and its rotation in degrees (0 points right, 90 down). Behind the camera the projected point is mirrored,
-- so the direction is turned round; straight behind it points down.
function GuideRules.edgeArrow(
	x: number,
	y: number,
	inFront: boolean,
	width: number,
	height: number,
	margin: number
): (number?, number?, number?)
	if inFront and x >= margin and x <= width - margin and y >= margin and y <= height - margin then
		return nil, nil, nil
	end
	local centreX, centreY = width / 2, height / 2
	local dx, dy = x - centreX, y - centreY
	if not inFront then
		dx, dy = -dx, -dy
	end
	if math.abs(dx) < 1e-6 and math.abs(dy) < 1e-6 then
		dy = 1
	end
	local halfW, halfH = math.max(centreX - margin, 0), math.max(centreY - margin, 0)
	local scale = math.huge
	if math.abs(dx) > 1e-6 then
		scale = math.min(scale, halfW / math.abs(dx))
	end
	if math.abs(dy) > 1e-6 then
		scale = math.min(scale, halfH / math.abs(dy))
	end
	return centreX + dx * scale, centreY + dy * scale, math.deg(math.atan2(dy, dx))
end

return GuideRules
