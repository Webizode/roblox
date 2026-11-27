--!strict
-- The touch debug overlay (Config/TouchControls debugOverlay; phone tests 26./27.11.2026: on a real phone the jump
-- button did nothing and walking with the stick seemed to turn the camera). Only for the UserIds listed there on a
-- touch screen, in Studio also with the attribute TouchDebug on Workspace. A small grey box at the screen's left edge,
-- next to the icon buttons and under the top row, shows live (jump first, so it is never cut off):
--   * the build (Version), so a phone shows whether the newest publish arrived
--   * the jump: taps the JUMP button got, its presses of Roblox's JumpAction (TouchControls) and that action's state,
--     jumps set before the physics, the humanoid's state, floor, jump values and whether jumping is allowed, how
--     often it really lifted off and how often a tap did not (with the state then), changes of the jump values or of
--     the Jumping state by any script, and what lies over the JUMP button's centre (Roblox's TouchGui and ability
--     buttons listed apart)
--   * the camera: CameraType, the modes, how fast it turns now, Roblox's own camera turn input (CameraRotationAction),
--     which finger moved while it turned (the stick's finger or a free one) and which code last wrote Camera.CFrame
--     (CombatCamera, the camera jolts, or Roblox's camera module)
--   * every finger on the screen with its number and what it started on (our button, Roblox's stick, other GUI, free)
--   * the move controls and the last few events with their time
-- A tap on its title folds it to one line and back. It never takes a touch (Interactable off), except that title.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TouchConfig = require(Shared:WaitForChild("Config"):WaitForChild("TouchControls"))

local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local Version = require(client:WaitForChild("Version"))
local CameraLog = require(client:WaitForChild("CameraLog"))
local Screen = UiKit.Screen

local TouchDebug = {}

local CONFIG = TouchConfig.debugOverlay
local TEXT_SIZE = 6 -- half of what it was (phone test 27.11.2026: the box covered the buttons, the jump lines were cut)
local TITLE_SIZE = 7
local WIDTH = 0.36 -- share of the screen's width
local player = Players.LocalPlayer
local registry: any = nil

local gui: ScreenGui? = nil
local box: Frame
local body: TextLabel
local title: TextButton
local folded = false
local shown = false

type Touch = {
	n: number,
	input: InputObject,
	start: Vector3,
	at: number,
	what: string,
	stick: boolean,
	movedFrame: number,
}
local touches: { [InputObject]: Touch } = {}
local touchCount = 0
local events: { string } = {}
local frame = 0

-- the jump
local jumpsDone = 0 -- the humanoid really entered Jumping
local lastLiftOff = 0
local pendingTap: number? = nil -- os.clock() of a tap still waiting to lift off
local noLiftOff = 0
local lastNoLiftOff = "-"

-- the camera
local yaw: number? = nil
local yawRate = 0 -- degrees per second, smoothed
local yawBefore: number? = nil -- the camera's yaw before the camera scripts ran this frame
local writer = "-" -- who changed the camera's turn last, and when
local writerAt = 0
local turner = "-" -- which finger moved while the camera turned last, and when
local turnerAt = 0
local walk = { active = false, turned = 0, time = 0 } -- the walk going on
local lastWalk = "none yet" -- the last finished walk

local function log(text: string)
	table.insert(events, 1, string.format("%7.2f %s", os.clock() % 1000, text))
	while #events > CONFIG.events do
		table.remove(events)
	end
end

local function allowed(): boolean
	if RunService:IsStudio() then
		local attribute = workspace:GetAttribute(CONFIG.attribute)
		if attribute ~= nil then
			return attribute == true
		end
	end
	return table.find(CONFIG.users, player.UserId) ~= nil and UserInputService.TouchEnabled
end

local function ours(object: Instance): boolean
	return gui ~= nil and object:IsDescendantOf(gui)
end

local function name(object: GuiObject): string
	local screenGui = object:FindFirstAncestorWhichIsA("LayerCollector")
	return (if screenGui then screenGui.Name .. "/" else "") .. object.Name
end

local function enumName(value: any): string
	return if typeof(value) == "EnumItem" then value.Name else tostring(value)
end

local function read(getter: () -> any): string
	local ok, value = pcall(getter)
	return if ok then enumName(value) else "?"
end

local function ago(at: number): string
	return if at > 0 then string.format("%.1fs ago", os.clock() - at) else "never"
end

local function yawOf(camera: Camera): number
	local look = camera.CFrame.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

-- What is under a point of the screen (in the coordinates of InputObject.Position): the first object that takes the
-- input (a button or Active), and the first object at all, both without this overlay.
local function hit(x: number, y: number): (GuiObject?, GuiObject?)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil, nil
	end
	local taker, first = nil, nil
	for _, object in playerGui:GetGuiObjectsAtPosition(x, y) do
		if not ours(object) and object.Visible then
			first = first or object
			if object:IsA("GuiButton") or object.Active then
				taker = object
				break
			end
		end
	end
	return taker, first
end

-- Roblox's touch GUIs: its TouchGui (stick, jump button) and, with its ability buttons on (CCL), the AbilitiesGui.
local function robloxGuis(): { ScreenGui }
	local found = {}
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, child in playerGui:GetChildren() do
			if child:IsA("ScreenGui") and (child.Name == "TouchGui" or child.Name == "AbilitiesGui") then
				table.insert(found, child)
			end
		end
	end
	return found
end

-- Whether a point lies on Roblox's stick: inside its frame, visible or not (the dynamic stick's frame stays invisible
-- until a finger is down, so a test for visible GUI misses it).
local function onStick(x: number, y: number): boolean
	for _, screenGui in robloxGuis() do
		for _, found in screenGui:GetDescendants() do
			if
				(found.Name == "ThumbstickFrame" or found.Name == "DynamicThumbstickFrame") and found:IsA("GuiObject")
			then
				local at, size = found.AbsolutePosition, found.AbsoluteSize
				if x >= at.X and x <= at.X + size.X and y >= at.Y and y <= at.Y + size.Y then
					return true
				end
			end
		end
	end
	return false
end

-- What a finger started on: one of our action buttons, Roblox's stick or other touch controls, other GUI, or nothing.
local function classify(input: InputObject, processed: boolean): (string, boolean)
	local x, y = input.Position.X, input.Position.Y
	local taker, first = hit(x, y)
	local touchGui = registry and registry.TouchControls and select(1, registry.TouchControls.debugInfo())
	if taker then
		if touchGui and taker:IsDescendantOf(touchGui) then
			return "button " .. taker.Name, false
		end
		local screenGui = taker:FindFirstAncestorWhichIsA("ScreenGui")
		if screenGui and (screenGui.Name == "TouchGui" or screenGui.Name == "AbilitiesGui") then
			return "roblox " .. taker.Name, onStick(x, y)
		end
		return "gui " .. name(taker), false
	end
	if onStick(x, y) then
		return "STICK", true
	end
	local under = if first then " over " .. name(first) else ""
	return (if processed then "free(processed)" else "free") .. under, false
end

-- Roblox's camera turn input this frame (its CameraRotationAction, fed by TouchDelta on a touch screen).
local function rotationInput(): Vector2?
	local module = StarterPlayer:FindFirstChild("PlayerModule")
	local contexts = module and module:FindFirstChild("InputContexts")
	local camera = contexts and contexts:FindFirstChild("CameraContext")
	local action = camera and camera:FindFirstChild("CameraRotationAction")
	if action and action:IsA("InputAction") then
		local ok, state = pcall(function()
			return action:GetState()
		end)
		if ok and typeof(state) == "Vector2" then
			return state
		end
	end
	return nil
end

-- What Roblox's camera module makes of the settings (its GetCameraMovementModeFromSettings): on a touch screen
-- (PreferredInput Touch) the Player's DevTouchCameraMode, with UserChoice the player's own setting, whose Default is
-- Follow (the camera turns with the walk). Elsewhere the computer modes, whose Default is Classic.
local function cameraModule(): string
	local ok, text = pcall(function()
		local settings = UserSettings():GetService("UserGameSettings")
		local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
		local dev = if touch then (player :: any).DevTouchCameraMode else player.DevComputerCameraMode
		local own = if touch then settings.TouchCameraMovementMode else settings.ComputerCameraMovementMode
		local picked = if dev.Name == "UserChoice" then own else dev
		local effective = if picked.Name == "Default" then (if touch then "Follow" else "Classic") else picked.Name
		return `dev={dev.Name} own={own.Name} effective={effective}`
	end)
	return if ok then text else "unreadable"
end

local function rect(object: GuiObject): string
	local at, size = object.AbsolutePosition, object.AbsoluteSize
	return string.format("%d,%d %dx%d", at.X, at.Y, size.X, size.Y)
end

local function jumpLines(lines: { string }, humanoid: Humanoid?)
	table.insert(lines, "-- jump")
	local touchGui, buttons, stats, held
	if registry and registry.TouchControls then
		touchGui, buttons, stats, held = registry.TouchControls.debugInfo()
	end
	if stats then
		table.insert(
			lines,
			`taps {stats.taps} ({ago(stats.lastTap)}) held={tostring(held)} | JumpAction presses {stats.actionPresses} reached {stats.actionReached}{if stats.actionError
					~= ""
				then " ERR " .. stats.actionError
				else ""}`
		)
		local actions = {}
		for _, action in registry.TouchControls.jumpActions() do
			table.insert(
				actions,
				`{action.Parent and action.Parent.Parent and action.Parent.Parent.Parent and action.Parent.Parent.Parent.Name or "?"}: state={read(
					function()
						return action:GetState()
					end
				)} enabled={tostring(action.Enabled)}`
			)
		end
		table.insert(lines, "JumpAction " .. (if #actions > 0 then table.concat(actions, "; ") else "NOT FOUND"))
		table.insert(
			lines,
			`Humanoid.Jump set {stats.sets}x ({ago(stats.lastSet)}){if stats.blocked ~= ""
				then " blocked: " .. stats.blocked
				else ""}`
		)
	end
	if humanoid then
		table.insert(
			lines,
			`state={humanoid:GetState().Name} floor={humanoid.FloorMaterial.Name} Jumping enabled={tostring(
				humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
			)} Jump={tostring(humanoid.Jump)}`
		)
		table.insert(
			lines,
			string.format(
				"UseJumpPower=%s JumpPower=%.0f JumpHeight=%.1f",
				tostring(humanoid.UseJumpPower),
				humanoid.JumpPower,
				humanoid.JumpHeight
			)
		)
		table.insert(
			lines,
			`lifted off {jumpsDone}x ({ago(lastLiftOff)}), taps without lift-off {noLiftOff} (last: {lastNoLiftOff})`
		)
	else
		table.insert(lines, "no humanoid")
	end
	local jumpButton = buttons and buttons.jump
	if jumpButton then
		local centre = jumpButton.AbsolutePosition + jumpButton.AbsoluteSize / 2
		local taker, first = hit(centre.X, centre.Y)
		local on = if taker == jumpButton
			then "ok"
			elseif taker then "COVERED by " .. name(taker)
			else "nothing takes it" .. (if first then " (over " .. name(first) .. ")" else "")
		table.insert(lines, `JUMP {rect(jumpButton)} visible={tostring(jumpButton.Visible)} centre: {on}`)
	end
	-- Roblox's own touch GUIs and anything of theirs that shows (an invisible one takes no tap)
	local parts = {}
	for _, screenGui in robloxGuis() do
		local visible = {}
		for _, found in screenGui:GetDescendants() do
			if found:IsA("GuiButton") and found.Visible then
				table.insert(visible, found.Name)
			end
		end
		table.insert(
			parts,
			`{screenGui.Name}(on={tostring(screenGui.Enabled)} order={screenGui.DisplayOrder}) buttons shown: {if #visible
					> 0
				then table.concat(visible, ",")
				else "none"}`
		)
	end
	table.insert(lines, if #parts > 0 then table.concat(parts, " | ") else "no Roblox touch GUI")
	if touchGui then
		local inset = GuiService:GetGuiInset()
		table.insert(lines, string.format("inset %d,%d safe area %s", inset.X, inset.Y, rect(touchGui :: any)))
	end
end

local function cameraLines(lines: { string }, humanoid: Humanoid?)
	local camera = workspace.CurrentCamera
	table.insert(lines, "-- camera")
	table.insert(
		lines,
		`type={read(function()
			return camera.CameraType
		end)} {cameraModule()} autoRotate={if humanoid then tostring(humanoid.AutoRotate) else "-"}`
	)
	local input = rotationInput()
	table.insert(
		lines,
		string.format(
			"turning %+.0f deg/s, Roblox turn input %s",
			yawRate,
			if input then string.format("%.2f,%.2f", input.X, input.Y) else "-"
		)
	)
	table.insert(lines, `last turned by: {writer} ({ago(writerAt)})`)
	table.insert(lines, `finger moving then: {turner} ({ago(turnerAt)})`)
	table.insert(
		lines,
		`walk now {if walk.active then string.format("%.0f deg in %.1fs", walk.turned, walk.time) else "-"}, last {lastWalk}`
	)
end

local function touchLines(lines: { string })
	local active = {}
	for _, touch in touches do
		table.insert(active, touch)
	end
	table.sort(active, function(a, b)
		return a.n < b.n
	end)
	local parts = {}
	for _, touch in active do
		table.insert(
			parts,
			string.format("#%d %s%s", touch.n, touch.what, if touch.movedFrame == frame then "*" else "")
		)
	end
	table.insert(lines, `-- touches {#active}: {table.concat(parts, " | ")} (* moving)`)
end

local function text(): string
	local lines = { Version.text() }
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local settings = UserSettings():GetService("UserGameSettings")
	jumpLines(lines, humanoid)
	cameraLines(lines, humanoid)
	touchLines(lines)
	table.insert(
		lines,
		`-- move: devTouchMove={read(function()
			return player.DevTouchMovementMode
		end)} own={read(function()
			return settings.TouchMovementMode
		end)} moveDir={if humanoid then string.format("%.2f", humanoid.MoveDirection.Magnitude) else "-"}`
	)
	table.insert(lines, "-- events")
	for _, event in events do
		table.insert(lines, event)
	end
	return table.concat(lines, "\n")
end

-- At the left edge, right of the icon buttons and under the top row (the HUD's plan), so it covers no button.
local function place(plan: any)
	if not plan then
		return
	end
	local x = if plan.column then plan.column.x + plan.column.w + 6 else 8
	local topBar = if plan.topbar then plan.topbar.height else 44
	local y = topBar + 4
	if plan.top then
		y = math.max(y, plan.top.y + plan.top.h + 4)
	end
	box.Position = UDim2.fromOffset(x, y)
end

local function build()
	local made = Screen.gui("TouchDebug", 1000)
	box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0, 0)
	box.Position = UDim2.fromOffset(8, 48)
	box.Size = UDim2.fromScale(WIDTH, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundColor3 = Color3.new(0, 0, 0)
	box.BackgroundTransparency = 0.55
	box.BorderSizePixel = 0
	box.Interactable = false
	box.Parent = made
	Screen.onChanged(place)
	place(Screen.plan())
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = box

	title = Instance.new("TextButton")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, TITLE_SIZE + 4)
	title.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
	title.BackgroundTransparency = 0.2
	title.BorderSizePixel = 0
	title.TextColor3 = Color3.new(1, 1, 1)
	title.FontFace = Font.fromEnum(Enum.Font.RobotoMono)
	title.TextSize = TITLE_SIZE
	title.Text = "TOUCH DEBUG (tap to fold)"
	title.Interactable = true
	title.Parent = box
	title.Activated:Connect(function()
		folded = not folded
		body.Visible = not folded
		title.Text = if folded then "TOUCH DEBUG (tap to open)" else "TOUCH DEBUG (tap to fold)"
	end)

	body = Instance.new("TextLabel")
	body.Name = "Body"
	body.LayoutOrder = 2
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.TextColor3 = Color3.new(1, 1, 1)
	body.FontFace = Font.fromEnum(Enum.Font.RobotoMono)
	body.TextSize = TEXT_SIZE
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Interactable = false
	body.Parent = box
	gui = made
end

local function update()
	local want = allowed()
	if want and not gui then
		build()
	end
	shown = want
	if gui then
		gui.Enabled = want
	end
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			jumpsDone += 1
			lastLiftOff = os.clock()
			pendingTap = nil
			log("lifted off")
		end
	end)
	-- any script that changes the jump values or switches jumping off shows here (only the server sets them, once)
	for _, property in { "JumpPower", "JumpHeight", "UseJumpPower" } do
		humanoid:GetPropertyChangedSignal(property):Connect(function()
			log(`{property} -> {tostring((humanoid :: any)[property])}`)
		end)
	end
	humanoid.StateEnabledChanged:Connect(function(state, enabled)
		if state == Enum.HumanoidStateType.Jumping then
			log(`Jumping enabled -> {tostring(enabled)}`)
		end
	end)
end

-- Before the camera scripts: the camera's turn so far.
local function beforeCamera()
	CameraLog.nextFrame()
	local camera = workspace.CurrentCamera
	yawBefore = if camera then yawOf(camera) else nil
end

-- After all camera scripts: whether this frame turned the camera, who did it, and which finger moved meanwhile.
local function afterCamera(dt: number)
	local camera = workspace.CurrentCamera
	if not camera or dt <= 0 then
		return
	end
	frame += 1
	local now = yawOf(camera)
	local delta = 0
	if yaw then
		delta = (now - yaw + 540) % 360 - 180
	end
	yaw = now
	yawRate += (delta / dt - yawRate) * math.min(1, dt * 8)

	local turnedHere = 0
	if yawBefore then
		turnedHere = math.abs((now - yawBefore + 540) % 360 - 180)
	end
	if turnedHere > 0.05 or math.abs(delta) > 0.05 then
		local own, _, thisFrame = CameraLog.last()
		writer = if thisFrame then own else "Roblox camera module"
		writerAt = os.clock()
		local moving = {}
		for _, touch in touches do
			if touch.movedFrame >= frame - 1 then
				table.insert(moving, `#{touch.n} {if touch.stick then "STICK" else touch.what}`)
			end
		end
		if #moving > 0 then
			turner = table.concat(moving, ", ")
			turnerAt = os.clock()
		end
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local walking = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.1
	if walking then
		if not walk.active then
			walk.active, walk.turned, walk.time = true, 0, 0
		end
		walk.turned += math.abs(delta)
		walk.time += dt
	elseif walk.active then
		walk.active = false
		lastWalk = string.format("%.0f deg in %.1fs", walk.turned, walk.time)
		if walk.time > 0.3 then
			log("walk ended: " .. lastWalk)
		end
	end

	-- a tap that has not lifted off within 0.4 s: note the state it was in
	if pendingTap and os.clock() - pendingTap > 0.4 then
		pendingTap = nil
		noLiftOff += 1
		lastNoLiftOff = if humanoid
			then `{humanoid:GetState().Name} on {humanoid.FloorMaterial.Name}`
			else "no humanoid"
		log("tap without lift-off: " .. lastNoLiftOff)
	end
end

function TouchDebug.Init(reg)
	registry = reg
end

function TouchDebug.Start()
	update()
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal(CONFIG.attribute):Connect(update)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if not shown or input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		touchCount += 1
		local what, stick = classify(input, processed)
		local touch: Touch = {
			n = touchCount,
			input = input,
			start = input.Position,
			at = os.clock(),
			what = what,
			stick = stick,
			movedFrame = -1,
		}
		touches[input] = touch
		log(string.format("touch #%d began at %d,%d: %s", touch.n, input.Position.X, input.Position.Y, what))
	end)
	UserInputService.InputChanged:Connect(function(input)
		local touch = touches[input]
		if touch then
			touch.movedFrame = frame + 1 -- counted for the frame being drawn next
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local touch = touches[input]
		if touch then
			touches[input] = nil
			log(string.format("touch #%d ended after %.2fs", touch.n, os.clock() - touch.at))
		end
	end)

	RunService:BindToRenderStep("WobbleTouchDebugBefore", Enum.RenderPriority.Camera.Value - 1, function()
		if shown then
			beforeCamera()
		end
	end)
	local lastTaps, lastPresses, elapsed = 0, 0, 0
	local lastMode = ""
	RunService:BindToRenderStep("WobbleTouchDebugAfter", Enum.RenderPriority.Last.Value, function(dt)
		if not shown then
			return
		end
		afterCamera(dt)
		local stats = registry.TouchControls and select(3, registry.TouchControls.debugInfo())
		if stats then
			if stats.taps ~= lastTaps then
				lastTaps = stats.taps
				pendingTap = os.clock()
				log("JUMP tapped")
			end
			if stats.actionPresses ~= lastPresses then
				lastPresses = stats.actionPresses
				log(`JumpAction pressed ({stats.actionReached} reached)`)
			end
		end
		local mode = cameraModule()
		if mode ~= lastMode then
			lastMode = mode
			log("camera: " .. mode)
		end
		elapsed += dt
		if elapsed >= CONFIG.interval and not folded then
			elapsed = 0
			body.Text = text()
		end
	end)

	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
end

return TouchDebug
