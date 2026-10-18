--!strict
-- Deterministic inverted-pendulum model of a scoop tower.
--
-- Pure Luau with no Roblox globals: the owning client runs it at a fixed step, the server can run it for
-- plausibility checks, and Lune tests run it headless. Tilt is a 2D vector in world space (x, z) in radians;
-- a positive x means the top leans towards +X.
--
--   tilt'' = gravity*sin(tilt) - stiffness*tilt - damping*tilt' - accelGain*accel + padGain*pad + drift
--
-- gravity grows with the centre of mass of the stack, so short towers are self-righting and tall towers
-- become unstable and must be balanced actively. Accelerating the base towards the lean reduces it, like
-- balancing a broom on your hand.

export type FlavorPhysics = {
	mass: number,
	stiffness: number,
	damping: number,
	jerk: number,
}

export type Variant = {
	accelGain: number,
	padGain: number,
}

export type Tuning = {
	tipAngle: number,
	groanFraction: number,
	groanDuration: number,
	gravityGain: number,
	baseStiffness: number,
	baseDamping: number,
	minDamping: number,
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

	local driftX = params.drift * wander(state.seed, state.t, 1)
	local driftZ = params.drift * wander(state.seed, state.t, 2)

	if params.jerk > 0 then
		local interval = math.max(1, math.floor(tuning.jerkInterval / dt + 0.5))
		if state.step % interval == 0 then
			local angle = (hash(state.seed, state.step) % 6283) / 1000
			local strength = params.jerk * tuning.jerkStrength
			state.vx += math.cos(angle) * strength
			state.vz += math.sin(angle) * strength
		end
	end

	local accelX = params.gravity * math.sin(state.x)
		- params.stiffness * state.x
		- params.damping * state.vx
		- variant.accelGain * input.ax
		+ variant.padGain * input.padX
		+ driftX
	local accelZ = params.gravity * math.sin(state.z)
		- params.stiffness * state.z
		- params.damping * state.vz
		- variant.accelGain * input.az
		+ variant.padGain * input.padZ
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
