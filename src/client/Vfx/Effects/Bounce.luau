-- A gummy pad throws a player up (Config/Vfx.effects.bounce, Config/Bounce): a soft puff and gummy drops over its top,
-- and a pink ring runs out on the floor around it.

local Vfx = require(script.Parent.Parent)

local Bounce = {}

-- `top`: the middle of the pad's top; `floor`: the height of the floor it stands on.
function Bounce.play(top: Vector3, floor: number, own: boolean)
	Vfx.burst("bounce", Vfx.upAt(top), { own = own })
	Vfx.groundRings("bounce", Vector3.new(top.X, floor, top.Z), nil, own)
end

return Bounce
