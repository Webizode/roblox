-- lune run scripts/progression-fit
-- Looks for upgrade prices that meet the progression goals (scripts/lib/Progression.luau): the first upgrade after 2 to
-- 3 minutes, every upgrade at about level 5 after 1 hour, half the levels after about 10 hours, everything at the top
-- after 30 to 50 hours. Prices (Upgrades.cost): base x growth ^ level, from level `bend` on lateGrowth per level. For
-- each pair of growths the base is searched so that level 5 falls at 1 hour; the pairs closest to 10 h and 40 h are
-- printed. The Equip Slots (3 levels) cost what level 5, 12 and 22 of the others cost.
-- The chosen values go into Config/Upgrades by hand; scripts/progression then shows the whole table.

local Progression = require("./lib/Progression")
local Upgrades = require("../src/shared/Upgrades")
local UpgradesConfig = require("../src/shared/Config/Upgrades")

local RUNS = 5
local HOURS = 70
local BEND = 12
local GOAL = { half = 10 * 60, top = 40 * 60 }

-- the shape of the tracks (as in Config/Upgrades since 25.11.2026): many levels with a small step each
local SHAPE = {
	cone = { maxLevel = 25, perLevel = 1 }, -- 20 to 45 scoops
	stability = { maxLevel = 20, perLevel = 1 }, -- 10 to 30
	cart = { maxLevel = 25, perLevel = 0.04 }, -- x1 to x2
	luck = { maxLevel = 25, perLevel = 0.006 }, -- 0 to 15 %
	sprinkles = { maxLevel = 25, perLevel = 0.04 },
}

local function proposal(base: number, growth: number, late: number): any
	local config = table.clone(UpgradesConfig)
	config.tracks = {}
	local cost = { base = base, growth = growth, bend = BEND, lateGrowth = late }
	for id, track in UpgradesConfig.tracks do
		local copy = table.clone(track)
		local shape = SHAPE[id]
		if shape then
			copy.maxLevel = shape.maxLevel
			copy.perLevel = shape.perLevel
			copy.cost = cost
		end
		config.tracks[id] = copy
	end
	-- the slots at the price of level 5, 12 and 22 of the others
	local probe = { tracks = { x = { maxLevel = 25, cost = cost } }, priceDigits = 6 }
	local c5 = Upgrades.cost("x", 5, probe) :: number
	local c12 = Upgrades.cost("x", 12, probe) :: number
	local c22 = Upgrades.cost("x", 22, probe) :: number
	config.tracks.slots.cost = { base = c5, growth = c12 / c5, bend = 1, lateGrowth = c22 / c12 }
	return config
end

local function hours(minutes: number?): string
	return if minutes then string.format("%.1f h", minutes / 60) else "> " .. HOURS .. " h"
end

local rows = {}
for growth = 1.3, 2.01, 0.1 do
	for late = 1.04, 1.25, 0.03 do
		local low, high = 1, 100000
		for _ = 1, 14 do
			local base = math.sqrt(low * high)
			local result = Progression.median(proposal(base, growth, late), 3, RUNS, nil, 6)
			if (result.reached[5] or math.huge) > 60 then
				high = base
			else
				low = base
			end
		end
		local base = math.sqrt(low * high)
		local result = Progression.median(proposal(base, growth, late), HOURS, RUNS, nil, 30)
		local half = result.reached[13] or math.huge
		local top = result.allMax or math.huge
		local miss = math.abs(math.log(half / GOAL.half)) + math.abs(math.log(top / GOAL.top))
		table.insert(rows, {
			miss = miss,
			text = string.format(
				"| %.2f | %.2f | %.0f | %.1f min | %s | %s | %s |",
				growth,
				late,
				base,
				result.firstUpgrade or -1,
				hours(result.reached[5]),
				hours(result.reached[13]),
				hours(result.allMax)
			),
		})
	end
end
table.sort(rows, function(a, b)
	return a.miss < b.miss
end)
print("| growth | late growth | base | first upgrade | all level 5 | all level 13 (half) | all at top |")
print("|---|---|---|---|---|---|---|")
for index = 1, math.min(10, #rows) do
	print(rows[index].text)
end
