-- A perfect throw, in the green of the charge arc (Config/Combat crosshair.perfectColor): green glitter where the
-- ball leaves the hand (Config/Vfx.effects.perfectRelease) and a glowing green streak with small stars behind the
-- ball (Config/Vfx.perfectTrail), so everybody sees the fast one coming.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VfxRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VfxRules"))

local Vfx = require(script.Parent.Parent)
local Emit = require(script.Parent.Parent:WaitForChild("Emit"))

local PerfectThrow = {}

local Config = Vfx.Config
local Look = Config.perfectTrail

-- The glitter at the release: at `origin`, bursting along the throw.
function PerfectThrow.release(origin: Vector3, velocity: Vector3, own: boolean)
	local forward = if velocity.Magnitude > 1e-3 then velocity.Unit else Vector3.new(0, 1, 0)
	Vfx.burst("perfectRelease", CFrame.lookAt(origin, origin + forward, Vector3.new(0, 1, 0.001)), { own = own })
end

-- Dresses a flying ball's streak, twinkles and glow (BallVisual.addFlight) as a perfect throw's.
function PerfectThrow.dress(flight: { trail: Trail, emitter: ParticleEmitter, light: PointLight })
	local white = Emit.color("white")
	local green = Emit.color("perfect")
	local deep = Emit.color("perfectDeep")
	local trail = flight.trail
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, white),
		ColorSequenceKeypoint.new(0.25, green),
		ColorSequenceKeypoint.new(1, deep),
	})
	trail.Lifetime *= Look.trailLifetime
	trail.LightEmission = Look.trailLight

	local emitter = flight.emitter
	emitter.Texture = Config.textures.star
	emitter.Color = ColorSequence.new(white, green)
	emitter.Rate = VfxRules.rate(Look.rate, Vfx.quality(), Config)
	emitter.Lifetime = NumberRange.new(Look.lifetime * 0.6, Look.lifetime)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Look.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0)
	emitter.LightEmission = 0.4
	emitter.LightInfluence = 0
	emitter.RotSpeed = NumberRange.new(-240, 240)

	flight.light.Color = green
end

return PerfectThrow
