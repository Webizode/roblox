--!strict
-- Deterministic inverted-pendulum model of a scoop tower.
--
-- Pure Luau with no Roblox globals: the owning client runs it at a fixed step, the server can run it for
-- plausibility checks, and Lune tests run it headless. Tilt is a 2D vector in world space (x, z) in radians;
-- a positive x means the top leans towards +X.
--
--   tilt'' = gravity*sin(tilt) - stiffness*tilt - damping*tilt' - accelGain*accel + padAuthority*pad + drift
--
-- gravity grows with the centre of mass of the stack, so short towers are self-righting and tall towers
-- become unstable and must be balanced actively. Accelerating the base towards the lean reduces it, like
-- balancing a broom on your hand.
--
-- padAuthority grows with how unstable the tower is (gravity - stiffness). A fixed pad strength was either too
-- weak for tall towers or so strong that holding a key toppled a one-scoop tower in under a second.

export type FlavorPhysics = {
	mass: number,
	stiffness: number,
	damping: number,
	jerk: number,
}

export type Variant = {
	accelGain: number,
	-- extra leverage from walking on unstable towers: accelGain * (1 + accelPerInstability * instability)
	accelPerInstability: number?,
	padGain: number, -- multiplier on the pad authority, 0 when the variant has no pad
	driftScale: number?, -- multiplier on the random wandering, 1 when omitted
}

export type Tuning = {
	tipAngle: number,
	groanFraction: number,
	groanDuration: number,
	gravityGain: number,
	baseStiffness: number,
	baseDamping: number,
	minDamping: number,
	padBase: number,
	padPerInstability: number,
	padMax: number,
	padWrongWay: number,
	driftStartScoops: number,
	driftPerScoop: number,
	jerkInterval: number,
	jerkStrength: number,
	landingKick: number,
	steady: {
		minScoops: number,
		fraction: number,
		ratePerSecond: number,
		max: number,
	},
}

export type Params = {
	count: number,
	gravity: number,
	stiffness: number,
	damping: number,
	drift: number,
	jerk: number,
}

export type State = {
	x: number,
	z: number,
	vx: number,
	vz: number,
	t: number,
	step: number,
	seed: number,
	groan: number, -- seconds spent above the groan threshold, 0 when not groaning
	toppled: boolean,
	steadySeconds: number,
	rigidUntil: number,
	unsteadyUntil: number, -- after a dash: corrections only partly land until this time
	unsteadyFactor: number,
	seenX: number, -- the lean as the automatic stabiliser sees it: smoothed, so it reacts late
	seenZ: number,
	seenVx: number,
	seenVz: number,
	rescueUntil: number,
}

export type Input = {
	ax: number, -- base acceleration in studs/s^2, world space
	az: number,
	padX: number, -- corrective input in [-1, 1], world space
	padZ: number,
}

-- Events returned by step(). At most one per step.
export type Event = "groan" | "saved" | "toppled"

local TowerModel = {}

local NO_INPUT: Input = table.freeze({ ax = 0, az = 0, padX = 0, padZ = 0 })
TowerModel.NO_INPUT = NO_INPUT

function TowerModel.newState(seed: number): State
	return {
		x = 0,
		z = 0,
		vx = 0,
		vz = 0,
		t = 0,
		step = 0,
		seed = seed,
		groan = 0,
		toppled = false,
		steadySeconds = 0,
		rigidUntil = 0,
		unsteadyUntil = 0,
		unsteadyFactor = 1,
		seenX = 0,
		seenZ = 0,
		seenVx = 0,
		seenVz = 0,
		rescueUntil = 0,
	}
end

-- Clears tilt and per-carry progress but keeps the clock and seed, so drift continues smoothly.
function TowerModel.reset(state: State)
	state.x = 0
	state.z = 0
	state.vx = 0
	state.vz = 0
	state.groan = 0
	state.toppled = false
	state.steadySeconds = 0
	state.rigidUntil = 0
	state.unsteadyUntil = 0
	state.seenX, state.seenZ, state.seenVx, state.seenVz = 0, 0, 0, 0
	state.rescueUntil = 0
end

-- flavorIds are bottom to top. stiffnessMultiplier comes from the cone upgrade.
function TowerModel.params(
	flavorIds: { string },
	flavors: { [string]: FlavorPhysics },
	tuning: Tuning,
	stiffnessMultiplier: number
): Params
	local count = #flavorIds
	local totalMass = 0
	local weightedHeight = 0
	local stiffness = tuning.baseStiffness * stiffnessMultiplier
	local damping = tuning.baseDamping
	local jerk = 0

	for index, id in flavorIds do
		local flavor = flavors[id]
		local mass = if flavor then flavor.mass else 1
		totalMass += mass
		weightedHeight += mass * index
		if flavor then
			stiffness += flavor.stiffness
			damping += flavor.damping
			jerk += flavor.jerk
		end
	end

	local centreOfMass = if totalMass > 0 then weightedHeight / totalMass else 0
	local drift = 0
	if count >= tuning.driftStartScoops then
		drift = tuning.driftPerScoop * (count - tuning.driftStartScoops + 1)
	end

	return {
		count = count,
		gravity = tuning.gravityGain * centreOfMass,
		stiffness = stiffness,
		damping = math.max(tuning.minDamping, damping),
		drift = drift,
		jerk = jerk,
	}
end

-- Smooth, deterministic wandering in [-1, 1]. Two incommensurate sines per axis never repeat visibly.
local function wander(seed: number, t: number, axis: number): number
	local a = math.sin(t * (0.61 + 0.07 * axis) + seed * 1.37 + axis)
	local b = math.sin(t * (1.73 + 0.11 * axis) + seed * 2.11 + 3 * axis)
	return (a + 0.5 * b) / 1.5
end

-- Deterministic integer hash for the cursed pickle kicks.
local function hash(seed: number, step: number): number
	return (seed * 73856093 + step * 19349663) % 2147483647
end

function TowerModel.tilt(state: State): number
	return math.sqrt(state.x * state.x + state.z * state.z)
end

function TowerModel.impulse(state: State, ix: number, iz: number)
	if state.toppled then
		return
	end
	state.vx += ix
	state.vz += iz
end

export type AssistTuning = {
	kp: number,
	kd: number,
	lag: number,
	strength: number,
	fadeFrom: number,
	fadeTo: number,
	fullUntil: number,
	zeroAt: number,
	floor: number,
}

-- The automatic stabiliser, fed into step() as pad input (so the pad authority and the full-strength-only-
-- against-the-lean rule apply to it). It is deliberately imperfect: it sees the lean late (smoothed over
-- assist.lag), gives up between fadeFrom and fadeTo of the tip angle, and gets weaker on taller towers. Small
-- wobbles go away by themselves; a big lean, fast turns and tall towers need the rescue. During a rescue it
-- works on the real lean without the delay, with at most rescue.authority rad/s^2, so a late rescue on a tall,
-- groaning tower can fail. Call once per step, before step().
function TowerModel.assist(
	state: State,
	params: Params,
	variant: Variant,
	tuning: Tuning & { assist: AssistTuning, rescue: { authority: number } },
	dt: number
): (number, number)
	local assist = tuning.assist
	local tipAngle = tuning.tipAngle
	local blend = math.min(1, dt / assist.lag)
	state.seenX += (state.x - state.seenX) * blend
	state.seenZ += (state.z - state.seenZ) * blend
	state.seenVx += (state.vx - state.seenVx) * blend
	state.seenVz += (state.vz - state.seenVz) * blend
	if params.count == 0 or state.toppled then
		return 0, 0
	end

	if state.t < state.rescueUntil then
		local limit = math.min(1, tuning.rescue.authority / TowerModel.padAuthority(params, variant, tuning))
		return math.clamp(-(assist.kp * state.x + assist.kd * state.vx), -limit, limit),
			math.clamp(-(assist.kp * state.z + assist.kd * state.vz), -limit, limit)
	end

	local seen = math.sqrt(state.seenX * state.seenX + state.seenZ * state.seenZ) / tipAngle
	local fade = math.clamp((assist.fadeTo - seen) / (assist.fadeTo - assist.fadeFrom), 0, 1)
	local height = math.clamp((assist.zeroAt - params.count) / (assist.zeroAt - assist.fullUntil), 0, 1)
	local share = assist.strength * fade * (assist.floor + (1 - assist.floor) * height)
	return math.clamp(-(assist.kp * state.seenX + assist.kd * state.seenVx), -share, share),
		math.clamp(-(assist.kp * state.seenZ + assist.kd * state.seenVz), -share, share)
end

-- Starts a rescue window (the server has already checked the cooldown).
function TowerModel.rescue(state: State, duration: number)
	if not state.toppled then
		state.rescueUntil = state.t + duration
	end
end

-- The rescue cooldown, shared by server and client: a new rescue `cooldown` seconds after the last one ended.
-- `slack` lets the server accept a request that network jitter brought in a little early.
function TowerModel.rescueReady(
	lastStart: number,
	now: number,
	rescue: { duration: number, cooldown: number },
	slack: number?
): boolean
	return now - lastStart >= rescue.duration + rescue.cooldown - (slack or 0)
end

function TowerModel.rescueActive(state: State): boolean
	return state.t < state.rescueUntil
end

-- A dash yanks the cone, so the top lags behind: a tilt-rate kick against the dash direction (a unit vector on the
-- ground) that grows with the scoop count, and a short window in which pad and walking corrections are weaker.
-- Returns the kick size.
function TowerModel.dashKick(
	state: State,
	dash: {
		kickBase: number,
		kickPerScoop: number,
		kickMax: number,
		unsteadySeconds: number,
		unsteadyFactor: number,
	},
	count: number,
	dirX: number,
	dirZ: number
): number
	local length = math.sqrt(dirX * dirX + dirZ * dirZ)
	if count <= 0 or length < 1e-6 then
		return 0
	end
	local kick = math.min(dash.kickMax, dash.kickBase + dash.kickPerScoop * count)
	TowerModel.impulse(state, -dirX / length * kick, -dirZ / length * kick)
	state.unsteadyUntil = state.t + dash.unsteadySeconds
	state.unsteadyFactor = dash.unsteadyFactor
	return kick
end

-- Small nudge when a scoop lands. Direction varies with the scoop count so it is never the same twice.
function TowerModel.landingKick(state: State, tuning: Tuning, count: number)
	local angle = (hash(state.seed, count * 7919) % 6283) / 1000
	TowerModel.impulse(state, math.cos(angle) * tuning.landingKick, math.sin(angle) * tuning.landingKick)
end

function TowerModel.makeRigid(state: State, seconds: number)
	state.rigidUntil = math.max(state.rigidUntil, state.t + seconds)
end

function TowerModel.steadyBonus(state: State, tuning: Tuning): number
	return math.min(tuning.steady.max, state.steadySeconds * tuning.steady.ratePerSecond)
end

-- Tilt acceleration (rad/s^2) at full pad deflection. Small towers get a gentle nudge, unstable ones enough
-- leverage to be caught again.
function TowerModel.padAuthority(params: Params, variant: Variant, tuning: Tuning): number
	local instability = math.max(0, params.gravity - params.stiffness)
	return variant.padGain * math.min(tuning.padMax, tuning.padBase + tuning.padPerInstability * instability)
end

-- How strongly base acceleration tips the tower. Walking speed is capped, so without extra leverage on
-- unstable towers a walking-only player (variant A) could never hold more than about a dozen scoops.
function TowerModel.accelAuthority(params: Params, variant: Variant): number
	local instability = math.max(0, params.gravity - params.stiffness)
	return variant.accelGain * (1 + (variant.accelPerInstability or 0) * instability)
end

-- One fixed step of the movement smoothing that feeds the tower: the base velocity eases towards the target
-- (MoveDirection * WalkSpeed) over `smoothing` seconds, and the change is the acceleration the tower feels.
-- The client and the tests share this, so the tests see the same input limits as players do.
function TowerModel.baseVelocityStep(
	vx: number,
	vz: number,
	targetX: number,
	targetZ: number,
	smoothing: number,
	dt: number
): (number, number, number, number)
	local alpha = 1 - math.exp(-dt / smoothing)
	local nextX = vx + (targetX - vx) * alpha
	local nextZ = vz + (targetZ - vz) * alpha
	return nextX, nextZ, (nextX - vx) / dt, (nextZ - vz) / dt
end

function TowerModel.step(
	state: State,
	params: Params,
	input: Input,
	variant: Variant,
	tuning: Tuning,
	dt: number
): Event?
	if state.toppled then
		return nil
	end

	state.t += dt
	state.step += 1

	if params.count == 0 then
		state.x, state.z, state.vx, state.vz = 0, 0, 0, 0
		state.groan = 0
		return nil
	end

	if state.t < state.rigidUntil then
		-- Rocky Mountain: the tower snaps upright and ignores everything for a while.
		local decay = math.exp(-12 * dt)
		state.x *= decay
		state.z *= decay
		state.vx, state.vz = 0, 0
		state.groan = 0
		return nil
	end

	local drift = params.drift * (variant.driftScale or 1)
	local driftX = drift * wander(state.seed, state.t, 1)
	local driftZ = drift * wander(state.seed, state.t, 2)
	local pad = TowerModel.padAuthority(params, variant, tuning)
	local walk = TowerModel.accelAuthority(params, variant)
	if state.t < state.unsteadyUntil then
		-- right after a dash the cone is still swinging, so corrections only partly land
		pad *= state.unsteadyFactor
		walk *= state.unsteadyFactor
	end

	if params.jerk > 0 then
		local interval = math.max(1, math.floor(tuning.jerkInterval / dt + 0.5))
		if state.step % interval == 0 then
			local angle = (hash(state.seed, state.step) % 6283) / 1000
			local strength = params.jerk * tuning.jerkStrength
			state.vx += math.cos(angle) * strength
			state.vz += math.sin(angle) * strength
		end
	end

	-- The pad corrects: the part of the input that pushes against the current lean has full strength, the rest
	-- (pushing an upright tower, pushing with the lean, pushing sideways) only padWrongWay of it. So a correct
	-- press brings the tower back and runs out of force as it passes upright, a wrong one still adds risk.
	local padX, padZ = input.padX, input.padZ
	local lean = TowerModel.tilt(state)
	local fixX, fixZ = 0, 0
	if lean > 1e-4 then
		local along = (padX * state.x + padZ * state.z) / lean
		if along < 0 then
			fixX, fixZ = along * state.x / lean, along * state.z / lean
		end
	end
	padX = fixX + (padX - fixX) * tuning.padWrongWay
	padZ = fixZ + (padZ - fixZ) * tuning.padWrongWay

	local accelX = params.gravity * math.sin(state.x)
		- params.stiffness * state.x
		- params.damping * state.vx
		- walk * input.ax
		+ pad * padX
		+ driftX
	local accelZ = params.gravity * math.sin(state.z)
		- params.stiffness * state.z
		- params.damping * state.vz
		- walk * input.az
		+ pad * padZ
		+ driftZ

	-- semi-implicit Euler: stable at 60 Hz for the stiffness range we use
	state.vx += accelX * dt
	state.vz += accelZ * dt
	state.x += state.vx * dt
	state.z += state.vz * dt

	local tilt = TowerModel.tilt(state)
	if tilt > tuning.tipAngle then
		-- clamp at the tip angle and remove the outward part of the velocity
		local nx, nz = state.x / tilt, state.z / tilt
		state.x, state.z = nx * tuning.tipAngle, nz * tuning.tipAngle
		local outward = state.vx * nx + state.vz * nz
		if outward > 0 then
			state.vx -= outward * nx
			state.vz -= outward * nz
		end
		tilt = tuning.tipAngle
	end

	if params.count >= tuning.steady.minScoops and tilt < tuning.steady.fraction * tuning.tipAngle then
		state.steadySeconds += dt
	end

	if tilt >= tuning.groanFraction * tuning.tipAngle then
		local wasGroaning = state.groan > 0
		state.groan += dt
		if state.groan >= tuning.groanDuration then
			state.toppled = true
			return "toppled"
		end
		if not wasGroaning then
			return "groan"
		end
	elseif state.groan > 0 then
		state.groan = 0
		return "saved"
	end

	return nil
end

return TowerModel
