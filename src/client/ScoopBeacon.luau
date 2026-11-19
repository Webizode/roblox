-- The rarity beacon over a scoop lying on the ground (LootRenderer): a soft light column in its rarity's colour, so a
-- rare scoop reads from far away (Config/Vfx.beacons, from rare on). Never on a tower or in flight (there the landing
-- circle and the trail show the rarity). ScoopModel:setBeacon keeps it on whichever model shows.
--
-- A Beam between two attachments in the scoop's part, facing the camera. The part may roll and turn: the shared loop
-- (every Config/Vfx.beacons.check seconds) points the top straight up again, and shows only the maxShown nearest within
-- maxDistance of the camera (fewer at low VFX quality); the others stand switched off.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ConfigFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Vfx = require(ConfigFolder:WaitForChild("Vfx"))
local Flavors = require(ConfigFolder:WaitForChild("Flavors"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local ScoopBeacon = {}

local LOOK = Vfx.beacons

type Beacon = { beam: Beam, height: number }

local live: { [Beam]: Beacon } = {}
local connection: RBXScriptConnection? = nil

local function update()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local share = LOOK.quality[Settings.effective().vfxQuality] or 0
	local limit = math.floor(LOOK.maxShown * share + 0.5)
	local near: { { beacon: Beacon, distance: number } } = {}
	local count = 0
	for beam, beacon in live do
		local part = beam.Parent
		if not part or not part:IsA("BasePart") then
			continue -- not on a scoop yet (ScoopModel:setBeacon), or between two
		end
		count += 1
		local top = beam.Attachment1
		if top then
			-- straight up in the world, whichever way the scoop has rolled
			top.Position = part.CFrame:VectorToObjectSpace(Vector3.new(0, beacon.height, 0))
		end
		local distance = (part.Position - eye).Magnitude
		if distance <= LOOK.maxDistance then
			table.insert(near, { beacon = beacon, distance = distance })
		else
			beam.Enabled = false
		end
	end
	table.sort(near, function(a, b)
		return a.distance < b.distance
	end)
	for index, entry in near do
		entry.beacon.beam.Enabled = index <= limit
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

-- A beacon for a scoop of `flavorId` (a Beam with its two attachments, not parented yet: ScoopModel:setBeacon puts
-- them into the scoop's part), or nil for a flavor whose rarity has none.
function ScoopBeacon.new(flavorId: string): Beam?
	local flavor = Flavors.byId[flavorId]
	local kind = flavor and LOOK.byRarity[flavor.rarity]
	if not kind then
		return nil
	end
	local color = Color3.fromHex(Flavors.rarityColors[flavor.rarity] or "#FFFFFF")
	local foot = Instance.new("Attachment")
	foot.Name = "BeaconFoot"
	local top = Instance.new("Attachment")
	top.Name = "BeaconTop"
	top.Position = Vector3.new(0, kind.height, 0)
	local beam = Instance.new("Beam")
	beam.Name = "Beacon"
	beam.Attachment0 = foot
	beam.Attachment1 = top
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = kind.width
	beam.Width1 = kind.width * 0.6
	beam.Color = ColorSequence.new(color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, kind.transparency),
		NumberSequenceKeypoint.new(0.6, (1 + kind.transparency) / 2),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Enabled = false -- the loop switches it on when it is near enough
	live[beam] = { beam = beam, height = kind.height }
	ensureLoop()
	return beam
end

-- Puts the beacon (beam and attachments) into `part`, or takes it out with nil.
function ScoopBeacon.attach(beam: Beam, part: BasePart?)
	local foot, top = beam.Attachment0, beam.Attachment1
	if foot then
		foot.Parent = part
	end
	if top then
		top.Parent = part
	end
	beam.Parent = part
end

-- The beacon is done (its scoop was picked up or destroyed).
function ScoopBeacon.release(beam: Beam)
	live[beam] = nil
	local foot, top = beam.Attachment0, beam.Attachment1
	beam:Destroy()
	if foot then
		foot:Destroy()
	end
	if top then
		top:Destroy()
	end
end

return ScoopBeacon
