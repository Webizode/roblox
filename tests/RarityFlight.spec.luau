local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local RarityFlight = require("../src/shared/RarityFlight")
local Vfx = require("../src/shared/Config/Vfx")
local Flavors = require("../src/shared/Config/Flavors")

local CONFIG = Vfx.flight
local COLORS = Flavors.rarityColors

local function style(rarity: string, quality: string?)
	return RarityFlight.style(rarity, quality or "high", CONFIG, COLORS)
end

describe("Rarity in flight", function()
	it("has a look for every rarity, mythic, secret and divine like legendary until they are designed", function()
		for _, rarity in Flavors.rarities do
			expect(CONFIG.byRarity[rarity] ~= nil).toBe(true)
		end
		for _, rarity in { "mythic", "secret", "divine" } do
			expect(CONFIG.byRarity[rarity].like).toBe("legendary")
			expect(style(rarity).trail.width).toBe(style("legendary").trail.width)
		end
	end)

	it("gets louder with the rarity: no trail for common, then wider and longer trails", function()
		expect(style("common").trail).toBeNil()
		local order = { "uncommon", "rare", "epic", "legendary" }
		for i = 2, #order do
			local before, now = style(order[i - 1]), style(order[i])
			expect(now.trail.width).toBeGreaterThan(before.trail.width)
			expect(now.trail.lifetime).toBeGreaterThan(before.trail.lifetime)
		end
	end)

	it("adds the glow from rare, sparks and a sound from epic, the highlight only for legendary", function()
		expect(style("uncommon").glow).toBeNil()
		expect(style("rare").glow ~= nil).toBe(true)
		expect(style("rare").sparks).toBe(0)
		expect(style("epic").sparks).toBeGreaterThan(0)
		expect(style("epic").sound ~= nil).toBe(true)
		expect(style("epic").highlight).toBe(false)
		expect(style("legendary").highlight).toBe(true)
		expect(style("legendary").sound ~= nil).toBe(true)
		expect(style("legendary").sound ~= style("epic").sound).toBe(true)
	end)

	it("uses the rarity colours of the signs and circles, gold for legendary", function()
		expect(style("uncommon").color).toBe(COLORS.uncommon)
		expect(style("rare").color).toBe(COLORS.rare)
		expect(style("epic").color).toBe(COLORS.epic)
		expect(style("legendary").color).toBe("#FFD23F")
	end)

	it("keeps only the trail on low quality: no sparks, light or highlight", function()
		local low = style("legendary", "low")
		expect(low.trail ~= nil).toBe(true)
		expect(low.sparks).toBe(0)
		expect(low.glow).toBeNil()
		expect(low.highlight).toBe(false)
		expect(style("legendary", "medium").sparks).toBeLessThan(style("legendary", "high").sparks)
		expect(style("legendary", "unknown").sparks).toBe(style("legendary", "high").sparks)
	end)

	it(
		"announces epic with a flash and legendary with a 1 s glow, delaying only that shot; banner only legendary",
		function()
			expect(style("rare").announce).toBeNil()
			expect(style("epic").announce.kind).toBe("flash")
			expect(RarityFlight.delay("epic", CONFIG)).toBe(0)
			expect(style("legendary").announce.kind).toBe("glow")
			expect(style("legendary").announce.time).toBeCloseTo(1, 0.3)
			expect(RarityFlight.delay("legendary", CONFIG)).toBeCloseTo(style("legendary").announce.time, 1e-9)
			expect(RarityFlight.delay("common", CONFIG)).toBe(0)
			expect(RarityFlight.delay("unknown", CONFIG)).toBe(0)
			expect(style("epic").banner).toBe(false)
			expect(style("legendary").banner).toBe(true)
		end
	)
end)

describe("Landing circles of the Big Swirl", function()
	local TowerScoops = require("../src/shared/Config/TowerScoops")
	local look = TowerScoops.landingCircle

	it("have no dark rim any more and are a little see-through", function()
		expect(look.outline).toBeNil()
		expect(look.outlineImage).toBeNil()
		expect(look.transparency > 0.3 and look.transparency < 0.7).toBe(true)
		expect(look.flashTransparency > 0 and look.flashTransparency < look.transparency).toBe(true)
	end)

	it("common is light grey, every rarer one the colour of its trail (a legendary golden)", function()
		expect(RarityFlight.circleColor("common", CONFIG, COLORS, look.common)).toBe(look.common)
		expect(look.common ~= "#FFFFFF").toBe(true) -- not glaring white
		for _, rarity in { "uncommon", "rare", "epic", "legendary", "mythic", "secret", "divine" } do
			expect(RarityFlight.circleColor(rarity, CONFIG, COLORS, look.common)).toBe(style(rarity).color)
		end
		expect(RarityFlight.circleColor(nil, CONFIG, COLORS, look.common)).toBe(look.common)
		expect(RarityFlight.circleColor("unknown", CONFIG, COLORS, look.common)).toBe(look.common)
		expect(RarityFlight.circleColor("legendary", CONFIG, COLORS, look.common)).toBe(COLORS.golden)
		expect(RarityFlight.circleColor("rare", CONFIG, COLORS, look.common)).toBe(COLORS.rare)
	end)
end)
