-- Owns the local tower: runs TowerModel at a fixed step, feeds it smoothed movement plus pad/gyro input,
-- renders it, reports topples, replicates tilt and serves automatically at the player's cart.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local groundY = 1

local function variantKey(): string
	local key = player:GetAttribute("ControlVariant")
	return if type(key) == "string" and Tuning.variants[key] then key else Tuning.defaultVariant
end

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

-- Corrective input in world space, from the pad (screen space) or the device tilt.
local function correctiveInput(variant): (number, number)
	local screenX, screenY = 0, 0
	if variant.usesGyro and UserInputService.AccelerometerEnabled then
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
	elseif variant.usesPad or variant.usesGyro then
		-- gyro without an accelerometer (PC) falls back to the pad
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

local function padMode(variant): "interactive" | "display"
	if variant.usesPad or (variant.usesGyro and not UserInputService.AccelerometerEnabled) then
		return "interactive"
	end
	return "display"
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
	local variant = Tuning.variants[variantKey()]
	local smoothing = variant.accelSmoothing or Tuning.accelSmoothing
	accumulator = math.min(accumulator + dt, MAX_FRAME)
	while accumulator >= STEP do
		accumulator -= STEP
		local target = humanoid.MoveDirection * humanoid.WalkSpeed
		local ax, az
		baseVelocityX, baseVelocityZ, ax, az =
			TowerModel.baseVelocityStep(baseVelocityX, baseVelocityZ, target.X, target.Z, smoothing, STEP)

		local padX, padZ = correctiveInput(variant)
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

	local steady = TowerModel.steadyBonus(state, Tuning)
	local value = Economy.serveValue(scoops, Flavors.byId, EconomyConfig, { steadyBonus = steady })
	registry.Hud.setTower(#scoops, value, steady)

	local target = servePoint()
	registry.Hud.setCartTarget(target)
	if target and #scoops > 0 and not state.toppled then
		local distance = (root.Position - target.Position).Magnitude
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

	registry.BalancePad.setMode(padMode(Tuning.variants[variantKey()]))

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
	player:GetAttributeChangedSignal("ControlVariant"):Connect(function()
		gyroBase = nil -- recalibrate the neutral phone angle on every switch
	end)

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
