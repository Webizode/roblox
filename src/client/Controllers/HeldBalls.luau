-- The ball floating above the open right palm of every player in combat mode (ThrowAnimator raises the hand to
-- present it): the next ball they can throw. It is the
-- vanilla ball (BallVisual), bobbing and swaying gently (BallMotion.idle). A throw makes the next one pop in with a
-- quick turn (BallMotion.nextThrow); with the load empty a see-through frost ball grows there until the reload ends.
-- Every client draws it for every player from the CombatMode, IceBalls and IceBallsReadyAt attributes the server sets
-- (Combat.ammoDisplay turns the ammo into what to show). Client-only, anchored, non-colliding, like the towers;
-- nothing here touches gameplay. The thrown ball itself starts at the server's release point, the same hand.
-- Charging lights it up for everyone (ChargeStartedAt, Combat.chargeGlow): a glowing shell that grows with the
-- strength and flares green while letting go would be perfect, with the charge-up and perfect sounds for players nearby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Combat = require(Shared:WaitForChild("Combat"))
local BallMotion = require(Shared:WaitForChild("BallMotion"))
local CombatConfig = require(Config:WaitForChild("Combat"))
local Palette = require(Config:WaitForChild("Palette"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))
local BallVisual = require(client:WaitForChild("BallVisual"))
local Sfx = require(client:WaitForChild("Sfx"))

local HeldBalls = {}

type Held = {
	part: Part, -- the plain ice ball: the frost while refilling, and the loaded ball when there is no model
	model: Model?, -- the vanilla ball, drawn while a ball is loaded
	frost: BallVisual.Frost?, -- its sparkles and glow, on while it shows
	count: number?, -- loaded balls last frame; nil until the first reading, which shows without a pop
	loaded: boolean,
	changedAt: number, -- os.clock() the last pop in or out started
	spinAt: number, -- os.clock() the last ball popped in; it turns once from there
	from: number, -- scale and transparency when it changed, so a pop starts from what was on screen
	fromTransparency: number,
	scale: number,
	transparency: number,
	size: number, -- last size written to the part
	modelSize: number, -- and to the model
	shown: boolean,
	glow: Part, -- the charge glow: a see-through neon shell with a light, around the ball while charging
	chargeStart: number?, -- the ChargeStartedAt last frame, to hear a new charge start
	chargePerfect: boolean, -- letting go would be perfect last frame, to hear each perfect moment once
}

local STEP = "WobbleHeldBalls"
local HIDDEN_SCALE = 0.02
local Look = CombatConfig.held
local DIAMETER = CombatConfig.ballRadius * 2 -- the same ball that flies
local Charge = Look.charge
local ICE = Color3.fromHex(Palette.skyTop)
local PERFECT = Color3.fromHex(CombatConfig.crosshair.perfectColor)
local GLOW_SIZE = 1.5 -- the shell, times the ball

local localPlayer = Players.LocalPlayer
local held: { [Player]: Held } = {}

local function newHeld(player: Player): Held
	local part = TowerVisual.makePart(TowerVisual.root())
	part.Name = "HeldBall_" .. player.UserId
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Ice
	part.Color = Color3.fromHex(Palette.skyTop)
	part.Parent = nil
	local model = BallVisual.new("HeldBall_" .. player.UserId, DIAMETER)
	local glow = TowerVisual.makePart(TowerVisual.root())
	glow.Name = "ChargeGlow_" .. player.UserId
	glow.Shape = Enum.PartType.Ball
	glow.Material = Enum.Material.Neon
	glow.CastShadow = false
	glow.Size = Vector3.one * DIAMETER * GLOW_SIZE
	local light = Instance.new("PointLight")
	light.Shadows = false
	light.Parent = glow
	glow.Parent = nil
	return {
		part = part,
		model = model,
		frost = if model then BallVisual.addFrost(model) else nil,
		count = nil,
		loaded = true,
		changedAt = -math.huge,
		spinAt = -math.huge,
		from = 0,
		fromTransparency = 0,
		scale = 1,
		transparency = 0,
		size = -1,
		modelSize = DIAMETER,
		shown = false,
		glow = glow,
		chargeStart = nil,
		chargePerfect = false,
	}
end

local function place(instance: Instance, on: boolean)
	local parent = if on then TowerVisual.root() else nil
	if instance.Parent ~= parent then
		instance.Parent = parent
	end
end

local function show(entry: Held, on: boolean)
	if entry.shown ~= on then
		entry.shown = on
		if not on then
			place(entry.part, false)
			place(entry.glow, false)
			if entry.model then
				place(entry.model, false)
			end
			if entry.frost then
				BallVisual.setFrost(entry.frost, false)
			end
			entry.count = nil -- what changed while hidden shows as it is, without a pop
		end
	end
end

-- The charge, for every player (Combat.chargeGlow from the ChargeStartedAt attribute): the shell round the ball and
-- its light grow with the strength and flare up green while letting go would be perfect. Players nearby hear the
-- charge start and each perfect moment at the hand.
local function chargeLook(
	player: Player,
	entry: Held,
	hand: BasePart,
	centre: Vector3,
	serverNow: number,
	shown: boolean
)
	local startedAt = player:GetAttribute("ChargeStartedAt")
	local level, perfect = Combat.chargeGlow(startedAt, serverNow, CombatConfig)
	local started = if type(startedAt) == "number" then startedAt else nil
	if started ~= entry.chargeStart then
		entry.chargeStart = started
		if started then
			Sfx.at("chargeUp", hand, Charge.hearing)
		end
	end
	if perfect and not entry.chargePerfect then
		Sfx.at("perfectReady", hand, Charge.hearing)
	end
	entry.chargePerfect = perfect
	local glow = entry.glow
	local on = shown and level > 0
	place(glow, on)
	if not on then
		return
	end
	local light = glow:FindFirstChildOfClass("PointLight") :: PointLight
	local color = if perfect then PERFECT else ICE
	glow.Color = color
	light.Color = color
	glow.Transparency = if perfect then 0.45 else 1 - 0.35 * level
	light.Brightness = if perfect then Charge.perfectBrightness else Charge.brightness * level
	light.Range = if perfect then Charge.perfectRange else Charge.range * level
	glow.CFrame = CFrame.new(centre)
	if player == localPlayer then
		glow.LocalTransparencyModifier = hand.LocalTransparencyModifier -- fades with the arm in first person
	end
end

-- Starts a pop when the loaded count changes: a throw (fewer, still some) pops the next ball in from nothing once the
-- arm has swung through (reappearDelay; until then the hand is empty, the thrown ball is in the air), the last throw
-- pops it out, a refill pops it in from the frost. Every ball that pops in turns once.
local function sync(entry: Held, loaded: number, clock: number)
	local previous = entry.count
	entry.count = loaded
	if previous == nil then
		entry.loaded = loaded > 0
		entry.changedAt = -math.huge
		return
	end
	if loaded == previous then
		return
	end
	entry.from, entry.fromTransparency = entry.scale, entry.transparency
	entry.changedAt = clock
	if loaded > 0 and previous > loaded then
		-- the ball in the hand was thrown; the next one appears after the swing (scale 0 until changedAt)
		entry.from, entry.fromTransparency = 0, 0
		entry.changedAt = clock + Look.reappearDelay
	end
	if loaded > 0 then
		entry.spinAt = entry.changedAt
	end
	entry.loaded = loaded > 0
end

-- Scale and transparency to draw, and whether it is the frost ball (otherwise a loaded or vanishing ball).
local function look(entry: Held, clock: number, refill: number): (number, number, boolean)
	if entry.loaded then
		local alpha = math.clamp((clock - entry.changedAt) / Look.popIn, 0, 1)
		local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		return entry.from + (1 - entry.from) * eased, entry.fromTransparency * (1 - alpha), false
	end
	local alpha = math.clamp((clock - entry.changedAt) / Look.popOut, 0, 1)
	local out = entry.from * (1 - alpha)
	local frost = Look.frostMax * refill
	if out >= frost then
		return out, entry.fromTransparency, false
	end
	return frost, Look.frostTransparency, true
end

local function handOf(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if hand and hand:IsA("BasePart") then hand else nil
end

-- The centre of the ball above the palm: over the middle of the R15 hand, or over the hand end of R6's one-piece
-- arm (a block as wide as the arm at its lower end), `hover` studs above the top of that block as it is turned now.
local function aboveThePalm(hand: BasePart): Vector3
	local palm, size = hand.CFrame, hand.Size
	if hand.Name == "Right Arm" then
		palm *= CFrame.new(0, -(size.Y - size.X) / 2, 0)
		size = Vector3.new(size.X, size.X, size.Z)
	end
	-- half the block's height in the world, whichever way it is turned
	local halfUp = (
		math.abs(palm.RightVector.Y) * size.X
		+ math.abs(palm.UpVector.Y) * size.Y
		+ math.abs(palm.LookVector.Y) * size.Z
	) / 2
	return palm.Position + Vector3.yAxis * (halfUp + Look.hover + DIAMETER / 2)
end

-- The way the character faces, flat, so the ball's face looks ahead with it.
local function facingOf(character: Model): CFrame
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local lookVector = root.CFrame.LookVector
		local flat = Vector3.new(lookVector.X, 0, lookVector.Z)
		if flat.Magnitude > 1e-3 then
			return CFrame.lookAt(Vector3.zero, flat)
		end
	end
	return CFrame.identity
end

local function onRenderStep()
	local clock = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	for player, entry in held do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hand = character and handOf(character)
		local visible = player:GetAttribute("CombatMode") == true
			and hand ~= nil
			and humanoid ~= nil
			and humanoid.Health > 0
			and (eye == nil or (hand.Position - eye).Magnitude <= Look.drawDistance)
		show(entry, visible)
		if not visible or not hand or not character then
			continue
		end

		local count = player:GetAttribute("IceBalls")
		local readyAt = player:GetAttribute("IceBallsReadyAt")
		local loaded, refill = Combat.ammoDisplay(
			if type(count) == "number" then count else CombatConfig.ammo,
			if type(readyAt) == "number" then readyAt else 0,
			serverNow,
			CombatConfig
		)
		sync(entry, loaded, clock)
		local scale, transparency, frost = look(entry, clock, refill)
		entry.scale, entry.transparency = scale, transparency

		local diameter = DIAMETER * math.max(scale, HIDDEN_SCALE)
		local shownTransparency = if scale < HIDDEN_SCALE then 1 else transparency
		local localModifier = if player == localPlayer then hand.LocalTransparencyModifier else nil -- fades with the arm in first person
		-- floating above the palm of the presenting hand (ThrowAnimator)
		local facing = facingOf(character)
		local centre = CFrame.new(aboveThePalm(hand) + facing.RightVector * Look.side)
		local model = entry.model
		local useModel = model ~= nil and not frost
		place(entry.part, not useModel)

		if model and useModel then
			place(model, true)
			if math.abs(entry.modelSize - diameter) > 1e-3 then
				entry.modelSize = diameter
				BallVisual.setDiameter(model, diameter)
			end
			BallVisual.setTransparency(model, shownTransparency, localModifier)
			-- sparkles and glow only while the ball can be seen (not hidden, popping in from nothing, or in first person)
			if entry.frost then
				BallVisual.setFrost(entry.frost, scale > 0.5 and (localModifier or 0) < 0.5)
			end
			local idle = BallMotion.idle(clock, CombatConfig)
			local turn = BallMotion.nextThrow(clock - entry.spinAt, CombatConfig)
			local spin = math.rad(Look.spinSpeed) * clock
			model:PivotTo(
				centre
					* facing
					* CFrame.new(0, idle.lift * DIAMETER, 0)
					* CFrame.Angles(0, idle.yaw + turn + spin, 0)
					* CFrame.Angles(idle.pitch, 0, idle.roll)
			)
			chargeLook(player, entry, hand, model:GetPivot().Position, serverNow, scale > 0.5)
			continue
		end
		if model then
			place(model, false)
		end
		if entry.frost then
			BallVisual.setFrost(entry.frost, false)
		end

		local part = entry.part
		if math.abs(entry.size - diameter) > 1e-3 then
			entry.size = diameter
			part.Size = Vector3.one * diameter
		end
		-- Transparency is stored as a float32, so an exact compare would rewrite 0.55 every frame
		if math.abs(part.Transparency - shownTransparency) > 1e-3 then
			part.Transparency = shownTransparency
		end
		if localModifier then
			part.LocalTransparencyModifier = localModifier
		end
		part.CFrame = centre
		chargeLook(player, entry, hand, centre.Position, serverNow, not frost and scale > 0.5)
	end
end

local function track(player: Player)
	if not held[player] then
		held[player] = newHeld(player)
	end
end

local function untrack(player: Player)
	local entry = held[player]
	if entry then
		held[player] = nil
		entry.part:Destroy()
		entry.glow:Destroy()
		if entry.model then
			entry.model:Destroy()
		end
	end
end

function HeldBalls.Start()
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	-- after MovementController's pose (Character + 2), so the ball sits in the posed hand
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Character.Value + 3, onRenderStep)
end

return HeldBalls
