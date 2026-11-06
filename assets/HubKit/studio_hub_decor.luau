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
	{ "WafflePlanter", -16, 218, "path" },
}
-- outside the ring walkway, towards sector k + 1 (u < 0); crowns: own flavour or the neighbour's; the sixth field
-- marks the third tree, only in every other sector
local TREES = {
	{ "IceTree", -28, 207, 0, "own" },
	{ "IceTree", -40, 216, 0, "next" },
	{ "IceTree", -30, 223, 0, "own", true },
	{ "FlowerBush", -36, 205, 0 },
	{ "FlowerBush", -22, 226, 0 },
	{ "Rock", -47, 208, 0 },
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
local function recolour(model, part, hex)
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") and d.Name:find("_" .. part .. "_", 1, true) then
			d.Color = Color3.fromHex(hex)
		end
	end
end

-- a small fixed jitter so the groups do not look stamped
local function jitter(k, i)
	return ((k * 37 + i * 61) % 41) - 20
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
