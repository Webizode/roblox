-- lune run scripts/loot-load
-- How many spilled scoops lie around on a full server, and how often the cap Config/Loot.maxFree pushes the oldest
-- out (Loot.makeRoom), for several lifetimes and caps. The game's rules: what falls (Economy.keepOnTopple), the cap.
-- The assumptions, not measured yet (the kill test logs topples per serve, not per minute):
--   players            12 (a full server)
--   spills per minute  per player: 0.15 normal (about 0.4 topples per serve as in the kill test, a serve every 3 to
--                      4 minutes), 0.4 in a heavy fight
--   tower              8 to 24 scoops when it falls
--   picked up          60 % of the fallen scoops are picked up, after 15 s on average (owner, thieves); the rest lies
--                      until its lifetime ends
-- Prints for each case: free scoops on average and at most, the share of time at the cap, and the scoops the cap
-- pushed out per hour (the oldest, which were going to vanish anyway).

local Economy = require("../src/shared/Economy")
local Loot = require("../src/shared/Loot")
local EconomyConfig = require("../src/shared/Config/Economy")
local LootConfig = require("../src/shared/Config/Loot")

local PLAYERS = 12
local HOURS = 2
local PICKED = 0.6
local PICK_MEAN = 15
local STEP = 0.5 -- seconds

local function newRandom(seed: number)
	local state = seed % 2147483646 + 1
	return function(): number
		state = state * 48271 % 2147483647
		return (state - 1) / 2147483646
	end
end

local function run(spillsPerMinute: number, lifetime: number, cap: number, seed: number)
	local random = newRandom(seed)
	local config = table.clone(LootConfig)
	config.maxFree = cap
	local free = {} -- end times, oldest first
	local sum, peak, atCap, pushed, samples = 0, 0, 0, 0, 0
	local chance = spillsPerMinute * PLAYERS / 60 * STEP
	local t = 0
	while t < HOURS * 3600 do
		t += STEP
		-- scoops whose time is up or that were picked up
		for index = #free, 1, -1 do
			if free[index] <= t then
				table.remove(free, index)
			end
		end
		if random() < chance then
			local size = 8 + math.floor(random() * 17)
			local fell = size - Economy.keepOnTopple(size, EconomyConfig)
			local remove, kept = Loot.makeRoom(#free, fell, config)
			pushed += remove + (fell - kept)
			table.sort(free)
			for _ = 1, remove do
				table.remove(free, 1)
			end
			for _ = 1, kept do
				local endAt = t + lifetime
				if random() < PICKED then
					endAt = math.min(endAt, t - PICK_MEAN * math.log(1 - random()))
				end
				table.insert(free, endAt)
			end
		end
		samples += 1
		sum += #free
		peak = math.max(peak, #free)
		if #free >= cap then
			atCap += 1
		end
	end
	return sum / samples, peak, atCap / samples, pushed / HOURS
end

print("| fights | lifetime | maxFree | on average | at most | time at the cap | pushed out per hour |")
print("|---|---|---|---|---|---|---|")
for _, case in { { "normal", 0.15 }, { "heavy", 0.4 } } do
	for _, lifetime in { 20, 45 } do
		for _, cap in { 40, 60 } do
			local avg, peak, share, pushed = 0, 0, 0, 0
			local runs = 5
			for seed = 1, runs do
				local a, p, s, x = run(case[2], lifetime, cap, seed * 101)
				avg += a / runs
				peak = math.max(peak, p)
				share += s / runs
				pushed += x / runs
			end
			print(
				string.format(
					"| %s | %d s | %d | %.1f | %d | %.1f %% | %.0f |",
					case[1],
					lifetime,
					cap,
					avg,
					peak,
					share * 100,
					pushed
				)
			)
		end
	end
end
