--!strict
-- The touch debug overlay (Config/TouchControls debugOverlay; phone tests 26./27.11.2026: on a real phone the jump
-- button did nothing, fixed in TouchControls, and walking with the stick turns the camera). Only for the UserIds listed
-- there on a touch screen, in Studio also with the attribute TouchDebug on Workspace. A small grey box in the top left
-- corner, away from THROW and the action buttons, shows live and compact:
--   * the build (Version), so a phone shows whether the newest publish arrived
--   * how fast the camera turns now and Roblox's own camera turn input (its CameraRotationAction)
--   * which code last turned the camera (CombatCamera, the camera jolts, or Roblox's camera module; CameraLog)
--   * which finger moved while the camera turned: the stick's finger (found by the stick's frame, which stays
--     invisible until touched) or a free one
--   * in combat mode: how fast each source turns combat mode's own camera (touch, mouse, pad, aim assist), which
--     finger's drag turned it last, how far the body faces from the camera and how often AutoRotate came back on
--   * every finger on the screen with its number, what it started on (our button, Roblox's stick, other GUI, free)
--     and what it is to the combat camera (cam=camera turns it; stick, left, button never do)
-- The events (jump taps, lift-offs, touches, changes of the jump values) are still logged, not shown. A tap on its
-- title folds it to one line and back. It never takes a touch (Interactable off), except that title.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TouchConfig = require(Shared:WaitForChild("Config"):WaitForChild("TouchControls"))

local client = script.Parent.Parent
local UiKit = require(client:WaitForChild("UiKit"))
local Version = require(client:WaitForChild("Version"))
local CameraLog = require(client:WaitForChild("CameraLog"))
local CombatCamera = require(client:WaitForChild("CombatCamera"))
local Screen = UiKit.Screen

local TouchDebug = {}

local CONFIG = TouchConfig.debugOverlay
local TEXT_SIZE = 5 -- small (phone tests 27.11.2026: the box covered THROW and the buttons, the camera lines were cut)
local TITLE_SIZE = 6
local WIDTH = 0.3 -- share of the screen's width
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

local function cameraLines(lines: { string })
	local input = rotationInput()
	table.insert(
		lines,
		string.format(
			"turning %+.0f deg/s (Roblox input %s)",
			yawRate,
			if input then string.format("%.2f,%.2f", input.X, input.Y) else "-"
		)
	)
	table.insert(lines, `last turned by: {writer} ({ago(writerAt)})`)
	table.insert(lines, `finger moving then: {turner} ({ago(turnerAt)})`)
end

local function touchLines(lines: { string })
	local active = {}
	for _, touch in touches do
		table.insert(active, touch)
	end
	table.sort(active, function(a, b)
		return a.n < b.n
	end)
	local roles = select(5, CombatCamera.debugInfo())
	local parts = {}
	for _, touch in active do
		local role = roles[touch.input]
		table.insert(
			parts,
			string.format(
				"#%d %s%s%s",
				touch.n,
				touch.what,
				if role then " cam=" .. role else "",
				if touch.movedFrame == frame then "*" else ""
			)
		)
	end
	table.insert(lines, `touches {#active}: {table.concat(parts, " | ")} (* moving)`)
end

-- Combat mode's own camera (CombatCamera): how fast each source turns it, which finger's drag turned it last, how far
-- the body faces from the camera and how often AutoRotate came back on.
local function combatLines(lines: { string })
	local running, rates, fingers, fingersAt, roles, resets, apart = CombatCamera.debugInfo()
	if not running then
		table.insert(lines, "combat cam: off")
		return
	end
	table.insert(
		lines,
		string.format(
			"COMBAT CAM touch %+.0f mouse %+.0f pad %+.0f assist %+.0f deg/s | body-cam %.0f deg, AutoRotate back on %dx",
			rates.touch,
			rates.mouse,
			rates.pad,
			rates.assist,
			apart,
			resets
		)
	)
	local names = {}
	for _, input in fingers do
		local touch = touches[input]
		table.insert(names, `#{if touch then touch.n else "?"} {roles[input] or "gone"}`)
	end
	table.insert(
		lines,
		`combat cam turned by finger: {if #names > 0 then table.concat(names, ", ") else "-"} ({ago(fingersAt)})`
	)
end

local function text(): string
	local lines = { Version.text() }
	combatLines(lines)
	cameraLines(lines)
	touchLines(lines)
	return table.concat(lines, "\n")
end

-- In the top left corner, right under Roblox's top bar: away from THROW and the action buttons (bottom right).
local function place(plan: any)
	local topBar = if plan and plan.topbar then plan.topbar.height else 44
	box.Position = UDim2.fromOffset(4, topBar + 2)
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
