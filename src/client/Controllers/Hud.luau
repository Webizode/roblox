-- The HUD, built from the UI kit (UiKit) and laid out by UiLayout (Screen.plan): the coins bottom left (top left on
-- touch screens, where the thumbstick sits bottom left); bottom right (on touch screens over the jump and action
-- buttons) the dash bar and, only in combat mode, the ice-ball ammo on it (three big balls, the one loading filling up,
-- the reload countdown), with the balance gauge over them (ArenaHud: lean, how close to tipping, the steady stance's
-- energy) - the gauge and the dash bar in the arena only, the gauge in the ice balls' place without combat mode; at the
-- bottom centre the tower pill (scoops of the cone's capacity, worth, steady bonus). Short messages go through
-- UiKit.Toast, the way to the own plot through PlotGuide. Everything stays out of the middle of the screen, where the character and
-- the tower are, and out of Roblox's touch controls. Catching and serving happen automatically.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Combat = require(Shared:WaitForChild("Combat"))
local ArenaZone = require(Shared:WaitForChild("ArenaZone"))
local Tuning = require(Config:WaitForChild("Tower"))
local CombatConfig = require(Config:WaitForChild("Combat"))
local MapConfig = require(Config:WaitForChild("Map"))
local UiConfig = require(Config:WaitForChild("Ui"))

local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local ArenaHud = require(client:WaitForChild("ArenaHud"))
local Theme, Screen, Widgets, Toast = UiKit.Theme, UiKit.Screen, UiKit.Widgets, UiKit.Toast

local Hud = {}

local BALL = UiConfig.ammo.ball
local FADE = 0.15 -- seconds the ice balls, the gauge and the dash bar take to fade in or out

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

local towerCount = 0
local warning = false -- the tower tips dangerously while Steady could save it (TIPPING!)
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

	-- the tower pill (Widgets.infoPill, like the coins): the stacked cone, then in one row the count big, the coin with
	-- the worth, and on bigger screens the steady bonus; the pill is as long as the row
	local L = UiConfig.infoPill
	local tower = Widgets.infoPill("Tower", Theme.icons.scoops)
	towerPill = tower.frame
	towerPill.AnchorPoint = Vector2.new(0.5, 1)
	towerPill.Position = UDim2.new(0.5, 0, 1, -UiConfig.shadow)
	towerPill.Visible = false
	towerPill.Parent = bottom
	countText = Widgets.pillNumber(tower.row, "Count", L.text, 1)
	local worth = Theme.frame({
		Name = "Worth",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, L.worthIcon),
		LayoutOrder = 2,
		Parent = tower.row,
	})
	local worthList = Instance.new("UIListLayout")
	worthList.FillDirection = Enum.FillDirection.Horizontal
	worthList.VerticalAlignment = Enum.VerticalAlignment.Center
	worthList.Padding = UDim.new(0, 4)
	worthList.SortOrder = Enum.SortOrder.LayoutOrder
	worthList.Parent = worth
	Theme.icon(Theme.icons.coin, {
		Size = UDim2.fromOffset(L.worthIcon, L.worthIcon),
		LayoutOrder = 1,
		ZIndex = 5,
		Parent = worth,
	})
	worthText = Widgets.pillNumber(worth, "Amount", L.worthText, 2)
	worthText.TextColor3 = COLORS.yellow
	steadyText = Theme.text({
		Name = "Steady",
		FontFace = Theme.fontText,
		TextSize = L.steadyText,
		TextColor3 = COLORS.mint,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, L.steadyText + 4),
		LayoutOrder = 3,
		Visible = false,
		Parent = tower.row,
	}) -- the count pops the pill when it changes; a full cone says so in red (from the count it heads for)
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
end

-- Every cluster where the plan puts it, scaled for the screen.
local function layout(plan)
	local scale = plan.scale
	Screen.place(coinsFrame, plan.coins, scale)
	Screen.place(bottom, plan.bottom, scale)
	Screen.place(ammoGroup, plan.ammo, plan.groupScale)
	Screen.place(dashBar.frame, plan.dash, plan.groupScale)
	touchScreen = plan.touch
	-- on phones the steady bonus is left out of the tower pill
	if plan.touch then
		steadyText.Visible = false
	end
	currentPlan = plan
	placeGauge(false)
end

function Hud.Init(reg)
	registry = reg
	gui = Screen.gui("Hud", 5)
	coinsFrame = frame({ Name = "CoinsCluster", Parent = gui })
	coins = Widgets.coins()
	coins.frame.AnchorPoint = Vector2.new(0, 0.5) -- on the cluster's left edge, its middle; it grows to the right
	coins.frame.Position = UDim2.fromScale(0, 0.5)
	coins.frame.Parent = coinsFrame
	buildAmmo()
	buildBottom()
	gauge = ArenaHud.gauge(gui)
	gauge.set(0, false, false, 0, 0, 0, "ready")
	dashBar = ArenaHud.dash(gui)
	Screen.onChanged(layout)
end

function Hud.Start()
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
	-- the moment the tower starts tipping dangerously while Steady could save it: a short warning (the tutorial teaches
	-- what to do; the gauge shows it all along)
	local tipping = visible and tilt >= Tuning.warnFraction and stance == "ready"
	if tipping and not warning then
		Toast.show("TIPPING!", "warn", "scoops")
	end
	warning = tipping
	gauge.set(tilt, groaning, visible, leanX, leanY, energy, stance)
end

return Hud
