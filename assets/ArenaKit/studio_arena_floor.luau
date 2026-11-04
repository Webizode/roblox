--!nocheck
-- Builds the arena floor in Studio (Edit mode, run through the Studio MCP or the command bar). Replaces what is in
-- Ice Cream Map.Plac (the old floor is kept in ServerStorage."MapBackup_2026-11-04_ArenaFloor") and leaves the Big
-- Swirl's marker Arena_Znacznik where it is.
--
-- The old floor Arena_Baza was there twice and not anchored: at the start of a game both sank into the brown island
-- core (Wyspa_Kern, top y 1.0), which is what players saw and the landing spots stood on.
--
-- Two parts collide, both anchored: Arena_Boden (r 133, the plates, top at FLOOR_Y = 1.2, the level the ramps, the
-- rim and the cover stand on) and Arena_Rand (r 136, the pink rim, 0.02 lower so the two never fight for the same
-- pixels). Everything else lies above them and neither collides nor takes queries, so landing spots, throws and
-- walking only ever see the floor. All of it is Locked: a stray drag in Studio once lifted the floor 0.38 studs and
-- buried the emblem, the sprinkles and the landing circles in it.
--   Arena_Boden   cream plates: MaterialVariant WS_ArenaPlates (ArenaFloor_Tiles, 12 studs per tile, 2 x 2 plates)
--   Arena_Rand    the clean round edge, Pink
--   Emblem        a disc 0.06 over the floor, MaterialVariant WS_ArenaEmblem (ArenaEmblem, one tile across the disc):
--                 round the Big Swirl (whose base covers r 0-26) a Gold ring, the Waffle lattice and pink ice cream
--                 with drips, as if looking down into a cone
--   Streusel      a few flat sprinkles between r 55 and 125
-- Pictures as MaterialVariants, never as Texture or Decal on the floor: Roblox draws Texture and Decal objects
-- pulled towards the camera, by a lot at a player's low angle, so a textured floor swallowed whatever lay just above
-- it (landing circles at +0.12, loot, the emblem). A material has no such offset.
-- Colours: the game colours of the arena kit (assets/ArenaKit/arenakit.py GAME_COLOURS). Pictures:
-- assets/ArenaKit/make_floor_textures.py.

local FLOOR_Y = 1.2
local PLATES = { name = "WS_ArenaPlates", picture = "rbxassetid://84950832445484", studs = 12 }
local EMBLEM = { name = "WS_ArenaEmblem", picture = "rbxassetid://96149400644272", radius = 49 }
local COLOURS = {
	Rim = "#F06AAE",
	Gold = "#F2A83C",
	Pink = "#F06AAE",
	SkyBlue = "#75D6F2",
}

local map = workspace["Ice Cream Map"]
local plac = map.Plac
local SS = game:GetService("ServerStorage")
local MS = game:GetService("MaterialService")

local backupName = "MapBackup_2026-11-04_ArenaFloor"
if not SS:FindFirstChild(backupName) then
	local backup = Instance.new("Folder")
	backup.Name = backupName
	plac:Clone().Parent = backup
	backup.Parent = SS
end
for _, child in plac:GetChildren() do
	if child.Name ~= "Arena_Znacznik" then
		child:Destroy()
	end
end

local function variant(spec, studs)
	local v = MS:FindFirstChild(spec.name) or Instance.new("MaterialVariant")
	v.Name = spec.name
	v.BaseMaterial = Enum.Material.SmoothPlastic
	v.ColorMap = spec.picture
	v.StudsPerTile = studs
	v.Parent = MS
	return v.Name
end

local UP = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis (X) pointing up: its +X face (Right) is the top

local function disc(parent, name, radius, top, thickness, colour, solid)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(thickness, radius * 2, radius * 2)
	p.CFrame = CFrame.new(0, top - thickness / 2, 0) * UP
	p.Anchored = true
	p.Locked = true
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromHex(colour)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = solid
	p.CanQuery = solid
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- the floor and its rim: the only parts that collide
local floor = disc(plac, "Arena_Boden", 133, FLOOR_Y, 0.4, "#FFFFFF", true) -- white: the picture's own colours
floor.MaterialVariant = variant(PLATES, PLATES.studs)
disc(plac, "Arena_Rand", 136, FLOOR_Y - 0.02, 0.4, COLOURS.Rim, true)

-- the emblem round the Big Swirl: one disc, one picture
local emblem = disc(plac, "Emblem", EMBLEM.radius, FLOOR_Y + 0.06, 0.05, "#FFFFFF", false)
emblem.MaterialVariant = variant(EMBLEM, EMBLEM.radius * 2)

-- a few sprinkles, spread over the plates (off the emblem and the ramps)
local sprinkles = Instance.new("Folder")
sprinkles.Name = "Streusel"
sprinkles.Parent = plac
local rng = Random.new(11)
local colours = { COLOURS.Pink, COLOURS.SkyBlue, COLOURS.Gold }
for i = 1, 36 do
	local r = 55 + (125 - 55) * math.sqrt(rng:NextNumber())
	local a = rng:NextNumber() * math.pi * 2
	local s = Instance.new("Part")
	s.Name = "Streusel"
	s.Shape = Enum.PartType.Cylinder -- lying on its side: a little rod
	s.Size = Vector3.new(1.6, 0.4, 0.4)
	s.CFrame = CFrame.new(math.sin(a) * r, FLOOR_Y + 0.05, math.cos(a) * r)
		* CFrame.Angles(0, rng:NextNumber() * math.pi, 0)
	s.Anchored = true
	s.Locked = true
	s.Material = Enum.Material.SmoothPlastic
	s.Color = Color3.fromHex(colours[(i - 1) % #colours + 1])
	s.CanCollide = false
	s.CanQuery = false
	s.CanTouch = false
	s.CastShadow = false
	s.Parent = sprinkles
end

local count = 0
for _, d in plac:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
return `arena floor built, {count} parts in Plac`
