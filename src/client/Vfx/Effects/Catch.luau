-- A scoop from the Big Swirl is caught (Config/Vfx.effects.catch, groundRings.catch): small stars in its colour pop where it
-- lands on the tower, and a ring in its colour runs out over the ground from its landing circle.

local Vfx = require(script.Parent.Parent)

local Catch = {}

-- `scoop`: where the caught scoop is; `landing`: the middle of its landing circle on the ground.
function Catch.play(scoop: Vector3, landing: Vector3, flavorId: string?, own: boolean)
	local color = Vfx.flavorColor(flavorId)
	Vfx.burst("catch", Vfx.upAt(scoop), { color = color, own = own })
	Vfx.groundRings("catch", landing, color, own)
end

return Catch
