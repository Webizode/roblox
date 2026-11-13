local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local VfxRules = require("../src/shared/VfxRules")
local Config = require("../src/shared/Config/Vfx")
local SettingsConfig = require("../src/shared/Config/Settings")

local QUALITIES = { "high", "medium", "low" }

describe("Vfx: every effect keeps its budget", function()
	it("no effect shows more particles than its budget, at any quality", function()
		for name, effect in Config.effects do
			local written = 0
			for _, layer in effect.layers do
				written += layer.count
			end
			if written > effect.budget.particles then
				error(`{name}: {written} particles written, budget {effect.budget.particles}`)
			end
			for _, quality in QUALITIES do
				expect(VfxRules.peak(effect, quality, Config) <= effect.budget.particles).toBe(true)
			end
		end
	end)

	it("no particle outlives its effect's duration", function()
		for name, effect in Config.effects do
			if VfxRules.longest(effect) > effect.budget.duration then
				error(`{name}: a particle lives {VfxRules.longest(effect)} s, budget {effect.budget.duration} s`)
			end
		end
	end)

	it("every layer names a picture and a colour that exist", function()
		for name, effect in Config.effects do
			for index, layer in effect.layers do
				if not Config.textures[layer.texture] then
					error(`{name} layer {index}: no picture {layer.texture}`)
				end
				local known = layer.color == "scoop"
					or Config.colors[layer.color]
					or string.sub(layer.color, 1, 1) == "#"
				if not known then
					error(`{name} layer {index}: no colour {layer.color}`)
				end
			end
		end
	end)

	it("the perfect throw's trail keeps its budget", function()
		local trail = Config.perfectTrail
		expect(trail.rate * trail.lifetime <= trail.budget.particles).toBe(true)
	end)

	it("the worst case stays under the cap: six headshots that knock down, each from a perfect throw", function()
		local effects = Config.effects
		for _, quality in QUALITIES do
			local one = VfxRules.peak(effects.hit, quality, Config)
				+ VfxRules.peak(effects.headshot, quality, Config)
				+ VfxRules.peak(effects.knockdownDust, quality, Config)
				+ VfxRules.items(Config.knockdownStars.count, Config.knockdownStars.min, quality, "full", Config)
				+ VfxRules.rate(Config.perfectTrail.rate, quality, Config) * Config.perfectTrail.lifetime
			expect(6 * one <= Config.maxLive).toBe(true)
		end
	end)
end)

describe("Vfx: quality and distance", function()
	it("a lower quality shows fewer particles, and low leaves the extras out", function()
		local hit = Config.effects.hit
		local high = VfxRules.plan(hit, "high", "full", math.huge, Config)
		local medium = VfxRules.plan(hit, "medium", "full", math.huge, Config)
		local low = VfxRules.plan(hit, "low", "full", math.huge, Config)
		expect(medium.total).toBeLessThan(high.total)
		expect(low.total).toBeLessThan(medium.total)
		for index, layer in hit.layers do
			if layer.extra then
				expect(high.counts[index]).toBeGreaterThan(0)
				expect(low.counts[index]).toBe(0)
			else
				expect(low.counts[index]).toBeGreaterThan(0) -- every other layer still shows
			end
		end
	end)

	it("far away an effect is simpler, further away it is left out; the own one always plays in full", function()
		expect(VfxRules.tier(10, false, Config)).toBe("full")
		expect(VfxRules.tier(Config.distance.full + 1, false, Config)).toBe("reduced")
		expect(VfxRules.tier(Config.distance.reduced + 1, false, Config)).toBe("off")
		expect(VfxRules.tier(Config.distance.reduced + 1, true, Config)).toBe("full")
		local hit = Config.effects.hit
		local near = VfxRules.plan(hit, "high", "full", math.huge, Config)
		local far = VfxRules.plan(hit, "high", "reduced", math.huge, Config)
		local gone = VfxRules.plan(hit, "high", "off", math.huge, Config)
		expect(far.total).toBeLessThan(near.total)
		expect(far.total).toBeGreaterThan(0)
		expect(gone.total).toBe(0)
		for index, layer in hit.layers do
			if layer.extra then
				expect(far.counts[index]).toBe(0)
			end
		end
	end)

	it("the cap thins an effect out and then leaves it out", function()
		local hit = Config.effects.hit
		local full = VfxRules.plan(hit, "high", "full", math.huge, Config)
		local tight = VfxRules.plan(hit, "high", "full", 10, Config)
		expect(tight.total <= 10).toBe(true)
		expect(tight.total).toBeGreaterThan(0)
		expect(tight.total).toBeLessThan(full.total)
		expect(VfxRules.plan(hit, "high", "full", 0, Config).total).toBe(0)
		expect(VfxRules.plan(hit, "high", "full", -5, Config).total).toBe(0)
	end)

	it(
		"the stars over a knocked down head: fewer at a lower quality, never fewer than the minimum, none when off",
		function()
			local stars = Config.knockdownStars
			expect(VfxRules.items(stars.count, stars.min, "high", "full", Config)).toBe(stars.count)
			expect(VfxRules.items(stars.count, stars.min, "low", "full", Config)).toBe(stars.min)
			expect(VfxRules.items(stars.count, stars.min, "low", "reduced", Config)).toBe(stars.min)
			expect(VfxRules.items(stars.count, stars.min, "high", "off", Config)).toBe(0)
		end
	)

	it("an unknown quality counts as high, and every quality of the settings is known here", function()
		local hit = Config.effects.hit
		expect(VfxRules.peak(hit, "ultra", Config)).toBe(VfxRules.peak(hit, "high", Config))
		for quality in SettingsConfig.particleScale do
			expect(Config.quality[quality]).toBeTruthy()
		end
	end)
end)
