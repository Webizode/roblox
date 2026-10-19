-- Ice-ball throws, the only normal attack. The server owns everything that matters: ammo and reload, the charge
-- (it times the hold itself and only accepts a bar value that fits it), where a ball starts and how it flies
-- (simulated here every frame), what it hits, the hit power, the knockdown decision and who may be hit. Clients only draw the ball and play the reaction the server announces; the victim's client
-- applies the knockback and the tower shove, like every other tower force.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Combat = require(Shared:WaitForChild("Combat"))
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))

local CombatService = {}

type PlayerState = {
	ammo: Combat.Ammo,
	stagger: number,
	lastHitAt: number,
	downUntil: number,
	reloadToken: number,
	chargeStartedAt: number?, -- server time the throw button went down; cleared by a throw, knockdown or respawn
	lastChargeAt: number,
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
	charge: number,
}

-- without a usable right hand the ball leaves a little in front of the chest
local RELEASE_UP = 1.5
local RELEASE_FORWARD = 1
-- one charge start per this many seconds is plenty for a human; faster ones are dropped
local CHARGE_INTERVAL = 0.05

-- keyed by Player, not by character: a respawn keeps ammo, reload and stagger
local states: { [Player]: PlayerState } = {}
local balls: { Ball } = {}
local nextId = 0

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

-- The throw button went down: the server starts its own clock for the charge. Ammo and the rest are checked on
-- the throw itself; a start without a throw just gets replaced by the next one.
local function onCharge(player: Player)
	local state = states[player]
	local time = now()
	if not state or time - state.lastChargeAt < CHARGE_INTERVAL or time < state.downUntil then
		return
	end
	state.lastChargeAt = time
	state.chargeStartedAt = time
end

-- Where the ball leaves: the right hand, if the character has one near its root, and not through a wall.
local function releasePoint(character: Model, root: BasePart): Vector3
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local point = if hand
			and hand:IsA("BasePart")
			and (hand.Position - root.Position).Magnitude <= Config.handReach
		then hand.Position
		else root.Position + Vector3.new(0, RELEASE_UP, 0) + root.CFrame.LookVector * RELEASE_FORWARD
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local blocked = workspace:Raycast(root.Position, point - root.Position, params)
	return if blocked then root.Position:Lerp(blocked.Position, 0.8) else point
end

-- Release: the charge is the client's bar value as far as the server's own timing of the hold allows, the ball
-- flies from the hand through the aim point at the speed that charge gives.
local function onThrow(player: Player, aimX: any, aimY: any, aimZ: any, claimedCharge: any)
	local state = states[player]
	if not state then
		return
	end
	local startedAt = state.chargeStartedAt
	state.chargeStartedAt = nil
	if type(aimX) ~= "number" or type(aimY) ~= "number" or type(aimZ) ~= "number" then
		return
	end
	local root = rootOf(player)
	local time = now()
	-- the cheap checks first, so spammed requests cost no raycast
	Combat.refresh(state.ammo, time, Config)
	if
		not root
		or time < state.downUntil
		or state.ammo.count <= 0
		or time - state.ammo.lastThrowAt < Config.throwInterval
	then
		return
	end
	local held = if startedAt then time - startedAt else 0
	local charge = Combat.validateCharge(if type(claimedCharge) == "number" then claimedCharge else 0, held, Config)
	local speed = Combat.throwSpeed(charge, Config)
	local origin = releasePoint(root.Parent :: Model, root)
	local ok, vx, vy, vz = Combat.aimVelocity(origin.X, origin.Y, origin.Z, aimX, aimY, aimZ, speed, Config)
	if not ok or not Combat.tryThrow(state.ammo, time, Config) then
		return
	end
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
		t0 = time,
		lastT = 0,
		speed = speed,
		charge = charge,
	})
	Remotes.IceBallThrown:FireAllClients(nextId, player, origin, Vector3.new(vx, vy, vz), time)
end

local function resolve(ball: Ball, victim: Player?, position: Vector3, power: number, knockdown: boolean)
	local flat = Vector3.new(ball.vx, 0, ball.vz)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
	Remotes.IceBallResolved:FireAllClients(ball.id, ball.thrower, victim, position, flat.X, flat.Z, power, knockdown)
end

local function hitPlayer(ball: Ball, victim: Player, position: Vector3, distance: number, speed: number)
	local state = states[victim]
	local time = now()
	local power = Combat.hitPower(distance, speed, ball.speed, ball.charge, Config)
	local knockdown = false
	if state then
		state.stagger, knockdown = Combat.addHit(state.stagger, state.lastHitAt, time, power, Config)
		state.lastHitAt = time
		if knockdown then
			state.downUntil = time + Config.knockdownTime
			state.chargeStartedAt = nil -- a knockdown drops the charge; a new press starts a new one
		end
	end
	resolve(ball, victim, position, power, knockdown)
end

-- Moves every ball from its last checked time to now and resolves the first thing it touches: a player capsule
-- or the world. Players knocked down are not targets until they are up again, and nobody hits themselves.
local function step()
	local time = now()
	local raycast = RaycastParams.new()
	raycast.FilterType = Enum.RaycastFilterType.Exclude
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	raycast.FilterDescendantsInstances = characters

	for index = #balls, 1, -1 do
		local ball = balls[index]
		local t = math.min(time - ball.t0, Config.maxFlight)
		local ax, ay, az =
			Combat.position(ball.ox, ball.oy, ball.oz, ball.vx, ball.vy, ball.vz, Config.gravity, ball.lastT)
		local bx, by, bz = Combat.position(ball.ox, ball.oy, ball.oz, ball.vx, ball.vy, ball.vz, Config.gravity, t)
		local from, to = Vector3.new(ax, ay, az), Vector3.new(bx, by, bz)

		local bestS, bestVictim, bestDistance = math.huge, nil :: Player?, 0
		for _, player in Players:GetPlayers() do
			local victimState = states[player]
			local root = rootOf(player)
			if player ~= ball.thrower and root and not (victimState and time < victimState.downUntil) then
				local p = root.Position
				local distance, s = Combat.closestToCapsule(ax, ay, az, bx, by, bz, p.X, p.Y, p.Z, Config.hitHalfHeight)
				if distance <= Config.hitRadius + Config.ballRadius and s < bestS then
					bestS, bestVictim, bestDistance = s, player, distance
				end
			end
		end

		local worldHit = workspace:Raycast(from, to - from, raycast)
		local worldS = if worldHit
			then (worldHit.Position - from).Magnitude / math.max((to - from).Magnitude, 1e-6)
			else math.huge

		local resolved = true
		if bestVictim and bestS <= worldS then
			local hitT = ball.lastT + (t - ball.lastT) * bestS
			local speed = Vector3.new(ball.vx, ball.vy - Config.gravity * hitT, ball.vz).Magnitude
			hitPlayer(ball, bestVictim, from:Lerp(to, bestS), bestDistance, speed)
		elseif worldHit then
			resolve(ball, nil, worldHit.Position, 0, false)
		elseif t >= Config.maxFlight then
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
		}
		states[player] = state
		publishAmmo(player, state)
		-- a respawn keeps the ammo but never a charge from the old character
		player.CharacterAdded:Connect(function()
			state.chargeStartedAt = nil
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	Remotes.ChargeIceBall.OnServerEvent:Connect(onCharge)
	Remotes.ThrowIceBall.OnServerEvent:Connect(onThrow)
	RunService.Heartbeat:Connect(step)
end

return CombatService
