-- lune run tests
-- Runs every spec and syntax-checks every Luau file under src, so Roblox-only code is at least parsed here.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local harness = require("./harness")

require("./TowerModel.spec")
require("./Economy.spec")
require("./Geometry.spec")
require("./Catch.spec")
require("./Combat.spec")
require("./Dash.spec")
require("./ThrowPose.spec")
require("./BallMotion.spec")
require("./Stance.spec")
require("./Loot.spec")

local syntaxErrors = {}
local checkedFiles = 0

local function walk(directory: string)
	for _, name in fs.readDir(directory) do
		local path = directory .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif string.sub(name, -5) == ".luau" then
			checkedFiles += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				table.insert(syntaxErrors, path .. ": " .. tostring(err))
			end
		end
	end
end

walk("src")

local results = harness.results()
for _, failure in results.failures do
	print(`FAIL {failure.name}\n     {failure.err}`)
end
for _, message in syntaxErrors do
	print(`SYNTAX {message}`)
end

print(`{results.passed} passed, {results.failed} failed, {checkedFiles} files parsed, {#syntaxErrors} syntax errors`)

if results.failed > 0 or #syntaxErrors > 0 then
	process.exit(1)
end
