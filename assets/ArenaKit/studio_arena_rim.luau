--!nocheck
-- Places the arena rim, the entrance arches and the barrier in Studio (Edit mode, run through the Studio MCP or the
-- command bar), from the templates in ServerStorage.ArenaKit (studio_arenakit_templates.luau). Rebuilds what it
-- made before; nothing else in the map is touched.
--
--   Dekoracje.ArenaRand  per gap between two ramps (ramp lines at 15 + k * 30 degrees): a rim pillar PILLAR_OFF
--                        studs along the arc from each ramp line and two wall pieces meeting in the middle of the
--                        gap, all at r RIM_R on the strip (top y 9), their front (-Z) towards the arena centre
--   Dekoracje.Wejscia    an entrance arch over every ramp's top edge (r 159)
--   Sperre               invisible walls that only stop players (Config/Map.playersOnlyFolders): over every wall
--                        piece and rim pillar up to TOP, a cylinder on every seam between two wall pieces, and along
--                        both edges of every ramp from the arena edge to its top edge. A jump (about 4 studs at
--                        jump power 40) or a dash (up to 25 studs, the power dash) never takes anyone over the rim or
--                        off a ramp's side: in and out only over the 12 ramp tops. Roblox ignores CanQuery = false on
--                        parts that collide, so throws, aim, the cameras and the ground and landing rays look through
--                        this folder by rule (MapRules.playersOnly), not by CanQuery.
-- Tested 05.11.2026 in a playtest: walking, jumping, dash, quick and power dash against the rim from the strip and from
-- the arena, at a wall's middle, a seam and a pillar, and off and onto a ramp's side; all stopped. Out and back in
-- over ramp 01 walks through freely, and the landing spots stay 13,347.

local STRIP_Y = 9
local RIM_R, RIM_SPAN, PILLAR_OFF = 137.5, 11.19, 8.7 -- PILLAR_OFF: at 8.0 a pillar's foot hung over the ramp
local ENTRANCE_R = 159
local TOP = 40
local RAMP_HALF, RAMP_R0, RAMP_R1, EDGE = 6.0, 133.5, 159.0, 0.5

local map = workspace["Ice Cream Map"]
local kit = game:GetService("ServerStorage").ArenaKit
local deco = map:FindFirstChild("Dekoracje") or Instance.new("Folder")
deco.Name = "Dekoracje"
deco.Parent = map
for _, old in { deco:FindFirstChild("ArenaRand"), deco:FindFirstChild("Wejscia"), map:FindFirstChild("Sperre") } do
	old:Destroy()
end
local rim = Instance.new("Folder")
rim.Name = "ArenaRand"
local gates = Instance.new("Folder")
gates.Name = "Wejscia"
local barrier = Instance.new("Folder")
barrier.Name = "Sperre"

local function at(r, deg)
	local a = math.rad(deg)
	local p = Vector3.new(r * math.sin(a), STRIP_Y, r * math.cos(a))
	return CFrame.lookAt(p, Vector3.new(0, STRIP_Y, 0))
end
local function put(name, cframe, parent, label)
	local m = kit[name]:Clone()
	m.Name = label
	m:PivotTo(cframe)
	m.Parent = parent
	return m
end
local UP = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis (X) pointing up
local function wall(name, cframe, size, round)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = round and Enum.PartType.Cylinder or Enum.PartType.Block
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.CastShadow = false
	p.Locked = true
	p.Parent = barrier
end

for k = 0, 11 do
	local ramp = 15 + 30 * k
	local i = string.format("%02d", k + 1)
	put("ArenaEntrance", at(ENTRANCE_R, ramp), gates, "Wejscie_" .. i)
	local dp = math.deg(PILLAR_OFF / RIM_R)
	local mid = ramp + 15
	local pieces = {
		put("ArenaRimPillar", at(RIM_R, ramp + dp), rim, "RandSaeule_" .. i .. "a"),
		put("ArenaRimPillar", at(RIM_R, ramp + 30 - dp), rim, "RandSaeule_" .. i .. "b"),
		put("ArenaRim", at(RIM_R, mid - RIM_SPAN / 2), rim, "RandWand_" .. i .. "a"),
		put("ArenaRim", at(RIM_R, mid + RIM_SPAN / 2), rim, "RandWand_" .. i .. "b"),
	}
	for _, m in pieces do
		local c = m.Collision
		if m.Name:find("RandWand") then -- over the wall's box up to TOP
			local top = c.Position.Y + c.Size.Y / 2
			local h = TOP - top
			wall(
				"Sperre_" .. m.Name,
				c.CFrame * CFrame.new(0, c.Size.Y / 2 + h / 2, 0),
				Vector3.new(c.Size.X, h, c.Size.Z)
			)
		else -- a pillar: from the strip up to TOP, as wide as its collision
			local h = TOP - STRIP_Y
			wall(
				"Sperre_" .. m.Name,
				CFrame.new(c.Position.X, STRIP_Y + h / 2, c.Position.Z) * UP,
				Vector3.new(h, c.Size.Y, c.Size.Z),
				true
			)
		end
	end
	-- the seam where the gap's two wall pieces meet: their straight boxes leave a thin wedge there
	local a = math.rad(mid)
	wall(
		"Sperre_Naht_" .. i,
		CFrame.new(math.sin(a) * RIM_R, STRIP_Y + (TOP - STRIP_Y) / 2, math.cos(a) * RIM_R) * UP,
		Vector3.new(TOP - STRIP_Y, 4.2, 4.2),
		true
	)
	-- both edges of the ramp, from the arena floor up to TOP
	local r = math.rad(ramp)
	local dir = Vector3.new(math.sin(r), 0, math.cos(r))
	local side = Vector3.new(dir.Z, 0, -dir.X)
	for _, s in { -1, 1 } do
		local centre = dir * ((RAMP_R0 + RAMP_R1) / 2)
			+ side * s * (RAMP_HALF + EDGE / 2)
			+ Vector3.new(0, (1.2 + TOP) / 2, 0)
		wall(
			string.format("Sperre_Rampa_%s_%s", i, s < 0 and "L" or "R"),
			CFrame.lookAt(centre, centre + dir),
			Vector3.new(EDGE, TOP - 1.2, RAMP_R1 - RAMP_R0)
		)
	end
end
rim.Parent = deco
gates.Parent = deco
barrier.Parent = map
return `{#rim:GetChildren()} rim pieces, {#gates:GetChildren()} entrances, {#barrier:GetChildren()} barrier parts`
