-- Ice-ball throws on the client. Holding the throw button (left mouse button, the Throw button on touch screens,
-- R2 on a gamepad) charges the bar under the crosshair (AimHud), releasing asks the server to throw at the point
-- under the crosshair with that charge. It draws every ball on the curve the server simulates and plays the
-- reaction the server announces. The server decides everything: the charge it accepts, ammo, flight, hits, power
-- and knockdowns. The victim's own client
-- applies the knockback and the tower shove, like every other force on the local character and tower.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
-- a margin on the throw interval, so network jitter never makes the server see two throws too close together
local INTERVAL_MARGIN = 0.05
local wantCharge = false -- the throw button is down
local charging = false -- the bar runs; the server got the matching ChargeIceBall
local chargeStartedAt = 0 -- os.clock()

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

-- Whether a throw could happen now: ammo left, standing, alive. The server checks all of it again.
local function canThrow(): boolean
	local count = player:GetAttribute("IceBalls")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return type(count) == "number" and count > 0 and os.clock() >= downUntil and humanoid ~= nil and humanoid.Health > 0
end

-- Drops a running charge without throwing; with the button still down it starts again once a throw is possible.
local function cancelCharge(releaseButton: boolean)
	charging = false
	if releaseButton then
		wantCharge = false
	end
end

-- The bar starts once the button is down and a throw is possible: right away, after the throw interval, after a
-- reload, or after getting up. The server starts its own clock with it.
local function tryStartCharge()
	if wantCharge and not charging and canThrow() then
		if os.clock() - lastRequestAt >= CombatConfig.throwInterval + INTERVAL_MARGIN then
			charging = true
			chargeStartedAt = os.clock()
			Remotes.ChargeIceBall:FireServer()
		end
	end
end

-- The world point under the crosshair (the screen centre), or a point far along that ray.
local function aimPoint(): Vector3
	local camera = workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local direction = ray.Direction * CombatConfig.aimDistance
	local result = workspace:Raycast(ray.Origin, direction, params)
	return if result then result.Position else ray.Origin + direction
end

-- Button down charges, button up throws with the bar's value at that moment. The local checks only save pointless
-- requests; the server decides about the charge, ammo, cooldown and whether the throw happens at all.
local function requestThrow(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		wantCharge = true
		tryStartCharge()
	elseif inputState == Enum.UserInputState.End then
		if charging and canThrow() then
			local charge = Combat.charge(os.clock() - chargeStartedAt, CombatConfig)
			local aim = aimPoint()
			lastRequestAt = os.clock()
			Remotes.ThrowIceBall:FireServer(aim.X, aim.Y, aim.Z, charge)
		end
		cancelCharge(true)
	elseif inputState == Enum.UserInputState.Cancel then
		cancelCharge(true)
	end
	return Enum.ContextActionResult.Sink
end

local function onAimStep()
	if charging and not canThrow() then
		cancelCharge(false) -- knocked down or died mid-charge
	end
	tryStartCharge()
	registry.AimHud.set(canThrow(), if charging then Combat.charge(os.clock() - chargeStartedAt, CombatConfig) else nil)
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
	RunService.RenderStepped:Connect(onAimStep)
	-- no charge survives a respawn or the window losing focus (the button-up would never arrive)
	player.CharacterAdded:Connect(function()
		cancelCharge(true)
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		cancelCharge(true)
	end)
end

return CombatController
