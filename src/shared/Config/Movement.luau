--!strict
-- Look and feel of moving: optional animation overrides and the procedural effects of MovementController.
-- Nothing here changes speed, jump power, dash distance or any gameplay value.

return {
	-- Animation overrides for Roblox's built-in Animate script, as "rbxassetid://<id>". Empty means Roblox's
	-- default animation stays. The animations must be published by the same account or group that owns the
	-- experience (or shared with it), otherwise Roblox does not play them; MovementController checks that each one
	-- loads and keeps Roblox's default for any that does not. Keys are the Animate script's animation sets; within a
	-- set, each named Animation child gets the id. R15's Animate plays the run set at normal walking speed already
	-- (the walk set only when creeping), so a walk animation goes into both. The animations must be made for R15: one
	-- for R6 loads but moves no R15 joint, and the character glides with stiff legs (the load check cannot see that).
	-- Empty for now, so Roblox's own idle, walk and run play outside combat mode: "Idle 1" (89576729034814) and
	-- "Walk4" (95197756431784) moved no R15 joint at all, and the sprint 10862419793 does not load (other creator).
	animations = {
		idle = { Animation1 = "", Animation2 = "" },
		walk = { WalkAnim = "" },
		run = { RunAnim = "" },
		jump = { JumpAnim = "" },
		fall = { FallAnim = "" },
	},

	-- combat mode only (the CombatMode attribute): animations over Roblox's Animate (Movement priority, below the
	-- throw), ended as soon as combat mode ends, the character is in the air or it dies. Empty or not loading: the
	-- normal animation stays for that state (the combat walk stands in for the sprint).
	combat = {
		walk = "rbxassetid://127299725054429", -- "movement"
		idle = "rbxassetid://111304519579927", -- "Idle Animation"; its right arm stays under the procedural stance
		sprint = "", -- your combat sprint; until then the combat walk, played faster
		walkSpeedAt = 16, -- studs/s at which the walk plays at its own speed; faster walking plays it faster
		sprintPlaySpeed = 1.15, -- extra speed of the walk standing in for the sprint
		fade = 0.12, -- seconds between walk, sprint and idle
		stopFade = 0.1, -- seconds from moving to standing: a quick, clean stop
		moveThreshold = 1.5, -- studs/s on the ground below which the character counts as standing
		-- moving sideways turns the hips (and the legs with them) up to hipTurn towards the way it goes while the
		-- upper body keeps facing the aim; backwards plays the walk in reverse
		hipTurn = math.rad(50),
		hipResponse = 14, -- 1/s, how fast the hips follow a change of direction
		leanBoost = 1.3, -- forward lean of walking and sprinting is this much stronger in combat mode
	},

	-- running lean (all characters, drawn by every client from the replicated velocity)
	leanForward = math.rad(10), -- at full walk speed
	leanTurn = math.rad(9), -- into a turn at full speed
	leanResponse = 10, -- 1/s, how fast the lean follows; higher feels snappier
	sprintLean = 1.4, -- lean grows with speed up to this share of leanForward (sprinting is 1.3x walking)
	sprintFov = 6, -- degrees wider while the local player sprints
	sprintFovTime = 0.3,

	-- hit stumble (procedural, under the hit animation) and the procedural knockdown pose, which only stands in when the
	-- knockdown animations of Config/Combat reactionAnimations do not load
	stumbleAngle = math.rad(28), -- back-tilt of a full hit
	stumbleRecover = 5, -- 1/s
	knockdownAngle = math.rad(78),
	knockdownDrop = 1.6, -- studs the body sinks while down
	knockdownIn = 0.18, -- seconds to fall
	getUpTime = 0.35, -- seconds to stand up

	-- local camera and effects
	dashFovKick = 9, -- degrees added to the field of view for a dash
	dashFovTime = 0.28,

	-- dash effects taken over from the DashSystem model, drawn by every client for every dashing character:
	-- fading white afterimages of the body and short streaks behind hands and feet. If the model's assets were
	-- imported in Studio as ReplicatedStorage.DashAssets (the part DashVfx, the sounds Sounds.FrontDash and
	-- Sounds.BackDash), their particles and sounds play too; without them the game's own dash sound plays.
	dashAfterimages = 3, -- over the whole dash
	dashAfterimageFade = 0.25, -- seconds
	dashAfterimageTransparency = 0.45,
	dashLimbTrailLifetime = 0.16,
	-- the body leans into the dash, whichever way it goes (forward, back, to a side or diagonally): a procedural pose
	-- on the root joint, only for directions without a dash animation (dashAnimations below)
	dashLean = math.rad(16),
	dashLeanIn = 0.05, -- seconds to lean in
	dashLeanOut = 0.22, -- seconds to straighten up after the burst
	-- a thin bright streak on the ground along the dash and a puff of dust where it starts and ends
	dashStreak = { width = 0.9, transparency = 0.45, fade = 0.4 },
	-- dash animations by direction (Dash.kind; forward alternates between two), "rbxassetid://<id>" of animations
	-- published by the experience owner for the game's rig. Empty plays none. The model's own animations are R6
	-- and published by its author, so they cannot be used as they are.
	dashAnimations = {
		forward1 = "rbxassetid://131205595010379",
		forward2 = "rbxassetid://131205595010379", -- only one forward animation so far
		left = "rbxassetid://97220317798033",
		right = "rbxassetid://126986340101454",
		back = "rbxassetid://126984073461087",
	},
	-- the dash animations play sped up so they end this long after the dash itself (seconds), whatever their own
	-- length: the move fits the burst, the rest straightens the body up (Dash.animationSpeed)
	dashAnimationRecovery = 0.1,
	landMinAirTime = 0.35, -- shorter hops land without dust or shake
	landFullAirTime = 1.1, -- landings after this long get the full effect
	landShake = 0.5, -- degrees
	hitShake = 1.2, -- degrees for a full hit, x1.6 for a knockdown
	shakeTime = 0.25,
	dustPuffs = 5,
}
