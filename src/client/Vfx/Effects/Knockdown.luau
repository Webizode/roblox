-- A knockdown: stars circle over the head for as long as the player lies there (Vfx.Stars), and soft pastel puffs of
-- dust rise where the body hits the ground (Config/Vfx.effects.knockdownDust). The victim's own camera jolt comes
-- with the knockdown itself (MovementController.knockDown, Vfx.Camera).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VfxRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VfxRules"))

local Vfx = require(script.Parent.Parent)

local Knockdown = {}

local Config = Vfx.Config

-- The ground under a character's feet, from its root part.
local function feet(character: Model): Vector3?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil
	end
	return root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 - 0.5, 0) -- a little above it, so the puffs are not cut off by the floor
end

-- `character` goes down for `seconds`; `own`: it is the local player's.
function Knockdown.play(character: Model, seconds: number, own: boolean)
	local head = character:FindFirstChild("Head") :: BasePart?
	if head then
		local look = Config.knockdownStars
		local tier = Vfx.tier(head.Position, own)
		Vfx.Stars.play(head, VfxRules.items(look.count, look.min, Vfx.quality(), tier, Config), seconds)
	end
	task.delay(Config.knockdownDustDelay, function()
		local ground = character.Parent and feet(character)
		if ground then
			-- straight up: the puffs spread out over the ground and rise a little
			Vfx.burst("knockdownDust", CFrame.lookAt(ground, ground + Vector3.new(0, 1, 0), Vector3.new(0, 0, 1)), {
				own = own,
			})
		end
	end)
end

return Knockdown
