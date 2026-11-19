-- The gummy bounce pads in the arena (Config/Bounce): every Model in the cover folder named GummyPad* or GummyBouncer*.
-- The client throws its player up the moment it steps on one (Controllers/BounceController) and reports it here. This
-- checks it roughly (Bounce.check: alive, in the arena, at the pad, not too soon after the last one). A bounce that
-- holds is shown to everybody else (the pad squashes, puff and boing); one that does not puts the player back on the
-- ground under them, so a client cannot fly by reporting bounces it never had.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Bounce = require(Shared:WaitForChild("Bounce"))
local BounceConfig = require(Config:WaitForChild("Bounce"))
local MapConfig = require(Config:WaitForChild("Map"))

local BounceService = {}

type Pad = { kind: string, centre: Vector3, radius: number, tall: number }

local registry
local pads: { [Model]: Pad } = {}
local lastAt: { [Player]: number } = {}
local refused: { [Player]: number } = {} -- count, for the log

-- The pads of the map, with their middle, radius and top worked out once (they never move).
local function findPads()
	local map = workspace:FindFirstChild(MapConfig.root)
	local cover = map and map:FindFirstChild(MapConfig.coverFolder)
	if not cover then
		return
	end
	for _, item in cover:GetDescendants() do
		if item:IsA("Model") then
			local kind = Bounce.kindOf(item.Name, BounceConfig)
			if kind then
				local box, size = item:GetBoundingBox()
				pads[item] = {
					kind = kind,
					centre = item:GetPivot().Position,
					radius = math.max(size.X, size.Z) / 2,
					tall = box.Position.Y + size.Y / 2 - item:GetPivot().Position.Y,
				}
			end
		end
	end
end

local function putBack(player: Player, root: BasePart, why: string)
	local character = player.Character
	if not character then
		return
	end
	local position = root.Position
	local ground = registry.MapService.groundAt(position.X, position.Y, position.Z, 300)
	if ground.y then
		local feet = root.Size.Y / 2
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			feet += humanoid.HipHeight
		end
		character:PivotTo(CFrame.new(position.X, ground.y + feet, position.Z) * root.CFrame.Rotation)
	end
	root.AssemblyLinearVelocity = Vector3.zero
	refused[player] = (refused[player] or 0) + 1
	warn(`[Bounce] refused {player.Name} ({why}), {refused[player]} so far; put back on the ground`)
end

local function onBounce(player: Player, model: unknown)
	if typeof(model) ~= "Instance" or not (model :: Instance):IsA("Model") then
		return
	end
	local pad = pads[model :: Model]
	if not pad then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local offset = root.Position - pad.centre
	local now = os.clock()
	local ok, why = Bounce.check({
		now = now,
		lastAt = lastAt[player],
		alive = humanoid.Health > 0,
		inArena = registry.ArenaService.inArena(player, BounceConfig.server.arenaSlack),
		distance = Vector3.new(offset.X, 0, offset.Z).Magnitude,
		radius = pad.radius,
		height = root.Position.Y - pad.centre.Y,
		tall = pad.tall,
	}, BounceConfig)
	if not ok then
		putBack(player, root, why or "?")
		return
	end
	lastAt[player] = now
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Remotes.Bounce:FireClient(other, player, model)
		end
	end
end

function BounceService.Init(reg)
	registry = reg
end

function BounceService.Start()
	findPads()
	local count = 0
	for _ in pads do
		count += 1
	end
	print(`[Bounce] {count} gummy pads in the arena`)
	Remotes.Bounce.OnServerEvent:Connect(onBounce)
	Players.PlayerRemoving:Connect(function(player)
		lastAt[player] = nil
		refused[player] = nil
	end)
end

-- for checks: how often a player's bounce was refused
function BounceService.refusedCount(player: Player): number
	return refused[player] or 0
end

return BounceService
