-- Records what the week-1 kill test needs: serve heights, topples and session length, grouped by control scheme
-- (today only "auto": WASD plus the automatic stabiliser and the rescue).
-- Prints a summary every two minutes and on shutdown, and mirrors it as JSON in ServerStorage.KillTestLog
-- so it can be read through the Studio MCP during a playtest.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local KillTestLog = {}

type Serve = { userId: number, controls: string, count: number, value: number, carry: number, minute: number }
type Topple = { userId: number, controls: string, count: number, cause: string }
type Session = { userId: number, name: string, joinedAt: number, leftAt: number? }

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
	local seen, schemes = {}, {}
	for _, entry in serves do
		seen[entry.controls] = true
	end
	for _, entry in topples do
		seen[entry.controls] = true
	end
	for scheme in seen do
		table.insert(schemes, scheme)
	end
	table.sort(schemes)

	for _, scheme in schemes do
		local heights, lateHeights, toppleHeights = {}, {}, {}
		for _, serve in serves do
			if serve.controls == scheme then
				table.insert(heights, serve.count)
				if serve.minute >= 5 then
					table.insert(lateHeights, serve.count)
				end
			end
		end
		for _, topple in topples do
			if topple.controls == scheme then
				table.insert(toppleHeights, topple.count)
			end
		end
		table.insert(
			lines,
			string.format(
				"  controls %s: %d serves, median height %s (after minute 5: %s), %d topples at median %s",
				scheme,
				#heights,
				format(median(heights)),
				format(median(lateHeights)),
				#toppleHeights,
				format(median(toppleHeights))
			)
		)
	end

	for _, session in sessions do
		local minutes = ((session.leftAt or now()) - session.joinedAt) / 60
		table.insert(
			lines,
			string.format("  %s: %.1f min%s", session.name, minutes, if session.leftAt then "" else " (still playing)")
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

function KillTestLog.join(player: Player)
	sessions[player.UserId] = {
		userId = player.UserId,
		name = player.Name,
		joinedAt = now(),
		leftAt = nil,
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

function KillTestLog.serve(
	player: Player,
	controls: string,
	count: number,
	value: number,
	carry: number,
	sinceJoin: number
)
	table.insert(serves, {
		userId = player.UserId,
		controls = controls,
		count = count,
		value = math.floor(value),
		carry = math.floor(carry * 10) / 10,
		minute = math.floor(sinceJoin / 60),
	})
	changed()
end

function KillTestLog.topple(player: Player, controls: string, count: number, cause: string)
	table.insert(topples, { userId = player.UserId, controls = controls, count = count, cause = cause })
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
