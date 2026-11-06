local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local PlotLayout = require("../src/shared/PlotLayout")
local MapConfig = require("../src/shared/Config/Map")
local EconomyConfig = require("../src/shared/Config/Economy")
local ArenaZone = require("../src/shared/ArenaZone")

local plot = MapConfig.plot

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-6)
end

describe("Plot islands: size and place on the ring", function()
	it("are wide rectangles across the lane, about 110 x 60", function()
		expect(plot.width).toBe(110)
		expect(plot.depth).toBe(60)
		expect(plot.width > plot.depth).toBe(true)
	end)

	it("the bridge (unchanged) reaches onto the island's inner side, a few studs, not past the rim", function()
		local inner = PlotLayout.innerRadius(plot)
		expect(inner).toBe(292)
		expect(plot.bridgeEnd > inner).toBe(true)
		expect(plot.bridgeEnd - inner <= plot.rim).toBe(true)
		-- and it meets the long side in the middle: the lane runs through the island's centre
		local frame = PlotLayout.frame(PlotLayout.laneAngle(1, MapConfig), MapConfig)
		local u = PlotLayout.toLocal(frame, frame.outX * plot.bridgeEnd, frame.outZ * plot.bridgeEnd)
		expect(near(u, 0)).toBe(true)
	end)

	it("Plot_01 lies on the first lane at 15 degrees, the others every 30", function()
		expect(PlotLayout.laneAngle(1, MapConfig)).toBe(15)
		expect(PlotLayout.laneAngle(12, MapConfig)).toBe(345)
		local frame = PlotLayout.frame(15, MapConfig)
		expect(near(frame.x, 322 * math.sin(math.rad(15)))).toBe(true)
		expect(near(frame.z, 322 * math.cos(math.rad(15)))).toBe(true)
	end)

	it("right as seen from the bridge looking out is the +u direction", function()
		-- on the lane at 0 degrees the island looks out along +Z; Roblox's right of a look along +Z is -X
		local frame = PlotLayout.frame(0, MapConfig)
		expect(near(frame.rightX, -1)).toBe(true)
		expect(near(frame.rightZ, 0)).toBe(true)
		local x, z = PlotLayout.toWorld(frame, 10, 5)
		local u, v = PlotLayout.toLocal(frame, x, z)
		expect(near(u, 10) and near(v, 5)).toBe(true)
	end)

	it("neighbouring islands keep well apart (about 45 studs)", function()
		local gap = PlotLayout.neighbourGap(MapConfig, 0)
		expect(gap > 40).toBe(true)
		expect(gap < 50).toBe(true)
	end)

	it("with a sand rim of sandReserve all round they still keep minGap apart", function()
		expect(plot.sandReserve >= 6).toBe(true)
		expect(PlotLayout.neighbourGap(MapConfig, plot.sandReserve) >= plot.minGap).toBe(true)
		-- the rim does not reach back to the hub ring the bridges start from (r 232)
		expect(PlotLayout.innerRadius(plot) - plot.sandReserve > 232).toBe(true)
	end)

	it("the whole island, rim included, lies in the safe zone", function()
		local frame = PlotLayout.frame(PlotLayout.laneAngle(1, MapConfig), MapConfig)
		for _, corner in PlotLayout.corners(frame, plot, plot.sandReserve) do
			expect(ArenaZone.contains(corner[1], corner[2], MapConfig.arena)).toBe(false)
		end
		local x, z = PlotLayout.toWorld(frame, 0, -plot.depth / 2)
		expect(ArenaZone.contains(x, z, MapConfig.arena)).toBe(false)
	end)
end)

describe("Plot zones and stations", function()
	local spans = PlotLayout.zones(plot)
	local stations = plot.stations
	local CART_HALF_DEPTH = 9.3 / 2 -- the Sell Cart's collision box (assets/PlotKit/studio_plotkit_templates.luau)

	it("three zones side by side fill the walkable surface exactly, without gaps", function()
		expect(#spans).toBe(3)
		local halfU = PlotLayout.surfaceHalf(plot)
		expect(near(spans[1].from, -halfU)).toBe(true)
		expect(near(spans[#spans].to, halfU)).toBe(true)
		for i = 2, #spans do
			expect(near(spans[i].from, spans[i - 1].to)).toBe(true)
			expect(spans[i].to > spans[i].from).toBe(true)
		end
	end)

	it("in this order from the left: Working Station, Sell Cart, Scoop Chest", function()
		local ids = {}
		for _, span in spans do
			table.insert(ids, span.id)
		end
		expect(table.concat(ids, ",")).toBe("WorkingStation,SellCart,ScoopChest")
	end)

	it("every station stands in its own zone, on the walkable surface", function()
		local halfU, halfV = PlotLayout.surfaceHalf(plot)
		for id, station in stations do
			expect(PlotLayout.zoneAt(plot, station.u, station.v)).toBe(id)
			expect(math.abs(station.u) < halfU and math.abs(station.v) < halfV).toBe(true)
		end
	end)

	it("from the bridge: station left, cart at the back in the middle, chest right", function()
		expect(stations.WorkingStation.u < 0).toBe(true)
		expect(stations.ScoopChest.u > 0).toBe(true)
		expect(stations.SellCart.u).toBe(0)
		expect(stations.SellCart.v > plot.plaza.v).toBe(true)
		-- all facing the plaza: the cart to the bridge, the station to +u, the chest to -u
		expect(stations.SellCart.turn).toBe(0)
		expect(stations.WorkingStation.turn).toBe(90)
		expect(stations.ScoopChest.turn).toBe(-90)
		expect(stations.WorkingStation.v).toBe(plot.plaza.v)
		expect(stations.ScoopChest.v).toBe(plot.plaza.v)
	end)

	it("the ServePoint is in front of the Sell Cart's counter, in the Sell Cart zone", function()
		local u, v = PlotLayout.servePoint(plot)
		local cart = stations.SellCart
		expect(PlotLayout.zoneAt(plot, u, v)).toBe("SellCart")
		expect(u).toBe(cart.u)
		local gap = cart.v - CART_HALF_DEPTH - v -- from the cart's front to the ServePoint
		expect(gap > 1 and gap < 4).toBe(true)
	end)

	it("the Spawn is on the plaza, out of the serve radius, so a fresh catch is not served away", function()
		local su, sv = PlotLayout.spawn(plot)
		local pu, pv = PlotLayout.servePoint(plot)
		expect(math.sqrt((su - plot.plaza.u) ^ 2 + (sv - plot.plaza.v) ^ 2) < 7).toBe(true)
		expect(math.sqrt((su - pu) ^ 2 + (sv - pv) ^ 2) > EconomyConfig.serveRadius + 4).toBe(true)
		-- and the bridge's end is out of it too: players coming in do not serve on the bridge
		expect(plot.centerRadius + pv - EconomyConfig.serveRadius > plot.bridgeEnd).toBe(true)
	end)

	it("the plot sign stands beside the bridgehead, on the island, off the bridge", function()
		local u, v = PlotLayout.sign(plot)
		expect(math.abs(u) > plot.bridgeHalfWidth).toBe(true)
		expect(PlotLayout.zoneAt(plot, u, v) ~= nil).toBe(true)
		expect(v < 0).toBe(true)
	end)

	it("off the walkable surface there is no zone", function()
		local halfU, halfV = PlotLayout.surfaceHalf(plot)
		expect(PlotLayout.zoneAt(plot, halfU + 1, 0)).toBe(nil)
		expect(PlotLayout.zoneAt(plot, 0, -halfV - 1)).toBe(nil)
	end)

	it("plot numbers come from the names", function()
		expect(PlotLayout.indexOf("Plot_07")).toBe(7)
		expect(PlotLayout.indexOf("Plot_12")).toBe(12)
		expect(PlotLayout.indexOf("Cart_1")).toBe(nil)
	end)
end)
