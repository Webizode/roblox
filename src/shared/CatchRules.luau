--!strict
-- The server's rules for a catch claim. Pure: ShotMath and TowerShape are passed in, so Lune tests can prove
-- that honest claims pass under latency and forged ones still fail.
--
-- The client reports the server time at which its scoop touched the tower and the tilt it had then. The server
-- replays the scoop at that time against the tower column built from the character it sees, which lags the
-- client by the same uplink delay as the claim, so both look at the same moment.

export type Claim = {
	claimTime: any,
	tiltX: any,
	tiltZ: any,
}

export type Shot = {
	fx: number,
	fy: number,
	fz: number,
	tx: number,
	ty: number,
	tz: number,
	apex: number,
	t0: number,
	flight: number,
}

export type Tower = {
	baseX: number,
	baseY: number,
	baseZ: number,
	count: number,
	speed: number, -- horizontal root speed, already capped by the caller
}

export type Rules = {
	catchRadius: number,
	serverTolerance: number,
	serverSpeedLead: number,
	maxClaimAge: number,
	maxClaimLead: number,
	apexSlack: number,
	catchWindowEnd: number,
	claimSweep: number,
	contactStep: number,
}

export type Result = {
	ok: boolean,
	reason: string,
	distance: number?,
}

local CatchRules = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- tilt is clamped to what an honest tower can reach, so a forged tilt cannot stretch the column
local function clampTilt(x: number, z: number, tipAngle: number): (number, number)
	local tilt = math.sqrt(x * x + z * z)
	if tilt > tipAngle then
		return x / tilt * tipAngle, z / tilt * tipAngle
	end
	return x, z
end

function CatchRules.check(
	claim: Claim,
	shot: Shot,
	tower: Tower,
	now: number,
	rules: Rules,
	towerTuning: any,
	ShotMath: any,
	TowerShape: any
): Result
	if not isFinite(claim.claimTime) or not isFinite(claim.tiltX) or not isFinite(claim.tiltZ) then
		return { ok = false, reason = "bad arguments" }
	end
	local claimTime: number = claim.claimTime
	if claimTime > now + rules.maxClaimLead then
		return { ok = false, reason = "claim time in the future" }
	end
	if claimTime < now - rules.maxClaimAge then
		return { ok = false, reason = "claim too old" }
	end

	local alpha = (claimTime - shot.t0) / shot.flight
	local apexAlpha = ShotMath.apexAlpha(shot.fy, shot.ty, shot.apex)
	local windowStart = apexAlpha - rules.apexSlack
	if alpha < windowStart then
		return { ok = false, reason = "scoop still rising" }
	end
	if alpha > rules.catchWindowEnd then
		return { ok = false, reason = "scoop already landed" }
	end

	local tiltX, tiltZ = clampTilt(claim.tiltX, claim.tiltZ, towerTuning.tipAngle)
	local offsets = TowerShape.column(tower.count, tiltX, tiltZ, towerTuning)
	local points = table.create(#offsets)
	for index = 1, #offsets, 3 do
		points[index] = tower.baseX + offsets[index]
		points[index + 1] = tower.baseY + offsets[index + 1]
		points[index + 2] = tower.baseZ + offsets[index + 2]
	end

	local radius = rules.catchRadius + rules.serverTolerance + math.max(0, tower.speed) * rules.serverSpeedLead
	local sweep = rules.claimSweep / shot.flight
	local from = math.max(windowStart, alpha - sweep)
	local to = math.min(rules.catchWindowEnd, alpha + sweep)
	if ShotMath.firstContact(shot, from, to, points, radius, rules.contactStep) then
		return { ok = true, reason = "ok" }
	end

	local x, y, z = ShotMath.position(shot.fx, shot.fy, shot.fz, shot.tx, shot.ty, shot.tz, shot.apex, alpha)
	return {
		ok = false,
		reason = "too far from the tower",
		distance = ShotMath.distanceToPolyline(x, y, z, points),
	}
end

return CatchRules
