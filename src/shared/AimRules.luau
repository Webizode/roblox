--!strict
-- The crosshair's numbers (Config/Combat crosshair and aimAssist): how big the circle is, and the aim help in the
-- combat camera (which rival it works on, how much it slows the turning down and how much it draws the camera to
-- them). Purely the display and the camera: throws never scatter and the server checks hits as always. Pure: the
-- config is passed in; AimHud and CombatCamera use it. The inner circle's pulse is Combat.pulse.

export type Spread = {
	moving: boolean,
	sprinting: boolean,
	sinceDash: number, -- seconds since the last dash (math.huge: none)
	sinceThrow: number, -- seconds since the last throw
	strength: number?, -- the held throw's strength (Combat.strength), nil while nothing is held
}

local AimRules = {}

local function fading(since: number, time: number): number
	if since ~= since or since < 0 then
		return 0
	end
	return math.max(0, 1 - since / time)
end

-- The radius (pixels, before the crosshair size setting) the circle heads for: bigger while moving, sprinting, right
-- after a dash and right after a throw; held throws pull it in, the more the stronger.
function AimRules.radius(spread: Spread, config: any): number
	local c = config.crosshair
	local radius = c.radius
		+ (if spread.moving then c.walk else 0)
		+ (if spread.sprinting then c.sprint else 0)
		+ c.dash * fading(spread.sinceDash, c.dashTime)
		+ c.throw * fading(spread.sinceThrow, c.throwTime)
	if spread.strength then
		radius *= 1 - c.holdShrink * math.clamp(spread.strength, 0, 1)
	end
	return radius
end

-- One step of the circle easing from `current` towards `target` over `dt` seconds.
function AimRules.ease(current: number, target: number, dt: number, config: any): number
	return target + (current - target) * math.exp(-config.crosshair.response * math.max(dt, 0))
end

export type Candidate = {
	angle: number, -- degrees between the crosshair's direction and the rival
	distance: number, -- studs
	visible: boolean, -- nothing solid between the camera and them
	shielded: boolean, -- in their cart's safe zone
}

-- The aim help's strength for the input in use ("keyboard" is the mouse, "gamepad", "touch"); an unknown one gets
-- the mouse's, the lightest.
function AimRules.device(kind: string, config: any): { friction: number, pull: number }
	local devices = config.aimAssist.devices
	return devices[kind] or devices.keyboard
end

-- The rival the aim help works on: the one closest to the crosshair among those within maxAngle and maxRange, in
-- plain sight and not shielded; nil when there is none (never one behind or beside the crosshair).
function AimRules.pick(candidates: { Candidate }, config: any): number?
	local a = config.aimAssist
	local best, bestAngle = nil, math.huge
	for index, c in candidates do
		if
			c.visible
			and not c.shielded
			and c.distance <= a.maxRange
			and c.angle < a.maxAngle
			and c.angle < bestAngle
		then
			best, bestAngle = index, c.angle
		end
	end
	return best
end

-- How strongly the help works on a rival `angle` degrees off the crosshair: 1 right on it, fading to 0 at maxAngle.
function AimRules.closeness(angle: number, config: any): number
	if angle ~= angle then
		return 0
	end
	return math.clamp(1 - angle / config.aimAssist.maxAngle, 0, 1)
end

-- The share of the player's own turning that is left near a rival (friction): 1 without one, less the closer it is.
function AimRules.friction(closeness: number, device: { friction: number, pull: number }): number
	return 1 - device.friction * math.clamp(closeness, 0, 1)
end

-- The share of the way to the rival the camera closes this frame (pull), never all of it: no snapping.
function AimRules.pull(closeness: number, dt: number, device: { friction: number, pull: number }): number
	return 1 - math.exp(-device.pull * math.clamp(closeness, 0, 1) * math.max(dt, 0))
end

-- Whether a topple at `now` counts as the doing of a hit at `hitAt` (Config/Combat feedback.creditSeconds).
function AimRules.credited(hitAt: number?, now: number, config: any): boolean
	return hitAt ~= nil and now >= hitAt and now - hitAt <= config.feedback.creditSeconds
end

return AimRules
