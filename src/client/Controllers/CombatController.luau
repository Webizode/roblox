-- Ice-ball throws on the client: asks the server to throw (left mouse button, the Throw button on touch screens,
-- R2 on a gamepad), draws every ball on the curve the server simulates, and plays the reaction the server
-- announces. The server decides everything: ammo, flight, hits, power and knockdowns. The victim's own client
-- applies the knockback and the tower shove, like every other force on the local character and tower.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Combat = require(Shared:WaitForChild("Combat"))
local CombatConfig = require(Config:WaitForChild("Combat"))
local Palette = require(Config:WaitForChild("Palette"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))
local Sfx = require(client:WaitForChild("Sfx"))

local CombatController = {}

local THROW_ACTION = "WobbleThrow"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 100

type Ball = {
	part: Part,
	origin: Vector3,
	velocity: Vector3,
	t0: number,
}

local player = Players.LocalPlayer
local registry
local balls: { [number]: Ball } = {}
local lastRequestAt = -math.huge
local downUntil = 0 -- os.clock() until the local player stands up again

local function effectPart(name: string, size: number, color: Color3, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Ice
	part.Color = color
	part.Size = Vector3.new(size, size, size)
	part.Position = position
	part.Parent = TowerVisual.root()
	return part
end

local function onThrown(id: number, _thrower: Player, origin: Vector3, velocity: Vector3, t0: number)
	local part = effectPart("IceBall", CombatConfig.ballRadius * 2, Color3.fromHex(Palette.skyTop), origin)
	balls[id] = { part = part, origin = origin, velocity = velocity, t0 = t0 }
	Sfx.play("throw")
end

-- A puff of ice where the ball ended, bigger and whiter on a hit.
local function puff(position: Vector3, hit: boolean)
	local size = if hit then 3 else 1.6
	local part = effectPart("IcePuff", size, Color3.fromHex(Palette.vanilla), position)
	part.Transparency = 0.2
	TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(size * 2.5, size * 2.5, size * 2.5),
		Transparency = 1,
	}):Play()
	task.delay(0.4, function()
		part:Destroy()
	end)
end

-- A short white flash on whoever was hit, seen by everyone.
local function flash(character: Model)
	local highlight = Instance.new("Highlight")
	highlight.Name = "IceHit"
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	TweenService:Create(highlight, TweenInfo.new(0.3), { FillTransparency = 1 }):Play()
	task.delay(0.35, function()
		highlight:Destroy()
	end)
end

-- Controlled knockback on the local character: away from the thrower and a little up, for a moment.
local function knockback(root: BasePart, dirX: number, dirZ: number, strength: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "KnockbackAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "KnockbackVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.VectorVelocity = Vector3.new(
		dirX * CombatConfig.knockbackSpeed * strength,
		CombatConfig.knockbackUp * strength,
		dirZ * CombatConfig.knockbackSpeed * strength
	)
	velocity.MaxForce = root.AssemblyMass * 3000
	velocity.Parent = root
	task.delay(CombatConfig.knockbackTime, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
end

-- The local player cannot move or jump while down. The body only lies down visually (MovementController): the
-- root stays upright, so the tower, catching and serving keep working from the same spot.
local function knockDown()
	downUntil = os.clock() + CombatConfig.knockdownTime
	local playerModule = player:WaitForChild("PlayerScripts"):FindFirstChild("PlayerModule")
	local ok, controls = pcall(function()
		return (require(playerModule :: ModuleScript) :: any):GetControls()
	end)
	if not ok or not controls then
		return
	end
	controls:Disable()
	task.delay(CombatConfig.knockdownTime, function()
		if os.clock() >= downUntil - 0.05 then
			controls:Enable()
		end
	end)
end

local function onResolved(
	id: number,
	thrower: Player,
	victim: Player?,
	position: Vector3,
	dirX: number,
	dirZ: number,
	power: number,
	knockdown: boolean
)
	local ball = balls[id]
	if ball then
		balls[id] = nil
		ball.part:Destroy()
	end
	puff(position, victim ~= nil)
	if not victim then
		return
	end

	local character = victim.Character
	local strength = if knockdown then power * CombatConfig.knockdownBoost else power
	if character then
		flash(character)
		registry.MovementController.stumble(character, dirX, dirZ, strength)
		if knockdown then
			registry.MovementController.knockDown(character, CombatConfig.knockdownTime)
		end
	end
	if thrower == player and victim ~= player then
		registry.Hud.toast(if knockdown then "KNOCKDOWN!" else "HIT!", Palette.lemon)
	end
	if victim ~= player or not character then
		return
	end

	-- the local player was hit: the server already decided how hard and whether it knocks down
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	Sfx.play("hit")
	if root then
		knockback(root, dirX, dirZ, strength)
	end
	registry.TowerController.hit(dirX, dirZ, strength)
	if knockdown then
		knockDown()
		registry.Hud.toast("KNOCKED DOWN!", Palette.awning)
	end
end

local function onRenderStep()
	local time = workspace:GetServerTimeNow()
	for id, ball in balls do
		local t = time - ball.t0
		if t > CombatConfig.maxFlight + 0.5 then
			-- the resolve message got lost; do not keep orphans around
			balls[id] = nil
			ball.part:Destroy()
			continue
		end
		local o, v = ball.origin, ball.velocity
		local x, y, z = Combat.position(
			o.X,
			o.Y,
			o.Z,
			v.X,
			v.Y,
			v.Z,
			CombatConfig.gravity,
			math.clamp(t, 0, CombatConfig.maxFlight)
		)
		ball.part.Position = Vector3.new(x, y, z)
	end
end

-- One press, one throw request, aimed where the camera looks. The local checks only save pointless requests; the
-- server decides about ammo, cooldown and whether the throw happens at all.
local function requestThrow(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local count = player:GetAttribute("IceBalls")
	if type(count) ~= "number" or count <= 0 then
		return Enum.ContextActionResult.Pass
	end
	if os.clock() - lastRequestAt < CombatConfig.throwInterval or os.clock() < downUntil then
		return Enum.ContextActionResult.Sink
	end
	lastRequestAt = os.clock()
	local aim = workspace.CurrentCamera.CFrame.LookVector
	Remotes.ThrowIceBall:FireServer(aim.X, aim.Y, aim.Z)
	return Enum.ContextActionResult.Sink
end

function CombatController.Init(reg)
	registry = reg
end

function CombatController.Start()
	Remotes.IceBallThrown.OnClientEvent:Connect(onThrown)
	Remotes.IceBallResolved.OnClientEvent:Connect(onResolved)
	ContextActionService:BindActionAtPriority(
		THROW_ACTION,
		requestThrow,
		true, -- creates the Throw button on touch screens
		ACTION_PRIORITY,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:SetTitle(THROW_ACTION, "Throw")
	RunService.RenderStepped:Connect(onRenderStep)
end

return CombatController
