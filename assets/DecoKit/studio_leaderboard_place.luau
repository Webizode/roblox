--!nocheck
-- Studio command bar / MCP: the leaderboard signs (10.11.2026). Every pink placeholder Platzhalter_Leaderboard in
-- Dekoracje.Hub.Platzhalter becomes the deco kit's Leaderboard (ServerStorage.DecoKit.Leaderboard) at its spot, its
-- front where the placeholder's front was, standing on the placeholder's ground. The signs go to
-- Dekoracje.Hub.Leaderboards; LeaderboardService finds them by name (Config/Leaderboard.modelName) and draws the top
-- list on their Display. The placeholders move to ServerStorage."MapBackup_2026-11-10_LeaderboardPlatzhalter".
-- Safe to run again (it rebuilds the signs from the backup). RESTORE = true puts the placeholders back.

local RESTORE = false

local SS = game:GetService("ServerStorage")
local hub = workspace["Ice Cream Map"].Dekoracje.Hub
local holder = hub:FindFirstChild("Platzhalter")
local backupName = "MapBackup_2026-11-10_LeaderboardPlatzhalter"
local backup = SS:FindFirstChild(backupName)
if not backup then
	backup = Instance.new("Folder")
	backup.Name = backupName
	backup.Parent = SS
end
for _, p in holder and holder:GetChildren() or {} do
	if p.Name == "Platzhalter_Leaderboard" then
		p.Parent = backup
	end
end
local folder = hub:FindFirstChild("Leaderboards")
if folder then
	folder:Destroy()
end
if RESTORE then
	for _, p in backup:GetChildren() do
		p.Parent = holder
	end
	return "placeholders back"
end
folder = Instance.new("Folder")
folder.Name = "Leaderboards"
folder.Parent = hub
local made = {}
for i, p in backup:GetChildren() do
	local sign = SS.DecoKit.Leaderboard:Clone()
	sign.Name = "Leaderboard"
	local ground = p.Position.Y - p.Size.Y / 2
	-- the template's front is its -Z (LookVector), as the placeholder part's
	sign:PivotTo(CFrame.new(p.Position.X, ground, p.Position.Z) * p.CFrame.Rotation)
	sign.Parent = folder
	table.insert(made, string.format("%d at (%.0f, %.0f)", i, p.Position.X, p.Position.Z))
end
return #made .. " signs: " .. table.concat(made, ", ")
