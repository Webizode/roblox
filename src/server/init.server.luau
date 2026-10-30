-- Server entry. Services are plain modules with optional Init(registry) and Start(); Init runs for all
-- services before any Start, so services can look each other up without circular requires.

local Services = script:WaitForChild("Services")

local ORDER = {
	"MapService",
	"DataService",
	"KillTestLog",
	"PlotService",
	"ArenaService",
	"TowerService",
	"LauncherService",
	"CombatService",
	"LootService",
	"DebugDummies",
	"WalkTimer",
}

local registry = {}
for _, name in ORDER do
	registry[name] = require(Services:WaitForChild(name))
end

for _, name in ORDER do
	local service = registry[name]
	if service.Init then
		service.Init(registry)
	end
end

for _, name in ORDER do
	local service = registry[name]
	if service.Start then
		task.spawn(service.Start)
	end
end
