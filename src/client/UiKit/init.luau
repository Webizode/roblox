-- The UI kit everything on screen is built from (Shops, Index, Upgrades and Crafting will build on it too):
--   Theme    colours, font, outline, corners, gloss, shadow (Config/Ui), rarity colours (Config/Flavors)
--   Screen   safe area, device, input in use, the HUD layout plan (UiLayout)
--   Anim     press, hover, pop
--   Buttons  icon button, wide button (normal, pressed, locked), close button, key badge
--   Window   window with title bar, glaze rim and close button; popup; tabs
--   Widgets  coin counter, progress bar, item card (six rarities, silhouette), reward message, safe-zone sign
--   Toast    the short messages (Toast.show(text, kind, icon)), all in one look
-- The test page with every piece: Controllers/UiKitGallery (Studio only).

local UiKit = {
	Theme = require(script:WaitForChild("Theme")),
	Screen = require(script:WaitForChild("Screen")),
	Anim = require(script:WaitForChild("Anim")),
	Buttons = require(script:WaitForChild("Buttons")),
	Window = require(script:WaitForChild("Window")),
	Widgets = require(script:WaitForChild("Widgets")),
	Toast = require(script:WaitForChild("Toast")),
}

return UiKit
