-- Ice-ball throws, the only normal attack. The server owns everything that matters: ammo and reload, the charge
-- (it times the hold itself and accepts the strength and a perfect throw only as far as that timing allows), where a ball starts and how it flies
-- (simulated here every frame), what it hits, the hit power, the knockdown decision and who may be hit. Clients only draw the ball and play the reaction the server announces; the victim's client
-- applies the knockback and the tower shove, like every other tower force.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Combat = require(Shared:WaitForChild("Combat"))
local MouseRules = require(Shared:WaitForChild("MouseRules"))
local AimRules = require(Shared:WaitForChild("AimRules"))
local Loot = require(Shared:WaitForChild("Loot"))
local MapQuery = require(Shared:WaitForChild("MapQuery"))
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))
local LootConfig = require(Shared:WaitForChild("Config"):WaitForChild("Loot"))
local Features = require(Shared:WaitForChild("Config"):WaitForChild("Features"))
local MapConfig = require(Shared:WaitForChild("Config"):WaitForChild("Map"))

local CombatService = {}

local registry

type PlayerState = {
	ammo: Combat.Ammo,
	stagger: number,
	lastHitAt: number,
	downUntil: number,
	reloadToken: number,
	chargeStartedAt: number?, -- server time the throw button went down; cleared by a throw, knockdown or respawn
	lastChargeAt: number,
	combatMode: boolean, -- only in combat mode can the player charge and throw; off after every respawn
	lastModeAt: number,
	unshieldedUntil: number, -- a throw from the own cart's safe zone lifts its protection until then
}

type Ball = {
	id: number,
	thrower: Player,
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	t0: number,
	lastT: number,
	speed: number, -- at release
	strength: number, -- Combat.strength, as the server accepted it
	perfect: boolean,
}

-- without a usable right hand the ball leaves a little in front of the chest
local RELEASE_UP = 1.5
local RELEASE_FORWARD = 1
-- one charge start per this many seconds is plenty for a human; faster ones are dropped
local CHARGE_INTERVAL = 0.05

-- keyed by Player, not by character: a respawn keeps ammo, reload and stagger
local states: { [Player]: PlayerState } = {}
local balls: { Ball } = {}
-- the last hit each player took that did harm, so a topple soon after it is credited to its thrower
local lastHitBy: { [Player]: { thrower: Player, at: number } } = {}
local nextId = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Temporary throw diagnostics (Features.debugThrow). Rejections print at most once a second per player.
local lastRejectLog: { [Player]: number } = {}
local function debugLog(message: string)
	if Features.debugThrow then
		print("[Throw] " .. message)
	end
end
local function debugReject(player: Player, reason: string)
	if Features.debugThrow and os.clock() - (lastRejectLog[player] or -math.huge) >= 1 then
		lastRejectLog[player] = os.clock()
		print(`[Throw] rejected {player.Name}: {reason}`)
	end
end

-- A raycast that only stops at parts a ball cannot fly through: anything without collision (invisible zones,
-- trigger volumes) and the thin decoration of Config/Map is skipped, the same rule the client's aim ray follows.
local function solidRaycast(origin: Vector3, direction: Vector3, ignore: { Instance }): RaycastResult?
	return MapQuery.throwRaycast(origin, direction, ignore)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Studs from the player's root to their own cart's ServePoint, or nil without either.
local function cartDistance(player: Player, root: BasePart): number?
	local servePoint = registry.PlotService.servePoint(player)
	return servePoint and (root.Position - servePoint).Magnitude
end

local function publishAmmo(player: Player, state: PlayerState)
	player:SetAttribute("IceBalls", state.ammo.count)
	player:SetAttribute("IceBallsReadyAt", state.ammo.reloadUntil)
end

-- Refill exactly when the reload ends, so the HUD shows the new load without waiting for the next throw.
local function scheduleRefill(player: Player, state: PlayerState)
	state.reloadToken += 1
	local token = state.reloadToken
	task.delay(math.max(0, state.ammo.reloadUntil - now()) + 0.05, function()
		if states[player] ~= state or state.reloadToken ~= token then
			return
		end
		Combat.refresh(state.ammo, now(), Config)
		publishAmmo(player, state)
	end)
end

-- Whether the player is charging a throw, published as the Charging attribute so every client can draw the wind-up.
local function setCharging(player: Player, state: PlayerState, startedAt: number?)
	state.chargeStartedAt = startedAt
	player:SetAttribute("Charging", startedAt ~= nil)
end

-- Combat mode is published as the CombatMode attribute, so every client can draw the ball in the hand.
local function setCombatMode(player: Player, state: PlayerState, on: boolean)
	state.combatMode = on
	if not on then
		setCharging(player, state, nil)
	end
	player:SetAttribute("CombatMode", on)
end

-- Combat mode on or off (R). Off always goes through, so a client can never get stuck in it; on is rate-limited and
-- only granted in the arena (MouseRules, ArenaService).
local function onSetCombatMode(player: Player, on: any)
	local state = states[player]
	if not state or type(on) ~= "boolean" or on == state.combatMode then
		return
	end
	local time = now()
	if on and time - state.lastModeAt < Config.combatModeInterval then
		return
	end
	if on and not MouseRules.canEnterCombat(registry.ArenaService.inArena(player, MapConfig.arena.serverSlack)) then
		return -- combat mode only exists in the arena
	end
	state.lastModeAt = time
	setCombatMode(player, state, on)
end

-- The throw button went down: the server starts its own clock for the charge. Ammo and the rest are checked on
-- the throw itself; a start without a throw just gets replaced by the next one.
local function onCharge(player: Player)
	local state = states[player]
	local time = now()
	if not state or not state.combatMode or time - state.lastChargeAt < CHARGE_INTERVAL or time < state.downUntil then
		return
	end
	state.lastChargeAt = time
	setCharging(player, state, time)
end

-- Where the ball leaves: the right hand, if the character has one near its root, and not through a wall.
local function releasePoint(character: Model, root: BasePart): Vector3
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local point = if hand
			and hand:IsA("BasePart")
			and (hand.Position - root.Position).Magnitude <= Config.handReach
		then hand.Position
		else root.Position + Vector3.new(0, RELEASE_UP, 0) + root.CFrame.LookVector * RELEASE_FORWARD
	local blocked = solidRaycast(root.Position, point - root.Position, { character })
	return if blocked then root.Position:Lerp(blocked.Position, 0.8) else point
end

-- Release: the strength and a perfect throw are the client's claims as far as the server's own timing of the hold
-- allows (Combat.validateStrength, validatePerfect); the ball flies from the hand through the aim point at the speed
-- they give. A perfect throw is full strength at perfect.speed.
local function onThrow(player: Player, aimX: any, aimY: any, aimZ: any, claimedStrength: any, claimedPerfect: any)
	local state = states[player]
	if not state then
		return
	end
	local startedAt = state.chargeStartedAt
	setCharging(player, state, nil)
	if not state.combatMode then
		debugReject(player, "not in combat mode")
		return
	end
	if type(aimX) ~= "number" or type(aimY) ~= "number" or type(aimZ) ~= "number" then
		debugReject(player, "aim point is not three numbers")
		return
	end
	local root = rootOf(player)
	local time = now()
	-- the cheap checks first, so spammed requests cost no raycast
	Combat.refresh(state.ammo, time, Config)
	if not root then
		debugReject(player, "no living character")
		return
	elseif time < state.downUntil then
		debugReject(player, "knocked down")
		return
	elseif state.ammo.count <= 0 then
		debugReject(player, "no ammo (reloading)")
		return
	elseif time - state.ammo.lastThrowAt < Config.throwInterval then
		debugReject(player, "too soon after the last throw")
		return
	end
	local held = if startedAt then time - startedAt else 0
	local perfect = Combat.validatePerfect(claimedPerfect == true, held, Config)
	local strength = if perfect
		then 1
		else Combat.validateStrength(
			if type(claimedStrength) == "number" then claimedStrength else 0,
			held,
			Config
		)
	local speed = Combat.throwSpeed(strength, perfect, Config)
	local origin = releasePoint(root.Parent :: Model, root)
	local ok, vx, vy, vz = Combat.aimVelocity(origin.X, origin.Y, origin.Z, aimX, aimY, aimZ, speed, Config)
	if not ok then
		debugReject(player, `aim point {Vector3.new(aimX, aimY, aimZ)} unusable from the hand at {origin}`)
		return
	end
	if not Combat.tryThrow(state.ammo, time, Config) then
		debugReject(player, "ammo check failed")
		return
	end
	registry.TowerService.interruptStance(player) -- a throw in the steady stance ends it (charging does not)
	-- no camping: a throw from the own safe zone lifts its protection for a while (UnshieldedUntil for the HUD)
	local unshielded = Loot.afterThrow(cartDistance(player, root), time, state.unshieldedUntil, LootConfig)
	if unshielded ~= state.unshieldedUntil then
		state.unshieldedUntil = unshielded
		player:SetAttribute("UnshieldedUntil", unshielded)
	end
	debugLog(
		string.format(
			"%s throws: strength %.2f%s (claimed %s, held %.2f s), %.0f studs/s from %s to aim %s (%.1f studs away)",
			player.Name,
			strength,
			if perfect then ", perfect" else "",
			tostring(claimedStrength),
			held,
			speed,
			tostring(origin),
			tostring(Vector3.new(aimX, aimY, aimZ)),
			(Vector3.new(aimX, aimY, aimZ) - origin).Magnitude
		)
	)
	publishAmmo(player, state)
	if state.ammo.count == 0 then
		scheduleRefill(player, state)
	end

	nextId += 1
	table.insert(balls, {
		id = nextId,
		thrower = player,
		ox = origin.X,
		oy = origin.Y,
		oz = origin.Z,
		vx = vx,
		vy = vy,
		vz = vz,
		-- the throw is decided now; the ball leaves the hand releaseDelay later, with the throw animation's release
		t0 = time + Config.releaseDelay,
		lastT = 0,
		speed = speed,
		strength = strength,
		perfect = perfect,
	})
	-- told right away, so every client starts the throw animation now and the ball with its t0
	Remotes.IceBallThrown:FireAllClients(
		nextId,
		player,
		origin,
		Vector3.new(vx, vy, vz),
		time + Config.releaseDelay,
		perfect
	)
end

local function resolve(
	ball: Ball,
	victim: Player?,
	position: Vector3,
	power: number,
	knockdown: boolean,
	shielded: boolean?
)
	local flat = Vector3.new(ball.vx, 0, ball.vz)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
	Remotes.IceBallResolved:FireAllClients(
		ball.id,
		ball.thrower,
		victim,
		position,
		flat.X,
		flat.Z,
		power,
		knockdown,
		shielded == true
	)
end

local function hitPlayer(ball: Ball, victim: Player, position: Vector3, distance: number, speed: number)
	local state = states[victim]
	local time = now()
	-- at the own cart a hit lands but does no harm: no power, no stagger, no knockdown (design rule 4)
	local root = rootOf(victim)
	if state and root and Loot.isShielded(cartDistance(victim, root), time, state.unshieldedUntil, LootConfig) then
		debugLog(`{victim.Name} hit by {ball.thrower.Name} in their cart's safe zone: no harm`)
		resolve(ball, victim, position, 0, false, true)
		return
	end
	local power = Combat.hitPower(distance, speed, ball.speed, ball.strength, Config)
	local knockdown = false
	if state then
		local before = math.max(0, state.stagger - Config.staggerDecay * math.max(0, time - state.lastHitAt))
		state.stagger, knockdown = Combat.addHit(state.stagger, state.lastHitAt, time, power, Config)
		debugLog(
			string.format(
				"%s hit by %s: power %.2f (%.2f studs off the axis, %.0f of %.0f studs/s, strength %.2f%s), stagger %.2f + %.2f %s %.1f%s",
				victim.Name,
				ball.thrower.Name,
				power,
				distance,
				speed,
				ball.speed,
				ball.strength,
				if ball.perfect then ", perfect" else "",
				before,
				power,
				if knockdown then ">=" else "<",
				Config.knockdownAt,
				if knockdown then ": KNOCKDOWN" else ""
			)
		)
		state.lastHitAt = time
		registry.TowerService.hitStance(victim, power)
		lastHitBy[victim] = { thrower = ball.thrower, at = time }
		if knockdown then
			Remotes.HitFeedback:FireClient(ball.thrower, "knockdown", victim, 0)
			state.downUntil = time + Config.knockdownTime
			-- a knockdown drops the charge, ends combat mode and the steady stance; the player switches them on again
			-- after getting up
			setCombatMode(victim, state, false)
			registry.TowerService.endStance(victim)
			-- the head start on the own spilled scoops only begins once the player is up again
			registry.LootService.ownerDown(victim, state.downUntil)
		end
	end
	resolve(ball, victim, position, power, knockdown)
end

-- Moves every ball from its last checked time to now and resolves the first thing it touches: a player capsule
-- or the world. Players knocked down are not targets until they are up again, players outside the arena never are
-- (ArenaService), and nobody hits themselves.
local function step()
	local time = now()
	if #balls == 0 then
		return
	end
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end

	for index = #balls, 1, -1 do
		local ball = balls[index]
		if time < ball.t0 then
			continue -- still in the hand
		end
		local t = math.min(time - ball.t0, Config.maxFlight)
		local ax, ay, az =
			Combat.position(ball.ox, ball.oy, ball.oz, ball.vx, ball.vy, ball.vz, Config.gravity, ball.lastT)
		local bx, by, bz = Combat.position(ball.ox, ball.oy, ball.oz, ball.vx, ball.vy, ball.vz, Config.gravity, t)
		local from, to = Vector3.new(ax, ay, az), Vector3.new(bx, by, bz)

		local bestS, bestVictim, bestDistance = math.huge, nil :: Player?, 0
		for _, player in Players:GetPlayers() do
			local victimState = states[player]
			local root = rootOf(player)
			-- players outside the arena are never hit: the ball flies on through them, even one already in the air
			local target = player ~= ball.thrower and root and registry.ArenaService.inArena(player)
			if target and root and not (victimState and time < victimState.downUntil) then
				local p = root.Position
				local distance, s = Combat.closestToCapsule(ax, ay, az, bx, by, bz, p.X, p.Y, p.Z, Config.hitHalfHeight)
				if distance <= Config.hitRadius + Config.ballRadius and s < bestS then
					bestS, bestVictim, bestDistance = s, player, distance
				end
			end
		end

		local worldHit = solidRaycast(from, to - from, characters)
		local worldS = if worldHit
			then (worldHit.Position - from).Magnitude / math.max((to - from).Magnitude, 1e-6)
			else math.huge

		local resolved = true
		if bestVictim and bestS <= worldS then
			local hitT = ball.lastT + (t - ball.lastT) * bestS
			local speed = Vector3.new(ball.vx, ball.vy - Config.gravity * hitT, ball.vz).Magnitude
			debugLog(string.format("#%d hit %s after %.2f s", ball.id, bestVictim.Name, hitT))
			-- how centred: the closest its path comes to the axis on through the body, not where it entered the reach
			local p = (rootOf(bestVictim) :: BasePart).Position
			local centred = math.min(
				bestDistance,
				Combat.passDistance(
					ball.ox,
					ball.oy,
					ball.oz,
					ball.vx,
					ball.vy,
					ball.vz,
					ball.lastT,
					p.X,
					p.Y,
					p.Z,
					Config
				)
			)
			hitPlayer(ball, bestVictim, from:Lerp(to, bestS), centred, speed)
		elseif worldHit then
			debugLog(
				string.format(
					"#%d hit the world after %.2f s, %.1f studs from its start: %s",
					ball.id,
					t,
					(worldHit.Position - Vector3.new(ball.ox, ball.oy, ball.oz)).Magnitude,
					worldHit.Instance:GetFullName()
				)
			)
			resolve(ball, nil, worldHit.Position, 0, false)
		elseif t >= Config.maxFlight then
			debugLog(string.format("#%d reached its maximum flight time without a hit", ball.id))
			resolve(ball, nil, to, 0, false)
		else
			resolved = false
			ball.lastT = t
		end
		if resolved then
			table.remove(balls, index)
		end
	end
end

function CombatService.Init(reg)
	registry = reg
end

-- Whether the player lies knocked down right now.
function CombatService.isDown(player: Player): boolean
	local state = states[player]
	return state ~= nil and now() < state.downUntil
end

-- Server time until which the player lies knocked down (in the past when they are up).
function CombatService.downUntil(player: Player): number
	local state = states[player]
	return if state then state.downUntil else 0
end

-- Whether the player is in combat mode (the same state the CombatMode attribute shows).
function CombatService.inCombatMode(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.combatMode
end

-- The player's tower toppled and `lost` scoops fell off it (TowerService). If a hit of someone else came shortly
-- before (AimRules.credited), that thrower is told: it was their doing.
function CombatService.toppled(victim: Player, lost: number)
	local hit = lastHitBy[victim]
	lastHitBy[victim] = nil
	if lost > 0 and hit and hit.thrower.Parent and AimRules.credited(hit.at, now(), Config) then
		Remotes.HitFeedback:FireClient(hit.thrower, "toppled", victim, lost)
	end
end

function CombatService.Start()
	local function onPlayer(player: Player)
		local state: PlayerState = {
			ammo = Combat.newAmmo(Config),
			stagger = 0,
			lastHitAt = 0,
			downUntil = 0,
			reloadToken = 0,
			chargeStartedAt = nil,
			lastChargeAt = -math.huge,
			combatMode = false,
			lastModeAt = -math.huge,
			unshieldedUntil = 0,
		}
		states[player] = state
		publishAmmo(player, state)
		setCombatMode(player, state, false)
		-- a respawn keeps the ammo but never a charge or combat mode from the old character
		player.CharacterAdded:Connect(function()
			setCombatMode(player, state, false)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		lastRejectLog[player] = nil
		lastHitBy[player] = nil
		for victim, hit in lastHitBy do
			if hit.thrower == player then
				lastHitBy[victim] = nil
			end
		end
	end)

	Remotes.SetCombatMode.OnServerEvent:Connect(onSetCombatMode)
	Remotes.ChargeIceBall.OnServerEvent:Connect(onCharge)
	Remotes.ThrowIceBall.OnServerEvent:Connect(onThrow)
	RunService.Heartbeat:Connect(step)
	-- combat mode ends the moment a player leaves the arena (the client ends it there too)
	RunService.Heartbeat:Connect(function()
		for player, state in states do
			if
				MouseRules.mustLeaveCombat(
					state.combatMode,
					registry.ArenaService.inArena(player, MapConfig.arena.serverSlack)
				)
			then
				setCombatMode(player, state, false)
			end
		end
	end)
end

return CombatService
