-- The waffle-cone backpack on every character. For now it is an empty waffle: it belongs to the collecting and
-- tower side of the game, and what it will show there is still open. It is not the ice-ball ammo (that shows in the
-- hand, HeldBalls). Client-only, anchored, non-colliding parts like the towers; nothing here touches gameplay. It
-- follows the torso, so it leans and falls with the movement pose.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Look = require(Config:WaitForChild("Backpack"))
local Palette = require(Config:WaitForChild("Palette"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))

local Backpacks = {}

type Pack = {
	model: Model,
	parts: { BasePart }, -- all of them, for the first-person fade
	cone: { Part }, -- segments from the opening down
	rim: Part,
	tip: Part,
	straps: { Part }, -- front left, front right, over the left shoulder, over the right shoulder
	moveParts: { BasePart },
	moveCFrames: { CFrame },
	torsoSize: Vector3?, -- the torso size the parts are built for
	shown: boolean,
	fade: number,
}

local STEP = "WobbleBackpacks"
local CYLINDER_UP = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X
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
		moveParts = {},
		moveCFrames = {},
		torsoSize = nil,
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
	-- the order place() writes the CFrames in
	for _, part in pack.cone do
		table.insert(pack.moveParts, part)
	end
	table.insert(pack.moveParts, pack.rim)
	table.insert(pack.moveParts, pack.tip)
	for _, strap in pack.straps do
		table.insert(pack.moveParts, strap)
	end
	return pack
end

-- Sizes for one torso size.
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

local function torsoOf(character: Model): BasePart?
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	return if torso and torso:IsA("BasePart") then torso else nil
end

-- The waffle's frame on a torso (centre on the cone axis, +Y towards the opening) and its scale. The one place the
-- waffle's position comes from: the backpack parts and the scoop tower standing in it (Backpacks.opening) both use
-- it, so the two can never drift apart.
local function coneFrame(torso: BasePart): (CFrame, number)
	local torsoSize = torso.Size
	local s = torsoSize.Y / Look.referenceTorsoHeight
	-- back is +Z in the torso's frame
	local back = torsoSize.Z / 2 + AXIS_BACK * s
	return torso.CFrame * CFrame.new(0, Look.coneUp * s, back) * CFrame.Angles(Look.coneTilt, 0, 0), s
end

-- Moves every part and returns the opening's position and the scale, for the local camera fade.
local function place(pack: Pack, torso: BasePart): (Vector3, number)
	local torsoSize = torso.Size
	if pack.torsoSize ~= torsoSize then
		resize(pack, torsoSize)
	end
	local cone, s = coneFrame(torso)
	local length = Look.coneLength * s
	local torsoCFrame = torso.CFrame

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

	workspace:BulkMoveTo(pack.moveParts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	return (cone * CFrame.new(0, length / 2, 0)).Position, s
end

local function onRenderStep()
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

		local opening, s = place(pack, torso)
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

-- The centre and radius of a character's waffle opening this frame, for the scoop tower that stands in it; nil while
-- the backpack is not shown on that character (no torso, dead, knocked down). Call it after the movement pose
-- (RenderPriority.Character + 2) so it matches the drawn waffle.
function Backpacks.opening(character: Model): (Vector3?, number)
	local torso = torsoOf(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not torso or not humanoid or humanoid.Health <= 0 or torso.CFrame.UpVector.Y < Look.minUpright then
		return nil, 0
	end
	local cone, s = coneFrame(torso)
	return (cone * CFrame.new(0, Look.coneLength * s / 2, 0)).Position, Look.coneTopDiameter / 2 * s
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
