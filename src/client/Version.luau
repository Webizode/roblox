--!strict
-- Which build this is: the commit and date of the code (Shared.Build, written by `lune run scripts/stamp`, gitignored;
-- missing in a fresh clone that never ran it) and the place version the server runs (the server's Workspace attribute
-- PlaceVersion, set at its start: the published version a live server was started with). Shown small at the bottom of
-- the settings and on the touch debug overlay, to see on a phone whether the newest publish arrived.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Version = {}

type Build = { commit: string, date: string, dirty: boolean }

local function build(): Build?
	local module = ReplicatedStorage:WaitForChild("Shared"):FindFirstChild("Build")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, value = pcall(require, module)
	if ok and type(value) == "table" and type(value.commit) == "string" then
		return value :: any
	end
	return nil
end

-- "Build 39036f1 · 2026-11-26 15:58 · Place v628"; a "+" after the commit: changes on top of it that were not
-- committed when the stamp was written; "Studio" instead of the place version in a Studio playtest.
function Version.text(): string
	local stamp = build()
	local code = if stamp
		then `Build {stamp.commit}{if stamp.dirty then "+" else ""} · {stamp.date}`
		else "Build unknown (no stamp)"
	local place = workspace:GetAttribute("PlaceVersion")
	local where = if RunService:IsStudio()
		then "Studio"
		elseif type(place) == "number" then `Place v{place}`
		else "Place v?"
	return `{code} · {where}`
end

-- Calls `listener()` once the server's place version is known (it can arrive after the client starts).
function Version.onChanged(listener: () -> ())
	workspace:GetAttributeChangedSignal("PlaceVersion"):Connect(listener)
end

return Version
