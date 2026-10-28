--!strict
-- Which Big Swirl arm fires a scoop and when (Config/BigSwirl). Pure: the config is passed in, so the server's
-- launcher and the Lune tests share it.

export type Timing = {
	speed: number, -- the arm animation's play speed
	releaseLead: number, -- seconds from the start of the animation to the release
	scoopLead: number, -- seconds from the scoop showing in the cup to the release
	busyFor: number, -- seconds the arm is taken
}

local LaunchArms = {}

-- The play speed for a launcher firing every `interval` seconds: N arms at speed 1 manage one shot per
-- cycleLength / N; a faster launcher speeds the arms up (with a little slack), within the config's limits.
function LaunchArms.playSpeed(interval: number, config: any): number
	local arms = #config.releasePoints
	local needed = config.cycleLength / (arms * math.max(interval, 1e-3))
	return math.clamp(needed * config.speedSlack, config.minPlaySpeed, config.maxPlaySpeed)
end

-- An arm's pose `elapsed` seconds into its cycle at play speed `speed`: the shoulder's lift and the wrist's tip in
-- degrees from the rest pose (Config/BigSwirlCycle), straight between its frames; 0, 0 before and after the cycle.
function LaunchArms.pose(cycle: any, elapsed: number, speed: number): (number, number)
	local frame = elapsed * speed * cycle.fps
	local last = #cycle.shoulder - 1
	if frame <= 0 or frame >= last then
		return 0, 0
	end
	local i = math.floor(frame)
	local f = frame - i
	local s0, s1 = cycle.shoulder[i + 1], cycle.shoulder[i + 2]
	local w0, w1 = cycle.wrist[i + 1], cycle.wrist[i + 2]
	return s0 + (s1 - s0) * f, w0 + (w1 - w0) * f
end

function LaunchArms.timing(speed: number, config: any): Timing
	return {
		speed = speed,
		releaseLead = config.releaseAt / speed,
		scoopLead = (config.releaseAt - config.scoopedAt) / speed,
		busyFor = config.cycleLength / speed + config.busyMargin,
	}
end

-- The free arm (freeAt[n] <= now) that points closest to the flat direction (dx, dz) from the machine to the target,
-- or nil when the free ones all point more than maxAngle away (the shot waits). Arm directions are their release
-- points' flat directions.
function LaunchArms.pick(dx: number, dz: number, freeAt: { number }, now: number, config: any): number?
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-6 then
		dx, dz, length = 1, 0, 1
	end
	dx, dz = dx / length, dz / length
	local best, bestDot = nil, math.cos(config.maxAngle)
	for arm, point in config.releasePoints do
		if (freeAt[arm] or -math.huge) <= now then
			local ax, az = point[1], point[3]
			local alen = math.sqrt(ax * ax + az * az)
			local dot = (ax * dx + az * dz) / alen
			if dot >= bestDot then
				best, bestDot = arm, dot
			end
		end
	end
	return best
end

return LaunchArms
