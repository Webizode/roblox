local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local AimCamera = require("../src/shared/AimCamera")
local Combat = require("../src/shared/Combat")
local Config = require("../src/shared/Config/Combat")

local aim = Config.camera.aim

describe("Aim camera", function()
	it("moves over the shoulder and closer only while charging", function()
		local blend = AimCamera.targets(false, 1, true, true, Config)
		expect(blend).toBe(0)
		blend = AimCamera.targets(true, 0, false, true, Config)
		expect(blend).toBe(1)
		local nx, ny, nz = AimCamera.offset(0, 0, Config)
		local ax, ay, az = AimCamera.offset(1, 0, Config)
		expect(ax > nx).toBe(true) -- further to the side
		expect(az < nz).toBe(true) -- closer
		expect(az > 1).toBe(true) -- never into the character
		expect(ay).toBe(ny)
	end)

	it(
		"narrows the view with the charge, a little more in the perfect window, never with motion effects off",
		function()
			local _, none = AimCamera.targets(true, 0, false, true, Config)
			local _, full = AimCamera.targets(true, 1, false, true, Config)
			local _, perfect = AimCamera.targets(true, 1, true, true, Config)
			local _, off = AimCamera.targets(true, 1, true, false, Config)
			expect(none).toBe(0)
			expect(full).toBe(aim.fov)
			expect(perfect).toBe(aim.fov + aim.perfectFov)
			expect(off).toBe(0)
			expect(full <= -8 and full >= -12).toBe(true) -- as asked: 8 to 12 degrees
			-- the perfect extra follows the throw's own perfect window
			local held = Config.perfect.rise
			local _, atTouch =
				AimCamera.targets(true, Combat.strength(held, Config), Combat.isPerfect(held, Config), true, Config)
			expect(atTouch).toBe(aim.fov + aim.perfectFov)
		end
	)

	it("eases smoothly without overshooting, whatever the frame rate", function()
		local a = AimCamera.ease(0, 1, 1 / 60, aim.ease)
		expect(a > 0 and a < 1).toBe(true)
		local slow, fast = 0, 0
		slow = AimCamera.ease(slow, 1, 0.1, aim.ease)
		for _ = 1, 6 do
			fast = AimCamera.ease(fast, 1, 0.1 / 6, aim.ease)
		end
		expect(math.abs(slow - fast) < 1e-9).toBe(true)
		expect(AimCamera.ease(0.5, 1, 100, aim.ease)).toBeCloseTo(1, 1e-9)
	end)

	it("pushes forward on the throw and is back after kick.time; stronger when perfect, none without shake", function()
		local mid = aim.kick.time / 2
		local forward, fov = AimCamera.kick(mid, false, true, Config)
		expect(forward).toBeCloseTo(aim.kick.forward, 1e-9)
		expect(fov).toBeCloseTo(aim.kick.fov, 1e-9)
		local perfectForward = AimCamera.kick(mid, true, true, Config)
		expect(perfectForward > forward).toBe(true)
		local after = AimCamera.kick(aim.kick.time, true, true, Config)
		expect(after).toBe(0)
		local shakeOff, shakeOffFov = AimCamera.kick(mid, true, false, Config)
		expect(shakeOff).toBe(0)
		expect(shakeOffFov).toBe(0)
	end)
end)
