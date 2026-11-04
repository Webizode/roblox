--!strict
-- Where everything on a plot island is (Config/Map.plot): the island, its zones, the ServePoint, the Spawn and the
-- plot sign, in the island's own coordinates and in the world. Pure: MapService checks the place against it, the map
-- build script places the graybox with it, and the Lune tests pin it down.
--
-- Local coordinates: `u` along the ring, right as seen from the bridge looking out (0 on the lane), `v` along the
-- lane, outward from the island's centre. World coordinates are x and z around the arena centre.

export type Zone = { id: string, name: string, width: number, color: string }
export type PlotConfig = {
	centerRadius: number,
	width: number,
	depth: number,
	rim: number,
	corner: number,
	surfaceY: number,
	bridgeHalfWidth: number,
	bridgeEnd: number,
	zones: { Zone },
	serveInset: number,
	signAt: { u: number, inset: number },
	sandReserve: number,
	minGap: number,
}
export type MapConfig = {
	arena: { center: { x: number, z: number }, ramps: number, firstRamp: number },
	plot: PlotConfig,
}
-- the island's frame in the world: centre, `right` (the +u direction) and `out` (the +v direction), unit vectors
export type Frame = { x: number, z: number, rightX: number, rightZ: number, outX: number, outZ: number, angle: number }
export type ZoneSpan = { id: string, name: string, color: string, from: number, to: number }

local PlotLayout = {}

-- The lane angle in degrees (from +Z towards +X) of plot number `index` (1 for Plot_01).
function PlotLayout.laneAngle(index: number, config: MapConfig): number
	return config.arena.firstRamp + (index - 1) * 360 / config.arena.ramps
end

-- The frame of the island on the lane at `angle` degrees.
function PlotLayout.frame(angle: number, config: MapConfig): Frame
	local a = math.rad(angle)
	local outX, outZ = math.sin(a), math.cos(a)
	local radius = config.plot.centerRadius
	return {
		x = config.arena.center.x + outX * radius,
		z = config.arena.center.z + outZ * radius,
		-- looking out along the lane, right is out x up: (-outZ, outX)
		rightX = -outZ,
		rightZ = outX,
		outX = outX,
		outZ = outZ,
		angle = angle,
	}
end

-- World x, z of the local point (u, v) on the island with this frame.
function PlotLayout.toWorld(frame: Frame, u: number, v: number): (number, number)
	return frame.x + frame.rightX * u + frame.outX * v, frame.z + frame.rightZ * u + frame.outZ * v
end

-- Local u, v of the world point (x, z).
function PlotLayout.toLocal(frame: Frame, x: number, z: number): (number, number)
	local dx, dz = x - frame.x, z - frame.z
	return dx * frame.rightX + dz * frame.rightZ, dx * frame.outX + dz * frame.outZ
end

-- The walkable surface: half its size along u and v (the island less its rim).
function PlotLayout.surfaceHalf(plot: PlotConfig): (number, number)
	return plot.width / 2 - plot.rim, plot.depth / 2 - plot.rim
end

-- Studs from the machine to the island's inner (bridge) side and outer side.
function PlotLayout.innerRadius(plot: PlotConfig): number
	return plot.centerRadius - plot.depth / 2
end
function PlotLayout.outerRadius(plot: PlotConfig): number
	return plot.centerRadius + plot.depth / 2
end

-- The zones with their u span, left to right, filling the walkable surface's width from its left edge.
function PlotLayout.zones(plot: PlotConfig): { ZoneSpan }
	local halfU = PlotLayout.surfaceHalf(plot)
	local spans = {}
	local from = -halfU
	for _, zone in plot.zones do
		table.insert(spans, { id = zone.id, name = zone.name, color = zone.color, from = from, to = from + zone.width })
		from += zone.width
	end
	return spans
end

-- The zone under the local point (u, v), or nil off the walkable surface.
function PlotLayout.zoneAt(plot: PlotConfig, u: number, v: number): string?
	local halfU, halfV = PlotLayout.surfaceHalf(plot)
	if math.abs(v) > halfV or math.abs(u) > halfU then
		return nil
	end
	for _, span in PlotLayout.zones(plot) do
		if u >= span.from and u <= span.to then
			return span.id
		end
	end
	return nil
end

-- Local spots: the ServePoint at the bridgehead on the lane, the Spawn in the middle, the sign beside the bridgehead.
function PlotLayout.servePoint(plot: PlotConfig): (number, number)
	return 0, -plot.depth / 2 + plot.serveInset
end
function PlotLayout.spawn(_plot: PlotConfig): (number, number)
	return 0, 0
end
function PlotLayout.sign(plot: PlotConfig): (number, number)
	return plot.signAt.u, -plot.depth / 2 + plot.rim + plot.signAt.inset
end

-- The island's four corners in the world (a rectangle grown by `grow` studs all round: the sand rim later).
function PlotLayout.corners(frame: Frame, plot: PlotConfig, grow: number): { { number } }
	local hu, hv = plot.width / 2 + grow, plot.depth / 2 + grow
	local corners = {}
	for _, s in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
		local x, z = PlotLayout.toWorld(frame, hu * s[1], hv * s[2])
		table.insert(corners, { x, z })
	end
	return corners
end

local function segmentDistance(px: number, pz: number, a: { number }, b: { number }): number
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local t = math.clamp(((px - a[1]) * dx + (pz - a[2]) * dz) / (dx * dx + dz * dz), 0, 1)
	local cx, cz = a[1] + t * dx - px, a[2] + t * dz - pz
	return math.sqrt(cx * cx + cz * cz)
end

-- The smallest distance between two neighbouring islands, each grown by `grow` studs (0 when they overlap at a
-- corner; two rectangles that do not overlap are closest corner to edge).
function PlotLayout.neighbourGap(config: MapConfig, grow: number): number
	local a = PlotLayout.corners(PlotLayout.frame(PlotLayout.laneAngle(1, config), config), config.plot, grow)
	local b = PlotLayout.corners(PlotLayout.frame(PlotLayout.laneAngle(2, config), config), config.plot, grow)
	local best = math.huge
	for _, pair in { { a, b }, { b, a } } do
		for _, point in pair[1] do
			for i = 1, 4 do
				best = math.min(best, segmentDistance(point[1], point[2], pair[2][i], pair[2][i % 4 + 1]))
			end
		end
	end
	return best
end

-- Plot number from a plot's name ("Plot_07" -> 7), nil for any other name.
function PlotLayout.indexOf(name: string): number?
	local digits = string.match(name, "^Plot_(%d+)$")
	return if digits then tonumber(digits) else nil
end

return PlotLayout
