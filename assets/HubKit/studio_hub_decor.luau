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
--     with the signpost. PLACEHOLDERS: flat see-through plates for the shops and the leaderboard (folder Platzhalter).
--   * the lawn (LAWN): one meadow round the hub up to every curb, the ways and squares cut out, and under it the
--     terrain grass (GRASS_TERRAIN) whose blades grow through it; the script checks that none lies under a walkway.
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
-- the lawn: top over the ground (since 07.11.2026, before 0.26). Free scoops rest on the ring under it (the lawn has no
-- collision, MapQuery.ground looks through it): at 0.26 they sank in visibly (playtest 07.11.2026), at 0.08 they sit on it
local BED_TOP = 0.08
-- the lawn (since 07.11.2026, before: up to three loose beds per sector): one meadow round the whole hub, right up to
-- every curb. Per sector and side one field inside the ring walkway and one outside it, from the way's middle to the
-- gap (where the next sector's field runs on without a seam). Paved stay only the walkways themselves and the squares
-- cut out of the meadow: the forecourt at each bridge, the squares of the shops, the fountain (with the cafe) and the
-- harbour gate, and the square in front of the pavilion.
-- A field runs from `near` (its edge on the ring walkway's curb) to `far` (the strip at r 171, or under the fence).
-- The ring walkway is built from straight chords of 7.5 degrees (RING_CHORDS), so near the walkway the lawn is built
-- from pieces of the same 7.5 degrees whose straight edge lies exactly on the curb: r = curb / cos(3.75 degrees).
local CHORD_HALF = math.rad(180 / RING_CHORDS)
local RING_MID = RING_R * math.cos(CHORD_HALF) -- the walkway's middle line, in the middle of a chord
local LAWN = {
	{ near = (RING_MID - RING_W / 2 - CURB) / math.cos(CHORD_HALF), mid = 180, far = 171.05 },
	{ near = (RING_MID + RING_W / 2 + CURB) / math.cos(CHORD_HALF), mid = 206, far = 231.8 },
}
local LAWN_COLOUR = "#6FA046" -- meadow green; since 10.11.2026 darker and less yellow (was #82B84E, under CartoonColor it read lime); the terrain grass takes the same
local LAWN_STEP = 1.875 -- degrees per straight piece along the arcs away from the walkway (the strip, the fence)
local WAY_CUT = 6 + CURB -- the way from the ramp to the bridge: its curbs end 6.6 from its middle
-- the forecourt at every bridge (lanterns, bench, planter, bin): |u| < u from r0 out to the fence, corners rounded
local FORECOURT_SQUARE = { u = 19.5, r0 = 207, corner = 3 }
-- next to a gap in SPECIAL: the paved square in the gap's frame (u from lo to hi, negative towards smaller angles),
-- per field; no entry: the meadow runs on over the gap
local LAWN_CLEAR = {
	UpgradeShop = { outer = { -24, 24 } },
	CosmeticShop = { outer = { -24, 24 } },
	QuestHub = { outer = { -24, 24 } },
	Fountain = { outer = { -38, 18 }, inner = { -8, 8 } }, -- outer: the cafe (u -36) and the benches; inner: the table
	HarborGate = { outer = { -15, 15 }, inner = { -8, 8 } }, -- inner: the kiosk and its front to the ring walkway
}
-- squares in front of buildings that stand in the meadow: { sector, u0, u1, r0, r1, corner } in the sector frame
local PLAZAS = {
	{ sector = 2, u0 = 29, u1 = 41, r0 = 195, r1 = 208.5, corner = 2 }, -- the pavilion, its front to the ring walkway
}
-- the terrain grass under the lawn (Terrain.Decoration: blades in the lawn, since 07.11.2026). Voxels of 4: the lower
-- layer (y 4..8) filled OCC brings the surface to about y 8.9, just under the paving (y 9): the blades grow up through
-- ring and lawn, and the terrain itself shows nowhere. Only columns whose middle lies INSET inside the lawn all round,
-- so no blade grows on a walkway or a square.
local GRASS_TERRAIN = { occ = 0.72, inset = 3.5 }
-- the leaderboard's place (a placeholder until the model comes): in front of the Cosmetic Shop, inside the ring
-- walkway, 17 off the shop's line and turned 25 degrees to the bridges, where most players walking from the plot to
-- the arena see it (sectors 11, 12 and 1; 07.11.2026)
local LEADERBOARD = { gap = 120, u = -17, r = 180, yaw = 25, size = Vector3.new(10, 11, 1) }
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
	"#C8792F", -- 09 Karamell (#E8B877 until 11.11.2026)
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
	{ "WafflePlanter", -13.5, 218, "path" }, -- on the forecourt square (|u| < 19.5)
}
-- side L lies towards sector k + 1 (the gap at angle - 15), R the other way.
-- In the outer L field, towards sector k + 1; crowns: own flavour or the neighbour's. Two ice trees at most (since
-- 07.11.2026, before three in every other sector), upright, away from the ways. They stand on the lawn (BED_TOP).
local TREES = {
	{ "IceTree", -29, 207, BED_TOP, "own" },
	{ "IceTree", -42, 221, BED_TOP, "next" },
	{ "FlowerBush", -36, 205, BED_TOP },
	{ "FlowerBush", -22, 224, BED_TOP }, -- clear of the fence wall (r 230)
	{ "Rock", -45, 210, BED_TOP },
}
-- one bush in the inner L field and one in the outer R field: { model, u, r, side }
local BED_PLANTS = {
	{ "FlowerBush", -26, 179, "L" },
	{ "FlowerBush", 33, 213, "R" },
}
-- inside the ring walkway on the other side (u > 0), on the lawn; y lifts a crate onto the one below
local CRATES = {
	{ "Crate", 28, 178, BED_TOP },
	{ "Crate", 28, 178, BED_TOP + 3 },
	{ "Crate", 32, 181.5, BED_TOP },
	{ "Barrel", 32.5, 176, BED_TOP },
	{ "Barrel", 25, 182.5, BED_TOP },
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

-- the lawn ---------------------------------------------------------------------------------------------------------
-- A field (LAWN) runs from the line at the sector's angle to the gap at angle + 15 s (s = -1: side L, +1: side R).
-- Built from exact trapezoids along the ring (block + two flat wedges each): of 7.5 degrees by the ring walkway, so
-- the edge lies on its straight curbs, of LAWN_STEP towards the strip or the fence. Merged into one PartOperation
-- (GeometryService), the way and the paved squares cut out, so nothing overlaps on the same plane. The lawn has no
-- collision and no queries: one walks on the ring BED_TOP in the grass, with no edge to trip on, and ground rays (free
-- scoops, MapQuery.ground) see the ring as before.

local GeometryService = game:GetService("GeometryService")
-- SplitApart = false: the trapezoids only touch edge to edge, and split apart they came back as loose pieces
local CSG = {
	-- precise: the terrain grass test (grassTerrain) casts rays on the lawn, and a Box would cover the cut-out ways
	CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition,
	RenderFidelity = Enum.RenderFidelity.Precise,
	SplitApart = false,
}

local function piece(parent, class, size, cframe)
	local p = Instance.new(class)
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.Parent = parent
	return p
end

-- a trapezoid between the radial lines at a and b (degrees), from r0 to r1, `h` high, its bottom on the ground
local function trapezoid(parent, a, b, r0, r1, h)
	local m = math.rad((a + b) / 2)
	local half = math.rad(math.abs(b - a) / 2)
	local er = Vector3.new(math.cos(m), 0, math.sin(m))
	local et = Vector3.new(-math.sin(m), 0, math.cos(m))
	-- the radial lines meet the arcs at u = ±r sin(half), measured along et from the line at m; along er at r cos(half)
	local v0, v1 = r0 * math.cos(half), r1 * math.cos(half)
	local w0, w1 = 2 * r0 * math.sin(half), 2 * r1 * math.sin(half)
	local L, e = v1 - v0, (w1 - w0) / 2
	local y = Vector3.new(0, Y + h / 2, 0)
	local mid = er * (v0 + v1) / 2 + y
	local pieces = { piece(parent, "Part", Vector3.new(w0, h, L), CFrame.lookAt(mid, mid + er)) }
	-- a flat wedge: local X up, its right angle at the outer corner of the block
	for _, side in { -1, 1 } do
		local c = mid + et * side * (w0 / 2 + e / 2)
		local up = Vector3.yAxis * side
		table.insert(pieces, piece(parent, "WedgePart", Vector3.new(h, e, L), CFrame.fromMatrix(c, up, et * side, er)))
	end
	return pieces
end

-- what to cut out of the lawn: the rectangle u0..u1, v0..v1 in the frame at `angle` (v along the line), its corners
-- rounded with radius `corner` (0: square), a little higher than the lawn
local function square(list, parent, angle, u0, u1, v0, v1, corner, h)
	local er, et = basis(angle)
	local y = Vector3.new(0, Y + h / 2, 0)
	local function box(a0, a1, b0, b1)
		local mid = er * (b0 + b1) / 2 + et * (a0 + a1) / 2 + y
		table.insert(list, piece(parent, "Part", Vector3.new(a1 - a0, h + 0.2, b1 - b0), CFrame.lookAt(mid, mid + er)))
	end
	local c = corner or 0
	if c <= 0 then
		box(u0, u1, v0, v1)
		return
	end
	box(u0, u1, v0 + c, v1 - c)
	box(u0 + c, u1 - c, v0, v1)
	for _, cu in { u0 + c, u1 - c } do
		for _, cv in { v0 + c, v1 - c } do
			local pos = er * cv + et * cu + y
			local round = piece(
				parent,
				"Part",
				Vector3.new(h + 0.2, 2 * c, 2 * c),
				CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
			)
			round.Shape = Enum.PartType.Cylinder
			table.insert(list, round)
		end
	end
end

-- the trapezoids of one field on side s, from the line at `angle` to the gap: `step` degrees each, from r0 to r1
local function strips(pieces, parent, angle, s, step, r0, r1, h)
	local n = math.max(1, math.round(15 / step))
	for i = 0, n - 1 do
		local a, b = angle + s * 15 * i / n, angle + s * 15 * (i + 1) / n
		for _, p in trapezoid(parent, a, b, math.min(r0, r1), math.max(r0, r1), h) do
			table.insert(pieces, p)
		end
	end
end

-- the lawn fields of sector k: per side the field inside the ring walkway (LAWN[1]) and outside it (LAWN[2])
local function lawn(k, parent)
	local angle = rampAngle(k)
	local h = BED_TOP
	local work = Instance.new("Folder")
	work.Name = "Bau"
	work.Parent = parent
	for _, s in { -1, 1 } do
		local gap = angle + 15 * s
		local clear = LAWN_CLEAR[SPECIAL[gap % 360]]
		for index, field in LAWN do
			-- by the walkway pieces of a chord (7.5 degrees) out to past `mid`, beyond it the fine pieces
			local pieces = {}
			local over = if field.far > field.near then 1 else -1
			strips(pieces, work, angle, s, 360 / RING_CHORDS, field.near, field.mid + over, h)
			strips(pieces, work, angle, s, LAWN_STEP, field.mid, field.far, h)
			local base = table.remove(pieces, 1)
			local ok, res = pcall(function()
				return GeometryService:UnionAsync(base, pieces, CSG)
			end)
			assert(ok and res[1], "HubDecor: lawn union failed: " .. tostring(res))
			local shape = res[1]
			shape.Parent = work
			-- cut out: the way from the ramp to the bridge, the forecourt, the gap's square, the squares of buildings
			local cut = {}
			square(cut, work, angle, -WAY_CUT, WAY_CUT, 150, 240, 0, h)
			if index == 2 then
				local f = FORECOURT_SQUARE
				square(cut, work, angle, -f.u, f.u, f.r0, 240, f.corner, h)
			end
			local range = clear and clear[if index == 1 then "inner" else "outer"]
			if range then
				square(cut, work, gap, range[1], range[2], 150, 240, 0, h)
			end
			for _, p in PLAZAS do
				if p.sector == k then
					square(cut, work, angle, p.u0, p.u1, p.r0, p.r1, p.corner, h)
				end
			end
			ok, res = pcall(function()
				return GeometryService:SubtractAsync(shape, cut, CSG)
			end)
			assert(ok and res[1], "HubDecor: lawn cut failed: " .. tostring(res))
			local grass = res[1]
			grass.Name = "Rasen"
			grass.UsePartColor = true
			grass.Color = Color3.fromHex(LAWN_COLOUR)
			grass.Material = Enum.Material.SmoothPlastic
			grass.MaterialVariant = "WS_Grass"
			grass.Anchored = true
			grass.CanCollide = false
			grass.CanQuery = false
			grass.CanTouch = false
			grass.CastShadow = false
			grass.Parent = parent
			parts += 1
			work:ClearAllChildren()
		end
	end
	work:Destroy()
end

-- the fence ---------------------------------------------------------------------------------------------------------

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
	lawn(k, folder(f, "Rasen"))
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
			label.FontFace = Font.fromEnum((Enum.Font :: any)[require(game:GetService("ReplicatedStorage").Shared.Config.Ui).fonts.main]) -- the main font (Config/Ui.fonts)
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
	-- the leaderboard's place: a see-through pink board with its word on both faces
	local lb = LEADERBOARD
	local er, et = basis(lb.gap)
	local pos = er * lb.r + et * lb.u + Vector3.new(0, Y + lb.size.Y / 2, 0)
	local board = Instance.new("Part")
	board.Name = "Platzhalter_Leaderboard"
	board.Size = lb.size
	board.CFrame = CFrame.lookAt(pos, pos + CFrame.fromAxisAngle(Vector3.yAxis, math.rad(lb.yaw)) * er)
	board.Color = Color3.fromHex("#FF4FA3")
	board.Material = Enum.Material.SmoothPlastic
	board.Transparency = 0.15
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	board:SetAttribute("Placeholder", "Leaderboard")
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 0.4)
		label.Position = UDim2.fromScale(0, 0.3)
		label.FontFace = Font.fromEnum((Enum.Font :: any)[require(game:GetService("ReplicatedStorage").Shared.Config.Ui).fonts.main]) -- the main font (Config/Ui.fonts)
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = "LEADERBOARD"
		label.Parent = gui
		gui.Parent = board
	end
	board.Parent = f
	parts += 1
end

-- the terrain grass under the lawn of the whole hub (GRASS_TERRAIN): the old grass voxels of the hub go, then every
-- voxel column whose middle and eight points INSET round it all lie on a lawn gets grass. The lawn parts take queries
-- only for this test.
local function grassTerrain()
	local T = workspace.Terrain
	local g = GRASS_TERRAIN
	local lawns = {}
	for _, d in hub:GetDescendants() do
		if d.Name == "Rasen" and d:IsA("BasePart") then
			d.CanQuery = true
			table.insert(lawns, d)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = lawns
	local function onLawn(x, z)
		return workspace:Raycast(Vector3.new(x, Y + 5, z), Vector3.new(0, -6, 0), params) ~= nil
	end
	local region = Region3.new(Vector3.new(-236, 4, -236), Vector3.new(236, 12, 236))
	local mats, occs = T:ReadVoxels(region, 4)
	local lo = region.CFrame.Position - region.Size / 2
	local columns = 0
	for ix = 1, mats.Size.X do
		for iz = 1, mats.Size.Z do
			local x, z = lo.X + (ix - 0.5) * 4, lo.Z + (iz - 0.5) * 4
			local r = math.sqrt(x * x + z * z)
			-- the region's corners reach the plot islands (Plot_02 and others): their grass (studio_plot_grass.luau) stays
			for iy = 1, mats.Size.Y do
				if r < 260 and mats[ix][iy][iz] == Enum.Material.Grass then
					mats[ix][iy][iz] = Enum.Material.Air
					occs[ix][iy][iz] = 0
				end
			end
			if r > 171 and r < 232 and onLawn(x, z) then
				local all = true
				for i = 0, 7 do
					local a = i * math.pi / 4
					if not onLawn(x + g.inset * math.cos(a), z + g.inset * math.sin(a)) then
						all = false
						break
					end
				end
				if all then
					mats[ix][1][iz] = Enum.Material.Grass
					occs[ix][1][iz] = g.occ
					columns += 1
				end
			end
		end
		if ix % 10 == 0 then
			task.wait()
		end
	end
	T:WriteVoxels(region, 4, mats, occs)
	for _, d in lawns do
		d.CanQuery = false
	end
	T.Decoration = true
	T.GrassLength = 0.4 -- since 10.11.2026 (was 0.7): long blades in front of the camera read as spikes
	T:SetMaterialColor(Enum.Material.Grass, Color3.fromHex(LAWN_COLOUR))
	return columns
end

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local recording = ChangeHistoryService:TryBeginRecording("HubDecor")
local list = SECTORS == "all" and { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 } or SECTORS
-- the build runs protected: an error (a CSG step, a missing template) cancels the recording instead of leaving it
-- open, which would block Studio's undo and every later command
local grassColumns = 0
local built, failure = pcall(function()
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
		grassColumns = grassTerrain()
	end
	-- the lantern lights on every copy (the template keeps them off)
	for _, d in hub:GetDescendants() do
		if d:IsA("PointLight") then
			d.Enabled = LANTERN_LIGHT.enabled
			d.Brightness = LANTERN_LIGHT.brightness
			d.Range = LANTERN_LIGHT.range
		end
	end
end)

if recording then
	ChangeHistoryService:FinishRecording(
		recording,
		if built then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
	)
end
assert(built, failure)

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

-- check: no model's collision touches a walkway (Weg, Bordstein), and no terrain grass lies under one
local walkways = {}
for _, d in hub:GetDescendants() do
	if d:IsA("BasePart") and (d.Name == "Weg" or d.Name == "Bordstein") then
		table.insert(walkways, d)
	end
end
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = walkways
local onWays = {}
for _, d in hub:GetDescendants() do
	if d:IsA("BasePart") and d.Name:sub(1, 9) == "Collision" and d.Parent:IsA("Model") then
		if #workspace:GetPartsInPart(d, overlap) > 0 then
			table.insert(onWays, d.Parent:GetFullName())
		end
	end
end
if #onWays > 0 then
	warn("HubDecor: collision on a walkway: " .. table.concat(onWays, ", "))
end
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
local grassUnderWays = 0
for _, w in walkways do
	for _, fx in { -0.45, 0, 0.45 } do
		for _, fz in { -0.45, 0, 0.45 } do
			local p = w.CFrame * Vector3.new(w.Size.X * fx, 0, w.Size.Z * fz)
			local hit = workspace:Raycast(Vector3.new(p.X, Y + 0.3, p.Z), Vector3.new(0, -2, 0), terrainOnly)
			if hit and hit.Material == Enum.Material.Grass then
				grassUnderWays += 1
			end
		end
	end
end
if grassUnderWays > 0 then
	warn(("HubDecor: terrain grass under walkways at %d points"):format(grassUnderWays))
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
	(
		"HubDecor: built %d models, %d parts; Dekoracje.Hub now %d models, %d parts; %d pieces in a way, "
		.. "%d collisions on walkways; %d terrain grass columns, %d grass points under walkways"
	):format(models, parts, totalModels, totalParts, #blocked, #onWays, grassColumns, grassUnderWays)
)
