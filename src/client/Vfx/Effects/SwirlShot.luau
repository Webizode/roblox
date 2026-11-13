-- The Big Swirl's scoops (Config/Vfx.effects swirlShot, landed; groundRings circle, landed), drawn by ShotRenderer:
--   fire     a scoop leaves its arm's cup: a puff of steam and sparks in its colour along its way
--   circle   its landing circle shows itself: a ring in its colour runs out of it
--   landed   nobody caught it and it comes down on the circle: a soft puff and a small ring

local Vfx = require(script.Parent.Parent)

local SwirlShot = {}

-- `position`: the cup it leaves; `toward`: where it is going (its landing point).
function SwirlShot.fire(position: Vector3, toward: Vector3, flavorId: string?)
	local flat = Vector3.new(toward.X - position.X, 0, toward.Z - position.Z)
	local way = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	-- out of the cup: forwards and up, as the scoop flies
	local direction = (way + Vector3.new(0, 1.2, 0)).Unit
	Vfx.burst("swirlShot", CFrame.lookAt(position, position + direction), { color = Vfx.flavorColor(flavorId) })
end

-- `centre`: the landing circle's middle on the ground.
function SwirlShot.circle(centre: Vector3, flavorId: string?)
	Vfx.groundRings("circle", centre, Vfx.flavorColor(flavorId))
end

function SwirlShot.landed(centre: Vector3, flavorId: string?)
	local color = Vfx.flavorColor(flavorId)
	Vfx.burst("landed", Vfx.upAt(centre + Vector3.new(0, 0.3, 0)), { color = color })
	Vfx.groundRings("landed", centre, color)
end

return SwirlShot
