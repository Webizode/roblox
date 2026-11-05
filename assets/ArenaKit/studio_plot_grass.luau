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

local GRASS = { name = "WS_Grass", picture = "rbxassetid://79201403556010", studs = 16 }
local TINT = Color3.fromHex("#FFFFFF")
local SURFACE_Y = 9.0 -- Config/Map.plot.surfaceY
local BODY_DROP = 0.1
local MARKER_TRANSPARENCY = 0.8

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

local done, lowered = 0, 0
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
	end
end
return `{done} plot surfaces are grass ({GRASS.name}, {GRASS.studs} studs per tile), {lowered} island bodies lowered`
