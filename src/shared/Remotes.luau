-- All remotes in one place. The server creates them, clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local DEFINITIONS = {
	ShotFired = "RemoteEvent", -- server -> all: id, flavorId, from, to, apex, t0, flight
	ShotResolved = "RemoteEvent", -- server -> all: id, catcher (Player or nil when it splats)
	CatchClaim = "RemoteEvent", -- client -> server: id, claimTime (server time), tiltX, tiltZ
	TowerChanged = "RemoteEvent", -- server -> owner: scoops (bottom to top), reason
	TowerToppled = "RemoteEvent", -- client -> server
	TowerTilt = "UnreliableRemoteEvent", -- client -> server: x, z (10 Hz); server -> other players: player, x, z
	ServeRequest = "RemoteEvent", -- client -> server: steadyBonus
	Served = "RemoteEvent", -- server -> all: player, count, value
	Dash = "RemoteEvent", -- client -> server: dirX, dirZ (request); server -> all: player, dirX, dirZ (granted)
	SetSprint = "RemoteEvent", -- client -> server: sprinting (boolean)
	Rescue = "RemoteEvent", -- client -> server: request; server -> all: player (granted)
	ThrowIceBall = "RemoteEvent", -- client -> server: aimX, aimY, aimZ (camera look vector)
	IceBallThrown = "RemoteEvent", -- server -> all: id, thrower, origin, velocity, t0 (server time)
	IceBallResolved = "RemoteEvent", -- server -> all: id, thrower, victim (nil on a miss), position, dirX, dirZ, power, knockdown
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
