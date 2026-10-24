--!strict
-- The steady stance's energy bar, shared by the client (HUD and its own prediction) and the server (the truth).
-- Holding the stance drains the bar, a full one lasts holdSeconds; once released it refills in refillSeconds after
-- a short refillDelay. A new stance needs at least minStart of it, so an empty bar cannot be tapped back on.
-- A throw or a dash interrupts the stance and locks it for `lockout` seconds; ice-ball hits taken in it drain the bar.
-- Pure: no Roblox globals, the config comes in as an argument. tests/Stance.spec.luau covers it.

export type Config = {
	holdSeconds: number,
	refillSeconds: number,
	refillDelay: number,
	minStart: number,
	lockout: number,
}

export type Meter = {
	energy: number, -- 0 empty, 1 full
	active: boolean,
	idleFor: number, -- seconds since the stance ended, for the refill delay
	lockedFor: number, -- seconds until a stance may start again after a throw or a dash ended one
}

local Stance = {}

function Stance.new(): Meter
	-- never held yet: idle "forever", so an early throw or dash finds no recent stance to lock
	return { energy = 1, active = false, idleFor = math.huge, lockedFor = 0 }
end

-- Whether a stance could start now. `slack` lets the server accept a start that its own bar, a little behind the
-- client's after network jitter, would just refuse; `lockSlack` does the same for the lockout, in seconds.
function Stance.canStart(meter: Meter, config: Config, slack: number?, lockSlack: number?): boolean
	return not meter.active and meter.energy >= config.minStart - (slack or 0) and meter.lockedFor <= (lockSlack or 0)
end

-- Starts the stance if the bar allows it. Returns whether it is on.
function Stance.start(meter: Meter, config: Config, slack: number?, lockSlack: number?): boolean
	if Stance.canStart(meter, config, slack, lockSlack) then
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

-- A throw or a dash: ends a running stance and locks it for config.lockout. A stance that ended less than `recent`
-- seconds before is locked too, so the server cannot be dodged by ending the stance just before the throw or dash.
-- Returns whether it locked.
function Stance.interrupt(meter: Meter, config: Config, recent: number?): boolean
	if not meter.active and meter.idleFor >= (recent or 0) then
		return false
	end
	Stance.stop(meter)
	meter.lockedFor = config.lockout
	return true
end

-- An ice-ball hit taken in the stance drains `amount` of the bar. Returns true when that emptied it and stopped the
-- stance. Outside the stance a hit costs nothing.
function Stance.drain(meter: Meter, amount: number): boolean
	if not meter.active then
		return false
	end
	meter.energy = math.max(0, meter.energy - amount)
	if meter.energy <= 0 then
		Stance.stop(meter)
		return true
	end
	return false
end

-- Moves the bar on by dt. Returns true when the stance ran out of energy in this call and was stopped.
function Stance.advance(meter: Meter, dt: number, config: Config): boolean
	meter.lockedFor = math.max(0, meter.lockedFor - dt)
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
	if refilling > 0 then -- false for a never-held bar (huge minus huge), which is full anyway
		meter.energy = math.min(1, meter.energy + refilling / config.refillSeconds)
	end
	return false
end

return Stance
