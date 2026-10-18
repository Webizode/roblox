--!strict
-- Lookups for Secret Stacks and Churn swirls. Pure functions over the data in Config/Recipes.

export type StackDef = {
	id: string,
	sequence: { string },
	effect: any,
}

export type SwirlDef = {
	id: string,
	inputs: { string },
	minutes: number,
}

export type Match = {
	id: string,
	from: number,
	to: number,
	effect: any,
}

local Recipes = {}

-- Finds every non-overlapping occurrence of each secret stack in a tower (bottom to top).
function Recipes.findStacks(flavorIds: { string }, defs: { StackDef }): { Match }
	local matches: { Match } = {}
	for _, def in defs do
		local length = #def.sequence
		local index = 1
		while index + length - 1 <= #flavorIds do
			local hit = true
			for offset = 1, length do
				if flavorIds[index + offset - 1] ~= def.sequence[offset] then
					hit = false
					break
				end
			end
			if hit then
				table.insert(matches, { id = def.id, from = index, to = index + length - 1, effect = def.effect })
				index += length
			else
				index += 1
			end
		end
	end
	return matches
end

-- The swirl two flavors make, in either order, or nil if they do not combine.
function Recipes.churnResult(a: string, b: string, defs: { SwirlDef }): SwirlDef?
	for _, def in defs do
		local first, second = def.inputs[1], def.inputs[2]
		if (first == a and second == b) or (first == b and second == a) then
			return def
		end
	end
	return nil
end

return Recipes
