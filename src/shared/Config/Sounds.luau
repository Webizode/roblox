--!strict
-- Placeholder sounds from the built-in Studio content folder. Week 4 replaces them with our own recordings
-- (waffle crunch, spoon plop, sprinkles in a jar, creaking drawer for the groan). rbxasset://sounds/swoosh.wav is
-- no longer usable (Roblox maps it to the private audio 911864050), so the whoosh comes from a free Creator Store audio.

return {
	catch = "rbxasset://sounds/electronicpingshort.wav",
	serve = "rbxasset://sounds/button.wav",
	groan = "rbxasset://sounds/snap.wav",
	topple = "rbxasset://sounds/splat.wav",
	saved = "rbxassetid://127438224839678", -- "zapsplat cartoon whoosh whip away", 0.33 s
	dash = "rbxassetid://127438224839678",
	throw = "rbxassetid://127438224839678",
	hit = "rbxasset://sounds/snap.wav",
	-- what the thrower hears when their ball hits (since the kill test of 13.11.2026; before only a headshot had a
	-- sound): a creamy squish for every hit, the sparkle on top for a perfect throw, the headshot keeps its bell.
	-- Free Creator Store placeholders: "SLIME SQUISHY 1" (0.48 s), ProSoundEffects "Synth Sparkle Tone High Pitch Bell
	-- Tone Ding" (1.16 s)
	hitConfirm = "rbxassetid://87295773843957",
	perfectHit = "rbxassetid://9126073001",
	-- free Creator Store placeholders: "bell hitsound" (1.7 s), "charge up" (0.97 s), ProSoundEffects "Magic Twirling
	-- Small High Pitch Spinning Chime" (2.1 s)
	headshot = "rbxassetid://124010691633262", -- the thrower hears it on their headshot
	chargeUp = "rbxassetid://139493189032178", -- at the charging hand, for players nearby
	perfectReady = "rbxassetid://9125644410", -- at the hand each time letting go would be perfect
	-- the Scoop Chest (placeholders): the magic chime when it opens, a soft thud when it shuts, a ding when rare
	-- scoops go into it or a catch turns lucky
	chestOpen = "rbxassetid://9125644410",
	chestClose = "rbxasset://sounds/button.wav",
	chestStored = "rbxassetid://9126073001",
	-- a gummy pad throws a player up (Config/Bounce): free Creator Store placeholder "Pogo Stick Boing Sound City Break"
	bounce = "rbxassetid://137750395861529",

	-- every catch climbs one step of a pentatonic scale so a growing tower "sings"
	pentatonic = { 0, 2, 4, 7, 9 },
	maxSemitones = 24,
	basePlaybackSpeed = 0.8,
}
