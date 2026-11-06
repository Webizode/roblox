--!nocheck
-- Puts the plot kit (ServerStorage.PlotKit, made by studio_plotkit_templates.luau) on all 12 plot islands (Edit mode,
-- command bar or Studio MCP), every plot the same, turned to its own bridge. In the plot's frame (PlotLayout: u along
-- the ring, right as seen from the bridge; v along the lane, outward; the bridge meets the inner side v -30 in the
-- middle), as seen from the bridge since 06.11.2026 (Config/Map.plot.stations, plaza, serveAt, spawnAt, signAt):
--   Working Station on the left (-36, -4), Sell Cart at the back in the middle (0, 16) looking at the bridge, Scoop
--   Chest on the right (32, -4), all facing the round plaza (0, -4). Paths: from the bridge (18 wide at the
--   bridgehead, then 6) to the plaza, on to the cart's forecourt (the ServePoint (0, 9) in front of its counter), to
--   the station and to the chest. The Plot Sign stays at the bridgehead (24, -26); the fence round it all at u +-48,
--   v +-24 with a gap of 32 for the bridge (u -16..16: the bridge is 18 wide, nothing of the fence stands in its way).
--   Until 05.11.2026 the Sell Cart stood at the bridgehead (0, -17) with the ServePoint at (0, -24), the station at the
--   back, the chest at (28, -1).
-- Each plot gets a Folder PlotKit in Ice Cream Map.Plots.Plot_NN (rebuilt every run). Also:
--   * the old graybox sign (Plot_NN.PlotSign) moves to ServerStorage."MapBackup_2026-11-05_PlotSigns" (once)
--   * the zone markers (Plot_NN.Strefy) are hidden (Transparency 1, their labels off): the models stand there now
--   * Pier.Plots.Plot_NN.ServePoint and .Spawn move to PlotLayout.servePoint / spawn, keeping their height
--   * Pier.Plots.Plot_NN.Body (the owner's name) moves over the sign
-- Models stand on the surface (Config/Map.plot.surfaceY), path stones PATH_SINK lower (they have no collision).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapConfig = require(Shared.Config.Map)
local PlotLayout = require(Shared.PlotLayout)

local KIT = ServerStorage:FindFirstChild("PlotKit")
assert(KIT, "ServerStorage.PlotKit is missing: run studio_plotkit_templates.luau first")
local PATH_SINK = 0.2
local BODY_ABOVE_SIGN = 4 -- studs from the sign's top to the name label
local PLOT = MapConfig.plot
local SIGN = { PlotLayout.sign(PLOT) } -- (24, -26)
local SERVE = { PlotLayout.servePoint(PLOT) } -- (0, 9)
local PLAZA = PLOT.plaza -- (0, -4)

-- { template, u, v, turn in degrees (0: its front to the bridge, -v), sink }
local ITEMS = {
	{ "PlotSign", SIGN[1], SIGN[2], 0 },
	{ "PathRound", PLAZA.u, PLAZA.v, 0, PATH_SINK }, -- 14 across: u -7..7, v -11..3
}
for id, station in PLOT.stations do
	table.insert(ITEMS, { id, station.u, station.v, station.turn })
end
-- PathStraight is 6 wide (its x) and 4 long (its z): turned 0 it runs along v, turned 90 along u
for _, v in { -25, -21 } do -- the bridgehead, as wide as the bridge: u -9..9, v -27..-19
	for _, u in { -6, 0, 6 } do
		table.insert(ITEMS, { "PathStraight", u, v, 0, PATH_SINK })
	end
end
for _, v in { -17, -13 } do -- on to the plaza, v -19..-11
	table.insert(ITEMS, { "PathStraight", 0, v, 0, PATH_SINK })
end
table.insert(ITEMS, { "PathStraight", 0, PLAZA.v + 8, 0, PATH_SINK }) -- from the plaza to the cart, v 2..6
for _, u in { -6, -2, 2, 6 } do -- the cart's forecourt round the ServePoint: u -8..8, v 6..12 (under the cart's front)
	table.insert(ITEMS, { "PathStraight", u, SERVE[2], 90, PATH_SINK })
end
for _, u in { 9, 13, 17, 21, 25, 29 } do -- to the station's counter (u -31.6): u -31..-7
	table.insert(ITEMS, { "PathStraight", -u, PLAZA.v, 90, PATH_SINK })
end
for _, u in { 9, 13, 17, 21, 25 } do -- to the chest (its front at u 28): u 7..27
	table.insert(ITEMS, { "PathStraight", u, PLAZA.v, 90, PATH_SINK })
end
-- the fence, once round from the right side of the gap to its left side: every section has its post at its start
-- (seen in the direction of the round), so each corner gets one post; a FencePost closes the gap's left side
local FENCE_U, FENCE_V, GAP, STEP = 48, 24, 16, 8
local LOOP = { { GAP, -FENCE_V }, { FENCE_U, -FENCE_V }, { FENCE_U, FENCE_V }, { -FENCE_U, FENCE_V }, { -FENCE_U, -FENCE_V }, { -GAP, -FENCE_V } }
for i = 1, #LOOP - 1 do
	local a, b = LOOP[i], LOOP[i + 1]
	local du, dv = b[1] - a[1], b[2] - a[2]
	local length = math.sqrt(du * du + dv * dv)
	du, dv = du / length, dv / length
	local turn = math.deg(math.atan2(dv, du))
	for k = 0, math.round(length / STEP) - 1 do
		local s = STEP * (k + 0.5)
		table.insert(ITEMS, { "FenceSection", a[1] + du * s, a[2] + dv * s, turn })
	end
end
table.insert(ITEMS, { "FencePost", LOOP[#LOOP][1], LOOP[#LOOP][2], 0 })

-- The model's pivot on the plot with this frame: at (u, v) on the surface, turned `turn` degrees in the plot's u-v
-- plane. The kit models' X runs against Blender's x (the import turns it round), so their X axis is -(the turned u).
local function placeAt(frame, u, v, turn, sink)
	local x, z = PlotLayout.toWorld(frame, u, v)
	local right = Vector3.new(frame.rightX, 0, frame.rightZ)
	local out = Vector3.new(frame.outX, 0, frame.outZ)
	local t = math.rad(turn)
	local ex = right * math.cos(t) + out * math.sin(t) -- the model's own x (Blender) after the turn
	local ey = -right * math.sin(t) + out * math.cos(t) -- its back (Blender +y, Roblox +Z)
	return CFrame.fromMatrix(Vector3.new(x, MapConfig.plot.surfaceY - (sink or 0), z), -ex, Vector3.yAxis, ey)
end

local map = workspace["Ice Cream Map"]
local pier = workspace.Pier
local backup = ServerStorage:FindFirstChild("MapBackup_2026-11-05_PlotSigns")
if not backup then
	backup = Instance.new("Folder")
	backup.Name = "MapBackup_2026-11-05_PlotSigns"
	backup.Parent = ServerStorage
end
local signTop = KIT.PlotSign:GetExtentsSize().Y
local report = {}
for _, plot in map.Plots:GetChildren() do
	local index = PlotLayout.indexOf(plot.Name)
	if not index then
		continue
	end
	local frame = PlotLayout.frame(PlotLayout.laneAngle(index, MapConfig), MapConfig)
	local old = plot:FindFirstChild("PlotKit")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "PlotKit"
	for _, item in ITEMS do
		local copy = KIT[item[1]]:Clone()
		copy:PivotTo(placeAt(frame, item[2], item[3], item[4], item[5]))
		copy.Parent = folder
	end
	folder.Parent = plot
	-- the old graybox sign goes to the backup, the zone markers hide
	local oldSign = plot:FindFirstChild("PlotSign")
	if oldSign and oldSign:IsA("Model") and not oldSign:FindFirstChild("PlotSign_Face_Cream") then
		oldSign.Name = plot.Name .. "_PlotSign"
		oldSign.Parent = backup
	end
	local markers = plot:FindFirstChild("Strefy")
	if markers then
		for _, marker in markers:GetDescendants() do
			if marker:IsA("BasePart") then
				marker.Transparency = 1
			elseif marker:IsA("SurfaceGui") then
				marker.Enabled = false
			end
		end
	end
	-- the owner's name over the new sign (where Config/Map.plot.signAt puts it, PlotLayout.sign)
	local helpers = pier.Plots:FindFirstChild(plot.Name)
	local body = helpers and helpers:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		local x, z = PlotLayout.toWorld(frame, SIGN[1], SIGN[2])
		body.Position = Vector3.new(x, MapConfig.plot.surfaceY + signTop + BODY_ABOVE_SIGN, z)
	end
	-- the ServePoint in front of the Sell Cart, the Spawn on the plaza; each keeps its height above the ground
	for name, spot in { ServePoint = SERVE, Spawn = { PlotLayout.spawn(PLOT) } } do
		local helper = helpers and helpers:FindFirstChild(name)
		if helper and helper:IsA("BasePart") then
			local x, z = PlotLayout.toWorld(frame, spot[1], spot[2])
			helper.CFrame = helper.CFrame - helper.Position + Vector3.new(x, helper.Position.Y, z)
		end
	end
	table.insert(report, `{plot.Name}: {#folder:GetChildren()} models`)
	task.wait()
end
return table.concat(report, ", ")
