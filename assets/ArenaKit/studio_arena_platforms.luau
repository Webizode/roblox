-- Studio (Edit, run through the MCP or the command bar), kill test 13.11.2026: highground in the arena.
--
-- Six raised platforms in Ice Cream Map.Platformy, one at every second gap between the arena ramps (30, 90, ... 330
-- degrees), each moved to the nearest spot clear of the cover in Covery (2.5 studs round every box, searched on
-- 14.11.2026, see PLATFORMS) and turned to fit there. Each one: a rounded IceKit plateau 18 x 12, HEIGHT high, with a
-- ramp of RAMP_LENGTH at both short ends. A jump from the side gets on top too (measured on 14.11.2026: Roblox's step-up
-- at an edge carries a character onto 6.8 at JumpPower 40); the ramps are the easy way up. The meshes are copies of the old plateau's (ServerStorage.MapBackup_2026-11-04_Plots70, Platformy.Plateau_01)
-- because a script cannot set a MeshId; they neither collide nor take queries. Invisible boxes and wedges
-- (*_Kolizja) collide, stop thrown balls and are ground for landing scoops, like the ramps in Schody.
-- Highground is an advantage, not a fortress: open edges, nothing on top, seen and hit from below.
-- REMOVE = true clears Platformy again.

local REMOVE = false

local FLOOR = 1.2 -- top of Arena_Boden
local HEIGHT = 5.6
local LENGTH, DEPTH = 18, 12 -- along the platform (the ramps' line) and across
local RAMP_LENGTH, RAMP_WIDTH = 15, 6
-- { angle in degrees, radius, turn in degrees from lying along the ring }
local PLATFORMS = {
	{ 30, 73, -30 },
	{ 98, 73, 0 },
	{ 150, 75, -30 },
	{ 210, 75, -30 },
	{ 269, 73, 30 },
	{ 330, 76, 60 },
}

local map = workspace["Ice Cream Map"]
local folder = map:FindFirstChild("Platformy")
assert(folder, "Ice Cream Map.Platformy is missing")
folder:ClearAllChildren()
if REMOVE then
	print("[Platforms] removed")
	return "removed"
end

local template = game:GetService("ServerStorage")["MapBackup_2026-11-04_Plots70"]
	:FindFirstChild("Platformy", true).Plateau_01
local plateauMesh = template.Plateau
local rampMesh = template.Rampa_zewn

local function setup(part: BasePart, visible: boolean)
	part.Anchored = true
	part.Locked = true
	part.CanTouch = false
	if visible then
		part.CanCollide = false
		part.CanQuery = false
	else
		part.CanCollide = true
		part.CanQuery = true
		part.Transparency = 1
		part.CastShadow = false
	end
end

for index, spec in PLATFORMS do
	local angle, radius, turn = math.rad(spec[1]), spec[2], math.rad(spec[3])
	local centre = Vector3.new(math.cos(angle) * radius, FLOOR, math.sin(angle) * radius)
	local along = angle + math.pi / 2 + turn
	local look = Vector3.new(math.cos(along), 0, math.sin(along))
	local frame = CFrame.lookAt(centre, centre + look) -- -Z of this frame runs along the platform
	local model = Instance.new("Model")
	model.Name = string.format("Platform_%02d", index)

	local top = frame * CFrame.new(0, HEIGHT / 2, 0)
	local mesh = plateauMesh:Clone()
	mesh.Name = "Plateau"
	mesh.Size = Vector3.new(DEPTH, HEIGHT, LENGTH)
	mesh.CFrame = top
	setup(mesh, true)
	mesh.Parent = model
	local box = Instance.new("Part")
	box.Name = "Plateau_Kolizja"
	box.Size = Vector3.new(DEPTH, HEIGHT, LENGTH)
	box.CFrame = top
	setup(box, false)
	box.Parent = model

	for _, side in { -1, 1 } do
		-- a WedgePart is high at its +Z end: turn it so that end meets the plateau
		local at = frame * CFrame.new(0, HEIGHT / 2, side * (LENGTH / 2 + RAMP_LENGTH / 2))
		local wedgeFrame = if side == 1 then at * CFrame.Angles(0, math.pi, 0) else at
		local wedge = Instance.new("WedgePart")
		wedge.Name = if side == 1 then "Rampa_a_Kolizja" else "Rampa_b_Kolizja"
		wedge.Size = Vector3.new(RAMP_WIDTH, HEIGHT, RAMP_LENGTH)
		wedge.CFrame = wedgeFrame
		setup(wedge, false)
		wedge.Parent = model
		-- the ramp mesh lies along its X axis, high at -X: a quarter turn from the wedge (as in the old plateau)
		local ramp = rampMesh:Clone()
		ramp.Name = if side == 1 then "Rampa_a" else "Rampa_b"
		ramp.Size = Vector3.new(RAMP_LENGTH, HEIGHT, RAMP_WIDTH)
		ramp.CFrame = wedgeFrame * CFrame.Angles(0, math.rad(90), 0)
		setup(ramp, true)
		ramp.Parent = model
	end
	model.Parent = folder
end

local text = string.format("[Platforms] %d platforms in %s", #PLATFORMS, folder:GetFullName())
print(text)
return text
