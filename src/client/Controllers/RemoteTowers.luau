-- Renders every other player's tower from the TowerFlavors attribute on their character and the tilt the
-- server relays at 10 Hz. Tilt is smoothed so 10 Hz updates still look fluid.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tower"))
local TowerShape = require(Shared:WaitForChild("TowerShape"))

local client = script.Parent.Parent
local TowerVisual = require(client:WaitForChild("TowerVisual"))

local RemoteTowers = {}
local registry

type Remote = {
	visual: any,
	tiltX: number,
	tiltZ: number,
	targetX: number,
	targetZ: number,
	connections: { RBXScriptConnection },
}

local SMOOTHING = 12 -- per second

local localPlayer = Players.LocalPlayer
local towers: { [Player]: Remote } = {}

local function parse(value: any): { string }
	local ids = {}
	if type(value) == "string" then
		for _, id in string.split(value, ",") do
			if id ~= "" then
				table.insert(ids, id)
			end
		end
	end
	return ids
end

local function watchCharacter(remote: Remote, character: Model)
	local function refresh()
		remote.visual:setFlavors(parse(character:GetAttribute("TowerFlavors")))
	end
	table.insert(remote.connections, character:GetAttributeChangedSignal("TowerFlavors"):Connect(refresh))
	refresh()
end

local function track(player: Player)
	if player == localPlayer or towers[player] then
		return
	end
	local remote: Remote = {
		visual = TowerVisual.new("Tower_" .. player.UserId),
		tiltX = 0,
		tiltZ = 0,
		targetX = 0,
		targetZ = 0,
		connections = {},
	}
	towers[player] = remote
	table.insert(
		remote.connections,
		player.CharacterAdded:Connect(function(character)
			remote.visual:setFlavors({})
			watchCharacter(remote, character)
		end)
	)
	if player.Character then
		watchCharacter(remote, player.Character)
	end
end

local function untrack(player: Player)
	local remote = towers[player]
	if not remote then
		return
	end
	towers[player] = nil
	for _, connection in remote.connections do
		connection:Disconnect()
	end
	remote.visual:destroy()
end

local function onRenderStep(dt: number)
	local alpha = 1 - math.exp(-SMOOTHING * dt)
	for player, remote in towers do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			remote.tiltX += (remote.targetX - remote.tiltX) * alpha
			remote.tiltZ += (remote.targetZ - remote.tiltZ) * alpha
			-- standing in the waffle on their back, like the own tower (TowerController.towerBase)
			local seat = registry.Backpacks.seat(character :: Model, TowerVisual.SCOOP_SIZE / 2)
			local base = root.CFrame * CFrame.new(0, Tuning.holdUp, -Tuning.holdForward)
			if seat then
				local _, bottom = TowerShape.offset(1, 1, 0, 0, Tuning)
				base = CFrame.new(seat - Vector3.new(0, bottom, 0))
			end
			remote.visual:update(base, remote.tiltX, remote.tiltZ)
		end
	end
end

function RemoteTowers.Init(reg)
	registry = reg
end

function RemoteTowers.Start()
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	for _, player in Players:GetPlayers() do
		track(player)
	end

	Remotes.TowerTilt.OnClientEvent:Connect(function(player: Player, x: number, z: number)
		local remote = towers[player]
		if remote then
			remote.targetX, remote.targetZ = x, z
		end
	end)

	RunService:BindToRenderStep("WobbleRemoteTowers", registry.TowerController.VISUAL_PRIORITY, onRenderStep)
end

return RemoteTowers
