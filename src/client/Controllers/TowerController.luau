-- Owns the local tower: runs TowerModel at a fixed step, feeds it smoothed movement plus the automatic
-- stabiliser (TowerModel.assist), renders it, reports topples, replicates tilt and serves automatically at the
-- player's cart. Players only steer with WASD; holding F or the Steady button takes the steady stance, which runs on
-- an energy bar (Stance) and costs speed and sprint; a throw or a dash ends it and locks it for a moment.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local TowerModel = require(Shared:WaitForChild("TowerModel"))
local Stance = require(Shared:WaitForChild("Stance"))
local DashCharges = require(Shared:WaitForChild("DashCharges"))
local TowerShape = require(Shared:WaitForChild("TowerShape"))
local Economy = require(Shared:WaitForChild("Economy"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))
local ScoopChest = require(Shared:WaitForChild("ScoopChest"))
local ChestConfig = require(Config:WaitForChild("Chest"))
local Dash = require(Shared:WaitForChild("Dash"))
local ArenaZone = require(Shared:WaitForChild("ArenaZone"))
local Features = require(Config:WaitForChild("Features"))
local Flavors = require(Config:WaitForChild("Flavors"))
local EconomyConfig = require(Config:WaitForChild("Economy"))
local UpgradesConfig = require(Config:WaitForChild("Upgrades"))
local Palette = require(Config:WaitForChild("Palette"))
local Tuning = require(Config:WaitForChild("Tower"))
local CombatConfig = require(Config:WaitForChild("Combat"))
local MapConfig = require(Config:WaitForChild("Map"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))
local RobloxControls = require(client:WaitForChild("RobloxControls"))
local Sfx = require(client:WaitForChild("Sfx"))
local UiKit = require(client:WaitForChild("UiKit"))
local Keys = require(client:WaitForChild("Keys"))
local SavedVfx = require(client:WaitForChild("Vfx"):WaitForChild("Effects"):WaitForChild("Saved"))

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
local FADE_RESPONSE = 8 -- 1/s
-- a scoop turns see-through when the middle of the screen comes closer than FADE_IN to it and solid again only
-- beyond FADE_OUT; one threshold made a wobbling tower flicker on and off (studs beyond the scoop radius)
local FADE_IN, FADE_OUT = 0.4, 1.2
local DASH_ACTION = "WobbleDash"
local SPRINT_ACTION = "WobbleSprint"
-- Roblox puts shift lock on Shift, which is the sprint here; it moves to Ctrl
local SHIFT_LOCK_KEYS = { Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl }
local STANCE_ACTION = "WobbleSteady"
-- an "off" from the server this soon after a start may still be the answer to the previous stance
local STANCE_ECHO = 0.5
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
local lastPaidServeAt = -math.huge
local tiltTimer = 0
local sentEmptyTilt = true
local lastServeRequest = 0
-- a tower is only served after it has been carried outside the serve radius once, so catching next to the
-- cart does not instantly serve every single scoop
local serveArmed = false
-- the dash charges counted here too (DashCharges), so the key cannot spam requests and the HUD's bar shows them; the
-- server keeps the ones that count
local dashCharges = DashCharges.new(Tuning.dash)
local dashRunningUntil = 0 -- no dash request while one still runs
local meter = Stance.new() -- the steady stance's energy bar, predicted here; the server's counts
local stanceStartedAt = 0
local sprinting = false
local scoopFades: { number } = {} -- per scoop of the own tower
local covering: { boolean } = {} -- per scoop: it covers the middle of the screen (with the hysteresis above)
local stanceEnded: (tellServer: boolean) -> ()
local stopStance: (tellServer: boolean) -> ()

-- The sprint look (wider view) follows the sprint key, but not while the stance holds the sprint back.
local function syncSprintLook()
	registry.MovementController.setSprinting(sprinting and not meter.active)
end

-- The own level of an upgrade (the Upgrade_<id> attributes DataService publishes; 0 until the save is loaded).
local function upgradeLevel(id: string): number
	local value = player:GetAttribute("Upgrade_" .. id)
	return if type(value) == "number" then value else 0
end

-- How many scoops the cone holds (the Big Cone upgrade, the same on the server).
local function capacity(): number
	return Upgrades.value("cone", upgradeLevel("cone"), UpgradesConfig)
end

-- The tower tuning with the Stability upgrade's walkHeavyFrom (Config/Upgrades tracks.stability), one copy per level.
local stabilityTunings: { [number]: any } = {}
local function stableTuning(): any
	local level = upgradeLevel("stability")
	if level == 0 then
		return Tuning
	end
	local tuning = stabilityTunings[level]
	if not tuning then
		tuning = table.clone(Tuning)
		tuning.walkHeavyFrom = Upgrades.value("stability", level, UpgradesConfig)
		stabilityTunings[level] = tuning
	end
	return tuning
end

-- The tower's physics for the scoops on it, with the own upgrades (cone stiffness, stability).
local function towerParams()
	return TowerModel.params(
		scoops,
		Flavors.byId,
		stableTuning(),
		Upgrades.stiffness(upgradeLevel("cone"), UpgradesConfig)
	)
end

local function rootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The visible tower on the back: its bottom scoop sits in the waffle (Backpacks.seat, from the same frame the waffle
-- is drawn with) and the rest stacks up from it. While no waffle shows (knocked down), it falls back to the fixed
-- offset from the root.
local function towerBase(root: BasePart): Vector3
	local character = root.Parent :: Model?
	local seat = character and registry.Backpacks.seat(character, TowerVisual.SCOOP_SIZE / 2)
	if seat then
		local _, bottom = TowerShape.offset(1, 1, 0, 0, Tuning)
		return seat - Vector3.new(0, bottom, 0)
	end
	return (root.CFrame * CFrame.new(0, Tuning.holdUp, -Tuning.holdForward)).Position
end

-- The catch column, straight above the character; the server checks catches from the same point.
local function catchBase(root: BasePart): Vector3
	return (root.CFrame * CFrame.new(0, Tuning.catchUp, -Tuning.catchForward)).Position
end

local function servePoint(): BasePart?
	local plotName = player:GetAttribute("PlotName")
	local pier = workspace:FindFirstChild("Pier")
	local plots = pier and pier:FindFirstChild("Plots")
	local plot = plots and type(plotName) == "string" and plots:FindFirstChild(plotName)
	return plot and plot:FindFirstChild("ServePoint") :: BasePart?
end

local function flatten(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > 1e-4 then flat.Unit else Vector3.zero
end

-- `safe`: the character is in the safe zone (outside the arena) right now.
local function onEvent(event: string, safe: boolean)
	if event == "groan" then
		visual:setGroan(true)
		Sfx.play("groan")
	elseif event == "saved" then
		visual:setGroan(false)
		Sfx.play("saved")
		UiKit.Toast.show("SAVED!", "good", "scoops")
		-- out of the arena with a groaning tower: the big effect; caught in the arena: the small one
		if player.Character then
			SavedVfx.play(player.Character, safe)
		end
	elseif event == "toppled" then
		visual:setGroan(false)
		toppledAt = os.clock()
		visual:spill(Economy.keepOnTopple(#scoops, EconomyConfig))
		Sfx.play("topple")
		UiKit.Toast.show("TOPPLED!", "bad", "scoopEmpty")
		Remotes.TowerToppled:FireServer()
	end
end

local function onTowerChanged(newScoops: { string }, reason: string)
	local previous = #scoops
	scoops = newScoops
	params = towerParams()

	local added = (reason == "catch" or reason == "pickup") and #scoops > previous
	if added then
		if toppledAt then
			-- a catch that was in flight when the tower toppled: the topple answer follows and rebuilds the tower
			return
		end
		TowerModel.landingKick(state, Tuning, #scoops)
		Sfx.catch(#scoops)
		if reason == "pickup" then
			-- a spilled scoop picked up: the tower cannot topple on its own for a moment (Config/Tower graceSeconds),
			-- at most once per graceCooldown
			if TowerModel.pickupGrace(state, Tuning) then
				visual:setGroan(false)
			end
		end
	elseif reason == "bossHit" then
		-- a boss knocked the top scoops off: the rest stays as it leans (TowerController.bossHit shoves it)
		if toppledAt then
			return
		end
	elseif reason ~= "catch" and reason ~= "pickup" then
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

local function simulate(dt: number, humanoid: Humanoid, safe: boolean)
	local variant = Tuning.variant
	local smoothing = Tuning.accelSmoothing
	accumulator = math.min(accumulator + dt, MAX_FRAME)
	while accumulator >= STEP do
		accumulator -= STEP
		local target = humanoid.MoveDirection * humanoid.WalkSpeed
		local ax, az
		baseVelocityX, baseVelocityZ, ax, az = TowerModel.baseVelocityStep(
			baseVelocityX,
			baseVelocityZ,
			target.X,
			target.Z,
			smoothing,
			STEP,
			Tuning.turnFactor
		)

		-- standing still (no move input) rescues a groaning tower (Config/Tower rescue)
		local still = target.Magnitude < 1e-3
		local padX, padZ = TowerModel.assist(state, params, Tuning.variant, Tuning, STEP, still)
		local event = TowerModel.step(state, params, {
			ax = ax,
			az = az,
			padX = padX,
			padZ = padZ,
			safe = safe,
		}, variant, Tuning, STEP)
		if event then
			onEvent(event, safe)
		end
	end
end

-- the HUD's preview of what the chest keeps, worked out again only when the tower or the chest changed
local keptFor: { scoops: { string }?, version: number, kept: { [number]: boolean } } = { version = -1, kept = {} }

local function updateHud(root: BasePart)
	local tilt = TowerModel.tilt(state) / Tuning.tipAngle
	local camera = workspace.CurrentCamera
	local lean = Vector3.new(state.x, 0, state.z) / Tuning.tipAngle
	local leanX = lean:Dot(flatten(camera.CFrame.RightVector))
	local leanY = lean:Dot(flatten(camera.CFrame.LookVector))
	local stance = if meter.active then "active" elseif Stance.canStart(meter, Tuning.stance) then "ready" else "empty"
	registry.Hud.setBalance(tilt, state.groan > 0, #scoops > 0, leanX, leanY, meter.energy, stance)

	local target = servePoint()
	local distance = if target then (root.Position - target.Position).Magnitude else math.huge

	local steady = TowerModel.steadyBonus(state, Tuning)
	-- a preview: the scoops the Scoop Chest will keep pay nothing (by the player's Auto Sell, if it has room and
	-- holds fewer than the per-flavor limit: worked out on a copy of the chest as the window last showed it), its coins
	-- passive counts
	local kept = {}
	if Features.scoopChest then
		local version = registry.ChestController.version()
		if keptFor.scoops ~= scoops or keptFor.version ~= version then
			local copy = registry.ChestController.chestCopy()
			keptFor.kept = if copy
				then ScoopChest.store(
					copy,
					scoops,
					nil,
					Flavors.byId,
					Flavors.rarities,
					ChestConfig,
					registry.ChestController.seen(),
					registry.ChestController.autoSell()
				).kept
				else {}
			keptFor.scoops, keptFor.version = scoops, version
		end
		kept = keptFor.kept
	end
	local coinBonus = player:GetAttribute("PassiveCoins")
	local towerBonus = player:GetAttribute("PassiveTower")
	local tower = ChestConfig.passives.kinds.tower
	local value = Economy.serveValue(scoops, Flavors.byId, EconomyConfig, {
		steadyBonus = steady,
		serveMultiplier = Upgrades.value("cart", upgradeLevel("cart"), UpgradesConfig), -- the Coin Boost upgrade
		kept = kept,
		coinBonus = if type(coinBonus) == "number" then coinBonus else 0,
		towerBonus = Economy.towerBonus(
			#scoops,
			if type(towerBonus) == "number" then towerBonus else 0,
			tower.from,
			tower.full
		),
	})
	registry.Hud.setTower(#scoops, capacity(), value, steady)

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

-- The tower stands on the back, between the camera and the character. Only in combat mode (aiming) do the scoops
-- that cover the crosshair turn see-through, for their owner only; the rest of the tower stays solid. Fading the whole
-- tower left it see-through nearly all the time. Since 19.11.2026 not outside combat mode any more: with the textured
-- scoop models a faded pale scoop on the back looked like a grey, see-through lump.
local function updateFade(dt: number)
	local camera = workspace.CurrentCamera
	local blend = 1 - math.exp(-FADE_RESPONSE * dt)
	local aiming = player:GetAttribute("CombatMode") == true
	for index, scoop in visual.scoops do
		local covers = false
		if camera and aiming then
			local look = camera.CFrame.LookVector
			local offset = scoop.part.Position - camera.CFrame.Position
			local along = math.clamp(offset:Dot(look), 0, FADE_RAY)
			local distance = (offset - look * along).Magnitude
			covers = distance < SCOOP_RADIUS + (if covering[index] then FADE_OUT else FADE_IN)
		end
		covering[index] = covers
		local fade = scoopFades[index] or 0
		fade += ((if covers then Tuning.ownTowerFade else 0) - fade) * blend
		scoopFades[index] = fade
		visual:setScoopFade(index, fade)
	end
	for index = #scoopFades, #visual.scoops + 1, -1 do
		scoopFades[index], covering[index] = nil, nil
	end
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

	if Stance.advance(meter, dt, Tuning.stance) then
		stanceEnded(true) -- the bar ran dry; the server's runs dry at about the same time
	elseif meter.active and (#scoops == 0 or state.toppled or toppledAt ~= nil) then
		stopStance(true)
	end
	TowerModel.setStance(state, meter.active)
	-- outside the arena the tower wobbles on but cannot topple (Config/Tower safeTiltFraction)
	simulate(dt, humanoid, not ArenaZone.contains(root.Position.X, root.Position.Z, MapConfig.arena))
	updateHud(root)
	replicateTilt(dt)
end

-- The warning while the tower groans (Config/Tower warning): beeps that rise in pitch the longer it groans,
-- and a visible wobble on top of the lean (drawn only, the physics and the other players do not see it). The red
-- gauge comes from the HUD (groaning).
local warning = Tuning.warning
local nextBeepAt = 0
local function tipWarning(): number
	if state.groan <= 0 or state.toppled or toppledAt then
		nextBeepAt = 0
		return 0
	end
	local share = math.clamp(state.groan / TowerModel.groanLimit(state, Tuning), 0, 1)
	local clock = os.clock()
	if clock >= nextBeepAt then
		nextBeepAt = clock + warning.beepInterval
		Sfx.play("tipWarn", warning.beepPitchFrom + (warning.beepPitchTo - warning.beepPitchFrom) * share)
	end
	return share
end

-- Draws the tower after the movement pose (Character + 2), so it stands in the waffle as it is drawn this frame,
-- leaning and all. The simulation and the catch column above do not depend on it.
local function onVisualStep(dt: number)
	local root = rootPart()
	if not root then
		return
	end
	local shake = tipWarning()
	local wobbleX, wobbleZ = 0, 0
	if shake > 0 then
		local phase = os.clock() * warning.wobbleRate * 2 * math.pi
		local size = warning.wobbleAngle * (0.4 + 0.6 * shake)
		wobbleX, wobbleZ = math.sin(phase) * size, math.cos(phase * 1.3) * size * 0.6
	end
	-- the base with the character's facing: the stack turns after it (TowerVisual, Config/TowerScoops turn)
	visual:update(CFrame.new(towerBase(root)) * root.CFrame.Rotation, state.x + wobbleX, state.z + wobbleZ)
	updateFade(dt)
end

local function canCatch(): boolean
	if toppledAt or state.toppled then
		return false
	end
	return #scoops < capacity()
end

-- A ring that bursts out under the character, seen by everyone: lemon for a dash, mint for a steady stance.
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
local function debugDash(message: string)
	if Features.debugDash then
		print("[Dash] " .. message)
	end
end

-- How fast and how long each kind of dash goes: the dash, and in combat mode the quick dash. A fuller waffle makes it
-- shorter (Economy.dashScale, the same on the server).
local function dashMotion(kind: string): (number, number)
	local sneakers = player:GetAttribute("Upgrade_sneakers")
	local scale =
		Economy.dashScale(#scoops, capacity(), if type(sneakers) == "number" then sneakers else 0, EconomyConfig)
	if kind == "quick" then
		return Tuning.dash.quick.speed, Tuning.dash.quick.duration * scale
	end
	return Tuning.dash.speed, Tuning.dash.duration * scale
end

local function dashBurst(
	root: BasePart,
	humanoid: Humanoid,
	dirX: number,
	dirZ: number,
	speed: number,
	duration: number
)
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
	velocity.PlaneVelocity = Vector2.new(dirX, dirZ) * speed
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
	local start = root.Position
	debugDash(string.format("burst: %.0f studs/s for %.3f s towards (%.2f, %.2f)", speed, duration, dirX, dirZ))
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local wall = false
		local hit
		if root.Parent then
			local reach = math.min(speed * dt + 0.4, 6)
			hit = workspace:Blockcast(root.CFrame, castSize, ahead * reach, params)
			wall = hit ~= nil and Dash.blocks(hit.Normal.X, hit.Normal.Y, hit.Normal.Z, dirX, dirZ)
		end
		if not wall and elapsed < duration - dt / 2 and root.Parent then
			return
		end
		connection:Disconnect()
		debugDash(
			string.format(
				"burst ended after %.3f s, %.1f studs: %s",
				elapsed,
				if root.Parent then (root.Position - start).Magnitude else -1,
				if wall and hit then "stopped at " .. hit.Instance:GetFullName() else "time is up"
			)
		)
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

local function onDash(who: Player, dirX: number, dirZ: number, kind: string?)
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local dashKind = if kind == "quick" then kind else "dash"
	local speed, duration = dashMotion(dashKind)
	-- the movement and the tower kick first: an error in the effects below must never cost the dash itself
	if who == player then
		debugDash(`{dashKind} granted by the server`)
		dashRunningUntil = os.clock() + duration
		local humanoid = (character :: Model):FindFirstChildOfClass("Humanoid")
		if humanoid then
			dashBurst(root, humanoid, dirX, dirZ, speed, duration)
		end
		if #scoops > 0 and not state.toppled and not toppledAt then
			TowerModel.dashKick(state, Tuning.dash, #scoops, dirX, dirZ)
		end
	end
	local ok, problem = pcall(function()
		burstRing(root, Palette.lemon)
		registry.MovementController.dash(character :: Model, duration, dirX, dirZ, speed * duration)
	end)
	if not ok then
		warn("[Dash] effects failed, the dash itself still ran: " .. tostring(problem))
	end
end

-- Asks the server for a dash; the burst happens when it agrees. Every dash (the dash and the quick dash) goes the
-- way the character walks, diagonals included, or ahead when it stands.
local function askForDash()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootPart()
	if not humanoid or not root or humanoid.Health <= 0 then
		debugDash("no request: no living character")
		return
	end
	if os.clock() < dashRunningUntil then
		debugDash("no request: a dash is still running")
		return
	end
	local sticky = player:GetAttribute("StickyUntil")
	if type(sticky) == "number" and workspace:GetServerTimeNow() < sticky then
		debugDash("no request: stuck in a boss's sticky puddle")
		return
	end
	local direction = flatten(humanoid.MoveDirection)
	if direction == Vector3.zero then
		direction = flatten(root.CFrame.LookVector)
	end
	if direction == Vector3.zero then
		debugDash("no request: no direction")
		return
	end
	if not DashCharges.tryUse(dashCharges, os.clock(), Tuning.dash) then
		debugDash(string.format("no request: no charge (%d ready)", dashCharges.charges))
		return
	end
	Remotes.Dash:FireServer(direction.X, direction.Z)
	TowerController.interruptStance()
	debugDash(string.format("dash request sent towards (%.2f, %.2f)", direction.X, direction.Z))
end

-- Q on PC, X on a gamepad, the dash button on touch screens: the dash, in combat mode the quick dash (the server
-- decides which).
local function requestDash(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		askForDash()
	end
	return Enum.ContextActionResult.Sink
end

-- F on PC, the Steady button on touch screens: the stance holds while the key is down. It ends on release, when the
-- bar runs dry (hits drain it too), when the tower is gone, with a throw or a dash (then locked for stance.lockout),
-- or when the server ends it (knockdown); then it stays off until the key is pressed again. The server keeps its own
-- bar and applies the costs (speed, no sprint).
local function startStance()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if #scoops == 0 or state.toppled or toppledAt or not humanoid or humanoid.Health <= 0 then
		return
	end
	if not Stance.start(meter, Tuning.stance) then
		return
	end
	stanceStartedAt = os.clock()
	TowerModel.setStance(state, true)
	Remotes.SetStance:FireServer(true)
	syncSprintLook()
	Sfx.play("saved")
end

-- The stance has just ended locally (the bar is already off).
function stanceEnded(tellServer: boolean)
	TowerModel.setStance(state, false)
	if tellServer then
		Remotes.SetStance:FireServer(false)
	end
	syncSprintLook()
end

function stopStance(tellServer: boolean)
	if meter.active then
		Stance.stop(meter)
		stanceEnded(tellServer)
	end
end

local function onStanceInput(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		startStance()
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		stopStance(true)
	end
	return Enum.ContextActionResult.Sink
end

-- Every player's stance, from the server's SteadyStance attribute: a mint ring when one starts, and for the local
-- player the end of a stance the server stopped.
local function watchStance(who: Player)
	who:GetAttributeChangedSignal("SteadyStance"):Connect(function()
		if who:GetAttribute("SteadyStance") == true then
			local character = who.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				burstRing(root, Palette.mint)
			end
		elseif who == player and meter.active and os.clock() - stanceStartedAt > STANCE_ECHO then
			stopStance(false)
		end
	end)
end

local function setSprinting(on: boolean)
	if on == sprinting then
		return
	end
	sprinting = on
	Remotes.SetSprint:FireServer(on)
	syncSprintLook()
end

-- Shift sprints while held; L3 and the Sprint button on touch screens toggle it. The server sets the speed.
local function onSprintInput(_: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local toggles = input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Keys.pad("sprint")
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

-- Puts Roblox's shift lock on Ctrl (RobloxControls), so it keeps working without taking the sprint's Shift.
local function moveShiftLockToCtrl()
	RobloxControls.moveShiftLock(SHIFT_LOCK_KEYS)
end

function TowerController.Init(reg)
	registry = reg
	visual = TowerVisual.new("MyTower")
end

function TowerController.Start()
	Remotes.TowerChanged.OnClientEvent:Connect(onTowerChanged)
	-- a bought (or reset) Big Cone or Stability changes the physics of the tower on the back at once
	for _, id in { "cone", "stability" } do
		player:GetAttributeChangedSignal("Upgrade_" .. id):Connect(function()
			params = towerParams()
		end)
	end
	Remotes.Served.OnClientEvent:Connect(
		function(who: Player, count: number?, value: number?, _steady: any, sold: number?)
			-- only the own serve shows (kill test 13.11.2026: no feed line for others any more; the server only tells
			-- the others that someone served, PlotPins glints at their pin)
			-- a serve that only filled the Scoop Chest pays nothing: no "+0", the chest's message says what happened
			if who == player and type(value) == "number" and value > 0 then
				Sfx.play("serve")
				-- some went into the Scoop Chest (Auto Sell): the message says how many were sold, the chest's says the rest
				local partly = type(count) == "number" and type(sold) == "number" and sold < count
				UiKit.Toast.show(
					if partly
						then string.format("SOLD %d %s! +%d", sold, if sold == 1 then "SCOOP" else "SCOOPS", value)
						else string.format("SERVE! +%d", value),
					"good",
					"coin"
				)
				lastPaidServeAt = os.clock()
			end
		end
	)
	Remotes.Dash.OnClientEvent:Connect(onDash)
	ContextActionService:BindActionAtPriority(
		DASH_ACTION,
		requestDash,
		false, -- touch screens use the Dash button of TouchControls
		ACTION_PRIORITY,
		table.unpack(Keys.inputs("dash"))
	)
	registry.TouchControls.bind("dash", function(state)
		requestDash(DASH_ACTION, state)
	end)

	ContextActionService:BindActionAtPriority(
		SPRINT_ACTION,
		onSprintInput,
		false, -- touch screens use the Sprint button of TouchControls (it toggles)
		ACTION_PRIORITY,
		table.unpack(Keys.inputs("sprint"))
	)
	registry.TouchControls.bind("sprint", function(state, input)
		onSprintInput(SPRINT_ACTION, state, input)
	end)
	-- the server resets sprint on respawn, so the client does too
	player.CharacterAdded:Connect(function()
		sprinting = false
		stopStance(false) -- the server ends it on respawn too
		syncSprintLook()
	end)
	task.spawn(moveShiftLockToCtrl)

	Players.PlayerAdded:Connect(watchStance)
	for _, other in Players:GetPlayers() do
		watchStance(other)
	end
	ContextActionService:BindActionAtPriority(
		STANCE_ACTION,
		onStanceInput,
		false, -- touch screens use the Steady button of TouchControls
		ACTION_PRIORITY,
		table.unpack(Keys.inputs("steady"))
	)
	registry.TouchControls.bind("steady", function(state)
		onStanceInput(STANCE_ACTION, state)
	end)

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

-- Whether the local player holds the steady stance.
function TowerController.inStance(): boolean
	return meter.active
end

-- A throw or a dash was just requested: the stance ends and is locked for stance.lockout (also one released a
-- moment ago, like the server does). The server ends and locks its own when it grants the request; the "off" sent
-- here, after the request, only counts if it refuses.
-- How full each segment of the dash bar is (0..1, one per charge): the same count the key checks, so a full
-- segment is a dash that can be asked for.
function TowerController.dashSegments(): { number }
	return DashCharges.segments(dashCharges, os.clock(), Tuning.dash)
end

function TowerController.interruptStance()
	local wasActive = meter.active
	Stance.interrupt(meter, Tuning.stance, Tuning.stance.lockRecent)
	if wasActive then
		stanceEnded(true)
	end
end

-- An ice-ball hit announced by the server: shove the tower along the ball's flight (half as hard in the stance) and
-- drain the stance's bar. The server decided the power and drains its own bar.
function TowerController.hit(dirX: number, dirZ: number, power: number)
	if #scoops > 0 and not state.toppled and not toppledAt then
		TowerModel.hitKick(state, CombatConfig, #scoops, dirX, dirZ, power)
	end
	if Stance.drain(meter, power * CombatConfig.stanceDrain) then
		stanceEnded(false)
	end
end

-- A boss attack hit the local player (BossController, Config/Bosses hit): a strong shove along (dirX, dirZ), and the
-- tower is held up like in the grace for `protect` seconds, so it wobbles hard but never falls from it: only players
-- topple towers. The scoops that fell off come from the server (TowerService.bossHit).
function TowerController.bossHit(dirX: number, dirZ: number, kick: number, protect: number)
	if #scoops == 0 or state.toppled or toppledAt then
		return
	end
	TowerModel.startGrace(state, protect)
	TowerModel.impulse(state, dirX * kick, dirZ * kick)
	visual:setGroan(false)
end

-- Knocked down: the tower cannot topple on its own while the carrier is down and for graceSeconds after getting up
-- (Config/Tower). `downSeconds` is how long the knockdown lasts. A hit or a dash still ends it.
function TowerController.knockedDown(downSeconds: number)
	if #scoops > 0 and not state.toppled then
		TowerModel.startGrace(state, downSeconds + Tuning.graceSeconds)
		visual:setGroan(false)
	end
end

-- Whether the local tower can take a scoop right now (not toppling, room on the cone): catching and picking up.
function TowerController.canTake(): boolean
	return canCatch()
end

-- The carrier landed after a gummy pad's jump (Controllers/BounceController): a kick of `kick` rad/s in a random
-- direction (Bounce.towerKick, never enough to topple a standing tower on its own).
function TowerController.bounceLanded(kick: number)
	if #scoops > 0 and kick > 0 and not state.toppled and not toppledAt then
		local angle = math.random() * 2 * math.pi
		TowerModel.impulse(state, math.cos(angle) * kick, math.sin(angle) * kick)
	end
end

-- Luck turned the scoop just caught (the top one, already `to` in the server's list) from `from` into `to`: it shows
-- as `from` for a moment, then changes with a fresh plop. Calls `changed(position)` at the change, with where the
-- scoop is. False when the top scoop is not that catch (nothing shown).
function TowerController.lucky(from: string, to: string, delay: number, changed: (Vector3) -> ()): boolean
	local index = #scoops
	if index == 0 or scoops[index] ~= to then
		return false
	end
	local shown = table.clone(scoops)
	shown[index] = from
	visual:setFlavors(shown)
	task.delay(delay, function()
		if scoops[index] ~= to then
			return -- served, toppled or changed meanwhile: the tower already shows the server's list
		end
		visual:setFlavors(scoops)
		visual:replop(index)
		changed(visual:topPosition())
	end)
	return true
end

-- How many scoops the tower holds and how many the cone takes (Config/Economy upgrades.cone.capacity).
-- os.clock() of the last serve that paid coins (its "SERVE!" message), for the chest's message to wait its turn.
function TowerController.lastPaidServe(): number
	return lastPaidServeAt
end

function TowerController.fill(): (number, number)
	return #scoops, capacity()
end

-- The own plot's serve point (nil while the plot is not known yet).
function TowerController.servePoint(): BasePart?
	return servePoint()
end

-- Whether the cone holds as many scoops as its level allows (Config/Economy upgrades.cone.capacity).
function TowerController.isFull(): boolean
	return #scoops >= capacity()
end

-- The free scoops of the own topple arrived (LootRenderer): the stand-ins left where the tower stood can go.
function TowerController.clearSpill()
	visual:clearSpill()
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
