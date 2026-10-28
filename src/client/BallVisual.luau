-- The vanilla ball model as a client-only visual: a copy of the template in ReplicatedStorage (Config/Combat
-- ballModel.template; imported from Blender, body and face welded, pivot at the body's centre, the face towards -Z),
-- anchored and non-colliding like the towers, scaled to the ball that flies (ballRadius). HeldBalls and
-- CombatController draw it; without the template in the place both keep their plain ice ball. It also carries the
-- ball's ice look: the frost in the hand, the streak and twinkles in flight and the shards of a hit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local CombatConfig = require(Config:WaitForChild("Combat"))
local Features = require(Config:WaitForChild("Features"))
local Palette = require(Config:WaitForChild("Palette"))

local Settings = require(script.Parent:WaitForChild("Settings"))

local BallVisual = {}

local reported = false

local function template(): Model?
	local found = ReplicatedStorage:FindFirstChild(CombatConfig.ballModel.template)
	if found and found:IsA("Model") and found.PrimaryPart then
		return found
	end
	if Features.debugThrow and not reported then
		reported = true
		print(
			`[Throw] no ball model ReplicatedStorage.{CombatConfig.ballModel.template} with a PrimaryPart, `
				.. "drawing the plain ice ball"
		)
	end
	return nil
end

-- Scales the model so its largest side is `diameter` studs, around its pivot.
function BallVisual.setDiameter(model: Model, diameter: number)
	local size = model:GetExtentsSize()
	local largest = math.max(size.X, size.Y, size.Z)
	if largest > 0 then
		model:ScaleTo(model:GetScale() * diameter / largest)
	end
end

-- A fresh copy `diameter` studs across, not parented yet; nil without the template.
function BallVisual.new(name: string, diameter: number): Model?
	local source = template()
	if not source then
		return nil
	end
	local model = source:Clone()
	model.Name = name
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.CastShadow = false
		end
	end
	BallVisual.setDiameter(model, diameter)
	return model
end

-- The body, the part a trail or an attachment goes on.
function BallVisual.body(model: Model): BasePart
	return model.PrimaryPart :: BasePart
end

-- Transparency of every part, and optionally their local modifier (first person). Transparency is stored as a
-- float32, so only real changes are written.
function BallVisual.setTransparency(model: Model, transparency: number, localModifier: number?)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			if math.abs(descendant.Transparency - transparency) > 1e-3 then
				descendant.Transparency = transparency
			end
			if localModifier then
				descendant.LocalTransparencyModifier = localModifier
			end
		end
	end
end

-- The ice look (Config/Combat iceVfx): only particles, a trail and lights, nothing that moves or collides.
local Vfx = CombatConfig.iceVfx
local ICE = Color3.fromHex(Palette.skyTop)
local WHITE = Color3.fromHex(Palette.vanilla)
local DEEP = Color3.fromHex(Palette.sea)

local function sparkles(parent: Instance, rate: number, lifetime: number, size: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter") -- Roblox's built-in sparkle texture
	emitter.Name = "IceSparkles"
	emitter.Rate = rate * Settings.effective().particleScale -- fewer at a lower VFX quality
	emitter.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Color = ColorSequence.new(WHITE, ICE)
	emitter.LightEmission = 1
	emitter.Speed = NumberRange.new(0.3, 1.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = parent
	return emitter
end

local function glow(parent: Instance, brightness: number, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Name = "IceGlow"
	light.Color = ICE
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	-- the lights go at the low VFX quality and in the performance mode: lights cost the most on weak phones
	light.Enabled = Settings.effective().heavyDashEffects
	light.Parent = parent
	return light
end

export type Frost = { emitter: ParticleEmitter, light: PointLight, on: boolean }

-- A few slow sparkles and a soft glow on the ball in the hand; off until setFrost turns it on.
function BallVisual.addFrost(model: Model): Frost
	local body = BallVisual.body(model)
	local frost = {
		emitter = sparkles(body, Vfx.frost.rate, Vfx.frost.lifetime, Vfx.frost.size),
		light = glow(body, Vfx.frost.brightness, Vfx.frost.range),
		on = true,
	}
	BallVisual.setFrost(frost, false)
	return frost
end

function BallVisual.setFrost(frost: Frost, on: boolean)
	if frost.on ~= on then
		frost.on = on
		frost.emitter.Enabled = on
		frost.light.Enabled = on and Settings.effective().heavyDashEffects
	end
end

export type Flight = { trail: Trail, emitter: ParticleEmitter, light: PointLight, attachments: { Attachment } }

-- The flying ball's look: a short light streak from white to ice blue that thins out, twinkles falling off it and a
-- glow. The streak's two attachments sit above and below the centre, on the axis the ball spins around, so the spin
-- does not twist it.
function BallVisual.addFlight(part: BasePart, radius: number): Flight
	local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
	top.Position = Vector3.new(0, radius * 0.8, 0)
	bottom.Position = Vector3.new(0, -radius * 0.8, 0)
	top.Parent, bottom.Parent = part, part
	local trail = Instance.new("Trail")
	trail.Name = "IceStreak"
	trail.Attachment0, trail.Attachment1 = top, bottom
	trail.Lifetime = Vfx.trail.lifetime
	trail.FaceCamera = true
	trail.LightEmission = Vfx.trail.lightEmission
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.4, ICE),
		ColorSequenceKeypoint.new(1, DEEP),
	})
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
	trail.Parent = part
	return {
		trail = trail,
		emitter = sparkles(part, Vfx.twinkle.rate, Vfx.twinkle.lifetime, Vfx.twinkle.size),
		light = glow(part, Vfx.glow.brightness, Vfx.glow.range),
		attachments = { top, bottom },
	}
end

-- The ball is gone: its streak and twinkles stay where it ended and fade out there instead of vanishing with it.
function BallVisual.leaveFlight(flight: Flight, where: CFrame)
	local holder = Instance.new("Part")
	holder.Name = "IceStreakFade"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.1
	holder.CFrame = where
	holder.Parent = workspace:FindFirstChild("LocalVisuals") or workspace
	for _, attachment in flight.attachments do
		attachment.Parent = holder
	end
	flight.trail.Parent = holder
	flight.emitter.Enabled = false
	flight.emitter.Parent = holder
	flight.light:Destroy()
	task.delay(Vfx.fadeOut + Vfx.trail.lifetime, function()
		holder:Destroy()
	end)
end

-- The hit: a quick pinwheel of thin ice shards spinning out from the impact and fading, plus a burst of sparkles.
-- Bigger on a player than on the world.
function BallVisual.hitShards(position: Vector3, hit: boolean)
	local root = workspace:FindFirstChild("LocalVisuals") or workspace
	local size = if hit then 1 else 0.7
	for index = 1, Vfx.shards do
		local angle = (index / Vfx.shards) * math.pi * 2
		local shard = Instance.new("WedgePart")
		shard.Name = "IceShard"
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = false
		shard.Material = Enum.Material.Neon
		shard.Color = if index % 2 == 0 then ICE else WHITE
		shard.Transparency = 0.15
		shard.Size = Vector3.new(0.08, 0.5, 0.9) * size
		local start = CFrame.new(position) * CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(20), 0, 0)
		shard.CFrame = start
		shard.Parent = root
		TweenService:Create(shard, TweenInfo.new(Vfx.shardTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = start * CFrame.new(0, 0, -1.6 * size) * CFrame.Angles(0, 0, math.rad(120)),
			Transparency = 1,
			Size = shard.Size * 0.3,
		}):Play()
		task.delay(Vfx.shardTime + 0.05, function()
			shard:Destroy()
		end)
	end
	local burst = Instance.new("Attachment")
	burst.Parent = workspace.Terrain
	burst.WorldPosition = position
	local emitter = sparkles(burst, 0, 0.5, 0.3 * size)
	emitter.Speed = NumberRange.new(4, 9)
	emitter:Emit(if hit then 22 else 12)
	task.delay(0.6, function()
		burst:Destroy()
	end)
end

return BallVisual
