-- The HUD makes room for a window: every visible piece of the HUD's ScreenGuis (Config/Ui.hudAway.guis, e.g. the coins,
-- the navigation column, the bottom cluster) glides out over its nearest screen edge while the window pops up, and
-- glides back when it closes. Any window can ask for it (Window.new's `hudAway`), and so can other code:
--   local release = HudAway.push()   -- the HUD glides away (several pushes at once: it stays away until all are back)
--   release()                         -- this push is over; the last one brings the HUD back
-- Only the top-level frames of those guis move, by Position; the layout (Screen.place) keeps owning their places: on a
-- screen change while the HUD is away, the new places are taken as home and the pieces stay out of sight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ui"))
local Screen = require(script.Parent:WaitForChild("Screen"))

local HudAway = {}

local LOOK = UiConfig.hudAway
local player = Players.LocalPlayer

type Piece = { home: UDim2, away: UDim2, tween: Tween? }

local pushes = 0
local pieces: { [GuiObject]: Piece } = {}

local function playerGui(): Instance?
	return player:FindFirstChildOfClass("PlayerGui")
end

-- Where a piece goes: out over the nearest edge of its ScreenGui, as far as its own size plus a margin.
local function awayFrom(piece: GuiObject, home: UDim2, gui: ScreenGui): UDim2
	local size = gui.AbsoluteSize
	local at = piece.AbsolutePosition - gui.AbsolutePosition
	local box = piece.AbsoluteSize
	local center = at + box / 2
	local margin = LOOK.margin
	local options = {
		{ distance = center.X, offset = Vector2.new(-(at.X + box.X + margin), 0) },
		{ distance = size.X - center.X, offset = Vector2.new(size.X - at.X + margin, 0) },
		{ distance = center.Y, offset = Vector2.new(0, -(at.Y + box.Y + margin)) },
		{ distance = size.Y - center.Y, offset = Vector2.new(0, size.Y - at.Y + margin) },
	}
	local best = options[1]
	for _, option in options do
		if option.distance < best.distance then
			best = option
		end
	end
	return home + UDim2.fromOffset(best.offset.X, best.offset.Y)
end

local function glide(target: GuiObject, piece: Piece, to: UDim2, info: TweenInfo)
	if piece.tween then
		piece.tween:Cancel()
	end
	local tween = TweenService:Create(target, info, { Position = to })
	piece.tween = tween
	tween:Play()
end

-- Every visible top-level piece of the configured guis, with its ScreenGui.
local function each(callback: (GuiObject, ScreenGui) -> ())
	local root = playerGui()
	if not root then
		return
	end
	for _, name in LOOK.guis do
		local gui = root:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") and gui.Enabled then
			for _, child in gui:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					callback(child, gui)
				end
			end
		end
	end
end

local function goAway(instant: boolean)
	local info = TweenInfo.new(LOOK.away, Enum.EasingStyle.Back, Enum.EasingDirection.In, 0, false, 0)
	each(function(target, gui)
		local piece = pieces[target]
		-- still gliding home: its home is known, not where it is now; settled: where it is now (the layout may have
		-- moved it since)
		local gliding = piece ~= nil and piece.tween ~= nil and piece.tween.PlaybackState == Enum.PlaybackState.Playing
		if piece and piece.tween then
			piece.tween:Cancel()
		end
		local home = if piece and gliding and not instant then piece.home else target.Position
		if not piece then
			piece = { home = home, away = home }
			pieces[target] = piece
		end
		piece.home = home
		-- measured from home: put it there for a moment (same frame, nothing is drawn in between)
		target.Position = home
		piece.away = awayFrom(target, home, gui)
		if instant then
			target.Position = piece.away
		else
			glide(target, piece, piece.away, info)
		end
	end)
end

local function comeBack()
	local info = TweenInfo.new(LOOK.back, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for target, piece in pieces do
		if target.Parent then
			glide(target, piece, piece.home, info)
		else
			pieces[target] = nil
		end
	end
end

-- The HUD glides away; returns the function that ends this push.
function HudAway.push(): () -> ()
	pushes += 1
	if pushes == 1 then
		goAway(false)
	end
	local released = false
	return function()
		if released then
			return
		end
		released = true
		pushes -= 1
		if pushes == 0 then
			comeBack()
		end
	end
end

function HudAway.isAway(): boolean
	return pushes > 0
end

-- A new layout while away: the HUD's own listeners place the pieces anew (onto the screen); take those places as home
-- and put the pieces straight back out of sight.
Screen.onChanged(function()
	if pushes == 0 then
		return
	end
	task.defer(function()
		if pushes == 0 then
			return
		end
		for _, piece in pieces do
			if piece.tween then
				piece.tween:Cancel()
				piece.tween = nil
			end
		end
		table.clear(pieces)
		goAway(true)
	end)
end)

return HudAway
