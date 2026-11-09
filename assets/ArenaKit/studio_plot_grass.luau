--!nocheck
-- Lays grass on the 12 plot islands in Studio (Edit mode, run through the Studio MCP or the command bar): soft
-- pastel cartoon grass like the reference "Eiscreme-Insel: Spielerplot-Layout" (ice cream style, not tropical), calm
-- so the plot's models, players and scoops read on it. Picture since 05.11.2026 the pastel one (the first, juicier
-- one was rbxassetid://111206069018985).
--
-- Only looks change: each island's walkable surface (Ice Cream Map.Plots.Plot_NN.Powierzchnia, 104 x 54) gets the
-- MaterialVariant WS_Grass (Plot_Grass, 16 studs per tile) and TINT as its colour (the part colour multiplies the
-- picture). Size, position, CanCollide and CanQuery stay as they are, so landing rules, walking and the zone markers
-- on top are untouched. Every surface is Locked against stray drags. The colours before are kept as the attribute
-- ColourBefore on each surface. The island bodies (Wyspa_*) ended at the surface's height (y 9.0) and flickered
-- through the grass (z-fighting): their tops go BODY_DROP lower, their bottoms stay; the rim round the surface is then
-- 0.1 below it. The zone markers (Strefy, placeholders until the plot models stand there) go to MARKER_TRANSPARENCY
-- so the grass shows through them. Run again after a change: it is safe to repeat.
-- Picture: assets/ArenaKit/make_floor_textures.py (GRASS).
-- Since 08.11.2026 the plots look like the hub meadow (studio_hub_decor.luau): the same MaterialVariant, the same tint
-- #82B84E (no colour edge at the bridge), and under the surface the same terrain grass whose blades
-- (Terrain.Decoration) grow through it. Blades only where a voxel column's middle and eight points TERRAIN.inset round
-- it all lie on the surface and none of the nine is under anything else (path stones, the plot walkways and the round
-- square, the three stations with their platforms, the plot sign, the fence, the spawn), and none within
-- TERRAIN.serveFree of the ServePoint (the serve radius is 8).

local GRASS = { name = "WS_Grass", picture = "rbxassetid://79201403556010", studs = 16 }
local TINT = Color3.fromHex("#82B84E") -- the hub lawn's colour (LAWN_COLOUR); until 08.11.2026 #FFFFFF
local TERRAIN = { occ = 0.72, inset = 3.5, serveFree = 12 } -- occ and inset as the hub (GRASS_TERRAIN)
local SURFACE_Y = 9.0 -- Config/Map.plot.surfaceY
local BODY_DROP = 0.1
-- 1 since 08.11.2026: the plot kit's models stand on the zones, and the tinted markers made patches in the grass
local MARKER_TRANSPARENCY = 1

-- lowers a body's top from SURFACE_Y by BODY_DROP, whichever local axis points up (the corners are cylinders)
local function lowerTop(body)
	local cf, size = body.CFrame, body.Size
	local best
	for _, axis in { { cf.RightVector, "X" }, { cf.UpVector, "Y" }, { cf.LookVector, "Z" } } do
		if not best or math.abs(axis[1].Y) > math.abs(best[1].Y) then
			best = axis
		end
	end
	if math.abs(body.Position.Y + size[best[2]] / 2 - SURFACE_Y) > 0.01 then
		return false -- already lowered, or not at the surface
	end
	local s = { X = size.X, Y = size.Y, Z = size.Z }
	s[best[2]] -= BODY_DROP
	body.Size = Vector3.new(s.X, s.Y, s.Z)
	body.CFrame = cf - Vector3.new(0, BODY_DROP / 2, 0)
	return true
end

local MS = game:GetService("MaterialService")
local v = MS:FindFirstChild(GRASS.name) or Instance.new("MaterialVariant")
v.Name = GRASS.name
v.BaseMaterial = Enum.Material.SmoothPlastic
v.ColorMap = GRASS.picture
v.StudsPerTile = GRASS.studs
v.Parent = MS

-- the terrain grass under one plot's surface (TERRAIN): its old grass voxels go, then every voxel column (4 studs, the
-- lower layer y 4..8 filled occ, surface about y 8.9 just under the plot surface) that passes the test above gets grass
local function grassTerrain(plot, surface)
	local T = workspace.Terrain
	local onSurface = RaycastParams.new()
	onSurface.FilterType = Enum.RaycastFilterType.Include
	onSurface.FilterDescendantsInstances = { surface }
	-- everything standing on the island but the island itself and its flat zone markers
	local cf, size = plot:GetBoundingBox()
	local blockers = {}
	for _, part in workspace:GetPartBoundsInBox(cf, size + Vector3.new(4, 40, 4)) do
		local isIsland = part == surface or part.Name:sub(1, 6) == "Wyspa_" or part:IsDescendantOf(plot.Strefy)
		if not isIsland and part.Transparency < 1 or part:IsA("SpawnLocation") then
			table.insert(blockers, part)
		end
	end
	local onBlocker = RaycastParams.new()
	onBlocker.FilterType = Enum.RaycastFilterType.Include
	onBlocker.FilterDescendantsInstances = blockers
	local serve = workspace.Pier.Plots:FindFirstChild(plot.Name)
	serve = serve and serve:FindFirstChild("ServePoint")
	local function free(x, z)
		local top = SURFACE_Y + 0.5
		if not workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -1, 0), onSurface) then
			return false
		end
		return workspace:Raycast(Vector3.new(x, SURFACE_Y + 40, z), Vector3.new(0, -40.5, 0), onBlocker) == nil
	end
	-- the surface is turned along its lane: the voxel region is its world-axis box
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, sx in { -0.5, 0.5 } do
		for _, sz in { -0.5, 0.5 } do
			local p = surface.CFrame * Vector3.new(sx * surface.Size.X, 0, sz * surface.Size.Z)
			minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
			minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
		end
	end
	local region = Region3.new(Vector3.new(minX - 4, 4, minZ - 4), Vector3.new(maxX + 4, 8, maxZ + 4)):ExpandToGrid(4)
	local mats, occs = T:ReadVoxels(region, 4)
	local lo = region.CFrame.Position - region.Size / 2
	local columns = 0
	for ix = 1, mats.Size.X do
		for iz = 1, mats.Size.Z do
			local x, z = lo.X + (ix - 0.5) * 4, lo.Z + (iz - 0.5) * 4
			-- only this island's columns change (the region's corners reach the water and the neighbours' lanes)
			if workspace:Raycast(Vector3.new(x, SURFACE_Y + 0.5, z), Vector3.new(0, -1, 0), onSurface) then
				local grass = free(x, z)
				for i = 0, 7 do
					if not grass then
						break
					end
					local a = i * math.pi / 4
					grass = free(x + TERRAIN.inset * math.cos(a), z + TERRAIN.inset * math.sin(a))
				end
				if grass and serve then
					local d = Vector3.new(x - serve.Position.X, 0, z - serve.Position.Z).Magnitude
					grass = d > TERRAIN.serveFree
				end
				for iy = 1, mats.Size.Y do
					mats[ix][iy][iz] = grass and Enum.Material.Grass or Enum.Material.Air
					occs[ix][iy][iz] = grass and TERRAIN.occ or 0
				end
				if grass then
					columns += 1
				end
			end
		end
	end
	T:WriteVoxels(region, 4, mats, occs)
	return columns
end

local done, lowered, columns = 0, 0, 0
for _, plot in workspace["Ice Cream Map"].Plots:GetChildren() do
	for _, body in plot:GetChildren() do
		if body:IsA("BasePart") and body.Name:sub(1, 6) == "Wyspa_" and lowerTop(body) then
			lowered += 1
		end
	end
	local markers = plot:FindFirstChild("Strefy")
	if markers then
		for _, marker in markers:GetChildren() do
			if marker:IsA("BasePart") then
				marker.Transparency = MARKER_TRANSPARENCY
			end
		end
	end
	local surface = plot:FindFirstChild("Powierzchnia")
	if surface and surface:IsA("BasePart") then
		if surface:GetAttribute("ColourBefore") == nil then
			surface:SetAttribute("ColourBefore", surface.Color:ToHex())
		end
		surface.Material = Enum.Material.SmoothPlastic
		surface.MaterialVariant = GRASS.name
		surface.Color = TINT
		surface.Locked = true
		done += 1
		columns += grassTerrain(plot, surface)
		task.wait()
	end
end
workspace.Terrain.Decoration = true
workspace.Terrain:SetMaterialColor(Enum.Material.Grass, TINT)
return `{done} plot surfaces are grass ({GRASS.name}, {GRASS.studs} studs per tile, {TINT:ToHex()}), {lowered} island`
	.. ` bodies lowered, {columns} terrain grass columns`
