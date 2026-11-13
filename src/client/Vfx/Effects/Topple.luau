-- A tower topples (Config/Vfx.effects.topple, Config/Vfx.topple): a puff of cream where it stood, blobs in the colour
-- of its scoops and sprinkles, bigger the more scoops fly off. The scoops themselves fly apart as free scoops
-- (LootRenderer); the owner's camera shakes.

local Vfx = require(script.Parent.Parent)

local Topple = {}

local Config = Vfx.Config
local Look = Config.topple

-- `foot`: where the tower stood; `count` scoops of (mostly) `flavorId` came off; `own`: it was the local player's.
function Topple.play(foot: Vector3, flavorId: string?, count: number, own: boolean)
	local scale = math.clamp(1 + (count - 1) * Look.perScoop, 1, Look.maxScale)
	Vfx.burst("topple", Vfx.upAt(foot + Vector3.new(0, Look.lift, 0)), {
		color = Vfx.flavorColor(flavorId),
		scale = scale,
		own = own,
	})
	if own then
		local jolt = Config.camera.toppleOwner
		Vfx.Camera.shake(jolt.degrees, jolt.time)
	end
end

return Topple
