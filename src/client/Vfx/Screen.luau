-- The effects' own layer on the screen (the coins flying to the coin counter, the dash's speed lines): one full-screen
-- ScreenGui over the HUD that keeps across respawns, and the conversion of world points and HUD elements into it.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Screen = {}

local gui: ScreenGui? = nil

function Screen.gui(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("ScreenGui")
	made.Name = "VfxScreen"
	made.ResetOnSpawn = false
	made.IgnoreGuiInset = true
	made.ScreenInsets = Enum.ScreenInsets.None
	made.DisplayOrder = 6 -- over the HUD (5), under menus
	made.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	made.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = made
	return made
end

-- A point of the GUI space (where every AbsolutePosition is measured, below the top bar) in this layer.
function Screen.fromAbsolute(point: Vector2): Vector2
	return point - Screen.gui().AbsolutePosition
end

-- Where a world point shows in this layer, and whether it is in front of the camera.
function Screen.fromWorld(position: Vector3): (Vector2, boolean)
	local camera = workspace.CurrentCamera
	local point, visible = camera:WorldToViewportPoint(position)
	local inset = GuiService:GetGuiInset()
	return Screen.fromAbsolute(Vector2.new(point.X, point.Y) - inset), visible and point.Z > 0
end

-- The middle of a GUI element in this layer.
function Screen.centreOf(element: GuiObject): Vector2
	return Screen.fromAbsolute(element.AbsolutePosition + element.AbsoluteSize / 2)
end

-- The screen's height in pixels, for sizes given as shares of it.
function Screen.height(): number
	return Screen.gui().AbsoluteSize.Y
end

return Screen
