-- The screen the kit lays out on: the safe area (notch, rounded corners, Roblox's top bar), the device (phone,
-- tablet, PC, TV, UiLayout.device) and the input in use (touch, keyboard, gamepad; Settings.inputKind). Screen.plan()
-- is the current UiLayout plan; Screen.onChanged calls back when the screen size, the device or the input changes.
-- Every kit ScreenGui comes from Screen.gui, so all of them stay inside the device's safe area; the plan keeps clear of
-- Roblox's top bar (GuiService.TopbarInset: only its free part is used).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiConfig = require(Shared:WaitForChild("Config"):WaitForChild("Ui"))
local UiLayout = require(Shared:WaitForChild("UiLayout"))
local client = script.Parent.Parent
local Settings = require(client:WaitForChild("Settings"))

local Screen = {}

local player = Players.LocalPlayer
local listeners: { (UiLayout.Plan) -> () } = {}
local current: UiLayout.Plan
local probe: ScreenGui
local input = "keyboard"
local lastKey = ""

-- A ScreenGui inside the safe area that keeps across respawns.
function Screen.gui(name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- the top bar is in it; UiLayout keeps to its free part
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

-- "touch", "keyboard" or "gamepad": what the player uses right now (the settings can fix it).
function Screen.input(): string
	return input
end

function Screen.plan(): UiLayout.Plan
	return current
end

function Screen.onChanged(listener: (UiLayout.Plan) -> ())
	table.insert(listeners, listener)
	listener(current)
end

-- A rectangle of the plan as position and size of a frame whose content is drawn in design pixels and scaled by a
-- UIScale (`scale`): the frame gets the design size, the UIScale makes it the planned size.
function Screen.place(frame: GuiObject, rect: UiLayout.Rect, scale: number)
	frame.AnchorPoint = Vector2.zero
	frame.Position = UDim2.fromOffset(math.round(rect.x), math.round(rect.y))
	frame.Size = UDim2.fromOffset(rect.w / scale, rect.h / scale)
	local uiScale = frame:FindFirstChild("Layout") :: UIScale?
	if not uiScale then
		local created = Instance.new("UIScale")
		created.Name = "Layout"
		created.Parent = frame
		uiScale = created
	end
	(uiScale :: UIScale).Scale = scale
end

-- Studio only: the Workspace attribute ScreenPreview (a Vector2 in GUI pixels, e.g. 936 x 432 for a 2576 x 1188 phone)
-- lays the whole kit out as on such a touch screen, in the top left corner of the real one, with a phone's top bar.
-- Studio's device emulator cannot be switched through the MCP (17.11.2026).
local function preview(): Vector2?
	if not RunService:IsStudio() then
		return nil
	end
	local size = workspace:GetAttribute("ScreenPreview")
	return if typeof(size) == "Vector2" and size.X > 100 and size.Y > 100 then size else nil
end

-- The size the kit lays out on (the safe area, or the Studio preview).
function Screen.size(): Vector2
	return preview() or probe.AbsoluteSize
end

local function update()
	local previewSize = preview()
	local size = previewSize or probe.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	input = if previewSize then "touch" else Settings.inputKind()
	-- the free part of Roblox's top bar, from screen pixels into the ScreenGui's (its origin sits at its
	-- AbsolutePosition plus the inset Roblox reserves at the top)
	local origin = probe.AbsolutePosition + GuiService:GetGuiInset()
	local bar = GuiService.TopbarInset
	local topbar = {
		left = math.max(0, bar.Min.X - origin.X),
		right = math.min(size.X, bar.Max.X - origin.X),
		height = math.max(0, bar.Max.Y - origin.Y),
	}
	if topbar.right <= topbar.left then
		topbar = { left = 0, right = size.X, height = 0 }
	end
	if previewSize then
		-- a phone's top bar, about: Roblox's menu, chat and voice buttons on the left, 44 pixels high
		topbar = { left = 150, right = size.X, height = 44 }
	end
	local device = UiLayout.device(size.X, size.Y, input, GuiService:IsTenFootInterface(), UiConfig)
	local plan = UiLayout.plan(size.X, size.Y, device, UiConfig, topbar)
	local key = string.format(
		"%s %s %.4f %d %d %d %d %d",
		plan.device,
		input,
		plan.scale,
		size.X,
		size.Y,
		topbar.left,
		topbar.right,
		topbar.height
	)
	current = plan;
	(plan :: any).input = input
	if key == lastKey then
		return
	end
	lastKey = key
	for _, listener in listeners do
		task.spawn(listener, plan)
	end
end

probe = Screen.gui("UiProbe", 0)
local size0 = probe.AbsoluteSize
current = UiLayout.plan(
	math.max(size0.X, 1280),
	math.max(size0.Y, 720),
	if UserInputService.TouchEnabled then "phone" else "pc",
	UiConfig
);
(current :: any).input = Settings.inputKind()
probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(update)
Settings.onChanged(update)
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("ScreenPreview"):Connect(update)
end
task.defer(update)

return Screen
