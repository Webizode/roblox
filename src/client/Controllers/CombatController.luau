-- Ice-ball throws on the client. R (Y on a gamepad, the Combat button on touch screens) switches combat mode on and
-- off; only in it are the crosshair and the throw button there, and the mouse is caught in the middle of the screen
-- so it aims. A tap on the throw button (left mouse button, the Throw button on touch screens, R2 on a gamepad)
-- throws at once; holding it builds the strength while a small circle pulses inside the crosshair (AimHud), and
-- letting go when it touches the outer circle is a faster perfect throw (Combat.strength, pulse, isPerfect). The
-- crosshair is fixed in the middle of the screen and every throw aims through it; the aim help is the combat
-- camera's (CombatCamera). It draws every ball on the curve the server simulates and plays the
-- reaction the server announces. The server decides everything: the strength and perfect throw it accepts, ammo,
-- flight, hits, power and knockdowns. The victim's own client
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
local AimRules = require(Shared:WaitForChild("AimRules"))
local BallMotion = require(Shared:WaitForChild("BallMotion"))
local MapQuery = require(Shared:WaitForChild("MapQuery"))
local CombatConfig = require(Config:WaitForChild("Combat"))
local Features = require(Config:WaitForChild("Features"))
local Palette = require(Config:WaitForChild("Palette"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))
local CombatCamera = require(client:WaitForChild("CombatCamera"))
local Sfx = require(client:WaitForChild("Sfx"))
local BallVisual = require(client:WaitForChild("BallVisual"))

local CombatController = {}

local THROW_ACTION = "WobbleThrow"
local MODE_ACTION = "WobbleCombatMode"
local BLOCK_SHIFT_LOCK_ACTION = "WobbleCombatBlockShiftLock"
local BLOCK_CAMERA_PAN_ACTION = "WobbleCombatBlockCameraPan"
local MOUSE_STEP = "WobbleCombatMouse"
local RELEASE_STEP = "WobbleCombatMouseRelease"
-- after leaving combat mode the mouse is kept free this long, against a late lock from anything that still
-- remembers the combat mouse state
local RELEASE_GUARD = 1
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 100

type Ball = {
	part: BasePart, -- the plain ice ball, or the vanilla ball's body; the trail sits on it
	model: Model?, -- the vanilla ball (BallVisual), hopping and spinning on the path (BallMotion.flight)
	flight: BallVisual.Flight, -- its streak, twinkles and glow
	facing: CFrame, -- flat along the throw, so the face starts looking where the ball flies
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
local lastThrowAt = -math.huge -- os.clock() of the local player's last throw, for the crosshair's spread
local crosshairRadius = CombatConfig.crosshair.radius -- eased (AimRules.ease)
local combatMode = false
local modeChangedAt = -math.huge
local releaseUntil = 0 -- os.clock() until which the release guard keeps the mouse free
local forceExit: () -> () -- defined with the combat mode functions below; the knockdown needs it earlier

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

local function debugLog(message: string)
	if Features.debugThrow then
		print("[Throw] " .. message)
	end
end

-- The ball ends (hit, missed or lost): its streak and twinkles stay where it was and fade out, the ball goes.
local function destroyBall(ball: Ball)
	BallVisual.leaveFlight(ball.flight, ball.part.CFrame)
	if ball.model then
		ball.model:Destroy()
	else
		ball.part:Destroy()
	end
end

local function onThrown(id: number, thrower: Player, origin: Vector3, velocity: Vector3, t0: number, perfect: boolean?)
	-- still in the hand until t0, the throw animation's release
	local model = BallVisual.new("IceBall", CombatConfig.ballRadius * 2)
	local part: BasePart
	if model then
		part = BallVisual.body(model)
		BallVisual.setTransparency(model, 1)
		model:PivotTo(CFrame.new(origin))
		model.Parent = TowerVisual.root()
	else
		part = effectPart("IceBall", CombatConfig.ballRadius * 2, Color3.fromHex(Palette.skyTop), origin)
		part.Transparency = 1
	end
	-- the streak, twinkles and glow (BallVisual); dark until the release, like the ball
	local flight = BallVisual.addFlight(part, CombatConfig.ballRadius)
	flight.emitter.Enabled = false
	flight.light.Enabled = false
	if perfect then
		BallVisual.perfect(flight) -- a perfect throw sparkles gold for everybody
	end
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	balls[id] = {
		part = part,
		model = model,
		flight = flight,
		facing = if flat.Magnitude > 1e-3 then CFrame.lookAt(Vector3.zero, flat) else CFrame.identity,
		origin = origin,
		velocity = velocity,
		t0 = t0,
	}
	registry.ThrowAnimator.thrown(thrower, t0)
	if thrower == player then
		debugLog(
			string.format(
				"#%d thrown from %s at %.0f studs/s, %.2f s after the server started it",
				id,
				tostring(origin),
				velocity.Magnitude,
				workspace:GetServerTimeNow() - t0
			)
		)
	end
	Sfx.play("throw")
end

-- A puff of ice where the ball ended, bigger on a hit; see-through and small enough not to hide the player behind it
-- (BallVisual.hitShards adds the shards around it).
local function puff(position: Vector3, hit: boolean)
	local size = if hit then 2 else 1.3
	local part = effectPart("IcePuff", size, Color3.fromHex(Palette.vanilla), position)
	part.Transparency = 0.45
	TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(size * 2, size * 2, size * 2),
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
	forceExit() -- the server ends combat mode with the knockdown too
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
	knockdown: boolean,
	shielded: boolean?
)
	local ball = balls[id]
	if ball then
		balls[id] = nil
		destroyBall(ball)
		if thrower == player then
			debugLog(
				string.format(
					"#%d ended at %s after %.2f s, %.1f studs from its start (%s)",
					id,
					tostring(position),
					workspace:GetServerTimeNow() - ball.t0,
					(position - ball.origin).Magnitude,
					if victim then "hit " .. victim.Name else "world or out of range"
				)
			)
		end
	end
	puff(position, victim ~= nil)
	BallVisual.hitShards(position, victim ~= nil)
	if not victim then
		return
	end
	if shielded then
		-- the victim stands in their cart's safe zone: the ball lands, nothing else happens
		if thrower == player or victim == player then
			registry.Hud.toast("SAFE!", Palette.mint)
		end
		return
	end

	local character = victim.Character
	local strength = if knockdown then power * CombatConfig.knockdownBoost else power
	if character then
		flash(character)
		registry.MovementController.stumble(character, dirX, dirZ, strength)
		if knockdown then
			registry.MovementController.knockDown(character, CombatConfig.knockdownTime)
		else
			registry.MovementController.hitReaction(character)
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
			destroyBall(ball)
			continue
		end
		if t < 0 then
			continue -- the throw animation has not released it yet
		end
		if ball.part.Transparency > 0 then
			if ball.model then
				BallVisual.setTransparency(ball.model, 0)
			else
				ball.part.Transparency = 0
			end
			ball.flight.emitter.Enabled = true
			ball.flight.light.Enabled = true
		end
		local o, v = ball.origin, ball.velocity
		local flight = math.clamp(t, 0, CombatConfig.maxFlight)
		local x, y, z = Combat.position(o.X, o.Y, o.Z, v.X, v.Y, v.Z, CombatConfig.gravity, flight)
		local model = ball.model
		if model then
			-- the hop is only drawn; the server's path (and its hit test) stays exactly the curve above
			local lift, spin = BallMotion.flight(flight, CombatConfig)
			model:PivotTo(
				CFrame.new(x, y + lift * CombatConfig.ballRadius * 2, z) * ball.facing * CFrame.Angles(0, spin, 0)
			)
		else
			ball.part.Position = Vector3.new(x, y, z)
		end
	end
end

-- Whether a throw could happen now: ammo left, standing, alive. The steady stance does not stop it: charging keeps
-- the stance, the throw ends it. The server checks all of it again.
local function canThrow(): boolean
	local count = player:GetAttribute("IceBalls")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return combatMode
		and type(count) == "number"
		and count > 0
		and os.clock() >= downUntil
		and humanoid ~= nil
		and humanoid.Health > 0
end

-- Drops a running charge without throwing; with the button still down it starts again once a throw is possible.
local function cancelCharge(releaseButton: boolean)
	if charging then
		registry.ThrowAnimator.charge(false)
	end
	charging = false
	CombatCamera.setAiming(false) -- after a throw and after a dropped charge alike
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
			registry.ThrowAnimator.charge(true)
			CombatCamera.setAiming(true)
		end
	end
end

-- The world point the throw aims at: under `screen` (viewport pixels), or a point far along that ray. The ray
-- ignores the own character, the own tower and every drawn scoop and ball (LocalVisuals), everything the ball would
-- fly through anyway (parts without collision and the thin
-- decoration of Config/Map, MapQuery.throwRaycast), and
-- everything between the camera and the character, so only what lies ahead of the player can be the target.
local function aimPoint(screen: Vector2): Vector3
	local camera = workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local origin, unit = ray.Origin, ray.Direction.Unit
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		origin += unit * math.max(0, (root.Position - origin):Dot(unit))
	end
	-- the own tower, every scoop and ball and the free scoops are drawn in LocalVisuals: none of them is a target
	local ignore: { Instance } = { TowerVisual.root() }
	if character then
		table.insert(ignore, character)
	end
	local direction = unit * CombatConfig.aimDistance
	local result = MapQuery.throwRaycast(origin, direction, ignore)
	return if result then result.Position else origin + direction
end

-- Button down charges, button up throws with the bar's value at that moment. The local checks only save pointless
-- requests; the server decides about the charge, ammo, cooldown and whether the throw happens at all.
local function requestThrow(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		wantCharge = true
		tryStartCharge()
	elseif inputState == Enum.UserInputState.End then
		if charging and canThrow() then
			local held = os.clock() - chargeStartedAt
			local strength = Combat.strength(held, CombatConfig)
			local perfect = Combat.isPerfect(held, CombatConfig)
			local camera = workspace.CurrentCamera
			local aim = aimPoint(camera.ViewportSize / 2) -- always through the middle of the screen
			lastRequestAt = os.clock()
			lastThrowAt = os.clock()
			Remotes.ThrowIceBall:FireServer(aim.X, aim.Y, aim.Z, strength, perfect)
			if perfect then
				Sfx.play("perfectThrow", 1.4) -- the thrower hears it at once; everybody sees its sparkle (onThrown)
			end
			registry.TowerController.interruptStance() -- after the request, so the server locks its stance too
			registry.ThrowAnimator.release() -- the throw animation starts with the button-up, like the server's clock
			local character = player.Character
			local hand = character and character:FindFirstChild("RightHand") :: BasePart?
			debugLog(
				string.format(
					"release: strength %.2f%s, aim %s, %.1f studs from the hand",
					strength,
					if perfect then " (perfect)" else "",
					tostring(aim),
					if hand then (aim - hand.Position).Magnitude else -1
				)
			)
		elseif charging or wantCharge then
			debugLog("release without a throw: no ammo, knocked down, dead or out of combat mode")
		end
		cancelCharge(true)
	elseif inputState == Enum.UserInputState.Cancel then
		cancelCharge(true)
	end
	return Enum.ContextActionResult.Sink
end

local function onAimStep(dt: number)
	if charging and not canThrow() then
		cancelCharge(false) -- knocked down or died mid-charge
	end
	tryStartCharge()
	-- the crosshair stays in the middle of the screen; nothing in the world moves it
	local held = if charging then os.clock() - chargeStartedAt else nil
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local target = AimRules.radius({
		moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.1,
		sprinting = registry.MovementController.isSprinting(),
		sinceDash = os.clock() - registry.MovementController.lastDash(),
		sinceThrow = os.clock() - lastThrowAt,
		strength = if held then Combat.strength(held, CombatConfig) else nil,
	}, CombatConfig)
	crosshairRadius = AimRules.ease(crosshairRadius, target, dt, CombatConfig)
	registry.AimHud.set(combatMode, canThrow(), crosshairRadius, held)
end

-- Holds the mouse in the middle of the screen and keeps the cursor hidden (the crosshair is the cursor) while combat
-- mode is on. Runs after the camera scripts every frame, because they set the mouse behaviour and the cursor
-- themselves (a held right mouse button pans Roblox's camera and shows the cursor).
local function onMouseStep()
	if UserInputService.MouseEnabled and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
	if UserInputService.MouseIconEnabled then
		UserInputService.MouseIconEnabled = false
	end
end

-- Swallows an input while combat mode holds the mouse: shift lock (Ctrl), so the mouse state saved on entry is still
-- the right one to restore, and the right mouse button, which would pan Roblox's camera and show the cursor.
local function swallow(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

-- Whether Roblox's own shift lock (Ctrl) is on, read from the PlayerModule. If that cannot be read, it counts as
-- off, so leaving combat mode always frees the mouse.
local function shiftLockOn(): boolean
	local ok, locked = pcall(function()
		local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: any) :: any
		return playerModule:GetCameras().activeMouseLockController:GetIsMouseLocked()
	end)
	return ok and locked == true
end

-- For a moment after leaving combat mode: the mouse stays free unless shift lock or the right mouse button (Roblox's
-- own camera pan) asks for it, or the camera is in first person.
local function onReleaseStep()
	if os.clock() > releaseUntil then
		RunService:UnbindFromRenderStep(RELEASE_STEP)
		return
	end
	if UserInputService.MouseBehavior == Enum.MouseBehavior.Default or shiftLockOn() then
		return
	end
	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		return
	end
	local camera = workspace.CurrentCamera
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	if camera and head and (camera.CFrame.Position - head.Position).Magnitude < 1.5 then
		return
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

local function enterCombatMode()
	combatMode = true
	RunService:UnbindFromRenderStep(RELEASE_STEP)
	UserInputService.MouseIconEnabled = false -- the crosshair is the cursor now
	CombatCamera.start()
	RunService:BindToRenderStep(MOUSE_STEP, Enum.RenderPriority.Camera.Value + 1, onMouseStep)
	ContextActionService:BindActionAtPriority(
		BLOCK_SHIFT_LOCK_ACTION,
		swallow,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.RightControl
	)
	ContextActionService:BindActionAtPriority(
		BLOCK_CAMERA_PAN_ACTION,
		swallow,
		false,
		ACTION_PRIORITY,
		Enum.UserInputType.MouseButton2
	)
	ContextActionService:BindActionAtPriority(
		THROW_ACTION,
		requestThrow,
		true, -- creates the Throw button on touch screens
		ACTION_PRIORITY,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:SetTitle(THROW_ACTION, "Throw")
end

-- Ends combat mode locally and gives the mouse back to Roblox. Safe to call when it is already off.
-- The order matters: the mouse is freed before Roblox's camera takes over again. Roblox's camera remembers the mouse
-- state it finds when it locks the mouse itself (shift lock) and restores that one later; finding our combat lock
-- there would leave the mouse caught for good. If shift lock is on, Roblox's camera locks the mouse again on its own.
local function exitCombatMode()
	cancelCharge(true)
	if not combatMode then
		return
	end
	combatMode = false
	ContextActionService:UnbindAction(THROW_ACTION)
	ContextActionService:UnbindAction(BLOCK_SHIFT_LOCK_ACTION)
	ContextActionService:UnbindAction(BLOCK_CAMERA_PAN_ACTION)
	RunService:UnbindFromRenderStep(MOUSE_STEP)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	CombatCamera.stop()
	releaseUntil = os.clock() + RELEASE_GUARD
	RunService:BindToRenderStep(RELEASE_STEP, Enum.RenderPriority.Camera.Value + 1, onReleaseStep)
end

local function setCombatMode(on: boolean)
	if on == combatMode then
		return
	end
	if on then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or os.clock() < downUntil then
			return
		end
		enterCombatMode()
	else
		exitCombatMode()
	end
	Remotes.SetCombatMode:FireServer(on)
end

-- R toggles; a little slower than the server's limit, so the server never drops a switch the client made.
local function onModeInput(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if
		inputState == Enum.UserInputState.Begin
		and os.clock() - modeChangedAt >= CombatConfig.combatModeInterval + 0.05
	then
		modeChangedAt = os.clock()
		setCombatMode(not combatMode)
	end
	return Enum.ContextActionResult.Sink
end

-- Everything that ends combat mode without the player asking: knockdown, death, respawn, or the server saying so.
function forceExit()
	if combatMode then
		exitCombatMode()
		Remotes.SetCombatMode:FireServer(false)
	end
end

function CombatController.Init(reg)
	registry = reg
end

function CombatController.Start()
	Remotes.IceBallThrown.OnClientEvent:Connect(onThrown)
	Remotes.IceBallResolved.OnClientEvent:Connect(onResolved)
	ContextActionService:BindActionAtPriority(
		MODE_ACTION,
		onModeInput,
		true, -- creates the Combat button on touch screens
		ACTION_PRIORITY,
		Enum.KeyCode.R,
		Enum.KeyCode.ButtonY
	)
	ContextActionService:SetTitle(MODE_ACTION, "Combat")
	RunService.RenderStepped:Connect(onRenderStep)
	RunService.RenderStepped:Connect(onAimStep)

	-- combat mode and its mouse never outlive the character: death, respawn, or the server ending it (knockdown)
	local function watchCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid and character == player.Character then
			humanoid.Died:Connect(forceExit)
			CombatCamera.follow() -- the normal camera follows the new character, not the old one
		end
	end
	player.CharacterAdded:Connect(function(character)
		forceExit()
		watchCharacter(character)
	end)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player:GetAttributeChangedSignal("CombatMode"):Connect(function()
		if player:GetAttribute("CombatMode") == false then
			forceExit()
		end
	end)
	-- losing the window focus ends combat mode: the button-up would never arrive, and the mouse must not be caught
	-- when the player comes back
	UserInputService.WindowFocusReleased:Connect(forceExit)
end

return CombatController
