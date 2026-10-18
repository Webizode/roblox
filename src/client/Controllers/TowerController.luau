-- Owns the local tower: runs TowerModel at a fixed step, feeds it smoothed movement plus pad/key/gyro input,
-- renders it, reports topples, replicates tilt and serves automatically at the player's cart.
-- The control scheme is picked automatically from the device and the settings (see controlSchemes in
-- Config/Tower); the HUD never shows or switches it.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local TowerModel = require(Shared:WaitForChild("TowerModel"))
local TowerShape = require(Shared:WaitForChild("TowerShape"))
local Economy = require(Shared:WaitForChild("Economy"))
local Flavors = require(Config:WaitForChild("Flavors"))
local EconomyConfig = require(Config:WaitForChild("Economy"))
local Palette = require(Config:WaitForChild("Palette"))
local Tuning = require(Config:WaitForChild("Tower"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))
local Sfx = require(client:WaitForChild("Sfx"))

local TowerController = {}

-- runs right after the character moved, and before ShotRenderer (RENDER_PRIORITY + 1) checks for catches
TowerController.RENDER_PRIORITY = Enum.RenderPriority.Character.Value + 1

local STEP = 1 / Tuning.stepRate
local MAX_FRAME = 0.1 -- never simulate more than this per frame after a hitch
local TOPPLE_TIMEOUT = 2
local DASH_ACTION = "WobbleDash"
local SCHEME_REPORT_DELAY = 1 -- a scheme is reported to the kill-test log once it has been stable this long

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
local gyroBase: Vector3? = nil
local gyroSeen = false -- the motion sensor has delivered a real reading, so tilt controls can work here
local scheme = "walk"
local schemeSince = 0
local reportedScheme: string? = nil
local groundY = 1
local dashReadyAt = 0 -- local cooldown so the key cannot spam requests; the server has the final say

local function coneLevel(): number
	local value = player:GetAttribute("ConeLevel")
	return if type(value) == "number" then value else 0
end

local function rootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function towerBase(root: BasePart): Vector3
	return (root.CFrame * CFrame.new(0, Tuning.holdUp, -Tuning.holdForward)).Position
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

-- Device gravity as a unit vector in screen axes (x right, y up), or nil while the sensor has no reading.
-- The device reports in its own axes; in landscape its long axis runs along the screen, and the two landscape
-- orientations are 180 degrees apart. Signs come from Config/Tower and are unverified on real phones.
local function screenGravity(): Vector3?
	local gravity = UserInputService:GetDeviceGravity().Position
	if gravity.Magnitude < 0.5 then
		return nil
	end
	gravity = gravity.Unit
	local orientation = player.PlayerGui.CurrentScreenOrientation
	local x, y = gravity.X, gravity.Y
	if orientation == Enum.ScreenOrientation.LandscapeLeft then
		x, y = -gravity.Y, gravity.X
	elseif orientation == Enum.ScreenOrientation.LandscapeRight then
		x, y = gravity.Y, -gravity.X
	end
	return Vector3.new(x * Tuning.gyroSignX, y * Tuning.gyroSignY, gravity.Z)
end

local function gyroAvailable(): boolean
	if not UserInputService.AccelerometerEnabled then
		return false
	end
	if not gyroSeen then
		gyroSeen = screenGravity() ~= nil
	end
	return gyroSeen
end

-- First match wins: the pad when it is switched on, keys when a keyboard is connected, tilt when the device has a
-- working motion sensor and tilt controls are on, otherwise balancing by walking.
local function pickScheme(): string
	if registry.Settings.get("balancePad") then
		return "pad"
	elseif Tuning.keyboardPad and UserInputService.KeyboardEnabled then
		return "keys"
	elseif registry.Settings.get("tiltControls") and gyroAvailable() then
		return "gyro"
	end
	return "walk"
end

local function updateScheme()
	local picked = pickScheme()
	if picked ~= scheme then
		scheme = picked
		schemeSince = os.clock()
		gyroBase = nil -- recalibrate the neutral phone angle on every change
		registry.BalancePad.setMode(if picked == "pad" then "pad" elseif picked == "keys" then "keys" else "off")
		registry.Hud.setControls(picked)
	end
	-- only for the kill-test log; waiting until it settles keeps a quick back-and-forth in the settings quiet
	if scheme ~= reportedScheme and os.clock() - schemeSince >= SCHEME_REPORT_DELAY then
		reportedScheme = scheme
		Remotes.ControlScheme:FireServer(scheme)
	end
end

-- Corrective input in world space, from the pad or keys (screen space) or the device tilt.
local function correctiveInput(): (number, number)
	local screenX, screenY = 0, 0
	if scheme == "gyro" then
		if #scoops == 0 then
			-- the neutral angle is taken when the next tower starts, not while the phone is still tilted from
			-- the tower just served
			gyroBase = nil
			return 0, 0
		end
		local gravity = screenGravity()
		if gravity then
			if not gyroBase then
				gyroBase = gravity
			end
			local delta = gravity - gyroBase
			screenX = math.clamp(delta.X * Tuning.gyroGain, -1, 1)
			screenY = math.clamp(delta.Y * Tuning.gyroGain, -1, 1)
		end
	elseif scheme == "pad" or scheme == "keys" then
		screenX, screenY = registry.BalancePad.get()
	else
		return 0, 0
	end

	local camera = workspace.CurrentCamera
	local right = flatten(camera.CFrame.RightVector)
	local forward = flatten(camera.CFrame.LookVector)
	local world = right * screenX + forward * screenY
	return world.X, world.Z
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
	local variant = Tuning.variants[Tuning.controlSchemes[scheme]]
	local smoothing = variant.accelSmoothing or Tuning.accelSmoothing
	accumulator = math.min(accumulator + dt, MAX_FRAME)
	while accumulator >= STEP do
		accumulator -= STEP
		local target = humanoid.MoveDirection * humanoid.WalkSpeed
		local ax, az
		baseVelocityX, baseVelocityZ, ax, az =
			TowerModel.baseVelocityStep(baseVelocityX, baseVelocityZ, target.X, target.Z, smoothing, STEP)

		local padX, padZ = correctiveInput()
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
	registry.BalancePad.setLevel(tilt, state.groan > 0, leanX, leanY)
	-- with the pad on screen its ring already shows the level
	registry.Hud.setBalance(tilt, state.groan > 0, #scoops > 0 and scheme ~= "pad", leanX, leanY)

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

local function onRenderStep(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootPart()
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	updateScheme()

	if toppledAt and os.clock() - toppledAt > TOPPLE_TIMEOUT then
		-- the server never answered the topple: fall back to the last list it sent
		TowerModel.reset(state)
		toppledAt = nil
		visual:setFlavors(scoops)
	end

	simulate(dt, humanoid)
	visual:update(CFrame.new(towerBase(root)), state.x, state.z)
	updateHud(root)
	replicateTilt(dt)
end

local function canCatch(): boolean
	if toppledAt or state.toppled then
		return false
	end
	return #scoops < Economy.capacity(coneLevel(), EconomyConfig)
end

-- A lemon ring that bursts out under the character, seen by everyone.
local function dashEffect(root: BasePart)
	local ring = Instance.new("Part")
	ring.Name = "DashRing"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromHex(Palette.lemon)
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

-- The burst itself: a horizontal velocity for a moment, gravity untouched, then the humanoid takes over again.
local function dashBurst(root: BasePart, dirX: number, dirZ: number)
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
	velocity.MaxForce = root.AssemblyMass * 2000
	velocity.Parent = root
	task.delay(Tuning.dash.duration, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
end

local function onDash(who: Player, dirX: number, dirZ: number)
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	dashEffect(root)
	if who ~= player then
		return
	end
	dashReadyAt = os.clock() + Tuning.dash.cooldown
	dashBurst(root, dirX, dirZ)
	Sfx.play("dash")
	if #scoops > 0 and not state.toppled and not toppledAt then
		TowerModel.dashKick(state, Tuning.dash, #scoops, dirX, dirZ)
	end
end

-- Shift on PC, the dash button on touch screens. Asks the server; the burst happens when it agrees.
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
	-- Sink: Shift would otherwise also toggle shift lock
	return Enum.ContextActionResult.Sink
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
	schemeSince = os.clock()

	Remotes.Dash.OnClientEvent:Connect(onDash)
	ContextActionService:BindActionAtPriority(
		DASH_ACTION,
		requestDash,
		true, -- creates the dash button on touch screens
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift
	)
	ContextActionService:SetTitle(DASH_ACTION, "Dash")

	RunService:BindToRenderStep("WobbleTower", TowerController.RENDER_PRIORITY, onRenderStep)
end

-- The tower column in world space (flat x, y, z list, see TowerShape.column) plus the current tilt, or nil when
-- the tower cannot catch right now. Built from the character's current position, not last frame's visuals.
function TowerController.catchColumn(): ({ number }?, number, number)
	local root = rootPart()
	if not root or not canCatch() then
		return nil, 0, 0
	end
	local base = towerBase(root)
	local offsets = TowerShape.column(#scoops, state.x, state.z, Tuning)
	local points = table.create(#offsets)
	for index = 1, #offsets, 3 do
		points[index] = base.X + offsets[index]
		points[index + 1] = base.Y + offsets[index + 1]
		points[index + 2] = base.Z + offsets[index + 2]
	end
	return points, state.x, state.z
end

-- Where the next scoop sits on the tower, used to show a claimed scoop until the server confirms it.
function TowerController.topPosition(): Vector3?
	local root = rootPart()
	if not root or toppledAt or state.toppled then
		return nil
	end
	local ox, oy, oz = TowerShape.top(#scoops, state.x, state.z, Tuning)
	return towerBase(root) + Vector3.new(ox, oy, oz)
end

return TowerController
