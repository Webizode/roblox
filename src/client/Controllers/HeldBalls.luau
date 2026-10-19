-- The ice ball in the right hand of every player in combat mode: the next ball they can throw. A throw makes the
-- next one pop into the hand; with the load empty a see-through frost ball grows there until the reload ends. Every
-- client draws it for every player from the CombatMode, IceBalls and IceBallsReadyAt attributes the server sets
-- (Combat.ammoDisplay turns the ammo into what to show). Client-only, anchored, non-colliding, like the towers;
-- nothing here touches gameplay. The thrown ball itself starts at the server's release point, the same hand.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Combat = require(Shared:WaitForChild("Combat"))
local CombatConfig = require(Config:WaitForChild("Combat"))
local Palette = require(Config:WaitForChild("Palette"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))

local HeldBalls = {}

type Held = {
	part: Part,
	count: number?, -- loaded balls last frame; nil until the first reading, which shows without a pop
	loaded: boolean,
	changedAt: number, -- os.clock() the last pop in or out started
	from: number, -- scale and transparency when it changed, so a pop starts from what was on screen
	fromTransparency: number,
	scale: number,
	transparency: number,
	size: number, -- last size written
	shown: boolean,
}

local STEP = "WobbleHeldBalls"
local HIDDEN_SCALE = 0.02
local Look = CombatConfig.held
local DIAMETER = CombatConfig.ballRadius * 2 -- the same ball that flies

local localPlayer = Players.LocalPlayer
local held: { [Player]: Held } = {}

local function newHeld(player: Player): Held
	local part = TowerVisual.makePart(TowerVisual.root())
	part.Name = "HeldBall_" .. player.UserId
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Ice
	part.Color = Color3.fromHex(Palette.skyTop)
	part.Parent = nil
	return {
		part = part,
		count = nil,
		loaded = true,
		changedAt = -math.huge,
		from = 0,
		fromTransparency = 0,
		scale = 1,
		transparency = 0,
		size = -1,
		shown = false,
	}
end

local function show(entry: Held, on: boolean)
	if entry.shown ~= on then
		entry.shown = on
		entry.part.Parent = if on then TowerVisual.root() else nil
		if not on then
			entry.count = nil -- what changed while hidden shows as it is, without a pop
		end
	end
end

-- Starts a pop when the loaded count changes: a throw (fewer, still some) pops the next ball in from nothing, the
-- last throw pops it out, a refill pops it in from the frost.
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
		entry.from, entry.fromTransparency = 0, 0 -- the ball in the hand was thrown; the next one appears
	end
	entry.loaded = loaded > 0
end

local function look(entry: Held, clock: number, refill: number): (number, number)
	if entry.loaded then
		local alpha = math.clamp((clock - entry.changedAt) / Look.popIn, 0, 1)
		local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		return entry.from + (1 - entry.from) * eased, entry.fromTransparency * (1 - alpha)
	end
	local alpha = math.clamp((clock - entry.changedAt) / Look.popOut, 0, 1)
	local out = entry.from * (1 - alpha)
	local frost = Look.frostMax * refill
	if out >= frost then
		return out, entry.fromTransparency
	end
	return frost, Look.frostTransparency
end

local function handOf(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if hand and hand:IsA("BasePart") then hand else nil
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
		if not visible or not hand then
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
		local scale, transparency = look(entry, clock, refill)
		entry.scale, entry.transparency = scale, transparency

		local part = entry.part
		local diameter = DIAMETER * math.max(scale, HIDDEN_SCALE)
		if math.abs(entry.size - diameter) > 1e-3 then
			entry.size = diameter
			part.Size = Vector3.one * diameter
		end
		local shownTransparency = if scale < HIDDEN_SCALE then 1 else transparency
		-- Transparency is stored as a float32, so an exact compare would rewrite 0.55 every frame
		if math.abs(part.Transparency - shownTransparency) > 1e-3 then
			part.Transparency = shownTransparency
		end
		if player == localPlayer then
			part.LocalTransparencyModifier = hand.LocalTransparencyModifier -- fades with the arm in first person
		end
		-- in the palm: just below the hand along its own down axis
		part.CFrame = hand.CFrame * CFrame.new(0, -(hand.Size.Y / 2 + DIAMETER * 0.3), 0)
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
