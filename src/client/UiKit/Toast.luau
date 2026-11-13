-- The short messages of the whole game, all through Toast.show(text, kind, icon): no box, the word in the main font,
-- white or in its kind's colour (normal, warn, bad, good: Config/Ui.toast.kinds), with a thick dark outline and a
-- small icon in front, free in the picture just over the bottom cluster (the tower pill). It pops in, stands a moment
-- (shorter and smaller on touch screens, so it covers nothing) and fades out. One message at a time: a new one
-- replaces it, and the same text again while it stands (or within repeatAfter) only pops it once more.
-- Only feedback on something that just happened goes here; how the game works is the tutorial's job.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Screen = require(script.Parent:WaitForChild("Screen"))
local Anim = require(script.Parent:WaitForChild("Anim"))

local Toast = {}

export type Kind = "normal" | "warn" | "bad" | "good"

local Look = Theme.config.toast

local gui: ScreenGui? = nil
local holder: Frame
local group: CanvasGroup
local row: Frame
local icon: ImageLabel
local label: TextLabel
local touchScale: UIScale
local shownText: string? = nil
local shownAt = -math.huge
local token = 0
local fadeTween: Tween? = nil

local function build()
	local screen = Screen.gui("Toasts", 40)
	gui = screen
	holder = Theme.frame({ Name = "Holder", Parent = screen })
	-- a CanvasGroup fades the word, its outline and the icon as one
	group = Instance.new("CanvasGroup")
	group.Name = "Toast"
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 1)
	group.Position = UDim2.fromScale(0.5, 0)
	group.AutomaticSize = Enum.AutomaticSize.XY
	group.Size = UDim2.fromOffset(0, 0)
	group.GroupTransparency = 1
	group.Visible = false
	group.Parent = holder
	touchScale = Instance.new("UIScale")
	touchScale.Name = "Touch"
	touchScale.Parent = group
	-- room round the row so the thick outline is not cut at the group's edge
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Look.stroke + 2)
	padding.PaddingRight = UDim.new(0, Look.stroke + 2)
	padding.PaddingTop = UDim.new(0, Look.stroke + 2)
	padding.PaddingBottom = UDim.new(0, Look.stroke + 2)
	padding.Parent = group
	row = Theme.frame({ Name = "Row", AutomaticSize = Enum.AutomaticSize.XY, Parent = group })
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	icon = Theme.icon("", { Size = UDim2.fromOffset(Look.icon, Look.icon), LayoutOrder = 1, Parent = row })
	label = Theme.text({
		Name = "Text",
		TextSize = Look.textSize,
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
		Parent = row,
	})
	local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = Look.stroke

	Screen.onChanged(function(plan)
		-- centred over the bottom cluster, `above` design pixels over it
		Screen.place(holder, {
			x = plan.bottom.x + plan.bottom.w / 2,
			y = plan.bottom.y - Look.above * plan.scale,
			w = 1,
			h = 1,
		}, plan.scale)
		touchScale.Scale = if plan.touch then Look.touchScale else 1
	end)
end

local function pop()
	local scale = Anim.scaleOf(row)
	scale.Scale = Look.popFrom
	TweenService:Create(scale, TweenInfo.new(Look.pop, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

-- Shows `text` (kind: normal white, warn yellow, bad red, good green; icon: a key of Config/Ui.icons or an asset id).
function Toast.show(text: string, kind: Kind?, iconName: string?)
	if not gui then
		build()
	end
	local now = os.clock()
	local hold = if Screen.input() == "touch" then Look.touchHold else Look.hold
	local again = text == shownText and now - shownAt < math.max(Look.repeatAfter, hold + Look.fade)
	shownAt = now
	if again and group.Visible and group.GroupTransparency < 1 then
		-- the same message again: no new one, it pops once more and stands a little longer
		pop()
	else
		shownText = text
		label.Text = text
		label.TextColor3 = Theme.color(Look.kinds[kind or "normal"] or "text")
		local image = if iconName then Theme.icons[iconName] or iconName else nil
		icon.Image = image or ""
		icon.Visible = image ~= nil
		pop()
	end
	if fadeTween then
		fadeTween:Cancel()
	end
	group.Visible = true
	group.GroupTransparency = 0
	token += 1
	local mine = token
	task.delay(hold, function()
		if token ~= mine then
			return
		end
		local tween = TweenService:Create(
			group,
			TweenInfo.new(Look.fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ GroupTransparency = 1 }
		)
		fadeTween = tween
		tween:Play()
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and token == mine then
				group.Visible = false
			end
		end)
	end)
end

return Toast
