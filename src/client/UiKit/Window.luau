-- The kit's windows: a cream panel with a candy title bar whose glaze drips over the panel, a glaze rim inside the
-- outline and the red close button on the corner; popups (a small window with a text and buttons) and tabs. One
-- window is open at a time. It closes with the close button, B on a gamepad, or by opening another; with a gamepad the
-- selection jumps into it when it opens and is given back when it closes.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Anim = require(script.Parent:WaitForChild("Anim"))
local Screen = require(script.Parent:WaitForChild("Screen"))
local HudAway = require(script.Parent:WaitForChild("HudAway"))
local Buttons = require(script.Parent:WaitForChild("Buttons"))
local Keys = require(script.Parent.Parent:WaitForChild("Keys"))

local Window = {}

local CLOSE_ACTION = "UiKitWindowClose"
local PRIORITY = Enum.ContextActionPriority.High.Value + 200
-- the window surface (Config/Ui.skins.window): its glaze in design pixels, the rim round the panel, and the space
-- round the content (callers give a window's size for a content area of height - CONTENT_LESS)
local SCALE = Theme.config.skins.window.scale
local GLAZE = Theme.config.windowGlaze
local GLAZE_MIDDLE = GLAZE.middle * SCALE
local CONTENT_TOP = math.ceil(GLAZE.drips * SCALE) + 4
local RIM = 14
local CONTENT_LESS = 98
local TITLE_SIDE = 100 -- each side of the title stays free for the sprinkles and the close button
local DIM = 0.45 -- the dim behind an open window
local WINDOW_MARGIN = 16 -- design pixels kept free round a window (and its title plaque) inside the HUD's frame
local ART_TITLE = { width = 380, height = 76 } -- the title pill of a window with own pictures but no title picture

export type Window = {
	gui: ScreenGui,
	root: Frame,
	content: Frame,
	closeButton: GuiButton,
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	onClosed: (callback: () -> ()) -> (),
	firstSelection: GuiObject?,
}

-- A window drawn from its own pictures instead of the kit's surface (e.g. the Scoop Chest, Config/Chest.art.window):
-- `panel` is a 9-slice image (`slice` its middle in image pixels, `sliceScale` design pixels per image pixel), `title`
-- a picture with the title in it, `titleSize` its size and `titleY` its middle (design pixels, from the window's top),
-- `inset` the content's distance from the window's edges. Without `title` the window's title stands on a pill at titleY.
export type Art = {
	panel: string,
	slice: Rect,
	sliceScale: number,
	title: string?,
	titleSize: Vector2?,
	titleY: number?,
	inset: { top: number, side: number, bottom: number },
	-- the title is painted on the panel (a plaque without words): only the live word, `titleText` its box (design
	-- pixels, centred at titleY), in the main font with the chocolate outline
	titleText: { width: number, height: number }?,
	-- an own close button: its picture, its middle (design pixels from the window's top left) and its size
	close: { image: string, x: number, y: number, size: number }?,
}

local current: Window? = nil

-- props: name, title, color (the window's accent, e.g. a message's big line), width, height (design pixels; the
-- content area is height - 98 high, the window itself as much taller as its glaze needs). hudAway: the window pops up
-- bigger (Config/Ui.windowPop), the dim fades in, and the HUD glides out to the screen edges while it is open (HudAway).
function Window.new(props: {
	name: string,
	title: string,
	color: Color3,
	width: number?,
	height: number?,
	hudAway: boolean?,
	art: Art?,
}): Window
	local art = props.art
	local width = props.width or 560
	local contentHeight = (props.height or 380) - CONTENT_LESS
	local height = if art then art.inset.top + contentHeight + art.inset.bottom else CONTENT_TOP + contentHeight + 22
	local gui = Screen.gui(props.name, 30)
	gui.Enabled = false

	local dim = Theme.frame({
		Name = "Dim",
		BackgroundTransparency = DIM,
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
	-- The window's one UIScale: its fit to the screen and the pop when it opens in one (Roblox applies only the first
	-- UIScale of an object, so a second one for the pop never showed, found 17.11.2026).
	local layoutScale = Instance.new("UIScale")
	layoutScale.Name = "Layout"
	layoutScale.Parent = root
	local fit = 1
	local popTween: Tween? = nil
	-- what reaches out of the window's box: the title plaque over the top edge (own pictures) or the close button
	local overTop = if art
			and art.title
			and art.titleSize
		then math.max(13, art.titleSize.Y / 2 - (art.titleY or 0))
		elseif art then math.max(13, ART_TITLE.height / 2 - (art.titleY or 0))
		else 13
	Screen.onChanged(function(plan)
		-- As big as the HUD's frame allows (the safe area under Roblox's top bar, with its margins), never bigger than
		-- the HUD's scale, with a margin all round; title plaque and close button count. Centred in that frame. Before
		-- (phone test 17.11.2026) a touch screen let the window reach up under Roblox's top bar, and the close button
		-- sat on the gear.
		local frame = plan.frame
		local needW, needH = width + 2 * WINDOW_MARGIN, height + overTop + 2 * WINDOW_MARGIN
		fit = math.min(plan.scale, frame.w / needW, frame.h / needH)
		local top = frame.y + (frame.h - needH * fit) / 2 + (WINDOW_MARGIN + overTop) * fit
		root.Position = UDim2.fromOffset(math.round(frame.x + frame.w / 2), math.round(top + height * fit / 2))
		if not (popTween and popTween.PlaybackState == Enum.PlaybackState.Playing) then
			layoutScale.Scale = fit
		end
	end)
	local function pop(from: number, time: number)
		if popTween then
			popTween:Cancel()
		end
		layoutScale.Scale = fit * from
		popTween = TweenService:Create(
			layoutScale,
			TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = fit }
		)
		popTween:Play()
	end

	if art then
		-- the window's own pictures: the panel as a 9-slice, the title plaque over its top edge
		local panel = Theme.icon(art.panel, { Name = "Panel", Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = root })
		panel.ScaleType = Enum.ScaleType.Slice
		panel.SliceCenter = art.slice
		panel.SliceScale = art.sliceScale
		local square = panel:FindFirstChildOfClass("UIAspectRatioConstraint")
		if square then
			square:Destroy()
		end
		if art.titleText then
			-- the plaque is in the panel picture: only the word, live, with a thick chocolate outline
			local word = Theme.text({
				Name = "Title",
				Text = props.title,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, art.titleY or 0),
				Size = UDim2.fromOffset(art.titleText.width, art.titleText.height),
				TextScaled = true,
				TextColor3 = Theme.color("cream"),
				ZIndex = 5,
				Parent = root,
			})
			local outline = word:FindFirstChildOfClass("UIStroke")
			if outline then
				outline.Thickness = 5
			end
		elseif art.title and art.titleSize then
			local title = Theme.icon(art.title, {
				Name = "Title",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, art.titleY or 0),
				Size = UDim2.fromOffset(art.titleSize.X, art.titleSize.Y),
				ZIndex = 5,
				Parent = root,
			})
			title:FindFirstChildOfClass("UIAspectRatioConstraint").AspectRatio = art.titleSize.X / art.titleSize.Y
		else
			-- no title picture (yet): the title on a candy pill in the window's colour over the top edge
			local plaque = Theme.frame({
				Name = "Title",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, art.titleY or 0),
				Size = UDim2.fromOffset(ART_TITLE.width, ART_TITLE.height),
				ZIndex = 5,
				Parent = root,
			})
			Theme.skin(plaque, "pill", ART_TITLE.height, props.color).image.ZIndex = 5
			Theme.text({
				Name = "Label",
				Text = props.title,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, -2),
				Size = UDim2.new(1, -ART_TITLE.height, 0.6, 0),
				TextScaled = true,
				ZIndex = 6,
				Parent = plaque,
			})
		end
	else
		-- the chocolate panel with the pink glaze and its drips (one 9-slice), the faint waffle on the panel under the glaze
		local panel = Theme.frame({ Name = "Panel", Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = root })
		Theme.skin(panel, "window", height)
		local waffle = Theme.waffle(panel, 3, UDim.new(0, 22))
		waffle.Position = UDim2.fromOffset(RIM, GLAZE.band * SCALE)
		waffle.Size = UDim2.new(1, -RIM * 2, 1, -GLAZE.band * SCALE - RIM)
		Theme.text({
			Name = "Title",
			Text = props.title,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, GLAZE_MIDDLE),
			Size = UDim2.new(1, -TITLE_SIDE * 2, 0, 34),
			TextScaled = true,
			ZIndex = 5,
			Parent = root,
		})
		for _, place in Theme.config.sprinkles.window do
			local x = place[2]
			Theme.sprinkle(root, place[1], UDim2.new(if x < 0 then 1 else 0, x, 0, GLAZE_MIDDLE), place[3], 5)
		end
	end

	local closeButton: GuiButton
	local closeArt = art and art.close
	if closeArt then
		-- the window's own close picture where the panel has room for it
		local own = Instance.new("ImageButton")
		own.Name = "Close"
		own.BackgroundTransparency = 1
		own.Image = closeArt.image
		own.AnchorPoint = Vector2.new(0.5, 0.5)
		own.Position = UDim2.fromOffset(closeArt.x, closeArt.y)
		own.Size = UDim2.fromOffset(closeArt.size, closeArt.size)
		own.ZIndex = 6
		own.Parent = root
		Anim.button(own)
		closeButton = own
	else
		closeButton = Buttons.close(50)
		closeButton.AnchorPoint = Vector2.new(0.5, 0.5)
		closeButton.Position = UDim2.new(1, -18, 0, 12)
		closeButton.ZIndex = 6
		closeButton.Parent = root
	end
	local closeBadge = Buttons.badge(closeButton, "back", 28)
	closeBadge.frame.Position = UDim2.new(0, -4, 1, 2)

	local side = if art then art.inset.side else 22
	local content = Theme.frame({
		Name = "Content",
		Position = UDim2.fromOffset(side, if art then art.inset.top else CONTENT_TOP),
		Size = UDim2.new(1, -side * 2, 0, contentHeight),
		ZIndex = 3,
		Parent = root,
	})

	local closedCallbacks: { () -> () } = {}
	local open = false
	local self: Window
	local releaseHud: (() -> ())? = nil
	local dimTween: Tween? = nil

	local function close()
		if not open then
			return
		end
		open = false
		gui.Enabled = false
		if releaseHud then
			releaseHud()
			releaseHud = nil
		end
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
			if props.hudAway then
				local look = Theme.config.windowPop
				pop(look.from, look.time)
				if dimTween then
					dimTween:Cancel()
				end
				dim.BackgroundTransparency = 1
				dimTween = TweenService:Create(dim, TweenInfo.new(look.dimTime), { BackgroundTransparency = DIM })
				dimTween:Play()
				releaseHud = HudAway.push()
			else
				pop(0.6, Theme.config.anim.pop)
			end
			ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, state)
				if state == Enum.UserInputState.Begin then
					close()
				end
				return Enum.ContextActionResult.Sink
			end, false, PRIORITY, table.unpack(Keys.inputs("back")))
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
		sub.FontFace = Theme.fontText -- a description
		sub.TextColor3 = Theme.color("creamDark") -- light on the chocolate panel
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
		TextColor3 = Theme.color("cream"), -- light on the chocolate panel, with the outline
		FontFace = Theme.fontText,
		ZIndex = 4,
		Parent = window.content,
	})
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
	local skins: { Theme.Skin } = {}
	local labels: { TextLabel } = {}
	local selected = 1
	local function paint()
		for index, button in buttons do
			local on = index == selected
			skins[index].setColor(if on then color else Theme.color("creamDark"))
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
		skins[index] = Theme.skin(button, "square", 44, Theme.color("creamDark"))
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
