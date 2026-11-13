-- The game's effects: the one door to them. An effect is a burst of particles described in Config/Vfx; this plays
-- it where it happens, as much of it as the VFX quality, the distance to the camera and the budget allow (VfxRules),
-- from pooled instances that go back when it is over. Client only and purely looks: effects are started by what the
-- server announced (Controllers/VfxController) and never decide anything.
--
-- Vfx.Camera has the camera jolts, Vfx.Stars the stars over a knocked down head; the effects themselves are the
-- modules in Effects.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Vfx"))
local Flavors = require(Shared:WaitForChild("Config"):WaitForChild("Flavors"))
local VfxRules = require(Shared:WaitForChild("VfxRules"))

local Settings = require(script.Parent:WaitForChild("Settings"))
local Pool = require(script:WaitForChild("Pool"))
local Emit = require(script:WaitForChild("Emit"))

local Vfx = {}

Vfx.Config = Config
Vfx.Pool = Pool
Vfx.Camera = require(script:WaitForChild("Camera"))

export type Options = {
	color: Color3?, -- the scoop's colour for the "scoop" layers
	scale: number?, -- times every size
	own: boolean?, -- the local player's own effect: always in full
}

local live = 0 -- particles of running bursts (their planned counts, until the burst's duration is over)
local played = 0 -- bursts started, for checks
local skipped = 0 -- bursts left out (too far, or no room under the cap)

-- The VFX quality in use ("high", "medium" or "low").
function Vfx.quality(): string
	return Settings.effective().vfxQuality
end

-- How much of an effect at `position` plays (VfxRules.tier), by its distance to the camera.
function Vfx.tier(position: Vector3, own: boolean?): VfxRules.Tier
	local camera = workspace.CurrentCamera
	local distance = if camera then (position - camera.CFrame.Position).Magnitude else 0
	return VfxRules.tier(distance, own == true, Config)
end

-- The colour of a flavor's scoop, for splashes; the default flavor's for an unknown one.
function Vfx.flavorColor(flavorId: string?): Color3
	local flavor = Flavors.byId[flavorId or Config.defaultFlavor] or Flavors.byId[Config.defaultFlavor]
	return Color3.fromHex(flavor.color)
end

-- Plays the effect `name` of Config/Vfx.effects at `where`, flying along its look direction. Returns the number of
-- particles it showed (0: left out).
function Vfx.burst(name: string, where: CFrame, options: Options?): number
	local effect = Config.effects[name]
	if not effect then
		warn(`[Vfx] no effect {name}`)
		return 0
	end
	local own = options ~= nil and options.own == true
	local tier = Vfx.tier(where.Position, own)
	local room = if own then math.huge else Config.maxLive - live
	local plan = VfxRules.plan(effect, Vfx.quality(), tier, room, Config)
	if plan.total <= 0 then
		skipped += 1
		return 0
	end
	local rig, fresh = Emit.take(name, effect)
	local color = (options and options.color) or Vfx.flavorColor(nil)
	local scale = (options and options.scale) or 1
	if fresh then
		-- built this frame: it can only emit from the next one on
		RunService.Heartbeat:Once(function()
			Emit.fire(rig, effect, plan.counts, where, color, scale)
		end)
	else
		Emit.fire(rig, effect, plan.counts, where, color, scale)
	end
	played += 1
	live += plan.total
	task.delay(effect.budget.duration + 0.05, function()
		live -= plan.total
		Emit.give(name, rig)
	end)
	return plan.total
end

-- Builds one set of emitters for every effect ahead of time, so the first hit of a session shows at once and without
-- a hitch.
function Vfx.prewarm()
	for name, effect in Config.effects do
		local rig = Emit.take(name, effect)
		Emit.give(name, rig)
	end
end

-- A short white flash over a whole character, seen by everyone: pooled Highlights that point at the character
-- instead of sitting in it, so they survive it.
function Vfx.flashBody(character: Model)
	if Vfx.tier(character:GetPivot().Position, false) == "off" then
		return
	end
	local look = Config.bodyFlash
	local highlight = Pool.take("bodyFlash", function(): Highlight
		local made = Instance.new("Highlight")
		made.Name = "VfxBodyFlash"
		made.FillColor = Color3.new(1, 1, 1)
		made.OutlineTransparency = 1
		made.DepthMode = Enum.HighlightDepthMode.Occluded
		made.Enabled = false
		return made
	end)
	highlight.Parent = Pool.folder()
	highlight.Adornee = character
	highlight.FillTransparency = look.transparency
	highlight.Enabled = true
	TweenService:Create(highlight, TweenInfo.new(look.time), { FillTransparency = 1 }):Play()
	task.delay(look.time + 0.05, function()
		highlight.Enabled = false
		highlight.Adornee = nil
		if highlight.Parent then
			Pool.give("bodyFlash", highlight)
		end
	end)
end

-- For checks (the performance test, the console): what runs right now and what the pools hold.
function Vfx.stats(): { live: number, played: number, skipped: number, quality: string, pools: any }
	return { live = live, played = played, skipped = skipped, quality = Vfx.quality(), pools = Pool.stats() }
end

Vfx.Stars = require(script:WaitForChild("Stars"))

return Vfx
