-- Makes still water pictures flow: every Texture tagged ScrollingWater (the hub fountain's ripples, set up by
-- assets/HubKit/studio_fountain_water.luau) slides by its ScrollU / ScrollV attributes (studs per second). Only on the
-- client and only while the texture is streamed in; the offset wraps at one tile, so it never grows.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "ScrollingWater"

local FountainWater = {}

local textures: { [Texture]: boolean } = {}

local function add(instance: Instance)
	if instance:IsA("Texture") then
		textures[instance] = true
	end
end

function FountainWater.Start()
	for _, instance in CollectionService:GetTagged(TAG) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
		textures[instance :: Texture] = nil
	end)
	RunService.Heartbeat:Connect(function(dt)
		for texture in textures do
			local u = texture:GetAttribute("ScrollU")
			local v = texture:GetAttribute("ScrollV")
			if typeof(u) == "number" and texture.StudsPerTileU > 0 then
				texture.OffsetStudsU = (texture.OffsetStudsU + u * dt) % texture.StudsPerTileU
			end
			if typeof(v) == "number" and texture.StudsPerTileV > 0 then
				texture.OffsetStudsV = (texture.OffsetStudsV + v * dt) % texture.StudsPerTileV
			end
		end
	end)
end

return FountainWater
