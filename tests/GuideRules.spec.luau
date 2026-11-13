local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local GuideRules = require("../src/shared/GuideRules")
local UiConfig = require("../src/shared/Config/Ui")

local config = { showShare = 0.75, arriveRadius = 20 }

describe("Plot guide: the light over the own serve point", function()
	it("shows from three quarters full, away from the plot", function()
		expect(GuideRules.showLight(21, 28, 100, config)).toBe(true)
		expect(GuideRules.showLight(28, 28, 100, config)).toBe(true)
		expect(GuideRules.showLight(20, 28, 100, config)).toBe(false)
		expect(GuideRules.showLight(3, 4, 100, config)).toBe(true) -- exactly 0.75
	end)

	it("never without scoops or a cone, and not at the plot", function()
		expect(GuideRules.showLight(0, 28, 100, config)).toBe(false)
		expect(GuideRules.showLight(5, 0, 100, config)).toBe(false)
		expect(GuideRules.showLight(28, 28, 20, config)).toBe(false)
		expect(GuideRules.showLight(28, 28, 20.5, config)).toBe(true)
	end)

	it("lights up the serve point once, on coming near with scoops", function()
		expect(GuideRules.arrived(5, false, 15, config)).toBe(true)
		expect(GuideRules.arrived(5, true, 15, config)).toBe(false) -- already there
		expect(GuideRules.arrived(0, false, 15, config)).toBe(false) -- nothing to serve
		expect(GuideRules.arrived(5, false, 25, config)).toBe(false) -- not there yet
	end)

	it("the shipped config shows the light before the cone is full", function()
		expect(UiConfig.guide.showShare).toBeGreaterThan(0)
		expect(UiConfig.guide.showShare).toBeLessThan(1)
	end)
end)

describe("Plot guide: the pin over the own plot", function()
	local pin = {
		pinFade = 40,
		pinHide = 22,
		pinTransparency = 0.4,
		pinStrongTransparency = 0,
		pinCombatTransparency = 0.7,
		pinCombatScale = 0.75,
		pinStrongScale = 1.15,
	}

	it("is faint from afar, gone on the plot and fades in between", function()
		local far = GuideRules.pinLook(300, false, false, pin)
		expect(far).toBeCloseTo(0.4)
		expect((GuideRules.pinLook(22, false, false, pin))).toBeCloseTo(1)
		expect((GuideRules.pinLook(10, false, false, pin))).toBeCloseTo(1)
		expect((GuideRules.pinLook(31, false, false, pin))).toBeCloseTo(0.7) -- half way: half as visible
	end)

	it("turns solid and bigger once the cone is nearly full", function()
		local transparency, scale = GuideRules.pinLook(300, true, false, pin)
		expect(transparency).toBeCloseTo(0)
		expect(scale).toBeCloseTo(1.15)
	end)

	it("is fainter and smaller in combat mode, even with a full cone", function()
		local transparency, scale = GuideRules.pinLook(300, true, true, pin)
		expect(transparency).toBeCloseTo(0.7)
		expect(scale).toBeCloseTo(1.15 * 0.75)
		local plain, plainScale = GuideRules.pinLook(300, false, true, pin)
		expect(plain).toBeCloseTo(0.7)
		expect(plainScale).toBeCloseTo(0.75)
	end)

	it("the shipped config hides the pin before it fades it", function()
		expect(UiConfig.guide.pinFade).toBeGreaterThan(UiConfig.guide.pinHide)
	end)
end)

describe("Plot guide: the arrow at the screen's edge", function()
	it("is not needed while the target is in the picture", function()
		local x = GuideRules.edgeArrow(400, 300, true, 800, 600, 40)
		expect(x).toBeNil()
	end)

	it("sits on the edge towards a target off to the right", function()
		local x, y, angle = GuideRules.edgeArrow(1200, 300, true, 800, 600, 40)
		expect(x).toBeCloseTo(760)
		expect(y).toBeCloseTo(300)
		expect(angle).toBeCloseTo(0)
	end)

	it("points the other way for a target behind the camera", function()
		-- behind and projected to the right: the target is to the left
		local x, y, angle = GuideRules.edgeArrow(700, 300, false, 800, 600, 40)
		expect(x).toBeCloseTo(40)
		expect(y).toBeCloseTo(300)
		expect(math.abs(angle :: number)).toBeCloseTo(180)
	end)

	it("points down for a target straight behind", function()
		local x, y, angle = GuideRules.edgeArrow(400, 300, false, 800, 600, 40)
		expect(x).toBeCloseTo(400)
		expect(y).toBeCloseTo(560)
		expect(angle).toBeCloseTo(90)
	end)

	it("stays inside the margin in a corner", function()
		local x, y = GuideRules.edgeArrow(-500, -500, true, 800, 600, 40)
		expect(x :: number >= 40 - 1e-6).toBe(true)
		expect(y :: number >= 40 - 1e-6).toBe(true)
	end)
end)
