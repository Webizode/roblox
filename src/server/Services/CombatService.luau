-- Ice-ball throws, the only normal attack. The server owns everything that matters: ammo and reload, where a
-- ball starts and how it flies (simulated here every frame), what it hits, the hit power, the knockdown decision
-- and who may be hit. Clients only draw the ball and play the reaction the server announces; the victim's client
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
}

-- the ball leaves a little in front of the chest so it does not start inside the thrower
local RELEASE_UP = 1.5
local RELEASE_FORWARD = 2

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

local function onThrow(player: Player, aimX: any, aimY: any, aimZ: any)
	local state = states[player]
	if not state or type(aimX) ~= "number" or type(aimY) ~= "number" or type(aimZ) ~= "number" then
		return
	end
	local ok, vx, vy, vz = Combat.launchVelocity(aimX, aimY, aimZ, Config)
	local root = rootOf(player)
	local time = now()
	if not ok or not root or time < state.downUntil then
		return
	end
	if not Combat.tryThrow(state.ammo, time, Config) then
		return
	end
	publishAmmo(player, state)
	if state.ammo.count == 0 then
		scheduleRefill(player, state)
	end

	local flat = Vector3.new(vx, 0, vz)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
	local origin = root.Position + Vector3.new(0, RELEASE_UP, 0) + flat * RELEASE_FORWARD
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
	local power = Combat.hitPower(distance, speed, Config)
	local knockdown = false
	if state then
		state.stagger, knockdown = Combat.addHit(state.stagger, state.lastHitAt, time, power, Config)
		state.lastHitAt = time
		if knockdown then
			state.downUntil = time + Config.knockdownTime
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
		}
		states[player] = state
		publishAmmo(player, state)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	Remotes.ThrowIceBall.OnServerEvent:Connect(onThrow)
	RunService.Heartbeat:Connect(step)
end

return CombatService
