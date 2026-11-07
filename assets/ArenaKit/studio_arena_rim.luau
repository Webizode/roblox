--!nocheck
-- Places the arena rim, the entrance arches and the barrier in Studio (Edit mode, run through the Studio MCP or the
-- command bar), from the templates in ServerStorage.ArenaKit (studio_arenakit_templates.luau). Rebuilds what it
-- made before; nothing else in the map is touched.
--
--   Dekoracje.ArenaRand  per gap between two ramps (ramp lines at 15 + k * 30 degrees): a rim pillar PILLAR_OFF
--                        studs along the arc from each ramp line and two wall pieces meeting in the middle of the
--                        gap, all at r RIM_R on the strip (top y 9), their front (-Z) towards the arena centre
--   Dekoracje.Wejscia    an entrance arch over every ramp's top edge (r 159)
--   Sperre               invisible walls that only stop players (Config/Map.playersOnlyFolders), only over the rim
--                        between the ramps: over every wall piece with exactly its outline, and over every rim pillar
--                        as wide as its collision, up to TOP. A jump (about 4 studs at jump power 40) or a dash (up to
--                        25 studs, the power dash) never takes anyone over the rim. The ramps stay open at their
--                        sides: a ramp belongs to the arena, the safe zone starts at its top edge. Roblox ignores
--                        CanQuery = false on parts that collide, so throws, aim, the cameras and the ground and
--                        landing rays look through this folder by rule (MapRules.playersOnly), not by CanQuery.
-- Nothing sticks out of the visible wall, inside or out: one can walk right along it and along the pillars.

local STRIP_Y = 9
local RIM_R, RIM_SPAN, PILLAR_OFF = 137.5, 11.19, 8.7 -- PILLAR_OFF: at 8.0 a pillar's foot hung over the ramp
local ENTRANCE_R = 159
local TOP = 40
-- the wall's own collision and the barrier over it: as thick as the glazed top of the wall (arena_pack ArenaRim:
-- glaze RIM_R +- 1.42, top 3.4 above the strip), in WALL_SEGMENTS pieces along its arc (each 4.5 studs, off the arc
-- by 0.02 at most)
local WALL_HALF, WALL_TOP, WALL_SEGMENTS = 1.42, 9 + 3.4, 6

local map = workspace["Ice Cream Map"]
local kit = game:GetService("ServerStorage").ArenaKit
local deco = map:FindFirstChild("Dekoracje") or Instance.new("Folder")
deco.Name = "Dekoracje"
deco.Parent = map
-- the hub fence walls (assets/HubKit/studio_hub_decor.luau) and the bridge walls (assets/HubKit/studio_bridges.luau)
-- live in Sperre.Hubzaun and Sperre.Bruecken: they stay
local kept = {}
for _, name in { "Hubzaun", "Bruecken" } do
	local f = map:FindFirstChild("Sperre") and map.Sperre:FindFirstChild(name)
	if f then
		f.Parent = nil
		table.insert(kept, f)
	end
end
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
	for p, m in pieces do
		local c = m.Collision
		if m.Name:find("RandWand") then
			-- the template's straight box stuck out of the bent wall by up to 0.66 studs (inwards in the middle,
			-- outwards at the ends) and caught players walking along it: the wall collides through WALL_SEGMENTS
			-- short boxes along its arc instead, exactly as thick as its glazed top (RIM_R +- WALL_HALF), and the
			-- barrier stands on them with the same outline, from the wall's top up to TOP
			local phi0 = math.rad(p == 3 and mid - RIM_SPAN / 2 or mid + RIM_SPAN / 2)
			m.WorldPivot = m:GetPivot()
			m.PrimaryPart = nil
			c:Destroy()
			local step = math.rad(RIM_SPAN) / WALL_SEGMENTS
			local chord = 2 * RIM_R * math.sin(step / 2) + 0.02 -- a hair longer, so the pieces close up
			for s = 1, WALL_SEGMENTS do
				local phi = phi0 - math.rad(RIM_SPAN) / 2 + step * (s - 0.5)
				local base =
					CFrame.lookAt(Vector3.new(RIM_R * math.sin(phi), 0, RIM_R * math.cos(phi)), Vector3.new(0, 0, 0))
				local box = Instance.new("Part")
				box.Name = "Collision_" .. s
				box.Size = Vector3.new(chord, WALL_TOP - STRIP_Y, 2 * WALL_HALF)
				box.CFrame = base + Vector3.new(0, (STRIP_Y + WALL_TOP) / 2, 0)
				box.Anchored = true
				box.CanCollide = true
				box.CanQuery = true
				box.CanTouch = false
				box.Transparency = 1
				box.CastShadow = false
				box.Parent = m
				wall(
					string.format("Sperre_%s_%d", m.Name, s),
					base + Vector3.new(0, (WALL_TOP + TOP) / 2, 0),
					Vector3.new(chord, TOP - WALL_TOP, 2 * WALL_HALF)
				)
			end
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
end
rim.Parent = deco
gates.Parent = deco
for _, f in kept do
	f.Parent = barrier
end
barrier.Parent = map
return `{#rim:GetChildren()} rim pieces, {#gates:GetChildren()} entrances, {#barrier:GetChildren()} barrier parts`
