--!strict
-- Roblox's own controls and camera (its PlayerModule), for the few things the game changes there: switching the move
-- controls off while knocked down, moving shift lock from Shift (the sprint) to Ctrl, and asking whether shift lock is
-- on. Works with both versions of the PlayerModule:
--   * the new one (2025; found 26.11.2026 while debugging the phone): it lies in StarterPlayer.PlayerModule while the
--     game runs, its only public API is `ControlModule.Enabled`, and shift lock is the InputAction
--     CameraContext.MouseLockSwitchAction with one InputBinding per key
--   * the old one in PlayerScripts.PlayerModule with GetControls(), GetCameras() and the StringValue BoundKeys
-- Before 26.11.2026 the game only knew the old one: the knockdown did not stop the stick, shift lock stayed on Shift.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local RobloxControls = {}

local player = Players.LocalPlayer
local WAIT = 10 -- seconds to wait for the PlayerModule at the start

local function newModule(): ModuleScript?
	local found = StarterPlayer:FindFirstChild("PlayerModule")
	return if found and found:IsA("ModuleScript") then found else nil
end

local function oldModule(): ModuleScript?
	local scripts = player:FindFirstChild("PlayerScripts")
	local found = scripts and scripts:FindFirstChild("PlayerModule")
	return if found and found:IsA("ModuleScript") then found else nil
end

-- the PlayerModule there is, waiting up to WAIT seconds for one to show
local function find(): (ModuleScript?, boolean)
	local deadline = os.clock() + WAIT
	repeat
		local fresh = newModule()
		if fresh then
			return fresh, true
		end
		local old = oldModule()
		if old then
			return old, false
		end
		task.wait(0.2)
	until os.clock() > deadline
	return nil, false
end

-- the new module's shift lock action, if it is the new one
local function mouseLockAction(): InputAction?
	local module = newModule()
	local contexts = module and module:FindFirstChild("InputContexts")
	local camera = contexts and contexts:FindFirstChild("CameraContext")
	local action = camera and camera:FindFirstChild("MouseLockSwitchAction")
	return if action and action:IsA("InputAction") then action else nil
end

-- Shift lock as the new module keeps it: Pressed toggles it while the action is enabled, switching the action off
-- ends it (MouseLockController.OnMouseLockToggled, EnableMouseLock). The controller itself cannot be reached.
local shiftLocked = false
local watching: InputAction? = nil

local function watchShiftLock(action: InputAction)
	if watching == action then
		return
	end
	watching = action
	shiftLocked = false
	action.Pressed:Connect(function()
		if action.Enabled then
			shiftLocked = not shiftLocked
		end
	end)
	action:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not action.Enabled then
			shiftLocked = false
		end
	end)
end

-- Switches the move controls (stick, keys, Roblox's jump) off or on. Returns whether it reached them.
function RobloxControls.setEnabled(enabled: boolean): boolean
	local module = newModule() or oldModule()
	if not module then
		return false
	end
	local ok = pcall(function()
		local api = require(module) :: any
		if api.GetControls == nil then
			api.ControlModule.Enabled = enabled -- the new module
		else
			local controls = api:GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end)
	return ok
end

-- Whether Roblox's shift lock is on. False when that cannot be read.
function RobloxControls.shiftLockOn(): boolean
	local action = mouseLockAction()
	if action then
		watchShiftLock(action)
		return shiftLocked
	end
	local module = oldModule()
	if not module then
		return false
	end
	local ok, locked = pcall(function()
		return (require(module) :: any):GetCameras().activeMouseLockController:GetIsMouseLocked()
	end)
	return ok and locked == true
end

-- Puts shift lock on these keys instead of Shift. Waits for the PlayerModule; call it in its own thread.
function RobloxControls.moveShiftLock(keys: { Enum.KeyCode })
	local module, fresh = find()
	if not module then
		return
	end
	if fresh then
		local action = mouseLockAction()
		if not action then
			return
		end
		watchShiftLock(action)
		local bindings = {}
		for _, child in action:GetChildren() do
			if child:IsA("InputBinding") then
				table.insert(bindings, child)
			end
		end
		table.sort(bindings, function(a, b)
			return a.Name < b.Name -- KeyboardPrimaryBinding before KeyboardSecondaryBinding
		end)
		for index, binding in bindings do
			binding.KeyCode = keys[index] or keys[1]
		end
		return
	end
	local ok, boundKeys = pcall(function()
		return module
			:WaitForChild("CameraModule", WAIT)
			:WaitForChild("MouseLockController", WAIT)
			:WaitForChild("BoundKeys", WAIT)
	end)
	if ok and boundKeys and boundKeys:IsA("StringValue") then
		local names = {}
		for _, key in keys do
			table.insert(names, key.Name)
		end
		boundKeys.Value = table.concat(names, ",")
	end
end

return RobloxControls
