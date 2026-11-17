-- The Scoop Chest's looks (Config/Vfx effects.chestOpen and chestGlint, Config/Chest.glow): golden stars and a soft
-- flash rise out of it as the lid opens, a warm light glows inside while it stands open and a glint rises now and
-- then. Everybody sees it on every plot (ChestController); purely looks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Vfx = require(script.Parent.Parent)
local ChestConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Chest"))

local Chest = {}

local GLOW = ChestConfig.glow

-- Where the effects start: above the chest's pivot (its base) in the opening.
function Chest.mouth(chest: Model): Vector3
	return chest:GetPivot().Position + Vector3.new(0, ChestConfig.sparkleLift, 0)
end

-- The lid opens: the burst of stars, `own` for the owner (always in full).
function Chest.open(chest: Model, own: boolean)
	Vfx.burst("chestOpen", Vfx.upAt(Chest.mouth(chest)), { own = own })
end

-- One glint rising out of the open chest.
function Chest.glint(chest: Model)
	Vfx.burst("chestGlint", Vfx.upAt(Chest.mouth(chest) - Vector3.new(0, 1, 0)))
end

-- The light inside, made once per chest (an Attachment with a PointLight on `part`, its brightness at 0).
function Chest.light(part: BasePart, chest: Model): PointLight
	local attachment = part:FindFirstChild("ChestGlow") :: Attachment?
	if not attachment then
		local made = Instance.new("Attachment")
		made.Name = "ChestGlow"
		made.WorldPosition = chest:GetPivot().Position + Vector3.new(0, GLOW.lift, 0)
		made.Parent = part
		attachment = made
	end
	local light = (attachment :: Attachment):FindFirstChildOfClass("PointLight")
	if not light then
		local made = Instance.new("PointLight")
		made.Color = Color3.fromHex(GLOW.color)
		made.Range = GLOW.range
		made.Brightness = 0
		made.Shadows = false
		made.Parent = attachment
		light = made
	end
	return light :: PointLight
end

-- The lid's curve for opening (open) or shutting (Config/Chest.lid); the light fades along with it.
function Chest.lidTween(open: boolean): TweenInfo
	local lid = ChestConfig.lid
	return TweenInfo.new(
		if open then lid.openTime else lid.closeTime,
		(Enum.EasingStyle :: any)[lid.style] or Enum.EasingStyle.Sine,
		(Enum.EasingDirection :: any)[lid.direction] or Enum.EasingDirection.InOut
	)
end

-- The light fades in (on) or out, as long and on the same curve as the lid.
function Chest.glow(light: PointLight, on: boolean)
	TweenService:Create(light, Chest.lidTween(on), {
		Brightness = if on then GLOW.brightness else 0,
	}):Play()
end

return Chest
