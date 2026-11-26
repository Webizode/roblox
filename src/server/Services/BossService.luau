-- Arena bosses (Config/Bosses, numbers in BossRules). The server owns all of it: when a boss comes, where it is, its
-- health, the damage every ice ball does (CombatService calls damage), its attacks and who they hit, the truce and the
-- rewards. Clients only draw it (BossController) from the state published on ReplicatedStorage.BossState and the
-- BossEvent remote.
--
-- Rhythm: a normal boss every 15 to 20 minutes, a big one at every full hour (server clock) with an announcement 5
-- minutes before, never two at once (BossRules.nextNormalAt keeps the normal ones out of the big one's block). A boss
-- leaves after `lifetime` seconds without a reward.
-- Truce (Config/Bosses truce): while a boss is alive no ice ball hits a player and nobody takes another player's
-- spilled scoops (CombatService, LootService ask BossService.truce()). The Big Swirl and catching go on.
-- Attacks never knock down or topple: a hit shoves the tower (the client holds it up) and 2 to 3 scoops fall off the
-- top as the owner's loot (TowerService.bossHit).
--
-- Studio only: ServerStorage.StudioBossTest starts and ends bosses at once (see Start).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local BossRules = require(Shared:WaitForChild("BossRules"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))
local BossConfig = require(Config:WaitForChild("Bosses"))
local Flavors = require(Config:WaitForChild("Flavors"))
local UpgradesConfig = require(Config:WaitForChild("Upgrades"))
local Features = require(Config:WaitForChild("Features"))

local BossService = {}

type Attack = {
	id: number,
	kind: string,
	spec: any,
	impactAt: number,
	x: number,
	z: number,
	toX: number?, -- leap: where the boss lands
	toZ: number?,
	spots: { Vector3 }?, -- puddle
	waveUntil: number?, -- wave: the ring runs until then
	hit: { [Player]: boolean }, -- wave: everybody at most once
	struck: boolean,
}

type Puddle = { x: number, z: number, radius: number, untilAt: number, slow: number }

type Boss = {
	id: string,
	spec: any,
	big: boolean,
	scale: number,
	x: number,
	z: number,
	y: number,
	facing: number,
	health: number,
	full: number,
	startedAt: number,
	endsAt: number,
	damage: { [Player]: number },
	readyAt: { number },
	nextAttackAt: number,
	attack: Attack?,
	puddles: { Puddle },
	wanderX: number,
	wanderZ: number,
}

local registry
local rng = Random.new()
local boss: Boss? = nil
local stateFolder: Folder
local nextAttackId = 0

-- the schedule, on the wall clock (os.time: the full hours are the real ones)
local nextNormalAt = 0
local bigHour = 0 -- the full hour of the next big boss
local announcedHour = -1
local bigDoneHour = -1

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- the living players in the arena, with their roots
local function arenaPlayers(): { { player: Player, root: BasePart } }
	local list = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and registry.ArenaService.inArena(player) then
			table.insert(list, { player = player, root = root })
		end
	end
	return list
end

local function groundY(x: number, z: number, fallback: number): number
	local ground = registry.MapService.groundAt(x, 80, z, 120)
	return if ground and ground.y then ground.y else fallback
end

-- The state every client draws from: attributes on ReplicatedStorage.BossState.
local function publish()
	local b = boss
	stateFolder:SetAttribute("Active", b ~= nil)
	stateFolder:SetAttribute("Truce", BossService.truce())
	if not b then
		return
	end
	stateFolder:SetAttribute("Id", b.id)
	stateFolder:SetAttribute("Model", b.spec.model)
	stateFolder:SetAttribute("Name", b.spec.name)
	stateFolder:SetAttribute("Big", b.big)
	stateFolder:SetAttribute("Scale", b.scale)
	stateFolder:SetAttribute("Hover", (b.spec.hover or 0) * b.scale)
	stateFolder:SetAttribute("Health", math.max(0, math.ceil(b.health)))
	stateFolder:SetAttribute("MaxHealth", b.full)
	stateFolder:SetAttribute("EndsAt", b.endsAt)
	stateFolder:SetAttribute("Position", Vector3.new(b.x, b.y, b.z))
	stateFolder:SetAttribute("Facing", b.facing)
end

local function publishAnnounce(startsAt: number?)
	stateFolder:SetAttribute("BigStartsAt", startsAt or 0)
end

-- Starts boss `id` (big or not) now. False when one is alive or the id is unknown.
local function spawn(id: string, big: boolean): boolean
	local spec = BossConfig.bosses[id]
	if boss or not spec then
		return false
	end
	local players = arenaPlayers()
	local angle = rng:NextNumber() * 2 * math.pi
	local x, z = math.cos(angle) * BossConfig.roam.spawnRadius, math.sin(angle) * BossConfig.roam.spawnRadius
	local full = BossRules.maxHealth(spec.health, #players, big, BossConfig)
	local time = now()
	boss = {
		id = id,
		spec = spec,
		big = big,
		scale = (spec.scale or 1) * (if big then BossConfig.big.scale else 1),
		x = x,
		z = z,
		y = groundY(x, z, 1.2),
		facing = angle + math.pi,
		health = full,
		full = full,
		startedAt = time,
		endsAt = time + BossConfig.lifetime,
		damage = {},
		readyAt = {},
		nextAttackAt = time + 3, -- a moment to see it first
		attack = nil,
		puddles = {},
		wanderX = x,
		wanderZ = z,
	}
	publish()
	Remotes.BossEvent:FireAllClients("start", spec.name, big, BossConfig.truce)
	print(
		string.format(
			"[Boss] %s%s appears with %d health (%d in the arena)",
			if big then "BIG " else "",
			spec.name,
			full,
			#players
		)
	)
	return true
end

-- The boss goes: defeated (rewards for everybody who did damage) or escaped (nothing). The truce ends at once.
local function finish(reason: string)
	local b = boss
	if not b then
		return
	end
	boss = nil
	publish()
	Remotes.BossEvent:FireAllClients("end", reason, b.spec.name, BossConfig.truce)
	nextNormalAt = BossRules.nextNormalAt(os.time(), rng:NextNumber(), BossConfig.schedule)
	print(string.format("[Boss] %s %s; the next normal boss in %d s", b.spec.name, reason, nextNormalAt - os.time()))
	if reason ~= "defeated" then
		return
	end
	local damages: { [Player]: number } = {}
	for player, amount in b.damage do
		if player.Parent then
			damages[player] = amount
		end
	end
	local coins = BossRules.rewards(damages, b.big, BossConfig)
	local odds = if b.big then BossConfig.big.odds else BossConfig.reward.odds
	local scoop = BossConfig.reward.scoop
	local index = 0
	for player, amount in coins do
		index += 1
		registry.TowerService.addCoins(player, amount)
		local rarity = BossRules.rollRarity(rng:NextNumber(), odds)
		local options = BossRules.flavorsOf(rarity, Flavors.list)
		local flavorId = options[rng:NextInteger(1, math.max(1, #options))]
		local angle = index * 2.4
		local at = Vector3.new(b.x + math.cos(angle) * scoop.spread, b.y, b.z + math.sin(angle) * scoop.spread)
		if flavorId then
			registry.LootService.reward(player, flavorId, at, scoop.ownerSeconds, scoop.lifetime)
		end
		Remotes.BossEvent:FireClient(player, "reward", amount, rarity)
	end
end

-- An attack hit `player` at `root` from (fromX, fromZ): a shove and 2 to 3 scoops off the top, unless dodged.
local function strike(player: Player, root: BasePart, fromX: number, fromZ: number, wave: boolean)
	local b = boss :: Boss
	local p = root.Position
	local feet: number? = nil
	if wave then
		local humanoid = (root.Parent :: Model):FindFirstChildOfClass("Humanoid")
		local hip = if humanoid then humanoid.HipHeight else 2
		feet = p.Y - root.Size.Y / 2 - hip - groundY(p.X, p.Z, p.Y)
	end
	if BossRules.dodged(registry.TowerService.lastDashAt(player), now(), feet, BossConfig) then
		Remotes.BossEvent:FireClient(player, "dodged")
		return
	end
	local dx, dz = p.X - fromX, p.Z - fromZ
	local length = math.sqrt(dx * dx + dz * dz)
	if length > 1e-3 then
		dx, dz = dx / length, dz / length
	else
		dx, dz = 1, 0
	end
	local drop = BossRules.dropCount(registry.TowerService.count(player), rng:NextNumber(), BossConfig)
	local dropped = registry.TowerService.bossHit(player, drop, dx, dz)
	local kick = BossConfig.hit.kick * (if b.big then BossConfig.big.hitKick else 1)
	Remotes.BossEvent:FireClient(player, "hit", dx, dz, kick, dropped)
end

-- Starts the next attack of the boss.
local function startAttack(b: Boss, time: number)
	local attacks = b.spec.attacks
	local index = BossRules.pickAttack(attacks, b.readyAt, time, rng:NextNumber())
	if not index then
		return
	end
	local spec = attacks[index]
	b.readyAt[index] = time + spec.cooldown
	nextAttackId += 1
	local attack: Attack = {
		id = nextAttackId,
		kind = spec.kind,
		spec = spec,
		impactAt = time + spec.warn,
		x = b.x,
		z = b.z,
		hit = {},
		struck = false,
	}
	local scale = b.scale
	local players = arenaPlayers()
	local data: { [string]: any } = {
		id = attack.id,
		kind = spec.kind,
		impactAt = attack.impactAt,
		warn = spec.warn,
		x = b.x,
		z = b.z,
		y = b.y,
	}
	if spec.kind == "stomp" then
		data.radius = spec.radius * scale
	elseif spec.kind == "wave" then
		data.speed, data.width, data.reach = spec.speed, spec.width * scale, spec.reach
	elseif spec.kind == "leap" then
		-- onto the nearest player's spot, kept in the ring
		local best, bestDistance = nil, math.huge
		for _, entry in players do
			local p = entry.root.Position
			local d = (p.X - b.x) ^ 2 + (p.Z - b.z) ^ 2
			if d < bestDistance then
				best, bestDistance = p, d
			end
		end
		local tx, tz = b.wanderX, b.wanderZ
		if best then
			tx, tz = best.X, best.Z
		end
		tx, tz = BossRules.intoRing(tx, tz, BossConfig.roam)
		attack.toX, attack.toZ = tx, tz
		data.toX, data.toZ, data.toY = tx, tz, groundY(tx, tz, b.y)
		data.radius = spec.radius * scale
	elseif spec.kind == "puddle" then
		local spots = {}
		for n = 1, spec.count do
			local around = players[((n - 1) % math.max(1, #players)) + 1]
			local cx, cz = b.x, b.z
			if around then
				cx, cz = around.root.Position.X, around.root.Position.Z
			end
			local angle = rng:NextNumber() * 2 * math.pi
			local distance = rng:NextNumber() * spec.radius * 0.8
			local px, pz = cx + math.cos(angle) * distance, cz + math.sin(angle) * distance
			table.insert(spots, Vector3.new(px, groundY(px, pz, b.y), pz))
		end
		attack.spots = spots
		data.spots, data.radius, data.duration = spots, spec.radius * scale, spec.duration
	end
	b.attack = attack
	Remotes.BossEvent:FireAllClients("attack", data)
end

-- The moment an attack strikes (and, for a wave, every tick while its ring runs).
local function resolveAttack(b: Boss, attack: Attack, time: number)
	local spec = attack.spec
	local tolerance = BossConfig.hit.tolerance
	local players = arenaPlayers()
	if attack.kind == "stomp" or attack.kind == "leap" then
		if attack.kind == "leap" then
			b.x, b.z = attack.toX :: number, attack.toZ :: number
			b.y = groundY(b.x, b.z, b.y)
		end
		local radius = spec.radius * b.scale
		for _, entry in players do
			local p = entry.root.Position
			if BossRules.inDisc(p.X, p.Z, b.x, b.z, radius, tolerance) then
				strike(entry.player, entry.root, b.x, b.z, false)
			end
		end
		attack.struck = true
		b.attack = nil
		b.nextAttackAt = time + BossRules.pause(b.spec.pause, b.big, BossConfig)
	elseif attack.kind == "wave" then
		if not attack.waveUntil then
			attack.waveUntil = attack.impactAt + spec.reach / spec.speed
		end
		local ring = (time - attack.impactAt) * spec.speed
		for _, entry in players do
			local p = entry.root.Position
			if
				not attack.hit[entry.player]
				and BossRules.waveTouches(p.X, p.Z, attack.x, attack.z, ring, spec.width * b.scale, tolerance)
			then
				attack.hit[entry.player] = true
				strike(entry.player, entry.root, attack.x, attack.z, true)
			end
		end
		if time >= (attack.waveUntil :: number) then
			b.attack = nil
			b.nextAttackAt = time + BossRules.pause(b.spec.pause, b.big, BossConfig)
		end
	elseif attack.kind == "puddle" then
		for _, spot in attack.spots or {} do
			table.insert(b.puddles, {
				x = spot.X,
				z = spot.Z,
				radius = spec.radius * b.scale,
				untilAt = time + spec.duration,
				slow = spec.slowFactor,
			})
		end
		b.attack = nil
		b.nextAttackAt = time + BossRules.pause(b.spec.pause, b.big, BossConfig)
	end
end

local function tick(dt: number)
	local b = boss
	if not b then
		return
	end
	local time = now()
	if time >= b.endsAt then
		finish("escaped")
		return
	end
	local players = arenaPlayers()
	-- more players came in: more health
	local full = BossRules.maxHealth(b.spec.health, #players, b.big, BossConfig)
	b.full, b.health = BossRules.grow(b.health, b.full, full)

	-- move towards the nearest player (or a wandering point), not while an attack winds up
	local attack = b.attack
	if not attack or attack.kind == "wave" or attack.kind == "puddle" then
		local tx, tz = b.wanderX, b.wanderZ
		local best = math.huge
		for _, entry in players do
			local p = entry.root.Position
			local d = (p.X - b.x) ^ 2 + (p.Z - b.z) ^ 2
			if d < best then
				best, tx, tz = d, p.X, p.Z
			end
		end
		if best == math.huge and (tx - b.x) ^ 2 + (tz - b.z) ^ 2 < 4 then
			local angle = rng:NextNumber() * 2 * math.pi
			local radius = BossConfig.roam.minRadius
				+ rng:NextNumber() * (BossConfig.roam.maxRadius - BossConfig.roam.minRadius)
			b.wanderX, b.wanderZ = math.cos(angle) * radius, math.sin(angle) * radius
		end
		-- stop a little short of a player instead of walking into them
		local keep = BossConfig.hitbox.radius * b.scale + 3
		if best < keep * keep then
			tx, tz = b.x, b.z
		end
		local x, z = BossRules.moveToward(b.x, b.z, tx, tz, b.spec.speed, dt, BossConfig.roam)
		if (x - b.x) ^ 2 + (z - b.z) ^ 2 > 1e-6 then
			b.facing = math.atan2(-(x - b.x), -(z - b.z))
		end
		b.x, b.z = x, z
		b.y = groundY(x, z, b.y)
	end

	if attack then
		if time >= attack.impactAt then
			resolveAttack(b, attack, time)
		end
	elseif time >= b.nextAttackAt then
		startAttack(b, time)
	end

	-- sticky puddles: everybody in one is held for a moment longer
	for index = #b.puddles, 1, -1 do
		local puddle = b.puddles[index]
		if time >= puddle.untilAt then
			table.remove(b.puddles, index)
		else
			for _, entry in players do
				local p = entry.root.Position
				if BossRules.inDisc(p.X, p.Z, puddle.x, puddle.z, puddle.radius, BossConfig.hit.tolerance) then
					registry.TowerService.setSticky(entry.player, time + 0.4, puddle.slow)
				end
			end
		end
	end
	publish()
end

-- The schedule, once a second: the big boss's announcement and start, the normal ones.
local function schedule()
	local clock = os.time()
	-- the next big boss: the coming full hour, once the last one has come (or was missed by far)
	if bigDoneHour == bigHour or clock > bigHour + BossConfig.lifetime then
		bigHour = BossRules.hourAtOrAfter(clock + 1)
	end
	if announcedHour ~= bigHour and bigDoneHour ~= bigHour and bigHour - clock <= BossConfig.schedule.announce then
		announcedHour = bigHour
		local startsAt = now() + (bigHour - clock)
		publishAnnounce(startsAt)
		Remotes.BossEvent:FireAllClients("announce", startsAt, BossConfig.truce)
		print(string.format("[Boss] big boss announced for %d s from now", bigHour - clock))
	end
	if boss then
		return
	end
	if bigDoneHour ~= bigHour and clock >= bigHour then
		bigDoneHour = bigHour
		publishAnnounce(nil)
		local id = BossConfig.order[rng:NextInteger(1, #BossConfig.order)]
		spawn(id, true)
		return
	end
	if clock >= nextNormalAt then
		if BossRules.blockingHour(clock, BossConfig.schedule) then
			nextNormalAt = BossRules.nextNormalAt(clock, rng:NextNumber(), BossConfig.schedule)
			return
		end
		local id = BossConfig.order[rng:NextInteger(1, #BossConfig.order)]
		spawn(id, false)
	end
end

function BossService.Init(reg)
	registry = reg
end

-- Whether the truce holds right now: a boss is alive and Config/Bosses truce is on.
function BossService.truce(): boolean
	return boss ~= nil and BossConfig.truce == true
end

-- The boss's body for ice balls (CombatService), or nil without a boss.
function BossService.capsule(): { x: number, y: number, z: number, radius: number, halfHeight: number }?
	local b = boss
	if not b then
		return nil
	end
	local half = BossConfig.hitbox.halfHeight * b.scale
	return {
		x = b.x,
		y = b.y + half + (b.spec.hover or 0) * b.scale,
		z = b.z,
		radius = BossConfig.hitbox.radius * b.scale,
		halfHeight = half,
	}
end

-- An ice ball of `thrower` hit the boss with `power` (0..1, Combat.hitPower). The thrower's Boss Power upgrade counts
-- here and nowhere else.
function BossService.damage(thrower: Player, power: number, _position: Vector3)
	local b = boss
	if not b then
		return
	end
	local data = registry.DataService.data(thrower)
	local level = Upgrades.levelOf(data and data.upgrades, "bossPower", UpgradesConfig)
	local amount = BossRules.damage(power, Upgrades.value("bossPower", level, UpgradesConfig), BossConfig)
	if amount <= 0 then
		return
	end
	amount = math.min(amount, b.health)
	b.health -= amount
	b.damage[thrower] = (b.damage[thrower] or 0) + amount
	Remotes.BossEvent:FireClient(thrower, "damage", amount)
	publish()
	if b.health <= 0 then
		finish("defeated")
	end
end

function BossService.Start()
	stateFolder = Instance.new("Folder")
	stateFolder.Name = "BossState"
	stateFolder:SetAttribute("Active", false)
	stateFolder:SetAttribute("Truce", false)
	stateFolder:SetAttribute("BigStartsAt", 0)
	stateFolder.Parent = ReplicatedStorage

	if not (Features.bosses and BossConfig.enabled) then
		print("[Boss] off (Features.bosses / Config/Bosses enabled)")
	else
		nextNormalAt = BossRules.nextNormalAt(os.time(), rng:NextNumber(), BossConfig.schedule, true)
		bigHour = BossRules.hourAtOrAfter(os.time())
		print(
			string.format(
				"[Boss] first normal boss in %d s, the big boss at the full hour in %d s",
				nextNormalAt - os.time(),
				bigHour - os.time()
			)
		)
		task.spawn(function()
			while true do
				task.wait(1)
				schedule()
			end
		end)
	end

	local step = 1 / BossConfig.tickRate
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= step then
			local elapsed = math.min(accumulator, 0.25)
			accumulator = 0
			tick(elapsed)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if boss then
			boss.damage[player] = nil
		end
	end)

	-- Studio only: start, end or hurry bosses from the command bar or the Studio MCP:
	--   StudioBossTest:Invoke("spawn", "iceBrute")   -- a normal boss now ("gummyBear", "creamGhost")
	--   StudioBossTest:Invoke("big", "gummyBear")    -- a big boss now
	--   StudioBossTest:Invoke("announce", 300)       -- announce a big boss in that many seconds (default 300)
	--   StudioBossTest:Invoke("kill")                -- defeat it now: rewards for everybody who did damage
	--   StudioBossTest:Invoke("escape")              -- it leaves without a reward
	--   StudioBossTest:Invoke("hurt", player, 100)   -- that much damage as if the player had thrown it
	--   StudioBossTest:Invoke("state")               -- a summary
	if RunService:IsStudio() then
		local test = Instance.new("BindableFunction")
		test.Name = "StudioBossTest"
		test.OnInvoke = function(action: string, a: any, b: any)
			if action == "spawn" or action == "big" then
				return spawn(if type(a) == "string" then a else BossConfig.order[1], action == "big")
			elseif action == "announce" then
				local seconds = if type(a) == "number" then a else BossConfig.schedule.announce
				local clock = os.time()
				-- pretend the next full hour is that far away
				bigHour = clock + math.floor(seconds)
				announcedHour, bigDoneHour = -1, -1
				schedule()
				return true
			elseif action == "kill" and boss then
				boss.health = 0
				finish("defeated")
				return true
			elseif action == "escape" and boss then
				finish("escaped")
				return true
			elseif action == "hurt" and boss and typeof(a) == "Instance" and a:IsA("Player") then
				local amount = if type(b) == "number" then b else 100
				local current = boss
				current.health -= amount
				current.damage[a] = (current.damage[a] or 0) + amount
				publish()
				if current.health <= 0 then
					finish("defeated")
				end
				return current.health
			elseif action == "state" then
				local current = boss
				return {
					alive = current ~= nil,
					id = current and current.id,
					big = current and current.big,
					health = current and current.health,
					full = current and current.full,
					truce = BossService.truce(),
					nextNormalIn = nextNormalAt - os.time(),
					bigIn = bigHour - os.time(),
				}
			end
			return false
		end
		test.Parent = ServerStorage
	end
end

return BossService
