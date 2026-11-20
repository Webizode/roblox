-- The gummy bounce pads in the arena (Config/Bounce, logic in Bounce): step on one and it throws the local player up
-- at once, on PC, phone and console alike, without a button. The GummyPad throws very high, the GummyBouncer
-- over the high covers; walking onto a bouncer from its side throws too (since 19.11.2026, no more shove). A tower
-- makes the jump lower (Economy.jumpScale) and gets a kick when its carrier lands (TowerController.bounceLanded).
-- Dashes in the air work as always; there is no fall damage.
--
-- The client decides and moves its own character, for a smooth feel; it tells the server (Services/BounceService),
-- which checks it roughly and shows it to the others. The pad squashes (only its meshes, locally: the collision never
-- changes) and springs back, with a puff (Vfx/Effects/Bounce) and a boing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Bounce = require(Shared:WaitForChild("Bounce"))
local Economy = require(Shared:WaitForChild("Economy"))
local BounceConfig = require(Config:WaitForChild("Bounce"))
local EconomyConfig = require(Config:WaitForChild("Economy"))
local MapConfig = require(Config:WaitForChild("Map"))

local client = script.Parent.Parent
local Sfx = require(client:WaitForChild("Sfx"))
local BounceVfx = require(client:WaitForChild("Vfx"):WaitForChild("Effects"):WaitForChild("Bounce"))

local BounceController = {}

local player = Players.LocalPlayer
local registry

-- One pad, by its Model. The arena streams in and out around the player and its parts come back as new instances,
-- so nothing here holds on to parts: the geometry is worked out again from the collision parts there are now.
type Pad = {
	model: Model,
	kind: string,
	tuning: Bounce.Kind,
	pivot: CFrame, -- the floor in its middle (the pads never move)
	floor: number,
	centre: Vector3,
	radius: number,
	top: number,
	squashFrom: number?, -- os.clock() of the running squash
}

local pads: { [Model]: Pad } = {}
-- Each mesh's size and place in its pad's frame at rest, taken once, before it is squashed for the first time, and
-- kept on the part itself (attributes REST_SIZE, REST_OFFSET; local only). Every squash is worked out from it and ends
-- on it, however many players land at once. Team test of 20.11.2026: a bouncer stayed bigger for good. The rest pose
-- was kept in a table with weak keys, and Roblox may drop an Instance key while the part still exists: a part dropped
-- mid-squash was left squashed, and the next bounce took that as its rest size, so the pad grew with every bounce.
local REST_SIZE = "BounceRestSize"
local REST_OFFSET = "BounceRestOffset"

local function restOf(part: BasePart): { size: Vector3, offset: CFrame }?
	local size, offset = part:GetAttribute(REST_SIZE), part:GetAttribute(REST_OFFSET)
	if typeof(size) == "Vector3" and typeof(offset) == "CFrame" then
		return { size = size, offset = offset }
	end
	return nil
end

local lastBounce: number? = nil
local settled: Pad? = nil -- the pad one came back down on after its own jump
local airborne: Pad? = nil -- the pad of the jump in progress (for the tower's landing kick)
-- the launch, held for its first moments: the humanoid still stands in the first frame and eats part of the push
local holding: { root: BasePart, up: number, from: number }? = nil
local HOLD = 0.1 -- seconds
local LIFT = 0.3 -- studs
local EARLY_LANDING = 0.25 -- seconds after a launch in which a landing does not count

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function isCollision(part: Instance): boolean
	return part:IsA("BasePart") and (part.Name == "Collision" or string.sub(part.Name, 1, 10) == "Collision_")
end

-- Radius and top of the pad from its collision parts as they are now; false while none is streamed in.
local function measure(pad: Pad): boolean
	local radius, top, any = 0, -math.huge, false
	for _, part in pad.model:GetDescendants() do
		if isCollision(part) then
			local box = part :: BasePart
			local r = box.CFrame.Rotation
			local size = box.Size
			-- the part's extent along the world axes
			local ex = math.abs(r.XVector.X) * size.X + math.abs(r.YVector.X) * size.Y + math.abs(r.ZVector.X) * size.Z
			local ey = math.abs(r.XVector.Y) * size.X + math.abs(r.YVector.Y) * size.Y + math.abs(r.ZVector.Y) * size.Z
			local ez = math.abs(r.XVector.Z) * size.X + math.abs(r.YVector.Z) * size.Y + math.abs(r.ZVector.Z) * size.Z
			local off = box.Position - pad.centre
			radius = math.max(radius, math.sqrt(off.X * off.X + off.Z * off.Z) + math.max(ex, ez) / 2)
			top = math.max(top, box.Position.Y + ey / 2)
			any = true
		end
	end
	if any then
		pad.radius, pad.top = radius, top
	end
	return any
end

local function padOf(model: Instance?): Pad?
	if not model or not model:IsA("Model") then
		return nil
	end
	local pad = pads[model]
	if not pad then
		local kind = Bounce.kindOf(model.Name, BounceConfig)
		if not kind then
			return nil
		end
		local pivot = model:GetPivot()
		pad = {
			model = model,
			kind = kind,
			tuning = (BounceConfig :: any)[kind],
			pivot = pivot,
			floor = pivot.Position.Y,
			centre = pivot.Position,
			radius = 0,
			top = pivot.Position.Y,
		}
		pads[model] = pad
		model.Destroying:Once(function()
			pads[model] = nil
		end)
	end
	if not measure(pad :: Pad) then
		return nil
	end
	return pad
end

-- The pad a part stood on belongs to, when it is one of a pad's collision parts.
local function padOfPart(part: Instance): Pad?
	if not isCollision(part) then
		return nil
	end
	return padOf(part:FindFirstAncestorOfClass("Model"))
end

-- The arena's pads are looked for now and then (for the bouncers' sides; standing on one needs no list).
local function scan()
	local map = workspace:FindFirstChild(MapConfig.root)
	local cover = map and map:FindFirstChild(MapConfig.coverFolder)
	if not cover then
		return
	end
	for _, item in cover:GetDescendants() do
		if item:IsA("Model") and not pads[item] then
			padOf(item)
		end
	end
end

-- The look of a pad at its squash: every mesh scaled about the pad's pivot (the floor in its middle).
local function pose(pad: Pad, height: number, width: number)
	for _, part in pad.model:GetDescendants() do
		if part:IsA("MeshPart") then
			local base = restOf(part)
			if base then
				local p = base.offset.Position
				local size = base.size
				part.Size = Vector3.new(Bounce.poseSize(size.X, size.Y, size.Z, height, width))
				part.CFrame = pad.pivot * CFrame.new(p.X * width, p.Y * height, p.Z * width) * base.offset.Rotation
			end
		end
	end
end

-- Takes the rest pose of meshes not seen yet (only while the pad is not squashed; a mesh that already has one keeps
-- it for good).
local function remember(pad: Pad)
	if pad.squashFrom then
		return
	end
	for _, part in pad.model:GetDescendants() do
		if part:IsA("MeshPart") and not restOf(part) then
			part:SetAttribute(REST_SIZE, part.Size)
			part:SetAttribute(REST_OFFSET, pad.pivot:ToObjectSpace(part.CFrame))
		end
	end
end

local function effects(pad: Pad, own: boolean)
	remember(pad)
	pad.squashFrom = os.clock()
	local top = Vector3.new(pad.centre.X, pad.top, pad.centre.Z)
	local ok, problem = pcall(function()
		BounceVfx.play(top, pad.floor, own)
		local anchor = pad.model:FindFirstChildWhichIsA("BasePart", true)
		if anchor then
			Sfx.at("bounce", anchor, BounceConfig.hearing)
		end
	end)
	if not ok then
		warn("[Bounce] effects failed: " .. tostring(problem))
	end
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function launch(pad: Pad, root: BasePart, humanoid: Humanoid, feetY: number)
	local count, capacity = registry.TowerController.fill()
	local scale = Economy.jumpScale(count, capacity, EconomyConfig)
	local way = flat(humanoid.MoveDirection)
	if way.Magnitude < 0.05 then
		way = flat(root.CFrame.LookVector)
	end
	local vx, vy, vz = Bounce.launch(pad.tuning, workspace.Gravity, pad.floor, feetY, scale, way.X, way.Z)
	local current = flat(root.AssemblyLinearVelocity)
	-- off the ground first (a jump, lifted a little), or the standing humanoid pulls the root back down in the first frames
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	root.CFrame += Vector3.new(0, LIFT, 0)
	root.AssemblyLinearVelocity = Vector3.new(current.X + vx, vy, current.Z + vz)
	lastBounce = os.clock()
	airborne = pad
	settled = nil
	holding = { root = root, up = vy, from = lastBounce }
	Remotes.Bounce:FireServer(pad.model)
	effects(pad, true)
end

local function step()
	local now = os.clock()
	if holding then
		local elapsed = now - holding.from
		if elapsed > HOLD or not holding.root.Parent then
			holding = nil
		else
			local want = holding.up - workspace.Gravity * elapsed
			local v = holding.root.AssemblyLinearVelocity
			if v.Y < want - 1 then
				holding.root.AssemblyLinearVelocity = Vector3.new(v.X, want, v.Z)
			end
		end
	end
	for _, pad in pads do
		if pad.squashFrom then
			local t = now - pad.squashFrom
			local height, width = Bounce.squashAt(t, pad.tuning.squash, BounceConfig)
			pose(pad, height, width)
			if t > BounceConfig.squashTime + BounceConfig.springTime then
				pad.squashFrom = nil
				pose(pad, 1, 1)
			end
		end
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if not Bounce.ready(lastBounce, now, BounceConfig.cooldown) then
		return
	end
	local feet = root.Size.Y / 2 + humanoid.HipHeight
	local velocity = root.AssemblyLinearVelocity

	-- standing on a pad (or coming down onto it): a short ray from the root down past the feet. Coming back down on
	-- the pad one was thrown from does not throw again (no endless hopping): one stays on it until one steps off or
	-- jumps, and coming down from that jump throws again.
	if velocity.Y < 6 then
		local ignore: { Instance } = {}
		for _, other in Players:GetPlayers() do
			if other.Character then
				table.insert(ignore, other.Character)
			end
		end
		local visuals = workspace:FindFirstChild("LocalVisuals")
		if visuals then
			table.insert(ignore, visuals)
		end
		rayParams.FilterDescendantsInstances = ignore
		-- falling fast it looks a frame ahead, or a small bouncer is passed between two frames
		local reach = feet + math.max(0.6, -velocity.Y / 30)
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
		local pad = hit and padOfPart(hit.Instance)
		if pad and hit then
			if pad == airborne or pad == settled then
				settled = pad
			else
				launch(pad, root, humanoid, hit.Position.Y)
				return
			end
		else
			settled = nil
		end
	else
		settled = nil
	end
end

local function watchLanding(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	airborne = nil
	humanoid.StateChanged:Connect(function(old, new)
		local landed = new == Enum.HumanoidStateType.Landed
			or (new == Enum.HumanoidStateType.Running and old == Enum.HumanoidStateType.Freefall)
		-- the humanoid may still report the ground in the launch's first frames: that is no landing
		if landed and airborne and not (lastBounce and os.clock() - lastBounce < EARLY_LANDING) then
			local pad = airborne
			airborne = nil
			-- a landing on that same pad must not throw again: the landing comes before the next ray down sees it. Landed
			-- anywhere else, that ray misses the pad and clears this again
			settled = pad
			local count = registry.TowerController.fill()
			registry.TowerController.bounceLanded(Bounce.towerKick(pad.tuning, count))
		end
	end)
end

function BounceController.Init(reg)
	registry = reg
end

function BounceController.Start()
	scan()
	task.spawn(function()
		while true do
			task.wait(2)
			scan()
		end
	end)
	Remotes.Bounce.OnClientEvent:Connect(function(_who: Player, model: Model?)
		local pad = padOf(model)
		if pad then
			effects(pad, false)
		end
	end)
	if player.Character then
		task.spawn(watchLanding, player.Character)
	end
	player.CharacterAdded:Connect(watchLanding)
	RunService.Heartbeat:Connect(step)
end

return BounceController
