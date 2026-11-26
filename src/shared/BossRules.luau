--!strict
-- The numbers of the arena bosses (Config/Bosses): when they come, how much health, damage and reward, who an attack
-- hits. Pure: no Roblox globals, no requires; the config comes in as an argument. BossService owns the state.

local BossRules = {}

local HOUR = 3600

-- The first full hour at or after `t` (server clock in seconds).
function BossRules.hourAtOrAfter(t: number): number
	return math.ceil(t / HOUR) * HOUR
end

-- The full hour whose block keeps a normal boss away at `t` (schedule.blockBefore before it, blockAfter after it),
-- or nil when a normal boss may start then.
function BossRules.blockingHour(t: number, schedule: any): number?
	local after = BossRules.hourAtOrAfter(t)
	if after - t < schedule.blockBefore then
		return after
	end
	local before = math.floor(t / HOUR) * HOUR
	if t - before < schedule.blockAfter then
		return before
	end
	return nil
end

-- When the next normal boss comes: `roll` (0..1) of the way between normalMin and normalMax after `from` (firstMin
-- and firstMax after a server start), pushed past a big boss's block when it would fall into one.
function BossRules.nextNormalAt(from: number, roll: number, schedule: any, first: boolean?): number
	local low = if first then schedule.firstMin else schedule.normalMin
	local high = if first then schedule.firstMax else schedule.normalMax
	local t = from + low + math.clamp(roll, 0, 1) * (high - low)
	local hour = BossRules.blockingHour(t, schedule)
	if hour then
		t = hour + schedule.blockAfter
	end
	return t
end

-- A boss's full health for `players` in the arena (at least one): base x (1 + perPlayer x (players - 1)), times the
-- big boss's factor.
function BossRules.maxHealth(base: number, players: number, big: boolean, config: any): number
	local count = math.max(1, math.floor(players))
	local health = base * (1 + config.health.perPlayer * (count - 1))
	if big then
		health *= config.big.health
	end
	return math.floor(health + 0.5)
end

-- More players came in: the health grows by as much as the full health does (never shrinks). Returns the new full
-- health and the new current health.
function BossRules.grow(current: number, full: number, newFull: number): (number, number)
	if newFull <= full then
		return full, current
	end
	return newFull, current + (newFull - full)
end

-- The damage of one ice ball: damagePerHit x hit power (0..1) x the thrower's Boss Power (1 without the upgrade).
-- Boss Power is only ever used here, never against players.
function BossRules.damage(power: number, bossPower: number, config: any): number
	if power ~= power then
		return 0
	end
	return config.damagePerHit * math.clamp(power, 0, 1) * math.max(1, bossPower)
end

-- The coins of everybody who did damage (keys are whatever the caller uses, e.g. UserIds): coinsBase plus their share
-- of coinsPot, times the big boss's factor. Nobody without damage gets anything.
function BossRules.rewards(damages: { [any]: number }, big: boolean, config: any): { [any]: number }
	local total = 0
	for _, amount in damages do
		if amount > 0 then
			total += amount
		end
	end
	local result = {}
	if total <= 0 then
		return result
	end
	local factor = if big then config.big.coins else 1
	local reward = config.reward
	for key, amount in damages do
		if amount > 0 then
			result[key] = math.floor((reward.coinsBase + reward.coinsPot * amount / total) * factor + 0.5)
		end
	end
	return result
end

local RARITY_ORDER = { "rare", "epic", "legendary" }

-- The rarity of a reward scoop for `roll` (0..1) by the weights in `odds` (rare, epic, legendary).
function BossRules.rollRarity(roll: number, odds: { [string]: number }): string
	local total = 0
	for _, rarity in RARITY_ORDER do
		total += math.max(0, odds[rarity] or 0)
	end
	if total <= 0 then
		return "rare"
	end
	local pick = math.clamp(roll, 0, 0.999999) * total
	for _, rarity in RARITY_ORDER do
		local weight = math.max(0, odds[rarity] or 0)
		if pick < weight then
			return rarity
		end
		pick -= weight
	end
	return RARITY_ORDER[#RARITY_ORDER]
end

-- The flavors a reward of `rarity` can be (not the placeholders), by id, sorted so a roll picks the same everywhere.
function BossRules.flavorsOf(
	rarity: string,
	flavors: { { id: string, rarity: string, placeholder: boolean? } }
): { string }
	local ids = {}
	for _, flavor in flavors do
		if flavor.rarity == rarity and not flavor.placeholder then
			table.insert(ids, flavor.id)
		end
	end
	table.sort(ids)
	return ids
end

-- Whether a point lies in a disc, its radius made `tolerance` smaller (the server sees players late; in their favour).
function BossRules.inDisc(px: number, pz: number, cx: number, cz: number, radius: number, tolerance: number): boolean
	local dx, dz = px - cx, pz - cz
	local reach = math.max(0, radius - tolerance)
	return dx * dx + dz * dz <= reach * reach
end

-- Whether a ground wave of radius `ring` (and `width`) out from (cx, cz) touches a point.
function BossRules.waveTouches(
	px: number,
	pz: number,
	cx: number,
	cz: number,
	ring: number,
	width: number,
	tolerance: number
): boolean
	local distance = math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
	return math.abs(distance - ring) <= math.max(0, width / 2 - tolerance / 2)
end

-- Whether a hit at `impactAt` is dodged: a dash granted at most dashDodge seconds before it (or after it, within the
-- same window, since the server hears of the dash late), or for a wave the feet above jumpClear.
function BossRules.dodged(lastDashAt: number, impactAt: number, feetAbove: number?, config: any): boolean
	if math.abs(impactAt - lastDashAt) <= config.hit.dashDodge then
		return true
	end
	return feetAbove ~= nil and feetAbove >= config.hit.jumpClear
end

-- How many scoops a boss hit knocks off a tower of `count`: dropMin to dropMax by `roll`, never more than there are.
function BossRules.dropCount(count: number, roll: number, config: any): number
	local hit = config.hit
	local n = hit.dropMin + math.floor(math.clamp(roll, 0, 0.999999) * (hit.dropMax - hit.dropMin + 1))
	return math.clamp(n, 0, math.max(0, count))
end

-- A point moved into the roaming ring (roam.minRadius to maxRadius round the centre at 0, 0).
function BossRules.intoRing(x: number, z: number, roam: any): (number, number)
	local distance = math.sqrt(x * x + z * z)
	if distance < 1e-6 then
		return roam.minRadius, 0
	end
	local clamped = math.clamp(distance, roam.minRadius, roam.maxRadius)
	return x / distance * clamped, z / distance * clamped
end

-- One step from (x, z) towards (tx, tz) at `speed` studs/s for dt seconds, kept in the roaming ring.
function BossRules.moveToward(
	x: number,
	z: number,
	tx: number,
	tz: number,
	speed: number,
	dt: number,
	roam: any
): (number, number)
	local dx, dz = tx - x, tz - z
	local distance = math.sqrt(dx * dx + dz * dz)
	local stepLength = speed * dt
	if distance > stepLength and distance > 1e-6 then
		x += dx / distance * stepLength
		z += dz / distance * stepLength
	else
		x, z = tx, tz
	end
	return BossRules.intoRing(x, z, roam)
end

-- Which attack comes next: one of those whose cooldown is over (readyAt[i] <= now), picked by `roll`; nil when none.
function BossRules.pickAttack(attacks: { any }, readyAt: { number }, now: number, roll: number): number?
	local ready = {}
	for index in attacks do
		if (readyAt[index] or 0) <= now then
			table.insert(ready, index)
		end
	end
	if #ready == 0 then
		return nil
	end
	return ready[math.clamp(math.floor(roll * #ready) + 1, 1, #ready)]
end

-- The pause after an attack: the boss's own, shorter for the big boss.
function BossRules.pause(pause: number, big: boolean, config: any): number
	return if big then pause / config.big.attackSpeed else pause
end

-- The bosses the schedule may send (Config/Bosses bosses[id].enabled), in the config's order.
function BossRules.enabledIds(config: any): { string }
	local ids = {}
	for _, id in config.order do
		local boss = config.bosses[id]
		if boss and boss.enabled ~= false then
			table.insert(ids, id)
		end
	end
	return ids
end

-- What comes next: the normal boss at `normalAt` or the big one at `bigAt` (both on the same clock), whichever is first;
-- the big one when they fall together. Returns the time and whether it is the big one.
function BossRules.nextBoss(normalAt: number, bigAt: number): (number, boolean)
	if bigAt <= normalAt then
		return bigAt, true
	end
	return normalAt, false
end

-- Remaining seconds as "4:59" (the announcement and the timer on the health bar).
function BossRules.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return BossRules
