--!strict
-- The dash's charges (Config/Tower.dash): up to `charges` dashes stored, each one recharging on its own in `recharge`
-- seconds, one after the other; two dashes need at least `minGap` seconds between them. So two dashes can go right
-- after each other, then there is a short wait. Pure: the server (TowerService) keeps the real count, the client
-- (TowerController) the same rules for its own requests and the HUD's dash bar.

export type State = {
	charges: number, -- whole charges ready
	refillAt: number, -- when the next charge is ready (only while charges < max)
	lastAt: number, -- the last dash, for minGap
}

export type Config = { charges: number, recharge: number, minGap: number }

local DashCharges = {}

-- Full, ready at once.
function DashCharges.new(config: Config): State
	return { charges = config.charges, refillAt = 0, lastAt = -math.huge }
end

-- Counts in the charges that have come back by `now`, one recharge after the other.
function DashCharges.refresh(state: State, now: number, config: Config)
	while state.charges < config.charges and now >= state.refillAt do
		state.charges += 1
		if state.charges < config.charges then
			state.refillAt += config.recharge
		end
	end
end

-- Whether a dash may go at `now` (`slack` seconds of network jitter allowed on the gap and the recharge); uses a
-- charge when it may.
function DashCharges.tryUse(state: State, now: number, config: Config, slack: number?): boolean
	local give = slack or 0
	DashCharges.refresh(state, now + give + 1e-6, config)
	if state.charges < 1 or now - state.lastAt < config.minGap - give - 1e-6 then
		return false
	end
	if state.charges >= config.charges then
		-- the first one used from a full bar starts the recharge
		state.refillAt = now + config.recharge
	end
	state.charges -= 1
	state.lastAt = now
	return true
end

-- How full each of the bar's segments is at `now` (0..1, the first segment first): the ready charges are full, the
-- one recharging fills up, the rest are empty.
function DashCharges.segments(state: State, now: number, config: Config): { number }
	DashCharges.refresh(state, now, config)
	local fills = table.create(config.charges, 0)
	for index = 1, config.charges do
		if index <= state.charges then
			fills[index] = 1
		elseif index == state.charges + 1 then
			fills[index] = 1 - math.clamp((state.refillAt - now) / config.recharge, 0, 1)
		end
	end
	return fills
end

return DashCharges
