-- The keys of an action (Config/Controls) as Roblox enums: for binding them (ContextActionService) and for the key
-- badges (UiKit Buttons.badge), so both always agree.

local Config = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config")
local Controls = require(Config:WaitForChild("Controls"))

local Keys = {}

local function toEnum(name: string): EnumItem?
	local ok, item = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	if ok and item then
		return item
	end
	ok, item = pcall(function()
		return (Enum.UserInputType :: any)[name]
	end)
	return if ok then item else nil
end

local function list(names: { string }?): { EnumItem }
	local items = {}
	for _, name in names or {} do
		local item = toEnum(name)
		if item then
			table.insert(items, item)
		else
			warn(`[Keys] unknown key {name} in Config/Controls`)
		end
	end
	return items
end

-- Every input of the action, keyboard and gamepad, to pass to ContextActionService:BindAction(..., table.unpack(...)).
function Keys.inputs(action: string): { EnumItem }
	local binding = Controls[action]
	if not binding then
		warn(`[Keys] no action {action} in Config/Controls`)
		return {}
	end
	local items = list(binding.keys)
	for _, item in list(binding.pad) do
		table.insert(items, item)
	end
	return items
end

-- The keyboard key (or mouse button) a badge shows, nil without one.
function Keys.key(action: string): EnumItem?
	local binding = Controls[action]
	return if binding then list(binding.keys)[1] else nil
end

-- The gamepad button a badge shows, nil without one.
function Keys.pad(action: string): Enum.KeyCode?
	local binding = Controls[action]
	return if binding then list(binding.pad)[1] :: any else nil
end

-- Whether an input is one of the action's.
function Keys.matches(action: string, input: InputObject): boolean
	for _, item in Keys.inputs(action) do
		if input.KeyCode == item or input.UserInputType == item then
			return true
		end
	end
	return false
end

return Keys
