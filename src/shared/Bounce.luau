--!strict
-- The gummy bounce pads (Config/Bounce): how hard one throws a player, when a player may bounce again, the kick a landing tower gets, the pad's squash, and the server's rough check of a bounce the
-- client reports. Pure: no Roblox globals, no requires; configs come in as arguments.

local Bounce = {}

export type Kind = {
	apex: number,
	forward: number,
	kickBase: number,
	kickPerScoop: number,
	kickMax: number,
	tallFrom: number,
	tallFade: number,
	tallFloor: number,
	squash: number,
}

export type Config = {
	kinds: { { prefix: string, kind: string } },
	pad: Kind,
	bouncer: Kind,
	cooldown: number,
	squashTime: number,
	springTime: number,
	spread: number,
	server: { cooldown: number, reach: number, below: number, above: number, arenaSlack: number },
}

-- What a model in the cover folder is by its name ("pad", "bouncer"), or nil when it is no bounce pad.
function Bounce.kindOf(name: string, config: Config): string?
	for _, entry in config.kinds do
		if string.sub(name, 1, #entry.prefix) == entry.prefix then
			-- GummyPadPressed and the like are the pads' other state, never placed: they count as the same kind
			return entry.kind
		end
	end
	return nil
end

-- The velocity a pad gives a player whose feet are at `feetY` on it (the pad's floor at `floorY`): straight up so the
-- feet reach kind.apex x heightScale above the floor (heightScale from Economy.jumpScale, 1 without a tower), plus
-- kind.forward along (lookX, lookZ) on the ground. Always at least a small hop, also from high up on the pad.
function Bounce.launch(
	kind: Kind,
	gravity: number,
	floorY: number,
	feetY: number,
	heightScale: number,
	lookX: number,
	lookZ: number
): (number, number, number)
	local rise = math.max(1, kind.apex * heightScale - (feetY - floorY))
	local up = math.sqrt(2 * gravity * rise)
	local length = math.sqrt(lookX * lookX + lookZ * lookZ)
	if length < 1e-6 then
		return 0, up, 0
	end
	return lookX / length * kind.forward, up, lookZ / length * kind.forward
end

-- How high the feet get above the floor with that launch speed (for checks).
function Bounce.apexOf(up: number, gravity: number, floorY: number, feetY: number): number
	return feetY - floorY + up * up / (2 * gravity)
end

-- Whether a player who last bounced at `lastAt` (nil: never) may bounce again at `now`.
function Bounce.ready(lastAt: number?, now: number, cooldown: number): boolean
	return lastAt == nil or now - lastAt >= cooldown - 1e-9
end

-- The kick (rad/s) a tower of `count` scoops gets when its carrier lands after that kind of jump.
function Bounce.towerKick(kind: Kind, count: number): number
	if count <= 0 then
		return 0
	end
	local kick = math.min(kind.kickMax, kind.kickBase + kind.kickPerScoop * count)
	local tall = math.clamp(1 - (count - kind.tallFrom) * kind.tallFade, kind.tallFloor, 1)
	return kick * tall
end

-- The pad's squash `t` seconds after a bounce: its height share (depth at the deepest point, 1 at rest) and its
-- width share. Down in squashTime, then back up in springTime with one overshoot that settles.
function Bounce.squashAt(t: number, depth: number, config: Config): (number, number)
	local down = config.squashTime
	local back = config.springTime
	local press = 0
	if t <= 0 or t >= down + back then
		press = 0
	elseif t < down then
		press = t / down
	else
		local u = (t - down) / back
		-- 1 at u = 0, through 0 at u = 0.4 to a small overshoot (-0.25) and back to 0 at the end
		press = math.cos(u * math.pi * 1.25) * (1 - u)
	end
	local height = 1 - (1 - depth) * press
	local width = 1 + config.spread * press
	return height, width
end

-- A mesh's size at a squash (height and width shares from squashAt), always from its size at rest: never from its
-- size of the frame before, so squashes that overlap (several players, several touches) cannot add up.
function Bounce.poseSize(x: number, y: number, z: number, height: number, width: number): (number, number, number)
	return x * width, y * height, z * width
end

export type Claim = {
	now: number,
	lastAt: number?, -- the server's last accepted bounce of that player
	alive: boolean,
	inArena: boolean,
	distance: number, -- the root's distance from the pad's middle on the ground plane
	radius: number, -- the pad's radius
	height: number, -- the root's height over the floor the pad stands on
	tall: number, -- the pad's own height (its top over that floor)
}

-- The server's rough check of a reported bounce: alive, in the arena, at the pad (generous for lag), not too soon.
-- Returns whether it holds and, if not, why ("dead", "arena", "far", "height", "cooldown").
function Bounce.check(claim: Claim, config: Config): (boolean, string?)
	local server = config.server
	if not claim.alive then
		return false, "dead"
	end
	if not claim.inArena then
		return false, "arena"
	end
	if claim.distance > claim.radius + server.reach then
		return false, "far"
	end
	if claim.height < -server.below or claim.height > claim.tall + server.above then
		return false, "height"
	end
	if not Bounce.ready(claim.lastAt, claim.now, server.cooldown) then
		return false, "cooldown"
	end
	return true, nil
end

return Bounce
