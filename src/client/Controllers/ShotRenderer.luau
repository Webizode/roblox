-- Draws scoops in flight and their landing circles, and claims a catch when a scoop touches the local tower.
-- The touch test sweeps the path between two frames against the whole tower column (cone tip to the free slot
-- on top), so a scoop that flies into the side of a tall tower is caught instead of passing through it.
-- The claim carries the server time of the touch and the tilt at that moment; the server replays exactly that.
-- With the Big Swirl's arm rig a scoop first rides in its arm's cup (from scoopAt, on the cup bone) and only starts its
-- flight at t0; until then it is not catchable. The landing circle shows from the start, as a warning.
-- The scoop is the tower scoop model (ScoopModel); caught, it waits above the free slot, where the tower's new top
-- scoop then plops in (TowerVisual). With Features.towerScoopFlight it also turns slowly on the way up, tips over like
-- a shuttlecock after the apex, dome first, and swings back upright when caught (Config/TowerScoops, ScoopFlight).
-- Its rarity shows all the way (Config/Vfx.flight, RarityFlight): from uncommon a trail in the rarity's colour, from
-- rare a glow, from epic sparks and a sound at the release, legendary a wide golden trail and a golden outline; a lower
-- VFX quality keeps only the trail. All of it is looks: the path is the server's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ShotMath = require(Shared:WaitForChild("ShotMath"))
local ScoopFlight = require(Shared:WaitForChild("ScoopFlight"))
local RarityFlight = require(Shared:WaitForChild("RarityFlight"))
local Tuning = require(Config:WaitForChild("Launcher"))
local Features = require(Config:WaitForChild("Features"))
local ArmConfig = require(Config:WaitForChild("BigSwirl"))
local Flavors = require(Config:WaitForChild("Flavors"))
local VfxConfig = require(Config:WaitForChild("Vfx"))
local Look = require(Config:WaitForChild("TowerScoops"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))
local ScoopModel = require(client:WaitForChild("ScoopModel"))
local ScoopSign = require(client:WaitForChild("ScoopSign"))
local ScoopAura = require(client:WaitForChild("ScoopAura"))
local BigSwirlArms = require(client:WaitForChild("BigSwirlArms"))
local Settings = require(client:WaitForChild("Settings"))
local Sfx = require(client:WaitForChild("Sfx"))
local SwirlAnnounce = require(client:WaitForChild("SwirlAnnounce"))
local RarityBanner = require(client:WaitForChild("RarityBanner"))
local CatchVfx = require(client:WaitForChild("Vfx"):WaitForChild("Effects"):WaitForChild("Catch"))
local SwirlShotVfx = require(client:WaitForChild("Vfx"):WaitForChild("Effects"):WaitForChild("SwirlShot"))

local ShotRenderer = {}

-- what shows a scoop's rarity in flight, on an invisible carrier that follows it (nil for a common one)
type Trail = {
	anchor: Part,
	trail: Trail?,
	sparkles: ParticleEmitter?,
	light: PointLight?,
	highlight: Highlight?,
	sound: string?, -- played once at the release
	lifetime: number,
}

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
	trail: Trail?, -- its rarity's trail, glow and sparks (nil for a common one)
	spin0: number, -- its turn at the start, so scoops in the air do not all face the same way
	claimed: boolean,
	released: boolean?, -- left the cup (its trail is on)
	down: boolean?, -- came down on its landing circle uncaught (its puff has played)
	claimedAt: number?, -- os.clock of the claim
	claimAxis: Vector3?, -- the tip it had then, undone by the swing back upright
	claimAngle: number?,
	claimSpin: number?,
	arm: number?, -- the Big Swirl arm it leaves from (nil: the Nozzle)
	scoopAt: number?, -- server time it shows in that arm's cup
}

local CIRCLE_SIZE = Look.landingCircle.size
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

-- The rarity's look rides on an invisible, unturned carrier that follows the scoop, so the scoop's turn and tip do not
-- twist the trail. It starts switched off (in the cup) and is switched on at the release. Nil when the rarity shows
-- nothing (common).
local function makeTrail(flavorId: string): Trail?
	local flavor = Flavors.byId[flavorId]
	local style = RarityFlight.style(
		flavor and flavor.rarity or "common",
		Settings.effective().vfxQuality,
		VfxConfig.flight,
		Flavors.rarityColors
	)
	if not style.trail and not style.glow and style.sparks <= 0 then
		return nil
	end
	local color = Color3.fromHex(style.color)

	local anchor = makePart()
	anchor.Name = "ScoopTrail"
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	local lifetime = 0
	local trail: Trail? = nil
	if style.trail then
		local look = style.trail
		lifetime = look.lifetime
		local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
		top.Position = Vector3.new(0, look.width / 2, 0)
		bottom.Position = Vector3.new(0, -look.width / 2, 0)
		top.Parent, bottom.Parent = anchor, anchor
		local made = Instance.new("Trail")
		made.Attachment0, made.Attachment1 = top, bottom
		made.Lifetime = look.lifetime
		made.FaceCamera = true
		made.LightEmission = look.lightEmission
		made.Color = ColorSequence.new(color)
		made.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, look.transparency),
			NumberSequenceKeypoint.new(1, 1),
		})
		made.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
		made.Enabled = false
		made.Parent = anchor
		trail = made :: any
	end

	local sparkles: ParticleEmitter? = nil
	if style.sparks > 0 then
		local emitter = Instance.new("ParticleEmitter") -- Roblox's built-in sparkle texture
		emitter.Rate = style.sparks
		emitter.Lifetime = NumberRange.new(0.3, 0.7)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new(0.05, 1)
		emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		emitter.LightEmission = 1
		emitter.Speed = NumberRange.new(0.5, 2)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 3
		emitter.Enabled = false
		emitter.Parent = anchor
		sparkles = emitter
	end

	local light: PointLight? = nil
	if style.glow then
		local made = Instance.new("PointLight")
		made.Color = color
		made.Brightness = style.glow.brightness
		made.Range = style.glow.range
		made.Shadows = false
		made.Enabled = false
		made.Parent = anchor
		light = made
	end

	local highlight: Highlight? = nil
	if style.highlight then
		local made = Instance.new("Highlight")
		made.FillColor = color
		made.FillTransparency = 0.65
		made.OutlineColor = color
		made.OutlineTransparency = 0
		made.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		made.Enabled = false
		made.Parent = anchor
		highlight = made
	end
	return {
		anchor = anchor,
		trail = trail,
		sparkles = sparkles,
		light = light,
		highlight = highlight,
		sound = style.sound,
		lifetime = lifetime,
	}
end

local function setTrail(trail: Trail?, on: boolean)
	if not trail then
		return
	end
	if trail.trail then
		trail.trail.Enabled = on
	end
	if trail.sparkles then
		trail.sparkles.Enabled = on
	end
	if trail.light then
		trail.light.Enabled = on
	end
	if trail.highlight then
		trail.highlight.Enabled = on
	end
	if on and trail.sound then
		Sfx.at(trail.sound, trail.anchor, VfxConfig.flight.hearing)
		trail.sound = nil -- once, at the release
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

-- the light-up of each new landing circle, stopped if the circle hides before it ends
local flashes: { [Part]: Tween } = setmetatable({}, { __mode = "k" }) :: any

-- Hides a landing circle.
local function hideCircle(circle: Part)
	local flash = flashes[circle]
	if flash then
		flash:Cancel()
		flashes[circle] = nil
	end
	circle.Transparency = 1
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
	-- a rare one is announced: the Big Swirl flashes or glows before it leaves, a legendary gets the banner
	SwirlAnnounce.shot(flavorId, t0)
	local flavor = Flavors.byId[flavorId]
	local look = flavor and RarityFlight.style(flavor.rarity, "high", VfxConfig.flight, Flavors.rarityColors)
	if flavor and look and look.banner then
		local lead = if look.announce then look.announce.time else 0
		task.delay(math.max(0, t0 - lead - workspace:GetServerTimeNow()), function()
			RarityBanner.show(`{string.upper(flavor.rarity)}!`, flavor.name, Color3.fromHex(look.color))
		end)
	end
	local scoop = ScoopModel.new(TowerVisual.root(), flavorId)
	scoop:setScale(Vector3.one * FLIGHT_SCALE * (if arm then ArmConfig.scoopInCupScale else 1))
	scoop:setSign(ScoopSign.new(flavorId, false)) -- golden scoops come with Features.goldenScoops
	scoop:setAura(ScoopAura.new(flavorId)) -- a legendary one glitters in flight
	scoop.part.CFrame = scoop:at(CFrame.new(from))

	local circle = makePart()
	circle.Name = "LandingCircle"
	circle.Shape = Enum.PartType.Cylinder
	circle.Size = Vector3.new(0.2, CIRCLE_SIZE, CIRCLE_SIZE)
	circle.CFrame = CFrame.new(to + Vector3.new(0, 0.12, 0)) * CIRCLE_ROTATION
	-- the rarity's colour like the trail, a common one light grey (RarityFlight.circleColor): where a rare one will come
	-- down shows from far away; no dark rim since 25.11.2026
	local rarity = Flavors.byId[flavorId] and Flavors.byId[flavorId].rarity
	circle.Color = Color3.fromHex(
		RarityFlight.circleColor(rarity, VfxConfig.flight, Flavors.rarityColors, Look.landingCircle.common)
	)
	circle.Material = Enum.Material.Neon
	-- it lights up as the Big Swirl fires and settles to its normal faintness
	circle.Transparency = Look.landingCircle.flashTransparency
	local flash = TweenService:Create(
		circle,
		TweenInfo.new(Look.landingCircle.flash, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = Look.landingCircle.transparency }
	)
	flashes[circle] = flash
	flash:Play()
	SwirlShotVfx.circle(to, flavorId)

	local trail = makeTrail(flavorId)
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
		if scoop.sign then
			scoop.sign.Enabled = false
		end
	else
		setTrail(trail, true)
	end
end

local function onShotResolved(id: number, catcher: Player?, landed: boolean?)
	local shot = shots[id]
	if not shot then
		return
	end
	if catcher ~= player then
		if shot.claimed and Features.debugCatch then
			print(string.format("[Catch] claim for shot %d was not accepted (reason in the server output)", id))
		end
		if catcher == nil and not landed then -- splashed into the water; a landed one lies on as a free scoop
			splat(shot)
		end
	end
	if catcher then
		CatchVfx.play(shot.scoop.part.Position, shot.to, shot.flavorId, catcher == player)
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
	shot.scoop:setSign(nil) -- it is a tower scoop now: those carry no sign
	shot.scoop:setAura(nil) -- and no particles
	hideCircle(shot.circle)
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
		if shot.trail and shot.trail.highlight and shot.trail.highlight.Adornee ~= part then
			shot.trail.highlight.Adornee = part -- the outline goes round whichever model shows
		end
		local arm = shot.arm
		if arm and alpha < 0 then
			-- still in the arm: hidden until it is scooped, then riding upright in the cup
			local bone = BigSwirlArms.cup(arm)
			local scooped = now >= (shot.scoopAt or shot.t0)
			scoop:setTransparency(if scooped and bone then 0 else 1)
			if scoop.sign then
				scoop.sign.Enabled = scooped and bone ~= nil
			end
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
				SwirlShotVfx.fire(part.Position, shot.to, shot.flavorId) -- steam and sparks out of the cup
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

		if alpha >= 1 then
			-- down on its landing point: it lies there upright until the server says what became of it (a free scoop
			-- takes over, LootRenderer, or it splashed). A touch just after landing still counts (catchWindowEnd).
			part.CFrame =
				scoop:at(CFrame.new(shot.to + Vector3.new(0, scoop:restHeight(), 0)) * CFrame.Angles(0, shot.spin0, 0))
			moveTrail(shot.trail, shot.to)
			hideCircle(shot.circle)
			if not shot.down then
				shot.down = true
				SwirlShotVfx.landed(shot.to, shot.flavorId)
			end
		else
			local position, axis, angle, spin = flying(shot, alpha, now)
			part.CFrame = scoop:at(CFrame.new(position) * turned(axis, angle, spin))
			moveTrail(shot.trail, position)
			local size = CIRCLE_SIZE * (1 - 0.6 * math.clamp(alpha, 0, 1))
			shot.circle.Size = Vector3.new(0.2, size, size)
		end

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
