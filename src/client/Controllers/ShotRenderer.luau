-- Draws scoops in flight and their landing circles, and claims a catch when a scoop passes the top of the
-- local tower. The server decides; a rejected claim simply splats.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ShotMath = require(Shared:WaitForChild("ShotMath"))
local Tuning = require(Config:WaitForChild("Launcher"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))

local ShotRenderer = {}

type Shot = {
	from: Vector3,
	to: Vector3,
	apex: number,
	t0: number,
	flight: number,
	flavorId: string,
	part: Part,
	circle: Part,
	claimed: boolean,
}

local CIRCLE_SIZE = 7
local CIRCLE_ROTATION = CFrame.Angles(0, 0, math.rad(90))

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

local function splat(shot: Shot)
	local puddle = makePart()
	puddle.Shape = Enum.PartType.Cylinder
	puddle.Size = Vector3.new(0.15, 3, 3)
	puddle.CFrame = CFrame.new(shot.to + Vector3.new(0, 0.1, 0)) * CIRCLE_ROTATION
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
	circle.Material = Enum.Material.Neon
	circle.Transparency = 0.5
	TowerVisual.applyFlavor(circle, flavorId)
	circle.Material = Enum.Material.Neon

	shots[id] = {
		from = from,
		to = to,
		apex = apex,
		t0 = t0,
		flight = flight,
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
	if catcher == nil then
		splat(shot)
	end
	remove(id)
end

local function onRenderStep()
	local now = workspace:GetServerTimeNow()
	local top = registry.TowerController.topPosition()
	for id, shot in shots do
		local alpha = (now - shot.t0) / shot.flight
		if alpha > Tuning.resolveAfter + 0.5 then
			-- the resolve message got lost; do not keep orphans around
			remove(id)
			continue
		end

		local x, y, z =
			ShotMath.position(shot.from.X, shot.from.Y, shot.from.Z, shot.to.X, shot.to.Y, shot.to.Z, shot.apex, alpha)
		shot.part.CFrame = CFrame.new(x, y, z)
		local size = CIRCLE_SIZE * (1 - 0.6 * math.clamp(alpha, 0, 1))
		shot.circle.Size = Vector3.new(0.2, size, size)

		if not shot.claimed and top and alpha >= Tuning.catchWindow[1] and alpha <= Tuning.catchWindow[2] then
			local dx, dz = x - top.X, z - top.Z
			if
				dx * dx + dz * dz <= Tuning.catchRadius * Tuning.catchRadius
				and math.abs(y - top.Y) <= Tuning.catchHeight
			then
				shot.claimed = true
				shot.part.Transparency = 1
				Remotes.CatchClaim:FireServer(id)
			end
		end
	end
end

function ShotRenderer.Init(reg)
	registry = reg
end

function ShotRenderer.Start()
	Remotes.ShotFired.OnClientEvent:Connect(onShotFired)
	Remotes.ShotResolved.OnClientEvent:Connect(onShotResolved)
	RunService.RenderStepped:Connect(onRenderStep)
end

return ShotRenderer
