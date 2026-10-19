-- The server's truth about every tower: which scoops are on it, coins, and what a serve pays.
-- Tilt is simulated by the owning client; the server only relays it to the other players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Economy = require(Shared:WaitForChild("Economy"))
local TowerModel = require(Shared:WaitForChild("TowerModel"))
local Recipes = require(Shared:WaitForChild("Recipes"))
local Flavors = require(Config:WaitForChild("Flavors"))
local EconomyConfig = require(Config:WaitForChild("Economy"))
local RecipeConfig = require(Config:WaitForChild("Recipes"))
local TowerTuning = require(Config:WaitForChild("Tower"))
local Features = require(Config:WaitForChild("Features"))

local TowerService = {}

type TowerState = {
	scoops: { string },
	coins: number,
	best: number,
	coneLevel: number,
	sneakersLevel: number,
	cartLevel: number,
	controls: string, -- kill-test log bucket; one control scheme since the automatic stabiliser
	lastDashAt: number,
	lastRescueAt: number,
	sprinting: boolean,
	lastSprintAt: number,
	carryStartedAt: number?,
	tiltX: number,
	tiltZ: number,
	lastTiltAt: number,
	lastServeAt: number,
	lastToppleAt: number,
	joinedAt: number,
	leaderstats: { coins: IntValue, best: IntValue },
}

local registry
local states: { [Player]: TowerState } = {}

-- honest clients send tilt at Tuning.tiltSendRate (10 Hz); anything faster than twice that is dropped
local MIN_TILT_INTERVAL = 0.5 / TowerTuning.tiltSendRate
-- the client starts its own cooldown when it asks, so the server allows a little network jitter on top
local DASH_SLACK = 0.25
local RESCUE_SLACK = 0.25
-- no human taps Shift faster than this; a quicker "on" is dropped
local SPRINT_INTERVAL = 0.08

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The server owns WalkSpeed: tower height, sneakers and sprint. The catch check reads it, so a sprinting
-- player's catches are judged at their real speed.
local function applyWalkSpeed(player: Player, state: TowerState)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = Economy.walkSpeed(#state.scoops, state.sneakersLevel, EconomyConfig, state.sprinting)
	end
end

local function publish(player: Player, state: TowerState, reason: string)
	applyWalkSpeed(player, state)
	if player.Character then
		player.Character:SetAttribute("TowerFlavors", table.concat(state.scoops, ","))
	end
	state.leaderstats.coins.Value = math.floor(state.coins)
	state.leaderstats.best.Value = state.best
	Remotes.TowerChanged:FireClient(player, table.clone(state.scoops), reason)
end

local function createState(player: Player): TowerState
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = folder
	local best = Instance.new("IntValue")
	best.Name = "Best"
	best.Parent = folder
	folder.Parent = player

	local state: TowerState = {
		scoops = {},
		coins = 0,
		best = 0,
		coneLevel = 0,
		sneakersLevel = 0,
		cartLevel = 0,
		controls = "auto",
		lastDashAt = 0,
		lastRescueAt = 0,
		sprinting = false,
		lastSprintAt = 0,
		carryStartedAt = nil,
		tiltX = 0,
		tiltZ = 0,
		lastTiltAt = 0,
		lastServeAt = 0,
		lastToppleAt = 0,
		joinedAt = now(),
		leaderstats = { coins = coins, best = best },
	}
	player:SetAttribute("ConeLevel", state.coneLevel)
	return state
end

local function onToppled(player: Player)
	local state = states[player]
	local count = state and #state.scoops or 0
	if not state or count == 0 or now() - state.lastToppleAt < 0.3 then
		return
	end
	state.lastToppleAt = now()

	local keep = Economy.keepOnTopple(count, EconomyConfig)
	for index = count, keep + 1, -1 do
		state.scoops[index] = nil
	end
	state.tiltX, state.tiltZ = 0, 0
	state.carryStartedAt = if keep > 0 then now() else nil

	registry.KillTestLog.topple(player, state.controls, count, "self")
	publish(player, state, "topple")
end

local function onServe(player: Player, steadyClaim: any)
	local state = states[player]
	if not state or #state.scoops == 0 then
		return
	end
	local time = now()
	if time - state.lastServeAt < EconomyConfig.serveCooldown then
		return
	end

	local root = rootOf(player)
	local servePoint = registry.CartService.servePoint(player)
	if not root or not servePoint then
		return
	end
	if (root.Position - servePoint).Magnitude > EconomyConfig.serveRadius + 4 then
		return
	end
	state.lastServeAt = time

	-- the client simulates steadiness, so its claim is capped by how long the tower was actually carried
	local carrySeconds = if state.carryStartedAt then time - state.carryStartedAt else 0
	local steadyCap = math.min(TowerTuning.steady.max, carrySeconds * TowerTuning.steady.ratePerSecond)
	local steady = if isFiniteNumber(steadyClaim) then math.clamp(steadyClaim, 0, steadyCap) else 0

	local stacks = if Features.secretStacks then Recipes.findStacks(state.scoops, RecipeConfig.secretStacks) else nil
	local count = #state.scoops
	local value = Economy.serveValue(state.scoops, Flavors.byId, EconomyConfig, {
		steadyBonus = steady,
		serveMultiplier = Economy.serveMultiplier(state.cartLevel, EconomyConfig),
		stacks = stacks,
	})

	state.coins += value
	state.best = math.max(state.best, count)
	table.clear(state.scoops)
	state.carryStartedAt = nil
	state.tiltX, state.tiltZ = 0, 0

	registry.KillTestLog.serve(player, state.controls, count, value, carrySeconds, time - state.joinedAt)
	publish(player, state, "serve")
	Remotes.Served:FireAllClients(player, count, math.floor(value), steady)
end

local function onTilt(player: Player, x: any, z: any)
	local state = states[player]
	if not state or not isFiniteNumber(x) or not isFiniteNumber(z) then
		return
	end
	local time = now()
	if time - state.lastTiltAt < MIN_TILT_INTERVAL then
		return
	end
	state.lastTiltAt = time

	-- clamp the tilt vector, not each axis: per axis a diagonal tilt could reach 1.4x the tip angle
	local tilt = math.sqrt(x * x + z * z)
	if tilt > TowerTuning.tipAngle then
		x, z = x / tilt * TowerTuning.tipAngle, z / tilt * TowerTuning.tipAngle
	end
	state.tiltX, state.tiltZ = x, z
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Remotes.TowerTilt:FireClient(other, player, x, z)
		end
	end
end

-- A dash only moves the asker's own character and shakes their own tower; it pays nothing. The server decides
-- whether it may happen (cooldown, alive, not seated) and tells every client, which plays the burst and effect.
local function onDash(player: Player, dirX: any, dirZ: any)
	local state = states[player]
	if not state or not isFiniteNumber(dirX) or not isFiniteNumber(dirZ) then
		return
	end
	local length = math.sqrt(dirX * dirX + dirZ * dirZ)
	if length < 0.5 or length > 1.5 then
		return
	end
	local time = now()
	if time - state.lastDashAt < TowerTuning.dash.cooldown - DASH_SLACK then
		return
	end
	local humanoid = humanoidOf(player)
	if not humanoid or humanoid.Health <= 0 or humanoid.Sit then
		return
	end
	state.lastDashAt = time
	Remotes.Dash:FireAllClients(player, dirX / length, dirZ / length)
end

-- Sprint on or off. Only changes the player's own speed, within sprintMultiplier. Switching on is rate-limited;
-- switching off always goes through, so a dropped release can never leave a player stuck sprinting.
local function onSprint(player: Player, sprinting: any)
	local state = states[player]
	if not state or type(sprinting) ~= "boolean" or sprinting == state.sprinting then
		return
	end
	local now = os.clock()
	if sprinting and now - state.lastSprintAt < SPRINT_INTERVAL then
		return
	end
	state.lastSprintAt = now
	state.sprinting = sprinting
	applyWalkSpeed(player, state)
end

-- The rescue (F / Steady button) only strengthens the asker's own stabiliser for a moment and pays nothing. The
-- server owns its timing: a new one only after the last one plus its cooldown, and only while carrying a tower.
local function onRescue(player: Player)
	local state = states[player]
	if not state or #state.scoops == 0 then
		return
	end
	local time = now()
	if not TowerModel.rescueReady(state.lastRescueAt, time, TowerTuning.rescue, RESCUE_SLACK) then
		return
	end
	local humanoid = humanoidOf(player)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	state.lastRescueAt = time
	Remotes.Rescue:FireAllClients(player)
end

function TowerService.Init(reg)
	registry = reg
end

function TowerService.Start()
	local function onPlayer(player: Player)
		local state = createState(player)
		states[player] = state
		registry.KillTestLog.join(player)
		player.CharacterAdded:Connect(function()
			-- a new character starts with an empty cone
			table.clear(state.scoops)
			state.sprinting = false
			state.carryStartedAt = nil
			state.tiltX, state.tiltZ = 0, 0
			task.defer(publish, player, state, "spawn")
		end)
		if player.Character then
			task.defer(publish, player, state, "spawn")
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		registry.KillTestLog.leave(player)
		states[player] = nil
	end)

	Remotes.TowerToppled.OnServerEvent:Connect(onToppled)
	Remotes.ServeRequest.OnServerEvent:Connect(onServe)
	Remotes.TowerTilt.OnServerEvent:Connect(onTilt)
	Remotes.Rescue.OnServerEvent:Connect(onRescue)
	Remotes.SetSprint.OnServerEvent:Connect(onSprint)
	Remotes.Dash.OnServerEvent:Connect(onDash)
end

function TowerService.count(player: Player): number
	local state = states[player]
	return state and #state.scoops or 0
end

-- Adds a caught scoop. Returns false when the cone is full or the player has no state.
function TowerService.addScoop(player: Player, flavorId: string): boolean
	local state = states[player]
	if not state or #state.scoops >= Economy.capacity(state.coneLevel, EconomyConfig) then
		return false
	end
	if #state.scoops == 0 then
		state.carryStartedAt = now()
	end
	table.insert(state.scoops, flavorId)
	publish(player, state, "catch")
	return true
end

-- World position of the catch column's base, the same point the client checks catches from (catchUp and
-- catchForward; the visible tower on the back is only drawn by the clients).
function TowerService.towerBase(player: Player): Vector3?
	local root = rootOf(player)
	if not states[player] or not root then
		return nil
	end
	return root.CFrame:PointToWorldSpace(Vector3.new(0, TowerTuning.catchUp, -TowerTuning.catchForward))
end

return TowerService
