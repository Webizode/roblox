-- A lying scoop's last moment (Config/Vfx.lootBlink, effects blinkGlint and lootPuff), drawn by LootRenderer: it blinks
-- faster and faster and glints each time it lights up again, then pops in a puff of its colour with a few blobs and
-- sprinkles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vfx = require(script.Parent.Parent)
local VfxRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VfxRules"))

local LootFade = {}

local Config = Vfx.Config
local Look = Config.lootBlink

-- How see-through the scoop is `left` seconds before it goes, in its last `span` seconds, and the blink count so far
-- (LootFade.glint when it changes).
function LootFade.blink(left: number, span: number): (number, number)
	local count, dark = VfxRules.blink(left, span, Look)
	return if dark then Look.see else 0, count
end

-- The scoop lights up again: a small glint just above it. Only close by (the tiers leave it out further away).
function LootFade.glint(position: Vector3)
	local at = position + Vector3.new(0, Look.glintLift, 0)
	local camera = workspace.CurrentCamera
	local look = if camera then camera.CFrame.Position else at + Vector3.zAxis
	Vfx.burst("blinkGlint", CFrame.lookAt(at, look))
end

-- Its time is up: the puff where it lay.
function LootFade.puff(position: Vector3, flavorId: string?)
	Vfx.burst("lootPuff", Vfx.upAt(position), { color = Vfx.flavorColor(flavorId) })
end

return LootFade
