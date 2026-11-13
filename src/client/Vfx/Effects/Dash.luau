-- A dash (Config/Vfx.effects.dashDust, dashLines): dust kicked up behind the feet where it starts and where it ends,
-- seen by everybody; for the local player speed lines round the edge of the screen while it runs (only with the
-- motion effects setting, like the field of view kick). The dash's trail, ground streak and afterimages are
-- MovementController's.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Vfx = require(script.Parent.Parent)
local Screen = require(script.Parent.Parent:WaitForChild("Screen"))
local Settings = require(script.Parent.Parent.Parent:WaitForChild("Settings"))

local Dash = {}

local Config = Vfx.Config
local Look = Config.dashLines
local player = Players.LocalPlayer

local lines: { Frame } = {}
local angles: { number } = {}
local runningUntil, runningFrom, runningTime = 0, 0, 0
local stepping = false

-- Dust at `feet`, blown against the dash's way (`dirX`, `dirZ`) and up.
function Dash.dust(feet: Vector3, dirX: number, dirZ: number, own: boolean)
	local back = Vector3.new(-dirX, 0, -dirZ)
	local direction = if back.Magnitude > 1e-3 then (back.Unit + Vector3.new(0, 0.8, 0)).Unit else Vector3.yAxis
	local at = feet + Vector3.new(0, 0.4, 0)
	Vfx.burst("dashDust", CFrame.lookAt(at, at + direction), { own = own })
end

local function buildLines()
	local gui = Screen.gui()
	local rng = Random.new(7)
	for index = 1, Look.count do
		local line = Instance.new("Frame")
		line.Name = "SpeedLine"
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.BackgroundColor3 = Color3.new(1, 1, 1)
		line.BorderSizePixel = 0
		line.BackgroundTransparency = 1
		line.Visible = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = line
		-- soft towards the middle: the line thins out where it points
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.6, 0),
			NumberSequenceKeypoint.new(1, 0),
		})
		fade.Parent = line
		line.Parent = gui
		lines[index] = line
		-- evenly round the screen, each a little off its place so it does not look like a clock face
		angles[index] = (index - 1 + rng:NextNumber(-0.35, 0.35)) / Look.count * 2 * math.pi
	end
end

local function step()
	local now = os.clock()
	local gui = Screen.gui()
	local size = gui.AbsoluteSize
	local done = now >= runningUntil
	local t = math.clamp((now - runningFrom) / math.max(runningTime, 1e-3), 0, 1)
	-- in and out over `fade` seconds at both ends
	local fadeIn = math.clamp((now - runningFrom) / Look.fade, 0, 1)
	local fadeOut = math.clamp((runningUntil - now) / Look.fade, 0, 1)
	local alpha = Look.alpha * math.min(fadeIn, fadeOut)
	local height = size.Y
	local centre = size / 2
	local reach = math.sqrt(centre.X * centre.X + centre.Y * centre.Y)
	for index, line in lines do
		if done then
			line.Visible = false
			continue
		end
		local angle = angles[index]
		local direction = Vector2.new(math.cos(angle), math.sin(angle))
		local length = Look.length * height
		-- its inner end `inner` of the way from the middle to a corner, sliding `slide` of its length inwards over the dash
		local distance = reach * Look.inner + length * (0.5 + Look.slide * (1 - t))
		local at = centre + direction * distance
		line.Position = UDim2.fromOffset(at.X, at.Y)
		line.Size = UDim2.fromOffset(length, math.max(2, Look.width * height))
		line.Rotation = math.deg(angle) -- its left end, where the gradient is clear, points at the middle
		line.BackgroundTransparency = 1 - alpha
		line.Visible = true
	end
	if done then
		stepping = false
		RunService:UnbindFromRenderStep("WobbleVfxDashLines")
	end
end

-- Speed lines over the local player's screen for `duration` seconds.
function Dash.lines(duration: number)
	if not Settings.effective().motionEffects then
		return
	end
	if #lines == 0 or not lines[1].Parent then
		table.clear(lines)
		buildLines()
	end
	runningFrom = os.clock()
	runningTime = duration
	runningUntil = runningFrom + duration
	if not stepping then
		stepping = true
		RunService:BindToRenderStep("WobbleVfxDashLines", Enum.RenderPriority.Last.Value, step)
	end
end

-- The whole dash of `character` in the way (`dirX`, `dirZ`): dust at the start and, `duration` seconds later, where
-- it ended; speed lines when it is the local player's.
function Dash.play(character: Model, duration: number, dirX: number, dirZ: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local own = character == player.Character
	local drop = humanoid.HipHeight + root.Size.Y / 2
	Dash.dust(root.Position - Vector3.new(0, drop, 0), dirX, dirZ, own)
	task.delay(duration, function()
		if root.Parent then
			Dash.dust(root.Position - Vector3.new(0, drop, 0), dirX, dirZ, own)
		end
	end)
	if own then
		Dash.lines(duration + 0.12)
	end
end

return Dash
