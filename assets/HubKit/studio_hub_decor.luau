--!nocheck
-- Decorates the hub ring (r 171-232, top y 9) and builds raised walkways (Studio command bar, Edit mode). Copies of
-- the hub kit templates in ServerStorage.HubKit and the walkway parts all go to
-- Workspace."Ice Cream Map".Dekoracje.Hub: Dekoracje is blocked for landing spots (Config/Map.landing.blockedFolders),
-- so one click on Hub hides or removes it all (RESTORE_PLOT_PATHS puts the plot path stones back down first).
--   * walkways: a slab WAY_HEIGHT above the ground with a rounded curb on both long sides, in Wege: from each ramp
--     top to its bridge (12 wide through the entrance arch, 18 wide on the forecourt), a ring round the hub (RING_R),
--     spurs to the fountain, the harbour gate and the three shop areas, and under the path stones on every plot
--     (the stones are lifted onto it). Where two walkways cross, each top hides the other's curb (the curb peaks just
--     under the top). Not in the arena and not on the ramps.
--   * per sector k (bridge Most_k at 75 - 30 (k - 1) degrees): the forecourt at the bridge head (two lanterns, bench,
--     waffle planter, trash bin), outside the ring walkway towards sector k + 1 a group of ice trees with bushes and
--     a rock, inside it on the other side a small group of crates and barrels. Nothing stands within PATH_HALF of
--     the line from the ramp to the bridge (crowns and umbrellas included); the script checks every piece.
--   * the gaps between two sectors in SPECIAL hold the one-off pieces and the shop areas; sectors leave their side
--     groups out there. UNIQUES: the fountain with benches and a picnic table, the harbour gate at the outer edge
--     with the signpost. PLACEHOLDERS: flat see-through plates for the shops (folder Platzhalter).
-- Running again rebuilds what it is told to build (old copies of those sectors and pieces are removed first).
-- Coordinates: u along the ring (positive towards larger angles), r out from the centre; u is the distance from the
-- line at the sector's (or gap's) angle.

local SECTORS = "all" -- { 1, 2 } or "all"
local UNIQUES = true
local PLACEHOLDERS = true
local RESTORE_PLOT_PATHS = false -- true: only lift the plot path stones back down and remove the plot walkways

local Y = 9 -- top of Wyspa.Ring, the strip and the plot surfaces
local PATH_HALF = 10 -- the free way from the ramp to the bridge is 20 wide
local WAY_HEIGHT = 0.5 -- walkway top over the ground (studs)
local CURB = 0.6 -- curb width; its round top peaks at WAY_HEIGHT, just under the walkway top
local RING_R, RING_W = 192, 8 -- ring walkway centre radius and width (curbs come on top of the width)
local RING_CHORDS = 48 -- straight pieces round the ring (7.5 degrees each)
local WAY_COLOUR = "#FFF4E4" -- walkway top, with the paver texture of the ring
local CURB_COLOUR = "#C98A4F" -- Karamell
local PLOT_LIFT = 0.42 -- plot path stones (0.32 high, sunk 0.2) lifted so their bed sits on the walkway top
local BED_TOP = 0.26 -- grass beds: top over the ground, half the walkway height
local BED_CORNER = 3 -- rounded corner radius of a bed
local FENCE_R = 231 -- the fence round the main island (the ring ends at r 232)
local FENCE_GAP = 11.2 -- half the opening at each bridge: the posts (1.1 half wide) stay out of the 20-wide way
local GATE_GAP = 14 -- half the opening at the harbour gate (26.7 wide)
local FENCE_WALL_TOP = 40 -- the invisible wall over the fence reaches this high, like the arena's Sperre
local FENCE_POST_COLOUR = "#6E4029" -- Schoko, as on the plots
local FENCE_CAP_COLOUR = "#C98A4F" -- Karamell: the fence is neutral, the flavours stay on the plots and ramps
-- the lanterns' PointLight (the template has it off): at brightness 2 and range 18 it washed the bridge heads out to
-- white in daylight; 1 and 14 keep a warm glow
local LANTERN_LIGHT = { enabled = true, brightness = 1, range = 14 }

-- the flavour of each plot (assets/MapColors/studio_map_flavors.luau): crowns and crate frames take these
local MAIN = {
	"#7FE0B8", -- 01 Mint
	"#FF6F12", -- 02 Mango
	"#6F7BEA", -- 03 Blaubeere
	"#FFE15A", -- 04 Zitrone
	"#BB9CF0", -- 05 Lavendel
	"#FF7480", -- 06 Erdbeere
	"#B4D46A", -- 07 Pistazie
	"#F06AAE", -- 08 Bubblegum
	"#E8B877", -- 09 Karamell
	"#75D6F2", -- 10 Himmelblau
	"#9A6244", -- 11 Schoko
	"#D7304E", -- 12 Kirsche
}

-- gaps by their angle (between two ramps): what stands there instead of the side groups
local SPECIAL = {
	[0] = "UpgradeShop",
	[120] = "CosmeticShop",
	[240] = "QuestHub",
	[180] = "Fountain",
	[300] = "HarborGate",
}

-- walkways of a sector: { u0, u1, r0, r1 } in the sector frame
local RADIAL = {
	{ -6, 6, 159, 211 }, -- 12 wide: the entrance arch leaves 12.9 between its feet
	{ -9, 9, 211, 229.5 }, -- the forecourt, as wide as the bridge; it ends on the bridge
}
-- walkways on a plot: { u0, u1, v0, v1 } from the plot centre (r 322), v outwards; and the round square
local PLOT_WAYS = {
	{ -9, 9, -27, -19 }, -- from the bridge
	{ -3, 3, -19, 7 }, -- to the cart
	{ -8, 8, 7, 11 }, -- in front of the cart
	{ -32, 28, -7, -1 }, -- across, to station and chest
}
local PLOT_SQUARE = { v = -4, d = 14 }
local PLOT_R = 322

-- face: "path" (front to u = 0), "out" (to the sea), "in" (to the arena), "along" (to +u: a lantern's arm then points
-- outwards, to the bridge)
local FORECOURT = {
	{ "Lantern", -12.5, 226, "along" },
	{ "Lantern", 12.5, 226, "along" },
	{ "ParkBench", 16, 218, "path" },
	{ "TrashBin", 16, 211, "path" },
	{ "WafflePlanter", -13.5, 218, "path" }, -- clear of the grass bed (u < -17.5)
}
-- grass beds, { u0, u1, r0, r1, side }: side L lies towards sector k + 1 (the gap at angle - 15), R the other way.
-- A bed next to a gap in SPECIAL is left out: there the square stays paved (fountain, gate, shops). The crates stand on
-- paving inside the ring walkway (u > 0), so that field stays paved everywhere.
local BEDS = {
	{ -51, -17.5, 199, 229, "L" }, -- outside the ring walkway: the tree group
	{ -42, -9, 172, 185.5, "L" }, -- inside it
	{ 20, 50, 199, 229, "R" }, -- outside, beyond the bench
}
-- in the outer L bed, towards sector k + 1; crowns: own flavour or the neighbour's; the sixth field marks the third
-- tree, only in every other sector. They stand on the bed (BED_TOP).
local TREES = {
	{ "IceTree", -28, 207, BED_TOP, "own" },
	{ "IceTree", -40, 216, BED_TOP, "next" },
	{ "IceTree", -30, 223, BED_TOP, "own", true },
	{ "FlowerBush", -36, 205, BED_TOP },
	{ "FlowerBush", -22, 224, BED_TOP }, -- clear of the fence wall (r 230)
	{ "Rock", -45, 210, BED_TOP },
}
-- one bush in each of the other two beds: { model, u, r, side }
local BED_PLANTS = {
	{ "FlowerBush", -26, 179, "L" },
	{ "FlowerBush", 33, 213, "R" },
}
-- inside the ring walkway on the other side (u > 0); y lifts a crate onto the one below
local CRATES = {
	{ "Crate", 28, 178, 0 },
	{ "Crate", 28, 178, 3 },
	{ "Crate", 32, 181.5, 0 },
	{ "Barrel", 32.5, 176, 0 },
	{ "Barrel", 25, 182.5, 0 },
}
-- one-off pieces, u from the middle of their gap; spur: the walkway from the ring walkway to the piece
local UNIQUE = {
	Fountain = {
		pieces = {
			{ "Fountain", 0, 214, "in" },
			{ "ParkBench", -13.5, 214, "path" },
			{ "ParkBench", 13.5, 214, "path" },
			{ "PicnicTable", 0, 178.5, "in" },
		},
		spur = { -4, 4, 196, 206 }, -- ends 0.4 before the basin (its collision starts at r 206.4)
	},
	HarborGate = {
		pieces = {
			{ "HarborGate", 0, 228.5, "in" },
			{ "Signpost", -9, 214, "in" },
		},
		spur = { -4, 4, 196, 227.3 },
	},
}
-- filler buildings (ServerStorage.HubKit, assets/HubKit/build_hub_pack.py): { model, gap angle or sector, u, r, face,
-- lift, accent sector }. Their MeshPart <Model>_Pink (awning, sign, cushions) takes that sector's flavour; walls and
-- roof stay muted (60/30/10). Only these three: the cafe by the fountain (its terrace towards it), the kiosk on the
-- empty inner field at the harbour gate (its window to the ring walkway), the pavilion in the outer R bed of sector 2
-- (it takes the place of that bed's bush). The cart garage is built but not placed (it made the ring too full).
local BUILDINGS = {
	{ "Cafe", gap = 180, u = -30, r = 216, face = "path", accent = 10 },
	{ "IceKiosk", gap = 300, u = 0, r = 179, face = "out", accent = 5 },
	{ "Pavilion", sector = 2, u = 35, r = 214, face = "in", lift = BED_TOP, accent = 2, bed = "R" },
}

local SHOP = { width = 44, r0 = 200, r1 = 230, colour = "#FFFFFF", transparency = 0.6, spur = { -4, 4, 196, 200.5 } }

local map = workspace["Ice Cream Map"]
local kit = game:GetService("ServerStorage"):FindFirstChild("HubKit")
assert(kit, "ServerStorage.HubKit is missing: import the hub kit and run assets/HubKit/studio_hubkit_templates.luau")
local deko = map.Dekoracje
local hub = deko:FindFirstChild("Hub") or Instance.new("Folder")
hub.Name = "Hub"
hub.Parent = deko

local function rampAngle(k)
	return 75 - 30 * (k - 1)
end
local function basis(angle)
	local a = math.rad(angle)
	return Vector3.new(math.cos(a), 0, math.sin(a)), Vector3.new(-math.sin(a), 0, math.cos(a))
end
-- the point u along the ring and r out from the centre, u measured from the line at `angle`
local function at(angle, u, r)
	local er, et = basis(angle)
	return er * r + et * u
end

local function folder(parent, name)
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end
local function child(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local models, parts = 0, 0

-- walkways ------------------------------------------------------------------------------------------------------

local function solid(parent, name, shape, size, cframe, colour, variant)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = Color3.fromHex(colour)
	p.Material = Enum.Material.SmoothPlastic
	if variant then
		p.MaterialVariant = variant
	end
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	parts += 1
	return p
end

-- one straight walkway: `frame` stands on the ground in its middle, its Z axis along the walkway; width without curbs
local function walkway(parent, frame, length, width, colour)
	local h = WAY_HEIGHT
	solid(
		parent,
		"Weg",
		Enum.PartType.Block,
		Vector3.new(width, h + 0.02, length),
		frame * CFrame.new(0, (h + 0.02) / 2, 0),
		colour or WAY_COLOUR,
		colour == nil and "WS_Pavers" or nil
	)
	for _, side in { -1, 1 } do
		local x = side * (width / 2 + CURB / 2)
		local low = h - CURB / 2
		solid(
			parent,
			"Bordstein",
			Enum.PartType.Block,
			Vector3.new(CURB, low, length),
			frame * CFrame.new(x, low / 2, 0),
			CURB_COLOUR
		)
		-- a cylinder lies along X: turn it to Z
		solid(
			parent,
			"Bordstein",
			Enum.PartType.Cylinder,
			Vector3.new(length, CURB, CURB),
			frame * CFrame.new(x, low, 0) * CFrame.Angles(0, math.rad(90), 0),
			CURB_COLOUR
		)
	end
end

-- a walkway given as { u0, u1, r0, r1 } in the frame of the line at `angle`, running outwards
local function radialWay(parent, angle, rect, ground)
	local u0, u1, r0, r1 = rect[1], rect[2], rect[3], rect[4]
	local mid = at(angle, (u0 + u1) / 2, (r0 + r1) / 2) + Vector3.new(0, ground or Y, 0)
	local er = basis(angle)
	walkway(parent, CFrame.lookAt(mid, mid + er), r1 - r0, u1 - u0)
end

-- the ring walkway pieces whose middle lies within `from`..`to` degrees
local function ringWays(parent, from, to)
	local step = 360 / RING_CHORDS
	local chord = 2 * RING_R * math.sin(math.rad(step / 2))
	for i = 0, RING_CHORDS - 1 do
		local a = (i + 0.5) * step
		local d = (a - from) % 360
		if d < (to - from) % 360 or to - from >= 360 then
			local er, et = basis(a)
			local mid = er * RING_R * math.cos(math.rad(step / 2)) + Vector3.new(0, Y, 0)
			-- 0.8 longer than the chord: closes the joints at the outer edge
			walkway(parent, CFrame.lookAt(mid, mid + et), chord + 0.8, RING_W)
		end
	end
end

-- the plot walkways under the path stones of Plot_k, and the stones lifted onto them
local function plotPaths(k, f)
	local plot = map.Plots[string.format("Plot_%02d", k)]
	local angle = rampAngle(k)
	local er = basis(angle)
	local centre = er * PLOT_R
	for _, rect in PLOT_WAYS do
		local u0, u1, v0, v1 = rect[1], rect[2], rect[3], rect[4]
		local mid = at(angle, (u0 + u1) / 2, PLOT_R + (v0 + v1) / 2) + Vector3.new(0, Y, 0)
		if v1 - v0 >= u1 - u0 then
			walkway(f, CFrame.lookAt(mid, mid + er), v1 - v0, u1 - u0, "#FFE9D0")
		else
			local _, et = basis(angle)
			walkway(f, CFrame.lookAt(mid, mid + et), u1 - u0, v1 - v0, "#FFE9D0")
		end
	end
	-- the round square: a cream disc on a slightly larger caramel disc (its rim is the curb)
	local sq = centre + er * PLOT_SQUARE.v + Vector3.new(0, Y, 0)
	local upright = CFrame.Angles(0, 0, math.rad(90))
	solid(
		f,
		"Bordstein",
		Enum.PartType.Cylinder,
		Vector3.new(WAY_HEIGHT, PLOT_SQUARE.d + 2 * CURB, PLOT_SQUARE.d + 2 * CURB),
		CFrame.new(sq + Vector3.new(0, WAY_HEIGHT / 2, 0)) * upright,
		CURB_COLOUR
	)
	solid(
		f,
		"Weg",
		Enum.PartType.Cylinder,
		Vector3.new(WAY_HEIGHT + 0.02, PLOT_SQUARE.d, PLOT_SQUARE.d),
		CFrame.new(sq + Vector3.new(0, (WAY_HEIGHT + 0.02) / 2, 0)) * upright,
		"#FFE9D0"
	)
	-- lift the stones once (the attribute keeps how far, so a second run does not lift them again)
	for _, m in plot.PlotKit:GetChildren() do
		if m:IsA("Model") and m.Name:match("^Path") and not m:GetAttribute("WalkwayLift") then
			m:PivotTo(m:GetPivot() + Vector3.new(0, PLOT_LIFT, 0))
			m:SetAttribute("WalkwayLift", PLOT_LIFT)
		end
	end
end

local function lowerPlotPaths(k)
	local plot = map.Plots[string.format("Plot_%02d", k)]
	for _, m in plot.PlotKit:GetChildren() do
		local lift = m:GetAttribute("WalkwayLift")
		if lift then
			m:PivotTo(m:GetPivot() - Vector3.new(0, lift, 0))
			m:SetAttribute("WalkwayLift", nil)
		end
	end
end

-- recolours the MeshParts <Model>_<part>_<Colour> (suffix: the MeshParts <Model>_<part>, a colour name)
local function recolour(model, part, hex, suffix)
	local key = "_" .. part .. (suffix and "" or "_")
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") then
			local hit = if suffix then d.Name:sub(-#key) == key else d.Name:find(key, 1, true) ~= nil
			if hit then
				d.Color = Color3.fromHex(hex)
			end
		end
	end
end

-- grass beds and the fence ---------------------------------------------------------------------------------------

-- a grass bed with rounded corners, { u0, u1, r0, r1 } in the frame of the line at `angle`: two crossed slabs and a
-- cylinder in each corner, the plots' pastel grass (WS_Grass on white)
local function bed(parent, angle, rect)
	local u0, u1, r0, r1 = rect[1], rect[2], rect[3], rect[4]
	local w, d, h, c = u1 - u0, r1 - r0, BED_TOP, BED_CORNER
	local mid = at(angle, (u0 + u1) / 2, (r0 + r1) / 2) + Vector3.new(0, Y, 0)
	local er = basis(angle)
	local frame = CFrame.lookAt(mid, mid + er) -- X along u, Z along r
	local function grass(shape, size, cframe)
		local p = solid(parent, "Beet", shape, size, cframe, "#FFFFFF", "WS_Grass")
		p.CastShadow = false
	end
	grass(Enum.PartType.Block, Vector3.new(w - 2 * c, h, d), frame * CFrame.new(0, h / 2, 0))
	grass(Enum.PartType.Block, Vector3.new(w, h, d - 2 * c), frame * CFrame.new(0, h / 2, 0))
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			grass(
				Enum.PartType.Cylinder,
				Vector3.new(h, 2 * c, 2 * c),
				frame * CFrame.new(sx * (w / 2 - c), h / 2, sz * (d / 2 - c)) * CFrame.Angles(0, 0, math.rad(90))
			)
		end
	end
end

local plotKit = game:GetService("ServerStorage"):FindFirstChild("PlotKit")
assert(plotKit, "ServerStorage.PlotKit is missing (FenceSection, FencePost)")

-- an invisible wall over the fence, in Sperre (Config/Map.playersOnlyFolders: it stops players only; throws, cameras
-- and ground rays look through it)
local function fenceWall(parent, cframe, length)
	local h = FENCE_WALL_TOP - Y
	local p = Instance.new("Part")
	p.Name = "Sperre_Zaun"
	p.Size = Vector3.new(length, h, 1.8)
	p.CFrame = cframe * CFrame.new(0, h / 2, 0)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	parts += 1
end

-- a plot kit fence piece in the sector's colour (cap in the flavour, post in Schoko), without its own collision: the
-- wall in Sperre does that
local function fencePiece(parent, name, cframe, k)
	local m = plotKit[name]:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Name:sub(1, 9) == "Collision" then
			d:Destroy()
		end
	end
	recolour(m, "Pink", FENCE_CAP_COLOUR, true)
	recolour(m, "Waffle", FENCE_POST_COLOUR, true)
	m:PivotTo(cframe)
	m.Parent = parent
	models += 1
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
end

local function circlePoint(deg)
	local th = math.rad(deg)
	return Vector3.new(FENCE_R * math.cos(th), Y, FENCE_R * math.sin(th)), th
end

-- fence sections along the circle FENCE_R from `from` to `to` degrees, each post at the start of its piece, so the
-- run opens at `from` with a post; the sections are spaced evenly so the last rails end exactly at `to`
local function fenceRun(f, walls, k, from, to)
	local dir = to > from and 1 or -1
	local length = FENCE_R * math.rad(math.abs(to - from))
	if length < 8 then
		return
	end
	local n = math.ceil((length - 8) / 8) + 1
	local step = if n > 1 then (length - 8) / (n - 1) else 0
	for i = 0, n - 1 do
		local _, th = circlePoint(from + dir * math.deg((i * step + 4) / FENCE_R))
		local pos = Vector3.new(FENCE_R * math.cos(th), Y, FENCE_R * math.sin(th))
		local along = Vector3.new(-math.sin(th), 0, math.cos(th)) * dir
		-- the model's +X (its post) points back along the run
		local cframe = CFrame.fromMatrix(pos, -along, Vector3.yAxis)
		fencePiece(f, "FenceSection", cframe, k)
		fenceWall(walls, cframe, 8.2)
	end
end

local function fencePost(f, walls, k, deg)
	local pos, th = circlePoint(deg)
	local cframe = CFrame.fromMatrix(pos, Vector3.new(-math.sin(th), 0, math.cos(th)), Vector3.yAxis)
	fencePiece(f, "FencePost", cframe, k)
	fenceWall(walls, cframe, 1.8)
end

-- the fence of sector k: from its bridge opening out to the middle of both gaps (or to the opening at the harbour
-- gate); the post in the middle of a gap belongs to the sector on its larger-angle side
local function buildFence(k, f)
	local angle = rampAngle(k)
	local sperre = map:FindFirstChild("Sperre")
	if not sperre then
		sperre = Instance.new("Folder")
		sperre.Name = "Sperre"
		sperre.Parent = map
	end
	local walls = folder(child(sperre, "Hubzaun"), string.format("Sektor_%02d", k))
	local open = math.deg(math.asin(FENCE_GAP / FENCE_R))
	local gate = math.deg(math.asin(GATE_GAP / FENCE_R))
	local up = SPECIAL[(angle + 15) % 360] == "HarborGate"
	local down = SPECIAL[(angle - 15) % 360] == "HarborGate"
	local upEnd = angle + 15 - (up and gate or 0)
	local downEnd = angle - 15 + (down and gate or 0)
	fenceRun(f, walls, k, angle + open, upEnd)
	fenceRun(f, walls, k, angle - open, downEnd)
	fencePost(f, walls, k, downEnd)
	if up then
		fencePost(f, walls, k, upEnd)
	end
end

-- decoration ----------------------------------------------------------------------------------------------------

local function place(parent, name, angle, u, r, face, lift, yaw)
	local template = kit:FindFirstChild(name)
	assert(template, "no template ServerStorage.HubKit." .. name)
	local er, et = basis(angle)
	local pos = at(angle, u, r) + Vector3.new(0, Y + (lift or 0), 0)
	local front
	if face == "path" then
		front = et * (u > 0 and -1 or 1)
	elseif face == "out" then
		front = er
	elseif face == "along" then
		front = et
	else -- "in"
		front = -er
	end
	local cf = CFrame.lookAt(pos, pos + front) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	local copy = template:Clone()
	copy:PivotTo(cf)
	copy.Parent = parent
	models += 1
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return copy
end

-- a small fixed jitter so the groups do not look stamped
local function jitter(k, i)
	return ((k * 37 + i * 61) % 41) - 20
end

-- whether a building stands in the bed on `side` of sector k (its bush is left out)
local function taken(k, side)
	for _, b in BUILDINGS do
		if b.sector == k and b.bed == side then
			return true
		end
	end
	return false
end

local function buildSector(k)
	local angle = rampAngle(k)
	local f = folder(hub, string.format("Sektor_%02d", k))
	local ways = folder(f, "Wege")
	for _, rect in RADIAL do
		radialWay(ways, angle, rect)
	end
	ringWays(ways, angle - 15, angle + 15)
	plotPaths(k, folder(f, "PlotWege"))
	local beds = folder(f, "Beete")
	for _, rect in BEDS do
		if not SPECIAL[(angle + (rect[5] == "L" and -15 or 15)) % 360] then
			bed(beds, angle, rect)
		end
	end
	for i, e in BED_PLANTS do
		if not SPECIAL[(angle + (e[4] == "L" and -15 or 15)) % 360] and not taken(k, e[4]) then
			place(f, e[1], angle, e[2], e[3], "in", BED_TOP, jitter(k, i + 10) * 4)
		end
	end
	buildFence(k, folder(f, "Zaun"))
	for _, e in FORECOURT do
		place(f, e[1], angle, e[2], e[3], e[4])
	end
	local nextK = k % 12 + 1
	local prevK = (k - 2) % 12 + 1
	-- u < 0 lies towards smaller angles, the gap to sector k + 1; u > 0 the gap to sector k - 1
	if not SPECIAL[(angle - 15) % 360] then
		for i, e in TREES do
			if not e[6] or k % 2 == 1 then
				local m = place(f, e[1], angle, e[2], e[3], "in", e[4], jitter(k, i) * 4)
				if e[5] then
					recolour(m, "Crown", MAIN[e[5] == "own" and k or nextK])
				end
			end
		end
	end
	if not SPECIAL[(angle + 15) % 360] then
		for i, e in CRATES do
			local m = place(f, e[1], angle, e[2], e[3], "in", e[4], jitter(k, i) * 2)
			-- mixed colours: the own flavour, the neighbour's and wood in turn
			local pick = (k + i) % 3
			if pick ~= 0 then
				recolour(m, e[1] == "Crate" and "Frame" or "Body", MAIN[pick == 1 and k or prevK])
			end
		end
	end
end

local function buildUniques()
	local f = folder(hub, "Einzelstuecke")
	local ways = child(f, "Wege")
	for _, b in BUILDINGS do
		local m = place(f, b[1], b.gap or rampAngle(b.sector), b.u, b.r, b.face, b.lift)
		recolour(m, "Pink", MAIN[b.accent], true)
	end
	for angle, what in SPECIAL do
		local spec = UNIQUE[what]
		if spec then
			for _, e in spec.pieces do
				place(f, e[1], angle, e[2], e[3], e[4])
			end
			radialWay(ways, angle, spec.spur)
		end
	end
end

local function buildPlaceholders()
	local f = folder(hub, "Platzhalter")
	local ways = child(f, "Wege")
	for angle, what in SPECIAL do
		if not UNIQUE[what] then
			local er = basis(angle)
			local pos = at(angle, 0, (SHOP.r0 + SHOP.r1) / 2) + Vector3.new(0, Y + 0.06, 0)
			local p = Instance.new("Part")
			p.Name = "Platzhalter_" .. what
			p.Size = Vector3.new(SHOP.width, 0.1, SHOP.r1 - SHOP.r0)
			p.CFrame = CFrame.lookAt(pos, pos - er)
			p.Color = Color3.fromHex(SHOP.colour)
			p.Material = Enum.Material.SmoothPlastic
			p.Transparency = SHOP.transparency
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p:SetAttribute("Placeholder", what)
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 10
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 0.3)
			label.Position = UDim2.fromScale(0, 0.35)
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.TextColor3 = Color3.fromHex("#7A4528")
			label.Text = what
			label.Parent = gui
			gui.Parent = p
			p.Parent = f
			parts += 1
			radialWay(ways, angle, SHOP.spur)
		end
	end
end

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local recording = ChangeHistoryService:TryBeginRecording("HubDecor")
local list = SECTORS == "all" and { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 } or SECTORS
if RESTORE_PLOT_PATHS then
	for _, k in list do
		lowerPlotPaths(k)
		local s = hub:FindFirstChild(string.format("Sektor_%02d", k))
		local w = s and s:FindFirstChild("PlotWege")
		if w then
			w:Destroy()
		end
	end
else
	for _, k in list do
		buildSector(k)
	end
	if UNIQUES then
		buildUniques()
	end
	if PLACEHOLDERS then
		buildPlaceholders()
	end
end
-- the lantern lights on every copy (the template keeps them off)
for _, d in hub:GetDescendants() do
	if d:IsA("PointLight") then
		d.Enabled = LANTERN_LIGHT.enabled
		d.Brightness = LANTERN_LIGHT.brightness
		d.Range = LANTERN_LIGHT.range
	end
end

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end

-- check: no piece (its rotated bounding box, crowns and umbrellas included) reaches into a way, from the ramp's top
-- (r 159) to the bridge (r 232)
local blocked = {}
for _, d in hub:GetDescendants() do
	if d:IsA("Model") and d.Parent:IsA("Folder") then
		local cf, size = d:GetBoundingBox()
		local corners = {}
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(corners, (cf * CFrame.new(sx * size.X / 2, 0, sz * size.Z / 2)).Position)
			end
		end
		for k = 1, 12 do
			local er, et = basis(rampAngle(k))
			local lo, hi, rmin, rmax = math.huge, -math.huge, math.huge, -math.huge
			for _, c in corners do
				local u, r = c:Dot(et), c:Dot(er)
				lo, hi = math.min(lo, u), math.max(hi, u)
				rmin, rmax = math.min(rmin, r), math.max(rmax, r)
			end
			if rmax > 159 and rmin < 232 and hi > -PATH_HALF and lo < PATH_HALF then
				table.insert(blocked, ("%s in way %02d"):format(d:GetFullName(), k))
			end
		end
	end
end
if #blocked > 0 then
	warn("HubDecor: pieces in a way: " .. table.concat(blocked, ", "))
end

local totalModels, totalParts = 0, 0
for _, d in hub:GetDescendants() do
	if d:IsA("Model") and d.Parent:IsA("Folder") then
		totalModels += 1
	elseif d:IsA("BasePart") then
		totalParts += 1
	end
end
print(
	("HubDecor: built %d models, %d parts; Dekoracje.Hub now %d models, %d parts; %d pieces in a way"):format(
		models,
		parts,
		totalModels,
		totalParts,
		#blocked
	)
)
