-- Every thrown ball in flight, kept quiet (Config/Vfx.throwTrail): a short pale streak that runs from white towards
-- the colour of the thrown scoop, and a few small glints falling off it. A perfect throw is dressed over this
-- (PerfectThrow.dress).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VfxRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VfxRules"))

local Vfx = require(script.Parent.Parent)
local Emit = require(script.Parent.Parent:WaitForChild("Emit"))

local ThrowTrail = {}

local Config = Vfx.Config
local Look = Config.throwTrail

-- Dresses a flying ball's streak, twinkles and glow (BallVisual.addFlight); `flavorId`: the thrown scoop's flavor
-- (nil: the default).
function ThrowTrail.dress(flight: { trail: Trail, emitter: ParticleEmitter, light: PointLight }, flavorId: string?)
	local white = Emit.color("white")
	local color = Vfx.flavorColor(flavorId):Lerp(white, Look.lighten)
	local trail = flight.trail
	trail.Color = ColorSequence.new(white, color)
	trail.Lifetime = Look.trailLifetime
	trail.LightEmission = Look.trailLight
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Look.trailTransparency),
		NumberSequenceKeypoint.new(1, 1),
	})

	local emitter = flight.emitter
	emitter.Texture = Config.textures.flash
	emitter.Color = ColorSequence.new(white, color)
	emitter.Rate = VfxRules.rate(Look.rate, Vfx.quality(), Config)
	emitter.Lifetime = NumberRange.new(Look.lifetime * 0.6, Look.lifetime)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Look.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.2, 0.6)
	emitter.LightEmission = 0.8
	emitter.LightInfluence = 0

	flight.light.Color = color
end

return ThrowTrail
