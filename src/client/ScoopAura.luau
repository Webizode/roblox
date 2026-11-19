-- The light, lasting particles round a legendary scoop while it flies (ShotRenderer) or lies on the ground
-- (LootRenderer), each legendary flavor its own (Config/Vfx.auras: glitter, snowflakes, petals, sparks, steam). Never
-- on a tower. ScoopModel:setAura keeps it on whichever model shows.
--
-- Budget: one shared loop (every Config/Vfx.auras.check seconds) shows only the maxShown nearest auras within
-- maxDistance of the camera, at the rate the VFX quality allows (low: none); the others stand still and cost nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Vfx"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local ScoopAura = {}

local LOOK = Config.auras

type Aura = { emitter: ParticleEmitter, rate: number }

local live: { [ParticleEmitter]: Aura } = {}
local connection: RBXScriptConnection? = nil

local function range(pair: { number }): NumberRange
	return NumberRange.new(pair[1], pair[2])
end

local function update()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local share = LOOK.quality[Settings.effective().vfxQuality] or 0
	local near: { { aura: Aura, distance: number } } = {}
	local count = 0
	for emitter, aura in live do
		local part = emitter.Parent
		if not part then
			continue -- not on a scoop yet (ScoopModel:setAura), or between two
		end
		count += 1
		local distance = if part:IsA("BasePart") then (part.Position - eye).Magnitude else math.huge
		if share > 0 and distance <= LOOK.maxDistance then
			table.insert(near, { aura = aura, distance = distance })
		else
			aura.emitter.Enabled = false
		end
	end
	table.sort(near, function(a, b)
		return a.distance < b.distance
	end)
	for index, entry in near do
		local on = index <= LOOK.maxShown
		entry.aura.emitter.Enabled = on
		entry.aura.emitter.Rate = entry.aura.rate * share
	end
	if count == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function ensureLoop()
	if connection then
		return
	end
	local since = 0
	connection = RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= LOOK.check then
			since = 0
			update()
		end
	end)
end

-- An aura for a scoop of `flavorId` (a ParticleEmitter, not parented yet: ScoopModel:setAura puts it into the scoop
-- part, whose volume the particles start in), or nil for a flavor without one.
function ScoopAura.new(flavorId: string): ParticleEmitter?
	local kind = LOOK.kinds[flavorId]
	if not kind then
		return nil
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Aura"
	emitter.Texture = Config.textures[kind.texture]
	emitter.Color = ColorSequence.new(Color3.fromHex(kind.colors[1]), Color3.fromHex(kind.colors[2]))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, kind.size[2]),
		NumberSequenceKeypoint.new(1, kind.size[1] * 0.5),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = range(kind.life)
	emitter.Speed = range(kind.speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, kind.rise, 0)
	emitter.RotSpeed = NumberRange.new(-kind.spin, kind.spin)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.LightEmission = kind.light
	emitter.LightInfluence = 0
	emitter.Rate = 0
	emitter.Enabled = false -- the loop switches it on when it is near enough
	emitter.LockedToPart = false
	live[emitter] = { emitter = emitter, rate = kind.rate }
	ensureLoop()
	return emitter
end

-- The aura is done (its scoop was destroyed).
function ScoopAura.release(emitter: ParticleEmitter)
	live[emitter] = nil
	emitter:Destroy()
end

return ScoopAura
