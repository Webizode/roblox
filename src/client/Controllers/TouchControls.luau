-- The action buttons on touch screens, in the UI kit's look (phone test 17.11.2026: Roblox's grey touch buttons, Sprint
-- cut off at the bottom): round candy buttons with an icon and a short word for Jump, Throw, Dash, Sprint, Combat and
-- Steady (Config/TouchControls). Roblox's own jump button is hidden, Jump here makes the character jump. Only on touch
-- screens; PC and console never see them and keep their keys.
--
-- The controllers that own an action give it its handler (TouchControls.bind; the same function their keys call,
-- with Begin and End) and say when it shows (TouchControls.setShown: Throw only in combat mode).
--
-- Where the buttons sit: TouchLayout from the defaults and the player's own layout (Settings touchLayout), always on
-- the screen, under Roblox's top bar and apart from each other. The same layout also places three displays of the HUD
-- (since 20.11.2026: the dash bar, the ice balls, the balance gauge; Config/TouchControls panels): Hud asks
-- TouchControls.panel where they go. Edit Controls (TouchControls.edit, from the settings) lets a finger move each
-- button and display (the displays show as named boxes then) and a slider size the picked one; nothing can leave the
-- screen, cover another element, the HUD's fixed buttons or the move stick's zone. Save stores only what was moved
-- and says whether the server really stored it, Reset puts everything back to its default, Cancel throws the changes
-- away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TouchConfig = require(Shared:WaitForChild("Config"):WaitForChild("TouchControls"))
local TouchLayout = require(Shared:WaitForChild("TouchLayout"))

local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local Settings = require(client:WaitForChild("Settings"))
local Theme, Screen, Buttons, Anim = UiKit.Theme, UiKit.Screen, UiKit.Buttons, UiKit.Anim

local TouchControls = {}

type Handler = (state: Enum.UserInputState, input: InputObject) -> ()
type Button = {
	id: string,
	button: TextButton,
	stroke: UIStroke,
	handler: Handler?,
	shown: boolean,
	input: InputObject?, -- the finger holding it
}
type Proxy = { button: TextButton, stroke: UIStroke } -- a display's stand-in while editing

local PANELS = TouchConfig.panels

local player = Players.LocalPlayer
local gui: ScreenGui
local editorGui: ScreenGui
local buttons: { [string]: Button } = {}
local proxies: { [string]: Proxy } = {}
local spots: TouchLayout.Layout = {}
local jumpHeld = false
local jumpQueued = false -- a tap shorter than a frame still jumps once
local layoutListeners: { () -> () } = {}

-- Edit Controls
local editing = false
local working: TouchLayout.Layout = {}
local moved: { [string]: boolean } = {} -- what Save stores (moved or sized now, or already saved before)
local selected: string? = nil
local drag: { id: string, input: InputObject, from: Vector3, start: any }? = nil
local sliderInput: InputObject? = nil
local releaseHud: (() -> ())? = nil -- the rest of the HUD is out of the way while editing
local knob: Frame
local track: Frame
local sizeLabel: TextLabel
local editorPanel: Frame? = nil
local EDITOR_SHARE = 0.56 -- the Edit Controls panel takes at most this share of the width, top left

local function touchScreen(): boolean
	return Screen.input() == "touch"
end

-- The screen in GUI pixels and the top bar's height (nothing reaches up there).
local function screen(): (number, number, number)
	local size = Screen.size()
	local plan = Screen.plan()
	local top = if plan and plan.topbar then plan.topbar.height else 0
	return size.X, size.Y, top
end

-- The displays' default rectangles from the HUD's plan (the gauge at its combat-mode place: in Edit Controls the ice
-- balls show too), and what a moved element must keep clear of: the HUD's fixed buttons and the move stick's zone.
local function planned(): (TouchLayout.Panels?, { TouchLayout.Rect })
	local plan = Screen.plan()
	if not plan or not plan.dash then
		return nil, {}
	end
	local blocked = { plan.top, plan.quick, plan.column, plan.settings, plan.coins, plan.bottom }
	if plan.touch and plan.zones and plan.zones[1] then
		table.insert(blocked, plan.zones[1]) -- the move stick
	end
	if editing and editorPanel then
		-- in the ScreenGuis' own pixels (what Position uses), not the screen's: their origin sits under the top bar inset
		local at, size = editorPanel.AbsolutePosition - editorGui.AbsolutePosition, editorPanel.AbsoluteSize
		table.insert(blocked, { x = at.X, y = at.Y, w = size.X, h = size.Y })
	end
	return { dashBar = plan.dash, ammo = plan.ammo, balance = plan.balance }, blocked
end

local function resolved(saved: TouchLayout.Layout?): TouchLayout.Layout
	local width, height, top = screen()
	local panels, blocked = planned()
	return TouchLayout.resolve(saved, width, height, top, TouchConfig, panels, blocked)
end

local function place(entry: Button, spot: TouchLayout.Spot)
	local width, height = screen()
	local diameter = spot.size * height
	entry.button.Position = UDim2.fromOffset(math.round(spot.x * width), math.round(spot.y * height))
	entry.button.Size = UDim2.fromOffset(math.round(diameter), math.round(diameter))
end

local function layout()
	local width, height = screen()
	if width <= 0 or height <= 0 then
		return
	end
	if editing then
		spots = working
	else
		spots = resolved(Settings.get().touchLayout)
	end
	for id, entry in buttons do
		local spot = spots[id]
		if spot then
			place(entry, spot)
		end
	end
	local panels = planned()
	for id, proxy in proxies do
		local spot = spots[id]
		local default = panels and panels[id]
		if spot and default then
			local rect = TouchLayout.panelRect(spot, default, width, height)
			proxy.button.Position = UDim2.fromOffset(math.round(rect.x), math.round(rect.y))
			proxy.button.Size = UDim2.fromOffset(math.round(rect.w), math.round(rect.h))
		end
	end
	for _, listener in layoutListeners do
		task.spawn(listener)
	end
end

local function refresh()
	gui.Enabled = touchScreen()
	editorGui.Enabled = editing and touchScreen()
	for id, entry in buttons do
		entry.button.Visible = editing or (entry.shown and (entry.handler ~= nil or id == "jump"))
		local picked = editing and id == selected
		entry.stroke.Color = if picked then Theme.color("select") else Theme.color("outline")
		entry.stroke.Thickness = if picked then 5 else 3
	end
	for id, proxy in proxies do
		proxy.button.Visible = editing
		local picked = editing and id == selected
		proxy.stroke.Color = if picked then Theme.color("select") else Theme.color("outline")
		proxy.stroke.Thickness = if picked then 5 else 3
	end
end

-- ================================================================================================ the buttons ===

local function release(entry: Button, input: InputObject)
	if entry.input ~= input then
		return
	end
	entry.input = nil
	if entry.handler and not editing then
		entry.handler(Enum.UserInputState.End, input)
	end
end

local function startDrag(id: string, input: InputObject)
	selected = id
	drag = { id = id, input = input, from = input.Position, start = working[id] }
	refresh()
	TouchControls.updateSlider()
end

local function pointer(input: InputObject): boolean
	local kind = input.UserInputType
	return kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1
end

local function makeButton(id: string)
	local spec = TouchConfig.buttons[id]
	local color = Theme.color(spec.color)
	local button = Instance.new("TextButton")
	button.Name = id
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = color
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.ZIndex = 2
	button.Selectable = false
	Theme.corner(button, UDim.new(0.5, 0))
	Theme.shade(button, color)
	local stroke = Theme.outline(button, 3)
	-- the gloss on top
	local gloss = Theme.frame({
		Name = "Gloss",
		BackgroundTransparency = 0.72,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.fromScale(0.62, 0.26),
		ZIndex = 3,
		Parent = button,
	})
	Theme.corner(gloss, UDim.new(0.5, 0))
	local icon = spec.icon and Theme.icons[spec.icon]
	if icon then
		Theme.icon(icon, {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromScale(TouchConfig.iconSize, TouchConfig.iconSize),
			ZIndex = 4,
			Parent = button,
		})
	end
	-- the word scaled into its box, never over the button's edge
	Theme.text({
		Name = "Label",
		Text = spec.label,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if icon then 0.76 else 0.5),
		Size = UDim2.fromScale(0.78, if icon then TouchConfig.labelHeight else 0.3),
		TextScaled = true,
		ZIndex = 5,
		Parent = button,
	})
	Anim.button(button)

	local entry: Button = { id = id, button = button, stroke = stroke, shown = true }
	button.InputBegan:Connect(function(input)
		if not pointer(input) then
			return
		end
		if editing then
			startDrag(id, input)
			return
		end
		if entry.input then
			return
		end
		entry.input = input
		if entry.handler then
			entry.handler(Enum.UserInputState.Begin, input)
		end
	end)
	button.InputEnded:Connect(function(input)
		release(entry, input)
	end)
	button.Parent = gui
	buttons[id] = entry
end

-- A display's stand-in in Edit Controls: a box of the display's size with its name, moved and sized like a button.
local function makeProxy(id: string)
	local color = Theme.color(PANELS.colors[id])
	local box = Instance.new("TextButton")
	box.Name = "Panel_" .. id
	box.Text = ""
	box.AutoButtonColor = false
	box.BackgroundColor3 = color
	box.BackgroundTransparency = 0.2
	box.ZIndex = 2
	box.Selectable = false
	box.Visible = false
	Theme.corner(box, UDim.new(0, 12))
	local stroke = Theme.outline(box, 3)
	Theme.text({
		Name = "Label",
		Text = PANELS.labels[id],
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.6),
		TextScaled = true,
		ZIndex = 3,
		Parent = box,
	})
	box.InputBegan:Connect(function(input)
		if editing and pointer(input) then
			startDrag(id, input)
		end
	end)
	box.Parent = gui
	proxies[id] = { button = box, stroke = stroke }
end

-- Jump: held, the character keeps jumping like with Roblox's own button. The jump is asked for right before the
-- physics step (PreSimulation): Roblox's controls write Humanoid.Jump every frame before it, so a jump set anywhere
-- else can be overwritten before the physics sees it. Not while knocked down.
local function jump(state: Enum.UserInputState)
	jumpHeld = state == Enum.UserInputState.Begin
	if jumpHeld then
		jumpQueued = true
	end
end

local function knockedDown(): boolean
	local downUntil = player:GetAttribute("DownUntil")
	return type(downUntil) == "number" and workspace:GetServerTimeNow() < downUntil
end

-- Roblox's jump button stays hidden while ours are up (it comes back with every new TouchGui).
local function hideRobloxJump(button: Instance)
	if button.Name ~= "JumpButton" or not button:IsA("GuiObject") then
		return
	end
	local function hide()
		if touchScreen() and button.Visible then
			button.Visible = false
		end
	end
	button:GetPropertyChangedSignal("Visible"):Connect(hide)
	hide()
end

-- ============================================================================================== Edit Controls ===

local function copy(from: TouchLayout.Layout): TouchLayout.Layout
	local made: TouchLayout.Layout = {}
	for id, spot in from do
		made[id] = table.clone(spot)
	end
	return made
end

-- Moves the dragged element where the finger is, as far as it stays on the screen and clear of the others, the
-- HUD's buttons and the move stick (sliding along something in the way rather than stopping).
local function onDrag(position: Vector3)
	local current = drag
	if not current then
		return
	end
	local width, height, top = screen()
	local panels, blocked = planned()
	local delta = position - current.from
	local start = current.start
	local function try(dx: number, dy: number): boolean
		local candidate = table.clone(working[current.id])
		candidate.x, candidate.y = start.x + dx / width, start.y + dy / height
		local spot = TouchLayout.inside(candidate, width, height, top, current.id, TouchConfig, panels)
		if TouchLayout.free(working, current.id, spot, width, height, TouchConfig, panels, blocked) then
			working[current.id] = spot
			moved[current.id] = true
			return true
		end
		return false
	end
	if not try(delta.X, delta.Y) then
		local _ = try(delta.X, 0) or try(0, delta.Y)
	end
	layout()
end

-- The slider's range for the picked element: a button's diameter or a display's scale.
local function range(id: string): (number, number, string)
	if TouchLayout.isPanel(id, TouchConfig) then
		return PANELS.minScale, PANELS.maxScale, "scale"
	end
	return TouchConfig.minSize, TouchConfig.maxSize, "size"
end

-- The slider sizes the picked element; a size that would leave the screen or touch something is not taken.
local function onSlide(input: InputObject)
	local id = selected
	if not id then
		return
	end
	local share = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
	local min, max, field = range(id)
	local width, height, top = screen()
	local panels, blocked = planned()
	local candidate = table.clone(working[id])
	candidate[field] = min + share * (max - min)
	local spot = TouchLayout.inside(candidate, width, height, top, id, TouchConfig, panels)
	if TouchLayout.free(working, id, spot, width, height, TouchConfig, panels, blocked) then
		working[id] = spot
		moved[id] = true
		layout()
	end
	TouchControls.updateSlider()
end

local function labelOf(id: string): string
	local button = TouchConfig.buttons[id]
	return if button then button.label else PANELS.labels[id]
end

function TouchControls.updateSlider()
	if not knob then
		return
	end
	local id = selected
	local spot = id and working[id]
	local share = 0
	if id and spot then
		local min, max, field = range(id)
		share = (spot[field] - min) / (max - min)
	end
	knob.Position = UDim2.fromScale(math.clamp(share, 0, 1), 0.5)
	sizeLabel.Text = if id then `SIZE: {labelOf(id)}` else "SIZE"
end

local function stopEditing()
	editing = false
	if releaseHud then
		releaseHud()
		releaseHud = nil
	end
	drag, sliderInput = nil, nil
	refresh()
	layout()
end

local function buildEditor()
	editorGui = Screen.gui("TouchEditor", 25) -- over the whole HUD
	editorGui.Enabled = false
	-- top left, at most EDITOR_SHARE of the width: the displays and buttons sit on the right, and nothing may be dragged
	-- under it (planned: it is in the way while editing)
	local panel = Theme.frame({
		Name = "Panel",
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Theme.color("chocolate"),
		AnchorPoint = Vector2.new(0, 0),
		Size = UDim2.fromOffset(640, 196),
		Active = true,
		Parent = editorGui,
	})
	editorPanel = panel
	Theme.corner(panel, UDim.new(0, 22))
	Theme.outline(panel, 3, Theme.color("rim"))
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	Screen.onChanged(function(plan)
		local width = Screen.size().X
		scale.Scale = math.min(plan.scale, (width * EDITOR_SHARE - plan.frame.x) / 640)
		panel.Position = UDim2.fromOffset(math.round(plan.frame.x), math.round(plan.frame.y))
	end)

	Theme.text({
		Name = "Title",
		Text = "EDIT CONTROLS",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(1, -40, 0, 34),
		TextScaled = true,
		Parent = panel,
	})
	local hint = Theme.text({
		Name = "Hint",
		Text = "Drag a button or display to move it. Tap one, then use the slider to resize it.",
		FontFace = Theme.fontText,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 46),
		Size = UDim2.new(1, -40, 0, 22),
		TextScaled = true,
		Parent = panel,
	})
	hint.TextColor3 = Theme.color("hint")

	-- the size slider
	sizeLabel = Theme.text({
		Name = "SizeLabel",
		Text = "SIZE",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(24, 96),
		Size = UDim2.fromOffset(190, 26),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	track = Theme.frame({
		Name = "Track",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("creamDark"),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(236, 96),
		Size = UDim2.new(1, -276, 0, 12),
		Active = true,
		Parent = panel,
	})
	Theme.corner(track, UDim.new(0.5, 0))
	knob = Theme.frame({
		Name = "Knob",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("yellow"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		ZIndex = 2,
		Parent = track,
	})
	Theme.corner(knob, UDim.new(0.5, 0))
	Theme.outline(knob, 3)
	-- a wide invisible strip over the track takes the finger (the track itself is thin)
	local grab = Instance.new("TextButton")
	grab.Name = "Grab"
	grab.Text = ""
	grab.BackgroundTransparency = 1
	grab.AnchorPoint = Vector2.new(0, 0.5)
	grab.Position = UDim2.new(0, -20, 0.5, 0)
	grab.Size = UDim2.new(1, 40, 0, 48)
	grab.ZIndex = 3
	grab.Selectable = false
	grab.Parent = track
	grab.InputBegan:Connect(function(input)
		if pointer(input) then
			sliderInput = input
			onSlide(input)
		end
	end)

	-- Save, Reset, Cancel
	local row = Theme.frame({
		Name = "Buttons",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, 54),
		Parent = panel,
	})
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 14)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	local function wide(name: string, text: string, color: Color3, order: number, callback: () -> ())
		local made = Buttons.wide({ name = name, text = text, color = color, width = 190, height = 52 })
		made.button.LayoutOrder = order
		made.button.Parent = row
		made.button.Activated:Connect(callback)
	end
	wide("Save", "SAVE", Theme.color("mint"), 1, function()
		-- only what was moved is stored (the rest keeps following the defaults); the toast waits for the server
		local stored = TouchLayout.toSave(working, moved)
		stopEditing()
		Settings.saveNow("touchLayout", stored, function(ok)
			if ok then
				UiKit.Toast.show("CONTROLS SAVED", "good")
			else
				UiKit.Toast.show("NOT SAVED - TRY AGAIN", "bad")
			end
		end)
	end)
	wide("Reset", "RESET", Theme.color("yellow"), 2, function()
		-- everything back to its default; Save stores that (an empty layout)
		working = copy(resolved(nil))
		table.clear(moved)
		layout()
		TouchControls.updateSlider()
	end)
	wide("Cancel", "CANCEL", Theme.color("red"), 3, stopEditing)
end

-- Opens Edit Controls (from the settings). Only on touch screens.
function TouchControls.edit()
	if editing or not touchScreen() then
		return
	end
	local saved = Settings.get().touchLayout
	working = copy(resolved(saved))
	table.clear(moved)
	for id in saved do
		moved[id] = true
	end
	editing = true
	selected = TouchConfig.order[1]
	releaseHud = UiKit.HudAway.push({ "TouchControls" })
	refresh()
	layout()
	TouchControls.updateSlider()
end

function TouchControls.isEditing(): boolean
	return editing
end

-- ================================================================================================= the API ===

-- `handler(state, input)` runs when the button of action `id` is pressed (Begin) and let go (End).
function TouchControls.bind(id: string, handler: Handler)
	local entry = buttons[id]
	if entry then
		entry.handler = handler
		refresh()
	end
end

-- Whether the button of action `id` shows (e.g. Throw only in combat mode).
function TouchControls.setShown(id: string, shown: boolean)
	local entry = buttons[id]
	if entry and entry.shown ~= shown then
		entry.shown = shown
		if not shown and entry.input then
			release(entry, entry.input) -- a hidden button lets go
		end
		refresh()
	end
end

-- Where a display goes on this touch screen (Hud): its rectangle in the ScreenGui's pixels, its scale against the
-- plan's size, and whether the player moved it. nil: not a touch screen or not laid out yet (the plan's place holds).
function TouchControls.panel(id: string): (TouchLayout.Rect?, number, boolean)
	if not touchScreen() or editing then
		return nil, 1, false
	end
	local spot = spots[id]
	local panels = planned()
	local default = panels and panels[id]
	if not spot or not default then
		return nil, 1, false
	end
	local width, height = screen()
	return TouchLayout.panelRect(spot, default, width, height), spot.scale, Settings.get().touchLayout[id] ~= nil
end

-- Calls `listener()` after every new layout (a new screen, a saved or loaded layout, Edit Controls closing).
function TouchControls.onLayout(listener: () -> ())
	table.insert(layoutListeners, listener)
end

function TouchControls.Init()
	gui = Screen.gui("TouchControls", 6)
	buildEditor()
	for _, id in TouchConfig.order do
		makeButton(id)
	end
	for _, id in PANELS.order do
		makeProxy(id)
	end
	buttons.throw.shown = false -- only in combat mode
	TouchControls.bind("jump", function(state)
		jump(state)
	end)
end

function TouchControls.Start()
	Screen.onChanged(function()
		refresh()
		layout()
	end)
	Settings.onChanged(function()
		if not editing then
			layout()
		end
	end)
	-- a finger that slides off a button and lifts elsewhere still lets go of it; the editor's drag and slider follow it
	UserInputService.InputEnded:Connect(function(input)
		for _, entry in buttons do
			release(entry, input)
		end
		if drag and drag.input == input then
			drag = nil
		end
		if sliderInput == input then
			sliderInput = nil
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not editing then
			return
		end
		if sliderInput and (input == sliderInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
			onSlide(input)
		elseif drag then
			-- a finger moves its own input; a mouse (Studio) moves the mouse while its button input stays put
			local mouse = drag.input.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			if drag.input == input or mouse then
				onDrag(input.Position)
			end
		end
	end)
	RunService.PreSimulation:Connect(function()
		local wanted = jumpHeld or jumpQueued
		jumpQueued = false
		if not wanted or editing or knockedDown() then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Jump = true
		end
	end)
	-- Studio only: the Workspace attribute StudioEditControls opens Edit Controls, false cancels it (playtests through
	-- the MCP, whose clicks do not reach the device emulator)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("StudioEditControls"):Connect(function()
			if workspace:GetAttribute("StudioEditControls") then
				TouchControls.edit()
			elseif editing then
				stopEditing() -- like Cancel
			end
		end)
	end
	local playerGui = player:WaitForChild("PlayerGui")
	playerGui.DescendantAdded:Connect(hideRobloxJump)
	for _, descendant in playerGui:GetDescendants() do
		hideRobloxJump(descendant)
	end
end

return TouchControls
