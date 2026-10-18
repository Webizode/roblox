-- Plays the placeholder sounds from Config/Sounds. Catches climb a pentatonic scale so a growing tower sings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))

local Sfx = {}

local cache: { [string]: Sound } = {}

local function sound(name: string): Sound?
	local existing = cache[name]
	if existing then
		return existing
	end
	local id = Sounds[name]
	if type(id) ~= "string" then
		return nil
	end
	local instance = Instance.new("Sound")
	instance.Name = name
	instance.SoundId = id
	instance.Volume = 0.6
	instance.Parent = SoundService
	cache[name] = instance
	return instance
end

function Sfx.play(name: string, playbackSpeed: number?)
	local template = sound(name)
	if not template then
		return
	end
	-- PlayLocalSound would ignore PlaybackSpeed, so clone per play
	local instance = template:Clone()
	instance.PlaybackSpeed = playbackSpeed or 1
	instance.Parent = SoundService
	instance.Ended:Once(function()
		instance:Destroy()
	end)
	instance:Play()
	task.delay(5, function()
		if instance.Parent then
			instance:Destroy()
		end
	end)
end

-- The nth catch of a tower, one pentatonic step higher each time.
function Sfx.catch(count: number)
	local steps = Sounds.pentatonic
	local index = math.max(count - 1, 0)
	local semitones = 12 * (index // #steps) + steps[index % #steps + 1]
	semitones = math.min(semitones, Sounds.maxSemitones)
	Sfx.play("catch", Sounds.basePlaybackSpeed * 2 ^ (semitones / 12))
end

return Sfx
