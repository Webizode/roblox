-- A free scoop is picked up from the ground (Config/Vfx.effects.pickup): a small pop where it lay, drops of its
-- colour hop up and a small ring runs out.

local Vfx = require(script.Parent.Parent)

local Pickup = {}

-- `position`: where the scoop lay (its centre); `ground`: the height of the ground under it.
function Pickup.play(position: Vector3, ground: number, flavorId: string?, own: boolean)
	local color = Vfx.flavorColor(flavorId)
	Vfx.burst("pickup", Vfx.upAt(position), { color = color, own = own })
	Vfx.groundRings("pickup", Vector3.new(position.X, ground, position.Z), color, own)
end

return Pickup
