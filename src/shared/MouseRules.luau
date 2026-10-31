--!strict
-- Combat mode and the mouse, by where the player stands (ArenaZone). Pure: the client (CombatController) and the server
-- (CombatService) ask these, and the Lune tests pin them down.
--
-- Combat mode only exists in the arena: R switches it on there; leaving the arena ends it, and outside R does nothing
-- but say so. In combat mode the mouse is locked in the middle of the screen and the cursor hidden, the crosshair is
-- the cursor, whatever else happens (a held right mouse button included). Outside combat mode the mouse is free, so
-- the teleport buttons outside the arena can be clicked.

export type Mouse = "locked" | "free"

local MouseRules = {}

-- Whether combat mode may be switched on here.
function MouseRules.canEnterCombat(inArena: boolean): boolean
	return inArena
end

-- Whether combat mode has to end now: it is on, and the player is out of the arena.
function MouseRules.mustLeaveCombat(combatMode: boolean, inArena: boolean): boolean
	return combatMode and not inArena
end

-- What the mouse does: locked with the cursor hidden in combat mode in the arena, free everywhere else. A held right
-- mouse button changes nothing (`_rightButton` is there so the tests can say so); without a mouse it stays free.
function MouseRules.mode(combatMode: boolean, inArena: boolean, mouseEnabled: boolean, _rightButton: boolean): Mouse
	if combatMode and inArena and mouseEnabled then
		return "locked"
	end
	return "free"
end

return MouseRules
