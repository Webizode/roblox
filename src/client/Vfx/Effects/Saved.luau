-- "SAVED!" (Config/Vfx.effects saved, savedSmall): the local player comes out of the arena into the safe zone with a
-- groaning tower: mint rings spread over the ground and stars rise along the tower. When the tower catches itself
-- while still in the arena it is the smaller one. The tilt is simulated on the owner's client only, so only the
-- owner sees it.

local Vfx = require(script.Parent.Parent)

local Saved = {}

-- `character`: whose tower was saved; `safeZone`: by reaching the safe zone (the big one).
function Saved.play(character: Model, safeZone: boolean)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local name = if safeZone then "saved" else "savedSmall"
	Vfx.burst(name, Vfx.upAt(feet), { own = true })
	Vfx.groundRings(name, feet, nil, true)
end

return Saved
