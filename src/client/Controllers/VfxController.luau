-- Starts the effects (client/Vfx) from what the server announces: nothing here decides anything, it only shows what
-- happened. Every client plays them, so everybody sees everybody's effects.
--   IceBallThrown    a perfect throw: green glitter at the release (its green streak is put on in CombatController,
--                    which draws the ball)
--   IceBallResolved  the hit (splash, sprinkles, flash; a headshot with golden stars), the knockdown (stars over the
--                    head, dust) and the small camera jolt for the local player whose ball hit
-- In Studio the attribute VfxPreview on Workspace plays an effect in front of the local character, for looking at it
-- and for screenshots: "hit", "headshot", "world", "perfect" or "knockdown" (set it again to play it again).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))

local client = script.Parent.Parent
local VfxModule = client:WaitForChild("Vfx")
local Vfx = require(VfxModule)
local Effects = VfxModule:WaitForChild("Effects")
local Hit = require(Effects:WaitForChild("Hit"))
local PerfectThrow = require(Effects:WaitForChild("PerfectThrow"))
local Knockdown = require(Effects:WaitForChild("Knockdown"))

local VfxController = {}

local player = Players.LocalPlayer

local function onThrown(_: number, thrower: Player, origin: Vector3, velocity: Vector3, t0: number, perfect: boolean?)
	if not perfect or typeof(origin) ~= "Vector3" or typeof(velocity) ~= "Vector3" then
		return
	end
	-- the ball is in the hand until t0, the throw animation's release
	local wait = if type(t0) == "number" then math.clamp(t0 - workspace:GetServerTimeNow(), 0, 1) else 0
	task.delay(wait, PerfectThrow.release, origin, velocity, thrower == player)
end

local function onResolved(
	_: number,
	thrower: Player,
	victim: Player?,
	position: Vector3,
	dirX: number,
	dirZ: number,
	_power: number,
	knockdown: boolean,
	shielded: boolean?,
	headshot: boolean?
)
	if typeof(position) ~= "Vector3" then
		return
	end
	local character = victim and victim.Character
	local own = thrower == player or victim == player
	Hit.play({
		position = position,
		dirX = if type(dirX) == "number" then dirX else 0,
		dirZ = if type(dirZ) == "number" then dirZ else 0,
		flavorId = nil, -- the ice ball is vanilla so far; a thrown flavor goes in here
		victim = character,
		headshot = headshot == true,
		shielded = shielded == true,
		own = own,
	})
	if not character or shielded then
		return
	end
	if knockdown then
		Knockdown.play(character, CombatConfig.knockdownTime, victim == player)
	end
	if thrower == player and victim ~= player then
		local jolt = if headshot then Vfx.Config.camera.headshotThrower else Vfx.Config.camera.hitThrower
		Vfx.Camera.punch(jolt.degrees, jolt.time)
	end
end

-- Studio only: plays the effect named by the VfxPreview attribute in front of the local character.
local function preview()
	local kind = workspace:GetAttribute("VfxPreview")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if type(kind) ~= "string" or kind == "" or not character or not root then
		return
	end
	local look = root.CFrame.LookVector
	local spot = root.Position + look * 6 + Vector3.new(0, 1, 0)
	if kind == "hit" or kind == "headshot" then
		Hit.play({
			position = spot,
			dirX = look.X,
			dirZ = look.Z,
			victim = character,
			headshot = kind == "headshot",
			shielded = false,
			own = true,
		})
	elseif kind == "world" then
		Hit.play({ position = spot, dirX = look.X, dirZ = look.Z, headshot = false, shielded = false, own = true })
	elseif kind == "perfect" then
		PerfectThrow.release(spot, look, true)
	elseif kind == "knockdown" then
		Knockdown.play(character, CombatConfig.knockdownTime, true)
	end
	workspace:SetAttribute("VfxPreview", nil)
end

function VfxController.Start()
	Vfx.prewarm()
	Remotes.IceBallThrown.OnClientEvent:Connect(onThrown)
	Remotes.IceBallResolved.OnClientEvent:Connect(onResolved)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VfxPreview"):Connect(preview)
	end
end

return VfxController
