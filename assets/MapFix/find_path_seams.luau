-- Studio (Edit, run through the MCP or the command bar): finds the seams of the hub walkways (kill test 13.11.2026:
-- gaps and edges between path and lawn, path pieces that do not meet cleanly at bends, curbs that jump). Reads only,
-- changes nothing. For every sector of Dekoracje.Hub (and Einzelstuecke, Platzhalter):
--   steps    two walkway slabs (Weg) that touch, with tops more than STEP apart
--   exposed  a slab whose top stands more than EXPOSED above the peak of the curbs beside it (its side shows)
--   curbGap  two curb cylinders of a bend whose ends are more than CURB_GAP apart (the curb jumps there)
--   wedges   points just outside a curb where the first thing below is neither lawn nor another walkway or curb,
--            with lawn on both sides along the curb (a bright gap between lawn and curb)
-- Prints a summary and returns the list as text.

local STEP = 0.005
local EXPOSED = 0.05
local CURB_GAP = 0.05
local SAMPLE = 0.5 -- studs between samples along a curb
local OUT = 0.15 -- studs outside the curb's outer face

local map = workspace["Ice Cream Map"]
local hub = map.Dekoracje.Hub

local function slabs(container)
	local out = {}
	for _, p in container:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "Weg" then
			table.insert(out, p)
		end
	end
	return out
end

local function curbs(container)
	local out = {}
	for _, p in container:GetDescendants() do
		if p:IsA("Part") and p.Name == "Bordstein" and p.Shape == Enum.PartType.Cylinder then
			table.insert(out, p)
		end
	end
	return out
end

local function top(p)
	return p.Position.Y + p.Size.Y / 2
end

-- horizontal footprint corners of a block
local function corners(p)
	local cf, s = p.CFrame, p.Size
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(out, (cf * CFrame.new(sx * s.X / 2, 0, sz * s.Z / 2)).Position)
		end
	end
	return out
end

local function inside(p, point, margin)
	local l = p.CFrame:PointToObjectSpace(point)
	return math.abs(l.X) <= p.Size.X / 2 + margin and math.abs(l.Z) <= p.Size.Z / 2 + margin
end

local function touches(a, b)
	for _, c in corners(a) do
		if inside(b, c, 0.05) then
			return true
		end
	end
	for _, c in corners(b) do
		if inside(a, c, 0.05) then
			return true
		end
	end
	return false
end

-- the two ends of a curb cylinder (it lies along its X axis)
local function ends(c)
	local half = c.CFrame.RightVector * c.Size.X / 2
	return c.Position - half, c.Position + half
end

local lines = {}
local totals = { steps = 0, exposed = 0, curbGap = 0, wedges = 0 }

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

local function scan(name, container)
	local ways, kerbs = slabs(container), curbs(container)
	local steps, exposed, gaps, wedges = 0, 0, 0, 0
	for i = 1, #ways do
		for j = i + 1, #ways do
			local a, b = ways[i], ways[j]
			if touches(a, b) and math.abs(top(a) - top(b)) > STEP then
				steps += 1
			end
		end
		-- the curb peaks beside this slab
		local w = ways[i]
		for _, c in kerbs do
			local p0, p1 = ends(c)
			local mid = (p0 + p1) / 2
			if inside(w, mid, 1) and math.abs(c.Position.Y + c.Size.Y / 2 - (top(w) - 0.02)) < 0.5 then
				if top(w) - (c.Position.Y + c.Size.Y / 2) > EXPOSED then
					exposed += 1
					break
				end
			end
		end
	end
	-- curb ends that should meet: the nearest end of another curb within 1 stud, but not on it
	for i, c in kerbs do
		for _, e in { ends(c) } do
			local best = math.huge
			for j, d in kerbs do
				if i ~= j then
					local d0, d1 = ends(d)
					best = math.min(best, (e - d0).Magnitude, (e - d1).Magnitude)
				end
			end
			if best > CURB_GAP and best < 1 then
				gaps += 1
			end
		end
	end
	-- just outside every curb: lawn expected
	local include = { map.Wyspa, map.Dekoracje.Hub, workspace.Terrain }
	params.FilterDescendantsInstances = include
	for _, c in kerbs do
		local p0, p1 = ends(c)
		local along = (p1 - p0)
		local length = along.Magnitude
		local dir = along.Unit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		for _, s in { -1, 1 } do
			local hits = {}
			for k = 0, math.floor(length / SAMPLE) do
				local point = p0 + dir * (k * SAMPLE) + side * s * (c.Size.Y / 2 + OUT)
				local hit = workspace:Raycast(point + Vector3.new(0, 3, 0), Vector3.new(0, -6, 0), params)
				local kind = "none"
				if hit then
					local n = hit.Instance.Name
					kind = if n == "Rasen" or hit.Instance:IsA("Terrain")
						then "lawn"
						elseif n == "Weg" or n == "Bordstein" then "way"
						else "ground"
				end
				hits[k + 1] = kind
			end
			-- a short run of bare ground with lawn on both sides
			local k = 1
			while k <= #hits do
				if hits[k] == "ground" then
					local start = k
					while k <= #hits and hits[k] == "ground" do
						k += 1
					end
					local before, after = hits[start - 1], hits[k]
					if before == "lawn" and after == "lawn" and (k - start) * SAMPLE <= 3 then
						wedges += 1
					end
				else
					k += 1
				end
			end
		end
	end
	totals.steps += steps
	totals.exposed += exposed
	totals.curbGap += gaps
	totals.wedges += wedges
	if steps + exposed + gaps + wedges > 0 then
		table.insert(
			lines,
			string.format(
				"%s: %d steps, %d exposed slabs, %d curb gaps, %d lawn gaps",
				name,
				steps,
				exposed,
				gaps,
				wedges
			)
		)
	end
end

for _, sector in hub:GetChildren() do
	if sector:IsA("Folder") or sector:IsA("Model") then
		scan(sector.Name, sector)
	end
end
table.sort(lines)
table.insert(
	lines,
	string.format(
		"total: %d steps, %d exposed slabs, %d curb gaps, %d lawn gaps",
		totals.steps,
		totals.exposed,
		totals.curbGap,
		totals.wedges
	)
)
local text = table.concat(lines, "\n")
print(text)
return text
