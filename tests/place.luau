-- lune run tests/place build/WobbleScoops.rbxl
-- Opens the place Rojo built and checks that every script ends up where the code looks for it, and that
-- every `WaitForChild("Name")` on a script-relative path points at something that exists.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or "build/WobbleScoops.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))

local failures = {}

local function find(root, segments: { string })
	local current = root
	for _, name in segments do
		current = current:FindFirstChild(name)
		if not current then
			return nil
		end
	end
	return current
end

local function expectInstance(segments: { string }, className: string)
	local instance = find(game, segments)
	local label = table.concat(segments, ".")
	if not instance then
		table.insert(failures, `missing {label}`)
	elseif instance.ClassName ~= className then
		table.insert(failures, `{label} is a {instance.ClassName}, expected {className}`)
	end
	return instance
end

expectInstance({ "ServerScriptService", "Server" }, "Script")
expectInstance({ "StarterPlayer", "StarterPlayerScripts", "Client" }, "LocalScript")
expectInstance({ "ReplicatedStorage", "Shared" }, "Folder")
expectInstance({ "ReplicatedStorage", "Shared", "Config" }, "Folder")

for _, name in
	{
		"Remotes",
		"TowerModel",
		"TowerShape",
		"Economy",
		"Recipes",
		"ShotMath",
		"CatchRules",
		"Combat",
		"Dash",
		"ThrowPose",
		"BallMotion",
		"Stance",
		"MapRules",
		"MapQuery",
		"SaveData",
		"SettingsRules",
		"LaunchArms",
		"ScoopFlight",
		"ScoopLabel",
		"TargetRules",
		"AimRules",
		"MusicPlaylist",
		"ArenaZone",
		"MouseRules",
		"HitPoints",
	}
do
	expectInstance({ "ReplicatedStorage", "Shared", name }, "ModuleScript")
end
for _, name in
	{
		"Flavors",
		"Tower",
		"Economy",
		"Recipes",
		"Palette",
		"Launcher",
		"Features",
		"Sounds",
		"Combat",
		"Movement",
		"Backpack",
		"Map",
		"Save",
		"Settings",
		"BigSwirl",
		"BigSwirlCycle",
		"TowerScoops",
	}
do
	expectInstance({ "ReplicatedStorage", "Shared", "Config", name }, "ModuleScript")
end
for _, name in
	{
		"MapService",
		"DataService",
		"KillTestLog",
		"PlotService",
		"ArenaService",
		"TowerService",
		"LauncherService",
		"CombatService",
		"DebugDummies",
		"WalkTimer",
	}
do
	expectInstance({ "ServerScriptService", "Server", "Services", name }, "ModuleScript")
end
expectInstance({ "ServerScriptService", "Server", "Packages", "ProfileStore" }, "ModuleScript")
for _, name in
	{ "TowerVisual", "BallVisual", "Sfx", "Ui", "CombatCamera", "Settings", "BigSwirlArms", "ScoopModel", "ScoopSign" }
do
	expectInstance({ "StarterPlayer", "StarterPlayerScripts", "Client", name }, "ModuleScript")
end
for _, name in
	{
		"Hud",
		"MovementController",
		"TowerController",
		"AimHud",
		"CombatController",
		"HitFeedback",
		"Backpacks",
		"HeldBalls",
		"ThrowAnimator",
		"ShotRenderer",
		"RemoteTowers",
		"SettingsController",
		"TeleportMenu",
	}
do
	expectInstance({ "StarterPlayer", "StarterPlayerScripts", "Client", "Controllers", name }, "ModuleScript")
end

-- Every Shared/Config module a script waits for must exist.
local shared = find(game, { "ReplicatedStorage", "Shared" })
local config = shared and shared:FindFirstChild("Config")
local checkedRequires = 0
for _, descendant in game:GetDescendants() do
	if descendant:IsA("LuaSourceContainer") then
		local source = descendant.Source
		for name in string.gmatch(source, 'Shared:WaitForChild%("(%w+)"%)') do
			checkedRequires += 1
			if name ~= "Config" and not (shared and shared:FindFirstChild(name)) then
				table.insert(failures, `{descendant:GetFullName()} waits for Shared.{name}, which does not exist`)
			end
		end
		for name in string.gmatch(source, 'Config"?%)?:WaitForChild%("(%w+)"%)') do
			checkedRequires += 1
			if not (config and config:FindFirstChild(name)) then
				table.insert(failures, `{descendant:GetFullName()} waits for Config.{name}, which does not exist`)
			end
		end
	end
end

for _, failure in failures do
	print("FAIL " .. failure)
end
print(`place check: {#failures} problems, {checkedRequires} shared requires resolved`)
if #failures > 0 then
	process.exit(1)
end
