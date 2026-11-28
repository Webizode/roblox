-- Aiming at a rival's tower names its rarest scoop for a moment (user 28.11.2026): "LEGENDARY Tiramisu" over that
-- scoop in its rarity's colour (TowerNameTag, Config/TowerScoops nameTag.peek). Aiming is the crosshair in combat mode
-- (the middle of the screen), otherwise the mouse on a device that has one. A tower behind a wall does not count. The
-- name shows once per look; aiming away and back after `again` seconds shows it again. Looks only, every `check`
-- seconds, so 11 rivals cost a few ray tests per second.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Look = require(Config:WaitForChild("TowerScoops"))
local Flavors = require(Config:WaitForChild("Flavors"))
local TowerMarks = require(Shared:WaitForChild("TowerMarks"))
local MapQuery = require(Shared:WaitForChild("MapQuery"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))
local TowerNameTag = require(client:WaitForChild("TowerNameTag"))

local TowerPeek = {}

local PEEK = Look.nameTag.peek
local player = Players.LocalPlayer
local registry
local aimed: any = nil -- the TowerVisual aimed at last look
local shownAt: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any -- os.clock its name last showed
local tag: TowerNameTag.Tag? = nil
local waited = 0

-- The screen point one aims with now, or nil (a touch screen outside combat mode has no pointer).
local function aimPoint(camera: Camera): Vector2?
	if registry.CombatController.inCombatMode() then
		return camera.ViewportSize / 2
	end
	if UserInputService.MouseEnabled then
		return UserInputService:GetMouseLocation()
	end
	return nil
end

-- The rival tower under the aim, the nearest when several line up, or nil.
local function aimedTower(): any
	local camera = workspace.CurrentCamera
	local screen = camera and aimPoint(camera)
	if not camera or not screen then
		return nil
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local o, d = ray.Origin, ray.Direction.Unit
	local best, bestDistance = nil, math.huge
	for _, visual in registry.RemoteTowers.visuals() do
		if #visual.scoops == 0 then
			continue
		end
		local a, b = visual.base, visual:topPosition()
		local along = TowerMarks.rayHitsColumn(
			o.X,
			o.Y,
			o.Z,
			d.X,
			d.Y,
			d.Z,
			a.X,
			a.Y,
			a.Z,
			b.X,
			b.Y,
			b.Z,
			PEEK.radius,
			PEEK.maxDistance
		)
		if along and along < bestDistance then
			best, bestDistance = visual, along
		end
	end
	if not best then
		return nil
	end
	-- a wall between: not aimed at (characters, towers and scoops do not block)
	local ignore: { Instance } = { TowerVisual.root() }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local hit = MapQuery.throwRaycast(o, d * bestDistance, ignore)
	if hit and (hit.Position - o).Magnitude < bestDistance - PEEK.radius then
		return nil
	end
	return best
end

local function look()
	local visual = aimedTower()
	if visual == aimed then
		return
	end
	aimed = visual
	if not visual then
		return
	end
	local now = os.clock()
	if now - (shownAt[visual] or -math.huge) < PEEK.again then
		return
	end
	local index = TowerMarks.rarest(visual.flavors, Flavors.byId, Flavors.rarities)
	local part = index and visual:scoopPart(index)
	if not index or not part then
		return
	end
	shownAt[visual] = now
	TowerNameTag.hide(tag)
	tag = TowerNameTag.show(part, visual.flavors[index])
end

function TowerPeek.Init(reg)
	registry = reg
end

function TowerPeek.Start()
	RunService.Heartbeat:Connect(function(dt)
		waited += dt
		if waited < PEEK.check or not player.Character then
			return
		end
		waited = 0
		look()
	end)
end

return TowerPeek
