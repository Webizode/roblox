-- lune run scripts/stamp
-- Writes src/shared/Build.luau (gitignored): the commit the code comes from, its date and whether there were changes
-- on top of it. Rojo syncs it into Studio like any other module, so what gets published carries it; the settings show
-- it at the bottom and the touch debug overlay on its first line (client Version). Runs from `lune run scripts/check`,
-- from start-rojo.cmd. After a commit, run it once more (`lune run scripts/stamp`) before publishing, so the
-- stamp names that commit and not the one before it with a "+".

local fs = require("@lune/fs")
local process = require("@lune/process")

local PATH = "src/shared/Build.luau"

local function git(args: { string }): string?
	local ok, result = pcall(process.exec, "git", args)
	if not ok or not result.ok then
		return nil
	end
	return (string.gsub(result.stdout, "%s+$", ""))
end

local line = git({ "log", "-1", "--format=%h|%cd", "--date=format:%Y-%m-%d %H:%M" })
local commit, date = "unknown", ""
if line then
	commit, date = string.match(line, "^([^|]*)|(.*)$")
	commit = commit or "unknown"
	date = date or ""
end
-- changes to the code that is synced (src, the project file), not to docs or assets
local status = git({ "status", "--porcelain", "--", "src", "default.project.json" }) or ""
-- the stamp itself is ignored, so it never makes the tree count as changed
local dirty = status ~= ""

local source = table.concat({
	"-- Written by `lune run scripts/stamp` (gitignored): the build the code comes from. Do not edit.",
	"return {",
	`\tcommit = "{commit}",`,
	`\tdate = "{date}",`,
	`\tdirty = {dirty},`,
	"}",
	"",
}, "\n")

local old = if fs.isFile(PATH) then fs.readFile(PATH) else nil
if old ~= source then
	fs.writeFile(PATH, source)
end
print(`build stamp: {commit}{if dirty then "+" else ""} {date}`)
