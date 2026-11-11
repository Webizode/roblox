--!nocheck
-- Builds the wooden bridges from the hub kit modules (Studio command bar or Studio MCP, Edit mode). Needs the
-- templates ServerStorage.HubKit.BridgeEnd and .BridgeMid (assets/HubKit/README.md, studio_hubkit_templates.luau).
-- Per bridge Workspace."Ice Cream Map".Mosty.Most_k (k in BRIDGES):
--   * the old flat MeshPart Pomost moves to ServerStorage."MapBackup_2026-11-07_Pomost" as Most_k (once; it stays
--     there on later runs). Pomost_Kolizja, the walking collision, stays exactly as it is: Mosty is not part of the
--     map contract, and the deck of the new bridge lies flush on it.
--   * a Model Bruecke with end + 4 middles + end (turned round) along the old deck, 66 long from r 229 to r 295:
--     the deck top (the modules' origin) on the top of Pomost_Kolizja, the end pieces' land side on the ring and on
--     the island. The post caps (MeshParts *_Cap_*) take the sector's flavour (MAIN, as on the hub buildings); the
--     rest keeps the kit colours. The railings collide through the modules' invisible boxes (Collision, Collision_*).
--   * over each railing an invisible wall from the deck up to y WALL_TOP, from big post to big post, in
--     Sperre.Bruecken.Most_k (Config/Map.playersOnlyFolders: it stops players only; throws, cameras and ground rays
--     look through). The railing is 3.5 high, its own boxes 4.4: without the wall a jump took a player over it into
--     the water (playtest 07.11.2026). Like the arena rim and the hub fence.
-- RESTORE = true removes Bruecke and its walls and puts Pomost back. Safe to repeat.

local BRIDGES = { 1 } -- { 1 } for the test bridge, "all" for all 12
local RESTORE = false

-- the flavour of each sector (assets/MapColors/studio_map_flavors.luau, main colour), as in studio_hub_decor.luau
local MAIN = {
	"#7FE0B8", -- 01 Mint
	"#FF6F12", -- 02 Mango
	"#6F7BEA", -- 03 Blaubeere
	"#FFE15A", -- 04 Zitrone
	"#BB9CF0", -- 05 Lavendel
	"#FF7480", -- 06 Erdbeere
	"#B4D46A", -- 07 Pistazie
	"#F06AAE", -- 08 Bubblegum
	"#C8792F", -- 09 Karamell (#E8B877 until 11.11.2026)
	"#75D6F2", -- 10 Himmelblau
	"#9A6244", -- 11 Schoko
	"#D7304E", -- 12 Kirsche
}
local END, MID, MIDS = 9, 12, 4 -- module lengths (build_hub_pack.py BRIDGE)
local RAIL_X, RAIL_THICK = 8.35, 1.8 -- the railings' collision boxes (build_hub_pack.py bridge_rail_collision)
local POST_IN = 3.75 - 0.9 -- from the end of the deck to the land side of the big post
local WALL_TOP = 40 -- as the arena's Sperre and the hub fence

local SS = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local map = workspace["Ice Cream Map"]
local kit = SS:FindFirstChild("HubKit")
assert(
	RESTORE or (kit and kit:FindFirstChild("BridgeEnd") and kit:FindFirstChild("BridgeMid")),
	"ServerStorage.HubKit.BridgeEnd / BridgeMid are missing: import HubKit_BridgeEnd.fbx and HubKit_BridgeMid.fbx, "
		.. "then run studio_hubkit_templates.luau"
)
local backup = SS:FindFirstChild("MapBackup_2026-11-07_Pomost")
if not backup then
	backup = Instance.new("Folder")
	backup.Name = "MapBackup_2026-11-07_Pomost"
	backup.Parent = SS
end

local list = {}
if BRIDGES == "all" then
	for k = 1, 12 do
		table.insert(list, k)
	end
else
	list = BRIDGES
end

local sperre = map:FindFirstChild("Sperre")
if not sperre then
	sperre = Instance.new("Folder")
	sperre.Name = "Sperre"
	sperre.Parent = map
end
local walls = sperre:FindFirstChild("Bruecken")
if not walls then
	walls = Instance.new("Folder")
	walls.Name = "Bruecken"
	walls.Parent = sperre
end

local recording = ChangeHistoryService:TryBeginRecording("Wobble bridges")
local report = {}
local parts = 0
for _, k in list do
	local id = string.format("%02d", k)
	local most = map.Mosty["Most_" .. id]
	local old = most:FindFirstChild("Bruecke")
	if old then
		old:Destroy()
	end
	local oldWalls = walls:FindFirstChild("Most_" .. id)
	if oldWalls then
		oldWalls:Destroy()
	end
	local saved = backup:FindFirstChild("Most_" .. id)
	if RESTORE then
		if saved then
			saved.Name = "Pomost"
			saved.Parent = most
		end
		table.insert(report, `Most_{id}: restored`)
		continue
	end
	local pomost = most:FindFirstChild("Pomost")
	if pomost and not saved then
		pomost.Name = "Most_" .. id
		pomost.Parent = backup
	elseif pomost then
		pomost:Destroy() -- a second copy; the backup already holds the original
	end

	local floor = most.Pomost_Kolizja
	local top = floor.Position.Y + floor.Size.Y / 2
	-- the long axis of the deck (Size.Z is 66), pointing away from the hub
	local out = floor.CFrame.LookVector
	if out:Dot(Vector3.new(floor.Position.X, 0, floor.Position.Z)) < 0 then
		out = -out
	end
	out = Vector3.new(out.X, 0, out.Z).Unit
	local start = Vector3.new(floor.Position.X, top, floor.Position.Z) - out * (floor.Size.Z / 2)

	local bridge = Instance.new("Model")
	bridge.Name = "Bruecke"
	local function piece(name, along, facing)
		local m = kit[name]:Clone()
		local at = start + out * along
		m:PivotTo(CFrame.lookAt(at, at + facing)) -- the module's front (-Z) looks along `facing`
		for _, d in m:GetDescendants() do
			if d:IsA("MeshPart") and d.Name:find("_Cap_", 1, true) then
				d.Color = Color3.fromHex(MAIN[k])
			end
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		m.Parent = bridge
	end
	piece("BridgeEnd", END / 2, -out) -- its land side towards the hub
	for i = 0, MIDS - 1 do
		piece("BridgeMid", END + MID * (i + 0.5), out)
	end
	piece("BridgeEnd", 2 * END + MIDS * MID - END / 2, out) -- its land side towards the island
	bridge.Parent = most

	local wallFolder = Instance.new("Folder")
	wallFolder.Name = "Most_" .. id
	local length = floor.Size.Z - 2 * POST_IN
	local h = WALL_TOP - top
	local side = out:Cross(Vector3.yAxis)
	for _, sx in { -1, 1 } do
		local at = start + out * (floor.Size.Z / 2) + side * (sx * RAIL_X) + Vector3.new(0, h / 2, 0)
		local p = Instance.new("Part")
		p.Name = "Sperre_Bruecke"
		p.Size = Vector3.new(RAIL_THICK, h, length)
		p.CFrame = CFrame.lookAt(at, at + out)
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = true
		p.CanQuery = true
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = wallFolder
	end
	wallFolder.Parent = walls
	table.insert(report, string.format("Most_%s: %d modules, deck top %.2f, 2 walls", id, #bridge:GetChildren(), top))
end
if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
return table.concat(report, "\n") .. `\n{parts} parts`
