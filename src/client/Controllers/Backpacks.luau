-- The waffle-cone backpack on every character. It holds the loaded ice balls, so everyone sees at a glance who
-- still has ammo: a thrown ball pops out of the top, and once the load is empty, frost balls grow in the cone until
-- it refills. Every client draws every backpack from the IceBalls / IceBallsReadyAt attributes the server sets on
-- each Player (Combat.backpack turns them into what to show). Client-only, anchored, non-colliding parts like the
-- towers; nothing here touches gameplay. It follows the torso, so it leans and falls with the movement pose.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Combat = require(Shared:WaitForChild("Combat"))
local CombatConfig = require(Config:WaitForChild("Combat"))
local Look = require(Config:WaitForChild("Backpack"))
local Palette = require(Config:WaitForChild("Palette"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))

local Backpacks = {}

type Slot = {
	part: Part,
	loaded: boolean,
	changedAt: number, -- os.clock() the last pop in or out started; later than now while a refill waits its turn
	from: number, -- scale and transparency when it changed, so a pop starts from what was on screen
	fromTransparency: number,
	scale: number, -- what the last frame drew
	transparency: number,
	size: number, -- last size written, so a ball at rest is not resized every frame
}

type Pack = {
	model: Model,
	parts: { BasePart }, -- all of them, for the first-person fade
	cone: { Part }, -- segments from the opening down
	rim: Part,
	tip: Part,
	straps: { Part }, -- front left, front right, over the left shoulder, over the right shoulder
	slots: { Slot },
	moveParts: { BasePart },
	moveCFrames: { CFrame },
	torsoSize: Vector3?, -- the torso size the parts are built for
	synced: boolean, -- false until the first ammo reading, which shows without popping
	shown: boolean,
	fade: number,
}

local STEP = "WobbleBackpacks"
local CYLINDER_UP = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X
local HIDDEN_SCALE = 0.02
local RIM_RADIUS = Look.coneTopDiameter / 2 + 0.06
-- the cone axis sits this far behind the back (before scaling), so the rim's lower near edge, the point closest
-- to the back, keeps coneBack from it
local AXIS_BACK = Look.coneBack
	+ math.cos(Look.coneTilt) * RIM_RADIUS
	- math.sin(Look.coneTilt) * (Look.coneLength / 2 - Look.rimHeight)

local localPlayer = Players.LocalPlayer
local packs: { [Player]: Pack } = {}

local function newPart(model: Model, name: string, shape: Enum.PartType, color: string, material: Enum.Material): Part
	local part = TowerVisual.makePart(model)
	part.Name = name
	part.Shape = shape
	part.Color = Color3.fromHex(color)
	part.Material = material
	return part
end

-- Where a slot's ball sits relative to the cone's opening, before scaling. A load bigger than the configured
-- slots stacks straight up from the last one.
local function slotOffset(index: number): Vector3
	local slots = Look.slots
	local entry = slots[math.min(index, #slots)]
	local above = math.max(0, index - #slots) * Look.ballDiameter
	return Vector3.new(entry[1], entry[2] + above, entry[3])
end

local function newPack(player: Player): Pack
	local model = Instance.new("Model")
	model.Name = "Backpack_" .. player.UserId
	local pack: Pack = {
		model = model,
		parts = {},
		cone = {},
		rim = nil :: any,
		tip = nil :: any,
		straps = {},
		slots = {},
		moveParts = {},
		moveCFrames = {},
		torsoSize = nil,
		synced = false,
		shown = false,
		fade = 0,
	}
	local function add(name: string, shape: Enum.PartType, color: string, material: Enum.Material): Part
		local part = newPart(model, name, shape, color, material)
		table.insert(pack.parts, part)
		return part
	end
	for _ = 1, Look.coneSegments do
		table.insert(pack.cone, add("Waffle", Enum.PartType.Cylinder, Palette.waffle, Enum.Material.SmoothPlastic))
	end
	pack.rim = add("Rim", Enum.PartType.Cylinder, Palette.chocolate, Enum.Material.SmoothPlastic)
	pack.tip = add("Tip", Enum.PartType.Ball, Palette.waffle, Enum.Material.SmoothPlastic)
	for _ = 1, 4 do
		local strap = add("Strap", Enum.PartType.Block, Palette.chocolate, Enum.Material.SmoothPlastic)
		strap.CastShadow = false
		table.insert(pack.straps, strap)
	end
	-- the same look as a ball in flight, so the ones on the back read as ammo
	for _ = 1, CombatConfig.ammo do
		table.insert(pack.slots, {
			part = add("IceBall", Enum.PartType.Ball, Palette.skyTop, Enum.Material.Ice),
			loaded = true,
			changedAt = -math.huge,
			from = 0,
			fromTransparency = 0,
			scale = 1,
			transparency = 0,
			size = -1,
		})
	end
	-- the order place() writes the CFrames in
	for _, part in pack.cone do
		table.insert(pack.moveParts, part)
	end
	table.insert(pack.moveParts, pack.rim)
	table.insert(pack.moveParts, pack.tip)
	for _, strap in pack.straps do
		table.insert(pack.moveParts, strap)
	end
	for _, slot in pack.slots do
		table.insert(pack.moveParts, slot.part)
	end
	return pack
end

-- Fixed sizes for one torso size: the cone and the straps. Ball sizes change with the pops, every frame.
local function resize(pack: Pack, torsoSize: Vector3)
	pack.torsoSize = torsoSize
	local s = torsoSize.Y / Look.referenceTorsoHeight
	local segment = Look.coneLength / Look.coneSegments
	for index, part in pack.cone do
		local share = (index - 0.5) / Look.coneSegments
		local diameter = Look.coneTopDiameter + (Look.coneTipDiameter - Look.coneTopDiameter) * share
		part.Size = Vector3.new(segment, diameter, diameter) * s
	end
	local rim = 2 * RIM_RADIUS
	pack.rim.Size = Vector3.new(Look.rimHeight, rim, rim) * s
	pack.tip.Size = Vector3.one * Look.coneTipDiameter * s
	local width, thickness = Look.strapWidth * s, Look.strapThickness * s
	local front = Vector3.new(width, torsoSize.Y * 0.95, thickness)
	local over = Vector3.new(width, thickness, torsoSize.Z + 2 * thickness + Look.strapReach * s)
	pack.straps[1].Size, pack.straps[2].Size = front, front
	pack.straps[3].Size, pack.straps[4].Size = over, over
end

local function show(pack: Pack, on: boolean)
	if pack.shown ~= on then
		pack.shown = on
		pack.model.Parent = if on then TowerVisual.root() else nil
		-- ammo changes while hidden must not replay as pops: the next reading shows as it is, like on join
		if not on then
			pack.synced = false
		end
	end
end

-- The local player's backpack fades with their own character in first person and when the camera comes close to
-- the backpack itself (zoomed in, or pushed against a wall).
local function setFade(pack: Pack, fade: number)
	if pack.fade ~= fade then
		pack.fade = fade
		for _, part in pack.parts do
			part.LocalTransparencyModifier = fade
		end
	end
end

-- Starts a pop wherever the ammo changed. A refill pops in bottom first, one ball after the other.
local function syncSlots(pack: Pack, loaded: number, clock: number)
	for index, slot in pack.slots do
		local want = index <= loaded
		if not pack.synced then
			slot.loaded = want
			slot.changedAt = -math.huge
		elseif slot.loaded ~= want then
			slot.loaded = want
			slot.from, slot.fromTransparency = slot.scale, slot.transparency
			slot.changedAt = if want then clock + (index - 1) * Look.popStagger else clock
		end
	end
	pack.synced = true
end

-- One ball's scale (share of the full size) and transparency this frame.
local function slotLook(slot: Slot, clock: number, refill: number): (number, number)
	if slot.loaded then
		local alpha = math.clamp((clock - slot.changedAt) / Look.popIn, 0, 1)
		local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		return slot.from + (1 - slot.from) * eased, slot.fromTransparency * (1 - alpha)
	end
	local alpha = math.clamp((clock - slot.changedAt) / Look.popOut, 0, 1)
	local out = slot.from * (1 - alpha)
	local frost = Look.frostMax * refill
	if out >= frost then
		return out, slot.fromTransparency
	end
	return frost, Look.frostTransparency
end

-- Moves every part and returns the opening's position and the scale, for the local camera fade.
local function place(pack: Pack, torso: BasePart, clock: number, refill: number): (Vector3, number)
	local torsoSize = torso.Size
	if pack.torsoSize ~= torsoSize then
		resize(pack, torsoSize)
	end
	local s = torsoSize.Y / Look.referenceTorsoHeight
	local length = Look.coneLength * s
	local torsoCFrame = torso.CFrame
	-- back is +Z in the torso's frame; the cone's frame has its centre on the cone axis, +Y towards the opening
	local back = torsoSize.Z / 2 + AXIS_BACK * s
	local cone = torsoCFrame * CFrame.new(0, Look.coneUp * s, back) * CFrame.Angles(Look.coneTilt, 0, 0)

	-- the part order never changes, so moveParts is filled once in newPack and only the CFrames are written
	local cframes = pack.moveCFrames
	local count = 0

	local segment = length / Look.coneSegments
	for index in pack.cone do
		count += 1
		cframes[count] = cone * CFrame.new(0, length / 2 - (index - 0.5) * segment, 0) * CYLINDER_UP
	end
	cframes[count + 1] = cone * CFrame.new(0, length / 2 - Look.rimHeight * s / 2, 0) * CYLINDER_UP
	cframes[count + 2] = cone * CFrame.new(0, -length / 2, 0)
	count += 2

	local strapX = torsoSize.X * 0.25
	local thickness = Look.strapThickness * s
	local frontZ = -(torsoSize.Z / 2 + thickness / 2)
	local overY = torsoSize.Y / 2 + thickness / 2
	local overZ = Look.strapReach * s / 2 -- the over-shoulder straps reach back to the rim
	cframes[count + 1] = torsoCFrame * CFrame.new(-strapX, 0, frontZ)
	cframes[count + 2] = torsoCFrame * CFrame.new(strapX, 0, frontZ)
	cframes[count + 3] = torsoCFrame * CFrame.new(-strapX, overY, overZ)
	cframes[count + 4] = torsoCFrame * CFrame.new(strapX, overY, overZ)
	count += 4

	local opening = cone * CFrame.new(0, length / 2, 0)
	for index, slot in pack.slots do
		local scale, transparency = slotLook(slot, clock, refill)
		slot.scale, slot.transparency = scale, transparency
		local part = slot.part
		if scale < HIDDEN_SCALE then
			transparency = 1
		else
			local diameter = Look.ballDiameter * s * scale
			if math.abs(slot.size - diameter) > 1e-3 then
				slot.size = diameter
				part.Size = Vector3.one * diameter
			end
		end
		-- Transparency is stored as a float32, so an exact compare would rewrite 0.55 every frame
		if math.abs(part.Transparency - transparency) > 1e-3 then
			part.Transparency = transparency
		end
		count += 1
		cframes[count] = opening * CFrame.new(slotOffset(index) * s)
	end

	workspace:BulkMoveTo(pack.moveParts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	return opening.Position, s
end

local function torsoOf(character: Model): BasePart?
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	return if torso and torso:IsA("BasePart") then torso else nil
end

local function onRenderStep()
	local clock = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	for player, pack in packs do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local torso = character and torsoOf(character)
		-- knocked down (lying on the back) the cone would stick in the floor, so it waits until the get-up
		local visible = torso ~= nil
			and humanoid ~= nil
			and humanoid.Health > 0
			and torso.CFrame.UpVector.Y >= Look.minUpright
			and (eye == nil or (torso.Position - eye).Magnitude <= Look.drawDistance)
		show(pack, visible)
		if not visible or not torso then
			continue
		end

		local count = player:GetAttribute("IceBalls")
		local readyAt = player:GetAttribute("IceBallsReadyAt")
		local loaded, refill = Combat.backpack(
			if type(count) == "number" then count else CombatConfig.ammo,
			if type(readyAt) == "number" then readyAt else 0,
			serverNow,
			CombatConfig
		)
		syncSlots(pack, loaded, clock)
		local opening, s = place(pack, torso, clock, refill)
		if player == localPlayer then
			local head = character:FindFirstChild("Head")
			local fade = if head and head:IsA("BasePart") then head.LocalTransparencyModifier else 0
			if eye then
				local near = (Look.fadeStart * s - (opening - eye).Magnitude) / ((Look.fadeStart - Look.fadeEnd) * s)
				fade = math.max(fade, math.clamp(near, 0, 1))
			end
			setFade(pack, fade)
		end
	end
end

local function track(player: Player)
	if not packs[player] then
		packs[player] = newPack(player)
	end
end

local function untrack(player: Player)
	local pack = packs[player]
	if pack then
		packs[player] = nil
		pack.model:Destroy()
	end
end

function Backpacks.Start()
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	-- after MovementController's pose (Character + 2), so the backpack sits on the posed torso
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Character.Value + 3, onRenderStep)
end

return Backpacks
