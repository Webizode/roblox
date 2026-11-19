--!strict
-- The action buttons on touch screens (client TouchControls, its Edit Controls mode in the settings, TouchLayout):
-- round buttons in the UI kit's look with an icon and a short word, in place of Roblox's grey touch buttons and its
-- jump button (phone test 17.11.2026). PC and console never see them.
--
-- Where a button sits by default: its centre `right` and `bottom` screen heights from the bottom right corner of the
-- safe area, `size` its diameter in screen heights. Measured in heights, so the cluster looks the same on a 19.5:9
-- phone and a 4:3 tablet. A player's own layout (Settings touchLayout) stores x and y as shares of the width and the
-- height and the size in heights instead; TouchLayout keeps it inside the screen and apart from the others.
-- `icon` names an icon of Config/Ui.icons (none: the word alone), `color` a colour token of Config/Ui.colors.

return {
	-- the order buttons are laid out and checked in (an earlier one keeps its place when a saved one overlaps it)
	order = { "jump", "throw", "dash", "sprint", "combat", "steady" },
	-- the free space kept between two buttons, in screen heights
	gap = 0.012,
	-- the size slider of Edit Controls, in screen heights
	minSize = 0.09,
	maxSize = 0.3,
	buttons = {
		jump = { label = "JUMP", right = 0.13, bottom = 0.16, size = 0.2, color = "sky" },
		throw = { label = "THROW", icon = "ammo", right = 0.36, bottom = 0.14, size = 0.17, color = "pink" },
		dash = { label = "DASH", icon = "sparkle", right = 0.12, bottom = 0.4, size = 0.13, color = "mint" },
		sprint = { label = "SPRINT", right = 0.3, bottom = 0.36, size = 0.12, color = "yellow" },
		combat = { label = "COMBAT", icon = "arena", right = 0.48, bottom = 0.32, size = 0.12, color = "red" },
		steady = { label = "STEADY", icon = "scoops", right = 0.55, bottom = 0.12, size = 0.12, color = "purple" },
	},
	-- the word under the icon, of the button's height; the icon above it
	labelHeight = 0.22,
	iconSize = 0.56,
}
