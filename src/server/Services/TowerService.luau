-- The server's truth about every tower: which scoops are on it, coins, and what a serve pays.
-- Tilt is simulated by the owning client; the server only relays it and uses it to locate the tower top.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Economy = require(Shared:WaitForChild("Economy"))
local Recipes = require(Shared:WaitForChild("Recipes"))
local TowerShape = require(Shared:WaitForChild("TowerShape"))
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
	variant: string,
	carryStartedAt: number?,
	tiltX: number,
	tiltZ: number,
	lastServeAt: number,
	lastToppleAt: number,
	joinedAt: number,
	leaderstats: { coins: IntValue, best: IntValue },
}

local registry
local states: { [Player]: TowerState } = {}

local MAX_TILT_MESSAGE = TowerTuning.tipAngle * 1.1

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

local function publish(player: Player, state: TowerState, reason: string)
	local count = #state.scoops
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = Economy.walkSpeed(count, state.sneakersLevel, EconomyConfig)
	end
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
		variant = TowerTuning.defaultVariant,
		carryStartedAt = nil,
		tiltX = 0,
		tiltZ = 0,
		lastServeAt = 0,
		lastToppleAt = 0,
		joinedAt = now(),
		leaderstats = { coins = coins, best = best },
	}
	player:SetAttribute("ControlVariant", state.variant)
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

	registry.KillTestLog.topple(player, state.variant, count, "self")
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

	registry.KillTestLog.serve(player, state.variant, count, value, carrySeconds, time - state.joinedAt)
	publish(player, state, "serve")
	Remotes.Served:FireAllClients(player, count, math.floor(value), steady)
end

local function onTilt(player: Player, x: any, z: any)
	local state = states[player]
	if not state or not isFiniteNumber(x) or not isFiniteNumber(z) then
		return
	end
	state.tiltX = math.clamp(x, -MAX_TILT_MESSAGE, MAX_TILT_MESSAGE)
	state.tiltZ = math.clamp(z, -MAX_TILT_MESSAGE, MAX_TILT_MESSAGE)
	-- clients ignore their own tilt
	Remotes.TowerTilt:FireAllClients(player, state.tiltX, state.tiltZ)
end

local function onVariant(player: Player, variant: any)
	local state = states[player]
	if not Features.variantSwitcher or not state or type(variant) ~= "string" then
		return
	end
	if not TowerTuning.variants[variant] or variant == state.variant then
		return
	end
	state.variant = variant
	player:SetAttribute("ControlVariant", variant)
	registry.KillTestLog.variant(player, variant)
end

function TowerService.Init(reg)
	registry = reg
end

function TowerService.Start()
	local function onPlayer(player: Player)
		local state = createState(player)
		states[player] = state
		registry.KillTestLog.join(player, state.variant)
		player.CharacterAdded:Connect(function()
			-- a new character starts with an empty cone
			table.clear(state.scoops)
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
	Remotes.SetVariant.OnServerEvent:Connect(onVariant)
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

-- World position of the free slot on top of the player's tower, from the last tilt the client reported.
function TowerService.topPosition(player: Player): Vector3?
	local state = states[player]
	local root = rootOf(player)
	if not state or not root then
		return nil
	end
	local base = root.CFrame:PointToWorldSpace(Vector3.new(0, TowerTuning.holdUp, -TowerTuning.holdForward))
	local ox, oy, oz = TowerShape.top(#state.scoops, state.tiltX, state.tiltZ, TowerTuning)
	return base + Vector3.new(ox, oy, oz)
end

return TowerService
