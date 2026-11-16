-- Shows the light and colour package of Config/Look (preset) on this client (LookApply), also on grass that streams in
-- later. In Studio the Workspace attribute LookPreset ("Soft" or "Vivid") switches it live during a playtest, for
-- comparing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local client = script.Parent.Parent
local LookApply = require(client:WaitForChild("LookApply"))
local LookConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Look"))

local LookController = {}

local ATTRIBUTE = "LookPreset"

local function current(): string
	local chosen = RunService:IsStudio() and workspace:GetAttribute(ATTRIBUTE)
	if type(chosen) == "string" and LookApply.has(chosen) then
		return chosen
	end
	return LookConfig.preset
end

function LookController.Start()
	LookApply.apply(current())
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
			LookApply.apply(current())
		end)
	end
	local map = workspace:WaitForChild(LookApply.MAP)
	map.DescendantAdded:Connect(function(part)
		if LookApply.isGrass(part) then
			LookApply.paintGrass(part :: BasePart, current())
		end
	end)
end

return LookController
