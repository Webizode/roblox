-- Draws scoops in flight and their landing circles, and claims a catch when a scoop touches the local tower.
-- The touch test sweeps the path between two frames against the whole tower column (cone tip to the free slot
-- on top), so a scoop that flies into the side of a tall tower is caught instead of passing through it.
-- The claim carries the server time of the touch and the tilt at that moment; the server replays exactly that.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ShotMath = require(Shared:WaitForChild("ShotMath"))
local Tuning = require(Config:WaitForChild("Launcher"))
local Features = require(Config:WaitForChild("Features"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))

local ShotRenderer = {}

type Shot = {
	path: ShotMath.Path,
	to: Vector3,
	t0: number,
	flight: number,
	apexAlpha: number,
	lastAlpha: number,
	flavorId: string,
	part: Part,
	circle: Part,
	claimed: boolean,
}

local CIRCLE_SIZE = 7
local CIRCLE_ROTATION = CFrame.Angles(0, 0, math.rad(90))

local player = Players.LocalPlayer
local registry
local shots: { [number]: Shot } = {}

local function makePart(): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = TowerVisual.root()
	return part
end

local function remove(id: number)
	local shot = shots[id]
	if shot then
		shots[id] = nil
		shot.part:Destroy()
		shot.circle:Destroy()
	end
end

-- A puddle where the scoop hits the ground: below its current position, which is the landing point for a
-- scoop nobody caught and the tower top for a claim the server turned down.
local function splat(shot: Shot)
	local position = shot.part.Position
	local puddle = makePart()
	puddle.Shape = Enum.PartType.Cylinder
	puddle.Size = Vector3.new(0.15, 3, 3)
	puddle.CFrame = CFrame.new(position.X, shot.to.Y + 0.1, position.Z) * CIRCLE_ROTATION
	TowerVisual.applyFlavor(puddle, shot.flavorId)
	TweenService:Create(puddle, TweenInfo.new(1.2), { Transparency = 1, Size = Vector3.new(0.15, 4.5, 4.5) }):Play()
	task.delay(1.3, function()
		puddle:Destroy()
	end)
end

local function onShotFired(
	id: number,
	flavorId: string,
	from: Vector3,
	to: Vector3,
	apex: number,
	t0: number,
	flight: number
)
	local part = makePart()
	part.Name = "Scoop"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2, 2, 2)
	part.CFrame = CFrame.new(from)
	TowerVisual.applyFlavor(part, flavorId)

	local circle = makePart()
	circle.Name = "LandingCircle"
	circle.Shape = Enum.PartType.Cylinder
	circle.Size = Vector3.new(0.2, CIRCLE_SIZE, CIRCLE_SIZE)
	circle.CFrame = CFrame.new(to + Vector3.new(0, 0.12, 0)) * CIRCLE_ROTATION
	circle.Transparency = 0.5
	TowerVisual.applyFlavor(circle, flavorId)
	circle.Material = Enum.Material.Neon

	shots[id] = {
		path = { fx = from.X, fy = from.Y, fz = from.Z, tx = to.X, ty = to.Y, tz = to.Z, apex = apex },
		to = to,
		t0 = t0,
		flight = flight,
		apexAlpha = ShotMath.apexAlpha(from.Y, to.Y, apex),
		lastAlpha = (workspace:GetServerTimeNow() - t0) / flight,
		flavorId = flavorId,
		part = part,
		circle = circle,
		claimed = false,
	}
end

local function onShotResolved(id: number, catcher: Player?)
	local shot = shots[id]
	if not shot then
		return
	end
	if catcher ~= player then
		if shot.claimed and Features.debugCatch then
			print(string.format("[Catch] claim for shot %d was not accepted (reason in the server output)", id))
		end
		if catcher == nil then
			splat(shot)
		end
	end
	-- caught by us: TowerChanged already put the scoop into the stack
	remove(id)
end

local function claim(id: number, shot: Shot, alpha: number, tiltX: number, tiltZ: number)
	shot.claimed = true
	shot.circle.Transparency = 1
	Remotes.CatchClaim:FireServer(id, shot.t0 + alpha * shot.flight, tiltX, tiltZ)
end

local function onRenderStep()
	local now = workspace:GetServerTimeNow()
	local column, tiltX, tiltZ = registry.TowerController.catchColumn()
	local top = registry.TowerController.topPosition()
	for id, shot in shots do
		local alpha = (now - shot.t0) / shot.flight
		if alpha > Tuning.resolveAfter + 0.5 then
			-- the resolve message got lost; do not keep orphans around
			remove(id)
			continue
		end

		if shot.claimed then
			-- predicted catch: the scoop rides on top of the tower until the server answers
			if top then
				shot.part.CFrame = CFrame.new(top)
			end
			continue
		end

		local path = shot.path
		local x, y, z = ShotMath.position(path.fx, path.fy, path.fz, path.tx, path.ty, path.tz, path.apex, alpha)
		shot.part.CFrame = CFrame.new(x, y, z)
		local size = CIRCLE_SIZE * (1 - 0.6 * math.clamp(alpha, 0, 1))
		shot.circle.Size = Vector3.new(0.2, size, size)

		if column then
			local from = math.max(shot.lastAlpha, shot.apexAlpha - Tuning.apexSlack)
			local to = math.min(alpha, Tuning.catchWindowEnd)
			local hit = ShotMath.firstContact(path, from, to, column, Tuning.catchRadius, Tuning.contactStep)
			if hit then
				claim(id, shot, hit, tiltX, tiltZ)
			end
		end
		shot.lastAlpha = alpha
	end
end

function ShotRenderer.Init(reg)
	registry = reg
end

function ShotRenderer.Start()
	Remotes.ShotFired.OnClientEvent:Connect(onShotFired)
	Remotes.ShotResolved.OnClientEvent:Connect(onShotResolved)
	-- after TowerController, so the column matches where the tower is drawn this frame
	RunService:BindToRenderStep("WobbleShots", registry.TowerController.RENDER_PRIORITY + 1, onRenderStep)
end

return ShotRenderer
