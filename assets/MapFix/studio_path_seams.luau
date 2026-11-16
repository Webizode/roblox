-- Studio (Edit, run through the MCP or the command bar), kill test 13.11.2026: clean seams on the hub walkways.
--
-- The walkways (assets/HubKit/studio_hub_decor.luau) are straight slabs: the ring at r 192 in 48 chords that overlap
-- 0.8 studs at every bend, the ways from the ramps to the bridges and the spurs crossing them. Overlapping slabs with
-- the same top flickered, and studio_zfighting.luau lifted every second one by 0.04 to 0.18 studs: that made steps at
-- the bends and slabs standing above their curbs (find_path_seams.luau: 120 steps, 48 exposed slabs). The straight
-- curb cylinders of two chords also part at the outside of every bend (72 curb gaps).
--
-- This script:
--   1. keeps a copy of every Wege folder in ServerStorage (BACKUP), once
--   2. puts every lifted walkway slab (Weg) back to its height (attribute ZFightOffset) and makes all slabs invisible:
--      they stay the walkways' collision, exactly as before
--   3. draws one visible surface instead: the union of all slabs (WegeOptik.Wege, no collision, no queries), so
--      nothing overlaps any more (no flicker, no seams) and the paving runs on across the bends
--   4. closes every curb gap at a bend with a ball the curb's size and colour (WegeOptik.Bordsteinkugeln)
-- RESTORE = true undoes it from the copy. Run it again after studio_hub_decor.luau rebuilt the walkways.
-- The plot walkways under the path stones (PlotWege) are left alone: they are hidden under the stones.

local RESTORE = false
local BACKUP = "MapBackup_2026-11-13_HubWege"
local CURB_GAP = { 0.05, 1 } -- studs between two curb ends that should meet

local ServerStorage = game:GetService("ServerStorage")
local hub = workspace["Ice Cream Map"].Dekoracje.Hub

local function wegeFolders()
	local out = {}
	for _, d in hub:GetDescendants() do
		if d:IsA("Folder") and d.Name == "Wege" then
			table.insert(out, d)
		end
	end
	return out
end

if RESTORE then
	local backup = ServerStorage:FindFirstChild(BACKUP)
	assert(backup, "no backup " .. BACKUP)
	for _, copy in backup:GetChildren() do
		local parentPath = copy:GetAttribute("From")
		local parent = hub
		for name in string.gmatch(parentPath, "[^/]+") do
			parent = parent:FindFirstChild(name)
		end
		local current = parent:FindFirstChild("Wege")
		if current then
			current:Destroy()
		end
		local restored = copy:Clone()
		restored:SetAttribute("From", nil)
		restored.Parent = parent
	end
	local optik = hub:FindFirstChild("WegeOptik")
	if optik then
		optik:Destroy()
	end
	print("[PathSeams] restored the walkways from " .. BACKUP)
	return "restored"
end

-- 1. the copy, once
if not ServerStorage:FindFirstChild(BACKUP) then
	local backup = Instance.new("Folder")
	backup.Name = BACKUP
	for _, f in wegeFolders() do
		local copy = f:Clone()
		local path = {}
		local p = f.Parent
		while p and p ~= hub do
			table.insert(path, 1, p.Name)
			p = p.Parent
		end
		copy.Name = "Wege_" .. table.concat(path, "_")
		copy:SetAttribute("From", table.concat(path, "/"))
		copy.Parent = backup
	end
	backup.Parent = ServerStorage
end

-- 2. heights back, slabs invisible
local slabs = {}
local lowered = 0
for _, f in wegeFolders() do
	for _, p in f:GetChildren() do
		if p:IsA("BasePart") and p.Name == "Weg" then
			local offset = p:GetAttribute("ZFightOffset")
			if type(offset) == "number" then
				p.Position -= Vector3.new(0, offset, 0)
				p:SetAttribute("ZFightOffset", nil)
				lowered += 1
			end
			p.Transparency = 1
			p.CastShadow = false
			p:SetAttribute("SeamFix", true)
			table.insert(slabs, p)
		end
	end
end

-- 3. one visible surface
local old = hub:FindFirstChild("WegeOptik")
if old then
	old:Destroy()
end
local optik = Instance.new("Folder")
optik.Name = "WegeOptik"
optik.Parent = hub
local copies = {}
for _, p in slabs do
	local c = p:Clone()
	c.Transparency = 0
	c.CastShadow = true
	c.CanCollide = false
	c:SetAttribute("SeamFix", nil)
	c.Parent = optik
	table.insert(copies, c)
end
local first = table.remove(copies, 1)
local union = first:UnionAsync(copies)
union.Name = "Wege"
union.UsePartColor = true
union.Color = first.Color
union.Material = first.Material
union.MaterialVariant = first.MaterialVariant
union.Anchored = true
union.CanCollide = false
union.CanQuery = false
union.CanTouch = false
union.Locked = true
union.Parent = optik
first:Destroy()
for _, c in copies do
	c:Destroy()
end

-- 4. balls on the curb gaps
local curbs = {}
for _, f in wegeFolders() do
	for _, p in f:GetChildren() do
		if p:IsA("Part") and p.Name == "Bordstein" and p.Shape == Enum.PartType.Cylinder then
			table.insert(curbs, p)
		end
	end
end
local balls = Instance.new("Folder")
balls.Name = "Bordsteinkugeln"
balls.Parent = optik
local done = {}
local count = 0
for i, c in curbs do
	local half = c.CFrame.RightVector * c.Size.X / 2
	for _, e in { c.Position - half, c.Position + half } do
		local best, bestEnd, bestJ = math.huge, nil, nil
		for j, d in curbs do
			if j ~= i then
				local dh = d.CFrame.RightVector * d.Size.X / 2
				for _, de in { d.Position - dh, d.Position + dh } do
					local gap = (e - de).Magnitude
					if gap < best then
						best, bestEnd, bestJ = gap, de, j
					end
				end
			end
		end
		local key = if bestJ then math.min(i, bestJ) .. ":" .. math.max(i, bestJ) else nil
		if bestEnd and best > CURB_GAP[1] and best < CURB_GAP[2] and not done[key] then
			done[key] = true
			local ball = Instance.new("Part")
			ball.Name = "Bordsteinkugel"
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.new(c.Size.Y, c.Size.Y, c.Size.Y)
			ball.Position = (e + bestEnd) / 2
			ball.Color = c.Color
			ball.Material = c.Material
			ball.MaterialVariant = c.MaterialVariant
			ball.Anchored = true
			ball.CanCollide = false
			ball.CanQuery = false
			ball.CanTouch = false
			ball.TopSurface = Enum.SurfaceType.Smooth
			ball.BottomSurface = Enum.SurfaceType.Smooth
			ball.Locked = true
			ball.Parent = balls
			count += 1
		end
	end
end

local text = string.format(
	"[PathSeams] %d slabs (%d put back to their height) drawn as one surface, %d curb gaps closed",
	#slabs,
	lowered,
	count
)
print(text)
return text
