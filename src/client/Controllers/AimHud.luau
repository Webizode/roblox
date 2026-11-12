-- The crosshair, only in combat mode: one clean thin circle fixed in the middle of the screen, where every throw aims.
-- Its size comes from AimRules (bigger while moving, sprinting, after a dash and right after a throw, a little smaller
-- while a throw is held). It stays white; a hit of the local player flashes a red X in it, a headshot a bigger gold
-- one (feedback.headshotMark).
--
-- While the throw button is held (mouse, trigger or the touch Throw button alike) the charge arc shows right of it,
-- after the reference "Glänzende Eiscreme-Bogenmeter nach rechts": the arc fills from the cone up to the icing with
-- the same pulse the throw uses (Combat.pulse: up in perfect.rise, down again, again and again), from a white glaze to
-- pink on the way up and paler on the way down. A green mark at its top shows the perfect window
-- (an image made for Combat.perfectShare: exactly where Combat.isPerfect says yes); while letting go would be a perfect throw the whole
-- arc glows green with a little sparkle. A tap (a hold shorter than SHOW_AFTER) shows nothing. Display only: the
-- timing, the window and the strength are the throw's own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Combat = require(Shared:WaitForChild("Combat"))
local Config = Shared:WaitForChild("Config")
local CombatConfig = require(Config:WaitForChild("Combat"))
local UiConfig = require(Config:WaitForChild("Ui"))

local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))

local AimHud = {}

local Look = CombatConfig.crosshair
local MARK = Ui.color("red")
local HEADSHOT = Ui.color("yellow")
local COLOR = Ui.color("white") -- fixed: the crosshair is not a setting

-- the arc, screen pixels: its height, and its width from the images (359 x 710)
-- sizes are for a 720 px high screen and scale with the screen's height (SCALE_MIN..SCALE_MAX), the same on PC, phone
-- and TV
local ARC_H = 170
local ARC_W = ARC_H * 359 / 710
local ARC_GAP = 14 -- from the crosshair's ring to the arc
local CROSS_SCALE = 1.7 -- the crosshair drawn this much bigger than AimRules' radius (pixels at 720 px high)
local SCALE_MIN, SCALE_MAX = 0.6, 1.5
-- where the fill runs in the images, as shares of their height: from the cone (bottom) to the icing (top)
local FILL_BOTTOM, FILL_TOP = 578 / 710, 145 / 710
local SHOW_AFTER = 0.12 -- seconds held before the arc shows: a tap throws without it
local FADE_IN = 0.08
local ONE_FRAME = 1 / 30 -- seconds: a slow frame, the most the shown arc can be behind the release

local holder: Frame
local outer: Frame
local outerStroke: UIStroke
local mark: Frame
local markUntil = 0
local markBars: { Frame } = {}

local arcHolder: Frame
local arcScale: UIScale
local shadow: ImageLabel
local arc: CanvasGroup
local pinkFill: ImageLabel
local perfectArc: ImageLabel
local sparkle: ImageLabel
local pop: UIScale
local setFill: (low: number, high: number) -> ()
local wasPerfect = false

-- A thin ring centred on the holder: a light line with a faint dark edge, so it reads on sky, sand and ice cream.
local function ring(name: string): (Frame, UIStroke)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundTransparency = 1
	Ui.corner(frame, UDim.new(0.5, 0))
	local line = Ui.stroke(frame, "white", Look.thickness, 0.05)
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Position = UDim2.fromScale(0.5, 0.5)
	edge.Size = UDim2.new(1, Look.thickness * 2, 1, Look.thickness * 2)
	edge.BackgroundTransparency = 1
	Ui.corner(edge, UDim.new(0.5, 0))
	Ui.stroke(edge, "outline", 1, 0.6)
	edge.Parent = frame
	frame.Parent = holder
	return frame, line
end

local function bar(rotation: number): Frame
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale(0.5, 0.5)
	line.Size = UDim2.new(1, 0, 0, 2)
	line.Rotation = rotation
	line.BackgroundColor3 = MARK
	line.BorderSizePixel = 0
	return line
end

local function image(name: string, asset: string, z: number, parent: Instance): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Image = asset
	label.ScaleType = Enum.ScaleType.Stretch
	label.Size = UDim2.fromOffset(ARC_W, ARC_H)
	label.ZIndex = z
	label.Parent = parent
	return label
end

-- A frame that shows only the arc's band between two fill shares (0 the cone, 1 the icing): the image inside keeps
-- its place on the arc, so the curved shape stays.
local function band(name: string, z: number): (Frame, (low: number, high: number) -> ())
	local clip = Instance.new("Frame")
	clip.Name = name
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.ZIndex = z
	clip.Parent = arc
	local function set(low: number, high: number)
		local range = (FILL_BOTTOM - FILL_TOP) * ARC_H
		local bottom = FILL_BOTTOM * ARC_H - low * range
		local top = FILL_BOTTOM * ARC_H - high * range
		clip.Position = UDim2.fromOffset(0, top)
		clip.Size = UDim2.fromOffset(ARC_W, math.max(0, bottom - top))
		for _, child in clip:GetChildren() do
			if child:IsA("ImageLabel") then
				child.Position = UDim2.fromOffset(0, -top)
			end
		end
	end
	return clip, set
end

local function buildArc()
	-- the holder takes the screen's scale; a soft dark copy of the arc behind it keeps it readable on sand and sky
	arcHolder = Instance.new("Frame")
	arcHolder.Name = "ChargeArcHolder"
	arcHolder.BackgroundTransparency = 1
	arcHolder.AnchorPoint = Vector2.new(0, 0.5)
	arcHolder.Size = UDim2.fromOffset(ARC_W, ARC_H)
	arcHolder.Visible = false
	arcHolder.Parent = holder
	arcScale = Instance.new("UIScale")
	arcScale.Parent = arcHolder
	shadow = image("Shadow", UiConfig.icons.arcFrame, 0, arcHolder)
	shadow.ImageColor3 = Color3.new(0, 0, 0)
	shadow.Position = UDim2.fromOffset(2, 3)

	arc = Instance.new("CanvasGroup")
	arc.Name = "ChargeArc"
	arc.BackgroundTransparency = 1
	arc.Size = UDim2.fromScale(1, 1)
	arc.GroupTransparency = 1
	arc.ZIndex = 1
	arc.Parent = arcHolder
	pop = Instance.new("UIScale")
	pop.Parent = arc

	image("Frame", UiConfig.icons.arcFrame, 1, arc)
	-- the fill: the white glaze with the pink over it, pink as it rises
	local fillClip
	fillClip, setFill = band("Fill", 2)
	image("White", UiConfig.icons.arcFillWhite, 2, fillClip)
	pinkFill = image("Pink", UiConfig.icons.arcFill, 3, fillClip)
	-- the perfect window: a green mark in the fill's own shape, from under the cap down to where perfect starts
	-- (the image is made for Combat.perfectShare, see the test), soft at its lower end; never outside the outline
	local markImage = image("PerfectMark", UiConfig.icons.arcMark, 4, arc)
	markImage.ImageTransparency = 0.15
	-- a perfect moment: the fill itself turns green (as high as it is), with a little star at the top
	perfectArc = image("Perfect", UiConfig.icons.arcFillGreen, 5, fillClip)
	perfectArc.Visible = false
	sparkle = Instance.new("ImageLabel")
	sparkle.Name = "Sparkle"
	sparkle.BackgroundTransparency = 1
	sparkle.Image = UiConfig.icons.sparkle
	sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
	sparkle.Position = UDim2.fromOffset(ARC_W * 0.42, ARC_H * (FILL_TOP + 0.06))
	sparkle.Size = UDim2.fromOffset(ARC_W * 0.5, ARC_W * 0.5)
	sparkle.ZIndex = 7
	sparkle.Visible = false
	sparkle.Parent = arc
	setFill(0, 0)
	-- loaded at the start, so the first charge already shows the whole arc
	task.spawn(function()
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(arc:GetDescendants())
		end)
	end)
end

function AimHud.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Aim"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- centred on the viewport, the point the throw aims through
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	holder = Instance.new("Frame")
	holder.Name = "Crosshair"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(0, 0)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui

	outer, outerStroke = ring("Outer")
	buildArc()

	mark = Instance.new("Frame")
	mark.Name = "HitMark"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromOffset(14, 14)
	mark.Visible = false
	local a, b = bar(45), bar(-45)
	a.Parent, b.Parent = mark, mark
	markBars = { a, b }
	mark.Parent = holder
end

-- The local player's throw hit somebody: the red X flashes in the crosshair; a headshot shows a bigger, thicker gold
-- X for longer.
function AimHud.mark(headshot: boolean?)
	local look = CombatConfig.feedback
	local size = if headshot then look.headshotMark.size else 14
	mark.Size = UDim2.fromOffset(size, size)
	for _, line in markBars do
		line.BackgroundColor3 = if headshot then HEADSHOT else MARK
		line.Size = UDim2.new(1, 0, 0, if headshot then look.headshotMark.thickness else 2)
	end
	markUntil = os.clock() + (if headshot then look.headshotMark.time else look.markTime)
end

-- The charge arc for a hold of `held` seconds (nil: not held).
local function showArc(held: number?, ring: number, scale: number)
	if held == nil or held < SHOW_AFTER then
		arcHolder.Visible = false
		perfectArc.Visible = false
		sparkle.Visible = false
		wasPerfect = false
		return
	end
	arcHolder.Visible = true
	arcScale.Scale = scale
	arcHolder.Position = UDim2.fromOffset(ring + ARC_GAP * scale, 0)
	arc.GroupTransparency = 1 - math.clamp((held - SHOW_AFTER) / FADE_IN, 0, 1)
	shadow.ImageTransparency = 0.55 + 0.45 * arc.GroupTransparency
	local share = Combat.pulse(held, CombatConfig)
	setFill(0, share)
	if Combat.falling(held, CombatConfig) then
		-- past the top: paler, the next chance comes on the way up again
		pinkFill.ImageTransparency = 0.6
	else
		pinkFill.ImageTransparency = 1 - share -- from the white glaze to pink
	end
	-- green only if letting go during the next frame is perfect too: the screen is a frame behind the release, so a
	-- green arc is always a perfect throw (at the window's edges it shows a frame late or goes a frame early)
	local perfect = Combat.isPerfect(held, CombatConfig) and Combat.isPerfect(held + ONE_FRAME, CombatConfig)
	perfectArc.Visible = perfect
	sparkle.Visible = perfect
	if perfect and not wasPerfect then
		pop.Scale = 1.15
		TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	wasPerfect = perfect
end

-- Called every frame. `active` shows the crosshair (combat mode), `ready` dims it while no throw is possible (empty
-- load); `radius` is its size (AimRules), `held` the seconds the throw button is held (nil: not held).
function AimHud.set(active: boolean, ready: boolean, radius: number, held: number?)
	holder.Visible = active
	if not active then
		return
	end
	-- the crosshair and the arc in proportion to the screen's height
	local camera = workspace.CurrentCamera
	local scale = math.clamp((if camera then camera.ViewportSize.Y else 720) / 720, SCALE_MIN, SCALE_MAX)
	local ring = radius * CROSS_SCALE * scale
	outer.Size = UDim2.fromOffset(ring * 2, ring * 2)
	outerStroke.Color = COLOR
	outerStroke.Thickness = Look.thickness * CROSS_SCALE * scale
	outerStroke.Transparency = if ready then 0.05 else 0.6
	showArc(held, ring, scale)
	mark.Visible = os.clock() < markUntil
end

return AimHud
