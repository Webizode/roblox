-- Owns the local tower: runs TowerModel at a fixed step, feeds it smoothed movement plus the automatic
-- stabiliser (TowerModel.assist), renders it, reports topples, replicates tilt and serves automatically at the
-- player's cart. Players only steer with WASD; F or the Steady button asks the server for a short rescue.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local TowerModel = require(Shared:WaitForChild("TowerModel"))
local TowerShape = require(Shared:WaitForChild("TowerShape"))
local Economy = require(Shared:WaitForChild("Economy"))
local Combat = require(Shared:WaitForChild("Combat"))
local Dash = require(Shared:WaitForChild("Dash"))
local Flavors = require(Config:WaitForChild("Flavors"))
local EconomyConfig = require(Config:WaitForChild("Economy"))
local Palette = require(Config:WaitForChild("Palette"))
local Tuning = require(Config:WaitForChild("Tower"))
local CombatConfig = require(Config:WaitForChild("Combat"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))
local Sfx = require(client:WaitForChild("Sfx"))

local TowerController = {}

-- runs right after the character moved, and before ShotRenderer (RENDER_PRIORITY + 1) checks for catches
TowerController.RENDER_PRIORITY = Enum.RenderPriority.Character.Value + 1
-- the visible towers are drawn after the movement pose (Character + 2) and the backpacks (Character + 3)
TowerController.VISUAL_PRIORITY = Enum.RenderPriority.Character.Value + 4

local STEP = 1 / Tuning.stepRate
local MAX_FRAME = 0.1 -- never simulate more than this per frame after a hitch
local TOPPLE_TIMEOUT = 2
local SCOOP_RADIUS = 1.05
local FADE_RAY = 60 -- studs along the middle of the screen that the own tower must not cover
local FADE_RESPONSE = 12 -- 1/s
local DASH_ACTION = "WobbleDash"
local SPRINT_ACTION = "WobbleSprint"
-- Roblox puts shift lock on Shift, which is the sprint here; it moves to Ctrl
local SHIFT_LOCK_KEYS = "LeftControl,RightControl"
local RESCUE_ACTION = "WobbleSteady"
-- above the default camera and player scripts, so no core binding can take these keys first
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 100

local player = Players.LocalPlayer
local registry
local state = TowerModel.newState(player.UserId % 100000)
local scoops: { string } = {}
local params = TowerModel.params(scoops, Flavors.byId, Tuning, 1)
local visual
local baseVelocityX, baseVelocityZ = 0, 0
local accumulator = 0
local toppledAt: number? = nil
local tiltTimer = 0
local sentEmptyTilt = true
local lastServeRequest = 0
-- a tower is only served after it has been carried outside the serve radius once, so catching next to the
-- cart does not instantly serve every single scoop
local serveArmed = false
local groundY = 1
local dashReadyAt = 0 -- local cooldown so the key cannot spam requests; the server has the final say
local rescueReadyAt = 0 -- same for the rescue
local sprinting = false
local towerFade = 0

local function coneLevel(): number
	local value = player:GetAttribute("ConeLevel")
	return if type(value) == "number" then value else 0
end

local function rootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The visible tower on the back: its bottom scoop rests in the waffle opening (Backpacks.opening, the same frame the
-- waffle is drawn from). While no waffle shows (knocked down), it falls back to the fixed offset from the root.
local function towerBase(root: BasePart): Vector3
	local character = root.Parent :: Model?
	local opening, ringRadius
	if character then
		opening, ringRadius = registry.Backpacks.opening(character)
	end
	if opening then
		local x, y, z =
			TowerShape.restingBase(opening.X, opening.Y, opening.Z, TowerVisual.SCOOP_SIZE / 2, ringRadius, Tuning)
		return Vector3.new(x, y, z)
	end
	return (root.CFrame * CFrame.new(0, Tuning.holdUp, -Tuning.holdForward)).Position
end

-- The catch column, straight above the character; the server checks catches from the same point.
local function catchBase(root: BasePart): Vector3
	return (root.CFrame * CFrame.new(0, Tuning.catchUp, -Tuning.catchForward)).Position
end

local function servePoint(): BasePart?
	local cartName = player:GetAttribute("CartName")
	local pier = workspace:FindFirstChild("Pier")
	local carts = pier and pier:FindFirstChild("Carts")
	local cart = carts and type(cartName) == "string" and carts:FindFirstChild(cartName)
	return cart and cart:FindFirstChild("ServePoint") :: BasePart?
end

local function flatten(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > 1e-4 then flat.Unit else Vector3.zero
end

local function onEvent(event: string)
	if event == "groan" then
		visual:setGroan(true)
		Sfx.play("groan")
	elseif event == "saved" then
		visual:setGroan(false)
		Sfx.play("saved")
		registry.Hud.toast("SAVED!", Palette.mint)
	elseif event == "toppled" then
		visual:setGroan(false)
		toppledAt = os.clock()
		visual:spill(Economy.keepOnTopple(#scoops, EconomyConfig), groundY)
		Sfx.play("topple")
		registry.Hud.toast("TOPPLED!", Palette.awning)
		Remotes.TowerToppled:FireServer()
	end
end

local function onTowerChanged(newScoops: { string }, reason: string)
	local previous = #scoops
	scoops = newScoops
	params = TowerModel.params(scoops, Flavors.byId, Tuning, Economy.coneStiffness(coneLevel(), EconomyConfig))

	if reason == "catch" and #scoops > previous then
		if toppledAt then
			-- a catch that was in flight when the tower toppled: the topple answer follows and rebuilds the tower
			return
		end
		TowerModel.landingKick(state, Tuning, #scoops)
		Sfx.catch(#scoops)
	elseif reason ~= "catch" then
		-- topple, serve or respawn: the server's list is the new starting point
		TowerModel.reset(state)
		visual:setGroan(false)
		toppledAt = nil
	end
	if #scoops == 0 then
		serveArmed = false
	end
	visual:setFlavors(scoops)
end

local function simulate(dt: number, humanoid: Humanoid)
	local variant = Tuning.variant
	local smoothing = Tuning.accelSmoothing
	accumulator = math.min(accumulator + dt, MAX_FRAME)
	while accumulator >= STEP do
		accumulator -= STEP
		local target = humanoid.MoveDirection * humanoid.WalkSpeed
		local ax, az
		baseVelocityX, baseVelocityZ, ax, az =
			TowerModel.baseVelocityStep(baseVelocityX, baseVelocityZ, target.X, target.Z, smoothing, STEP)

		local padX, padZ = TowerModel.assist(state, params, Tuning.variant, Tuning, STEP)
		local event = TowerModel.step(state, params, {
			ax = ax,
			az = az,
			padX = padX,
			padZ = padZ,
		}, variant, Tuning, STEP)
		if event then
			onEvent(event)
		end
	end
end

local function updateHud(root: BasePart)
	local tilt = TowerModel.tilt(state) / Tuning.tipAngle
	local camera = workspace.CurrentCamera
	local lean = Vector3.new(state.x, 0, state.z) / Tuning.tipAngle
	local leanX = lean:Dot(flatten(camera.CFrame.RightVector))
	local leanY = lean:Dot(flatten(camera.CFrame.LookVector))
	local rescue = if TowerModel.rescueActive(state)
		then "active"
		elseif os.clock() < rescueReadyAt then "cooldown"
		else "ready"
	registry.Hud.setBalance(tilt, state.groan > 0, #scoops > 0, leanX, leanY, rescue)

	local target = servePoint()
	local distance = if target then (root.Position - target.Position).Magnitude else math.huge
	registry.Hud.setCartTarget(target, distance <= EconomyConfig.serveRadius + 1)

	local steady = TowerModel.steadyBonus(state, Tuning)
	local value = Economy.serveValue(scoops, Flavors.byId, EconomyConfig, { steadyBonus = steady })
	registry.Hud.setTower(#scoops, value, steady)

	if target and #scoops > 0 and not state.toppled then
		if distance > EconomyConfig.serveRadius + 1 then
			serveArmed = true
		elseif serveArmed and distance <= EconomyConfig.serveRadius and os.clock() - lastServeRequest > 1 then
			lastServeRequest = os.clock()
			Remotes.ServeRequest:FireServer(steady)
		end
	end
end

local function replicateTilt(dt: number)
	tiltTimer += dt
	if tiltTimer < 1 / Tuning.tiltSendRate then
		return
	end
	tiltTimer = 0
	if #scoops > 0 then
		Remotes.TowerTilt:FireServer(state.x, state.z)
		sentEmptyTilt = false
	elseif not sentEmptyTilt then
		Remotes.TowerTilt:FireServer(0, 0)
		sentEmptyTilt = true
	end
end

-- The tower stands on the back, between the camera and the character: while it covers the middle of the screen
-- (the crosshair in combat mode, the character's head otherwise) it turns see-through for its owner only.
local function updateFade(dt: number)
	local camera = workspace.CurrentCamera
	local target = 0
	if camera and #scoops > 0 then
		local base, top = visual.base, visual:topPosition()
		local middle = (base + top) / 2
		local from = camera.CFrame.Position
		local to = from + camera.CFrame.LookVector * FADE_RAY
		local distance = Combat.closestToCapsule(
			from.X,
			from.Y,
			from.Z,
			to.X,
			to.Y,
			to.Z,
			middle.X,
			middle.Y,
			middle.Z,
			math.max(0, (top.Y - base.Y) / 2)
		)
		if distance < SCOOP_RADIUS + 0.4 then
			target = Tuning.ownTowerFade
		end
	end
	towerFade += (target - towerFade) * (1 - math.exp(-FADE_RESPONSE * dt))
	visual:setFade(towerFade)
end

local function onRenderStep(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootPart()
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	if toppledAt and os.clock() - toppledAt > TOPPLE_TIMEOUT then
		-- the server never answered the topple: fall back to the last list it sent
		TowerModel.reset(state)
		toppledAt = nil
		visual:setFlavors(scoops)
	end

	simulate(dt, humanoid)
	updateHud(root)
	replicateTilt(dt)
end

-- Draws the tower after the movement pose (Character + 2), so it stands in the waffle as it is drawn this frame,
-- leaning and all. The simulation and the catch column above do not depend on it.
local function onVisualStep(dt: number)
	local root = rootPart()
	if not root then
		return
	end
	visual:update(CFrame.new(towerBase(root)), state.x, state.z)
	updateFade(dt)
end

local function canCatch(): boolean
	if toppledAt or state.toppled then
		return false
	end
	return #scoops < Economy.capacity(coneLevel(), EconomyConfig)
end

-- A ring that bursts out under the character, seen by everyone: lemon for a dash, mint for a rescue.
local function burstRing(root: BasePart, colorHex: string)
	local ring = Instance.new("Part")
	ring.Name = "DashRing"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromHex(colorHex)
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.2, 3, 3)
	ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = TowerVisual.root()
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 11, 11),
		Transparency = 1,
	}):Play()
	task.delay(0.4, function()
		ring:Destroy()
	end)
end

-- The burst itself: a horizontal velocity for a moment, gravity untouched, moved by physics, never by teleporting.
-- It ends on the frame closest to the configured duration (not always a frame late), or earlier at a wall ahead: a
-- box cast in front of the root every frame (from the DashSystem model) stops it there instead of pressing into
-- the wall. At the end the horizontal speed drops straight back to the humanoid's own (walking or sprinting), or to
-- zero at a wall, so the dash stops crisply instead of sliding on; a knockback that is running keeps its velocity.
-- Like in the model, the humanoid cannot ragdoll or fall over during the burst.
local function dashBurst(root: BasePart, humanoid: Humanoid, dirX: number, dirZ: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DashVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(dirX, dirZ) * Tuning.dash.speed
	velocity.MaxForce = root.AssemblyMass * Tuning.dash.acceleration
	velocity.Parent = root

	local ragdollWas = humanoid:GetStateEnabled(Enum.HumanoidStateType.Ragdoll)
	local fallingDownWas = humanoid:GetStateEnabled(Enum.HumanoidStateType.FallingDown)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance }
	params.RespectCanCollide = true
	local castSize = root.Size + Vector3.new(0.35, 0.1, 0.35)
	local ahead = Vector3.new(dirX, 0, dirZ)

	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local wall = false
		if root.Parent then
			local reach = math.min(Tuning.dash.speed * dt + 0.4, 6)
			local hit = workspace:Blockcast(root.CFrame, castSize, ahead * reach, params)
			wall = hit ~= nil and Dash.blocks(hit.Normal.X, hit.Normal.Y, hit.Normal.Z, dirX, dirZ)
		end
		if not wall and elapsed < Tuning.dash.duration - dt / 2 and root.Parent then
			return
		end
		connection:Disconnect()
		velocity:Destroy()
		attachment:Destroy()
		if humanoid.Parent then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, ragdollWas)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, fallingDownWas)
		end
		if not root.Parent or root:FindFirstChild("KnockbackVelocity") then
			return
		end
		local current = root.AssemblyLinearVelocity
		local flat = Vector3.new(current.X, 0, current.Z)
		local cap = if wall then 0 else humanoid.WalkSpeed
		if flat.Magnitude > cap then
			flat = if cap > 0 then flat.Unit * cap else Vector3.zero
			root.AssemblyLinearVelocity = Vector3.new(flat.X, current.Y, flat.Z)
		end
	end)
end

local function onDash(who: Player, dirX: number, dirZ: number)
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	burstRing(root, Palette.lemon)
	registry.MovementController.dash(character :: Model, Tuning.dash.duration, dirX, dirZ)
	if who ~= player then
		return
	end
	dashReadyAt = os.clock() + Tuning.dash.cooldown
	local humanoid = (character :: Model):FindFirstChildOfClass("Humanoid")
	if humanoid then
		dashBurst(root, humanoid, dirX, dirZ)
	end
	if #scoops > 0 and not state.toppled and not toppledAt then
		TowerModel.dashKick(state, Tuning.dash, #scoops, dirX, dirZ)
	end
end

-- Q on PC, the dash button on touch screens. Asks the server; the burst happens when it agrees.
local function requestDash(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootPart()
	if not humanoid or not root or humanoid.Health <= 0 or os.clock() < dashReadyAt then
		return Enum.ContextActionResult.Sink
	end
	local direction = flatten(humanoid.MoveDirection)
	if direction == Vector3.zero then
		direction = flatten(root.CFrame.LookVector)
	end
	if direction == Vector3.zero then
		return Enum.ContextActionResult.Sink
	end
	dashReadyAt = os.clock() + Tuning.dash.cooldown
	Remotes.Dash:FireServer(direction.X, direction.Z)
	return Enum.ContextActionResult.Sink
end

local function onRescue(who: Player)
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	burstRing(root, Palette.mint)
	if who ~= player then
		return
	end
	rescueReadyAt = os.clock() + Tuning.rescue.duration + Tuning.rescue.cooldown
	TowerModel.rescue(state, Tuning.rescue.duration)
	Sfx.play("saved")
end

-- F on PC, the Steady button on touch screens. One press is one rescue: only the Begin of an input counts, so
-- holding the key does nothing more, and the server checks the cooldown before the rescue starts.
local function requestRescue(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if #scoops == 0 or state.toppled or toppledAt or os.clock() < rescueReadyAt then
		return Enum.ContextActionResult.Sink
	end
	rescueReadyAt = os.clock() + Tuning.rescue.duration + Tuning.rescue.cooldown
	Remotes.Rescue:FireServer()
	return Enum.ContextActionResult.Sink
end

local function setSprinting(on: boolean)
	if on == sprinting then
		return
	end
	sprinting = on
	Remotes.SetSprint:FireServer(on)
	registry.MovementController.setSprinting(on)
end

-- Shift sprints while held; L3 and the Sprint button on touch screens toggle it. The server sets the speed.
local function onSprintInput(_: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local toggles = input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonL3
	if toggles then
		if inputState == Enum.UserInputState.Begin then
			setSprinting(not sprinting)
		end
	elseif inputState == Enum.UserInputState.Begin then
		setSprinting(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setSprinting(false)
	end
	-- Sink: Shift must not reach anything else
	return Enum.ContextActionResult.Sink
end

-- Uses the PlayerModule's own setting for the shift-lock keys, so shift lock keeps working, just on Ctrl.
local function moveShiftLockToCtrl()
	local ok, boundKeys = pcall(function()
		return player
			:WaitForChild("PlayerScripts")
			:WaitForChild("PlayerModule", 10)
			:WaitForChild("CameraModule", 10)
			:WaitForChild("MouseLockController", 10)
			:WaitForChild("BoundKeys", 10)
	end)
	if ok and boundKeys and boundKeys:IsA("StringValue") then
		boundKeys.Value = SHIFT_LOCK_KEYS
	end
end

function TowerController.Init(reg)
	registry = reg
	visual = TowerVisual.new("MyTower")
end

function TowerController.Start()
	local pier = workspace:WaitForChild("Pier", 30)
	local deck = pier and pier:WaitForChild("Deck", 30)
	if deck and deck:IsA("BasePart") then
		groundY = deck.Position.Y + deck.Size.Y / 2
	end

	Remotes.TowerChanged.OnClientEvent:Connect(onTowerChanged)
	Remotes.Served.OnClientEvent:Connect(function(who: Player, count: number, value: number)
		if who == player then
			Sfx.play("serve")
			registry.Hud.toast(string.format("SERVE! +%d", value), Palette.lemon)
		elseif count >= 15 then
			registry.Hud.toast(string.format("%s served %d scoops!", who.DisplayName, count), Palette.strawberry)
		end
	end)
	Remotes.Dash.OnClientEvent:Connect(onDash)
	ContextActionService:BindActionAtPriority(
		DASH_ACTION,
		requestDash,
		true, -- creates the dash button on touch screens
		ACTION_PRIORITY,
		Enum.KeyCode.Q
	)
	ContextActionService:SetTitle(DASH_ACTION, "Dash")

	ContextActionService:BindActionAtPriority(
		SPRINT_ACTION,
		onSprintInput,
		true, -- creates the Sprint button on touch screens
		ACTION_PRIORITY,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.ButtonL3
	)
	ContextActionService:SetTitle(SPRINT_ACTION, "Sprint")
	-- the server resets sprint on respawn, so the client does too
	player.CharacterAdded:Connect(function()
		sprinting = false
		registry.MovementController.setSprinting(false)
	end)
	task.spawn(moveShiftLockToCtrl)

	Remotes.Rescue.OnClientEvent:Connect(onRescue)
	ContextActionService:BindActionAtPriority(
		RESCUE_ACTION,
		requestRescue,
		true, -- creates the Steady button on touch screens
		ACTION_PRIORITY,
		Enum.KeyCode.F
	)
	ContextActionService:SetTitle(RESCUE_ACTION, "Steady")

	RunService:BindToRenderStep("WobbleTower", TowerController.RENDER_PRIORITY, onRenderStep)
	RunService:BindToRenderStep("WobbleTowerVisual", TowerController.VISUAL_PRIORITY, onVisualStep)
end

-- The tower column in world space (flat x, y, z list, see TowerShape.column) plus the current tilt, or nil when
-- the tower cannot catch right now. Built from the character's current position, not last frame's visuals.
function TowerController.catchColumn(): ({ number }?, number, number)
	local root = rootPart()
	if not root or not canCatch() then
		return nil, 0, 0
	end
	local base = catchBase(root)
	local offsets = TowerShape.column(#scoops, state.x, state.z, Tuning)
	local points = table.create(#offsets)
	for index = 1, #offsets, 3 do
		points[index] = base.X + offsets[index]
		points[index + 1] = base.Y + offsets[index + 1]
		points[index + 2] = base.Z + offsets[index + 2]
	end
	return points, state.x, state.z
end

-- An ice-ball hit announced by the server: shove the tower along the ball's flight. The server decided the power.
function TowerController.hit(dirX: number, dirZ: number, power: number)
	if #scoops > 0 and not state.toppled and not toppledAt then
		TowerModel.hitKick(state, CombatConfig, #scoops, dirX, dirZ, power)
	end
end

-- Where the next scoop sits on the tower, used to show a claimed scoop until the server confirms it.
function TowerController.topPosition(): Vector3?
	local root = rootPart()
	if not root or toppledAt or state.toppled then
		return nil
	end
	return visual:topPosition() -- where the tower was drawn this frame
end

return TowerController
