-- Ice-ball throws on the client. R (Y on a gamepad, the Combat button on touch screens) switches combat mode on and
-- off; only in it are the crosshair and the throw button there, and the mouse is caught in the middle of the screen
-- so it aims. Holding the throw button (left mouse button, the Throw button on touch screens, R2 on a gamepad)
-- charges the bar under the crosshair (AimHud), releasing asks the server to throw at the point under the crosshair
-- with that charge. It draws every ball on the curve the server simulates and plays the
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
local Features = require(Config:WaitForChild("Features"))
local Palette = require(Config:WaitForChild("Palette"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))
local CombatCamera = require(client:WaitForChild("CombatCamera"))
local Sfx = require(client:WaitForChild("Sfx"))

local CombatController = {}

local THROW_ACTION = "WobbleThrow"
local MODE_ACTION = "WobbleCombatMode"
local BLOCK_SHIFT_LOCK_ACTION = "WobbleCombatBlockShiftLock"
local MOUSE_STEP = "WobbleCombatMouse"
local RELEASE_STEP = "WobbleCombatMouseRelease"
-- after leaving combat mode the mouse is kept free this long, against a late lock from anything that still
-- remembers the combat mouse state
local RELEASE_GUARD = 1
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

-- A short white streak behind a flying ball, so a fast throw stays easy to follow.
local function addTrail(part: Part)
	local front, back = Instance.new("Attachment"), Instance.new("Attachment")
	front.Position = Vector3.new(0, CombatConfig.ballRadius * 0.6, 0)
	back.Position = Vector3.new(0, -CombatConfig.ballRadius * 0.6, 0)
	front.Parent, back.Parent = part, part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = front, back
	trail.Lifetime = 0.15
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = part
end

local function onThrown(id: number, thrower: Player, origin: Vector3, velocity: Vector3, t0: number)
	local part = effectPart("IceBall", CombatConfig.ballRadius * 2, Color3.fromHex(Palette.skyTop), origin)
	part.Transparency = 1 -- still in the hand until t0, the throw animation's release
	addTrail(part)
	balls[id] = { part = part, origin = origin, velocity = velocity, t0 = t0 }
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
	knockdown: boolean
)
	local ball = balls[id]
	if ball then
		balls[id] = nil
		ball.part:Destroy()
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
		if t < 0 then
			continue -- the throw animation has not released it yet
		end
		if ball.part.Transparency > 0 then
			ball.part.Transparency = 0
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

-- Whether a throw could happen now: ammo left, standing, alive, not in the steady stance (taking it drops a running
-- charge, letting go starts it again while the button is held). The server checks all of it again.
local function canThrow(): boolean
	local count = player:GetAttribute("IceBalls")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return combatMode
		and type(count) == "number"
		and count > 0
		and os.clock() >= downUntil
		and not registry.TowerController.inStance()
		and humanoid ~= nil
		and humanoid.Health > 0
end

-- Drops a running charge without throwing; with the button still down it starts again once a throw is possible.
local function cancelCharge(releaseButton: boolean)
	if charging then
		registry.ThrowAnimator.charge(false)
	end
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
			registry.ThrowAnimator.charge(true)
		end
	end
end

-- The world point under the crosshair (the screen centre), or a point far along that ray. The ray ignores the own
-- character, everything the ball would fly through anyway (parts without collision, like invisible zones), and
-- everything between the camera and the character, so only what lies ahead of the player can be the target.
local function aimPoint(): Vector3
	local camera = workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local origin, unit = ray.Origin, ray.Direction.Unit
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		origin += unit * math.max(0, (root.Position - origin):Dot(unit))
	end
	local ignore: { Instance } = if character then { character } else {}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local direction = unit * CombatConfig.aimDistance
	for _ = 1, 8 do
		params.FilterDescendantsInstances = ignore
		local result = workspace:Raycast(origin, direction, params)
		if not result then
			break
		end
		if result.Instance.CanCollide then
			return result.Position
		end
		table.insert(ignore, result.Instance)
	end
	return origin + direction
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
			registry.ThrowAnimator.release() -- the throw animation starts with the button-up, like the server's clock
			local character = player.Character
			local hand = character and character:FindFirstChild("RightHand") :: BasePart?
			debugLog(
				string.format(
					"release: charge %.2f, aim %s, %.1f studs from the hand",
					charge,
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

local function onAimStep()
	if charging and not canThrow() then
		cancelCharge(false) -- knocked down or died mid-charge
	end
	tryStartCharge()
	registry.AimHud.set(
		combatMode,
		canThrow(),
		if charging then Combat.charge(os.clock() - chargeStartedAt, CombatConfig) else nil
	)
end

-- Holds the mouse in the middle of the screen while combat mode is on. Runs after the camera scripts every frame,
-- because they set the mouse behaviour themselves (for example after a right-click camera pan).
local function onMouseStep()
	if UserInputService.MouseEnabled and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

-- Shift lock (Ctrl) stays blocked while combat mode holds the mouse, so the mouse state saved on entry is still
-- the right one to restore.
local function blockShiftLock(): Enum.ContextActionResult
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
		blockShiftLock,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.RightControl
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
		if humanoid then
			humanoid.Died:Connect(forceExit)
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
