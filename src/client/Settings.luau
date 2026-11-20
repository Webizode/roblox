-- The local player's settings: what the menu shows and every effect reads. Starts with the defaults, takes the saved
-- settings from the Settings attribute once the save is loaded, and sends changes to the server a moment after the
-- last one (DataService checks and saves them). Every value goes through SettingsRules first.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local SettingsRules = require(Shared:WaitForChild("SettingsRules"))
local SettingsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Settings"))

local Settings = {}

local player = Players.LocalPlayer
local current = SettingsRules.sanitize({}, SettingsConfig)
local listeners: { (settings: { [string]: any }) -> () } = {}
local saveToken = 0
local lastLocalChange = -math.huge -- os.clock of the last change made here
local lastInput = "keyboard"
local loaded = false -- the saved settings arrived (Settings attribute) at least once
local changedEarly: { [string]: boolean } = {} -- keys set here before that
-- Settings.saveNow calls waiting for the server's echo
local waiters: { { key: string, value: any, done: (ok: boolean) -> () } } = {}

local function notify()
	for _, listener in listeners do
		task.spawn(listener, current)
	end
end

-- The current settings (read only; change them with Settings.set).
function Settings.get(): { [string]: any }
	return current
end

-- What the settings mean for the effects (SettingsRules.effective).
function Settings.effective(): SettingsRules.Effective
	return SettingsRules.effective(current, SettingsConfig, UserInputService.TouchEnabled)
end

-- Calls `listener(settings)` now and after every change.
function Settings.onChanged(listener: (settings: { [string]: any }) -> ())
	table.insert(listeners, listener)
	task.spawn(listener, current)
end

-- Nothing goes to the server before the saved settings arrived once (the Settings attribute): until then this client
-- only knows the defaults, and sending them would overwrite the player's saved settings (the touch layout too).
local function send()
	if loaded then
		Remotes.SaveSettings:FireServer(current)
	end
end

-- Sends the settings now (the menu closes) instead of after saveDelay.
function Settings.flush()
	saveToken += 1
	send()
end

-- Changes one setting: checked, applied at once, sent to the server a moment later. Changed before the save is loaded,
-- it is kept over the loaded value and sent once that arrived.
function Settings.set(key: string, value: any)
	local checked = SettingsRules.value(key, value, SettingsConfig)
	if checked == nil or checked == current[key] then
		return
	end
	current = table.clone(current)
	current[key] = checked
	lastLocalChange = os.clock()
	if not loaded then
		changedEarly[key] = true
	end
	notify()
	saveToken += 1
	local token = saveToken
	task.delay(SettingsConfig.saveDelay, function()
		if token == saveToken then
			send()
		end
	end)
end

-- Whether the saved settings have arrived from the server.
function Settings.isLoaded(): boolean
	return loaded
end

-- Changes one setting and sends it at once; `done(true)` once the server's echo (the Settings attribute) holds it,
-- `done(false)` when it did not within confirmTimeout seconds (not loaded yet, the server refused or never answered).
function Settings.saveNow(key: string, value: any, done: (ok: boolean) -> ())
	Settings.set(key, value)
	local wanted = SettingsRules.value(key, value, SettingsConfig)
	-- already stored like that (the attribute does not change, so no echo would come)
	local raw = player:GetAttribute("Settings")
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, if type(raw) == "string" then raw else "")
	if loaded and ok and SettingsRules.same(SettingsRules.sanitize(decoded, SettingsConfig)[key], wanted) then
		task.spawn(done, true)
		return
	end
	local waiter = { key = key, value = wanted, done = done }
	table.insert(waiters, waiter)
	Settings.flush()
	task.delay(SettingsConfig.confirmTimeout, function()
		local index = table.find(waiters, waiter)
		if index then
			table.remove(waiters, index)
			done(false)
		end
	end)
end

-- The input the hints and the combat camera follow: the chosen one if this device has it, else the last one used.
function Settings.inputKind(): string
	local available = {
		touch = UserInputService.TouchEnabled,
		keyboard = UserInputService.KeyboardEnabled or UserInputService.MouseEnabled,
		gamepad = UserInputService.GamepadEnabled,
	}
	return SettingsRules.inputKind(current.inputMode, available, lastInput)
end

local function kindOf(inputType: Enum.UserInputType): string?
	if inputType == Enum.UserInputType.Touch then
		return "touch"
	elseif string.find(inputType.Name, "Gamepad") then
		return "gamepad"
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Mouse") then
		return "keyboard"
	end
	return nil
end

local function onSaved()
	local raw = player:GetAttribute("Settings")
	if type(raw) ~= "string" then
		return
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok then
		return
	end
	local saved = SettingsRules.sanitize(decoded, SettingsConfig)
	-- Settings.saveNow: the server stored what was asked for
	for index = #waiters, 1, -1 do
		local waiter = waiters[index]
		if SettingsRules.same(saved[waiter.key], waiter.value) then
			table.remove(waiters, index)
			task.spawn(waiter.done, true)
		end
	end
	if not loaded then
		-- the first load: the saved settings, with what was changed here meanwhile on top (and sent)
		loaded = true
		local early = next(changedEarly) ~= nil
		for key in changedEarly do
			saved[key] = current[key]
		end
		table.clear(changedEarly)
		current = saved
		notify()
		if early then
			send()
		end
		return
	end
	-- right after a change here the server may still echo an older state; the next send brings it up to date
	if os.clock() - lastLocalChange < SettingsConfig.saveDelay + 2 then
		return
	end
	-- the server echoes what it stored; only a difference (the first load, a reset) changes anything here
	for key, value in saved do
		if not SettingsRules.same(current[key], value) then
			current = saved
			notify()
			return
		end
	end
end

local lastType = UserInputService:GetLastInputType()
lastInput = kindOf(lastType) or (if UserInputService.TouchEnabled then "touch" else "keyboard")
UserInputService.LastInputTypeChanged:Connect(function(inputType)
	local kind = kindOf(inputType)
	if kind and kind ~= lastInput then
		lastInput = kind
		if current.inputMode == "auto" then
			notify() -- the hints follow the device in use
		end
	end
end)
player:GetAttributeChangedSignal("Settings"):Connect(onSaved)
onSaved()

return Settings
