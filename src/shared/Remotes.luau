-- All remotes in one place. The server creates them, clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local DEFINITIONS = {
	-- server -> all: id, flavorId, from, to, apex, t0 (server time the scoop leaves), flight, and with the arm rig the arm
	-- (1-6), scoopAt (server time the scoop shows in its cup) and speed (the arm cycle's play speed); nil for the Nozzle
	ShotFired = "RemoteEvent",
	-- server -> all: id, catcher (Player or nil), landed (true: nobody caught it and it lies on the ground as a free
	-- scoop, LootSpawned came first; false with no catcher: it splashed into the water)
	ShotResolved = "RemoteEvent",
	CatchClaim = "RemoteEvent", -- client -> server: id, claimTime (server time), tiltX, tiltZ
	TowerChanged = "RemoteEvent", -- server -> owner: scoops (bottom to top), reason
	TowerToppled = "RemoteEvent", -- client -> server
	TowerTilt = "UnreliableRemoteEvent", -- client -> server: x, z (10 Hz); server -> other players: player, x, z
	ServeRequest = "RemoteEvent", -- client -> server: steadyBonus
	Served = "RemoteEvent", -- server -> all: player, count, value
	-- client -> server: dirX, dirZ, "power" or nil (request); server -> all: player, dirX, dirZ, kind (granted:
	-- "dash", "quick" or "power")
	Dash = "RemoteEvent",
	SetSprint = "RemoteEvent", -- client -> server: sprinting (boolean)
	SetStance = "RemoteEvent", -- client -> server: holding the steady stance (boolean); the server answers with the SteadyStance attribute
	SetCombatMode = "RemoteEvent", -- client -> server: combat mode on or off (boolean)
	ChargeIceBall = "RemoteEvent", -- client -> server: the throw button went down; starts the server's charge clock
	-- client -> server: aimX, aimY, aimZ (where the throw aims), strength (0..1, Combat.strength), perfect (boolean)
	ThrowIceBall = "RemoteEvent",
	IceBallThrown = "RemoteEvent", -- server -> all: id, thrower, origin, velocity, t0 (server time), perfect
	-- server -> all: id, thrower, victim (nil on a miss), position, dirX, dirZ, power, knockdown, shielded (the victim
	-- stood in their cart's safe zone: no harm)
	IceBallResolved = "RemoteEvent",
	-- server -> the thrower: kind ("knockdown": their hit knocked the victim down; "toppled": the victim's tower fell
	-- soon after their hit), victim, scoops the victim lost
	HitFeedback = "RemoteEvent",
	LootSpawned = "RemoteEvent", -- server -> all (a spill) or one (on join): list of free scoops, see LootService
	LootUpdated = "RemoteEvent", -- server -> all: ids, ownerUntil (the owner's head start moved, e.g. a knockdown)
	LootRemoved = "RemoteEvent", -- server -> all: id, catcher (Player or nil), reason ("caught", "puff", "water", "room")
	LootClaim = "RemoteEvent", -- client -> server: id (the local player walked over a free scoop)
	LootRejected = "RemoteEvent", -- server -> claimant: id (the scoop stays on the ground)
	SaveSettings = "RemoteEvent", -- client -> server: the settings table (DataService checks and saves it)
	TeleportRequest = "RemoteEvent", -- client -> server: "plot" or "arena" (ArenaService checks it)
}

local remotes = {}

if RunService:IsServer() then
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for name, className in DEFINITIONS do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
		remotes[name] = remote
	end
else
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	for name in DEFINITIONS do
		remotes[name] = folder:WaitForChild(name)
	end
end

return remotes
