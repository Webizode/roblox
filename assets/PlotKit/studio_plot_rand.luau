--!nocheck
-- Closes the edge of all 12 plot islands (Edit mode, command bar or Studio MCP). Map Check 2026-11-11, B1 + B2.
--
-- Before: the plot fence (u +-48, v +-24 in the plot's frame, PlotLayout) had a gap of 32 at the bridge (u -16..16)
-- while the bridge is 18 wide, and the fence (4.4 high) could be jumped (jump height 7.2). Players walked or jumped
-- into the sea beside the bridge and lost their tower.
--
-- This script
--   * builds Ice Cream Map.Sperre.Plotrand.Plot_NN: invisible walls up to y 40 (like Sperre.Hubzaun) on the fence
--     line all round, plus a short corridor at u +-8.35 from the island's inner edge to the fence, in line with the
--     walls over the bridge railings (Sperre.Bruecken), with a round post where they meet. The only way out is the
--     bridge. Sperre only stops players (Config/Map.playersOnlyFolders), throws and cameras see through.
--   * narrows the visible gap to the bridge: one FenceSection more on each side (a copy of the plot's own section, so
--     it keeps the flavour colours) and the gap's FencePost moved from u -16 to u -9.5. These pieces carry the
--     attribute PlotRand = true.
-- Running it again rebuilds the walls and the two sections; the post is set to its place again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapConfig = require(Shared.Config.Map)
local PlotLayout = require(Shared.PlotLayout)

local Y = MapConfig.plot.surfaceY -- 9
local TOP = 40 -- like Sperre.Hubzaun and the arena's Sperre
local THICK = 1.8
local FENCE_U, FENCE_V = 48, 24
local LANE = 8.35 -- the walls over the bridge railings stand at u +-8.35 and end at the island's edge (v -29.85)
local EDGE_V = -MapConfig.plot.depth / 2 -- -30
local POST_U = -9.5 -- the gap's FencePost, at the bridgehead path's left edge
local SECTION_U = { 13.6, -13.45 } -- pivots of the two added sections (they run +u with the post at their -u end)

local map = workspace["Ice Cream Map"]
local sperre = map:FindFirstChild("Sperre")
assert(sperre, "Ice Cream Map.Sperre is missing")

local old = sperre:FindFirstChild("Plotrand")
if old then
	old:Destroy()
end
local root = Instance.new("Folder")
root.Name = "Plotrand"

-- a wall from (u1, v1) to (u2, v2) on the plot's frame, THICK thick, from the surface up to TOP
local function wall(parent, frame, u1, v1, u2, v2)
	local x1, z1 = PlotLayout.toWorld(frame, u1, v1)
	local x2, z2 = PlotLayout.toWorld(frame, u2, v2)
	local a, b = Vector3.new(x1, 0, z1), Vector3.new(x2, 0, z2)
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	local h = TOP - Y
	local p = Instance.new("Part")
	p.Name = "Sperre_Plotrand"
	p.Size = Vector3.new(THICK, h, length)
	p.CFrame = CFrame.lookAt(Vector3.new(mid.X, Y + h / 2, mid.Z), Vector3.new(b.X, Y + h / 2, b.Z))
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
end

-- an upright invisible cylinder at (u, v), CORNER_D across, from the surface up to TOP
local CORNER_D = THICK -- flush with the walls: 2 across stood 0.1 proud and caught players too
local function round(parent, frame, u, v)
	local x, z = PlotLayout.toWorld(frame, u, v)
	local h = TOP - Y
	local p = Instance.new("Part")
	p.Name = "Sperre_Plotrand_Ecke"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(h, CORNER_D, CORNER_D)
	p.CFrame = CFrame.new(x, Y + h / 2, z) * CFrame.Angles(0, 0, math.rad(90)) -- the cylinder's axis (X) up
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
end

-- the fence pieces at the gap lose their own collision: the wall over them (Sperre) stops players exactly there,
-- and their post corners stuck into the rounded corner by a few hundredths and caught players
local function quiet(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name:sub(1, 9) == "Collision" then
			d.CanCollide = false
			d.CanQuery = false
		end
	end
end

local report = {}
for _, plot in map.Plots:GetChildren() do
	local index = PlotLayout.indexOf(plot.Name)
	if not index then
		continue
	end
	local frame = PlotLayout.frame(PlotLayout.laneAngle(index, MapConfig), MapConfig)
	local f = Instance.new("Folder")
	f.Name = plot.Name
	local o = THICK / 2 -- overlap at the corners, so no gap
	wall(f, frame, -FENCE_U - o, FENCE_V, FENCE_U + o, FENCE_V) -- back
	wall(f, frame, FENCE_U, -FENCE_V - o, FENCE_U, FENCE_V + o) -- right
	wall(f, frame, -FENCE_U, -FENCE_V - o, -FENCE_U, FENCE_V + o) -- left
	wall(f, frame, LANE, -FENCE_V, FENCE_U + o, -FENCE_V) -- front, right of the bridge
	wall(f, frame, -FENCE_U - o, -FENCE_V, -LANE, -FENCE_V) -- front, left of the bridge
	wall(f, frame, LANE, EDGE_V - 0.5, LANE, -FENCE_V) -- the bridgehead's sides, on from the bridge walls
	wall(f, frame, -LANE, EDGE_V - 0.5, -LANE, -FENCE_V)
	-- where a side meets the front the corner points into the walkway: a square corner there caught players turning
	-- off the bridge (playtest 11.11.2026), a round post lets them slide round it (and covers the fence posts' corners)
	round(f, frame, LANE, -FENCE_V)
	round(f, frame, -LANE, -FENCE_V)
	f.Parent = root

	-- the visible fence: two more sections at the gap, the post at its new place
	local kit = plot:FindFirstChild("PlotKit")
	if kit then
		for _, m in kit:GetChildren() do
			if m:GetAttribute("PlotRand") then
				m:Destroy()
			end
		end
		local template, post
		for _, m in kit:GetChildren() do
			local p = m:GetPivot().Position
			local u, v = PlotLayout.toLocal(frame, p.X, p.Z)
			if m.Name == "FenceSection" and math.abs(v + FENCE_V) < 0.5 and math.abs(u - 20) < 0.5 then
				template = m
			elseif m.Name == "FencePost" and math.abs(v + FENCE_V) < 0.5 and u < 0 and u > -17 then
				post = m
			end
		end
		if template then
			local pv = template:GetPivot()
			local ux, uz = frame.rightX, frame.rightZ
			for _, u in SECTION_U do
				local copy = template:Clone()
				copy:SetAttribute("PlotRand", true)
				copy:PivotTo(pv + Vector3.new(ux, 0, uz) * (u - 20))
				quiet(copy)
				copy.Parent = kit
			end
		end
		if post then
			local p = post:GetPivot()
			local u = PlotLayout.toLocal(frame, p.Position.X, p.Position.Z)
			post:PivotTo(p + Vector3.new(frame.rightX, 0, frame.rightZ) * (POST_U - u))
			quiet(post)
		end
		table.insert(report, string.format("%s: walls 7 + 2 round corners, sections %s, post %s", plot.Name, template and "2" or "MISSING", post and "moved" or "MISSING"))
	end
end
root.Parent = sperre
table.sort(report)
print("[Plotrand] " .. table.concat(report, " | "))
return table.concat(report, "\n")
