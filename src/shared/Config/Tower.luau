--!strict
-- Tuning for the wobble tower. Everything the kill test in week 1 might want to change lives here.

return {
	stepRate = 60, -- fixed simulation steps per second

	-- shape
	scoopSpacing = 1.5, -- studs between scoop centres
	coneHeight = 1.6,
	-- The visible tower stands in the waffle backpack: its bottom scoop rests in the opening, computed every frame from
	-- the same frame the waffle is drawn with (Backpacks.opening, TowerShape.restingBase). Only while no waffle shows
	-- (knocked down) does it stand at this fixed offset from the HumanoidRootPart; negative holdForward is behind.
	holdUp = -0.1,
	holdForward = -1.75,
	-- Where the catch column stands, for the client's contact check and the server's catch check alike: straight
	-- above the character, so a scoop is caught whichever way the player faces. On the back it would only catch with
	-- the back to the machine, because scoops come in at an angle and land in front of a tower behind the player
	-- (tests/Catch.spec). A caught scoop then flies onto the visible tower.
	catchUp = -0.1,
	catchForward = 0,
	showCone = false, -- the tower's own cone part; off while the backpack waffle carries the tower
	ownTowerFade = 0.6, -- how see-through an own scoop gets while it covers the middle of the screen

	-- tipping
	tipAngle = 0.55, -- radians at the top before the tower is clamped
	groanFraction = 0.8, -- above this share of tipAngle the tower groans
	groanDuration = 0.5, -- seconds of groaning before it topples

	-- dynamics: tilt'' = gravity*sin(tilt) - stiffness*tilt - damping*tilt' - accelGain*accel + padAuthority*pad + drift
	gravityGain = 1.0, -- per centre-of-mass index, so taller towers get more unstable
	baseStiffness = 5.5, -- about where ten classic scoops become self-unstable
	baseDamping = 1.8,
	minDamping = 0.4,
	-- padAuthority = variant.padGain * (padBase + padPerInstability * max(0, gravity - stiffness)), in rad/s^2.
	-- padBase keeps a held key from pushing a short tower past the groan line (steady lean = padBase / restoring
	-- stiffness, e.g. 1.0 / 4.5 = 0.22 rad for one scoop). padPerInstability gives tall towers the leverage they
	-- need: about 9.5 at 20 scoops, as strong as the old fixed pad (9). padMax caps it there so very tall towers
	-- keep a skill ceiling: in simulation no 0.2 s controller holds 40 scoops on a starter cone.
	padBase = 1.0,
	padPerInstability = 1.7,
	padMax = 10,
	-- Share of that authority for input that does not reduce the current lean (pushing an upright tower, pushing
	-- with the lean, sideways). The stabiliser and the stance act through this, so they cannot push a tower over.
	padWrongWay = 0.35,
	driftStartScoops = 10, -- below this the tower never wanders on its own
	driftPerScoop = 0.12, -- rad/s^2 of slow wandering per scoop above the start
	jerkInterval = 0.9, -- seconds between cursed pickle kicks
	jerkStrength = 0.35, -- rad/s per unit of flavor jerk
	landingKick = 0.12, -- rad/s nudge every time a scoop lands

	steady = {
		minScoops = 10, -- steady time only counts once the tower drifts by itself
		fraction = 0.25, -- tilt below this share of tipAngle counts as steady
		ratePerSecond = 0.05,
		max = 0.25,
	},

	accelSmoothing = 0.25, -- seconds, MoveDirection lerp that feeds the tower instead of raw Humanoid velocity

	-- Physics profile. padGain multiplies the pad authority above (the stabiliser and the stance act through it),
	-- driftScale the random wandering.
	variant = { accelGain = 0.02, padGain = 1, driftScale = 1 },

	-- Automatic stabiliser (TowerModel.assist), a PD controller on the lean that is deliberately imperfect: it sees
	-- the lean smoothed over `lag` seconds, uses at most `strength` of the pad, gives up between fadeFrom and fadeTo
	-- of the tip angle, and gets weaker from fullUntil scoops to `floor` of its strength at zeroAt scoops.
	-- In simulation (no player input at all): standing still, towers of up to 20 scoops stay up for 60 s; walking
	-- with a full-speed 90 degree turn every 1.5 s peaks at about 30 % of the tip angle up to 9 scoops, 47 % at 11,
	-- risks a topple from 13 and needs the steady stance from 15.
	assist = {
		kp = 2.0,
		kd = 0.6,
		lag = 0.35,
		strength = 0.35,
		fadeFrom = 0.3,
		fadeTo = 0.6,
		fullUntil = 2,
		zeroAt = 20,
		floor = 0.55,
	},

	-- Steady stance (hold F on PC, hold the Steady button on touch): while held, the stabiliser works on the real
	-- lean without its delay, with its own gains and up to `authority` rad/s^2 of pad, so even tall towers hardly
	-- fall; a hard hit can still knock a very tall one over. It costs: walking at walkMultiplier of the normal speed,
	-- no sprint, dash, charge or throw. It runs on an energy bar (Stance): a full bar lasts holdSeconds, refills in
	-- refillSeconds once released (after refillDelay), and a new stance needs at least minStart of it. The server
	-- keeps its own bar and enforces all of it.
	stance = {
		authority = 10,
		kp = 2.5,
		kd = 1.0,
		holdSeconds = 4,
		refillSeconds = 6,
		refillDelay = 0.5,
		minStart = 0.25,
		walkMultiplier = 0.6,
	},
	warnFraction = 0.6, -- from this share of the tip angle the HUD warns (the stabiliser has given up by then)

	tiltSendRate = 10, -- Hz, tilt replication for other players

	-- Dash (Q on PC, a dash button on touch): a short burst in the move direction that ends with a hard stop back to
	-- walking (or sprinting) speed, so nothing slides on after it. Distance = speed x duration. The server checks the
	-- cooldown. The cone is yanked forward, so the tower gets a tilt-rate kick against the dash direction that grows
	-- with its height: a tower leaning into the dash is pushed upright, one already leaning back can go over.
	dash = {
		cooldown = 4, -- seconds
		speed = 80, -- studs/s during the burst
		duration = 0.125, -- seconds; 10 studs, the same distance as before
		acceleration = 6000, -- studs/s^2 the burst may push with, so it is at full speed within a frame or two
		kickBase = 0.2, -- rad/s
		kickPerScoop = 0.03, -- rad/s per scoop
		kickMax = 0.9, -- rad/s
		unsteadySeconds = 0.6, -- afterwards pad and walking corrections are weaker for this long
		unsteadyFactor = 0.3, -- share of the normal correction strength during that window
	},
}
