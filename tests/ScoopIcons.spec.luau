local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local ScoopIcons = require("../src/shared/Config/ScoopIcons")
local Flavors = require("../src/shared/Config/Flavors")

describe("ScoopIcons", function()
	it("names only flavors that exist, each with an uploaded picture", function()
		local known = {}
		for id in Flavors.byId do
			known[id] = true
		end
		for id, image in ScoopIcons :: { [string]: string } do
			expect(known[id] == true).toBe(true)
			expect(string.match(image, "^rbxassetid://%d+$") ~= nil).toBe(true)
		end
	end)
end)
