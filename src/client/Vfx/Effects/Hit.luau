-- An ice ball ends (Config/Vfx.effects hit, headshot, hitWorld): on a player cream splashes in the colour of the
-- thrown scoop, sprinkles fly and a short white flash shows at the spot and on the body; a headshot is bigger, with a
-- burst of golden stars. On the world, on cover or on a player in their safe zone it is only a small splash. The
-- splash flies back the way the ball came, and a little up.

local Vfx = require(script.Parent.Parent)

local Hit = {}

local Look = Vfx.Config.hit

export type Params = {
	position: Vector3, -- where the ball ended
	dirX: number, -- the ball's flight on the ground
	dirZ: number,
	flavorId: string?, -- the thrown scoop's flavor (nil: the default)
	victim: Model?, -- the character that was hit, nil on the world
	headshot: boolean,
	shielded: boolean, -- the victim stood in their safe zone: no harm, a small splash
	own: boolean, -- the local player threw it or was hit
}

function Hit.play(params: Params)
	local back = Vector3.new(-params.dirX, 0, -params.dirZ)
	back = if back.Magnitude > 1e-3 then back.Unit else Vector3.zero
	local position = params.position + back * Look.lift
	local where = CFrame.lookAt(position, position + back + Vector3.new(0, 0.45, 0), Vector3.new(0, 1, 0.001))
	local color = Vfx.flavorColor(params.flavorId)

	if not params.victim or params.shielded then
		Vfx.burst("hitWorld", where, { color = color, scale = Look.worldScale, own = params.own })
		return
	end
	local scale = if params.headshot then Look.headshotScale else 1
	Vfx.burst("hit", where, { color = color, scale = scale, own = params.own })
	if params.headshot then
		Vfx.burst("headshot", where, { own = params.own })
	end
	Vfx.flashBody(params.victim)
end

return Hit
