-- The look of a mutated card (Golden, Rainbow): a see-through layer over a card, in the card's own shape when the card
-- is a picture (so the round corners stay clean), else a rounded rectangle.
--   golden    a warm gold gradient, and every few seconds a bright streak sweeps across at an angle
--   rainbow   a rainbow gradient that slowly turns, with a few little stars twinkling
-- Widgets.mutationOverlay(parent, kind, { image = the card's picture, zIndex = between the card and its icon/texts })
-- puts one on; the Scoop Chest uses it in the grid, the slots and the details, the Index will too.
--
-- One shared loop moves all layers (Config/Ui.mutationOverlay.fps times a second). It only runs while at least one
-- layer sits on an enabled ScreenGui: closing the window stops it, opening it starts it again. At a low saved graphics
-- level the layers stand still (gold without the streak, the rainbow at a fixed angle).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ui"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local MutationOverlay = {}

local LOOK = UiConfig.mutationOverlay
local STATIC_RAINBOW = 45 -- the rainbow's angle when it stands still
local CHECK_EVERY = 0.5 -- seconds between looks whether anything still shows

type Entry = {
	kind: string,
	gui: ScreenGui?,
	shine: UIGradient?,
	rainbow: UIGradient?,
	sparkles: { ImageLabel },
}

local entries: { [Frame]: Entry } = {}
local watched: { [ScreenGui]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local connection: RBXScriptConnection? = nil

local function lowQuality(): boolean
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if not ok or level == Enum.SavedQualitySetting.Automatic then
		return false
	end
	return level.Value <= LOOK.lowQuality
end

local function shown(overlay: Frame, entry: Entry): boolean
	local gui = entry.gui
	return gui ~= nil and gui.Enabled and overlay:IsDescendantOf(gui)
end

-- Where everything stands at time `now` (seconds); `still` puts it at rest.
local function pose(entry: Entry, now: number, still: boolean)
	local look = LOOK.kinds[entry.kind]
	if entry.shine then
		local x = 2 -- off the card
		if not still then
			local into = now % look.shineEvery
			if into < look.shineTime then
				x = -1.3 + 2.6 * (into / look.shineTime)
			end
		end
		entry.shine.Offset = Vector2.new(x, 0)
	end
	if entry.rainbow then
		entry.rainbow.Rotation = if still then STATIC_RAINBOW else (now / look.cycle * 360) % 360
	end
	for index, sparkle in entry.sparkles do
		if still then
			sparkle.ImageTransparency = 0.35
		else
			local wave = math.sin((now / look.twinkle + index / #entry.sparkles) * math.pi * 2)
			sparkle.ImageTransparency = 1 - math.max(0, wave) * 0.9
			local scale = sparkle:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = 0.6 + math.max(0, wave) * 0.4
			end
		end
	end
end

local function stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

local function anyShown(): boolean
	for overlay, entry in entries do
		if overlay.Parent == nil then
			entries[overlay] = nil -- destroyed with its card
		elseif shown(overlay, entry) then
			return true
		end
	end
	return false
end

local function ensureRunning()
	if connection or not anyShown() then
		return
	end
	if lowQuality() then
		for _, entry in entries do
			pose(entry, 0, true)
		end
		return
	end
	local sinceStep, sinceCheck = 0, 0
	connection = RunService.Heartbeat:Connect(function(dt)
		sinceCheck += dt
		if sinceCheck >= CHECK_EVERY then
			sinceCheck = 0
			if not anyShown() then
				stop()
				return
			end
		end
		sinceStep += dt
		if sinceStep < 1 / LOOK.fps then
			return
		end
		sinceStep = 0
		local now = os.clock()
		for overlay, entry in entries do
			if shown(overlay, entry) then
				pose(entry, now, false)
			end
		end
	end)
end

-- The ScreenGui a layer sits on, watched so opening it starts the loop.
local function resolve(overlay: Frame, entry: Entry)
	local gui = overlay:FindFirstAncestorOfClass("ScreenGui")
	entry.gui = gui
	if gui and not watched[gui] then
		watched[gui] = true
		gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if gui.Enabled then
				ensureRunning()
			end
		end)
	end
	ensureRunning()
end

-- A layer of the card's shape: its picture (white, to be coloured by a gradient) or a rounded rectangle.
local function layer(parent: GuiObject, name: string, image: string?, zIndex: number): GuiObject
	local made: GuiObject
	if image then
		local label = Instance.new("ImageLabel")
		label.Image = image
		label.ScaleType = Enum.ScaleType.Fit
		label.BackgroundTransparency = 1
		made = label
	else
		-- pure colour (a picture would multiply the gradient with its own colours): a rounded rectangle a little inside
		-- the card, so it stays within the card's round corners
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.BorderSizePixel = 0
		Theme.corner(frame, UDim.new(0, LOOK.corner))
		made = frame
	end
	made.Name = name
	local inset = if image then 0 else LOOK.inset
	made.AnchorPoint = Vector2.new(0.5, 0.5)
	made.Position = UDim2.fromScale(0.5, 0.5)
	made.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	made.ZIndex = zIndex
	made.Parent = parent
	return made
end

local function gradient(target: GuiObject, color: ColorSequence, transparency: NumberSequence, rotation: number)
	local made = Instance.new("UIGradient")
	made.Color = color
	made.Transparency = transparency
	made.Rotation = rotation
	made.Parent = target
	return made
end

-- Puts the look of mutation `kind` ("golden", "rainbow") over `parent` (a card's face, drawn in design pixels).
-- props.image: the card's picture, so the layer has its shape; props.zIndex: the layer's ZIndex (over the card picture,
-- under its icon and texts). Returns the layer, or nil for a kind without a look.
function MutationOverlay.new(parent: GuiObject, kind: string, props: { image: string?, zIndex: number? }?): Frame?
	local look = LOOK.kinds[kind]
	if not look then
		return nil
	end
	local options = props or {}
	local z = options.zIndex or (parent.ZIndex + 1)
	local holder = Theme.frame({ Name = "MutationLook", Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = parent })
	local entry: Entry = { kind = kind, sparkles = {} }

	if kind == "golden" then
		local tint = layer(holder, "Gold", options.image, z)
		gradient(
			tint,
			ColorSequence.new(Color3.fromHex(look.top), Color3.fromHex(look.bottom)),
			NumberSequence.new(look.transparency),
			90
		)
		local streak = layer(holder, "Shine", nil, z)
		local middle, width = 0.5, look.shineWidth
		entry.shine = gradient(
			streak,
			ColorSequence.new(Color3.new(1, 1, 1)),
			NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(middle - width, 1),
				NumberSequenceKeypoint.new(middle, look.shineTransparency),
				NumberSequenceKeypoint.new(middle + width, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			look.shineAngle
		)
	else
		local tint = layer(holder, "Rainbow", nil, z)
		local keys = {}
		for index, hex in look.colors do
			table.insert(keys, ColorSequenceKeypoint.new((index - 1) / (#look.colors - 1), Color3.fromHex(hex)))
		end
		entry.rainbow = gradient(tint, ColorSequence.new(keys), NumberSequence.new(look.transparency), STATIC_RAINBOW)
	end

	for _, spot in look.sparkles or {} do
		local sparkle = Theme.icon(Theme.icons.sparkle, {
			Name = "Sparkle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot[1], spot[2]),
			Size = UDim2.fromOffset(spot[3], spot[3]),
			ZIndex = z,
			Parent = holder,
		})
		Instance.new("UIScale").Parent = sparkle
		table.insert(entry.sparkles, sparkle)
	end

	pose(entry, 0, true)
	entries[holder] = entry
	holder.AncestryChanged:Connect(function()
		if holder.Parent then
			resolve(holder, entry)
		end
	end)
	resolve(holder, entry)
	return holder
end

return MutationOverlay
