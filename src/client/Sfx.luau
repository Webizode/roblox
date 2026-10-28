-- Plays the placeholder sounds from Config/Sounds. Catches climb a pentatonic scale so a growing tower sings.
-- Every sound of the game runs through one of two sound groups, so the settings set effects and music apart; the
-- background music (Config/Settings.music) loops in the music group.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Sounds = require(Config:WaitForChild("Sounds"))
local SettingsConfig = require(Config:WaitForChild("Settings"))

local Settings = require(script.Parent:WaitForChild("Settings"))

local Sfx = {}

local cache: { [string]: Sound } = {}

local function group(name: string): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local created = Instance.new("SoundGroup")
	created.Name = name
	created.Parent = SoundService
	return created
end

local effects = group("WobbleEffects")
local musicGroup = group("WobbleMusic")

local music = Instance.new("Sound")
music.Name = "BackgroundMusic"
music.SoundId = SettingsConfig.music.id
music.Volume = SettingsConfig.music.volume
music.Looped = true
music.SoundGroup = musicGroup
music.Parent = SoundService

Settings.onChanged(function(settings)
	effects.Volume = settings.sfxVolume
	musicGroup.Volume = settings.musicVolume
	if settings.musicVolume > 0 and not music.IsPlaying then
		music:Play()
	elseif settings.musicVolume <= 0 and music.IsPlaying then
		music:Stop()
	end
end)

-- The group for any other effect sound of the game (the dash model's sounds), so the effects volume covers it.
function Sfx.effectsGroup(): SoundGroup
	return effects
end

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
	instance.SoundGroup = effects
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
