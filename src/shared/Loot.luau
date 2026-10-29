--!strict
-- Spilled scoops (Config/Loot). Pure: TowerShape and the tunings are passed in, so the server (LootService), the
-- clients (LootRenderer) and the Lune tests share the same rules and the same paths.
--
-- A spilled scoop starts where it sat in the toppled tower, falls to the ground below that point in fallTime and
-- rolls a few studs further, slowing down. Offsets are in studs relative to the tower base, world-axis aligned.
-- A landed scoop (Loot.landed) is one from the Big Swirl that nobody caught: it lies where it came down, no fall, no
-- roll, nobody's, for landedLifetime seconds.

export type Config = {
	ownerLock: number,
	ownerSeconds: number,
	lifetime: number,
	blinkSeconds: number,
	maxFree: number,
	landedLifetime: number,
	landedBlinkSeconds: number,
	maxLanded: number,
	fallTime: number,
	rollMin: number,
	rollMax: number,
	rollSpread: number,
	rollDecay: number,
	waterSamples: number,
	maxRollStep: number,
	pickupRadius: number,
	pickupHeight: number,
	serverTolerance: number,
	serverSpeedLead: number,
	maxClaimsPerSecond: number,
	scoopRadius: number,
	ringSize: number,
	safeRadius: number,
	unshieldSeconds: number,
}

-- One spilled scoop's path, relative to the tower base: start (sx, sy, sz) in the tower, landing (lx, lz) on the
-- ground straight below it, then the roll (rx, rz) on top of that.
export type Path = {
	flavorId: string,
	sx: number,
	sy: number,
	sz: number,
	lx: number,
	lz: number,
	rx: number,
	rz: number,
}

-- What decides who may pick a scoop up. Times are server times; owner is the owner's UserId.
export type Scoop = {
	owner: number,
	landedAt: number,
	ownerFrom: number, -- the owner may pick it up from then on (Loot.ownerFrom)
	ownerUntil: number,
	expiresAt: number,
}

local Loot = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Deterministic number in [0, 1) for a seed and an index. Neighbouring indices must get unrelated numbers (a linear
-- hash gave every scoop of a spill nearly the same roll), so it scrambles with a sine. Only the server computes
-- spills (clients get the finished paths), so it need not match bit for bit across machines.
local function unit(seed: number, index: number, salt: number): number
	local x = math.sin(seed * 12.9898 + index * 78.233 + salt * 37.719) * 43758.5453
	return x - math.floor(x)
end

-- The paths of the scoops that fall off a toppled tower. `flavorIds` is the whole tower (bottom to top) before the
-- topple, `keep` how many stay on it; the ones above fall, the top one first in the list. The lean decides where
-- they go: each starts where it sat in the tower leaning (tiltX, tiltZ) and rolls on in that direction.
function Loot.spill(
	flavorIds: { string },
	keep: number,
	tiltX: number,
	tiltZ: number,
	seed: number,
	config: Config,
	towerTuning: any,
	TowerShape: any
): { Path }
	local count = #flavorIds
	local tilt = math.sqrt(tiltX * tiltX + tiltZ * tiltZ)
	local paths = {}
	for index = count, keep + 1, -1 do
		local sx, sy, sz = TowerShape.offset(index, count, tiltX, tiltZ, towerTuning)
		local heading = if tilt > 1e-3 then math.atan2(tiltZ, tiltX) else unit(seed, index, 1) * 2 * math.pi
		heading += (unit(seed, index, 2) * 2 - 1) * config.rollSpread
		local roll = config.rollMin + (config.rollMax - config.rollMin) * unit(seed, index, 3)
		table.insert(paths, {
			flavorId = flavorIds[index],
			sx = sx,
			sy = sy,
			sz = sz,
			lx = sx,
			lz = sz,
			rx = math.cos(heading) * roll,
			rz = math.sin(heading) * roll,
		})
	end
	return paths
end

-- Share of the roll done `elapsed` seconds after the topple: 0 until the scoop landed, then easing towards 1.
function Loot.rollShare(elapsed: number, config: Config): number
	if elapsed <= config.fallTime then
		return 0
	end
	return 1 - math.exp(-config.rollDecay * (elapsed - config.fallTime))
end

-- Offset from the tower base `elapsed` seconds after the topple. y is the height above the ground (0 once landed).
-- `stopShare` (Profile.stopShare) ends the roll early where a step or a wall is in the way.
function Loot.position(path: Path, elapsed: number, config: Config, stopShare: number?): (number, number, number)
	if elapsed < config.fallTime then
		local share = math.max(0, elapsed) / config.fallTime
		return path.sx + (path.lx - path.sx) * share,
			path.sy * (1 - share * share),
			path.sz + (path.lz - path.sz) * share
	end
	local roll = math.min(Loot.rollShare(elapsed, config), stopShare or 1)
	return path.lx + path.rx * roll, 0, path.lz + path.rz * roll
end

-- The points along the way where the server checks for ground: the landing point and waterSamples points along the
-- roll, each with the share of the roll done there and the time the scoop gets there.
function Loot.groundSamples(path: Path, config: Config): { { x: number, z: number, t: number, share: number } }
	local samples = { { x = path.lx, z = path.lz, t = config.fallTime, share = 0 } }
	for step = 1, config.waterSamples do
		local share = step / config.waterSamples * 0.95 -- the roll never quite ends
		local elapsed = config.fallTime - math.log(1 - share) / config.rollDecay
		table.insert(
			samples,
			{ x = path.lx + path.rx * share, z = path.lz + path.rz * share, t = elapsed, share = share }
		)
	end
	return samples
end

-- The ground along one scoop's way, from the heights the server found under groundSamples (nil: water or nothing).
--   shares/heights  the ground under the landing point and along the roll, as far as the scoop gets
--   stopShare       share of the roll where it ends: 1, or earlier at a step up higher than maxRollStep (it stops
--                   against it). Down steps are followed, the scoop drops off the edge.
--   sinkAt          seconds after the topple it reaches water, nil if it never does
export type Profile = {
	shares: { number },
	heights: { number },
	stopShare: number,
	sinkAt: number?,
}

function Loot.rollProfile(
	samples: { { x: number, z: number, t: number, share: number } },
	heights: { number? },
	config: Config
): Profile
	local profile: Profile = { shares = {}, heights = {}, stopShare = 1, sinkAt = nil }
	local previous: number? = nil
	for index, sample in samples do
		local height = heights[index]
		if height == nil then
			profile.sinkAt = sample.t
			profile.stopShare = sample.share
			break
		end
		if previous and height - previous > config.maxRollStep then
			profile.stopShare = samples[index - 1].share
			break
		end
		table.insert(profile.shares, sample.share)
		table.insert(profile.heights, height)
		previous = height
	end
	return profile
end

-- The ground height under the scoop at `share` of its roll, nil when the profile has no ground at all (it landed in
-- the water). Between two samples it slopes, so a scoop rolling off an edge comes down over a stud or so.
function Loot.groundHeight(profile: Profile, share: number): number?
	local shares, heights = profile.shares, profile.heights
	if #heights == 0 then
		return nil
	end
	if share <= shares[1] then
		return heights[1]
	end
	for index = 2, #heights do
		if share <= shares[index] then
			local blend = (share - shares[index - 1]) / (shares[index] - shares[index - 1])
			return heights[index - 1] + (heights[index] - heights[index - 1]) * blend
		end
	end
	return heights[#heights]
end

-- Until when only the owner may pick up a scoop that landed at `landedAt`: ownerSeconds from the moment the owner can
-- act again, so a knockdown (ownerDownUntil) does not eat the head start.
function Loot.ownerUntil(landedAt: number, ownerDownUntil: number, config: Config): number
	return math.max(landedAt, ownerDownUntil) + config.ownerSeconds
end

-- From when the owner may pick up their own scoop that landed at `landedAt`: ownerLock later, so a toppled tower
-- is not simply gathered up again on the spot.
function Loot.ownerFrom(landedAt: number, config: Config): number
	return landedAt + config.ownerLock
end

-- Whether `userId` may pick the scoop up at `now`, and why not.
function Loot.canCollect(scoop: Scoop, userId: number, now: number): (boolean, string)
	if now < scoop.landedAt then
		return false, "still falling"
	elseif now >= scoop.expiresAt then
		return false, "gone"
	elseif userId == scoop.owner and now < scoop.ownerFrom then
		return false, "not yet for the owner"
	elseif userId ~= scoop.owner and now < scoop.ownerUntil then
		return false, "the owner's turn"
	end
	return true, "ok"
end

-- From when `userId` may pick the scoop up (as long as it is there): what the client lights up for.
function Loot.collectableFrom(scoop: Scoop, userId: number): number
	local from = if userId == scoop.owner then scoop.ownerFrom else scoop.ownerUntil
	return math.max(scoop.landedAt, from)
end

-- Whether a character at (dx, dy, dz) from the scoop (dy: root height above the scoop's ground point) reaches it.
-- `speed` is the root's horizontal speed, already capped by the caller; the client passes 0 and no tolerance.
function Loot.inReach(dx: any, dy: any, dz: any, speed: number, tolerant: boolean, config: Config): boolean
	if not isFinite(dx) or not isFinite(dy) or not isFinite(dz) then
		return false
	end
	local radius = config.pickupRadius
	if tolerant then
		radius += config.serverTolerance + math.max(0, speed) * config.serverSpeedLead
	end
	return dx * dx + dz * dz <= radius * radius and math.abs(dy) <= config.pickupHeight
end

export type Landed = {
	path: Path,
	profile: Profile,
	rule: Scoop,
	t0: number, -- the time its path starts: landed right away (Loot.position puts it on the ground)
	endAt: number,
}

-- A scoop from the Big Swirl that came down at `landedAt` on ground of height `groundY` without anybody catching it:
-- it lies there, its path relative to the landing point all zero, anybody may pick it up (owner 0, no head start), and
-- it is gone landedLifetime seconds after landing.
function Loot.landed(flavorId: string, landedAt: number, groundY: number, config: Config): Landed
	local expiresAt = landedAt + config.landedLifetime
	return {
		path = { flavorId = flavorId, sx = 0, sy = 0, sz = 0, lx = 0, lz = 0, rx = 0, rz = 0 },
		profile = { shares = { 0 }, heights = { groundY }, stopShare = 1, sinkAt = nil },
		rule = { owner = 0, landedAt = landedAt, ownerFrom = landedAt, ownerUntil = landedAt, expiresAt = expiresAt },
		t0 = landedAt - config.fallTime,
		endAt = expiresAt,
	}
end

-- Whether a free scoop that is gone at `endAt` blinks at `now`: for the last blinkSeconds (landedBlinkSeconds for a
-- landed one). One that sinks in the water does not blink, it just goes under.
function Loot.blinks(endAt: number, now: number, landed: boolean, sinks: boolean, config: Config): boolean
	if sinks or now >= endAt then
		return false
	end
	return now > endAt - (if landed then config.landedBlinkSeconds else config.blinkSeconds)
end

-- How many landed scoops have to go (the oldest first) so that one more fits under maxLanded.
function Loot.landedRoom(current: number, config: Config): number
	return math.max(0, current + 1 - config.maxLanded)
end

-- How many of the free scoops already lying around have to go (the oldest first) so that `incoming` new ones fit,
-- and how many of the new ones are kept at all (never more than maxFree).
function Loot.makeRoom(current: number, incoming: number, config: Config): (number, number)
	local kept = math.min(incoming, config.maxFree)
	return math.max(0, current + kept - config.maxFree), kept
end

-- Whether a player `distance` studs from their own cart is protected from ice-ball harm at `now`. unshieldedUntil is
-- set by a throw from inside the zone.
function Loot.isShielded(distance: number?, now: number, unshieldedUntil: number, config: Config): boolean
	return distance ~= nil and distance <= config.safeRadius and now >= unshieldedUntil
end

-- A throw from `distance` studs of the own cart: the time until which the thrower is unprotected, or the old value
-- when the throw came from outside the zone.
function Loot.afterThrow(distance: number?, now: number, unshieldedUntil: number, config: Config): number
	if distance ~= nil and distance <= config.safeRadius then
		return math.max(unshieldedUntil, now + config.unshieldSeconds)
	end
	return unshieldedUntil
end

return Loot
