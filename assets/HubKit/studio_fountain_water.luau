-- Studio command bar / MCP: makes the hub fountain's water visible and moving (09.11.2026, kill-test feedback "the
-- water cannot be seen and stands still"). Safe to run again: it rebuilds only what it made.
--
-- Why it could not be seen: Fountain_Water was a pale #86DDF7 at 35 % transparency over the white basin, and the
-- CartoonColor correction lightens it further, so it read as part of the basin. Not streaming, not hidden by a script.
--
-- What it does, all in Dekoracje.Hub.Einzelstuecke.Fountain:
--   Fountain_Water           a stronger cartoon blue, less transparent
--   Fountain_Water.Ripples*  two Textures on the top (rbxassetid of Fountain_Ripples.png, make_fountain_textures.py),
--                            tagged ScrollingWater with ScrollU / ScrollV (studs per second): the client scrolls them
--                            (src/client/Controllers/FountainWater.luau), so the water flows
--   Fountain_Splash          an invisible disc in the basin with a ring of small splashes where the jets come down
--   Fountain_Cherry.JetTop   a soft jet of droplets above the top
-- Particles stay few (about 45 a second together), so phones keep up. Set RESTORE = true to take everything back
-- out and give the water its old colour.

local RESTORE = false

local RIPPLES = "rbxassetid://134345440824861" -- Fountain_Ripples.png
local DROP = "rbxassetid://109333264926383" -- Fountain_Drop.png
local WATER = { colour = Color3.fromHex("#4FC3F0"), transparency = 0.12 }
local OLD_WATER = { colour = Color3.fromHex("#86DDF7"), transparency = 0.35 }
local BASIN = { y = 11.4, radius = 5.6, inner = 0.72 } -- the basin water (measured by rays) and the ring the jets hit
local SPLASH_COLOUR = Color3.fromHex("#D8F4FF")

local CollectionService = game:GetService("CollectionService")
local fountain = workspace["Ice Cream Map"].Dekoracje.Hub.Einzelstuecke.Fountain
local water = fountain.Fountain_Water
local cherry = fountain.Fountain_Cherry

-- what this script made before
for _, old in water:GetChildren() do
	if old:IsA("Texture") and old.Name:sub(1, 7) == "Ripples" then
		old:Destroy()
	end
end
if fountain:FindFirstChild("Fountain_Splash") then
	fountain.Fountain_Splash:Destroy()
end
if cherry:FindFirstChild("JetTop") then
	cherry.JetTop:Destroy()
end

if RESTORE then
	water.Color, water.Transparency = OLD_WATER.colour, OLD_WATER.transparency
	return "fountain back to the old still water"
end

water.Color, water.Transparency = WATER.colour, WATER.transparency

-- two ripple layers at different sizes and directions, so the pattern never just slides as one sheet
for i, layer in { { studs = 5, u = 0.6, v = 1.1, see = 0.1 }, { studs = 3.2, u = -0.9, v = 0.5, see = 0.45 } } do
	local t = Instance.new("Texture")
	t.Name = "Ripples" .. i
	t.Face = Enum.NormalId.Top
	t.Texture = RIPPLES
	t.StudsPerTileU, t.StudsPerTileV = layer.studs, layer.studs
	t.Transparency = layer.see
	t:SetAttribute("ScrollU", layer.u)
	t:SetAttribute("ScrollV", layer.v)
	t.Parent = water
	CollectionService:AddTag(t, "ScrollingWater")
end

local function emitter(props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = DROP
	e.Color = ColorSequence.new(SPLASH_COLOUR)
	e.LightEmission = 0.3
	e.LightInfluence = 0.6
	for k, v in props do
		e[k] = v
	end
	return e
end

local centre = water.Position
local splash = Instance.new("Part")
splash.Name = "Fountain_Splash"
splash.Shape = Enum.PartType.Cylinder
-- a cylinder's axis is its X: turn it upright, so its disc lies flat in the basin
splash.Size = Vector3.new(0.2, BASIN.radius * 2, BASIN.radius * 2)
splash.CFrame = CFrame.new(centre.X, BASIN.y, centre.Z) * CFrame.Angles(0, 0, math.rad(90))
splash.Anchored, splash.CanCollide, splash.CanQuery, splash.CanTouch = true, false, false, false
splash.CastShadow = false
splash.Transparency = 1
emitter({
	Name = "Splashes",
	Shape = Enum.ParticleEmitterShape.Disc,
	ShapePartial = BASIN.inner,
	ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	EmissionDirection = Enum.NormalId.Right, -- the disc's normal: up, after the turn above
	Rate = 25,
	Lifetime = NumberRange.new(0.35, 0.6),
	Speed = NumberRange.new(3, 5),
	SpreadAngle = Vector2.new(25, 25),
	Acceleration = Vector3.new(0, -25, 0),
	Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.15) }),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
}).Parent = splash
splash.Parent = fountain

local jet = Instance.new("Attachment")
jet.Name = "JetTop"
jet.Parent = cherry -- first: WorldPosition counts from the parent
jet.WorldPosition = cherry.Position + Vector3.new(0, cherry.Size.Y / 2, 0)
emitter({
	Name = "Jet",
	Rate = 20,
	Lifetime = NumberRange.new(0.7, 0.9),
	Speed = NumberRange.new(6, 7.5),
	SpreadAngle = Vector2.new(9, 9),
	Acceleration = Vector3.new(0, -22, 0),
	Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.2) }),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.9) }),
}).Parent = jet

return "fountain water: "
	.. WATER.colour:ToHex()
	.. " at "
	.. WATER.transparency
	.. ", 2 ripple layers, splash ring and top jet"
