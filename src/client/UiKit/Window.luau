-- The kit's windows: a cream panel with a candy title bar whose glaze drips over the panel, a glaze rim inside the
-- outline and the red close button on the corner; popups (a small window with a text and buttons) and tabs. One
-- window is open at a time. It closes with the close button, B on a gamepad, or by opening another; with a gamepad the
-- selection jumps into it when it opens and is given back when it closes.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Anim = require(script.Parent:WaitForChild("Anim"))
local Screen = require(script.Parent:WaitForChild("Screen"))
local Buttons = require(script.Parent:WaitForChild("Buttons"))

local Window = {}

local CLOSE_ACTION = "UiKitWindowClose"
local PRIORITY = Enum.ContextActionPriority.High.Value + 200
local TITLE = 58

export type Window = {
	gui: ScreenGui,
	root: Frame,
	content: Frame,
	closeButton: TextButton,
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	onClosed: (callback: () -> ()) -> (),
	firstSelection: GuiObject?,
}

local current: Window? = nil

-- The drips of glaze hanging from the title bar: rounded drops of different lengths.
local function drips(bar: Frame, color: Color3, width: number)
	local spots = { 0.12, 0.27, 0.41, 0.58, 0.71, 0.86 }
	local lengths = { 18, 10, 24, 12, 20, 9 }
	for index, share in spots do
		local drop = Theme.frame({
			Name = "Drip",
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.darker(color, 0.1),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(share, 0, 1, -14),
			Size = UDim2.fromOffset(math.max(14, width * 0.03), 14 + lengths[index]),
			ZIndex = 3,
			Parent = bar,
		})
		Theme.corner(drop, UDim.new(0.5, 0))
	end
end

-- props: name, title, color (the title bar), width, height (design pixels).
function Window.new(props: { name: string, title: string, color: Color3, width: number?, height: number? }): Window
	local width, height = props.width or 560, props.height or 380
	local gui = Screen.gui(props.name, 30)
	gui.Enabled = false

	local dim = Theme.frame({
		Name = "Dim",
		BackgroundTransparency = 0.45,
		BackgroundColor3 = Color3.new(0, 0, 0),
		Size = UDim2.new(1, 0, 1, 200),
		Position = UDim2.fromOffset(0, -100),
		Active = true, -- clicks behind the window do nothing
		Parent = gui,
	})
	dim.ZIndex = 0

	local root = Theme.frame({
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		Parent = gui,
	})
	local layoutScale = Instance.new("UIScale")
	layoutScale.Name = "Layout"
	layoutScale.Parent = root
	Screen.onChanged(function(plan)
		-- as big as the screen allows, never bigger than the HUD's scale
		local room = math.min(plan.frame.w / (width + 40), plan.frame.h / (height + 40))
		layoutScale.Scale = math.min(plan.scale, room)
	end)

	local body = Theme.frame({
		Name = "Panel",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("cream"),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = root,
	})
	Theme.corner(body, UDim.new(0, 26))
	Theme.outline(body, 4)
	-- the glaze rim inside the outline
	local rim = Theme.frame({
		Name = "Glaze",
		Position = UDim2.fromOffset(7, 7),
		Size = UDim2.new(1, -14, 1, -14),
		ZIndex = 1,
		Parent = body,
	})
	Theme.corner(rim, UDim.new(0, 20))
	local rimStroke = Theme.outline(rim, 5, Theme.lighter(props.color, 0.45))
	rimStroke.Transparency = 0.15

	local bar = Theme.frame({
		Name = "TitleBar",
		BackgroundTransparency = 0,
		Size = UDim2.new(1, 0, 0, TITLE),
		ZIndex = 2,
		Parent = root,
	})
	Theme.corner(bar, UDim.new(0, 26))
	Theme.shade(bar, props.color)
	Theme.outline(bar, 4)
	-- square off the bar's lower corners, under the drips
	local foot = Theme.frame({
		Name = "Foot",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.darker(props.color, 0.1),
		Position = UDim2.new(0, 0, 1, -16),
		Size = UDim2.new(1, 0, 0, 16),
		ZIndex = 2,
		Parent = bar,
	})
	foot.BorderSizePixel = 0
	drips(bar, props.color, width)
	Theme.text({
		Name = "Title",
		Text = props.title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.new(1, -140, 0, 36),
		TextScaled = true,
		ZIndex = 5,
		Parent = bar,
	})

	local closeButton = Buttons.close(50)
	closeButton.AnchorPoint = Vector2.new(0.5, 0.5)
	closeButton.Position = UDim2.new(1, -18, 0, 12)
	closeButton.ZIndex = 6
	closeButton.Parent = root
	local closeBadge = Buttons.badge(closeButton, nil, Enum.KeyCode.ButtonB, 28)
	closeBadge.frame.Position = UDim2.new(0, -4, 1, 2)

	local content = Theme.frame({
		Name = "Content",
		Position = UDim2.fromOffset(22, TITLE + 22),
		Size = UDim2.new(1, -44, 1, -TITLE - 40),
		ZIndex = 3,
		Parent = root,
	})

	local closedCallbacks: { () -> () } = {}
	local open = false
	local self: Window

	local function close()
		if not open then
			return
		end
		open = false
		gui.Enabled = false
		if current == self then
			current = nil
		end
		ContextActionService:UnbindAction(CLOSE_ACTION)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
		for _, callback in closedCallbacks do
			task.spawn(callback)
		end
	end

	self = {
		gui = gui,
		root = root,
		content = content,
		closeButton = closeButton,
		firstSelection = nil,
		open = function()
			if open then
				return
			end
			if current and current ~= self then
				current.close()
			end
			current = self
			open = true
			gui.Enabled = true
			Anim.pop(root)
			ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, state)
				if state == Enum.UserInputState.Begin then
					close()
				end
				return Enum.ContextActionResult.Sink
			end, false, PRIORITY, Enum.KeyCode.ButtonB)
			if Screen.input() == "gamepad" then
				GuiService.SelectedObject = self.firstSelection or closeButton
			end
		end,
		close = close,
		isOpen = function()
			return open
		end,
		onClosed = function(callback: () -> ())
			table.insert(closedCallbacks, callback)
		end,
	}
	closeButton.Activated:Connect(close)
	return self
end

-- A window with an icon, a big line and a smaller one under it in the middle, e.g. "COMING SOON!".
function Window.message(props: {
	name: string,
	title: string,
	color: Color3,
	icon: string?,
	text: string,
	subtext: string?,
}): Window
	local window =
		Window.new({ name = props.name, title = props.title, color = props.color, width = 480, height = 340 })
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = window.content
	if props.icon then
		Theme.icon(
			props.icon,
			{ Size = UDim2.fromOffset(120, 120), LayoutOrder = 1, ZIndex = 4, Parent = window.content }
		)
	end
	Theme.text({
		Name = "Message",
		Text = props.text,
		Size = UDim2.new(1, 0, 0, 46),
		TextScaled = true,
		TextColor3 = props.color,
		LayoutOrder = 2,
		ZIndex = 4,
		Parent = window.content,
	})
	if props.subtext then
		local sub = Instance.new("TextLabel")
		sub.Name = "Subtext"
		sub.BackgroundTransparency = 1
		sub.Font = Theme.font
		sub.TextColor3 = Theme.color("textDark")
		sub.TextScaled = true
		sub.Text = props.subtext
		sub.Size = UDim2.new(1, -20, 0, 26)
		sub.LayoutOrder = 3
		sub.ZIndex = 4
		sub.Parent = window.content
	end
	return window
end

-- A popup: a small window with a text and up to three buttons. Each button calls its callback and closes the popup.
function Window.popup(props: {
	name: string,
	title: string,
	text: string,
	color: Color3,
	buttons: { { text: string, color: Color3, callback: (() -> ())? } },
}): Window
	local window =
		Window.new({ name = props.name, title = props.title, color = props.color, width = 440, height = 260 })
	Theme.text({
		Name = "Message",
		Text = props.text,
		Size = UDim2.new(1, 0, 0, 70),
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = Theme.color("textDark"),
		ZIndex = 4,
		Parent = window.content,
	})
		:FindFirstChildOfClass("UIStroke")
		:Destroy()
	local row = Theme.frame({
		Name = "Buttons",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 56),
		ZIndex = 4,
		Parent = window.content,
	})
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 14)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	for order, entry in props.buttons do
		local button = Buttons.wide({
			name = entry.text,
			text = entry.text,
			color = entry.color,
			width = 170,
			height = 52,
		})
		button.button.LayoutOrder = order
		button.button.Parent = row
		button.button.Activated:Connect(function()
			window.close()
			if entry.callback then
				entry.callback()
			end
		end)
		if order == 1 then
			window.firstSelection = button.button
		end
	end
	return window
end

export type Tabs = { frame: Frame, buttons: { TextButton }, select: (index: number) -> (), selected: () -> number }

-- A row of tabs; the selected one is raised and in `color`, the others cream. `onSelect(index)` runs on a change.
function Window.tabs(parent: GuiObject, names: { string }, color: Color3, onSelect: (index: number) -> ()): Tabs
	local frame = Theme.frame({ Name = "Tabs", Size = UDim2.new(1, 0, 0, 46), ZIndex = 4, Parent = parent })
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.Parent = frame
	local buttons: { TextButton } = {}
	local gradients: { UIGradient } = {}
	local labels: { TextLabel } = {}
	local selected = 1
	local function paint()
		for index, button in buttons do
			local on = index == selected
			Theme.recolor(gradients[index], if on then color else Theme.color("creamDark"))
			button.Size = UDim2.new(1 / #names, -8, 0, if on then 46 else 40)
			labels[index].TextColor3 = if on then Theme.color("text") else Theme.color("textDark")
			labels[index]:FindFirstChildOfClass("UIStroke").Enabled = on
		end
	end
	local self: Tabs
	for index, name in names do
		local button = Instance.new("TextButton")
		button.Name = name
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundTransparency = 1
		button.LayoutOrder = index
		button.Selectable = true
		button.SelectionImageObject = Theme.selection(UDim.new(0, 18))
		button.ZIndex = 4
		button.Parent = frame
		Anim.button(button)
		local _, gradient = Theme.body(button, Theme.color("creamDark"), UDim.new(0, 14))
		gradients[index] = gradient
		labels[index] = Theme.text({
			Text = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -12, 0.55, 0),
			TextScaled = true,
			ZIndex = 6,
			Parent = button,
		})
		buttons[index] = button
		button.Activated:Connect(function()
			self.select(index)
		end)
	end
	self = {
		frame = frame,
		buttons = buttons,
		select = function(index: number)
			if index ~= selected then
				selected = index
				paint()
				onSelect(index)
			end
		end,
		selected = function()
			return selected
		end,
	}
	paint()
	return self
end

return Window
