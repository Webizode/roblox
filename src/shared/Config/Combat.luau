--!strict
-- Ice-ball throw: the only normal attack. Tuning for ammo, flight, hits and the knockdown threshold.

return {
	-- combat mode (R): only in it can a player charge and throw. Switching on is rate-limited, off always works.
	combatModeInterval = 0.2, -- seconds

	-- ammo: three throws per load; once all three are gone the load refills after reloadTime. The server owns it.
	ammo = 3,
	reloadTime = 4, -- seconds
	throwInterval = 0.4, -- seconds between two throws, so a macro cannot fire a whole load at once

	-- throw strength (Combat.strength): a tap throws at once at strength 0; holding raises it to 1 by perfect.rise
	-- seconds (speed from minSpeed to maxSpeed, hit power factor from powerAtMinCharge to 1) and it stays 1. While held,
	-- the crosshair's inner circle grows from the middle to the outer circle in perfect.rise and shrinks back in the
	-- same time, again and again (Combat.pulse). Letting go when it reaches the outer circle, within perfect.window
	-- around that moment, is a perfect throw: full strength at perfect.speed, faster but no harder. The server times
	-- the hold itself and accepts the client's strength and perfect claim only as far as its own timing allows.
	perfect = {
		rise = 0.5, -- seconds from the middle to the outer circle
		window = 0.12, -- seconds round each moment it touches the outer circle: doable on a phone and a pad
		speed = 110, -- studs/s at release
	},
	-- seconds of network jitter between the server's measured hold and the client's
	chargeTolerance = 0.08,
	minSpeed = 55, -- studs/s at release at strength 0 (a tap)
	maxSpeed = 90, -- and at 1
	powerAtMinCharge = 0.6, -- hit power factor of a tap; full strength (and a perfect throw) hits with factor 1

	-- The crosshair (AimHud, AimRules): a thin circle fixed in the middle of the screen, where every throw aims. Its
	-- radius in pixels (times the crosshair size setting) grows while moving, sprinting, after a dash and right after a
	-- throw, and shrinks a little while a throw is held. Purely a display: throws never scatter. While held, a small
	-- inner circle pulses inside it (perfect); both turn perfectColor while letting go would be a perfect throw.
	crosshair = {
		radius = 14,
		walk = 4, -- added while moving
		sprint = 9, -- added while sprinting
		dash = 14, -- added right after a dash, gone after dashTime
		dashTime = 0.5,
		throw = 10, -- added right after a throw, gone after throwTime
		throwTime = 0.35,
		holdShrink = 0.25, -- share it shrinks by at full strength while holding
		response = 14, -- 1/s: how fast it follows (eases towards its size)
		thickness = 1.5, -- pixels
		perfectColor = "#3DDC84", -- green
	},
	-- Aim help in the combat camera (CombatCamera, AimRules), its strength by the input in use (Settings.inputKind,
	-- not the platform). A rival within maxAngle degrees of the crosshair, at most maxRange studs away, in plain sight
	-- (no wall between) and not in their cart's safe zone slows the turning down there (friction: share of the turn
	-- taken off) and draws the camera gently towards them (pull: per second, the share of the way closed). Both fade
	-- to nothing towards maxAngle, so nothing snaps, and nobody behind or beside the crosshair is ever picked. Purely
	-- the camera: the server checks hits as always.
	aimAssist = {
		maxAngle = 8, -- degrees from the crosshair
		maxRange = 120, -- studs
		aimHeight = 1, -- studs above the HumanoidRootPart the camera is drawn to (the chest)
		devices = {
			keyboard = { friction = 0.15, pull = 0.4 }, -- mouse: hardly felt
			gamepad = { friction = 0.35, pull = 1.6 },
			touch = { friction = 0.5, pull = 3 },
		},
	},
	-- what the thrower sees of a hit (HitFeedback): a red X on the crosshair, the scoops the victim lost rising over
	-- them, a line in the feed at the bottom. A topple counts as the thrower's when their hit came at most
	-- creditSeconds before it.
	feedback = {
		markTime = 0.3, -- seconds the X shows
		creditSeconds = 4,
		numberTime = 1.2, -- seconds the number rises and fades
		numberRise = 3, -- studs it rises
		feedTime = 2.5, -- seconds a feed line stays
		feedLines = 3, -- at most this many at once, the newest at the bottom
	},

	-- aiming: the ball leaves the right hand and flies on an arc through the point under the crosshair
	aimDistance = 400, -- studs the client looks for that point along the crosshair ray
	handReach = 4, -- studs; a hand farther from the HumanoidRootPart is not trusted as the release point

	-- the over-the-shoulder camera of combat mode (CombatCamera); the character stands left of the crosshair
	camera = {
		distance = 10.5, -- studs behind the pivot
		shoulder = 2.2, -- studs to the right
		up = 0.6, -- studs above
		pivotUp = 1.6, -- pivot above the HumanoidRootPart, about the neck
		pitchMin = math.rad(-65),
		pitchMax = math.rad(55),
		mouseSpeed = math.rad(0.4), -- per pixel of mouse movement at Roblox's mouse sensitivity 1
		gamepadSpeed = math.rad(220), -- per second with the right stick fully out
		touchSpeed = math.rad(0.35), -- per pixel a finger drags over the screen
		-- while a throw is charged (the wind-up and the held aim) the camera pulls back this much further and comes back
		-- after the release or a dropped charge; it eases there over about zoomTime
		aimZoom = 3, -- studs
		zoomTime = 0.2, -- seconds
		-- the camera is kept this far out of solid parts (a swept sphere), so roofs, palms and decorations do not
		-- slice through the near plane
		wallRadius = 0.6, -- studs
	},

	-- the ball in the hand (HeldBalls), drawn for every player in combat mode; purely visual
	held = {
		popIn = 0.2, -- seconds for the next ball to appear after a throw or a refill
		popOut = 0.08, -- seconds for the last ball to vanish from the hand
		frostMax = 0.85, -- share of the ball size a refilling frost ball reaches; it grows from zero over the reload
		frostTransparency = 0.55,
		drawDistance = 200, -- studs from the camera
		hover = 0.25, -- studs of air between the top of the palm and the bottom of the ball floating above it
		side = -0.15, -- studs the ball sits to the character's right (+) or left (-) of the palm's centre
		spinSpeed = 25, -- degrees per second the floating ball slowly turns, on top of its idle sway
		-- after a throw the next ball pops in only once the arm has swung through, so the hand is empty meanwhile
		reappearDelay = 0.5, -- seconds
	},

	-- ice look of the ball, purely visual and client-only (BallVisual, HeldBalls, CombatController). Particles use
	-- Roblox's built-in sparkle; colours come from the palette (vanilla, skyTop, sea). Nothing here moves a ball.
	iceVfx = {
		-- in the hand: a few slow sparkles and a soft glow
		frost = { rate = 10, lifetime = 0.8, size = 0.22, brightness = 1.2, range = 4 },
		-- in flight: a light streak from white to ice blue, twinkles falling off it, a brighter glow
		trail = { lifetime = 0.3, lightEmission = 0.7 },
		twinkle = { rate = 35, lifetime = 0.45, size = 0.2 },
		glow = { brightness = 2, range = 7 },
		fadeOut = 0.35, -- seconds the streak and twinkles linger where the ball ended
		-- the hit: a quick pinwheel of ice shards around the impact
		shards = 6,
		shardTime = 0.35,
	},

	-- the vanilla ball model (BallVisual) drawn for the held and the flying ball, scaled to ballRadius; purely visual.
	-- Its three motions come from the Blender actions of WSB_ThrowBall (BallMotion). Lengths in ball diameters,
	-- angles in degrees.
	ballModel = {
		template = "WSB_ThrowBall_Vanilla", -- model in ReplicatedStorage: pivot at its centre, face towards -Z
		-- floating in the hand: a slow bob with a little sway, one loop per period
		idle = { period = 2, bob = 0.038, pitch = 3, yaw = 6, roll = 2.5 },
		-- thrown: a quick hop up and back, then spinning flat around its own up axis
		flight = { bounce = 0.115, bounceRise = 0.1, bounceEnd = 0.27, turnsPerSecond = 2 },
		-- the next ball popping into the hand turns once
		nextThrow = { duration = 0.33 },
	},

	-- the throw animation. The ball leaves the hand releaseDelay after the button-up: the server checks the throw when
	-- the button-up arrives and starts the ball that much later, and the throw animation releases at the same moment
	-- (its "Release" marker). With animation ids (published by the experience owner for the R15 rig) the local player
	-- plays them and they replicate; while they are empty a procedural pose of the right arm and the waist stands in,
	-- drawn by every client for every player. Angles in degrees: shoulder swing (forward +, 180 is straight up), the
	-- arm out to the side (+), elbow bend, wrist bend (forward +), wrist twist (turns the hand about the forearm; it
	-- levels the palm against `out`), waist turn (left +). The stance presents the ball: the hand flat with its palm up, the ball floating above it (HeldBalls);
	-- the wind-up keeps that hand and only coils the waist. R6 swings its one arm to the middle of upper and lower arm
	-- (ThrowPose.singleArm). scripts/throw-animation.luau turns these poses into a KeyframeSequence file for the
	-- Animation Editor.
	releaseDelay = 0.08, -- seconds
	throwAnimation = {
		stance = "", -- "rbxassetid://<id>", looped combat stance
		charge = "", -- wind-up, with a "Held" marker at the end where it stops and holds
		-- throw, with a "Release" marker at releaseDelay. Set alone (stance and charge empty) it is one animation with
		-- the wind-up in it: it starts with the charge, holds releaseDelay before throwRelease until the button-up and
		-- then swings through, so the ball leaves the hand when the server starts it; the procedural pose stands in
		-- for the stance and steps aside while it plays.
		throw = "rbxassetid://109391766917607", -- "WSB_ThrowFixed", its "Release" marker is at 0.68 s
		throwRelease = 0.68, -- seconds into the throw animation where the ball leaves the hand (fastest forward swing)
		windupTime = 0.15, -- seconds from the stance to the full wind-up
		followTime = 0.14, -- after the release: the arm swings through
		recoverTime = 0.22, -- and back to the stance
		blendTime = 0.15, -- in and out of combat mode
		poses = {
			-- upper arm hanging a little forward, forearm raised a little above level, hand flat on top of it
			stance = { shoulder = 20, out = 12, elbow = 90, wrist = 70, twist = 37, waist = 0 },
			windup = { shoulder = 20, out = 12, elbow = 90, wrist = 70, twist = 37, waist = -12 },
			-- a push forward and up out of the presenting hand
			release = { shoulder = 100, out = 5, elbow = 15, wrist = 10, twist = 0, waist = 15 },
			follow = { shoulder = 60, out = 0, elbow = 25, wrist = 15, twist = 0, waist = 22 },
		},
	},

	-- flight, simulated by the server; clients draw the same curve
	lift = 0.12, -- a target out of reach gets a straight aim plus this much upward, so it arcs a little
	gravity = 60, -- studs/s^2
	maxFlight = 1.2, -- seconds
	ballRadius = 0.6,

	-- the target: a vertical capsule around the HumanoidRootPart
	hitRadius = 2.2,
	hitHalfHeight = 2.6,

	-- hit power: a centred hit at full charge is 1, a grazing, slowed-down or uncharged one less
	minPower = 0.5,

	-- player reaction
	knockbackSpeed = 26, -- studs/s away from the thrower, times the hit power (so a charged throw pushes harder)
	knockbackUp = 9, -- studs/s
	knockbackTime = 0.15, -- seconds

	-- tower reaction (TowerModel.hitKick): pushed along the ball's flight, corrections weaker for a moment
	-- Hits shake the tower: their powers add up and drain by towerShakeDecay per second, and each hit kicks harder
	-- (x 1 + towerShakeGain * shake) and stays unsteady longer (x 1 + shake) the more shaken the tower is. While
	-- unsteady the stabiliser (and the stance) only work at unsteadyFactor. In simulation, standing with only the
	-- stabiliser: one full hit never topples up to 9 scoops; on 5 scoops two full or three medium hits in a row topple
	-- it, the same three hits 1.5 s apart do not; three quick full hits topple even the smallest tower, while a single
	-- scoop survives two. A hit on 12 (leaning) or 16 scoops topples them unless the stance is taken.
	towerKickBase = 0.75, -- rad/s at power 1
	towerKickPerScoop = 0.03,
	towerKickMax = 1.0,
	towerShakeGain = 1.0,
	towerShakeDecay = 0.6, -- per second, like the stagger
	unsteadySeconds = 1.0, -- times 1 + shake
	unsteadyFactor = 0.35,
	-- The steady stance is no shield: a hit taken in it reaches the tower at stanceTowerScale of its power and drains
	-- stanceDrain of the energy bar per full hit (times the power); an emptied bar ends the stance.
	stanceTowerScale = 0.5,
	stanceDrain = 0.25,

	-- knockdown: every hit adds its power to a stagger value that drains by staggerDecay per second. A single hit
	-- (power <= 1) never reaches knockdownAt; two full-strength hits on the middle do, and so do three taps on the middle
	-- (0.6 each) of one load, even 0.6 s apart. Two taps, or three grazing ones, do not. (Since 29.10.2026; it was 0.6,
	-- which with taps never added up.)
	staggerDecay = 0.2,
	knockdownAt = 1.5,
	knockdownTime = 1.5, -- seconds on the ground; no further hits land meanwhile
	knockdownBoost = 1.5, -- knockback and tower kick multiplier for the hit that knocks down
}
