-- A list that can be longer than its frame, with the kit's scroll bar (Config/Ui.scrollbar): the ScrollingFrame on the
-- left, beside it a rounded chocolate track with a cream rim and a cream thumb with the outline. The bar only shows
-- while there is more than fits; the list then keeps room for it on the right.
--
-- Scrolling: the mouse wheel and dragging the list (touch) as in any ScrollingFrame, the thumb can be dragged with the
-- mouse or a finger (on screen only: a list on a surface in the world scrolls by wheel and drag), and with a gamepad
-- the list follows the selection (ScrollingFrame does that by itself). The thumb's sums are UiLayout.scrollThumb.
--
--   local scroller = Scroller.new({ name = "Grid", position = ..., size = ..., zIndex = 4, parent = panel })
--   scroller.list  -- the ScrollingFrame: put the layout and the items in here
--   scroller.refresh()  -- after changing the bar's look; it follows size and scrolling by itself

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiConfig = require(Shared:WaitForChild("Config"):WaitForChild("Ui"))
local UiLayout = require(Shared:WaitForChild("UiLayout"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local Scroller = {}

export type Options = {
	name: string?,
	position: UDim2?,
	size: UDim2?,
	zIndex: number?,
	parent: Instance?,
	-- inside a SurfaceGui the thumb cannot be dragged (screen and surface pixels differ); wheel and drag still work
	draggable: boolean?,
	-- the bar's width and its gap to the list in pixels (Config/Ui.scrollbar by default; wider on a board in the world)
	barWidth: number?,
	barGap: number?,
}

export type Scroller = {
	frame: Frame, -- the whole thing: list and bar
	list: ScrollingFrame,
	refresh: () -> (),
	destroy: () -> (),
}

function Scroller.new(options: Options): Scroller
	local look = UiConfig.scrollbar
	local barWidth = options.barWidth or look.width
	local barGap = options.barGap or look.gap
	local zIndex = options.zIndex or 4

	local frame = Theme.frame({
		Name = options.name or "Scroller",
		Position = options.position or UDim2.new(),
		Size = options.size or UDim2.fromScale(1, 1),
		ZIndex = zIndex,
	})

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 0 -- the kit's bar below instead
	list.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	list.Selectable = false
	list.ZIndex = zIndex
	list.Parent = frame

	local track = Theme.frame({
		Name = "ScrollTrack",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, barWidth, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color(look.track),
		ZIndex = zIndex + 1,
		Visible = false,
		Active = true,
		Parent = frame,
	})
	Theme.corner(track, UDim.new(0.5, 0))
	Theme.outline(track, 2, Theme.color("creamDark")).Transparency = look.rimTransparency

	local thumb = Theme.frame({
		Name = "ScrollThumb",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color(look.thumb),
		Size = UDim2.new(1, -4, 0, look.minThumb),
		Position = UDim2.fromOffset(2, 0),
		ZIndex = zIndex + 2,
		Active = true,
		Parent = track,
	})
	Theme.corner(thumb, UDim.new(0.5, 0))
	Theme.outline(thumb, 2)

	local shown = false
	local length = 0
	local function refresh()
		local canvas = list.AbsoluteCanvasSize.Y
		local view = list.AbsoluteWindowSize.Y
		local trackLength = frame.AbsoluteSize.Y
		local visible, thumbLength, offset =
			UiLayout.scrollThumb(canvas, view, list.CanvasPosition.Y, trackLength, look.minThumb)
		if visible ~= shown then
			shown = visible
			track.Visible = visible
			-- the list makes room for the bar only while it shows
			list.Size = if visible then UDim2.new(1, -(barWidth + barGap), 1, 0) else UDim2.fromScale(1, 1)
		end
		length = thumbLength
		if visible then
			thumb.Size = UDim2.new(1, -4, 0, thumbLength)
			thumb.Position = UDim2.fromOffset(2, offset)
		end
	end

	local connections: { RBXScriptConnection } = {
		list:GetPropertyChangedSignal("CanvasPosition"):Connect(refresh),
		list:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(refresh),
		list:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refresh),
		frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh),
	}

	if options.draggable ~= false then
		-- dragging the thumb: where on the track it was grabbed stays under the pointer
		local grab: number? = nil
		table.insert(
			connections,
			thumb.InputBegan:Connect(function(input)
				local kind = input.UserInputType
				if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
					grab = input.Position.Y - thumb.AbsolutePosition.Y
				end
			end)
		)
		table.insert(
			connections,
			UserInputService.InputChanged:Connect(function(input)
				local kind = input.UserInputType
				if grab and (kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch) then
					local offset = input.Position.Y - grab - track.AbsolutePosition.Y
					local y = UiLayout.scrollFromThumb(
						list.AbsoluteCanvasSize.Y,
						list.AbsoluteWindowSize.Y,
						track.AbsoluteSize.Y,
						length,
						offset
					)
					list.CanvasPosition = Vector2.new(list.CanvasPosition.X, y)
				end
			end)
		)
		table.insert(
			connections,
			UserInputService.InputEnded:Connect(function(input)
				local kind = input.UserInputType
				if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
					grab = nil
				end
			end)
		)
	end

	frame.Parent = options.parent
	task.defer(refresh)

	return {
		frame = frame,
		list = list,
		refresh = refresh,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			frame:Destroy()
		end,
	}
end

return Scroller
