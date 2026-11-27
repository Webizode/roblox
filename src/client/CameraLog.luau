--!strict
-- Which of the game's own scripts wrote Camera.CFrame last (for the touch debug overlay, TouchDebug; phone test
-- 27.11.2026: the camera seemed to turn while walking with the stick). Only CombatCamera (combat mode) and the camera
-- jolts (Vfx/Camera) write it; each calls CameraLog.wrote with its name in the frame it does. Everything else that moves
-- the camera is Roblox's own camera module.

local CameraLog = {}

local lastName = ""
local lastAt = 0 -- os.clock()
local lastFrame = -1
local frame = 0

-- `name` wrote Camera.CFrame this frame.
function CameraLog.wrote(name: string)
	lastName, lastAt, lastFrame = name, os.clock(), frame
end

-- Called once per frame by the overlay, before the camera scripts run.
function CameraLog.nextFrame()
	frame += 1
end

-- The last own writer, when (os.clock()), and whether it wrote in the current frame.
function CameraLog.last(): (string, number, boolean)
	return lastName, lastAt, lastFrame == frame
end

return CameraLog
