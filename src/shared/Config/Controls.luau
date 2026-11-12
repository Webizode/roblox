--!strict
-- Every action's keys, in one place: the bindings (ContextActionService) and the key badges in the HUD read them from
-- here (client Keys), so a badge always shows the key that really does it. Names of Enum.KeyCode items (or
-- Enum.UserInputType for mouse buttons); `keys` for keyboard and mouse, `pad` for a gamepad. The first of each is the
-- one a badge shows. Touch screens use Roblox's touch buttons and show no badges.

export type Binding = { keys: { string }?, pad: { string }? }

local Controls: { [string]: Binding } = {
	-- combat
	throw = { keys = { "MouseButton1" }, pad = { "ButtonR2" } },
	combat = { keys = { "R" }, pad = { "ButtonY" } },
	-- movement and the tower
	dash = { keys = { "Q" }, pad = { "ButtonX" } },
	sprint = { keys = { "LeftShift", "RightShift" }, pad = { "ButtonL3" } },
	steady = { keys = { "F" } },
	-- the navigation: the left column, MY PLOT and ARENA
	upgrades = { keys = { "One" } },
	cosmetics = { keys = { "Two" } },
	quests = { keys = { "Three" } },
	index = { keys = { "Four" } },
	scoops = { keys = { "Five" } },
	plot = { keys = { "H" } },
	arena = { keys = { "T" } },
	-- gamepad only: into the navigation column, the settings, back out of a window or the navigation
	navigation = { pad = { "DPadLeft" } },
	settings = { pad = { "DPadUp" } },
	back = { pad = { "ButtonB" } },
}

return Controls
