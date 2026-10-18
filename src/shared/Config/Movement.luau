--!strict
-- Look and feel of moving: optional animation overrides and the procedural effects of MovementController.
-- Nothing here changes speed, jump power, dash distance or any gameplay value.

return {
	-- Animation overrides for Roblox's built-in Animate script, as "rbxassetid://<id>". Empty means Roblox's
	-- default animation stays. The animations must be published by the same account or group that owns the
	-- experience, otherwise Roblox does not play them. Keys are the Animate script's animation sets; within a set,
	-- each named Animation child gets the id.
	animations = {
		idle = { Animation1 = "", Animation2 = "" },
		walk = { WalkAnim = "" },
		run = { RunAnim = "" },
		jump = { JumpAnim = "" },
		fall = { FallAnim = "" },
	},

	-- running lean (all characters, drawn by every client from the replicated velocity)
	leanForward = math.rad(10), -- at full walk speed
	leanTurn = math.rad(9), -- into a turn at full speed
	leanResponse = 10, -- 1/s, how fast the lean follows; higher feels snappier

	-- hit stumble and knockdown pose (procedural until stumble/knockdown/get-up animations exist)
	stumbleAngle = math.rad(28), -- back-tilt of a full hit
	stumbleRecover = 5, -- 1/s
	knockdownAngle = math.rad(78),
	knockdownDrop = 1.6, -- studs the body sinks while down
	knockdownIn = 0.18, -- seconds to fall
	getUpTime = 0.35, -- seconds to stand up

	-- local camera and effects
	dashFovKick = 9, -- degrees added to the field of view for a dash
	dashFovTime = 0.28,
	landMinAirTime = 0.35, -- shorter hops land without dust or shake
	landFullAirTime = 1.1, -- landings after this long get the full effect
	landShake = 0.5, -- degrees
	hitShake = 1.2, -- degrees for a full hit, x1.6 for a knockdown
	shakeTime = 0.25,
	dustPuffs = 5,
}
