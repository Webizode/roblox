-- The navigation (UiKit): MY PLOT and ARENA big at the top with the SAFE ZONE sign under them, and the icon buttons on
-- the left: Upgrades, Cosmetics and Quests teleport to their shop, Index and Scoops open a "Coming soon" window. Where
-- it all sits on each screen comes from UiLayout (Screen.plan).
--
-- All of it shows everywhere while combat mode is off. In combat mode only a small MY PLOT button stays (top centre),
-- for a free view of the fight. The SAFE ZONE sign shows outside the arena only: the client asks ArenaZone with the
-- character's position, the same function the server uses, and changes it once the answer has held for
-- Config/Map.arena.displayDelay, so nothing flickers on the line. The teleport buttons only name the target; the
-- server decides (TeleportRules: not knocked down, not right after a hit, in the arena not with scoops on the back)
-- and says why when it stops one (a toast).
--
-- PC: shortcuts 1-5 for the column, H and T for MY PLOT and ARENA (Config/Controls), shown as badges. Gamepad: D-pad
-- left jumps into the column, the selection then moves between all buttons; B leaves it. Features.debugArenaZone
-- draws the zone half transparent.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MapConfig = require(Config:WaitForChild("Map"))
local Features = require(Config:WaitForChild("Features"))
local UiConfig = require(Config:WaitForChild("Ui"))
local ArenaZone = require(Shared:WaitForChild("ArenaZone"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local Keys = require(client:WaitForChild("Keys"))
local Theme, Screen, Buttons, Window, Widgets = UiKit.Theme, UiKit.Screen, UiKit.Buttons, UiKit.Window, UiKit.Widgets

local Navigation = {}

local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 50
local FOCUS_ACTION = "WobbleNavigationFocus"
local LEAVE_ACTION = "WobbleNavigationLeave"

-- the left column, top to bottom; `teleport` names the server's target, `soon` opens the "Coming soon" window; `short` is the
-- word on touch screens, where the buttons are drawn smaller
local COLUMN = {
	{ id = "upgrades", text = "UPGRADES", short = "UPGRADE", color = "mint", teleport = "upgrades" },
	{ id = "cosmetics", text = "COSMETICS", short = "SHOP", color = "pink", teleport = "cosmetics" },
	{ id = "quests", text = "QUESTS", color = "sky", teleport = "quests" },
	{ id = "index", text = "INDEX", color = "purple", soon = "Discover every flavor here." },
	{ id = "scoops", text = "SCOOPS", color = "yellow", soon = "All your scoops in one place." },
}

local BIG = {
	{ id = "plot", text = "MY PLOT", color = "mint", teleport = "plot" },
	{ id = "arena", text = "ARENA", color = "red", teleport = "arena" },
}

-- why the server said no (TeleportDenied), as the player reads it
local DENIED = {
	down = "Can't teleport while knocked down",
	hit = "You just got hit! Walk away first",
	tower = "Carry your tower out of the arena first",
}

local registry
local player = Players.LocalPlayer
local zone = MapConfig.arena
local gui: ScreenGui
local top: Frame
local column: Frame
local grid: UIGridLayout
local columnButtons: { TextButton } = {}
local columnWords: { (text: string) -> () } = {} -- sets each column button's word
local bigButtons: { TextButton } = {}
local padHint: Frame
local quick: Frame -- the small MY PLOT button of combat mode
local sign: Frame
local windows: { [string]: any } = {}
local actions: { [string]: () -> () } = {}
local shown: boolean? = nil -- what the screen shows: the whole navigation (combat mode off)
local outside: boolean? = nil -- what the sign shows: true outside the arena
local pending: boolean? = nil -- what the zone says now
local pendingSince = 0

local function setShown(visible: boolean)
	shown = visible
	top.Visible = visible
	column.Visible = visible
	quick.Visible = not visible
	if not visible and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local function update()
	local full = not registry.CombatController.inCombatMode()
	if full ~= shown then
		setShown(full)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local isOutside = if root then not ArenaZone.contains(root.Position.X, root.Position.Z, zone) else true
	local now = os.clock()
	if isOutside ~= pending then
		pending, pendingSince = isOutside, now
	end
	if pending ~= outside and (outside == nil or now - pendingSince >= zone.displayDelay) then
		outside = pending
		sign.Visible = outside == true
	end
end

local function comingSoon(entry): any
	local window = windows[entry.id]
	if not window then
		window = Window.message({
			name = "Soon_" .. entry.id,
			title = entry.text,
			color = Theme.color(entry.color),
			icon = Theme.icons[entry.id],
			text = "COMING SOON!",
			subtext = entry.soon,
		})
		windows[entry.id] = window
	end
	return window
end

local function act(entry)
	if entry.teleport then
		Remotes.TeleportRequest:FireServer(entry.teleport)
	else
		local window = comingSoon(entry)
		if window.isOpen() then
			window.close()
		else
			window.open()
		end
	end
end

-- Where a gamepad's selection goes from each button: through the column's grid (top to bottom, then the next
-- column), up out of it to MY PLOT, between MY PLOT and ARENA, and down from them into the column. Set explicitly so it
-- never depends on Roblox guessing from the positions.
local function link(rows: number)
	local function at(col: number, row: number): TextButton?
		if col < 0 or row < 0 or row >= rows then
			return nil
		end
		return columnButtons[col * rows + row + 1]
	end
	for index, button in columnButtons do
		local col, row = (index - 1) // rows, (index - 1) % rows
		button.NextSelectionUp = at(col, row - 1) or bigButtons[1]
		button.NextSelectionDown = at(col, row + 1) or button
		button.NextSelectionLeft = at(col - 1, row) or button
		button.NextSelectionRight = at(col + 1, row) or bigButtons[1]
	end
	local plot, arena = bigButtons[1], bigButtons[2]
	plot.NextSelectionLeft, plot.NextSelectionRight = columnButtons[1], arena
	plot.NextSelectionUp, plot.NextSelectionDown = plot, columnButtons[1]
	arena.NextSelectionLeft, arena.NextSelectionRight = plot, arena
	arena.NextSelectionUp, arena.NextSelectionDown = arena, columnButtons[1]
end

-- The plan's rectangles for the two clusters; the column's grid follows the number of columns.
local function layout(plan)
	Screen.place(top, plan.top, plan.scale)
	Screen.place(quick, plan.quick, plan.scale)
	Screen.place(column, plan.column, plan.scale * plan.columnScale)
	local rows = math.ceil(#COLUMN / plan.columns)
	grid.FillDirectionMaxCells = rows
	link(rows)
	for order, entry in COLUMN do
		columnWords[order](if plan.touch and entry.short then entry.short else entry.text)
	end
	padHint.Visible = Screen.input() == "gamepad"
end

local function build()
	gui = Screen.gui("Navigation", 10)

	top = Theme.frame({ Name = "Top", Visible = false, Parent = gui })
	local bigRow = Theme.frame({
		Name = "Big",
		Size = UDim2.new(1, 0, 0, UiConfig.wideButton.height),
		Parent = top,
	})
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowList.Padding = UDim.new(0, UiConfig.gap)
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = bigRow
	for order, entry in BIG do
		local button = Buttons.wide({
			name = entry.id,
			text = entry.text,
			color = Theme.color(entry.color),
			icon = Theme.icons[entry.id],
			action = entry.id,
			shrink = true,
		})
		button.button.LayoutOrder = order
		button.button.Parent = bigRow
		bigButtons[order] = button.button
		button.button.Activated:Connect(function()
			act(entry)
		end)
		actions[entry.id] = function()
			act(entry)
		end
	end
	sign = Widgets.safeSign(UiConfig.safeSign.width, UiConfig.safeSign.height)
	sign.AnchorPoint = Vector2.new(0.5, 1)
	sign.Position = UDim2.fromScale(0.5, 1)
	sign.Parent = top

	-- combat mode: only this small MY PLOT button, where the big ones are otherwise
	quick = Theme.frame({ Name = "Quick", Visible = false, Parent = gui })
	local plotEntry = BIG[1]
	local small = Buttons.icon({
		name = "quickPlot",
		icon = Theme.icons.plot,
		text = plotEntry.text,
		color = Theme.color(plotEntry.color),
		action = "plot",
		size = UiConfig.quickButton,
		shrink = true,
	})
	small.button.Parent = quick
	small.button.Activated:Connect(function()
		act(plotEntry)
	end)

	column = Theme.frame({ Name = "Column", Visible = false, Parent = gui })
	local cells = Theme.frame({ Name = "Buttons", Size = UDim2.fromScale(1, 1), Parent = column })
	grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(UiConfig.iconButton, UiConfig.iconButton)
	grid.CellPadding = UDim2.fromOffset(UiConfig.gap, UiConfig.gap)
	grid.FillDirection = Enum.FillDirection.Vertical
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = cells
	for order, entry in COLUMN do
		local button = Buttons.icon({
			name = entry.id,
			icon = Theme.icons[entry.id],
			text = entry.text,
			color = Theme.color(entry.color),
			action = entry.id,
			shrink = true,
		})
		button.button.LayoutOrder = order
		button.button.Parent = cells
		button.button.Activated:Connect(function()
			act(entry)
		end)
		columnButtons[order] = button.button
		columnWords[order] = button.setText
		actions[entry.id] = function()
			act(entry)
		end
	end
	-- with a gamepad: the D-pad symbol over the column says how to get in
	padHint = Theme.frame({
		Name = "PadHint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(0, -4),
		Size = UDim2.fromOffset(30, 30),
		Visible = false,
		Parent = column,
	})
	local pad = Instance.new("ImageLabel")
	pad.BackgroundTransparency = 1
	pad.Size = UDim2.fromScale(1, 1)
	pad.ScaleType = Enum.ScaleType.Fit
	pad.Image = game:GetService("UserInputService"):GetImageForKeyCode(Keys.pad("navigation") :: Enum.KeyCode)
	pad.Parent = padHint

	Screen.onChanged(layout)
end

local function bindKeys()
	for _, id in { "upgrades", "cosmetics", "quests", "index", "scoops", "plot", "arena" } do
		ContextActionService:BindActionAtPriority("WobbleNav_" .. id, function(_, state)
			-- in combat mode only MY PLOT's key works, as its small button stays
			if state ~= Enum.UserInputState.Begin or (not shown and id ~= "plot") then
				return Enum.ContextActionResult.Pass
			end
			actions[id]()
			return Enum.ContextActionResult.Sink
		end, false, ACTION_PRIORITY, table.unpack(Keys.inputs(id)))
	end
	-- D-pad left: into the column; B: out of it again (a window's own B comes first)
	ContextActionService:BindActionAtPriority(FOCUS_ACTION, function(_, state)
		if state ~= Enum.UserInputState.Begin or not shown then
			return Enum.ContextActionResult.Pass
		end
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(gui) then
			return Enum.ContextActionResult.Pass -- moving inside the navigation
		end
		GuiService.SelectedObject = columnButtons[1]
		return Enum.ContextActionResult.Sink
	end, false, ACTION_PRIORITY, table.unpack(Keys.inputs("navigation")))
	ContextActionService:BindActionAtPriority(LEAVE_ACTION, function(_, state)
		local selected = GuiService.SelectedObject
		if state ~= Enum.UserInputState.Begin or not (selected and selected:IsDescendantOf(gui)) then
			return Enum.ContextActionResult.Pass
		end
		GuiService.SelectedObject = nil
		return Enum.ContextActionResult.Sink
	end, false, ACTION_PRIORITY, table.unpack(Keys.inputs("back")))
end

-- The zone, half transparent: the floor disc and every ramp up to its top edge (Studio testing only).
local function drawZone()
	local folder = Instance.new("Folder")
	folder.Name = "ArenaZoneDebug"
	local function piece(size: Vector3, cframe: CFrame, shape: Enum.PartType)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromHex("#FF5A6E")
		p.Transparency = 0.75
		p.Shape = shape
		p.Size = size
		p.CFrame = cframe
		p.Parent = folder
	end
	local cx, cz, height = zone.center.x, zone.center.z, 24
	piece(
		Vector3.new(height, zone.radius * 2, zone.radius * 2),
		CFrame.new(cx, height / 2, cz) * CFrame.Angles(0, 0, math.rad(90)),
		Enum.PartType.Cylinder
	)
	for index = 1, zone.ramps do
		local sx, sz = ArenaZone.lane(index, zone)
		local direction = Vector3.new(sx, 0, sz)
		local from, to = zone.radius - 10, zone.rampTop
		local middle = Vector3.new(cx, height / 2, cz) + direction * ((from + to) / 2)
		piece(
			Vector3.new(zone.rampHalfWidth * 2, height, to - from),
			CFrame.lookAt(middle, middle + direction),
			Enum.PartType.Block
		)
	end
	folder.Parent = workspace
end

function Navigation.Init(reg)
	registry = reg
end

function Navigation.Start()
	build()
	bindKeys()
	Remotes.TeleportDenied.OnClientEvent:Connect(function(reason: string)
		local text = DENIED[reason]
		if text then
			registry.Hud.toast(text, UiConfig.colors.red)
		end
	end)
	if Features.debugArenaZone then
		drawZone()
	end
	RunService.RenderStepped:Connect(update)
end

return Navigation
