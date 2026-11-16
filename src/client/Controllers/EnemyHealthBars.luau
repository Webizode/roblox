-- The life bar over rivals (Config/Combat healthBar, HealthPips, HealthBarView): the same bar as the own one under the
-- crosshair (KnockMeter), small, over each rival's head, above their name and below a WANTED badge. Only in the arena
-- (both the local player and the rival), never over the own character, and only for rivals near by, close to the
-- crosshair or just hit, at most a few at once. Never through cover: a rival whose head and body are both hidden from
-- the camera (the throw rule, MapQuery.throwRaycast) has no bar, so it gives no hiding place away. Sight is checked a
-- few times a second per rival, spread over the frames. Everything shown comes from the attributes the server sets
-- on each player (KnockPoints, KnockResetAt, KnockProtectedUntil, DownUntil, InArena); nothing here decides anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HitPoints = require(Shared:WaitForChild("HitPoints"))
local HealthPips = require(Shared:WaitForChild("HealthPips"))
local MapQuery = require(Shared:WaitForChild("MapQuery"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))

local client = script.Parent.Parent
local HealthBarView = require(client:WaitForChild("HealthBarView"))

local EnemyHealthBars = {}

local Knock = CombatConfig.knock
local Bar = CombatConfig.healthBar
local Board = Bar.billboard

type Entry = {
	billboard: BillboardGui,
	view: HealthBarView.View,
	shown: number, -- share of the bar drawn (refills over Bar.refill)
	alpha: number,
	lastResetAt: number?,
	seen: boolean, -- the last sight check found them in plain sight
	nextCheck: number, -- os.clock() of the next sight check
}

local player = Players.LocalPlayer
local entries: { [Instance]: Entry } = {}
local spread = 0 -- staggers the first sight checks of new entries

local function number(who: Instance, name: string): number
	local value = who:GetAttribute(name)
	return if type(value) == "number" and value == value then value else 0
end

local function entryOf(who: Instance, id: number): Entry
	local entry = entries[who]
	if entry then
		return entry
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar_" .. id
	billboard.AlwaysOnTop = true -- cover hides it by the sight check, not by depth (a tower must not cut it)
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.MaxDistance = Board.maxDistance
	billboard.Size = UDim2.new(Board.studsWide, Board.pixelsWide, Board.studsHigh, Board.pixelsHigh)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, Board.above, 0)
	billboard.Enabled = false
	local view = HealthBarView.new(1.5)
	view.root.Size = UDim2.fromScale(1, 1)
	view.root.Parent = billboard
	billboard.Parent = player:WaitForChild("PlayerGui")
	spread = (spread + 0.37) % 1
	entry = {
		billboard = billboard,
		view = view,
		shown = 1,
		alpha = 0,
		lastResetAt = nil,
		seen = false,
		nextCheck = os.clock() + spread / Bar.checksPerSecond,
	}
	entries[who] = entry
	return entry
end

local function remove(who: Instance)
	local entry = entries[who]
	if entry then
		entry.billboard:Destroy()
		entries[who] = nil
	end
end

type Rival = { key: Instance, id: number, body: Model? }

local DUMMIES = "HealthBarDummies" -- Studio only: figures in this Workspace folder count as rivals
local dummyIds: { [Instance]: number } = {}
local lastDummyId = 0

-- every other player; in Studio also the test figures in Workspace.HealthBarDummies (a Model with a Humanoid and the
-- same attributes a player has), since the MCP starts only one player
local function rivals(): { Rival }
	local list: { Rival } = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(list, { key = other, id = other.UserId, body = other.Character })
		end
	end
	local folder = RunService:IsStudio() and workspace:FindFirstChild(DUMMIES)
	if folder then
		for _, figure in folder:GetChildren() do
			if figure:IsA("Model") then
				if not dummyIds[figure] then
					lastDummyId -= 1
					dummyIds[figure] = lastDummyId
				end
				table.insert(list, { key = figure, id = dummyIds[figure], body = figure })
			end
		end
	end
	return list
end

-- whether the camera sees the rival's head or body past everything a ball stops at
local function inSight(origin: Vector3, head: BasePart, root: BasePart, ignore: { Instance }): boolean
	if MapQuery.throwRaycast(origin, head.Position - origin, ignore) == nil then
		return true
	end
	return MapQuery.throwRaycast(origin, root.Position - origin, ignore) == nil
end

local function onStep(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local clock = os.clock()
	local now = workspace:GetServerTimeNow()
	local origin, look = camera.CFrame.Position, camera.CFrame.LookVector
	local inArena = player:GetAttribute("InArena") == true

	-- what a sight ray passes: every character (they do not hide each other) and the client-only visuals
	local ignore: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	for _, name in { "LocalVisuals", DUMMIES } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end

	local candidates: { HealthPips.Candidate } = {}
	local heads: { [Instance]: BasePart } = {}
	local ids: { [Instance]: number } = {}
	for _, rival in rivals() do
		local other, body = rival.key, rival.body
		ids[other] = rival.id
		local entry = entryOf(other, rival.id)
		local head = body and body:FindFirstChild("Head") :: BasePart?
		local root = body and body:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = body and body:FindFirstChildOfClass("Humanoid")
		local resetAt = number(other, "KnockResetAt")
		if entry.lastResetAt ~= nil and resetAt ~= entry.lastResetAt then
			entry.view.hit(clock) -- a new counted hit moved their reset time
		end
		entry.lastResetAt = resetAt
		if not (inArena and head and root and humanoid and humanoid.Health > 0) then
			entry.seen = false
			continue
		end
		if other:GetAttribute("InArena") ~= true then
			entry.seen = false
			continue
		end
		heads[other] = head :: BasePart
		local to = (head :: BasePart).Position - origin
		local distance = to.Magnitude
		if distance > Board.maxDistance then
			entry.seen = false
			continue
		end
		if clock >= entry.nextCheck then
			entry.nextCheck = clock + 1 / Bar.checksPerSecond
			entry.seen = inSight(origin, head :: BasePart, root :: BasePart, ignore)
		end
		if not entry.seen then
			continue
		end
		local angle = if distance > 1e-3 then math.deg(math.acos(math.clamp(look:Dot(to.Unit), -1, 1))) else 0
		local sinceHit = now - HealthPips.hitAt(resetAt, Knock)
		table.insert(candidates, { id = rival.id, distance = distance, angle = angle, sinceHit = sinceHit })
	end
	local picked = HealthPips.pick(candidates, Bar)

	for other, entry in entries do
		if not ids[other] then
			remove(other) -- a Studio test figure that is gone
			dummyIds[other] = nil
			continue
		end
		local show = picked[ids[other]] == true
		entry.alpha = math.clamp(entry.alpha + (if show then dt else -dt) / Bar.fade, 0, 1)
		-- the share drawn follows the server even while hidden, so a bar fading in shows the present, no old refill
		local points, protected = HitPoints.display(
			number(other, "KnockPoints"),
			number(other, "KnockResetAt"),
			number(other, "KnockProtectedUntil"),
			now,
			Knock
		)
		local down = now < number(other, "DownUntil")
		local target = if down then 0 else HealthPips.left(points, Knock)
		entry.shown = HealthPips.approach(entry.shown, target, dt, Bar.refill)
		local head = heads[other]
		if not head then
			entry.alpha = 0
		end
		if entry.alpha <= 0 then
			entry.billboard.Enabled = false
			continue
		end
		entry.billboard.Adornee = head
		entry.billboard.Enabled = true
		entry.view.set(entry.shown, HealthPips.tone(entry.shown, down, protected, Bar))
		entry.view.step(clock)
		entry.view.setAlpha(entry.alpha * (if down then 0.6 else 1))
	end
end

function EnemyHealthBars.Start()
	Players.PlayerRemoving:Connect(remove)
	RunService.RenderStepped:Connect(onStep)
end

return EnemyHealthBars
