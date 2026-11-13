-- lune run scripts/vfx-serve
-- Serves the effects' particle pictures (assets/Vfx/textures/*.png, written by make_vfx_textures.py in Blender) on
-- http://localhost:8766/textures/<name>.png, so the Studio MCP can upload them (its image upload takes URLs). Only
-- that folder, only plain file names. Stop with Ctrl+C once the upload is done; the ids go into Config/Vfx.textures.

local fs = require("@lune/fs")
local net = require("@lune/net")

local PORT = 8766
local DIR = "assets/Vfx/textures"

net.serve(PORT, function(request)
	local name = string.match(request.path, "^/textures/([%w_%-]+%.png)$")
	local path = name and `{DIR}/{name}`
	if not path or not fs.isFile(path) then
		return { status = 404, body = "not found" }
	end
	return { status = 200, headers = { ["Content-Type"] = "image/png" }, body = fs.readFile(path) }
end)
print(`serving the effect pictures on http://localhost:{PORT}/textures/...`)
