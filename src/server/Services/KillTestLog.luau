-- Records what the week-1 kill test needs: serve heights, topples and session length per control variant.
-- Prints a summary every two minutes and on shutdown, and mirrors it as JSON in ServerStorage.KillTestLog
-- so it can be read through the Studio MCP during a playtest.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local KillTestLog = {}

type Serve = { userId: number, variant: string, count: number, value: number, carry: number, minute: number }
type Topple = { userId: number, variant: string, count: number, cause: string }
type Session = { userId: number, name: string, joinedAt: number, leftAt: number?, variants: { string } }

local serves: { Serve } = {}
local topples: { Topple } = {}
local sessions: { [number]: Session } = {}
local dirty = false
local mirror: StringValue

local function now(): number
	return workspace:GetServerTimeNow()
end

local function median(values: { number }): number?
	if #values == 0 then
		return nil
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	local middle = #sorted // 2
	if #sorted % 2 == 1 then
		return sorted[middle + 1]
	end
	return (sorted[middle] + sorted[middle + 1]) / 2
end

local function format(value: number?): string
	return if value then string.format("%.1f", value) else "-"
end

function KillTestLog.summary(): string
	local lines = { "[KillTest] summary" }
	local variants = {}
	for _, serve in serves do
		variants[serve.variant] = true
	end
	for _, topple in topples do
		variants[topple.variant] = true
	end

	for _, variant in { "A", "B", "C" } do
		if variants[variant] then
			local heights, lateHeights, toppleHeights = {}, {}, {}
			for _, serve in serves do
				if serve.variant == variant then
					table.insert(heights, serve.count)
					if serve.minute >= 5 then
						table.insert(lateHeights, serve.count)
					end
				end
			end
			for _, topple in topples do
				if topple.variant == variant then
					table.insert(toppleHeights, topple.count)
				end
			end
			table.insert(
				lines,
				string.format(
					"  variant %s: %d serves, median height %s (after minute 5: %s), %d topples at median %s",
					variant,
					#heights,
					format(median(heights)),
					format(median(lateHeights)),
					#toppleHeights,
					format(median(toppleHeights))
				)
			)
		end
	end

	for _, session in sessions do
		local minutes = ((session.leftAt or now()) - session.joinedAt) / 60
		table.insert(
			lines,
			string.format(
				"  %s: %.1f min, variants %s%s",
				session.name,
				minutes,
				table.concat(session.variants, ">"),
				if session.leftAt then "" else " (still playing)"
			)
		)
	end
	return table.concat(lines, "\n")
end

local function flush()
	if not dirty then
		return
	end
	dirty = false
	-- sessions are keyed by UserId; JSONEncode only takes arrays or string keys
	local sessionList = {}
	for _, session in sessions do
		table.insert(sessionList, session)
	end
	mirror.Value = HttpService:JSONEncode({ serves = serves, topples = topples, sessions = sessionList })
end

local function changed()
	dirty = true
	task.defer(flush)
end

function KillTestLog.join(player: Player, variant: string)
	sessions[player.UserId] = {
		userId = player.UserId,
		name = player.Name,
		joinedAt = now(),
		leftAt = nil,
		variants = { variant },
	}
	changed()
end

function KillTestLog.leave(player: Player)
	local session = sessions[player.UserId]
	if session then
		session.leftAt = now()
		changed()
		print(KillTestLog.summary())
	end
end

function KillTestLog.variant(player: Player, variant: string)
	local session = sessions[player.UserId]
	if session then
		table.insert(session.variants, variant)
		changed()
	end
end

function KillTestLog.serve(
	player: Player,
	variant: string,
	count: number,
	value: number,
	carry: number,
	sinceJoin: number
)
	table.insert(serves, {
		userId = player.UserId,
		variant = variant,
		count = count,
		value = math.floor(value),
		carry = math.floor(carry * 10) / 10,
		minute = math.floor(sinceJoin / 60),
	})
	changed()
end

function KillTestLog.topple(player: Player, variant: string, count: number, cause: string)
	table.insert(topples, { userId = player.UserId, variant = variant, count = count, cause = cause })
	changed()
end

function KillTestLog.Init()
	mirror = Instance.new("StringValue")
	mirror.Name = "KillTestLog"
	mirror.Parent = ServerStorage
end

function KillTestLog.Start()
	game:BindToClose(function()
		print(KillTestLog.summary())
	end)
	while true do
		task.wait(120)
		if #serves > 0 or #topples > 0 then
			print(KillTestLog.summary())
		end
	end
end

return KillTestLog
