--!strict
-- The aim camera's numbers (CombatCamera; Config/Combat camera.aim): how far over the shoulder and how close the
-- camera sits while a throw is charged, how much the view narrows, and the push of the throw. Pure, so the Lune tests
-- can check it. Display only: nothing here changes where a throw goes (always through the middle of the screen).

export type Config = any -- Config/Combat

local AimCamera = {}

-- Where the eased values head while a throw is charged (`charging`; `strength` 0..1 and `perfect` as Combat gives them
-- for the hold): the blend of the shoulder move (0 normal, 1 aiming) and the field of view change in degrees
-- (negative: narrower). `fov` false leaves the view as it is (motion effects off).
function AimCamera.targets(
	charging: boolean,
	strength: number,
	perfect: boolean,
	fov: boolean,
	config: Config
): (number, number)
	if not charging then
		return 0, 0
	end
	local aim = config.camera.aim
	local degrees = 0
	if fov then
		degrees = aim.fov * math.clamp(strength, 0, 1)
		if perfect then
			degrees += aim.perfectFov
		end
	end
	return 1, degrees
end

-- Eases `current` towards `target` over `dt` with the time constant `time` (frame-rate independent, never past it).
function AimCamera.ease(current: number, target: number, dt: number, time: number): number
	if time <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-math.max(0, dt) / time))
end

-- The camera's offset from the pivot (right, up, back; studs) at the aim blend `blend` (0..1) and `forward` studs of
-- the throw's push.
function AimCamera.offset(blend: number, forward: number, config: Config): (number, number, number)
	local look, aim = config.camera, config.camera.aim
	return look.shoulder + aim.shoulder * blend, look.up, look.distance - aim.closer * blend - forward
end

-- The throw's push `since` seconds after the release: studs forward and degrees wider, up and back down over
-- kick.time (a perfect throw stronger). Nothing after that, or with the shake off.
function AimCamera.kick(since: number, perfect: boolean, shake: boolean, config: Config): (number, number)
	local aim = config.camera.aim
	if not shake or since < 0 or since >= aim.kick.time then
		return 0, 0
	end
	local scale = if perfect then aim.perfectKick else 1
	local shape = math.sin(math.pi * since / aim.kick.time)
	return aim.kick.forward * scale * shape, aim.kick.fov * scale * shape
end

return AimCamera
