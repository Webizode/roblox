-- Serves the PNG and JPG files of one folder on http://localhost:<port>/<name>, so the Studio MCP's upload_image can
-- fetch them and upload them to Roblox (see docs/live-sync.md, "Bilder hochladen"). Stops with Ctrl+C.
--   lune run scripts/serve-images "<folder>" [port, default 8765]
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local dir = process.args[1]
local port = tonumber(process.args[2]) or 8765
assert(dir and fs.isDir(dir), "usage: lune run scripts/serve-images <folder> [port]")

local types = { png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg" }

net.serve(port, function(request)
	local name = string.match(request.path, "^/([%w_%-%.]+)$")
	local extension = name and string.lower(string.match(name, "%.(%w+)$") or "")
	local kind = extension and types[extension]
	if kind and fs.isFile(dir .. "/" .. name) then
		return { status = 200, headers = { ["Content-Type"] = kind }, body = fs.readFile(dir .. "/" .. name) }
	end
	return { status = 404, body = "not found" }
end)
print(`serving {dir} on http://localhost:{port}/`)
