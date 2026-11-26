--!strict
-- The touch debug overlay (Config/TouchControls debugOverlay; phone test 26.11.2026: on a real phone the jump button
-- did nothing and walking with the stick turned the camera). Only for the UserIds listed there on a touch screen, in
-- Studio also with the attribute TouchDebug on Workspace. A grey box at the top shows live:
--   * the build (Version), so a phone shows whether the newest publish arrived
--   * the camera: CameraType, the Player's DevTouchCameraMode (its copy of StarterPlayer's DevTouchCameraMovementMode),
--     the player's own setting in Roblox's menu, what Roblox's camera module made of them (follow camera or not), how
--     fast the camera turns and how far it turned during the last walk without a camera finger (0 with Classic)
--   * the move controls: Roblox's DevTouchMovementMode and own setting, which of Roblox's touch frames exist (a second
--     stick shows here) and whether Roblox's jump button is hidden
--   * the jump: taps the JUMP button got (TouchControls), jumps set before the physics, Humanoid.Jump right after, why a
--     wanted jump was not set, the humanoid's state, floor, jump power and whether jumping is allowed, how often it
--     really jumped
--   * the safe area and the jump button's place, and what lies on top of its centre (something there swallows taps)
--   * every finger on the screen: where it started, what it hit (our button, Roblox's stick, other GUI or the camera)
--   * the last few events with their time
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
local Screen = UiKit.Screen

local TouchDebug = {}

local CONFIG = TouchConfig.debugOverlay
local player = Players.LocalPlayer
local registry: any = nil

local gui: ScreenGui? = nil
local body: TextLabel
local title: TextButton
local folded = false
local shown = false

type Touch = { n: number, input: InputObject, start: Vector3, at: number, what: string }
local touches: { [InputObject]: Touch } = {}
local touchCount = 0
local events: { string } = {}

local jumpsDone = 0 -- the humanoid really entered Jumping
local yaw: number? = nil
local yawRate = 0 -- degrees per second, smoothed
local walk = { active = false, turned = 0, time = 0, cameraFinger = false } -- the walk going on
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

-- What a finger started on: one of our action buttons, Roblox's touch controls, other GUI, or nothing (the camera).
local function classify(input: InputObject, processed: boolean): string
	local taker, first = hit(input.Position.X, input.Position.Y)
	local touchGui = registry and registry.TouchControls and select(1, registry.TouchControls.debugInfo())
	if taker then
		if touchGui and taker:IsDescendantOf(touchGui) then
			return "button " .. taker.Name
		end
		local screenGui = taker:FindFirstAncestorWhichIsA("ScreenGui")
		if screenGui and screenGui.Name == "TouchGui" then
			return "roblox " .. taker.Name
		end
		return "gui " .. name(taker)
	end
	local under = if first then " (over " .. name(first) .. ")" else ""
	return (if processed then "processed, no gui" else "camera") .. under
end

local function enumName(value: any): string
	return if typeof(value) == "EnumItem" then value.Name else tostring(value)
end

local function read(getter: () -> any): string
	local ok, value = pcall(getter)
	return if ok then enumName(value) else "?"
end

-- the Player's copy of StarterPlayer.DevTouchCameraMovementMode, taken at the join: on the Player it is called
-- DevTouchCameraMode, and it is what Roblox's camera module reads
local function playerTouchCamera(): string
	return read(function()
		return (player :: any).DevTouchCameraMode
	end)
end

-- What Roblox's camera module makes of the settings (its GetCameraMovementModeFromSettings, PlayerModule of 2025): on
-- a touch screen (PreferredInput Touch, not TouchEnabled) the Player's DevTouchCameraMode, and with UserChoice the
-- player's own setting, whose Default is Follow (the camera turns with the walk). Elsewhere the computer modes, whose
-- Default is Classic. Also where the PlayerModule lives (since 2025 in StarterPlayer, before in PlayerScripts).
local function cameraModule(): string
	local ok, text = pcall(function()
		local settings = UserSettings():GetService("UserGameSettings")
		local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
		local dev = if touch then (player :: any).DevTouchCameraMode else player.DevComputerCameraMode
		local own = if touch then settings.TouchCameraMovementMode else settings.ComputerCameraMovementMode
		local picked = if dev.Name == "UserChoice" then own else dev
		local effective = if picked.Name == "Default" then (if touch then "Follow" else "Classic") else picked.Name
		local scripts = player:FindFirstChild("PlayerScripts")
		local where = if StarterPlayer:FindFirstChild("PlayerModule")
			then "StarterPlayer"
			elseif scripts and scripts:FindFirstChild("PlayerModule") then "PlayerScripts"
			else "none"
		return `preferred={enumName(UserInputService.PreferredInput)} effective={effective} PlayerModule in {where}`
	end)
	return if ok then text else "unreadable"
end

-- Roblox's own touch frames: a stick, the dynamic stick, its jump button (hidden while ours show).
local function robloxTouch(): string
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return "no PlayerGui"
	end
	local parts = {}
	local guis = 0
	for _, child in playerGui:GetChildren() do
		if child.Name == "TouchGui" and child:IsA("ScreenGui") then
			guis += 1
			for _, frameName in { "ThumbstickFrame", "DynamicThumbstickFrame", "JumpButton" } do
				for _, found in child:GetDescendants() do
					if found.Name == frameName and found:IsA("GuiObject") then
						table.insert(parts, `{frameName}={if found.Visible then "shown" else "hidden"}`)
					end
				end
			end
		end
	end
	return `TouchGui x{guis} ` .. (if #parts > 0 then table.concat(parts, " ") else "(no frames)")
end

local function rect(object: GuiObject): string
	local at, size = object.AbsolutePosition, object.AbsoluteSize
	return string.format("%d,%d %dx%d", at.X, at.Y, size.X, size.Y)
end

local function ago(at: number): string
	return if at > 0 then string.format("%.1fs ago", os.clock() - at) else "never"
end

local function text(): string
	local lines = { Version.text() }
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local settings = UserSettings():GetService("UserGameSettings")

	table.insert(lines, "-- camera")
	table.insert(
		lines,
		`type={read(function()
			return camera.CameraType
		end)} mode={enumName(player.CameraMode)} autoRotate={if humanoid then tostring(humanoid.AutoRotate) else "-"}`
	)
	table.insert(
		lines,
		`devTouchCam player={playerTouchCamera()} starter={enumName(StarterPlayer.DevTouchCameraMovementMode)} own={read(
			function()
				return settings.TouchCameraMovementMode
			end
		)}`
	)
	table.insert(lines, cameraModule())
	table.insert(
		lines,
		string.format(
			"turning %+.0f deg/s, walk now %s, last walk %s",
			yawRate,
			if walk.active
				then string.format(
					"%.0f deg in %.1fs%s",
					walk.turned,
					walk.time,
					if walk.cameraFinger then " (cam finger)" else ""
				)
				else "-",
			lastWalk
		)
	)

	table.insert(lines, "-- move")
	table.insert(
		lines,
		`devTouchMove={read(function()
			return player.DevTouchMovementMode
		end)} own={read(function()
			return settings.TouchMovementMode
		end)} moveDir={if humanoid then string.format("%.2f", humanoid.MoveDirection.Magnitude) else "-"}`
	)
	table.insert(lines, robloxTouch())
	table.insert(
		lines,
		`authority={read(function()
			return (workspace :: any).AuthorityMode
		end)}`
	)

	table.insert(lines, "-- jump")
	local touchGui, buttons, stats, held
	if registry and registry.TouchControls then
		touchGui, buttons, stats, held = registry.TouchControls.debugInfo()
	end
	if stats then
		table.insert(
			lines,
			`taps {stats.taps} (last {ago(stats.lastTap)}) held={tostring(held)} sets {stats.sets} (last {ago(
				stats.lastSet
			)}) Jump after set={tostring(stats.jumpAfterSet)}{if stats.blocked ~= ""
				then " blocked: " .. stats.blocked
				else ""}`
		)
	end
	if humanoid then
		table.insert(
			lines,
			`state={humanoid:GetState().Name} floor={humanoid.FloorMaterial.Name} jumping allowed={tostring(
				humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
			)} jumped {jumpsDone}x`
		)
		table.insert(
			lines,
			string.format(
				"useJumpPower=%s power=%.0f height=%.1f Jump=%s",
				tostring(humanoid.UseJumpPower),
				humanoid.JumpPower,
				humanoid.JumpHeight,
				tostring(humanoid.Jump)
			)
		)
	else
		table.insert(lines, "no humanoid")
	end

	table.insert(lines, "-- screen")
	local inset = GuiService:GetGuiInset()
	local viewport = if camera then camera.ViewportSize else Vector2.zero
	table.insert(
		lines,
		string.format(
			"viewport %dx%d inset %d,%d safe area %s",
			viewport.X,
			viewport.Y,
			inset.X,
			inset.Y,
			if touchGui then rect(touchGui :: any) else "-"
		)
	)
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

	local active = {}
	for _, touch in touches do
		table.insert(active, touch)
	end
	table.sort(active, function(a, b)
		return a.n < b.n
	end)
	table.insert(lines, `-- touches {#active}`)
	for _, touch in active do
		table.insert(
			lines,
			string.format(
				"#%d %.1fs from %d,%d now %d,%d %s",
				touch.n,
				os.clock() - touch.at,
				touch.start.X,
				touch.start.Y,
				touch.input.Position.X,
				touch.input.Position.Y,
				touch.what
			)
		)
	end

	table.insert(lines, "-- events")
	for _, event in events do
		table.insert(lines, event)
	end
	return table.concat(lines, "\n")
end

local function build()
	local made = Screen.gui("TouchDebug", 1000)
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.new(0.5, 0, 0, 48)
	box.Size = UDim2.fromScale(0.56, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundColor3 = Color3.new(0, 0, 0)
	box.BackgroundTransparency = 0.55
	box.BorderSizePixel = 0
	box.Interactable = false
	box.Parent = made
	-- under Roblox's top bar (its height from the HUD's plan)
	Screen.onChanged(function(plan)
		local top = if plan and plan.topbar then plan.topbar.height else 44
		box.Position = UDim2.new(0.5, 0, 0, top + 4)
	end)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = box

	title = Instance.new("TextButton")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 16)
	title.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
	title.BackgroundTransparency = 0.2
	title.BorderSizePixel = 0
	title.TextColor3 = Color3.new(1, 1, 1)
	title.FontFace = Font.fromEnum(Enum.Font.RobotoMono)
	title.TextSize = 12
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
	body.TextSize = 11
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
			log("humanoid Jumping")
		end
	end)
end

-- the camera's turn per frame, and how far it turned while walking (a camera finger marks the walk)
local function track(dt: number)
	local camera = workspace.CurrentCamera
	if not camera or dt <= 0 then
		return
	end
	local look = camera.CFrame.LookVector
	local now = math.deg(math.atan2(-look.X, -look.Z))
	local delta = 0
	if yaw then
		delta = (now - yaw + 540) % 360 - 180
	end
	yaw = now
	yawRate += (delta / dt - yawRate) * math.min(1, dt * 8)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.1
	local cameraFinger = false
	for _, touch in touches do
		if string.sub(touch.what, 1, 6) == "camera" then
			cameraFinger = true
		end
	end
	if moving then
		if not walk.active then
			walk.active, walk.turned, walk.time, walk.cameraFinger = true, 0, 0, false
		end
		walk.turned += math.abs(delta)
		walk.time += dt
		walk.cameraFinger = walk.cameraFinger or cameraFinger
	elseif walk.active then
		walk.active = false
		lastWalk = string.format(
			"%.0f deg in %.1fs%s",
			walk.turned,
			walk.time,
			if walk.cameraFinger then " (cam finger)" else ""
		)
		if walk.time > 0.3 then
			log("walk ended: " .. lastWalk)
		end
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
		local touch = { n = touchCount, input = input, start = input.Position, at = os.clock(), what = "" }
		touch.what = classify(input, processed)
		touches[input] = touch
		log(string.format("touch #%d began at %d,%d: %s", touch.n, input.Position.X, input.Position.Y, touch.what))
	end)
	UserInputService.InputEnded:Connect(function(input)
		local touch = touches[input]
		if touch then
			touches[input] = nil
			log(string.format("touch #%d ended after %.2fs", touch.n, os.clock() - touch.at))
		end
	end)

	local lastTaps, lastSets, loggedTap = 0, 0, 0
	local lastMode = ""
	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		if not shown then
			return
		end
		track(dt)
		local stats = registry.TouchControls and select(3, registry.TouchControls.debugInfo())
		if stats then
			if stats.taps ~= lastTaps then
				lastTaps = stats.taps
				log("JUMP tapped")
			end
			if stats.sets ~= lastSets then
				lastSets = stats.sets
				-- held, a jump is set every frame: logged once per tap
				if stats.lastTap ~= loggedTap then
					loggedTap = stats.lastTap
					log(`Humanoid.Jump set (now {tostring(stats.jumpAfterSet)})`)
				end
			end
		end
		local mode = playerTouchCamera() .. "/" .. cameraModule()
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
