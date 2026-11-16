-- Client entry. Same pattern as the server: Init(registry) for all controllers, then Start().

local Controllers = script:WaitForChild("Controllers")

local ORDER = {
	"Hud",
	"MovementController",
	"TowerController",
	"AimHud",
	"CombatController",
	"HitFeedback",
	"VfxController",
	"KnockMeter",
	"EnemyHealthBars",
	"WantedHud",
	"Backpacks",
	"HeldBalls",
	"ThrowAnimator",
	"ShotRenderer",
	"LootRenderer",
	"RemoteTowers",
	"SettingsController",
	"Navigation",
	"PlotGuide",
	"PlotPins",
	"UiKitGallery",
	"FountainWater",
	"Ocean",
	"HitZoneDebug",
}

local registry = {}
for _, name in ORDER do
	registry[name] = require(Controllers:WaitForChild(name))
end

for _, name in ORDER do
	local controller = registry[name]
	if controller.Init then
		controller.Init(registry)
	end
end

for _, name in ORDER do
	local controller = registry[name]
	if controller.Start then
		task.spawn(controller.Start)
	end
end
