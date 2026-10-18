-- lune run scripts/check
-- Everything a push has to pass: formatting, lint, unit tests, a Rojo build and a check of the built place.
-- Runs the same on Windows (PowerShell) and Linux because it only shells out to the Rokit tools.

local fs = require("@lune/fs")
local process = require("@lune/process")

local steps = {
	{ "stylua", { "--check", "src", "tests", "scripts" } },
	{ "selene", { "src", "tests", "scripts" } },
	{ "lune", { "run", "tests/run.luau" } },
	{ "rojo", { "build", "default.project.json", "-o", "build/WobbleScoops.rbxl" } },
	{ "lune", { "run", "tests/place.luau", "build/WobbleScoops.rbxl" } },
}

if not fs.isDir("build") then
	fs.writeDir("build")
end

for _, step in steps do
	local program, args = step[1], step[2]
	print(`> {program} {table.concat(args, " ")}`)
	local result = process.exec(program, args, { stdio = "inherit" })
	if not result.ok then
		print(`FAILED: {program} exited with {result.code}`)
		process.exit(result.code)
	end
end

print("all checks passed")
