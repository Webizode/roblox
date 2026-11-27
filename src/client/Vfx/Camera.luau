-- Every camera jolt of the game in one place: the shake when the local player is hit, knocked down or lands
-- (MovementController), and the short punch when their own ball hits somebody. The camera shake setting switches all
-- of it off. Only the picture moves, for a moment, after the camera scripts: where the player aims stays theirs.

local RunService = game:GetService("RunService")

local Settings = require(script.Parent.Parent:WaitForChild("Settings"))
local CameraLog = require(script.Parent.Parent:WaitForChild("CameraLog"))

local Camera = {}

local STEP = "WobbleVfxCamera"

local shakeUntil, shakeTime, shakeStrength = 0, 0, 0
local punchAt, punchTime, punchStrength, punchSide = -math.huge, 0, 0, 1
local bound = false
local rng = Random.new()

-- Runs after the camera script while a jolt lasts, then unbinds itself.
local function onStep()
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local pitch, yaw = 0, 0
	local running = false
	local left = shakeUntil - now
	if left > 0 and shakeTime > 0 then
		running = true
		local amount = math.rad(shakeStrength) * (left / shakeTime)
		local t = now * 40
		pitch += math.sin(t) * amount
		yaw += math.cos(t * 1.3) * amount
	end
	local since = now - punchAt
	if since < punchTime then
		running = true
		-- up at once, back down smoothly
		local fade = 1 - since / punchTime
		local amount = math.rad(punchStrength) * fade * fade
		pitch += amount
		yaw += amount * 0.35 * punchSide
	end
	if not running then
		bound = false
		RunService:UnbindFromRenderStep(STEP)
		return
	end
	if camera then
		camera.CFrame *= CFrame.Angles(pitch, yaw, 0)
		CameraLog.wrote("VfxCamera (shake)")
	end
end

local function bind()
	if not bound then
		bound = true
		RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value + 1, onStep)
	end
end

-- Shakes the picture by up to `degrees`, dying away over `seconds`. A stronger shake still running is kept.
function Camera.shake(degrees: number, seconds: number)
	if not Settings.effective().cameraShake or degrees <= 0 or seconds <= 0 then
		return
	end
	local now = os.clock()
	shakeStrength = math.max(if now < shakeUntil then shakeStrength else 0, degrees)
	shakeTime = seconds
	shakeUntil = now + seconds
	bind()
end

-- One short jolt up by `degrees` that settles within `seconds`.
function Camera.punch(degrees: number, seconds: number)
	if not Settings.effective().cameraShake or degrees <= 0 or seconds <= 0 then
		return
	end
	punchAt, punchTime, punchStrength = os.clock(), seconds, degrees
	punchSide = if rng:NextNumber() < 0.5 then -1 else 1
	bind()
end

return Camera
