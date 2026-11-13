-- The HUD, built from the UI kit (UiKit) and laid out by UiLayout (Screen.plan): the coins bottom left (top left on
-- touch screens, where the thumbstick sits bottom left); bottom right (on touch screens over the jump and action
-- buttons) the dash bar and, only in combat mode, the ice-ball ammo on it (three big balls, the one loading filling up,
-- the reload countdown), with the balance gauge over them (ArenaHud: lean, how close to tipping, the steady stance's
-- energy) - the gauge and the dash bar in the arena only, the gauge in the ice balls' place without combat mode; at the
-- bottom centre the tower pill (scoops of the cone's capacity, worth, steady bonus) with at most one hint above it;
-- toasts for SERVE!/SAVED!/TOPPLED!;
-- and a marker on the player's own cart. Everything stays out of the middle of the screen, where the character and
-- the tower are, and out of Roblox's touch controls. Catching and serving happen automatically.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Combat = require(Shared:WaitForChild("Combat"))
local ArenaZone = require(Shared:WaitForChild("ArenaZone"))
local Tuning = require(Config:WaitForChild("Tower"))
local CombatConfig = require(Config:WaitForChild("Combat"))
local MapConfig = require(Config:WaitForChild("Map"))
local Palette = require(Config:WaitForChild("Palette"))
local UiConfig = require(Config:WaitForChild("Ui"))

local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local ArenaHud = require(client:WaitForChild("ArenaHud"))
local Theme, Screen, Widgets = UiKit.Theme, UiKit.Screen, UiKit.Widgets

local Hud = {}

local BALL = UiConfig.ammo.ball
local FADE = 0.15 -- seconds the ice balls, the gauge and the dash bar take to fade in or out
local HINT_TEXT, HINT_TEXT_MIN = 19, 13
local PILL = 52

-- "catch" and "cart" show until the first serve; "steady" whenever the tower leans dangerously and the stance is
-- ready, so the player learns when to react.
local HINTS = {
	catch = "Stand in a landing circle to catch scoops",
	cart = "Carry your tower to your plot",
	steady = {
		touch = "It's tipping! Hold Steady",
		keyboard = "It's tipping! Hold F to steady it",
		gamepad = "It's tipping! Hold Steady",
	},
}

local COLORS = {
	outline = Theme.color("outline"),
	cream = Theme.color("cream"),
	mint = Theme.color("mint"),
	yellow = Theme.color("yellow"),
	red = Theme.color("red"),
	text = Theme.color("text"),
	textDark = Theme.color("textDark"),
	track = Theme.darker(Theme.color("chocolate"), 0.25),
}

-- toasts are asked for in the world's pastel colours (Config/Palette); on screen they take the kit's stronger ones
local TOAST_COLORS = {
	[Palette.mint] = UiConfig.colors.mint,
	[Palette.lemon] = UiConfig.colors.yellow,
	[Palette.awning] = UiConfig.colors.red,
	[Palette.strawberry] = UiConfig.colors.red,
}

local player = Players.LocalPlayer
local gui: ScreenGui
local coins: any -- UiKit.Widgets.coins
local coinsFrame: Frame
local bottom: Frame
local ammoGroup: CanvasGroup
-- per ice ball: the clip that shows how full it is (from the bottom up), the spent ball under it, whether it is full
local ammoSlots: { { slot: Frame, clip: Frame, spent: ImageLabel, full: boolean } } = {}
local ammoShown = false -- what the screen shows: true in combat mode
local registry
local gauge: ArenaHud.Gauge
local dashBar: ArenaHud.DashBar
local currentPlan: any = nil -- Screen.plan, for the gauge's two places
local gaugeHigh = false -- the gauge sits over the ice balls (combat mode)
local gaugeSlide: Tween? = nil
local arenaShown = false -- the zone's answer once it has held for the delay
local arenaPending = false
local arenaPendingSince = 0
local arenaVisible = false -- the gauge and the dash bar are up
local touchScreen = false -- the plan is for a touch screen
local reloadText: TextLabel
local towerPill: Frame
local countText: TextLabel
local worthText: TextLabel
local steadyText: TextLabel
-- the tower pill's numbers count smoothly to each new value (Widgets.counter); the capacity they are shown against
local countCounter: any
local worthCounter: any
local towerCapacity = 0
local hintHolder: Frame
local hintCard: Frame
local hintText: TextLabel
local hintMax = 400 -- the widest the hint's text may be, design pixels (Screen.plan's hintWidth)
local toastHolder: Frame
local toastLabel: TextLabel
local toastStroke: UIStroke
local cartMarker: BillboardGui
local toastTweens: { Tween } = {}

local towerCount = 0
local warning = false
local stanceState = "ready"
local hasServed = false
local atCart = false
local shownHint: string? = nil
local shownCoins: number? = nil

local function frame(props: { [string]: any }): Frame
	return Theme.frame(props)
end

-- Bottom right (on touch screens above the jump and action buttons), only in combat mode: the three ice balls, big,
-- as one overlapping row like the reference ("Drei glänzende Eiskugeln mit Streuseln"): the left one in front, each
-- next a third under the one before, a little higher and smaller. A loaded one is pink, a spent one grey (the same
-- ball with grey sprinkles); they are spent from the right. The one loading fills from grey to pink from the bottom
-- up over reloadPerBall and pops once it is ready; with none loaded the seconds to the next one show over them. The
-- strip under the row stays free for the dash bar.
local function buildAmmo()
	ammoGroup = Instance.new("CanvasGroup")
	ammoGroup.Name = "IceBalls"
	ammoGroup.BackgroundTransparency = 1
	ammoGroup.BorderSizePixel = 0
	ammoGroup.GroupTransparency = 1
	ammoGroup.Visible = false
	ammoGroup.Parent = gui
	local shape = UiConfig.ammo
	local count = CombatConfig.ammo
	for index = 1, count do
		local size = BALL * shape.shrink ^ (index - 1)
		-- the front ball draws over the ones behind it, also with global ZIndex
		local z = 2 * (count - index) + 1
		local slot = frame({
			Name = "Ball" .. index,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromOffset((index - 1) * shape.step, shape.height - (index - 1) * shape.rise),
			Size = UDim2.fromOffset(size, size),
			ZIndex = z,
			Parent = ammoGroup,
		})
		local spent = Theme.icon(Theme.icons.ammoEmpty, {
			Name = "Spent",
			Size = UDim2.fromScale(1, 1),
			ZIndex = z,
			Parent = slot,
		})
		-- the loaded ball over the spent one, clipped from the bottom up to how far it has loaded
		local clip = frame({
			Name = "Fill",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 1),
			ClipsDescendants = true,
			ZIndex = z + 1,
			Parent = slot,
		})
		Theme.icon(Theme.icons.ammo, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromOffset(size, size),
			ZIndex = z + 1,
			Parent = clip,
		})
		ammoSlots[index] = { slot = slot, clip = clip, spent = spent, full = true }
	end
	reloadText = Theme.text({
		Name = "Reload",
		FontFace = Theme.fontText,
		TextSize = 40,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.XY,
		ZIndex = 2 * count + 2,
		Visible = false,
		Parent = ammoGroup,
	})
end

-- Fades a group in or out (shown: Visible and see-through 0; hidden: see-through 1, then not Visible). One tween per
-- group at a time, so switching back halfway never leaves it stuck.
local fades: { [CanvasGroup]: Tween } = {}
local function fade(group: CanvasGroup, on: boolean)
	local running = fades[group]
	if running then
		running:Cancel()
	end
	if on then
		group.Visible = true
	end
	local tween = TweenService:Create(group, TweenInfo.new(FADE, Enum.EasingStyle.Quad), {
		GroupTransparency = if on then 0 else 1,
	})
	fades[group] = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and not on then
			group.Visible = false
		end
	end)
	tween:Play()
end

-- The gauge where the plan puts it: over the ice balls in combat mode (gaugeHigh), in their place without it; a slide
-- when it changes, a jump when the screen does.
local function placeGauge(slide: boolean)
	local plan = currentPlan
	if not plan then
		return
	end
	local rect = if gaugeHigh then plan.balance else plan.balanceLow
	local scale = if gaugeHigh then plan.balanceScale else plan.balanceLowScale
	local holder = gauge.frame
	if gaugeSlide then
		gaugeSlide:Cancel()
		gaugeSlide = nil
	end
	if not slide then
		Screen.place(holder, rect, scale)
		return
	end
	local uiScale = holder:FindFirstChild("Layout") :: UIScale
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local move = TweenService:Create(holder, info, {
		Position = UDim2.fromOffset(math.round(rect.x), math.round(rect.y)),
	})
	TweenService:Create(uiScale, info, { Scale = scale }):Play()
	gaugeSlide = move
	move:Play()
end

-- What shows bottom right, every frame:
--   * the ice balls while combat mode is on (CombatController's own state, so they go at once with every way it ends:
--     R, leaving the arena, a teleport, a knockdown, death, a respawn)
--   * the balance gauge and the dash bar in the arena (the same line and delay as the safe zone), alive
--   * the gauge over the ice balls in combat mode, in their place without it, sliding between the two
local function updateShown()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local alive = humanoid ~= nil and humanoid.Health > 0
	local combat = registry.CombatController.inCombatMode() and alive
	if combat ~= ammoShown then
		ammoShown = combat
		fade(ammoGroup, combat)
	end

	-- in the arena by the client's own check (no delay) and by the server's (InArena), so nothing shows in the hub
	-- even if one of them is off for a moment
	local inside = root ~= nil
		and ArenaZone.contains(root.Position.X, root.Position.Z, MapConfig.arena)
		and player:GetAttribute("InArena") == true
	local now = os.clock()
	if not alive then
		-- a new life starts outside: the next character has to stand in the arena for the delay first
		arenaShown, inside = false, false
	end
	if inside ~= arenaPending then
		arenaPending, arenaPendingSince = inside, now
	end
	if arenaPending ~= arenaShown and now - arenaPendingSince >= MapConfig.arena.displayDelay then
		arenaShown = arenaPending
	end
	-- dying hides them at once, not after the delay
	local arena = alive and arenaShown
	if arena ~= arenaVisible then
		arenaVisible = arena
		fade(gauge.group, arena)
		fade(dashBar.group, arena)
	end
	-- a safety net: hidden means hidden once its fade is over, whatever happened to the tween
	for _, group in { gauge.group, dashBar.group } do
		local running = fades[group]
		if not arena and group.Visible and not (running and running.PlaybackState == Enum.PlaybackState.Playing) then
			group.GroupTransparency = 1
			group.Visible = false
		end
	end
	if combat ~= gaugeHigh then
		gaugeHigh = combat
		placeGauge(true)
	end
end

-- Bottom centre, between the thumbstick and the jump button: the tower pill.
local function buildBottom()
	bottom = frame({ Name = "Bottom", Parent = gui })

	-- the tower pill: the stacked cone, the count big, worth and steady bonus small under it
	towerPill = frame({
		Name = "Tower",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -UiConfig.shadow),
		Size = UDim2.new(1, -16, 0, PILL),
		Visible = false,
		Parent = bottom,
	})
	-- the chocolate info pill with the cream glaze and the faint waffle, like the coins
	Theme.skin(towerPill, "info", PILL)
	Widgets.infoWaffle(towerPill, PILL)
	Theme.icon(Theme.icons.scoops, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, -6, 1, 2),
		Size = UDim2.fromOffset(PILL * 1.25, PILL * 1.25),
		ZIndex = 3,
		Parent = towerPill,
	})
	countText = Theme.text({
		Name = "Count",
		FontFace = Theme.fontNumbers,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(PILL + 2, 7), -- under the glaze's thickest part
		Size = UDim2.new(1, -PILL - 12, 0, 26),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		Parent = towerPill,
	})
	local details = frame({
		Name = "Details",
		Position = UDim2.new(0, PILL + 2, 1, -21),
		Size = UDim2.new(1, -PILL - 12, 0, 17),
		ZIndex = 4,
		Parent = towerPill,
	})
	local detailList = Instance.new("UIListLayout")
	detailList.FillDirection = Enum.FillDirection.Horizontal
	detailList.VerticalAlignment = Enum.VerticalAlignment.Center
	detailList.Padding = UDim.new(0, 4)
	detailList.SortOrder = Enum.SortOrder.LayoutOrder
	detailList.Parent = details
	Theme.icon(Theme.icons.coin, { Size = UDim2.fromOffset(17, 17), LayoutOrder = 1, ZIndex = 4, Parent = details })
	worthText = Theme.text({
		Name = "Worth",
		FontFace = Theme.fontNumbers,
		TextSize = 16,
		TextColor3 = COLORS.yellow,
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
		ZIndex = 4,
		Parent = details,
	})
	steadyText = Theme.text({
		Name = "Steady",
		FontFace = Theme.fontText,
		TextSize = 16,
		TextColor3 = COLORS.mint,
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 3,
		ZIndex = 4,
		Parent = details,
	})
	-- the count pops the pill when it changes; a full cone says so in red (from the count it heads for)
	countCounter = Widgets.counter(function(count)
		local full = towerCapacity > 0 and towerCount >= towerCapacity
		countText.Text = if full
			then string.format("%d/%d FULL", count, towerCapacity)
			else string.format("%d/%d", count, towerCapacity)
		countText.TextColor3 = if full then COLORS.red else COLORS.text
	end, towerPill)
	worthCounter = Widgets.counter(function(worth)
		worthText.Text = tostring(worth)
	end)

	-- the hint, over the cluster: a cream card, as wide as the space between the touch controls allows
	hintHolder = frame({ Name = "HintHolder", AnchorPoint = Vector2.new(0.5, 1), Parent = gui })
	hintCard = frame({
		Name = "Hint",
		BackgroundTransparency = 0,
		BackgroundColor3 = COLORS.cream,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Visible = false,
		Parent = hintHolder,
	})
	Theme.corner(hintCard, UDim.new(0, 14))
	Theme.outline(hintCard)
	hintText = Instance.new("TextLabel")
	hintText.Name = "Text"
	hintText.BackgroundTransparency = 1
	hintText.FontFace = Theme.fontText
	hintText.TextColor3 = COLORS.textDark
	hintText.TextWrapped = true
	hintText.AnchorPoint = Vector2.new(0.5, 0.5)
	hintText.Position = UDim2.fromScale(0.5, 0.5)
	hintText.Parent = hintCard
end

-- The hint's card sized to what it says, in design pixels (the cluster's UIScale scales it): one line as wide as the
-- words if that fits the room between the touch controls (hintMax), else two lines in the full room, else a smaller
-- size. Measured with room to spare (SLACK), so the words are never cut. No TextScaled: its size limits count in
-- screen pixels and stopped it from shrinking on small screens.
local HINT_PAD_X, HINT_PAD_Y = 14, 7
local SLACK = 1.12
local function fitHint()
	local text, font = hintText.Text, Theme.fontTextEnum
	local size, width, height = HINT_TEXT_MIN, hintMax, 0
	for candidate = HINT_TEXT, HINT_TEXT_MIN, -1 do
		size = candidate
		local natural = TextService:GetTextSize(text, candidate, font, Vector2.new(math.huge, math.huge))
		if natural.X * SLACK + 4 <= hintMax then
			width, height = natural.X * SLACK + 4, natural.Y
			break
		end
		local wrapped = TextService:GetTextSize(text, candidate, font, Vector2.new(hintMax / SLACK, math.huge))
		width, height = hintMax, wrapped.Y
		if wrapped.Y <= candidate * 2.6 then
			break
		end
	end
	hintText.TextSize = size
	height = height * 1.1 + 4
	hintText.Size = UDim2.fromOffset(width, height)
	hintCard.Size = UDim2.fromOffset(width + 2 * HINT_PAD_X, height + 2 * HINT_PAD_Y)
end

local function buildToast()
	toastHolder = frame({ Name = "ToastHolder", AnchorPoint = Vector2.new(0.5, 0), Parent = gui })
	toastLabel = Theme.text({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		TextSize = 44,
		AutomaticSize = Enum.AutomaticSize.XY,
		TextTransparency = 1,
		Parent = toastHolder,
	})
	toastStroke = toastLabel:FindFirstChildOfClass("UIStroke") :: UIStroke
	toastStroke.Thickness = 3.5
	toastStroke.Transparency = 1
end

local function buildCartMarker()
	-- BillboardGuis do not render inside a ScreenGui, so this one lives directly in PlayerGui
	cartMarker = Instance.new("BillboardGui")
	cartMarker.Name = "CartMarker"
	cartMarker.AlwaysOnTop = true
	cartMarker.ResetOnSpawn = false
	cartMarker.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	cartMarker.Size = UDim2.fromOffset(150, 46)
	cartMarker.StudsOffset = Vector3.new(0, 4.5, 0)
	cartMarker.Enabled = false
	cartMarker.Parent = gui.Parent

	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.new(1, 0, 0, 34)
	tag.BackgroundColor3 = COLORS.yellow
	tag.BorderSizePixel = 0
	tag.FontFace = Theme.fontMain
	tag.TextSize = 20
	tag.TextColor3 = COLORS.textDark
	tag.Text = "YOUR PLOT"
	tag.ZIndex = 2
	Theme.corner(tag, UDim.new(0, 12))
	Theme.outline(tag, 2.5)
	tag.Parent = cartMarker
	-- a yellow arrow tip under the tag, pointing at the cart
	local tip = Instance.new("Frame")
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromOffset(75, 34)
	tip.Size = UDim2.fromOffset(14, 14)
	tip.Rotation = 45
	tip.BackgroundColor3 = COLORS.yellow
	tip.BorderSizePixel = 0
	tip.ZIndex = 1
	Theme.outline(tip, 2.5)
	tip.Parent = cartMarker
end

local function hintFor(key: string): string
	local hint = HINTS[key]
	if type(hint) == "table" then
		return hint[Screen.input()] or hint.keyboard
	end
	return hint
end

local function setHint(key: string?)
	if key == shownHint then
		return
	end
	shownHint = key
	hintCard.Visible = key ~= nil
	if key then
		hintText.Text = hintFor(key)
		fitHint()
	end
end

local function refreshHint()
	if towerCount == 0 then
		setHint(if hasServed then nil else "catch")
	elseif warning and stanceState == "ready" then
		setHint("steady")
	elseif not hasServed and not atCart then
		setHint("cart")
	else
		setHint(nil)
	end
end

-- Every cluster where the plan puts it, scaled for the screen.
local function layout(plan)
	local scale = plan.scale
	Screen.place(coinsFrame, plan.coins, scale)
	Screen.place(bottom, plan.bottom, scale)
	Screen.place(ammoGroup, plan.ammo, plan.groupScale)
	Screen.place(dashBar.frame, plan.dash, plan.groupScale)
	touchScreen = plan.touch
	-- the worth bigger on phones, where the steady bonus beside it is left out
	worthText.TextSize = if plan.touch then 21 else 16
	if plan.touch then
		steadyText.Visible = false
	end
	currentPlan = plan
	placeGauge(false)
	-- the hint sits on the bottom cluster, the toast under the big buttons

	Screen.place(
		hintHolder,
		{ x = plan.bottom.x + plan.bottom.w / 2 - plan.hintWidth / 2, y = 0, w = plan.hintWidth, h = 1 },
		scale
	)
	hintHolder.AnchorPoint = Vector2.new(0, 1)
	hintHolder.Position = UDim2.fromOffset(
		math.round(plan.bottom.x + plan.bottom.w / 2 - plan.hintWidth / 2),
		math.round(plan.bottom.y - plan.frame.h * 0.01)
	)
	hintMax = math.max(60, plan.hintWidth / scale - 28)
	Screen.place(toastHolder, { x = plan.frame.x + plan.frame.w / 2, y = plan.toastY, w = 1, h = 1 }, scale)
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	if shownHint then
		hintText.Text = hintFor(shownHint)
		fitHint()
	end
end

function Hud.Init(reg)
	registry = reg
	gui = Screen.gui("Hud", 5)
	coinsFrame = frame({ Name = "CoinsCluster", Parent = gui })
	coins = Widgets.coins(UiConfig.coins.width, UiConfig.coins.height)
	coins.frame.Parent = coinsFrame
	buildAmmo()
	buildBottom()
	gauge = ArenaHud.gauge(gui)
	gauge.set(0, false, false, 0, 0, 0, "ready")
	dashBar = ArenaHud.dash(gui)
	buildToast()
	buildCartMarker()
	Screen.onChanged(layout)
end

function Hud.Start()
	Remotes.Served.OnClientEvent:Connect(function(who: Player)
		if who == player then
			hasServed = true
			refreshHint()
		end
	end)

	RunService.RenderStepped:Connect(function()
		local count = player:GetAttribute("IceBalls")
		local readyAt = player:GetAttribute("IceBallsReadyAt")
		local serverNow = workspace:GetServerTimeNow()
		local loaded, refill = Combat.ammoDisplay(
			if type(count) == "number" then count else CombatConfig.ammo,
			if type(readyAt) == "number" then readyAt else 0,
			serverNow,
			CombatConfig
		)
		-- loaded balls full, the one loading fills from the bottom up, the rest spent; a ball that just got full pops
		for index, ammoSlot in ammoSlots do
			local share = math.clamp(if index <= loaded then 1 elseif index == loaded + 1 then refill else 0, 0, 1)
			ammoSlot.clip.Size = UDim2.fromScale(1, share)
			local full = index <= loaded
			if full and not ammoSlot.full and ammoShown then
				UiKit.Anim.pop(ammoSlot.slot)
			end
			ammoSlot.full = full
		end
		updateShown()
		gauge.step()
		dashBar.set(registry.TowerController.dashCharge())
		local left = if type(readyAt) == "number" then readyAt - serverNow else 0
		reloadText.Visible = loaded <= 0 and left > 0
		if reloadText.Visible then
			reloadText.Text = string.format("%.1fs", left)
		end
	end)

	local leaderstats = player:WaitForChild("leaderstats")
	local coinValue = leaderstats:WaitForChild("Coins") :: IntValue
	local function update()
		coins.set(coinValue.Value, shownCoins ~= nil)
		shownCoins = coinValue.Value
	end
	coinValue.Changed:Connect(update)
	update()
end

-- count scoops of the cone's capacity; a full cone says so in red, since it takes no more until served.
function Hud.setTower(count: number, capacity: number, value: number, steady: number)
	-- the numbers count to their new values while the pill shows; appearing, it starts with them
	local animate = towerPill.Visible and count > 0
	towerCount = count
	towerPill.Visible = count > 0
	if count > 0 then
		local newCapacity = capacity ~= towerCapacity
		towerCapacity = capacity
		countCounter.set(count, animate)
		if newCapacity then
			countCounter.refresh() -- a bigger cone: the same count against the new capacity
		end
		worthCounter.set(math.floor(value), animate)
		local percent = math.floor(steady * 100 + 0.5)
		steadyText.Visible = percent > 0 and not touchScreen -- too small to read on a phone
		steadyText.Text = string.format("+%d%%", percent) -- the steady bonus, in mint
	end
	refreshHint()
end

-- tilt is the share of the tip angle; leanX/leanY the lean in screen space as a share of it (x right, y away
-- from the camera). energy is the stance bar (0..1), stance "active" (held), "ready" or "empty" (refilling below
-- the share a new stance needs).
function Hud.setBalance(
	tilt: number,
	groaning: boolean,
	visible: boolean,
	leanX: number,
	leanY: number,
	energy: number,
	stance: string
)
	-- visible: a tower is carried; the gauge itself shows in the arena either way, greyed out without one
	warning = visible and tilt >= Tuning.warnFraction
	stanceState = stance
	gauge.set(tilt, groaning, visible, leanX, leanY, energy, stance)
end

function Hud.toast(text: string, colorHex: string?)
	for _, tween in toastTweens do
		tween:Cancel()
	end
	toastLabel.Text = text
	local hex = if colorHex then TOAST_COLORS[colorHex] or colorHex else nil
	toastLabel.TextColor3 = if hex then Color3.fromHex(hex) else COLORS.text
	toastLabel.TextTransparency = 0
	toastStroke.Transparency = 0
	UiKit.Anim.pop(toastLabel)
	local fade = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.9)
	toastTweens = {
		TweenService:Create(toastLabel, fade, { TextTransparency = 1 }),
		TweenService:Create(toastStroke, fade, { Transparency = 1 }),
	}
	for _, tween in toastTweens do
		tween:Play()
	end
end

-- atCart: the player stands at the serve point, so the "carry it to your cart" hint is not needed.
function Hud.setCartTarget(part: BasePart?, isAtCart: boolean)
	cartMarker.Adornee = part
	cartMarker.Enabled = part ~= nil
	atCart = isAtCart
end

return Hud
