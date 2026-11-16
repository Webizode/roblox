-- Starts the effects (client/Vfx) from what the server announces: nothing here decides anything, it only shows what
-- happened. Every client plays them, so everybody sees everybody's effects.
--   IceBallThrown    a perfect throw: green glitter at the release (its green streak is put on in CombatController,
--                    which draws the ball)
--   LootSpawned      a tower toppled: the puff where it stood (its scoops fly apart in LootRenderer)
--   IceBallResolved  the hit (splash, sprinkles, flash; a headshot with golden stars), the knockdown (stars over the
--                    head, dust) and the small camera jolt for the local player whose ball hit
--   Served           the own serve only: the coin fountain with confetti, the coins fly to the coin counter
--   Teleported       the puff at the start and at the target
-- In Studio the attribute VfxPreview on Workspace plays an effect in front of the local character, for looking at it
-- and for screenshots: "hit", "headshot", "world", "perfect", "knockdown", "topple", "saved", "savedsmall",
-- "catch", "pickup", "serve", "swirl", "circle", "landed", "teleport", "dash", "blink" or "lootpuff" (set it again
-- to play it again).
-- A catch, a pickup and the Big Swirl's shots (steam and sparks, the landing circle's ring, the puff where an
-- uncaught one comes down) are started by the renderers that know where the scoop is (ShotRenderer, LootRenderer),
-- like a lying scoop's blinking and puff; "SAVED!" by the tower simulation (TowerController), the ball's trail by
-- CombatController, a dash's dust and speed lines by MovementController.

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
local Topple = require(Effects:WaitForChild("Topple"))
local Saved = require(Effects:WaitForChild("Saved"))
local Catch = require(Effects:WaitForChild("Catch"))
local Pickup = require(Effects:WaitForChild("Pickup"))
local Serve = require(Effects:WaitForChild("Serve"))
local SwirlShot = require(Effects:WaitForChild("SwirlShot"))
local Teleport = require(Effects:WaitForChild("Teleport"))
local Dash = require(Effects:WaitForChild("Dash"))
local LootFade = require(Effects:WaitForChild("LootFade"))

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

-- Free scoops appeared. A spill is a toppled tower: scoops that did not come down from the Big Swirl (`landed`),
-- all from one owner and one spot, just now (a late joiner gets the lying scoops without the puff).
local function onLootSpawned(list: any)
	if type(list) ~= "table" then
		return
	end
	local now = workspace:GetServerTimeNow()
	local spills: { [number]: { foot: Vector3, flavorId: string, count: number } } = {}
	for _, wire in list do
		local fresh = type(wire) == "table"
			and not wire.landed
			and type(wire.t0) == "number"
			and now - wire.t0 < Vfx.Config.topple.fresh
		if fresh and typeof(wire.base) == "Vector3" and type(wire.owner) == "number" then
			local spill = spills[wire.owner]
			if spill then
				spill.count += 1
			else
				spills[wire.owner] = { foot = wire.base, flavorId = wire.flavorId, count = 1 }
			end
		end
	end
	for owner, spill in spills do
		Topple.play(spill.foot, spill.flavorId, spill.count, owner == player.UserId)
	end
end

-- The local player served `count` scoops: the coin fountain at them and the coins to the counter. Only for the own
-- serve since the kill test of 13.11.2026; another player's serve comes without a count (PlotPins glints for it).
local function onServed(who: Player, count: number?)
	local character = who == player and player.Character
	if character and type(count) == "number" and count > 0 then
		Serve.play(character, count, true)
	end
end

-- Somebody teleported: the puff at both ends.
local function onTeleported(who: Player, from: Vector3, to: Vector3)
	if typeof(from) == "Vector3" and typeof(to) == "Vector3" then
		Teleport.play(from, to, who == player)
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
	elseif kind == "topple" then
		Topple.play(spot - Vector3.new(0, 3.5, 0), "strawberry", 12, true)
	elseif kind == "saved" or kind == "savedsmall" then
		Saved.play(character, kind == "saved")
	elseif kind == "catch" then
		Catch.play(spot + Vector3.new(0, 3, 0), spot - Vector3.new(0, 3.8, 0), "mint", true)
	elseif kind == "pickup" then
		Pickup.play(spot - Vector3.new(0, 3, 0), spot.Y - 4, "watermelon", true)
	elseif kind == "serve" then
		Serve.play(character, 12, true)
	elseif kind == "swirl" then
		SwirlShot.fire(spot, spot + look * 30, "strawberry")
	elseif kind == "circle" then
		SwirlShot.circle(spot - Vector3.new(0, 4, 0), "mint")
	elseif kind == "landed" then
		SwirlShot.landed(spot - Vector3.new(0, 4, 0), "lemon")
	elseif kind == "teleport" then
		Teleport.play(root.Position, root.Position + look * 12, true)
	elseif kind == "dash" then
		Dash.dust(spot - Vector3.new(0, 4, 0), look.X, look.Z, true)
		Dash.lines(0.35)
	elseif kind == "blink" then
		LootFade.glint(spot - Vector3.new(0, 3, 0))
	elseif kind == "lootpuff" then
		LootFade.puff(spot - Vector3.new(0, 3, 0), "bubblegum")
	end
	workspace:SetAttribute("VfxPreview", nil)
end

function VfxController.Start()
	Vfx.prewarm()
	Remotes.IceBallThrown.OnClientEvent:Connect(onThrown)
	Remotes.IceBallResolved.OnClientEvent:Connect(onResolved)
	Remotes.LootSpawned.OnClientEvent:Connect(onLootSpawned)
	Remotes.Served.OnClientEvent:Connect(onServed)
	Remotes.Teleported.OnClientEvent:Connect(onTeleported)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VfxPreview"):Connect(preview)
	end
end

return VfxController
