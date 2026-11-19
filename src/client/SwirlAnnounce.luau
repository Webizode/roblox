-- The Big Swirl announces a rare shot before it fires (Config/Vfx.flight, RarityFlight; ShotRenderer calls `shot` for
-- every shot): before an epic it flashes purple for a moment, before a legendary it glows gold for about a second (the
-- server lets only that shot leave that much later). A light in the middle of the machine, for a glow also a golden
-- outline over it (one Highlight, only for legendary). It shows at every VFX quality: it is the warning.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RarityFlight = require(Shared:WaitForChild("RarityFlight"))
local VfxConfig = require(Config:WaitForChild("Vfx"))
local Flavors = require(Config:WaitForChild("Flavors"))

local SwirlAnnounce = {}

local glowPart: Part? = nil
local light: PointLight? = nil
local outline: Highlight? = nil

local function machine(): Model?
	local pier = workspace:FindFirstChild("Pier")
	local swirl = pier and pier:FindFirstChild("BigSwirl")
	return if swirl and swirl:IsA("Model") then swirl else nil
end

-- The light (and the outline) on the machine, made the first time and again if the machine was streamed anew.
local function rig(): (PointLight?, Highlight?)
	local model = machine()
	if not model then
		return nil, nil
	end
	if not glowPart or not glowPart.Parent or not light or not outline or outline.Adornee ~= model then
		if glowPart then
			glowPart:Destroy()
		end
		local box, size = model:GetBoundingBox()
		local part = Instance.new("Part")
		part.Name = "SwirlAnnounceLight"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.one * 0.2
		part.CFrame = CFrame.new(box.Position + Vector3.new(0, size.Y * 0.2, 0))
		part.Parent = workspace
		local made = Instance.new("PointLight")
		made.Brightness = 0
		made.Shadows = false
		made.Parent = part
		local edge = Instance.new("Highlight")
		edge.Adornee = model
		edge.DepthMode = Enum.HighlightDepthMode.Occluded
		edge.FillTransparency = 1
		edge.OutlineTransparency = 1
		edge.Enabled = false
		edge.Parent = part
		glowPart, light, outline = part, made, edge
	end
	return light, outline
end

local function at(serverTime: number, run: () -> ())
	task.delay(math.max(0, serverTime - workspace:GetServerTimeNow()), run)
end

-- A shot of `flavorId` that leaves at server time `t0`.
function SwirlAnnounce.shot(flavorId: string, t0: number)
	local flavor = Flavors.byId[flavorId]
	if not flavor then
		return
	end
	local style = RarityFlight.style(flavor.rarity, "high", VfxConfig.flight, Flavors.rarityColors)
	local announce = style.announce
	if not announce then
		return
	end
	local color = Color3.fromHex(style.color)
	at(t0 - announce.time, function()
		local glow, edge = rig()
		if not glow or not edge then
			return
		end
		glow.Color = color
		glow.Range = announce.range
		if announce.kind == "glow" then
			-- it swells over `time` up to the release, then fades quickly
			edge.OutlineColor, edge.FillColor = color, color
			edge.Enabled = true
			local rise = TweenInfo.new(announce.time, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
			TweenService:Create(glow, rise, { Brightness = announce.brightness }):Play()
			TweenService:Create(edge, rise, { OutlineTransparency = 0, FillTransparency = 0.7 }):Play()
			task.delay(announce.time, function()
				local fall = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				TweenService:Create(glow, fall, { Brightness = 0 }):Play()
				local out = TweenService:Create(edge, fall, { OutlineTransparency = 1, FillTransparency = 1 })
				out.Completed:Once(function()
					edge.Enabled = false
				end)
				out:Play()
			end)
		else
			-- a flash: up at once, down over `time`
			glow.Brightness = announce.brightness
			TweenService:Create(glow, TweenInfo.new(announce.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Brightness = 0,
			}):Play()
		end
	end)
end

-- for checks: the machine's announcement light as it is now
function SwirlAnnounce.state(): (number, boolean)
	return if light then light.Brightness else 0, outline ~= nil and outline.Enabled
end

return SwirlAnnounce
