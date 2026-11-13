-- The stars circling over a knocked down head (Config/Vfx.knockdownStars): a BillboardGui on the head with a few
-- star pictures going round in a flat circle seen from the side, the near ones bigger and in front. It follows the
-- head by itself, lasts as long as the knockdown and goes back to the pool; one render step moves all of them and
-- stops when none is left.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Vfx"))

local Pool = require(script.Parent:WaitForChild("Pool"))
local Emit = require(script.Parent:WaitForChild("Emit"))

local Stars = {}

local Look = Config.knockdownStars
local STEP = "WobbleVfxStars"

type Halo = { gui: BillboardGui, stars: { ImageLabel }, shown: number, startedAt: number, endsAt: number }

local active: { Halo } = {}
local byHead: { [BasePart]: Halo } = {}
local bound = false

local function build(): Halo
	local gui = Instance.new("BillboardGui")
	gui.Name = "VfxStars"
	gui.Size = UDim2.fromScale(Look.width, Look.width * Look.tilt * 2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, Look.height, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = Config.distance.reduced
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local stars = table.create(Look.count)
	for index = 1, Look.count do
		local star = Instance.new("ImageLabel")
		star.Name = "Star"
		star.BackgroundTransparency = 1
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Image = Config.textures.star
		star.ImageColor3 = Emit.color(Look.color)
		star.SizeConstraint = Enum.SizeConstraint.RelativeXX
		star.Parent = gui
		stars[index] = star
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return { gui = gui, stars = stars, shown = 0, startedAt = 0, endsAt = 0 }
end

local function release(halo: Halo)
	local head = halo.gui.Adornee
	if head and byHead[head :: BasePart] == halo then
		byHead[head :: BasePart] = nil
	end
	halo.gui.Enabled = false
	halo.gui.Adornee = nil
	if halo.gui.Parent then
		Pool.give("stars", halo)
	end
end

local function onStep()
	local now = os.clock()
	for index = #active, 1, -1 do
		local halo = active[index]
		local head = halo.gui.Adornee
		if now >= halo.endsAt or not head or not head:IsDescendantOf(workspace) then
			table.remove(active, index)
			release(halo)
			continue
		end
		-- fades in and out by growing and shrinking
		local fade = math.clamp(math.min(now - halo.startedAt, halo.endsAt - now) / Look.fade, 0, 1)
		local turn = (now - halo.startedAt) * Look.turns * 2 * math.pi
		for starIndex = 1, halo.shown do
			local star = halo.stars[starIndex]
			local angle = turn + starIndex / halo.shown * 2 * math.pi
			local near = (math.sin(angle) + 1) / 2 -- 1 nearest to the camera, 0 farthest
			local size = Look.starSize * (Look.farScale + (1 - Look.farScale) * near) * fade
			star.Position =
				UDim2.fromScale(0.5 + 0.5 * (1 - Look.starSize) * math.cos(angle), 0.5 + 0.3 * math.sin(angle))
			star.Size = UDim2.fromScale(size, size)
			star.Rotation = math.deg(turn * 0.6) + starIndex * 40
			star.ZIndex = if near > 0.5 then 2 else 1
		end
	end
	if #active == 0 then
		bound = false
		RunService:UnbindFromRenderStep(STEP)
	end
end

-- `count` stars over `head` for `seconds`. A head that already has stars keeps them for the new time.
function Stars.play(head: BasePart, count: number, seconds: number)
	if count <= 0 or seconds <= 0 then
		return
	end
	local now = os.clock()
	local running = byHead[head]
	if running then
		running.endsAt = math.max(running.endsAt, now + seconds)
		return
	end
	local halo = Pool.take("stars", build)
	halo.shown = math.min(count, #halo.stars)
	halo.startedAt, halo.endsAt = now, now + seconds
	for index, star in halo.stars do
		star.Visible = index <= halo.shown
		star.Size = UDim2.fromScale(0, 0)
	end
	halo.gui.Adornee = head
	halo.gui.Enabled = true
	byHead[head] = halo
	table.insert(active, halo)
	if not bound then
		bound = true
		RunService:BindToRenderStep(STEP, Enum.RenderPriority.Last.Value, onStep)
	end
end

-- How many heads have stars right now, for checks.
function Stars.running(): number
	return #active
end

return Stars
