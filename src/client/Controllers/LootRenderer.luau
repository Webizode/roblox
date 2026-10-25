-- Draws the free spilled scoops the server announces (LootService) and picks one up when the local player walks
-- over it: the claim goes to the server, which decides. A scoop reserved for its owner glows in the owner's colour,
-- one about to disappear blinks. Also draws the local player's safe zone around the own cart.
--
-- Kept cheap for phones: one anchored part per scoop plus one ring while it is reserved, no collisions, shadows,
-- lights or particles, and a part is only moved while it falls, rolls or flies to a tower.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Loot = require(Shared:WaitForChild("Loot"))
local LootConfig = require(Config:WaitForChild("Loot"))
local Palette = require(Config:WaitForChild("Palette"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))

local LootRenderer = {}

type Wire = {
	id: number,
	flavorId: string,
	owner: number,
	base: Vector3,
	groundY: number,
	start: Vector3,
	land: Vector3,
	roll: Vector3,
	t0: number,
	ownerUntil: number,
	endAt: number,
	sinks: boolean,
}

type Drawn = {
	wire: Wire,
	path: Loot.Path,
	rule: Loot.Scoop,
	part: Part,
	ring: Part?,
	settled: boolean, -- done rolling, the part no longer moves
	claimedAt: number?, -- os.clock of the claim; the scoop flies to the own tower until the server answers
	retryAt: number, -- os.clock; after a refused claim, not again before this
	blinking: boolean,
}

local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X
local SETTLE = 1.2 -- seconds after landing the roll is drawn; it is all but over by then
local CLAIM_WAIT = 1 -- seconds a claim may go unanswered before the scoop drops back
local RETRY = 0.5
local FLY_RESPONSE = 18 -- 1/s, a claimed scoop closing in on the tower top
local ZONE_ALPHA = 0.85
local ZONE_OFF_ALPHA = 0.95

local player = Players.LocalPlayer
local registry
local drawn: { [number]: Drawn } = {}
local zone: Part?
local zoneCart: string?

local function makePart(): Part
	local part = TowerVisual.makePart(TowerVisual.root())
	part.CastShadow = false
	return part
end

local function ownerColor(userId: number): Color3?
	local owner = Players:GetPlayerByUserId(userId)
	local hex = owner and owner:GetAttribute("PlayerColor")
	return if type(hex) == "string" then Color3.fromHex(hex) else nil
end

-- World position of the scoop's centre at `elapsed` seconds after the topple. Loot.position's height is the share
-- of the way down from the tower; here it ends on the ground under the landing point.
local function worldPosition(scoop: Drawn, elapsed: number): Vector3
	local wire, path = scoop.wire, scoop.path
	local x, y, z = Loot.position(path, elapsed, LootConfig)
	local restY = wire.groundY + LootConfig.scoopRadius
	local fall = if path.sy > 1e-3 then y / path.sy else 0
	local startY = wire.base.Y + path.sy
	return Vector3.new(wire.base.X + x, restY + (startY - restY) * fall, wire.base.Z + z)
end

local function updateRing(scoop: Drawn, now: number)
	local reserved = now < scoop.rule.ownerUntil
	if reserved and not scoop.ring then
		local ring = makePart()
		ring.Name = "LootGlow"
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.35
		ring.Size = Vector3.new(0.15, LootConfig.ringSize, LootConfig.ringSize)
		ring.Color = ownerColor(scoop.wire.owner) or Color3.fromHex(Palette.lemon)
		scoop.ring = ring
	elseif not reserved and scoop.ring then
		scoop.ring:Destroy()
		scoop.ring = nil
	end
	if scoop.ring then
		local position = scoop.part.Position
		scoop.ring.CFrame = CFrame.new(position.X, scoop.wire.groundY + 0.1, position.Z) * FLAT
	end
end

local function add(wire: Wire)
	if drawn[wire.id] then
		return
	end
	local part = makePart()
	part.Name = "FreeScoop"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * LootConfig.scoopRadius * 2
	TowerVisual.applyFlavor(part, wire.flavorId)
	local scoop: Drawn = {
		wire = wire,
		path = {
			flavorId = wire.flavorId,
			sx = wire.start.X,
			sy = wire.start.Y,
			sz = wire.start.Z,
			lx = wire.land.X,
			lz = wire.land.Z,
			rx = wire.roll.X,
			rz = wire.roll.Z,
		},
		rule = {
			owner = wire.owner,
			landedAt = wire.t0 + LootConfig.fallTime,
			ownerUntil = wire.ownerUntil,
			expiresAt = wire.endAt,
		},
		part = part,
		ring = nil,
		settled = false,
		claimedAt = nil,
		retryAt = 0,
		blinking = false,
	}
	part.CFrame = CFrame.new(worldPosition(scoop, workspace:GetServerTimeNow() - wire.t0))
	drawn[wire.id] = scoop
end

local function drop(scoop: Drawn)
	drawn[scoop.wire.id] = nil
	if scoop.ring then
		scoop.ring:Destroy()
	end
end

-- Shrinks a part away and destroys it.
local function vanish(part: BasePart, seconds: number)
	TweenService:Create(part, TweenInfo.new(seconds), { Size = Vector3.one * 0.2, Transparency = 1 }):Play()
	task.delay(seconds, function()
		part:Destroy()
	end)
end

local function splash(position: Vector3)
	local puddle = makePart()
	puddle.Shape = Enum.PartType.Cylinder
	puddle.Material = Enum.Material.Neon
	puddle.Color = Color3.fromHex(Palette.skyTop)
	puddle.Transparency = 0.3
	puddle.Size = Vector3.new(0.15, 1.5, 1.5)
	puddle.CFrame = CFrame.new(position) * FLAT
	TweenService:Create(puddle, TweenInfo.new(0.5), { Size = Vector3.new(0.15, 4, 4), Transparency = 1 }):Play()
	task.delay(0.5, function()
		puddle:Destroy()
	end)
end

local function onSpawned(list: { Wire })
	local own = false
	for _, wire in list do
		add(wire)
		own = own or wire.owner == player.UserId
	end
	if own then
		registry.TowerController.clearSpill() -- the free scoops take over from the stand-ins on the tower's spot
	end
end

local function onUpdated(ids: { number }, ownerUntil: number)
	for _, id in ids do
		local scoop = drawn[id]
		if scoop then
			scoop.rule.ownerUntil = ownerUntil
		end
	end
end

local function onRemoved(id: number, catcher: Player?, reason: string)
	local scoop = drawn[id]
	if not scoop then
		return
	end
	drop(scoop)
	local part = scoop.part
	if catcher == player then
		part:Destroy() -- it is on the own tower now (TowerChanged)
	elseif catcher then
		-- someone else got it: it hops towards them and is gone
		local root = catcher.Character and catcher.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			TweenService:Create(part, TweenInfo.new(0.2), { Position = root.Position + Vector3.new(0, 2, 0) }):Play()
		end
		vanish(part, 0.2)
	elseif reason == "water" then
		splash(Vector3.new(part.Position.X, scoop.wire.groundY - 2, part.Position.Z))
		part:Destroy()
	else
		vanish(part, 0.25)
	end
end

local function onRejected(id: number)
	local scoop = drawn[id]
	if scoop then
		scoop.claimedAt = nil
		scoop.retryAt = os.clock() + RETRY
		scoop.settled = false -- back to where it lies
	end
end

-- The local player walks over a scoop they may take: claim it and let it fly to the tower.
local function tryClaim(scoop: Drawn, now: number, root: BasePart, humanoid: Humanoid)
	if scoop.claimedAt or os.clock() < scoop.retryAt then
		return
	end
	if not Loot.canCollect(scoop.rule, player.UserId, now) then
		return
	end
	local position = scoop.part.Position
	local feet = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	local dx, dy, dz = root.Position.X - position.X, feet - scoop.wire.groundY, root.Position.Z - position.Z
	if Loot.inReach(dx, dy, dz, 0, false, LootConfig) then
		scoop.claimedAt = os.clock()
		Remotes.LootClaim:FireServer(scoop.wire.id)
	end
end

-- The safe zone around the own cart: a faint disc, fainter while a throw from it has lifted the protection.
local function updateZone(now: number)
	local cartName = player:GetAttribute("CartName")
	if cartName ~= zoneCart or not zone then
		if zone then
			zone:Destroy()
			zone = nil
		end
		-- the cart is only remembered once its disc stands: the pier may not have arrived yet
		zoneCart = nil
		local pier = workspace:FindFirstChild("Pier")
		local carts = pier and pier:FindFirstChild("Carts")
		local cart = carts and type(cartName) == "string" and carts:FindFirstChild(cartName)
		local servePoint = cart and cart:FindFirstChild("ServePoint") :: BasePart?
		if servePoint then
			zoneCart = cartName
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { cart, TowerVisual.root() }
			local hit = workspace:Raycast(servePoint.Position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
			local y = if hit then hit.Position.Y else servePoint.Position.Y
			local disc = makePart()
			disc.Name = "SafeZone"
			disc.Shape = Enum.PartType.Cylinder
			disc.Material = Enum.Material.Neon
			disc.Color = Color3.fromHex(Palette.mint)
			disc.Size = Vector3.new(0.1, LootConfig.safeRadius * 2, LootConfig.safeRadius * 2)
			disc.CFrame = CFrame.new(servePoint.Position.X, y + 0.06, servePoint.Position.Z) * FLAT
			zone = disc
		end
	end
	if zone then
		local unshieldedUntil = player:GetAttribute("UnshieldedUntil")
		local off = type(unshieldedUntil) == "number" and now < unshieldedUntil
		zone.Transparency = if off then ZONE_OFF_ALPHA else ZONE_ALPHA
	end
end

local function onRenderStep(dt: number)
	local now = workspace:GetServerTimeNow()
	updateZone(now)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local canTake = root ~= nil and humanoid ~= nil and humanoid.Health > 0 and registry.TowerController.canTake()
	local top = registry.TowerController.topPosition()

	for _, scoop in drawn do
		local elapsed = now - scoop.wire.t0
		if scoop.claimedAt then
			if os.clock() - scoop.claimedAt > CLAIM_WAIT then
				onRejected(scoop.wire.id) -- no answer: it lies where it was
			elseif top then
				local blend = 1 - math.exp(-FLY_RESPONSE * dt)
				scoop.part.CFrame = CFrame.new(scoop.part.Position:Lerp(top, blend))
			end
		elseif not scoop.settled then
			scoop.part.CFrame = CFrame.new(worldPosition(scoop, elapsed))
			scoop.settled = elapsed > LootConfig.fallTime + SETTLE
		end

		local blinking = not scoop.wire.sinks and now > scoop.wire.endAt - LootConfig.blinkSeconds
		if blinking then
			scoop.part.Transparency = if math.floor(now * 8) % 2 == 0 then 0.65 else 0
		elseif scoop.blinking then
			scoop.part.Transparency = 0
		end
		scoop.blinking = blinking
		updateRing(scoop, now)

		if canTake and root and humanoid then
			tryClaim(scoop, now, root, humanoid)
		end
	end
end

-- A throw from the own safe zone lifts its protection: say so once.
local function onUnshielded()
	local unshieldedUntil = player:GetAttribute("UnshieldedUntil")
	if type(unshieldedUntil) == "number" and unshieldedUntil > workspace:GetServerTimeNow() then
		registry.Hud.toast(string.format("NOT SAFE FOR %d s", LootConfig.unshieldSeconds), Palette.awning)
	end
end

function LootRenderer.Init(reg)
	registry = reg
end

function LootRenderer.Start()
	Remotes.LootSpawned.OnClientEvent:Connect(onSpawned)
	Remotes.LootUpdated.OnClientEvent:Connect(onUpdated)
	Remotes.LootRemoved.OnClientEvent:Connect(onRemoved)
	Remotes.LootRejected.OnClientEvent:Connect(onRejected)
	player:GetAttributeChangedSignal("UnshieldedUntil"):Connect(onUnshielded)
	-- after TowerController, like ShotRenderer, so the root and the tower top are this frame's
	RunService:BindToRenderStep("WobbleLoot", registry.TowerController.RENDER_PRIORITY + 2, onRenderStep)
end

return LootRenderer
