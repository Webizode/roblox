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
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Combat = require(Shared:WaitForChild("Combat"))
local BallFlight = require(Shared:WaitForChild("BallFlight"))
local AimRules = require(Shared:WaitForChild("AimRules"))
local BallMotion = require(Shared:WaitForChild("BallMotion"))
local MapQuery = require(Shared:WaitForChild("MapQuery"))
local ArenaZone = require(Shared:WaitForChild("ArenaZone"))
local MouseRules = require(Shared:WaitForChild("MouseRules"))
local CombatConfig = require(Config:WaitForChild("Combat"))
local MapConfig = require(Config:WaitForChild("Map"))
local Features = require(Config:WaitForChild("Features"))
local Palette = require(Config:WaitForChild("Palette"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))
local CombatCamera = require(client:WaitForChild("CombatCamera"))
local RobloxControls = require(client:WaitForChild("RobloxControls"))
local Sfx = require(client:WaitForChild("Sfx"))
local UiKit = require(client:WaitForChild("UiKit"))
local Keys = require(client:WaitForChild("Keys"))
local BallVisual = require(client:WaitForChild("BallVisual"))
local Settings = require(client:WaitForChild("Settings"))
local VfxEffects = client:WaitForChild("Vfx"):WaitForChild("Effects")
local PerfectThrow = require(VfxEffects:WaitForChild("PerfectThrow"))
local ThrowTrail = require(VfxEffects:WaitForChild("ThrowTrail"))

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
	path: BallFlight.Ball, -- where it flies: the server's flight, homing in on `target` like there
	target: Player?,
	assist: any?, -- the homing strength (Config/Combat homing.devices), nil: none
	perfect: boolean, -- a perfect throw: the thrower hears the perfect sound only when it hits
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
local cancelCharge: (releaseButton: boolean) -> () -- defined with the charge functions below; the knockdown needs it earlier

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

-- With Features.debugThrow: a small magenta dot where the throw aims (the point under the crosshair it was sent to),
-- for 3 s, so a test can see where the ball should cross the crosshair.
local function debugAimDot(position: Vector3)
	if not Features.debugThrow then
		return
	end
	local dot = Instance.new("Part")
	dot.Name = "AimDebugDot"
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.new(0.4, 0.4, 0.4)
	dot.Material = Enum.Material.Neon
	dot.Color = Color3.fromRGB(255, 0, 255)
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	dot.CastShadow = false
	dot.Position = position
	dot.Parent = workspace:FindFirstChild("LocalVisuals") or workspace
	task.delay(3, function()
		dot:Destroy()
	end)
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

local function onThrown(
	id: number,
	thrower: Player,
	origin: Vector3,
	velocity: Vector3,
	t0: number,
	perfect: boolean?,
	target: Player?,
	device: string?
)
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
	ThrowTrail.dress(flight, nil) -- the ice ball is vanilla so far; a thrown flavor goes in here
	if perfect then
		PerfectThrow.dress(flight) -- a perfect throw glows green for everybody
	end
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	balls[id] = {
		part = part,
		model = model,
		flight = flight,
		facing = if flat.Magnitude > 1e-3 then CFrame.lookAt(Vector3.zero, flat) else CFrame.identity,
		path = BallFlight.new(origin.X, origin.Y, origin.Z, velocity.X, velocity.Y, velocity.Z),
		target = if typeof(target) == "Instance" and target:IsA("Player") then target else nil,
		assist = if type(device) == "string" then CombatConfig.homing.devices[device] else nil,
		perfect = perfect == true,
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
	-- combat mode stays on (kill test 13.11.2026: getting up out of it felt like a second punishment); the charge
	-- drops, a held button charges again after getting up (canThrow waits for downUntil), the body lies still
	cancelCharge(false)
	CombatCamera.pauseFacing(downUntil)
	if not RobloxControls.setEnabled(false) then
		return
	end
	task.delay(CombatConfig.knockdownTime, function()
		if os.clock() >= downUntil - 0.05 then
			RobloxControls.setEnabled(true)
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
	shielded: boolean?,
	headshot: boolean?
)
	local ball = balls[id]
	local perfect = ball ~= nil and ball.perfect
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
					(position - Vector3.new(ball.path.ox, ball.path.oy, ball.path.oz)).Magnitude,
					if victim then "hit " .. victim.Name else "world or out of range"
				)
			)
		end
	end
	-- the splash, the flash and the stars of a hit are the effects' (VfxController, from the same message)
	if not victim then
		return
	end
	if shielded then
		-- the victim stands in their cart's safe zone: the ball lands, nothing else happens
		if thrower == player or victim == player then
			UiKit.Toast.show("SAFE!", "normal", "safe")
		end
		return
	end

	local character = victim.Character
	local strength = if knockdown then power * CombatConfig.knockdownBoost else power
	if character then
		registry.MovementController.stumble(character, dirX, dirZ, strength)
		if knockdown then
			registry.MovementController.knockDown(character, CombatConfig.knockdownTime)
		else
			registry.MovementController.hitReaction(character)
		end
	end
	if thrower == player and victim ~= player then
		-- the thrower's hit sounds (Config/Sounds): a squish for every hit, the sparkle on top of it for a perfect throw
		-- (since the kill test of 13.11.2026 only when it hits, no longer at the release), the bell for a headshot
		if headshot then
			-- its own sound and word; a knockdown still says so in the feed (HitFeedback)
			Sfx.play("headshot")
			UiKit.Toast.show("HEADSHOT!", "good", "ammo")
		else
			Sfx.play("hitConfirm")
		end
		if perfect then
			Sfx.play("perfectHit")
		end
		if not headshot then
			UiKit.Toast.show(if knockdown then "KNOCKDOWN!" else "HIT!", if knockdown then "good" else "normal", "ammo")
		end
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
	if not knockdown then
		-- a knockdown does not shake the tower: the server spills it itself (TowerService.knockdownSpill) and the rest
		-- stands up straight again
		registry.TowerController.hit(dirX, dirZ, strength)
	end
	CombatCamera.hit() -- the aim camera lets go at once; the charge itself goes on
	if knockdown then
		knockDown()
		-- what is left on the tower cannot topple on its own while down and for a moment after getting up
		registry.TowerController.knockedDown(CombatConfig.knockdownTime)
		UiKit.Toast.show("KNOCKED DOWN!", "bad", "ammoEmpty")
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
		local flight = math.clamp(t, 0, CombatConfig.maxFlight)
		-- on along the server's flight: the same steps, homing in on where its target stands here
		local path = ball.path
		local body = ball.target and ball.target.Character
		local aimRoot = body and body:FindFirstChild("HumanoidRootPart") :: BasePart?
		local homeTo = if aimRoot and ball.assist
			then { x = aimRoot.Position.X, y = aimRoot.Position.Y, z = aimRoot.Position.Z }
			else nil
		BallFlight.advance(path, flight - path.t, homeTo, ball.assist, CombatConfig)
		local x, y, z = path.x, path.y, path.z
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
function cancelCharge(releaseButton: boolean)
	if charging then
		registry.ThrowAnimator.charge(false)
	end
	charging = false
	CombatCamera.setCharge(nil) -- after a throw and after a dropped charge alike
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

-- The world point the throw aims at: under `screen` (viewport pixels), or a point far along that ray. The ray
-- ignores the own character, the own tower and every drawn scoop and ball (LocalVisuals), everything the ball would
-- fly through anyway (parts without collision and the thin
-- decoration of Config/Map, MapQuery.throwRaycast), and
-- everything between the camera and the character, so only what lies ahead of the player can be the target. A rival
-- the ray passes over (body or head, Combat.aimDepth) is the target before the map behind them.
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
	local length = if result then (result.Position - origin).Magnitude else CombatConfig.aimDistance
	-- a rival under the crosshair: the map ray flies through their head, limbs and hair (they do not collide), so the
	-- aim goes to the crosshair's point at their depth, where the ball from the hand then crosses the crosshair ray
	local bodies: { Combat.AimBody } = {}
	for _, other in Players:GetPlayers() do
		local body = other ~= player and other.Character
		local otherRoot = body and body:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = body and body:FindFirstChildOfClass("Humanoid")
		if otherRoot and humanoid and humanoid.Health > 0 then
			local head = (body :: Model):FindFirstChild("Head") :: BasePart?
			local p = otherRoot.Position
			table.insert(bodies, {
				x = p.X,
				y = p.Y,
				z = p.Z,
				head = if head
					then {
						x = head.Position.X,
						y = head.Position.Y,
						z = head.Position.Z,
						radius = CombatConfig.headRadius, -- the server's head zone, the same for every avatar
					}
					else nil,
			})
		end
	end
	local depth = Combat.aimDepth(origin.X, origin.Y, origin.Z, unit.X, unit.Y, unit.Z, length, bodies, CombatConfig)
	if depth then
		return origin + unit * depth
	end
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
			debugAimDot(aim)
			lastRequestAt = os.clock()
			lastThrowAt = os.clock()
			-- the input in use picks the strength of the ball's homing (the server checks it and the setting)
			Remotes.ThrowIceBall:FireServer(aim.X, aim.Y, aim.Z, strength, perfect, Settings.inputKind())
			CombatCamera.thrown(perfect) -- the aim (above) is taken before the camera moves
			-- no perfect sound here: it plays when a perfect throw hits (onResolved); the release only has the plain
			-- throw sound, everybody sees the perfect throw's green glitter (Vfx)
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
	CombatCamera.setCharge(held) -- the aim camera follows the charge every frame
end

-- Whether the local character stands in the arena (ArenaZone, the same function the server asks).
local function inArena(): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and ArenaZone.contains(root.Position.X, root.Position.Z, MapConfig.arena)
end

-- Holds the mouse in the middle of the screen and keeps the cursor hidden (the crosshair is the cursor) while combat
-- mode is on, as MouseRules.mode says. Runs after the camera scripts every frame, because they set the mouse
-- behaviour and the cursor themselves (a held right mouse button pans Roblox's camera and shows the cursor).
local function onMouseStep()
	local here = inArena()
	local mode = MouseRules.mode(
		combatMode,
		here,
		UserInputService.MouseEnabled,
		UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	)
	if MouseRules.mustLeaveCombat(combatMode, here) then
		-- out of the arena: combat mode ends, and exitCombatMode frees the mouse for the teleport buttons
		forceExit()
		UiKit.Toast.show("COMBAT OFF", "normal", "safe")
		return
	end
	if mode ~= "locked" then
		return
	end
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
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

-- Whether Roblox's own shift lock (Ctrl) is on (RobloxControls). If that cannot be read, it counts as off, so
-- leaving combat mode always frees the mouse.
local function shiftLockOn(): boolean
	return RobloxControls.shiftLockOn()
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
		false, -- touch screens use the Throw button of TouchControls
		ACTION_PRIORITY,
		table.unpack(Keys.inputs("throw"))
	)
	registry.TouchControls.setShown("throw", true)
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
	registry.TouchControls.setShown("throw", false)
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
		if not MouseRules.canEnterCombat(inArena()) then
			UiKit.Toast.show("ARENA ONLY", "warn", "arena")
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

-- Whether the local player is in combat mode right now (the client's own state: on with R, off at once with every
-- way it ends), for the HUD's ice balls and the navigation.
function CombatController.inCombatMode(): boolean
	return combatMode
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
		false, -- touch screens use the Combat button of TouchControls
		ACTION_PRIORITY,
		table.unpack(Keys.inputs("combat"))
	)
	-- the touch buttons call the same functions as the keys
	registry.TouchControls.bind("combat", function(state)
		onModeInput(MODE_ACTION, state)
	end)
	registry.TouchControls.bind("throw", function(state)
		requestThrow(THROW_ACTION, state)
	end)
	RunService.RenderStepped:Connect(onRenderStep)
	RunService.RenderStepped:Connect(onAimStep)
	-- no first person in the arena (Config/Combat camera.arenaMinZoom), in and out of combat mode
	RunService.RenderStepped:Connect(function()
		CombatCamera.limitZoom(inArena())
	end)

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
