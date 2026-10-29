--!strict
-- Tuning for the wobble tower. Everything the kill test in week 1 might want to change lives here.

return {
	stepRate = 60, -- fixed simulation steps per second

	-- shape
	scoopSpacing = 1.5, -- studs between scoop centres
	coneHeight = 1.6,
	-- The visible tower stands in the waffle backpack: its bottom scoop rests in the opening, computed every frame from
	-- the same frame the waffle is drawn with (Backpacks.seat, TowerShape.seatInCone). Only while no waffle shows
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
	-- The danger comes from players, not from the physics alone (docs/design-regeln.md): the drift is only a faint
	-- wander on very tall towers, so the stabiliser holds a standing tower of 40 and more (simulation below).
	driftStartScoops = 28, -- below this the tower never wanders on its own
	driftPerScoop = 0.015, -- rad/s^2 of slow wandering per scoop above the start
	jerkInterval = 0.9, -- seconds between cursed pickle kicks
	jerkStrength = 0.35, -- rad/s per unit of flavor jerk
	landingKick = 0.12, -- rad/s nudge every time a scoop lands

	steady = {
		minScoops = 10, -- steady time only counts on towers of at least this many scoops
		fraction = 0.25, -- tilt below this share of tipAngle counts as steady
		ratePerSecond = 0.05,
		max = 0.25,
	},

	accelSmoothing = 0.25, -- seconds, MoveDirection lerp that feeds the tower instead of raw Humanoid velocity
	-- share of the acceleration that only turns the heading the tower feels (TowerModel.baseVelocityStep): starting,
	-- stopping and dashes count in full, curves and camera sweeps while walking (in combat mode the character walks
	-- the way the camera looks) half. Turning on the spot moves nothing and never wobbles the tower.
	turnFactor = 0.5,

	-- Physics profile. padGain multiplies the pad authority above (the stabiliser and the stance act through it),
	-- driftScale the random wandering. accelPerInstability makes walking tip unstable towers harder, so moving with
	-- a tall tower is what makes it dangerous, not standing with it.
	variant = { accelGain = 0.02, accelPerInstability = 0.2, padGain = 1, driftScale = 1 },

	-- Automatic stabiliser (TowerModel.assist), a PD controller on the lean that is deliberately imperfect: it sees
	-- the lean smoothed over `lag` seconds, uses at most `strength` of the pad, gives up between fadeFrom and fadeTo
	-- of the tip angle, and gets weaker from fullUntil scoops to `floor` of its strength at zeroAt scoops.
	-- In simulation (no player input at all, 12 seeds): standing still, towers of up to 46 scoops stay up for 300 s
	-- (47 on cone level 4, 48 on level 5: the 55 and 65 of those cones fall within 2 s, docs/ideen.md);
	-- the figures for turns below are from before turnFactor 0.5, with it hard 90 degree turns hold about 6 more;
	-- walking straight ahead (a stop every 3 s, 30 degree changes of heading) holds 25 for 60 s and up to 37 with
	-- the occasional steady stance. Sprinting holds 21, hard 90 degree turns every 1.5 s 24 (sprinting 21); at 25
	-- scoops a sprint topples after about 9 s, hard turns after 11 s, sprinted turns after 3 s. Dashes topple from
	-- 16 scoops, a single full ice-ball hit from 10.
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
	-- fall; a hard hit can still knock a very tall one over. It costs: walking at walkMultiplier of the normal speed
	-- and no sprint. Charging a throw is allowed; the throw itself and a dash end the stance at once, and it cannot
	-- start again for `lockout` seconds (F has to be pressed again). Ice-ball hits taken in it drain the bar
	-- (Config/Combat stanceDrain). It runs on an energy bar (Stance): a full bar lasts holdSeconds, refills in
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
		lockout = 1.0, -- seconds after a throw or a dash ended the stance
		lockRecent = 0.25, -- a stance released this shortly before the throw or dash is locked too
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
		-- In combat mode Q is the quick dash (a harder push of the same dash, same cooldown) and E the power dash: a
		-- long boost the way the character walks (diagonals too; ahead when standing), with its own cooldown. Neither
		-- exists outside combat mode, and no
		-- dash starts while another one still runs. Same burst as above (wall stop, speed back to walking at the end).
		quick = { speed = 100, duration = 0.12 }, -- 12 studs
		power = {
			speed = 125,
			duration = 0.2, -- 25 studs
			cooldown = 6, -- seconds, its own
			kickScale = 1.4, -- the tower is yanked this much harder than by a dash
		},
	},
}
