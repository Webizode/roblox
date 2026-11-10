--!strict
-- Pure rules for the leaderboard (no Roblox globals): turning an OrderedDataStore page into clean rows and writing
-- coin numbers for the board. LeaderboardService does the store calls and draws the rows.

local LeaderboardRules = {}

export type Entry = { key: string, value: number }
export type Row = { rank: number, userId: number, coins: number }

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- The value written for a player: whole coins, never negative, NaN or infinite (OrderedDataStore wants integers).
function LeaderboardRules.storedCoins(coins: any): number
	if not isFinite(coins) then
		return 0
	end
	return math.max(0, math.floor(coins))
end

-- The rows of a board from a sorted page (highest first): keys that are not user ids and bad values are dropped,
-- each user once, at most `count` rows, ranked 1.. in order. Ties keep the page's order.
function LeaderboardRules.rows(entries: { Entry }, count: number): { Row }
	local rows: { Row } = {}
	local seen: { [number]: boolean } = {}
	for _, entry in entries do
		if #rows >= count then
			break
		end
		local userId = tonumber(entry.key)
		if userId and userId > 0 and userId == math.floor(userId) and not seen[userId] and isFinite(entry.value) then
			seen[userId] = true
			table.insert(rows, { rank = #rows + 1, userId = userId, coins = LeaderboardRules.storedCoins(entry.value) })
		end
	end
	return rows
end

-- Coins for the board: 1,234,567 up to a million, then 1.2M / 12.5M / 1.2B, so the column stays narrow.
function LeaderboardRules.formatCoins(coins: number): string
	local n = LeaderboardRules.storedCoins(coins)
	if n >= 1e9 then
		return string.format("%.1fB", math.floor(n / 1e8) / 10)
	elseif n >= 1e6 then
		return string.format("%.1fM", math.floor(n / 1e5) / 10)
	end
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- Whether a player's coins have to be written again: changed since the last write and the last write is at least
-- `interval` seconds old (or there was none).
function LeaderboardRules.dueWrite(
	coins: number,
	lastCoins: number?,
	lastAt: number?,
	now: number,
	interval: number
): boolean
	if lastCoins == coins then
		return false
	end
	return lastAt == nil or now - lastAt >= interval
end

return LeaderboardRules
