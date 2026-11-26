-- Draws the arena boss the server runs (BossService, Config/Bosses) and tells everybody what it means: the boss's simple
-- part model, its big health bar at the top with the time it has left, the big boss's announcement, the truce banners
-- ("TRUCE! Defeat the boss together!" at the announcement and the start, "PvP is back!" at the end), the danger areas
-- of its attacks before they strike, the sticky puddles, and what a hit does to the local player's tower.
--
-- The server publishes the boss on ReplicatedStorage.BossState (attributes, about 15 times a second) and its moments
-- through the BossEvent remote; nothing here decides anything. Kept cheap for phones: under 15 parts for the boss,
-- one or two flat parts per danger area, 24 small parts for a ground wave, no lights, particles or shadows.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local BossRules = require(Shared:WaitForChild("BossRules"))
local BossConfig = require(Config:WaitForChild("Bosses"))

local client = script.Parent.Parent
local Sfx = require(client:WaitForChild("Sfx"))
local UiKit = require(client:WaitForChild("UiKit"))
local Theme, Screen = UiKit.Theme, UiKit.Screen

local BossController = {}

local registry
local player = Players.LocalPlayer
local stateFolder: Folder
local LOOK = BossConfig.look
local TEXT = BossConfig.text
local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X
local WAVE_SEGMENTS = 24

local function now(): number
	return workspace:GetServerTimeNow()
end

local function anchoredPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- The world folder for everything drawn here (not under the map: nothing here is ground or cover).
local worldFolder: Folder? = nil
local function world(): Folder
	if not worldFolder or not worldFolder.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "Boss"
		folder.Parent = workspace
		worldFolder = folder
	end
	return worldFolder :: Folder
end

---------------------------------------------------------------------------------------------------------------------
-- The models: a few parts each, in model space with the feet at y 0 and the face towards -Z. Placeholders.

type PartSpec = { shape: string, size: Vector3, at: Vector3, color: string, material: string?, transparency: number? }

local MODELS: { [string]: { PartSpec } } = {
	iceBrute = {
		{
			shape = "Block",
			size = Vector3.new(8, 8, 6),
			at = Vector3.new(0, 6, 0),
			color = "#9ED8F5",
			material = "Ice",
		},
		{
			shape = "Ball",
			size = Vector3.new(5, 5, 5),
			at = Vector3.new(0, 11.5, -0.5),
			color = "#C9ECFF",
			material = "Ice",
		},
		{
			shape = "Block",
			size = Vector3.new(3, 6, 3),
			at = Vector3.new(-5.5, 5, -0.5),
			color = "#7FC4EA",
			material = "Ice",
		},
		{
			shape = "Block",
			size = Vector3.new(3, 6, 3),
			at = Vector3.new(5.5, 5, -0.5),
			color = "#7FC4EA",
			material = "Ice",
		},
		{
			shape = "Ball",
			size = Vector3.new(3.6, 3.6, 3.6),
			at = Vector3.new(-5.5, 2, -0.5),
			color = "#E8F7FF",
			material = "Ice",
		},
		{
			shape = "Ball",
			size = Vector3.new(3.6, 3.6, 3.6),
			at = Vector3.new(5.5, 2, -0.5),
			color = "#E8F7FF",
			material = "Ice",
		},
		{
			shape = "Block",
			size = Vector3.new(2.6, 2, 2.6),
			at = Vector3.new(-2, 1, 0),
			color = "#7FC4EA",
			material = "Ice",
		},
		{
			shape = "Block",
			size = Vector3.new(2.6, 2, 2.6),
			at = Vector3.new(2, 1, 0),
			color = "#7FC4EA",
			material = "Ice",
		},
		{ shape = "Ball", size = Vector3.new(0.9, 0.9, 0.9), at = Vector3.new(-1, 12, -2.8), color = "#1B2A4A" },
		{ shape = "Ball", size = Vector3.new(0.9, 0.9, 0.9), at = Vector3.new(1, 12, -2.8), color = "#1B2A4A" },
	},
	gummyBear = {
		{
			shape = "Ball",
			size = Vector3.new(7, 8, 6),
			at = Vector3.new(0, 5, 0),
			color = "#FF4D6D",
			material = "Glass",
			transparency = 0.15,
		},
		{
			shape = "Ball",
			size = Vector3.new(5.2, 5, 5),
			at = Vector3.new(0, 10.5, 0),
			color = "#FF4D6D",
			material = "Glass",
			transparency = 0.15,
		},
		{
			shape = "Ball",
			size = Vector3.new(1.8, 1.8, 1.2),
			at = Vector3.new(-1.9, 13, 0),
			color = "#FF4D6D",
			material = "Glass",
			transparency = 0.15,
		},
		{
			shape = "Ball",
			size = Vector3.new(1.8, 1.8, 1.2),
			at = Vector3.new(1.9, 13, 0),
			color = "#FF4D6D",
			material = "Glass",
			transparency = 0.15,
		},
		{
			shape = "Ball",
			size = Vector3.new(2.2, 3, 2.2),
			at = Vector3.new(-2, 1.2, 0),
			color = "#E8344F",
			material = "Glass",
			transparency = 0.15,
		},
		{
			shape = "Ball",
			size = Vector3.new(2.2, 3, 2.2),
			at = Vector3.new(2, 1.2, 0),
			color = "#E8344F",
			material = "Glass",
			transparency = 0.15,
		},
		{ shape = "Ball", size = Vector3.new(0.8, 0.8, 0.8), at = Vector3.new(-1, 11, -2.4), color = "#2A0F14" },
		{ shape = "Ball", size = Vector3.new(0.8, 0.8, 0.8), at = Vector3.new(1, 11, -2.4), color = "#2A0F14" },
		{
			shape = "Ball",
			size = Vector3.new(1.6, 1.2, 1),
			at = Vector3.new(0, 9.9, -2.4),
			color = "#FF8FA3",
			material = "Glass",
		},
	},
	creamGhost = {
		{
			shape = "Ball",
			size = Vector3.new(7, 9, 7),
			at = Vector3.new(0, 6, 0),
			color = "#FFF6E6",
			material = "SmoothPlastic",
		},
		{
			shape = "Ball",
			size = Vector3.new(5.5, 5, 5.5),
			at = Vector3.new(0, 11, 0),
			color = "#FFFFFF",
			material = "SmoothPlastic",
		},
		{
			shape = "Ball",
			size = Vector3.new(2.4, 3, 2.4),
			at = Vector3.new(-2.5, 1.6, 0),
			color = "#FFF0D6",
			material = "SmoothPlastic",
		},
		{
			shape = "Ball",
			size = Vector3.new(2.4, 3.6, 2.4),
			at = Vector3.new(0, 1.2, -1),
			color = "#FFF0D6",
			material = "SmoothPlastic",
		},
		{
			shape = "Ball",
			size = Vector3.new(2.4, 3, 2.4),
			at = Vector3.new(2.5, 1.6, 0),
			color = "#FFF0D6",
			material = "SmoothPlastic",
		},
		{ shape = "Ball", size = Vector3.new(1, 1.4, 0.8), at = Vector3.new(-1.1, 11.5, -2.6), color = "#3B2016" },
		{ shape = "Ball", size = Vector3.new(1, 1.4, 0.8), at = Vector3.new(1.1, 11.5, -2.6), color = "#3B2016" },
		{ shape = "Ball", size = Vector3.new(1.6, 1, 0.8), at = Vector3.new(0, 9.8, -2.6), color = "#3B2016" },
		{ shape = "Ball", size = Vector3.new(1.2, 1.2, 1.2), at = Vector3.new(0, 14, 0), color = "#FF4D6D" }, -- the cherry
	},
}

type Shown = {
	key: string,
	model: Model,
	parts: { { part: BasePart, offset: CFrame, size: Vector3 } },
	highlight: Highlight,
	position: Vector3,
	facing: number,
	scale: number,
	leap: { from: Vector3, to: Vector3, startAt: number, endAt: number }?,
	lastHealth: number,
}

local shown: Shown? = nil

local function buildModel(key: string, scale: number): Shown
	local specs = MODELS[key] or MODELS.iceBrute
	local model = Instance.new("Model")
	model.Name = "Boss_" .. key
	local parts = {}
	for index, spec in specs do
		local part = anchoredPart({
			Name = "Part" .. index,
			Shape = Enum.PartType[spec.shape],
			Size = spec.size * scale,
			Color = Color3.fromHex(spec.color),
			Material = Enum.Material[spec.material or "SmoothPlastic"],
			Transparency = spec.transparency or 0,
		})
		part.Parent = model
		table.insert(parts, { part = part, offset = CFrame.new(spec.at * scale), size = spec.size * scale })
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	model.Parent = world()
	return {
		key = key,
		model = model,
		parts = parts,
		highlight = highlight,
		position = Vector3.zero,
		facing = 0,
		scale = scale,
		leap = nil,
		lastHealth = math.huge,
	}
end

local function placeModel(boss: Shown, position: Vector3, facing: number, bob: number)
	local base = CFrame.new(position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, facing, 0)
	for _, entry in boss.parts do
		entry.part.CFrame = base * entry.offset
	end
end

local function flash(boss: Shown)
	boss.highlight.FillTransparency = 0.35
	TweenService:Create(boss.highlight, TweenInfo.new(0.18), { FillTransparency = 1 }):Play()
end

---------------------------------------------------------------------------------------------------------------------
-- The HUD: the health bar at the top and the banners.

local gui: ScreenGui
local barHolder: Frame
local barFill: Frame
local barName: TextLabel
local barTimer: TextLabel
local barTruce: TextLabel
local banner: Frame
local bannerTitle: TextLabel
local bannerLine: TextLabel
local bannerToken = 0
local countdown: TextLabel

local function buildHud()
	gui = Screen.gui("BossHud", 35)
	gui.Parent = player:WaitForChild("PlayerGui")

	barHolder = Theme.frame({
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(LOOK.barWidth, LOOK.barHeight + 34),
		Visible = false,
		Parent = gui,
	})
	barName = Theme.text({
		Name = "Name",
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 28,
		Parent = barHolder,
	})
	local track = Theme.frame({
		Name = "Track",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, LOOK.barHeight),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("panel"),
		Parent = barHolder,
	})
	Theme.corner(track, UDim.new(0.5, 0))
	Theme.outline(track, 3)
	barFill = Theme.frame({
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("red"),
		Parent = track,
	})
	Theme.corner(barFill, UDim.new(0.5, 0))
	barTimer = Theme.text({
		Name = "Timer",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.new(0, 90, 1, -6),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.fontText,
		ZIndex = 3,
		Parent = track,
	})
	barTruce = Theme.text({
		Name = "Truce",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.new(0, 120, 1, -6),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "TRUCE",
		TextColor3 = Theme.color("mint"),
		ZIndex = 3,
		Parent = track,
	})

	countdown = Theme.text({
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.fromOffset(520, 34),
		TextSize = 30,
		TextColor3 = Theme.color("yellow"),
		Visible = false,
		Parent = gui,
	})

	banner = Theme.frame({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromOffset(900, 120),
		Visible = false,
		Parent = gui,
	})
	bannerTitle = Theme.text({
		Name = "Title",
		Size = UDim2.fromScale(1, 0.6),
		TextScaled = true,
		Parent = banner,
	})
	bannerLine = Theme.text({
		Name = "Line",
		Position = UDim2.fromScale(0.05, 0.62),
		Size = UDim2.fromScale(0.9, 0.38),
		TextScaled = true,
		Parent = banner,
	})
	-- smaller on small screens
	local scale = Instance.new("UIScale")
	scale.Parent = barHolder
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner
	Screen.onChanged(function(plan)
		local s = math.clamp(plan.scale, 0.5, 1)
		scale.Scale = s
		bannerScale.Scale = s
	end)
end

-- A big line at the top for a few seconds: `title` in `color`, `line` under it.
local function showBanner(title: string, line: string, color: Color3)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color
	bannerLine.Text = line
	banner.Visible = true
	local scale = banner:FindFirstChildOfClass("UIScale")
	if scale then
		local base = scale.Scale
		scale.Scale = base * 0.4
		TweenService
			:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base })
			:Play()
	end
	task.delay(4.5, function()
		if bannerToken == token then
			banner.Visible = false
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- The danger areas.

local function disc(position: Vector3, radius: number, color: Color3, transparency: number, lift: number): Part
	return anchoredPart({
		Name = "BossDanger",
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = transparency,
		Size = Vector3.new(0.15, radius * 2, radius * 2),
		CFrame = CFrame.new(position + Vector3.new(0, lift, 0)) * FLAT,
		Parent = world(),
	})
end

-- A disc that fills from the middle during `warn` seconds and strikes at `impactAt` (a white flash, then gone).
local function warnDisc(position: Vector3, radius: number, impactAt: number)
	local red = Color3.fromHex(LOOK.warnColor)
	local outer = disc(position, radius, red, LOOK.warnTransparency + 0.25, 0.12)
	local inner = disc(position, 0.1, red, LOOK.warnTransparency, 0.16)
	local left = math.max(0.05, impactAt - now())
	TweenService:Create(inner, TweenInfo.new(left, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.15, radius * 2, radius * 2),
	}):Play()
	task.delay(left, function()
		inner.Color = Color3.new(1, 1, 1)
		inner.Transparency = 0.2
		TweenService:Create(inner, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		outer:Destroy()
		task.delay(0.4, function()
			inner:Destroy()
		end)
	end)
end

-- A ground wave: a ring of small blocks running out from the middle from impactAt, `width` wide, up to `reach`.
local function wave(centre: Vector3, impactAt: number, speed: number, width: number, reach: number)
	-- the warning: a pulsing disc under the boss
	warnDisc(centre, math.max(6, width * 2), impactAt)
	local red = Color3.fromHex(LOOK.warnColor)
	local segments = {}
	for index = 1, WAVE_SEGMENTS do
		segments[index] = anchoredPart({
			Name = "BossWave",
			Material = Enum.Material.Neon,
			Color = red,
			Transparency = 1,
			Size = Vector3.new(1, 1.4, width),
			Parent = world(),
		})
	end
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = now() - impactAt
		if t < 0 then
			return
		end
		local ring = t * speed
		if ring > reach then
			connection:Disconnect()
			for _, part in segments do
				part:Destroy()
			end
			return
		end
		local length = 2 * math.pi * math.max(ring, 1) / WAVE_SEGMENTS
		for index, part in segments do
			local angle = (index - 1) / WAVE_SEGMENTS * 2 * math.pi
			local x, z = centre.X + math.cos(angle) * ring, centre.Z + math.sin(angle) * ring
			part.Size = Vector3.new(length + 0.3, 1.4, width)
			part.CFrame = CFrame.new(x, centre.Y + 0.7, z) * CFrame.Angles(0, -angle + math.pi / 2, 0)
			part.Transparency = 0.25 + 0.6 * (ring / reach)
		end
	end)
end

-- Sticky puddles: marked during the warning, then cream on the ground for `duration` seconds.
local function puddles(spots: { Vector3 }, radius: number, impactAt: number, duration: number)
	for _, spot in spots do
		warnDisc(spot, radius, impactAt)
	end
	task.delay(math.max(0, impactAt - now()), function()
		for _, spot in spots do
			local puddle = anchoredPart({
				Name = "BossPuddle",
				Shape = Enum.PartType.Cylinder,
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromHex(LOOK.stickyColor),
				Transparency = 0.1,
				Size = Vector3.new(0.3, radius * 2, radius * 2),
				CFrame = CFrame.new(spot + Vector3.new(0, 0.12, 0)) * FLAT,
				Parent = world(),
			})
			task.delay(math.max(0, duration - 0.6), function()
				TweenService:Create(puddle, TweenInfo.new(0.6), { Transparency = 1 }):Play()
				task.delay(0.65, function()
					puddle:Destroy()
				end)
			end)
		end
	end)
end

local function onAttack(data: any)
	if type(data) ~= "table" then
		return
	end
	local centre = Vector3.new(data.x, data.y, data.z)
	if data.kind == "stomp" then
		warnDisc(centre, data.radius, data.impactAt)
	elseif data.kind == "wave" then
		wave(centre, data.impactAt, data.speed, data.width, data.reach)
	elseif data.kind == "leap" then
		local target = Vector3.new(data.toX, data.toY, data.toZ)
		warnDisc(target, data.radius, data.impactAt)
		local boss = shown
		if boss then
			local jump = math.min(0.6, data.warn)
			boss.leap = { from = centre, to = target, startAt = data.impactAt - jump, endAt = data.impactAt }
		end
	elseif data.kind == "puddle" then
		puddles(data.spots, data.radius, data.impactAt, data.duration)
	end
end

---------------------------------------------------------------------------------------------------------------------

local function truceOn(): boolean
	return BossConfig.truce == true
end

local function onEvent(kind: string, a: any, b: any, c: any, d: any)
	if kind == "announce" then
		local line = if truceOn() then TEXT.truce else ""
		showBanner(
			BossConfig.big.title .. "!",
			string.format(TEXT.announce, BossRules.clock(a - now())) .. "  " .. line,
			Theme.color("yellow")
		)
		Sfx.play("saved")
	elseif kind == "start" then
		local title = if b then BossConfig.big.title .. ": " .. tostring(a) else tostring(a)
		showBanner(title, if c then TEXT.truce else string.format(TEXT.arrived, tostring(a)), Theme.color("red"))
		Sfx.play("groan")
	elseif kind == "end" then
		local line = string.format(if a == "defeated" then TEXT.defeated else TEXT.escaped, tostring(b))
		if c then
			showBanner(TEXT.pvpBack, line, Theme.color("mint"))
		else
			showBanner(line, "", Theme.color("mint"))
		end
		Sfx.play(if a == "defeated" then "saved" else "topple")
	elseif kind == "attack" then
		onAttack(a)
	elseif kind == "hit" then
		local hit = BossConfig.hit
		registry.TowerController.bossHit(a, b, c, hit.protectSeconds)
		Sfx.play("hit")
		UiKit.Toast.show(if (d or 0) > 0 then TEXT.hitByBoss else "SPLAT!", "bad", "scoopEmpty")
	elseif kind == "dodged" then
		UiKit.Toast.show("DODGED!", "good")
	elseif kind == "damage" then
		Sfx.play("hitConfirm")
		local boss = shown
		if boss then
			flash(boss)
		end
	elseif kind == "reward" then
		UiKit.Toast.show(string.format(TEXT.reward, a), "good", "coin")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The sign over the Big Swirl (Config/Bosses sign): the countdown to the next boss, or the living boss's name. The time
-- comes from the server (BossState NextAt and NextBig).

local SIGN = BossConfig.sign
local signGui: BillboardGui? = nil
local signLabel: TextLabel
local signFrame: Frame

local function buildSign(at: Vector3)
	local anchor = anchoredPart({
		Name = "BossSignAnchor",
		Size = Vector3.one * 0.2,
		Transparency = 1,
		CFrame = CFrame.new(at),
		Parent = world(),
	})
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BossSign"
	billboard.Adornee = anchor
	billboard.Size = UDim2.new(SIGN.studs.width, SIGN.pixels.width, SIGN.studs.height, SIGN.pixels.height)
	billboard.MaxDistance = SIGN.maxDistance
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = false
	billboard.ResetOnSpawn = false
	signFrame = Theme.frame({
		Name = "Plate",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.color("panel"),
		Parent = billboard,
	})
	Theme.corner(signFrame, UDim.new(0.5, 0))
	local rim = Instance.new("UIStroke")
	rim.Color = Theme.color("cream")
	rim.Thickness = 4
	rim.Parent = signFrame
	signLabel = Theme.text({
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.78),
		TextScaled = true,
		Parent = signFrame,
	})
	billboard.Parent = player:WaitForChild("PlayerGui")
	signGui = billboard
end

local function updateSign(time: number, active: boolean)
	if not signGui then
		local at = stateFolder:GetAttribute("SignAt")
		if typeof(at) ~= "Vector3" then
			return
		end
		buildSign(at)
	end
	local gui = signGui :: BillboardGui
	if active then
		local big = stateFolder:GetAttribute("Big") == true
		local name = tostring(stateFolder:GetAttribute("Name") or "")
		signLabel.Text = if big then BossConfig.big.title .. ": " .. name else name
		signLabel.TextColor3 = if big then Theme.color("yellow") else Theme.color("red")
		gui.Enabled = true
		return
	end
	local nextAt = stateFolder:GetAttribute("NextAt") or 0
	if nextAt <= 0 then
		gui.Enabled = false -- bosses are off
		return
	end
	local big = stateFolder:GetAttribute("NextBig") == true
	signLabel.Text = string.format(if big then SIGN.nextBig else SIGN.next, BossRules.clock(nextAt - time))
	signLabel.TextColor3 = if big then Theme.color("yellow") else Theme.color("text")
	gui.Enabled = true
end

---------------------------------------------------------------------------------------------------------------------
-- Studio only: a small panel at the right edge to start and end bosses without the command bar (StudioBossCommand;
-- the server ignores it outside Studio too).

local function buildStudioPanel()
	if not RunService:IsStudio() then
		return
	end
	local panelGui = Screen.gui("StudioBossPanel", 30)
	panelGui.Parent = player:WaitForChild("PlayerGui")
	local panel = Theme.frame({
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.45, 0),
		Size = UDim2.fromOffset(150, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Theme.color("panel"),
		Parent = panelGui,
	})
	Theme.corner(panel, UDim.new(0, 12))
	Theme.outline(panel, 3)
	local padding = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(padding :: any)[side] = UDim.new(0, 8)
	end
	padding.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel
	Theme.text({
		Name = "Title",
		Text = "BOSS TEST",
		TextSize = 18,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 0,
		Parent = panel,
	})
	local buttons = {
		{ "Ice Brute", "iceBrute", "sky" },
		{ "Gummy Bear", "gummyBear", "pink" },
		{ "Cream Ghost", "creamGhost", "creamDark" },
		{ "Big Boss", "big", "yellow" },
		{ "Kill", "kill", "mint" },
		{ "Escape", "escape", "red" },
	}
	for index, entry in buttons do
		local button = Instance.new("TextButton")
		button.Name = entry[2]
		button.LayoutOrder = index
		button.Size = UDim2.new(1, 0, 0, 30)
		button.BackgroundColor3 = Theme.color(entry[3])
		button.AutoButtonColor = true
		button.Text = ""
		button.Parent = panel
		Theme.corner(button, UDim.new(0.5, 0))
		Theme.outline(button, 2)
		Theme.text({
			Text = entry[1],
			TextSize = 18,
			Size = UDim2.fromScale(1, 1),
			Parent = button,
		})
		button.Activated:Connect(function()
			Remotes.StudioBossCommand:FireServer(entry[2])
		end)
	end
end

-- Every frame: the model follows the published position (smoothed; a leap flies its arc), the bar and the countdown.
local stuckShown = false
local function onRender(dt: number)
	local time = now()
	local active = stateFolder:GetAttribute("Active") == true
	if not active then
		if shown then
			shown.model:Destroy()
			shown = nil
		end
		barHolder.Visible = false
	else
		local key = stateFolder:GetAttribute("Model")
		local scale = stateFolder:GetAttribute("Scale") or 1
		local target = stateFolder:GetAttribute("Position")
		if typeof(target) ~= "Vector3" then
			target = Vector3.zero
		end
		local hover = stateFolder:GetAttribute("Hover") or 0
		if not shown or shown.key ~= key or shown.scale ~= scale then
			if shown then
				shown.model:Destroy()
			end
			shown = buildModel(if type(key) == "string" then key else "iceBrute", scale)
			shown.position = target
			shown.facing = stateFolder:GetAttribute("Facing") or 0
		end
		local boss = shown :: Shown
		local alpha = 1 - math.exp(-dt * 10)
		boss.position = boss.position:Lerp(target, alpha)
		local facing = stateFolder:GetAttribute("Facing") or boss.facing
		local turn = (facing - boss.facing + math.pi) % (2 * math.pi) - math.pi
		boss.facing += turn * alpha
		local position = boss.position
		local leap = boss.leap
		if leap and time >= leap.startAt then
			if time >= leap.endAt then
				boss.leap = nil
				boss.position = leap.to
				position = leap.to
			else
				local share = (time - leap.startAt) / (leap.endAt - leap.startAt)
				position = leap.from:Lerp(leap.to, share) + Vector3.new(0, math.sin(share * math.pi) * 14, 0)
			end
		end
		local bob = hover + math.sin(time * (if hover > 0 then 2 else 6)) * (if hover > 0 then 0.8 else 0.15)
		placeModel(boss, position, boss.facing, bob)

		local health = stateFolder:GetAttribute("Health") or 0
		local full = math.max(1, stateFolder:GetAttribute("MaxHealth") or 1)
		if health < boss.lastHealth and boss.lastHealth ~= math.huge then
			flash(boss)
		end
		boss.lastHealth = health
		barHolder.Visible = true
		local big = stateFolder:GetAttribute("Big") == true
		local name = tostring(stateFolder:GetAttribute("Name") or "")
		barName.Text = if big then BossConfig.big.title .. ": " .. name else name
		barFill.Size = UDim2.fromScale(math.clamp(health / full, 0, 1), 1)
		barTimer.Text = BossRules.clock((stateFolder:GetAttribute("EndsAt") or time) - time)
		barTruce.Visible = stateFolder:GetAttribute("Truce") == true
	end

	updateSign(time, active)
	local startsAt = stateFolder:GetAttribute("BigStartsAt") or 0
	if startsAt > time and not active then
		countdown.Visible = true
		countdown.Text = string.format(TEXT.announce, BossRules.clock(startsAt - time))
	else
		countdown.Visible = false
	end

	local sticky = player:GetAttribute("StickyUntil")
	local stuck = type(sticky) == "number" and time < sticky
	if stuck and not stuckShown then
		UiKit.Toast.show(TEXT.sticky, "warn")
	end
	stuckShown = stuck
end

function BossController.Init(reg)
	registry = reg
end

function BossController.Start()
	stateFolder = ReplicatedStorage:WaitForChild("BossState") :: Folder
	buildHud()
	buildStudioPanel()
	Remotes.BossEvent.OnClientEvent:Connect(onEvent)
	RunService.RenderStepped:Connect(onRender)
end

return BossController
