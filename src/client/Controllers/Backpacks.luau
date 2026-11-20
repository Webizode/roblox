-- The waffle-cone backpack on every character: the waffle from Blender (assets/Backpack, ReplicatedStorage.BackpackKit)
-- with its glaze in the colour of the owner's plot, or the old stepped cylinders while that kit is missing. An empty
-- waffle: it belongs to the collecting and tower side of the game, and what it will show there is still open. It is not the ice-ball ammo (that shows in the
-- hand, HeldBalls). Client-only, anchored, non-colliding parts like the towers; nothing here touches gameplay. It
-- follows the torso, so it leans and falls with the movement pose.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TowerShape = require(Shared:WaitForChild("TowerShape"))
local Look = require(Config:WaitForChild("Backpack"))
local Palette = require(Config:WaitForChild("Palette"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))

local Backpacks = {}

type Pack = {
	model: Model,
	parts: { BasePart }, -- all of them, for the first-person fade
	-- the Blender waffle (Config/Backpack meshes): its meshes in MESH_ORDER, nil while the kit is missing
	meshes: { BasePart }?,
	glaze: BasePart?,
	cone: { Part }, -- the old stepped waffle: segments from the opening down (empty with the meshes)
	rim: Part?,
	tip: Part?,
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
local RIM_LIFT = 0.03 -- studs (before scaling)
-- the cone axis sits this far behind the back (before scaling), so the rim's lower near edge, the point closest
-- to the back, keeps coneBack from it
local AXIS_BACK = Look.coneBack
	+ math.cos(Look.coneTilt) * RIM_RADIUS
	- math.sin(Look.coneTilt) * (Look.coneLength / 2 - Look.rimHeight)

local localPlayer = Players.LocalPlayer
local packs: { [Player]: Pack } = {}

local MESH_ORDER = { "waffle", "lines", "rim", "glaze" }
local MESH_NAMES = { waffle = "Waffle", lines = "Lines", rim = "Rim", glaze = "Glaze" }

-- The Blender waffle's four templates (ReplicatedStorage.<Look.kit>), or nil while they are not all there.
local function kitMeshes(): { [string]: MeshPart }?
	local kit = ReplicatedStorage:FindFirstChild(Look.kit)
	if not kit then
		return nil
	end
	local out = {}
	for _, key in MESH_ORDER do
		local mesh = kit:FindFirstChild(MESH_NAMES[key])
		if not (mesh and mesh:IsA("MeshPart")) then
			return nil
		end
		out[key] = mesh
	end
	return out
end

-- The glaze colour of a player's waffle: their plot's flavour (Palette.plotFlavors by the number in PlotName).
local function glazeColor(player: Player): Color3
	local plotName = player:GetAttribute("PlotName")
	local index = type(plotName) == "string" and tonumber(string.match(plotName, "%d+")) or nil
	local hex = index and Palette.plotFlavors[index]
	return Color3.fromHex(hex or Look.glazeFallback)
end

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
		meshes = nil,
		glaze = nil,
		cone = {},
		rim = nil,
		tip = nil,
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
	local kit = kitMeshes()
	if kit then
		-- the Blender waffle: copies of the four templates, the glaze in the plot's colour
		local meshes = {}
		for _, key in MESH_ORDER do
			local mesh = kit[key]:Clone()
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.Massless = true
			local spec = Look.meshes[key]
			if spec.color then
				mesh.Color = Color3.fromHex(spec.color)
			end
			mesh.Parent = model
			table.insert(meshes, mesh)
			table.insert(pack.parts, mesh)
		end
		pack.meshes = meshes
		local glaze = meshes[table.find(MESH_ORDER, "glaze") :: number]
		glaze.Color = glazeColor(player)
		pack.glaze = glaze
	else
		for _ = 1, Look.coneSegments do
			table.insert(pack.cone, add("Waffle", Enum.PartType.Cylinder, Palette.waffle, Enum.Material.SmoothPlastic))
		end
		pack.rim = add("Rim", Enum.PartType.Cylinder, Palette.chocolate, Enum.Material.SmoothPlastic)
		pack.tip = add("Tip", Enum.PartType.Ball, Palette.waffle, Enum.Material.SmoothPlastic)
	end
	for _ = 1, 4 do
		local strap = add("Strap", Enum.PartType.Block, Palette.chocolate, Enum.Material.SmoothPlastic)
		strap.CastShadow = false
		table.insert(pack.straps, strap)
	end
	-- the order place() writes the CFrames in
	if pack.meshes then
		for _, mesh in pack.meshes do
			table.insert(pack.moveParts, mesh)
		end
	else
		for _, part in pack.cone do
			table.insert(pack.moveParts, part)
		end
		table.insert(pack.moveParts, pack.rim :: Part)
		table.insert(pack.moveParts, pack.tip :: Part)
	end
	for _, strap in pack.straps do
		table.insert(pack.moveParts, strap)
	end
	return pack
end

-- Sizes for one torso size.
-- How far the over-shoulder straps run on behind the back: to the rim, which a bigger waffle moves further back
-- (coneFrame). `body` is the torso's scale, `s` the waffle's.
local function strapReach(body: number, s: number): number
	return Look.strapReach * body + (s - body) * Look.coneTopDiameter / 2
end

local function resize(pack: Pack, torsoSize: Vector3)
	pack.torsoSize = torsoSize
	local body = torsoSize.Y / Look.referenceTorsoHeight
	local s = body * Look.waffleScale -- the waffle; the straps follow the body
	local segment = Look.coneLength / Look.coneSegments
	for index, part in pack.cone do
		local share = (index - 0.5) / Look.coneSegments
		local diameter = Look.coneTopDiameter + (Look.coneTipDiameter - Look.coneTopDiameter) * share
		part.Size = Vector3.new(segment, diameter, diameter) * s
	end
	if pack.meshes then
		for index, mesh in pack.meshes do
			local size = Look.meshes[MESH_ORDER[index]].size
			mesh.Size = Vector3.new(size[1], size[2], size[3]) * s
		end
	else
		local rimPart, tipPart = pack.rim :: Part, pack.tip :: Part
		local rim = 2 * RIM_RADIUS
		rimPart.Size = Vector3.new(Look.rimHeight, rim, rim) * s
		tipPart.Size = Vector3.one * Look.coneTipDiameter * s
	end
	local width, thickness = Look.strapWidth * body, Look.strapThickness * body
	local front = Vector3.new(width, torsoSize.Y * 0.95, thickness)
	local over = Vector3.new(width, thickness, torsoSize.Z + 2 * thickness + strapReach(body, s))
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

-- The waffle's frame on a torso (centre on the cone axis, +Y towards the opening) and its scale (the body's times
-- Look.waffleScale). The one place the waffle's position comes from: the backpack parts and the scoop tower standing
-- in it (Backpacks.seat) both use it, so the two can never drift apart. A bigger waffle sits further back by as much
-- as it got wider, so its near side still runs along the back instead of into it.
local function coneFrame(torso: BasePart): (CFrame, number)
	local torsoSize = torso.Size
	local body = torsoSize.Y / Look.referenceTorsoHeight
	local s = body * Look.waffleScale
	-- back is +Z in the torso's frame
	local back = torsoSize.Z / 2 + AXIS_BACK * body + (s - body) * Look.coneTopDiameter / 2
	return torso.CFrame * CFrame.new(0, Look.coneUp * body, back) * CFrame.Angles(Look.coneTilt, 0, 0), s
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

	if pack.meshes then
		-- each mesh at its centre in the cone's frame (Config/Backpack meshes), scaled with the torso
		for index in pack.meshes do
			local centre = Look.meshes[MESH_ORDER[index]].centre
			count += 1
			cframes[count] = cone * CFrame.new(centre[1] * s, centre[2] * s, centre[3] * s)
		end
	else
		local segment = length / Look.coneSegments
		for index in pack.cone do
			count += 1
			cframes[count] = cone * CFrame.new(0, length / 2 - (index - 0.5) * segment, 0) * CYLINDER_UP
		end
		-- the rim stands RIM_LIFT above the top segment: with both top faces in one plane they flickered (z-fighting)
		cframes[count + 1] = cone * CFrame.new(0, length / 2 - Look.rimHeight * s / 2 + RIM_LIFT * s, 0) * CYLINDER_UP
		cframes[count + 2] = cone * CFrame.new(0, -length / 2, 0)
		count += 2
	end

	local strapX = torsoSize.X * 0.25
	local body = torsoSize.Y / Look.referenceTorsoHeight
	local thickness = Look.strapThickness * body
	local frontZ = -(torsoSize.Z / 2 + thickness / 2)
	local overY = torsoSize.Y / 2 + thickness / 2
	local overZ = strapReach(body, s) / 2 -- the over-shoulder straps reach back to the rim
	cframes[count + 1] = torsoCFrame * CFrame.new(-strapX, 0, frontZ)
	cframes[count + 2] = torsoCFrame * CFrame.new(strapX, 0, frontZ)
	cframes[count + 3] = torsoCFrame * CFrame.new(-strapX, overY, overZ)
	cframes[count + 4] = torsoCFrame * CFrame.new(strapX, overY, overZ)
	count += 4

	workspace:BulkMoveTo(pack.moveParts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	return (cone * CFrame.new(0, length / 2, 0)).Position, s
end

-- Whether a player lies on the ground knocked down: knocked down (the DownUntil attribute, server time) and the torso
-- tipped below minUpright. Only then does the waffle hide, since it would stick in the floor. The angle alone hid it
-- in a sprinting dash too (the torso leans to about 0.4 there, kill test 13.11.2026).
local function lying(player: Player?, torso: BasePart): boolean
	local downUntil = player and player:GetAttribute("DownUntil")
	return type(downUntil) == "number"
		and workspace:GetServerTimeNow() < downUntil
		and torso.CFrame.UpVector.Y < Look.minUpright
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
			and not lying(player, torso)
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
		-- the plot is handed out after joining: the glaze follows it
		player:GetAttributeChangedSignal("PlotName"):Connect(function()
			local pack = packs[player]
			if pack and pack.glaze then
				pack.glaze.Color = glazeColor(player)
			end
		end)
	end
end

local function untrack(player: Player)
	local pack = packs[player]
	if pack then
		packs[player] = nil
		pack.model:Destroy()
	end
end

-- Where the bottom scoop of a character's tower sits this frame: on the waffle's axis, as high above the chocolate
-- rim's top face as TowerShape.seatInCone says, so it rests in the waffle without cutting through the rim or the
-- wall below it from any side, the cone being tilted. Nil while the backpack is not shown on that character (no
-- torso, dead, knocked down). Call it after the movement pose (RenderPriority.Character + 2) so it matches the drawn
-- waffle.
function Backpacks.seat(character: Model, scoopRadius: number): Vector3?
	local torso = torsoOf(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not torso or not humanoid or humanoid.Health <= 0 or lying(Players:GetPlayerFromCharacter(character), torso) then
		return nil
	end
	local cone, s = coneFrame(torso)
	local length = Look.coneLength * s
	-- the rim's top face, as place() draws it
	local rimTop = cone * CFrame.new(0, length / 2 + RIM_LIFT * s, 0)
	-- the widest waffle segment right below the rim, as resize() sizes it
	local topDiameter = Look.coneTopDiameter + (Look.coneTipDiameter - Look.coneTopDiameter) * 0.5 / Look.coneSegments
	local seat = TowerShape.seatInCone(scoopRadius, {
		rimRadius = RIM_RADIUS * s,
		rimHeight = Look.rimHeight * s,
		topRadius = topDiameter / 2 * s,
		tipRadius = Look.coneTipDiameter / 2 * s,
		length = length - Look.rimHeight * s,
		margin = Look.scoopMargin * s,
	})
	return (rimTop * CFrame.new(0, seat, 0)).Position
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
