-- Builds the particle emitters of an effect from its layers (Config/Vfx) and fires them: one attachment with one
-- emitter per layer, made once and reused (Pool). Emitters never run on their own (Rate 0); an effect emits a
-- counted burst.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Vfx"))

local Pool = require(script.Parent:WaitForChild("Pool"))

local Emit = {}

export type Rig = { attachment: Attachment, emitters: { ParticleEmitter } }

local colorCache: { [string]: Color3 } = {}

-- A colour of Config/Vfx.colors or a hex colour.
function Emit.color(token: string): Color3
	local cached = colorCache[token]
	if cached then
		return cached
	end
	local color = Color3.fromHex(Config.colors[token] or token)
	colorCache[token] = color
	return color
end

local function sequence(points: { { number } }, scale: number): NumberSequence
	local keypoints = table.create(#points)
	for index, point in points do
		keypoints[index] = NumberSequenceKeypoint.new(point[1], point[2] * scale)
	end
	return NumberSequence.new(keypoints)
end

local function range(pair: { number }?): NumberRange
	return if pair then NumberRange.new(pair[1], pair[2]) else NumberRange.new(0)
end

local function emitter(layer: any): ParticleEmitter
	local made = Instance.new("ParticleEmitter")
	made.Name = layer.texture
	made.Enabled = false
	made.Rate = 0
	made.Texture = Config.textures[layer.texture]
	made.Lifetime = range(layer.lifetime)
	made.Speed = range(layer.speed)
	made.SpreadAngle = Vector2.new(layer.spread or 0, layer.spread or 0)
	made.Size = sequence(layer.size, 1)
	made.Transparency = sequence(layer.transparency, 1)
	made.Acceleration = Vector3.new(0, layer.accel or 0, 0)
	made.Drag = layer.drag or 0
	made.Rotation = range(layer.rotation)
	made.RotSpeed = range(layer.rotSpeed)
	made.Brightness = layer.bright or 1
	made.LightEmission = layer.light or 0
	made.LightInfluence = 0 -- the candy colours stay as they are, in shade and at night
	made.ZOffset = layer.z or 0
	made.EmissionDirection = Enum.NormalId.Front
	if layer.orient == "velocity" then
		made.Orientation = Enum.ParticleOrientation.VelocityParallel
	end
	if layer.flipbook then
		made.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		made.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	end
	return made
end

-- The emitters of `effect` (Config/Vfx.effects[name]) on one attachment, from the pool. Also returns whether they
-- were built just now: an emitter emits nothing in the frame it is created, so a fresh rig fires a frame later
-- (Vfx.burst); Vfx.prewarm builds the first of each ahead of time.
function Emit.take(name: string, effect: any): (Rig, boolean)
	local anchor = Pool.anchor() -- first: a lost anchor empties the pools
	local fresh = false
	local rig = Pool.take("emit:" .. name, function(): Rig
		fresh = true
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		local emitters = table.create(#effect.layers)
		for index, layer in effect.layers do
			local made = emitter(layer)
			made.Parent = attachment
			emitters[index] = made
		end
		attachment.Parent = anchor
		return { attachment = attachment, emitters = emitters }
	end)
	return rig, fresh
end

function Emit.give(name: string, rig: Rig)
	if rig.attachment.Parent then
		Pool.give("emit:" .. name, rig)
	end
end

-- Fires the rig at `where` (the burst flies along its look direction): `counts[i]` particles of layer i, the "scoop"
-- layers in `scoop`, all sizes times `scale`.
function Emit.fire(rig: Rig, effect: any, counts: { number }, where: CFrame, scoop: Color3, scale: number)
	rig.attachment.WorldCFrame = where
	for index, layer in effect.layers do
		local count = counts[index]
		if count > 0 then
			local made = rig.emitters[index]
			local color = if layer.color == "scoop" then scoop else Emit.color(layer.color)
			if layer.lighten then
				color = color:Lerp(Color3.new(1, 1, 1), layer.lighten)
			end
			made.Color = ColorSequence.new(color)
			made.Size = sequence(layer.size, scale)
			made:Emit(count)
		end
	end
end

return Emit
