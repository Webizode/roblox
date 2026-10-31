--!strict
-- Pure maths for the dash, taken over from the DashSystem model: which way a dash goes relative to where the
-- character faces (for its animation and effect), and whether a surface ahead stops it. No Roblox globals;
-- TowerController and MovementController use it, tests/Dash.spec.luau covers it.

export type Kind = "forward" | "back" | "left" | "right"

local Dash = {}

-- The dash direction (dirX, dirZ) against the character's facing (lookX, lookZ), both flat. Forward and back win
-- over the sides when they are equal, like in the model.
function Dash.kind(dirX: number, dirZ: number, lookX: number, lookZ: number): Kind
	-- the character's right on the ground: the look vector turned a quarter clockwise seen from above
	local rightX, rightZ = -lookZ, lookX
	local forward = dirX * lookX + dirZ * lookZ
	local side = dirX * rightX + dirZ * rightZ
	if math.abs(forward) >= math.abs(side) then
		return if forward >= 0 then "forward" else "back"
	end
	return if side >= 0 then "right" else "left"
end

-- Whether a hit surface with this normal stops a dash going (dirX, dirZ): a wall (not a floor or a gentle slope)
-- that faces against the dash. Slopes and walls the dash only grazes let it go on.
function Dash.blocks(normalX: number, normalY: number, normalZ: number, dirX: number, dirZ: number): boolean
	if normalY >= 0.6 then
		return false
	end
	return normalX * dirX + normalZ * dirZ < -0.15
end

-- How fast a dash animation `length` seconds long has to play so it is over `recovery` seconds after a dash of
-- `duration` seconds ends: the move itself fits the burst, the last bit straightens the body up. 1 for an animation
-- whose length is not known yet (0) or a dash without time.
function Dash.animationSpeed(length: number, duration: number, recovery: number): number
	local total = duration + recovery
	if length <= 0 or total <= 0 then
		return 1
	end
	return length / total
end

return Dash
