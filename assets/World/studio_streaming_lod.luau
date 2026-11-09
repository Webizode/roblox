-- Studio command bar / MCP: the big map models show a coarse stand-in instead of vanishing when the client has streamed
-- them out (09.11.2026, released by the user). Safe to run again; RESTORE = true sets them back to Automatic.
--
-- LevelOfDetail = StreamingMesh on the 12 plot islands (Plots.Plot_k, 110 wide) and the 12 bridges (Mosty.Most_k):
-- the biggest Models, the ones furthest from most players. Folders (the hub ring, the arena) cannot carry it; they lie
-- in the middle, at most about 630 studs from any player, well inside StreamingTargetRadius 1024 (the map reaches
-- r 400, so it is about 800 across and from every point the whole map is inside the radius).

local RESTORE = false

local map = workspace["Ice Cream Map"]
local n = 0
for _, folder in { map.Plots, map.Mosty } do
	for _, model in folder:GetChildren() do
		if model:IsA("Model") then
			model.LevelOfDetail = if RESTORE
				then Enum.ModelLevelOfDetail.Automatic
				else Enum.ModelLevelOfDetail.StreamingMesh
			n += 1
		end
	end
end
return `{n} models: LevelOfDetail {if RESTORE then "Automatic" else "StreamingMesh"}, StreamingTargetRadius {workspace.StreamingTargetRadius}`
