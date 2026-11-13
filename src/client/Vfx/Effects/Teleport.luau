-- A teleport went through (Config/Vfx.effects.teleport, groundRings.teleport): a pastel puff with stars and sprinkles
-- where the player was and where they arrive, and a ring over the ground at both. Everybody sees it (Remotes.Teleported).

local Vfx = require(script.Parent.Parent)

local Teleport = {}

-- `from`, `to`: the character's root before and after; `own`: the local player.
function Teleport.play(from: Vector3, to: Vector3, own: boolean)
	for _, root in { from, to } do
		local feet = root - Vector3.new(0, 3, 0) -- an R15 root is about 3 studs above the feet
		Vfx.burst("teleport", Vfx.upAt(feet + Vector3.new(0, 1, 0)), { own = own })
		Vfx.groundRings("teleport", feet, nil, own)
	end
end

return Teleport
