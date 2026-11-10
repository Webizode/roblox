--!nocheck
-- Studio command bar / MCP: Deko Runde 2, places the deco kit (ServerStorage.DecoKit, studio_decokit_templates.luau)
-- on the hub ring and the plot islands. Safe to run again: it rebuilds only its own folders.
--
-- Hub: Dekoracje.Hub.Sektor_k.Deko2. Small groups of bushes and rocks at the fence and in corners, one or two green
-- trees per sector next to the ice trees (at most 4 trees per sector in all), free lawn left open on purpose.
-- Plot: Plots.Plot_k.Deko2. Two or three palms at the island edges, a few bushes and rocks along the fence; nothing on
-- paths, in front of the stations, the sign, the spawn or the ServePoint, nothing on the round plaza where players
-- serve.
--
-- Every model is placed by its group's spot and then checked: under its whole footprint lies lawn (hub Rasen, plot
-- Powierzchnia), and no visible or colliding part stands in it (paths, curbs, benches, lanterns, stations, fence,
-- other deco, trunks). If the spot is taken, it searches outwards in a spiral (up to SEARCH studs) and skips the model
-- when nothing fits. Under every placed model the terrain grass goes (its blades would grow through the leaves).
-- Each sector and plot gets its own seed: same groups, a little turned, shifted and swapped, so no two look alike.
--
-- SECTORS / PLOTS: "all" or a list of numbers. RESTORE = true removes the deco again (the grass under it comes back
-- when studio_hub_decor.luau / studio_plot_grass.luau run again; run this script after them).

local SECTORS = { 1 }
local PLOTS = { 1 }
local RESTORE = false

local SEARCH = 10 -- studs the spiral looks round a taken spot
local SERVE_FREE = 14 -- studs kept free round the ServePoint and the Spawn
local STATION_MARGIN = 4 -- studs kept free in front of and round the stations and the sign

local KIT = game:GetService("ServerStorage"):WaitForChild("DecoKit")
local map = workspace["Ice Cream Map"]
local hub = map.Dekoracje.Hub
local T = workspace.Terrain

-- hub groups, per sector: a (degrees into the sector, which starts at (k-1)*30), r (studs from the middle); items
-- with dt (studs along the ring) and dr (studs outwards) from the group's spot; turn "ring" lays it along the ring
local HUB_GROUPS = {
	{ a = 4, r = 226, items = { { "Hedge", 0, 0, "ring" }, { "BushSmall", 6.5, -2.5 }, { "RockGroup", -6, -2.5 } } },
	{ a = 28, r = 218, items = { { "BushRound", 0, 0 }, { "RockRound", -5, 1.5 }, { "BushSmall", 3, -4 } } },
	{ a = 8, r = 197, items = { { "Tree", 0, 0 }, { "BushFlower", 6, 1.5 }, { "RockFlat", -5.5, 2.5 } } },
	{ a = 21, r = 193, items = { { "BushRound", 0, 0 }, { "BushSmall", 4, 3 } } },
	{ a = 12, r = 212, items = { { "RockRound", 0, 0 }, { "BushSmall", 3.5, 1.5 } } },
}
-- where a missing green tree may go instead (a, r), tried in this order
local TREE_SPOTS = { { 17, 205 }, { 24, 200 }, { 6, 210 }, { 15, 186 }, { 26, 214 }, { 3, 192 } }
-- plot groups, in the island's frame: x across (the Working Station at -x), z out of the island (+z is the bridge)
local PLOT_GROUPS = {
	{ x = -44, z = -19, items = { { "Palm", 0, 0 }, { "RockRound", 5, 2 }, { "BushSmall", -1, 5 } } },
	{ x = 44, z = -19, items = { { "Palm", 0, 0 }, { "BushRound", -6, 1 } } },
	{ x = -22, z = 19, items = { { "Palm", 0, 0 }, { "RockGroup", -5, 1 }, { "BushSmall", -2, -4 } } },
	{ x = -20, z = -21, items = { { "BushFlower", 0, 0 }, { "RockFlat", 6, 0.5 } } },
	{ x = 20, z = -21, items = { { "BushRound", 0, 0 }, { "BushSmall", -5, 1 } } },
	{ x = 44, z = 14, items = { { "RockRound", 0, 0 }, { "BushSmall", -4, 2 } } },
}

local function listOf(spec, n)
	if spec == "all" then
		local t = {}
		for i = 1, n do
			t[i] = i
		end
		return t
	end
	return spec
end

local function pad(k)
	return string.format("%02d", k)
end

-- what may stand under and in a footprint: lawn and terrain are the ground, the rest is in the way when it shows or
-- collides (the Pier helpers are invisible and handled by distance)
local lawns = {}
local function isGround(part)
	return lawns[part] ~= nil or part:IsA("Terrain")
end

local function footprint(model)
	local cf, size = model:GetBoundingBox()
	if size.Y > 8 then
		-- trees and palms stand on their foot; the crown high above may reach over a fence or a path
		return CFrame.new(model:GetPivot().Position), Vector3.new(4, size.Y, 4)
	end
	-- leaves hang out over the edge: the solid foot is about three quarters of the box
	return cf, Vector3.new(size.X * 0.75, size.Y, size.Z * 0.75)
end

local onLawn = RaycastParams.new()
onLawn.FilterType = Enum.RaycastFilterType.Include

local function fits(model, groundY, keepAway)
	local cf, size = footprint(model)
	local flat = CFrame.new(cf.Position.X, groundY, cf.Position.Z) * (cf - cf.Position)
	-- lawn under the middle, the corners and the edge middles
	for _, u in { -0.5, 0, 0.5 } do
		for _, v in { -0.5, 0, 0.5 } do
			local p = flat * Vector3.new(u * size.X, 0, v * size.Z)
			local hit = workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -4, 0), onLawn)
			if not hit then
				return false
			end
		end
	end
	-- nothing in the way from just above the ground up to 8 studs
	local box = CFrame.new(flat.Position + Vector3.new(0, 4.4, 0)) * (cf - cf.Position)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	for _, part in workspace:GetPartBoundsInBox(box, Vector3.new(size.X, 8, size.Z), params) do
		if not isGround(part) and (part.Transparency < 1 or part.CanCollide) then
			return false
		end
	end
	local half = math.max(size.X, size.Z) / 2
	for _, spot in keepAway do
		if spot.box then
			-- a station or the sign: its own turned box, grown by the margin and the model's half size
			local l = spot.box:PointToObjectSpace(cf.Position)
			if math.abs(l.X) < spot.size.X / 2 + half and math.abs(l.Z) < spot.size.Z / 2 + half then
				return false
			end
		elseif Vector3.new(cf.Position.X - spot.at.X, 0, cf.Position.Z - spot.at.Z).Magnitude < spot.radius + half then
			return false
		end
	end
	return true
end

-- the terrain grass under a placed model goes (voxels of 4 studs, the layer just under the lawn)
local function clearGrass(model, groundY)
	-- the whole box, leaves included: blades under a hanging leaf would poke through it
	local cf, size = model:GetBoundingBox()
	-- trees and palms: only round the foot, their crowns are high above the blades
	local half = if size.Y > 8 then 3 else math.max(size.X, size.Z) / 2
	local c = if size.Y > 8 then model:GetPivot().Position else cf.Position
	local region =
		Region3.new(Vector3.new(c.X - half, groundY - 6, c.Z - half), Vector3.new(c.X + half, groundY, c.Z + half))
			:ExpandToGrid(4)
	local mats, occs = T:ReadVoxels(region, 4)
	local cleared = 0
	for x = 1, mats.Size.X do
		for y = 1, mats.Size.Y do
			for z = 1, mats.Size.Z do
				if mats[x][y][z] == Enum.Material.Grass then
					mats[x][y][z] = Enum.Material.Air
					occs[x][y][z] = 0
					cleared += 1
				end
			end
		end
	end
	if cleared > 0 then
		T:WriteVoxels(region, 4, mats, occs)
	end
	return cleared
end

-- puts one model near `at` (ground height groundY), turned `yaw`; nil when nothing fits
local function place(name, at, groundY, yaw, parent, keepAway)
	local template = KIT:FindFirstChild(name)
	if not template then
		return nil, "no template " .. name
	end
	local model = template:Clone()
	model.Parent = parent
	local step, turns = 1.5, 0
	local offsets = { Vector3.zero }
	for ring = 1, math.floor(SEARCH / step) do
		local n = 6 * ring
		for i = 0, n - 1 do
			local a = 2 * math.pi * i / n + ring
			table.insert(offsets, Vector3.new(math.cos(a), 0, math.sin(a)) * ring * step)
		end
	end
	for _, o in offsets do
		turns += 1
		model:PivotTo(CFrame.new(at + o + Vector3.new(0, groundY - at.Y, 0)) * CFrame.Angles(0, yaw, 0))
		if fits(model, groundY, keepAway) then
			return model
		end
	end
	model:Destroy()
	return nil, name .. " found no free spot near " .. string.format("(%.0f, %.0f)", at.X, at.Z)
end

local report, skipped, grass = {}, {}, 0
local function countParts(inst)
	local n = 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end
local before = countParts(map)

-- the lawn takes no queries in the game; for the checks here it does, and is set back afterwards
local lawnList = {}
for _, sector in hub:GetChildren() do
	local r = sector:FindFirstChild("Rasen")
	for _, p in r and r:GetChildren() or {} do
		lawns[p] = p.CanQuery
		table.insert(lawnList, p)
	end
end
for _, plot in map.Plots:GetChildren() do
	local s = plot:FindFirstChild("Powierzchnia")
	if s then
		lawns[s] = s.CanQuery
		table.insert(lawnList, s)
	end
end
for p in lawns do
	p.CanQuery = true
end
onLawn.FilterDescendantsInstances = lawnList

local ok, err = pcall(function()
	-- hub
	for _, k in listOf(SECTORS, 12) do
		local sector = hub:FindFirstChild("Sektor_" .. pad(k))
		if not sector then
			continue
		end
		if sector:FindFirstChild("Deko2") then
			sector.Deko2:Destroy()
		end
		if RESTORE then
			continue
		end
		local folder = Instance.new("Folder")
		folder.Name = "Deko2"
		folder.Parent = sector
		local rng = Random.new(1000 + k)
		-- trees: the sector's ice trees count; one green tree, a second in every third sector
		local ice = 0
		for _, m in sector:GetChildren() do
			if m:IsA("Model") and m.Name:find("Tree") then
				ice += 1
			end
		end
		local greenTrees = math.max(0, math.min(if k % 3 == 0 then 2 else 1, 4 - ice))
		for g, group in HUB_GROUPS do
			-- every sector leaves one of the small groups out (a different one), so the lawn stays open
			if g >= 4 and (k + g) % 3 == 0 then
				continue
			end
			local a = math.rad((k - 1) * 30 + group.a + rng:NextNumber(-1.5, 1.5))
			local r = group.r + rng:NextNumber(-2, 2)
			local out = Vector3.new(math.sin(a), 0, math.cos(a))
			local along = Vector3.new(math.cos(a), 0, -math.sin(a))
			for _, item in group.items do
				local name = item[1]
				if name == "Tree" then
					if greenTrees <= 0 then
						continue
					end
					greenTrees -= 1
					name = if rng:NextNumber() < 0.5 then "TreeRound" else "TreeTall"
				elseif name == "BushRound" and rng:NextNumber() < 0.3 then
					name = "BushFlower"
				end
				local at = out * (r + item[3]) + along * item[2]
				local yaw = if item[4] == "ring" then a + math.pi / 2 else rng:NextNumber(0, 2 * math.pi)
				local model, why = place(name, at, 9.08, yaw, folder, {})
				if model then
					grass += clearGrass(model, 9.08)
				else
					table.insert(skipped, `Sektor_{pad(k)}: {why}`)
				end
			end
		end
		-- green trees still missing (one per sector, two in every third; the tree group's spot may be paved, as at
		-- the shops, the fountain or the harbour gate): try the open lawn elsewhere in the sector
		local placed = 0
		for _, m in folder:GetChildren() do
			if m.Name == "TreeRound" or m.Name == "TreeTall" then
				placed += 1
			end
		end
		local wanted = math.max(0, math.min(if k % 3 == 0 then 2 else 1, 4 - ice))
		for _, spot in TREE_SPOTS do
			if placed >= wanted then
				break
			end
			local a = math.rad((k - 1) * 30 + spot[1])
			local at = Vector3.new(math.sin(a), 0, math.cos(a)) * spot[2]
			local model = place(
				if (k + placed) % 2 == 0 then "TreeTall" else "TreeRound",
				at,
				9.08,
				rng:NextNumber(0, 6.28),
				folder,
				{}
			)
			if model then
				grass += clearGrass(model, 9.08)
				placed += 1
			end
		end
		table.insert(report, `Sektor_{pad(k)}: {#folder:GetChildren()} models`)
	end
	-- plots
	for _, k in listOf(PLOTS, 12) do
		local plot = map.Plots:FindFirstChild("Plot_" .. pad(k))
		if not plot then
			continue
		end
		if plot:FindFirstChild("Deko2") then
			plot.Deko2:Destroy()
		end
		if RESTORE then
			continue
		end
		local folder = Instance.new("Folder")
		folder.Name = "Deko2"
		folder.Parent = plot
		local rng = Random.new(2000 + k)
		local surface = plot.Powierzchnia
		local frame = surface.CFrame
		local groundY = surface.Position.Y + surface.Size.Y / 2
		local pier = workspace.Pier.Plots:FindFirstChild(plot.Name)
		local keepAway = {}
		for _, n in { "ServePoint", "Spawn" } do
			local p = pier and pier:FindFirstChild(n)
			if p then
				table.insert(keepAway, { at = p.Position, radius = SERVE_FREE })
			end
		end
		-- the round plaza in the middle, where players stand and serve
		table.insert(keepAway, { at = frame.Position, radius = 12 })
		for _, n in { "WorkingStation", "SellCart", "ScoopChest", "PlotSign" } do
			local m = plot.PlotKit:FindFirstChild(n)
			if m then
				local cf, size = m:GetBoundingBox()
				table.insert(keepAway, { box = cf, size = size + Vector3.new(2, 0, 2) * STATION_MARGIN })
			end
		end
		local palms = 0
		for g, group in PLOT_GROUPS do
			-- every plot leaves one of the bush groups out (a different one)
			if g >= 4 and (k + g) % 3 == 0 then
				continue
			end
			local base = Vector3.new(group.x + rng:NextNumber(-2, 2), 0, group.z + rng:NextNumber(-1, 1))
			for _, item in group.items do
				local name = item[1]
				local local3 = base + Vector3.new(item[2], 0, item[3])
				local at = frame:PointToWorldSpace(local3)
				local yaw = rng:NextNumber(0, 2 * math.pi)
				if name == "Palm" then
					palms += 1
					-- every plot one bent palm, the others straight; the bent one leans out over the edge (its lean is -X)
					name = if palms == 1 + (k % 3) then "PalmBent" else "PalmStraight"
					local outward = frame:VectorToWorldSpace(Vector3.new(group.x, 0, group.z).Unit)
					-- turned by yaw, the model's -X points to (-cos yaw, 0, sin yaw): make that the outward direction
					yaw = math.atan2(outward.Z, -outward.X)
				elseif name == "BushRound" and rng:NextNumber() < 0.3 then
					name = "BushFlower"
				end
				local model, why = place(name, at, groundY, yaw, folder, keepAway)
				if model then
					grass += clearGrass(model, groundY)
				else
					table.insert(skipped, `{plot.Name}: {why}`)
				end
			end
		end
		table.insert(report, `{plot.Name}: {#folder:GetChildren()} models`)
	end
end)
for p, was in lawns do
	p.CanQuery = was
end
if not ok then
	error(err)
end
local after = countParts(map)
return `parts {before} -> {after} (+{after - before}), {grass} grass voxels cleared\n{table.concat(report, "\n")}`
	.. (#skipped > 0 and ("\nskipped:\n" .. table.concat(skipped, "\n")) or "")
