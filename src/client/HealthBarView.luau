-- The life bar's look (Config/Combat healthBar, HealthPips), one for the own meter under the crosshair (KnockMeter)
-- and one over each rival (EnemyHealthBars), so both read as the same thing: a chocolate pill with the kit's outline
-- and gloss, holding one candy segment per normal hit up to the knockdown. Everything inside is laid out in shares of
-- the bar, so it fits a ScreenGui frame in pixels as well as a BillboardGui in studs. It only draws: the controllers
-- hand it the share left and the tone from HealthPips.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))
local HealthPips = require(Shared:WaitForChild("HealthPips"))

local Theme = require(script.Parent:WaitForChild("UiKit"):WaitForChild("Theme"))

local Bar = CombatConfig.healthBar
local SEGMENTS = HealthPips.segments(CombatConfig.knock)
local WHITE = Color3.new(1, 1, 1)
local SLOT = Theme.darker(Theme.color("chocolate"), 0.35) -- an emptied segment: the pill's dark inside

local TONES: { [string]: Color3 } = {}
for tone, hex in Bar.colors do
	TONES[tone] = Color3.fromHex(hex)
end

local function candy(color: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.lighter(color, 0.3)),
		ColorSequenceKeypoint.new(0.5, color),
		ColorSequenceKeypoint.new(1, Theme.darker(color, 0.18)),
	})
end

export type View = {
	root: CanvasGroup,
	-- the share of the bar left (0 to 1) and its tone
	set: (share: number, tone: HealthPips.Tone) -> (),
	-- a hit: a short white flash and shake, played by step
	hit: (now: number) -> (),
	-- 0 hidden to 1 shown
	setAlpha: (alpha: number) -> (),
	-- the flash and shake at `now` (os.clock())
	step: (now: number) -> (),
}

local HealthBarView = {}

-- A bar with an outline `stroke` pixels thick. The caller sizes and places `root`.
function HealthBarView.new(stroke: number): View
	-- the CanvasGroup fades the whole bar as one; a small inset keeps the outline inside it
	local root = Instance.new("CanvasGroup")
	root.Name = "HealthBar"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.GroupTransparency = 1

	local body = Theme.frame({
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -(stroke + Bar.shake) * 2, 1, -stroke * 2), -- room for the outline and the shake
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("chocolate"),
		Parent = root,
	})
	Theme.corner(body, UDim.new(0.5, 0))
	Theme.outline(body, stroke)

	local row = Theme.frame({
		Name = "Segments",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.62),
		Parent = body,
	})
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	local gap = 0.04
	list.Padding = UDim.new(gap, 0)
	list.Parent = row

	local fills: { Frame } = {}
	local gradients: { UIGradient } = {}
	local flashes: { Frame } = {}
	local width = (1 - gap * (SEGMENTS - 1)) / SEGMENTS
	for index = 1, SEGMENTS do
		local slot = Theme.frame({
			Name = "Segment" .. index,
			LayoutOrder = index,
			Size = UDim2.fromScale(width, 1),
			BackgroundTransparency = 0,
			BackgroundColor3 = SLOT,
			ClipsDescendants = true,
			Parent = row,
		})
		Theme.corner(slot, UDim.new(0.45, 0))
		local fill = Theme.frame({
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
			Parent = slot,
		})
		Theme.corner(fill, UDim.new(0.45, 0))
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Parent = fill
		local flash = Theme.frame({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BackgroundColor3 = WHITE,
			ZIndex = 3,
			Parent = slot,
		})
		Theme.corner(flash, UDim.new(0.45, 0))
		fills[index], gradients[index], flashes[index] = fill, gradient, flash
	end

	-- the kit's gloss: a soft white streak along the top of the pill
	local gloss = Theme.frame({
		Name = "Gloss",
		Position = UDim2.fromScale(0.07, 0.12),
		Size = UDim2.fromScale(0.5, 0.2),
		BackgroundTransparency = 0.5,
		BackgroundColor3 = WHITE,
		ZIndex = 4,
		Parent = body,
	})
	Theme.corner(gloss, UDim.new(0.5, 0))

	local shownTone: string? = nil
	local hitAt = -math.huge

	local view = {} :: View
	view.root = root

	function view.set(share: number, tone: HealthPips.Tone)
		for index, fill in HealthPips.fills(share, SEGMENTS) do
			fills[index].Size = UDim2.fromScale(fill, 1)
			fills[index].Visible = fill > 0
		end
		if tone ~= shownTone then
			shownTone = tone
			local sequence = candy(TONES[tone])
			for _, gradient in gradients do
				gradient.Color = sequence
			end
			body.BackgroundColor3 = if tone == "down" then Theme.darker(TONES.down, 0.3) else Theme.color("chocolate")
		end
	end

	function view.hit(now: number)
		hitAt = now
	end

	function view.setAlpha(alpha: number)
		root.GroupTransparency = 1 - math.clamp(alpha, 0, 1)
	end

	function view.step(now: number)
		local t = (now - hitAt) / Bar.flash
		local flash = if t < 1 then 1 - t else 0
		for _, frame in flashes do
			frame.BackgroundTransparency = 1 - flash * 0.85
		end
		local shake = if t < 2 then Bar.shake * (1 - t / 2) * math.sin((now - hitAt) * 70) else 0
		body.Position = UDim2.new(0.5, shake, 0.5, 0)
	end

	return view
end

return HealthBarView
