-- lune run scripts/progression [hours] [runs]
-- The progression simulation (scripts/lib/Progression.luau) with Config/Upgrades: when the first upgrade is bought,
-- when every upgrade reaches a level, the levels and coins over the hours of play. The median of `runs` players.
-- The assumptions about how a person plays are Progression.PLAY; a second table shows a slower and a faster player.

local process = require("@lune/process")

local Progression = require("./lib/Progression")
local Upgrades = require("../src/shared/Upgrades")
local UpgradesConfig = require("../src/shared/Config/Upgrades")

local hours = tonumber(process.args[1]) or 60
local runs = tonumber(process.args[2]) or 9

local function clock(minutes: number?): string
	if not minutes then
		return "never"
	end
	if minutes < 60 then
		return string.format("%.0f min", minutes)
	end
	return string.format("%.1f h", minutes / 60)
end

local function coins(value: number): string
	local text = tostring(math.floor(value))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1.")))
	return (string.gsub(formatted, "^%.", ""))
end

local function report(title: string, play: { [string]: any }?)
	local result = Progression.median(UpgradesConfig, hours, runs, play, 6)
	local sold = Upgrades.visible(UpgradesConfig)
	local top = 0
	for _, id in sold do
		top = math.max(top, UpgradesConfig.tracks[id].maxLevel)
	end
	-- levels count as a share of the longest track (Progression.run `reached`)
	local half = math.ceil(top / 2)
	print(`\n== {title} ==`)
	print("first upgrade after " .. clock(result.firstUpgrade))
	for _, level in { 1, 5, 10, half, 20 } do
		print(string.format("every upgrade at level %d or more after %s", level, clock(result.reached[level])))
	end
	print("every upgrade at its top after " .. clock(result.allMax))

	local header = "| play time | coins held | earned |"
	local line = "|---|---|---|"
	for _, id in sold do
		header ..= ` {UpgradesConfig.tracks[id].label} |`
		line ..= "---|"
	end
	print("\n" .. header)
	print(line)
	for _, at in { 0.1, 0.25, 0.5, 1, 2, 3, 5, 10, 15, 20, 30, 40, 50, 60 } do
		if at <= hours then
			local snap = result.snapshots[math.floor(at * 60 / 6 + 0.5) + 1]
			if snap then
				local row = string.format("| %s | %s | %s |", clock(at * 60), coins(snap.coins), coins(snap.earned))
				for _, id in sold do
					row ..= string.format(" %d/%d |", snap.levels[id], UpgradesConfig.tracks[id].maxLevel)
				end
				print(row)
			end
		end
	end
end

report("typical player (Progression.PLAY)")
local slow = Progression.PLAY.catchesPerMinute * 0.6
local fast = 6.8 * 1.1
report(string.format("slower player (%.1f catches a minute)", slow), { catchesPerMinute = slow })
report(string.format("fast player (%.1f catches a minute)", fast), { catchesPerMinute = fast })
