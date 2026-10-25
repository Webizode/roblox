-- Records what the week-1 kill test needs: serve heights, topples, picked-up spilled scoops (own and foreign) and
-- session length, serves and topples grouped by control scheme
-- (today only "auto": WASD plus the automatic stabiliser and the steady stance).
-- Prints a summary every two minutes and on shutdown, and mirrors it as JSON in ServerStorage.KillTestLog
-- so it can be read through the Studio MCP during a playtest.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local KillTestLog = {}

type Serve = { userId: number, controls: string, count: number, value: number, carry: number, minute: number }
type Topple = { userId: number, controls: string, count: number, cause: string }
type Session = { userId: number, name: string, joinedAt: number, leftAt: number? }
type Pickup = { userId: number, ownerId: number, foreign: boolean }

local serves: { Serve } = {}
local topples: { Topple } = {}
local sessions: { [number]: Session } = {}
local pickups: { Pickup } = {}
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
		local own, foreign = 0, 0
		for _, pickup in pickups do
			if pickup.userId == session.userId then
				if pickup.foreign then
					foreign += 1
				else
					own += 1
				end
			end
		end
		table.insert(
			lines,
			string.format(
				"  %s: %.1f min%s, picked up %d foreign and %d own spilled scoops",
				session.name,
				minutes,
				if session.leftAt then "" else " (still playing)",
				foreign,
				own
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
	mirror.Value =
		HttpService:JSONEncode({ serves = serves, topples = topples, pickups = pickups, sessions = sessionList })
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

-- A spilled scoop picked up; ownerId is the UserId of the player whose tower it fell from.
function KillTestLog.pickup(player: Player, ownerId: number)
	table.insert(pickups, { userId = player.UserId, ownerId = ownerId, foreign = ownerId ~= player.UserId })
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
		if #serves > 0 or #topples > 0 or #pickups > 0 then
			print(KillTestLog.summary())
		end
	end
end

return KillTestLog
