--!strict
-- The steady stance's energy bar, shared by the client (HUD and its own prediction) and the server (the truth).
-- Holding the stance drains the bar, a full one lasts holdSeconds; once released it refills in refillSeconds after
-- a short refillDelay. A new stance needs at least minStart of it, so an empty bar cannot be tapped back on.
-- Pure: no Roblox globals, the config comes in as an argument. tests/Stance.spec.luau covers it.

export type Config = {
	holdSeconds: number,
	refillSeconds: number,
	refillDelay: number,
	minStart: number,
}

export type Meter = {
	energy: number, -- 0 empty, 1 full
	active: boolean,
	idleFor: number, -- seconds since the stance ended, for the refill delay
}

local Stance = {}

function Stance.new(): Meter
	return { energy = 1, active = false, idleFor = 0 }
end

-- Whether a stance could start now. `slack` lets the server accept a start that its own bar, a little behind the
-- client's after network jitter, would just refuse.
function Stance.canStart(meter: Meter, config: Config, slack: number?): boolean
	return not meter.active and meter.energy >= config.minStart - (slack or 0)
end

-- Starts the stance if the bar allows it. Returns whether it is on.
function Stance.start(meter: Meter, config: Config, slack: number?): boolean
	if Stance.canStart(meter, config, slack) then
		meter.active = true
	end
	return meter.active
end

function Stance.stop(meter: Meter)
	if meter.active then
		meter.active = false
		meter.idleFor = 0
	end
end

-- Moves the bar on by dt. Returns true when the stance ran out of energy in this call and was stopped.
function Stance.advance(meter: Meter, dt: number, config: Config): boolean
	if meter.active then
		meter.energy -= dt / config.holdSeconds
		if meter.energy <= 0 then
			meter.energy = 0
			Stance.stop(meter)
			return true
		end
		return false
	end
	local before = meter.idleFor
	meter.idleFor += dt
	local refilling = meter.idleFor - math.max(before, config.refillDelay)
	if refilling > 0 then
		meter.energy = math.min(1, meter.energy + refilling / config.refillSeconds)
	end
	return false
end

return Stance
