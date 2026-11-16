-- "Wanted" for stolen scoops (Config/Wanted, WantedService), as everybody sees it. It only reads the WantedUntil
-- attribute the server sets on each player (server time, 0 = not wanted); nothing here decides anything.
--
-- Over every other wanted player: a red badge "WANTED" with a siren and the seconds left, always on top, pulsing, so
-- the hunters see at once whom to chase; at their tower a soft red pulsing light. For the wanted player themself: a
-- big "WANTED 7" line in the HUD with what it forbids, and a soft push back down the ramp before its top edge (their
-- own client moves their character; the server pulls back whoever gets clearly past anyway) with a hint each time
-- they run against it. Hints for a refused serve or a pull-back by the server come as WantedNotice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Wanted = require(Shared:WaitForChild("Wanted"))
local WantedConfig = require(Config:WaitForChild("Wanted"))
local MapConfig = require(Config:WaitForChild("Map"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local client = script.Parent.Parent
local Ui = require(client:WaitForChild("Ui"))
local UiKit = require(client:WaitForChild("UiKit"))

local WantedHud = {}

local ATTRIBUTE = "WantedUntil"
local RED = Color3.fromHex(WantedConfig.glow.color)
local WHITE = Color3.new(1, 1, 1)
local SIREN = utf8.char(0x1F6A8) -- the police light emoji

local HINTS = {
	edge = "WANTED! YOU CAN'T LEAVE THE ARENA WITH STOLEN SCOOPS",
	serve = "WANTED! STOLEN SCOOPS CAN'T BE SERVED YET",
}

type Mark = {
	character: Model,
	badge: BillboardGui,
	frame: Frame,
	count: TextLabel,
	attachment: Attachment,
	light: PointLight,
}

local player = Players.LocalPlayer
local marks: { [Player]: Mark } = {}
local hud: Frame
local hudCount: TextLabel
local hudScale: UIScale
local shownSeconds = -1
local push: { attachment: Attachment, velocity: LinearVelocity }? = nil
local lastHint = -math.huge

local function wantedSeconds(who: Player, now: number): number
	local value = who:GetAttribute(ATTRIBUTE)
	return if type(value) == "number" then Wanted.secondsLeft(value, now) else 0
end

local function hint(text: string)
	local clock = os.clock()
	if clock - lastHint < WantedConfig.hintEvery then
		return
	end
	lastHint = clock
	UiKit.Toast.show(text, "bad")
end

local function removeMark(who: Player)
	local mark = marks[who]
	if mark then
		mark.badge:Destroy()
		mark.attachment:Destroy()
		marks[who] = nil
	end
end

local function makeMark(who: Player, character: Model, head: BasePart, root: BasePart): Mark
	local look = WantedConfig.badge
	local badge = Instance.new("BillboardGui")
	badge.Name = "Wanted_" .. who.UserId
	badge.Adornee = head
	badge.AlwaysOnTop = true
	badge.LightInfluence = 0
	badge.MaxDistance = look.maxDistance
	badge.Size = UDim2.fromScale(look.width, look.width * 0.62)
	badge.StudsOffsetWorldSpace = Vector3.new(0, look.height, 0)
	badge.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = RED
	Ui.corner(frame, UDim.new(0.25, 0))
	Ui.stroke(frame, "outline", 3, 0)
	frame.Parent = badge

	local title = Ui.text({
		Text = "WANTED",
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromScale(1, 0.38),
		TextScaled = true,
		TextColor3 = WHITE,
	})
	title.Parent = frame

	local count = Ui.text({
		Text = SIREN,
		AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.fromScale(0, 0.34),
		Size = UDim2.fromScale(1, 0.62),
		TextScaled = true,
		TextColor3 = WHITE,
	})
	Ui.stroke(count, "outline", 2, 0).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	count.Parent = frame
	badge.Parent = player:WaitForChild("PlayerGui")

	-- the glow sits where the tower stands on the back (Config/Combat towerBack: behind is +Z of the root)
	local glow = WantedConfig.glow
	local attachment = Instance.new("Attachment")
	attachment.Name = "WantedGlow"
	attachment.Position = Vector3.new(0, glow.up, glow.back)
	attachment.Parent = root
	local light = Instance.new("PointLight")
	light.Color = RED
	light.Range = glow.range
	light.Brightness = glow.brightness
	light.Shadows = false
	light.Parent = attachment

	return {
		character = character,
		badge = badge,
		frame = frame,
		count = count,
		attachment = attachment,
		light = light,
	}
end

local function updateMarks(now: number)
	local look = WantedConfig.badge
	local glow = WantedConfig.glow
	for _, who in Players:GetPlayers() do
		local seconds = wantedSeconds(who, now)
		local character = who.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local mark = marks[who]
		if seconds <= 0 or not character or not head or not root then
			removeMark(who)
			continue
		end
		if mark and mark.character ~= character then
			removeMark(who)
			mark = nil
		end
		if not mark then
			mark = makeMark(who, character, head, root)
			marks[who] = mark
		end
		-- the own badge would sit in the middle of the own picture: the HUD line shows it instead
		mark.badge.Enabled = who ~= player
		mark.count.Text = `{SIREN} {seconds}`
		local beat = 0.5 + 0.5 * math.sin(now * look.pulse * 2 * math.pi)
		mark.frame.Size = UDim2.fromScale(0.92 + 0.08 * beat, 0.92 + 0.08 * beat)
		mark.frame.BackgroundColor3 = RED:Lerp(WHITE, 0.15 * beat)
		mark.light.Brightness = glow.brightness * (0.6 + 0.4 * math.sin(now * glow.pulse * 2 * math.pi) ^ 2)
	end
	for who in marks do
		if who.Parent ~= Players then
			removeMark(who)
		end
	end
end

local function stopPush()
	if push then
		push.velocity:Destroy()
		push.attachment:Destroy()
		push = nil
	end
end

-- The soft push back down the ramp: a horizontal velocity towards the nearest allowed point while past the line,
-- until the character is a stud back inside it.
local function updatePush(seconds: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if seconds <= 0 or not root or root.Parent == nil then
		stopPush()
		return
	end
	local position = root.Position
	local line = Wanted.limit(MapConfig.arena, WantedConfig)
	local _, _, past = Wanted.allowedPoint(position.X, position.Z, MapConfig.arena, line)
	local tx, tz, release = Wanted.allowedPoint(position.X, position.Z, MapConfig.arena, line - 1)
	if not push and past <= 0 then
		return
	end
	if past > WantedConfig.maxPull or release <= 0 then
		stopPush()
		return
	end
	local dx, dz = tx - position.X, tz - position.Z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-3 then
		stopPush()
		return
	end
	if not push or push.attachment.Parent ~= root then
		stopPush()
		local attachment = Instance.new("Attachment")
		attachment.Name = "WantedPushAttachment"
		attachment.Parent = root
		local velocity = Instance.new("LinearVelocity")
		velocity.Name = "WantedPush"
		velocity.Attachment0 = attachment
		velocity.RelativeTo = Enum.ActuatorRelativeTo.World
		velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		velocity.PrimaryTangentAxis = Vector3.xAxis
		velocity.SecondaryTangentAxis = Vector3.zAxis
		velocity.MaxForce = root.AssemblyMass * 1500
		velocity.Parent = root
		push = { attachment = attachment, velocity = velocity }
	end
	local active = push :: { attachment: Attachment, velocity: LinearVelocity }
	active.velocity.PlaneVelocity = Vector2.new(dx / length, dz / length) * WantedConfig.pushSpeed
	hint(HINTS.edge)
end

local function updateHud(seconds: number)
	hud.Visible = seconds > 0
	if seconds <= 0 then
		shownSeconds = -1
		return
	end
	if seconds ~= shownSeconds then
		shownSeconds = seconds
		hudCount.Text = `{SIREN} WANTED {seconds}`
		hudScale.Scale = 1.25 -- a little pop on every second
	end
	hudScale.Scale += (1 - hudScale.Scale) * 0.2
end

local function step()
	local now = workspace:GetServerTimeNow()
	updateMarks(now)
	local own = wantedSeconds(player, now)
	updateHud(own)
	updatePush(own)
end

function WantedHud.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WantedHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	-- the holder scales with the screen (Ui.autoScale), the line inside pops on every second (hudScale)
	local holder = Instance.new("Frame")
	holder.Name = "WantedHolder"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.fromScale(0.5, WantedConfig.hud.fromTop)
	holder.Size = UDim2.fromOffset(0, 0)
	holder.AutomaticSize = Enum.AutomaticSize.XY
	holder.BackgroundTransparency = 1
	Ui.autoScale(holder)
	holder.Parent = gui

	hud = Instance.new("Frame")
	hud.Name = "Wanted"
	hud.Size = UDim2.fromOffset(0, 0)
	hud.AutomaticSize = Enum.AutomaticSize.XY
	hud.BackgroundTransparency = 1
	hud.Visible = false
	Ui.list(hud, Enum.FillDirection.Vertical, 2)
	hudScale = Instance.new("UIScale")
	hudScale.Parent = hud

	hudCount = Ui.text({ Text = "WANTED", TextSize = WantedConfig.hud.textSize, LayoutOrder = 1 })
	hudCount.TextColor3 = RED
	Ui.stroke(hudCount, "outline", 3, 0).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	hudCount.Parent = hud
	local sub = Ui.text({
		Text = "NO LEAVING, NO TELEPORT, NO SERVING",
		TextSize = math.floor(WantedConfig.hud.textSize * 0.42),
		LayoutOrder = 2,
	})
	Ui.stroke(sub, "outline", 2, 0).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	sub.Parent = hud
	hud.Parent = holder
end

function WantedHud.Start()
	Remotes.WantedNotice.OnClientEvent:Connect(function(what: string)
		local text = HINTS[what]
		if text then
			lastHint = -math.huge
			hint(text)
		end
	end)
	Players.PlayerRemoving:Connect(removeMark)
	RunService.Heartbeat:Connect(step)
end

return WantedHud
