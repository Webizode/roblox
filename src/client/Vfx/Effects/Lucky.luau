-- Luck turned a caught scoop rarer (Config/Vfx.effects.lucky): a flash on the scoop and stars and a ring in the new
-- rarity's colour. Only the catcher sees it (ChestController).

local Vfx = require(script.Parent.Parent)

local Lucky = {}

-- `scoop`: where the scoop sits on the tower; `color`: the new rarity's colour.
function Lucky.play(scoop: Vector3, color: Color3)
	Vfx.burst("lucky", Vfx.upAt(scoop), { color = color, own = true })
end

return Lucky
