--!strict
-- The teleport buttons (Navigation, ArenaService): which targets exist, when a request is granted, which of several
-- shop targets and which spot round it. Pure: the server asks these, the Lune tests pin them down.
--
-- A request is granted for a living character that is not knocked down and has not taken a harmful hit for
-- Config/Map.teleportHitLock seconds; in the arena only with no scoops on the back (carrying the tower out of the arena
-- is the game, a button must not skip it). Requests closer together than teleportMinInterval are floods and dropped.
-- The same rules for every target.

export type Config = {
	teleportMinInterval: number,
	teleportHitLock: number,
	teleportTargets: { [string]: string },
}

-- why a request is turned down; nil means granted
export type Refusal = "unknown" | "flood" | "dead" | "down" | "hit" | "tower"

export type Request = {
	where: any, -- what the client sent
	alive: boolean,
	inArena: boolean,
	carrying: boolean, -- scoops on the back
	down: boolean, -- knocked down right now
	sinceHit: number, -- seconds since the last harmful hit (math.huge without one)
	sinceRequest: number, -- seconds since the player's last request (math.huge without one)
}

local TeleportRules = {}

-- "plot" and "arena" are built in; the shops come from Config/Map.teleportTargets
function TeleportRules.isTarget(where: any, config: Config): boolean
	return where == "plot" or where == "arena" or (type(where) == "string" and config.teleportTargets[where] ~= nil)
end

-- Why the request is turned down, or nil when it is granted. Flood first: a flood is dropped without a word.
function TeleportRules.refusal(request: Request, config: Config): Refusal?
	if not TeleportRules.isTarget(request.where, config) then
		return "unknown"
	elseif request.sinceRequest < config.teleportMinInterval then
		return "flood"
	elseif not request.alive then
		return "dead"
	elseif request.down then
		return "down"
	elseif request.sinceHit < config.teleportHitLock then
		return "hit"
	elseif request.inArena and request.carrying then
		return "tower"
	end
	return nil
end

-- The index of the point nearest to (x, z), nil for an empty list.
function TeleportRules.nearest(points: { { number } }, x: number, z: number): number?
	local best, bestDistance = nil, math.huge
	for index, point in points do
		local dx, dz = point[1] - x, point[2] - z
		local distance = dx * dx + dz * dz
		if distance < bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

-- Which spot to land on: the first with nobody closer than `gap`; when all are taken, the one whose nearest player is
-- farthest away. `spots` and `others` are world { x, z }.
function TeleportRules.spot(spots: { { number } }, others: { { number } }, gap: number): number
	local best, bestRoom = 1, -1
	for index, spot in spots do
		local room = math.huge
		for _, other in others do
			local dx, dz = other[1] - spot[1], other[2] - spot[2]
			room = math.min(room, math.sqrt(dx * dx + dz * dz))
		end
		if room >= gap then
			return index
		end
		if room > bestRoom then
			best, bestRoom = index, room
		end
	end
	return best
end

return TeleportRules
