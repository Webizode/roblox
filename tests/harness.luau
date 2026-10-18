-- Minimal test harness for Lune. Specs call describe/it/expect; run.luau reports and sets the exit code.

local harness = {}

local results = { passed = 0, failed = 0, failures = {} }
local prefix = {}

function harness.describe(name: string, body: () -> ())
	table.insert(prefix, name)
	body()
	table.remove(prefix)
end

function harness.it(name: string, body: () -> ())
	local fullName = table.concat(prefix, " > ") .. " > " .. name
	local ok, err = pcall(body)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, { name = fullName, err = tostring(err) })
	end
end

local function fail(message: string)
	error(message, 3)
end

function harness.expect(actual: any)
	local matchers = {}

	function matchers.toBe(expected: any)
		if actual ~= expected then
			fail(`expected {tostring(expected)}, got {tostring(actual)}`)
		end
	end

	function matchers.toBeCloseTo(expected: number, tolerance: number?)
		local tol = tolerance or 1e-6
		if math.abs(actual - expected) > tol then
			fail(`expected {expected} ± {tol}, got {actual}`)
		end
	end

	function matchers.toBeGreaterThan(expected: number)
		if not (actual > expected) then
			fail(`expected > {expected}, got {actual}`)
		end
	end

	function matchers.toBeLessThan(expected: number)
		if not (actual < expected) then
			fail(`expected < {expected}, got {actual}`)
		end
	end

	function matchers.toBeTruthy()
		if not actual then
			fail(`expected truthy, got {tostring(actual)}`)
		end
	end

	function matchers.toBeNil()
		if actual ~= nil then
			fail(`expected nil, got {tostring(actual)}`)
		end
	end

	return matchers
end

function harness.results()
	return results
end

return harness
