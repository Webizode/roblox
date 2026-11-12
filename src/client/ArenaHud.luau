-- The arena's two HUD pieces next to the ice balls (Hud places and shows them): the balance gauge and the dash bar.
-- Both only draw what they are told; the values come from the tower simulation (TowerController) and the dash's own
-- cooldown. Sizes are design pixels (Config/Ui), the cluster's UIScale scales them.
--
-- The balance gauge, after the reference "Drei Balanceanzeigen im Eiscreme-Stil": the frame (chocolate rim, icing,
-- the cone on top) is an image with its inside cut out; under it, as UI so it moves and colours smoothly:
--   * a cream disc; the steady stance's energy is its water level (light blue), glowing while the stance is held
--   * a ring round the disc's edge, filling clockwise from the top with how close the tower is to tipping (its lean
--     over the tip angle), green over yellow to red
--   * a dot that moves the way the tower leans, seen from the camera (up = away from you), so you know where to
--     steer against it
-- Close to tipping (the tower groans) the gauge pulses a little and glows red. Without a tower it is greyed out.
--
-- The dash bar, after the reference "Schlanke glänzende Neon-Balken": the grey glass with the blue one over it,
-- shown from the left as far as the dash has recharged. When it is full again it bumps and two little stars sparkle.
-- A key badge on PC (Q) and with a gamepad (X); none on touch screens.

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local UiConfig = require(Config:WaitForChild("Ui"))
local Tuning = require(Config:WaitForChild("Tower"))

local UiKit = require(script.Parent:WaitForChild("UiKit"))
local Theme, Buttons = UiKit.Theme, UiKit.Buttons

local ArenaHud = {}

local GAUGE = UiConfig.balance
local W, H = GAUGE.width, GAUGE.height
local CX, CY = GAUGE.hole.x * W, GAUGE.hole.y * H
local R = GAUGE.hole.radius * W -- the hole in the frame
local RIM_R = 0.493 * W -- the frame's outer edge round the same centre
local RING = 8 -- the ring's thickness
local RING_R = R - RING / 2 - 3 -- the ring's middle, clear of the rim
local DOT = 13
local DOT_TRAVEL = RING_R - RING / 2 - DOT / 2 - 1 -- how far the dot moves from the centre at the tip angle
local GLOW_PAD = 10 -- room round the frame for the red glow

local GREEN = Color3.fromHex("#45D43A")
local YELLOW = Theme.color("yellow")
local RED = Theme.color("red")
local WATER = Theme.color("sky")
local DISC = Color3.fromHex("#FDE6CC")
local GREY = Color3.fromRGB(185, 185, 185) -- the tint without a tower

local function circle(props: { [string]: any }): Frame
	local f = Theme.frame(props)
	Theme.corner(f, UDim.new(0.5, 0))
	return f
end

-- Green at rest, yellow at half the tip angle, red where the tower starts to groan.
local function ringColor(tilt: number): Color3
	if tilt <= 0.5 then
		return GREEN:Lerp(YELLOW, math.clamp(tilt / 0.5, 0, 1))
	end
	return YELLOW:Lerp(RED, math.clamp((tilt - 0.5) / math.max(Tuning.groanFraction - 0.5, 0.05), 0, 1))
end

-- A ring that fills clockwise from the top: two halves, each a stroked circle clipped to its half, the stroke's
-- gradient turned so the right part of the half shows (`set(share)`).
local function progressRing(parent: GuiObject, diameter: number, thickness: number, z: number)
	local strokes: { UIStroke } = {}
	local gradients: { UIGradient } = {}
	for index, side in { "Right", "Left" } do
		local clip = Theme.frame({
			Name = side,
			Position = UDim2.fromOffset(if side == "Right" then diameter / 2 else 0, 0),
			Size = UDim2.fromOffset(diameter / 2, diameter),
			ClipsDescendants = true,
			ZIndex = z,
			Parent = parent,
		})
		local ring = circle({
			Name = "Ring",
			Position = UDim2.fromOffset(if side == "Right" then -diameter / 2 else 0, 0),
			Size = UDim2.fromOffset(diameter, diameter),
			ZIndex = z,
			Parent = clip,
		})
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = thickness
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = ring
		local gradient = Instance.new("UIGradient")
		-- the right half shows the opaque half turned past 0 degrees, the left half the transparent one's complement
		gradient.Transparency = if side == "Right"
			then NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(0.501, 1),
				NumberSequenceKeypoint.new(1, 1),
			})
			else NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 1),
				NumberSequenceKeypoint.new(0.501, 0),
				NumberSequenceKeypoint.new(1, 0),
			})
		gradient.Parent = stroke
		strokes[index], gradients[index] = stroke, gradient
	end
	local function set(share: number, color: Color3)
		local angle = math.clamp(share, 0, 1) * 360
		gradients[1].Rotation = math.min(angle, 180)
		gradients[2].Rotation = math.clamp(angle - 180, 0, 180)
		strokes[1].Enabled = angle > 0.5
		strokes[2].Enabled = angle > 180.5
		strokes[1].Color, strokes[2].Color = color, color
	end
	set(0, GREEN)
	return set
end

export type Gauge = {
	frame: Frame, -- placed by the HUD (design size Config/Ui.balance)
	group: CanvasGroup, -- fades
	set: (
		tilt: number,
		groaning: boolean,
		hasTower: boolean,
		leanX: number,
		leanY: number,
		energy: number,
		stance: string
	) -> (),
	step: () -> (), -- every frame: the pulse
}

function ArenaHud.gauge(parent: Instance): Gauge
	local holder = Theme.frame({ Name = "Balance", Size = UDim2.fromOffset(W, H), Parent = parent })
	local group = Instance.new("CanvasGroup")
	group.Name = "Gauge"
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.Position = UDim2.fromOffset(-GLOW_PAD, -GLOW_PAD)
	group.Size = UDim2.fromOffset(W + 2 * GLOW_PAD, H + 2 * GLOW_PAD)
	group.GroupTransparency = 1
	group.Visible = false
	group.Parent = holder
	local body = Theme.frame({
		Name = "Body",
		Position = UDim2.fromOffset(GLOW_PAD, GLOW_PAD),
		Size = UDim2.fromOffset(W, H),
		Parent = group,
	})
	local pulse = Instance.new("UIScale")
	pulse.Name = "Pulse"
	pulse.Parent = body

	-- the red glow round the rim, near tipping
	local glow = circle({
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(CX, CY),
		Size = UDim2.fromOffset(2 * RIM_R - 4, 2 * RIM_R - 4),
		ZIndex = 1,
		Parent = body,
	})
	local glowStroke = Instance.new("UIStroke")
	glowStroke.Color = RED
	glowStroke.Thickness = 7
	glowStroke.Transparency = 1
	glowStroke.Parent = glow

	-- the disc with the stance's water in it (a CanvasGroup with round corners clips the water round)
	local disc = Instance.new("CanvasGroup")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromOffset(CX, CY)
	disc.Size = UDim2.fromOffset(2 * R + 6, 2 * R + 6)
	disc.BackgroundColor3 = DISC
	disc.BorderSizePixel = 0
	disc.ZIndex = 2
	disc.Parent = body
	Theme.corner(disc, UDim.new(0.5, 0))
	local water = Theme.frame({
		Name = "Water",
		BackgroundTransparency = 0.7,
		BackgroundColor3 = WATER,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = disc,
	})
	-- the glass's shine, top left like in the reference
	local shine = circle({
		Name = "Shine",
		BackgroundTransparency = 0.45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromScale(0.22, 0.2),
		Size = UDim2.fromScale(0.3, 0.14),
		Rotation = -30,
		ZIndex = 3,
		Parent = disc,
	})
	shine.Name = "Shine"
	local discGlow = Instance.new("UIStroke")
	discGlow.Color = WATER
	discGlow.Thickness = 4
	discGlow.Transparency = 1
	discGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	discGlow.Parent = disc

	-- the ring: a faint track, the filled part over it
	local ringHolder = Theme.frame({
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(CX, CY),
		Size = UDim2.fromOffset(2 * RING_R, 2 * RING_R),
		ZIndex = 4,
		Parent = body,
	})
	local track = circle({ Name = "Track", Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = ringHolder })
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = Theme.color("creamDark")
	trackStroke.Thickness = RING
	trackStroke.Transparency = 0.35
	trackStroke.Parent = track
	local setRing = progressRing(ringHolder, 2 * RING_R, RING, 5)

	local dot = circle({
		Name = "Dot",
		BackgroundTransparency = 0,
		BackgroundColor3 = GREEN,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(CX, CY),
		Size = UDim2.fromOffset(DOT, DOT),
		ZIndex = 6,
		Parent = body,
	})
	Theme.outline(dot, 2)
	circle({
		Name = "Gloss",
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromScale(0.22, 0.16),
		Size = UDim2.fromScale(0.36, 0.3),
		ZIndex = 7,
		Parent = dot,
	})

	local frameImage = Theme.icon(UiConfig.icons.balanceFrame, {
		Name = "Frame",
		Size = UDim2.fromOffset(W, H),
		ZIndex = 8,
		Parent = body,
	})
	local square = frameImage:FindFirstChildOfClass("UIAspectRatioConstraint")
	if square then
		square:Destroy() -- the frame is taller than wide, sized exactly to W x H
	end

	local danger = false
	local function set(
		tilt: number,
		groaning: boolean,
		hasTower: boolean,
		leanX: number,
		leanY: number,
		energy: number,
		stance: string
	)
		group.GroupColor3 = if hasTower then Color3.new(1, 1, 1) else GREY
		if not hasTower then
			tilt, leanX, leanY, energy, stance, groaning = 0, 0, 0, 0, "ready", false
		end
		local color = ringColor(tilt)
		setRing(tilt, color)
		-- the dot: the lean's direction on screen, at most to the ring at the tip angle
		local lean = Vector2.new(leanX, -leanY)
		if lean.Magnitude > 1 then
			lean = lean.Unit
		end
		dot.Position = UDim2.fromOffset(CX + lean.X * DOT_TRAVEL, CY + lean.Y * DOT_TRAVEL)
		dot.BackgroundColor3 = color
		-- the stance's energy as water; brighter and glowing while the stance is held, pale while it refills
		water.Size = UDim2.fromScale(1, math.clamp(energy, 0, 1))
		water.BackgroundTransparency = if stance == "active" then 0.45 elseif stance == "empty" then 0.85 else 0.7
		discGlow.Transparency = if stance == "active" then 0.1 else 1
		danger = groaning or tilt >= Tuning.groanFraction
	end

	local function step()
		if danger then
			local wave = 0.5 + 0.5 * math.sin(os.clock() * 12)
			pulse.Scale = 1 + 0.05 * wave
			glowStroke.Transparency = 0.15 + 0.5 * (1 - wave)
		else
			pulse.Scale = 1
			glowStroke.Transparency = 1
		end
	end

	return { frame = holder, group = group, set = set, step = step }
end

export type DashBar = {
	frame: Frame, -- placed by the HUD (design size ammo.width x dash.height)
	group: CanvasGroup,
	set: (share: number) -> (), -- 0 just used .. 1 ready
}

-- the bar images are 504 x 100: the slanted ends (70 px each side) and the top and bottom keep their shape
local SLICE = Rect.new(70, 49, 434, 51)
local BADGE = 24 -- the key badge left of the bar, as big as the navigation's (H, T)
local BADGE_ROOM = 16 -- left of the bar, for the sparkle's and the bump's overhang
local BAR_PAD = 4 -- under the bar, for the bump

local function barImage(image: string, props: { [string]: any }): ImageLabel
	local label = Theme.icon(image, props)
	label.ScaleType = Enum.ScaleType.Slice
	label.SliceCenter = SLICE
	label.SliceScale = UiConfig.dash.slice
	local aspect = label:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then
		aspect:Destroy() -- the bar stretches to the row's width
	end
	return label
end

function ArenaHud.dash(parent: Instance): DashBar
	local width, height = UiConfig.ammo.width, UiConfig.dash.height
	local holder = Theme.frame({ Name = "DashBar", Size = UDim2.fromOffset(width, height), Parent = parent })
	local group = Instance.new("CanvasGroup")
	group.Name = "Bar"
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	-- room round the bar for the sparkle and the bump (a CanvasGroup clips to its box)
	group.Position = UDim2.fromOffset(-BADGE_ROOM, -24)
	group.Size = UDim2.fromOffset(width + BADGE_ROOM, height + 24 + BAR_PAD)
	group.GroupTransparency = 1
	group.Visible = false
	group.Parent = holder
	local body = Theme.frame({
		Name = "Body",
		Position = UDim2.fromOffset(BADGE_ROOM, 24),
		Size = UDim2.fromOffset(width, height),
		Parent = group,
	})
	local bump = Instance.new("UIScale")
	bump.Name = "Bump"
	bump.Parent = body
	barImage(UiConfig.icons.dashEmpty, { Name = "Empty", Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = body })
	local clip = Theme.frame({
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = body,
	})
	barImage(UiConfig.icons.dashFull, {
		Name = "Full",
		Size = UDim2.fromOffset(width, height),
		ZIndex = 2,
		Parent = clip,
	})
	local sparkle = Theme.icon(UiConfig.icons.sparkle, {
		Name = "Sparkle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.fromOffset(30, 30),
		ImageTransparency = 1,
		ZIndex = 4,
		Parent = body,
	})
	-- the key badge, left of the bar with a little gap. It sits outside the CanvasGroup (text drawn inside one came out
	-- far too small) and shows while the group is more than half faded in.
	local badgeHolder = Theme.frame({
		Name = "Key",
		Size = UDim2.fromOffset(width, height),
		Visible = false,
		Parent = holder,
	})
	local badge = Buttons.badge(badgeHolder, Enum.KeyCode.Q, Enum.KeyCode.ButtonX, BADGE)
	badge.frame.Position = UDim2.fromOffset(-BADGE / 2 - 5, height / 2)
	local function syncBadge()
		badgeHolder.Visible = group.Visible and group.GroupTransparency < 0.5
	end
	group:GetPropertyChangedSignal("Visible"):Connect(syncBadge)
	group:GetPropertyChangedSignal("GroupTransparency"):Connect(syncBadge)

	local wasFull = true
	local function set(share: number)
		share = math.clamp(share, 0, 1)
		clip.Size = UDim2.fromScale(share, 1)
		local full = share >= 1
		if full and not wasFull then
			-- ready again: a little bump and the stars
			bump.Scale = 1.08
			TweenService:Create(bump, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			sparkle.ImageTransparency = 0
			sparkle.Size = UDim2.fromOffset(14, 14)
			TweenService:Create(sparkle, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(34, 34) })
				:Play()
			TweenService:Create(
				sparkle,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.35),
				{ ImageTransparency = 1 }
			):Play()
		end
		wasFull = full
	end
	set(1)
	return { frame = holder, group = group, set = set }
end

return ArenaHud
