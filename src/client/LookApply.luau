-- Applies a light and colour package of Config/Look to this data model: Lighting and its Atmosphere, colour correction,
-- bloom and sun rays, the terrain's grass and water, the hub lawn and plot ground, and the client sea. Nothing else.
-- Used by LookController on each client; Studio scripts (Edit mode) can require it to compare packages for screenshots.
-- Values that are colours are hex strings in the config; every other value is set as it is.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LookConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Look"))

local LookApply = {}

LookApply.MAP = "Ice Cream Map"

local function set(instance: Instance?, values: { [string]: any }?)
	if not instance or not values then
		return
	end
	for key, value in values do
		(instance :: any)[key] = if type(value) == "string" then Color3.fromHex(value) else value
	end
end

-- Whether a part of the map is grass: the hub lawn (Dekoracje.Hub.Sektor_*.Rasen) or a plot's ground
-- (Plots.Plot_*.Powierzchnia).
function LookApply.isGrass(part: Instance): boolean
	if not part:IsA("BasePart") then
		return false
	end
	if part.Name == "Rasen" then
		return true
	end
	local plot = part.Parent
	return part.Name == "Powierzchnia" and plot ~= nil and plot.Parent ~= nil and plot.Parent.Name == "Plots"
end

-- Whether `name` is a package of Config/Look.
function LookApply.has(name: string): boolean
	return LookConfig.presets[name] ~= nil
end

-- Colours one grass part as package `name` has it (for parts streamed in later).
function LookApply.paintGrass(part: BasePart, name: string)
	if part:IsA("UnionOperation") then
		part.UsePartColor = true
	end
	part.Color = Color3.fromHex(LookConfig.presets[name].grass)
end

function LookApply.apply(name: string)
	local preset = LookConfig.presets[name]
	assert(preset, `Look: no preset {name}`)
	set(Lighting, preset.lighting)
	set(Lighting:FindFirstChildOfClass("ColorCorrectionEffect"), preset.colorCorrection)
	set(Lighting:FindFirstChildOfClass("Atmosphere"), preset.atmosphere)
	set(Lighting:FindFirstChildOfClass("BloomEffect"), preset.bloom)
	set(Lighting:FindFirstChildOfClass("SunRaysEffect"), preset.sunRays)

	local terrain = workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromHex(preset.grass))
	terrain.WaterColor = Color3.fromHex(preset.water.color)
	terrain.WaterTransparency = preset.water.transparency
	local map = workspace:FindFirstChild(LookApply.MAP)
	if map then
		for _, part in map:GetDescendants() do
			if LookApply.isGrass(part) then
				LookApply.paintGrass(part :: BasePart, name)
			end
		end
	end
	local sea = workspace:FindFirstChild("Ocean")
	if sea and sea:IsA("BasePart") then
		sea.Color = Color3.fromHex(preset.ocean)
	end
end

return LookApply
