-- lune run scripts/tower-scoops-serve
-- Serves the tower scoops' detail pictures (assets/TowerScoops/textures/*.png, written by build_scoops.py in Blender)
-- on http://localhost:8765/textures/<name>.png, so the Studio MCP can upload them (its image upload takes URLs).
-- Only that folder, only plain file names. Stop with Ctrl+C once the upload is done.

local fs = require("@lune/fs")
local net = require("@lune/net")

local PORT = 8765
local DIR = "assets/TowerScoops/textures"

net.serve(PORT, function(request)
	local name = string.match(request.path, "^/textures/([%w_%-]+%.png)$")
	local path = name and `{DIR}/{name}`
	if not path or not fs.isFile(path) then
		return { status = 404, body = "not found" }
	end
	return { status = 200, headers = { ["Content-Type"] = "image/png" }, body = fs.readFile(path) }
end)
print(`serving the tower scoop pictures on http://localhost:{PORT}/textures/...`)
