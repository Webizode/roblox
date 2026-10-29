-- Draws scoops in flight and their landing circles, and claims a catch when a scoop touches the local tower.
-- The touch test sweeps the path between two frames against the whole tower column (cone tip to the free slot
-- on top), so a scoop that flies into the side of a tall tower is caught instead of passing through it.
-- The claim carries the server time of the touch and the tilt at that moment; the server replays exactly that.
-- With the Big Swirl's arm rig a scoop first rides in its arm's cup (from scoopAt, on the cup bone) and only starts its
-- flight at t0; until then it is not catchable. The landing circle shows from the start, as a warning.
-- The scoop is the tower scoop model (ScoopModel); caught, it waits above the free slot, where the tower's new top
-- scoop then plops in (TowerVisual). With Features.towerScoopFlight it also turns slowly on the way up, tips over like
-- a shuttlecock after the apex, dome first, swings back upright when caught, and a short trail in its colour follows
-- it, stronger for rarer flavors and shorter at a lower VFX quality (Config/TowerScoops, ScoopFlight). All of it is
-- looks: the path is the server's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ShotMath = require(Shared:WaitForChild("ShotMath"))
local ScoopFlight = require(Shared:WaitForChild("ScoopFlight"))
local Tuning = require(Config:WaitForChild("Launcher"))
local Features = require(Config:WaitForChild("Features"))
local ArmConfig = require(Config:WaitForChild("BigSwirl"))
local Flavors = require(Config:WaitForChild("Flavors"))
local Palette = require(Config:WaitForChild("Palette"))
local Look = require(Config:WaitForChild("TowerScoops"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))
local ScoopModel = require(client:WaitForChild("ScoopModel"))
local BigSwirlArms = require(client:WaitForChild("BigSwirlArms"))
local Settings = require(client:WaitForChild("Settings"))

local ShotRenderer = {}

type Trail = { anchor: Part, trail: Trail, sparkles: ParticleEmitter?, lifetime: number }

type Shot = {
	path: ShotMath.Path,
	to: Vector3,
	t0: number,
	flight: number,
	apexAlpha: number,
	lastAlpha: number,
	flavorId: string,
	scoop: ScoopModel.ScoopModel,
	circle: Part,
	trail: Trail?, -- nil while Features.towerScoopFlight is off
	spin0: number, -- its turn at the start, so scoops in the air do not all face the same way
	claimed: boolean,
	released: boolean?, -- left the cup (its trail is on)
	claimedAt: number?, -- os.clock of the claim
	claimAxis: Vector3?, -- the tip it had then, undone by the swing back upright
	claimAngle: number?,
	claimSpin: number?,
	arm: number?, -- the Big Swirl arm it leaves from (nil: the Nozzle)
	scoopAt: number?, -- server time it shows in that arm's cup
}

local CIRCLE_SIZE = 7
local CIRCLE_ROTATION = CFrame.Angles(0, 0, math.rad(90))
local FLIGHT_SCALE = 2 / ScoopModel.SIZE -- 2 studs across in flight, a little smaller than on a tower
local SCOOP_OFFSET = CFrame.new(ArmConfig.scoopOffset[1], ArmConfig.scoopOffset[2], ArmConfig.scoopOffset[3])
local VELOCITY_STEP = 0.01 -- share of the flight to look ahead for its direction

local player = Players.LocalPlayer
local registry
local shots: { [number]: Shot } = {}
local rng = Random.new()

local function makePart(): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = TowerVisual.root()
	return part
end

-- The trail rides on an invisible, unturned carrier that follows the scoop, so the scoop's turn and tip do not
-- twist it. It starts switched off (in the cup) and is switched on at the release.
local function makeTrail(flavorId: string): Trail
	local flavor = Flavors.byId[flavorId]
	local golden = false -- golden scoops come with Features.goldenScoops; the launcher does not send them yet
	local effects = Settings.effective()
	local style = ScoopFlight.trailStyle(
		ScoopFlight.trailTier(flavor and flavor.rarity or "common", golden, Look),
		effects.vfxQuality,
		Look
	)
	local color = Color3.fromHex(style.color or (if flavor then flavor.color else Palette.vanilla))

	local anchor = makePart()
	anchor.Name = "ScoopTrail"
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
	top.Position = Vector3.new(0, style.width / 2, 0)
	bottom.Position = Vector3.new(0, -style.width / 2, 0)
	top.Parent, bottom.Parent = anchor, anchor

	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = top, bottom
	trail.Lifetime = style.lifetime
	trail.FaceCamera = true
	trail.LightEmission = style.lightEmission
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, style.transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Enabled = false
	trail.Parent = anchor

	local sparkles: ParticleEmitter? = nil
	if style.sparkles > 0 then
		local emitter = Instance.new("ParticleEmitter") -- Roblox's built-in sparkle texture
		emitter.Rate = style.sparkles
		emitter.Lifetime = NumberRange.new(0.3, 0.6)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new(0.1, 1)
		emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		emitter.LightEmission = 1
		emitter.Speed = NumberRange.new(0.2, 1)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 3
		emitter.Enabled = false
		emitter.Parent = anchor
		sparkles = emitter
	end
	return { anchor = anchor, trail = trail, sparkles = sparkles, lifetime = style.lifetime }
end

local function setTrail(trail: Trail?, on: boolean)
	if not trail then
		return
	end
	trail.trail.Enabled = on
	if trail.sparkles then
		trail.sparkles.Enabled = on
	end
end

local function moveTrail(trail: Trail?, position: Vector3)
	if trail then
		trail.anchor.CFrame = CFrame.new(position)
	end
end

-- The scoop is gone: its trail stops growing and fades out where it is.
local function endTrail(trail: Trail?)
	if not trail then
		return
	end
	setTrail(trail, false)
	task.delay(trail.lifetime + 0.7, function()
		trail.anchor:Destroy()
	end)
end

local function remove(id: number)
	local shot = shots[id]
	if shot then
		shots[id] = nil
		shot.scoop:destroy()
		shot.circle:Destroy()
		endTrail(shot.trail)
	end
end

-- A puddle where the scoop hits the ground: below its current position, which is the landing point for a
-- scoop nobody caught and the tower top for a claim the server turned down.
local function splat(shot: Shot)
	local position = shot.scoop.part.Position
	local puddle = makePart()
	puddle.Shape = Enum.PartType.Cylinder
	puddle.Size = Vector3.new(0.15, 3, 3)
	puddle.CFrame = CFrame.new(position.X, shot.to.Y + 0.1, position.Z) * CIRCLE_ROTATION
	TowerVisual.applyFlavor(puddle, shot.flavorId)
	TweenService:Create(puddle, TweenInfo.new(1.2), { Transparency = 1, Size = Vector3.new(0.15, 4.5, 4.5) }):Play()
	task.delay(1.3, function()
		puddle:Destroy()
	end)
end

local function onShotFired(
	id: number,
	flavorId: string,
	from: Vector3,
	to: Vector3,
	apex: number,
	t0: number,
	flight: number,
	arm: number?,
	scoopAt: number?,
	speed: number?
)
	if arm and speed then
		BigSwirlArms.start(arm, t0, speed) -- the arm dives, scoops and whips so that it releases at t0
	end
	local scoop = ScoopModel.new(TowerVisual.root(), flavorId)
	scoop:setScale(Vector3.one * FLIGHT_SCALE * (if arm then ArmConfig.scoopInCupScale else 1))
	scoop.part.CFrame = scoop:at(CFrame.new(from))

	local circle = makePart()
	circle.Name = "LandingCircle"
	circle.Shape = Enum.PartType.Cylinder
	circle.Size = Vector3.new(0.2, CIRCLE_SIZE, CIRCLE_SIZE)
	circle.CFrame = CFrame.new(to + Vector3.new(0, 0.12, 0)) * CIRCLE_ROTATION
	circle.Transparency = 0.5
	TowerVisual.applyFlavor(circle, flavorId)
	circle.Material = Enum.Material.Neon

	local trail = if Features.towerScoopFlight then makeTrail(flavorId) else nil
	if trail then
		trail.anchor.CFrame = CFrame.new(from)
	end

	shots[id] = {
		path = { fx = from.X, fy = from.Y, fz = from.Z, tx = to.X, ty = to.Y, tz = to.Z, apex = apex },
		to = to,
		t0 = t0,
		flight = flight,
		apexAlpha = ShotMath.apexAlpha(from.Y, to.Y, apex),
		lastAlpha = (workspace:GetServerTimeNow() - t0) / flight,
		flavorId = flavorId,
		scoop = scoop,
		circle = circle,
		trail = trail,
		spin0 = rng:NextNumber(0, 2 * math.pi),
		claimed = false,
		arm = arm,
		scoopAt = scoopAt,
	}
	if arm then
		scoop:setTransparency(1) -- shows once it is scooped
	else
		setTrail(trail, true)
	end
end

local function onShotResolved(id: number, catcher: Player?)
	local shot = shots[id]
	if not shot then
		return
	end
	if catcher ~= player then
		if shot.claimed and Features.debugCatch then
			print(string.format("[Catch] claim for shot %d was not accepted (reason in the server output)", id))
		end
		if catcher == nil then
			splat(shot)
		end
	end
	-- caught by us: TowerChanged already put the scoop into the stack
	remove(id)
end

-- Where the scoop is at flight share `alpha` and which way it is turned: its spin, and after the apex its tip
-- towards the direction it flies. Also returns the tip as axis and angle, for the swing back after a catch.
local function flying(shot: Shot, alpha: number, now: number): (Vector3, Vector3?, number, number)
	local path = shot.path
	local x, y, z = ShotMath.position(path.fx, path.fy, path.fz, path.tx, path.ty, path.tz, path.apex, alpha)
	if not Features.towerScoopFlight then
		return Vector3.new(x, y, z), nil, 0, shot.spin0 -- upright, no turn
	end
	local spin = shot.spin0 + ScoopFlight.spin(now - shot.t0, Look)
	local tip = ScoopFlight.tip(alpha, shot.apexAlpha, Look)
	if tip <= 0 then
		return Vector3.new(x, y, z), nil, 0, spin
	end
	local ax, ay, az =
		ShotMath.position(path.fx, path.fy, path.fz, path.tx, path.ty, path.tz, path.apex, alpha + VELOCITY_STEP)
	local direction = Vector3.new(ax - x, ay - y, az - z)
	local axis = Vector3.new(0, 1, 0):Cross(direction)
	if axis.Magnitude < 1e-6 then
		return Vector3.new(x, y, z), nil, 0, spin
	end
	local angle = ScoopFlight.tipAngle(tip, direction.X, direction.Y, direction.Z, Look)
	return Vector3.new(x, y, z), axis.Unit, angle, spin
end

local function turned(axis: Vector3?, angle: number, spin: number): CFrame
	local spun = CFrame.Angles(0, spin, 0)
	return if axis then CFrame.fromAxisAngle(axis, angle) * spun else spun
end

local function claim(id: number, shot: Shot, alpha: number, tiltX: number, tiltZ: number)
	shot.claimed = true
	shot.circle.Transparency = 1
	local _, axis, angle, spin = flying(shot, alpha, workspace:GetServerTimeNow())
	shot.claimedAt, shot.claimAxis, shot.claimAngle, shot.claimSpin = os.clock(), axis, angle, spin
	Remotes.CatchClaim:FireServer(id, shot.t0 + alpha * shot.flight, tiltX, tiltZ)
end

local function onRenderStep()
	local now = workspace:GetServerTimeNow()
	BigSwirlArms.step(now) -- the arms first: a scoop riding in a cup follows its bone this frame
	local column, tiltX, tiltZ = registry.TowerController.catchColumn()
	local top = registry.TowerController.topPosition()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for id, shot in shots do
		local alpha = (now - shot.t0) / shot.flight
		if alpha > Tuning.resolveAfter + 0.5 then
			-- the resolve message got lost; do not keep orphans around
			remove(id)
			continue
		end

		local scoop = shot.scoop
		local part = scoop:updateLod((scoop.part.Position - eye).Magnitude)
		local arm = shot.arm
		if arm and alpha < 0 then
			-- still in the arm: hidden until it is scooped, then riding upright in the cup
			local bone = BigSwirlArms.cup(arm)
			local scooped = now >= (shot.scoopAt or shot.t0)
			scoop:setTransparency(if scooped and bone then 0 else 1)
			if bone then
				local position = (bone.TransformedWorldCFrame * SCOOP_OFFSET).Position
				part.CFrame = scoop:at(CFrame.new(position) * CFrame.Angles(0, shot.spin0, 0))
				moveTrail(shot.trail, position)
			end
			shot.lastAlpha = 0
			continue
		elseif arm then
			-- just released: visible, shrinking from its size in the cup to its flying size
			if not shot.released then
				shot.released = true
				scoop:setTransparency(0)
				setTrail(shot.trail, true)
			end
			local grown = math.clamp(1 - alpha * shot.flight / ArmConfig.shrinkTime, 0, 1)
			scoop:setScale(Vector3.one * FLIGHT_SCALE * (1 + (ArmConfig.scoopInCupScale - 1) * grown))
		end

		if shot.claimed then
			-- predicted catch: it swings back upright just above the free slot, where the tower's new top scoop
			-- plops in from (TowerVisual), and waits there for the server's answer
			if top then
				local undo = 1 - ScoopFlight.righting(os.clock() - (shot.claimedAt or 0), Look)
				local position = top + Vector3.new(0, Look.catch.plopDrop, 0)
				part.CFrame = scoop:at(
					CFrame.new(position) * turned(shot.claimAxis, (shot.claimAngle or 0) * undo, shot.claimSpin or 0)
				)
				moveTrail(shot.trail, position)
			end
			continue
		end

		local position, axis, angle, spin = flying(shot, alpha, now)
		part.CFrame = scoop:at(CFrame.new(position) * turned(axis, angle, spin))
		moveTrail(shot.trail, position)
		local size = CIRCLE_SIZE * (1 - 0.6 * math.clamp(alpha, 0, 1))
		shot.circle.Size = Vector3.new(0.2, size, size)

		if column then
			local from = math.max(shot.lastAlpha, shot.apexAlpha - Tuning.apexSlack)
			local to = math.min(alpha, Tuning.catchWindowEnd)
			local hit = ShotMath.firstContact(shot.path, from, to, column, Tuning.catchRadius, Tuning.contactStep)
			if hit then
				claim(id, shot, hit, tiltX, tiltZ)
			end
		end
		shot.lastAlpha = alpha
	end
end

function ShotRenderer.Init(reg)
	registry = reg
end

function ShotRenderer.Start()
	Remotes.ShotFired.OnClientEvent:Connect(onShotFired)
	Remotes.ShotResolved.OnClientEvent:Connect(onShotResolved)
	-- after TowerController, so the column matches where the tower is drawn this frame
	RunService:BindToRenderStep("WobbleShots", registry.TowerController.RENDER_PRIORITY + 1, onRenderStep)
end

return ShotRenderer
