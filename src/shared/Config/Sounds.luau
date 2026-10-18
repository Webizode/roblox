--!strict
-- Placeholder sounds from the built-in Studio content folder. Week 4 replaces them with our own recordings
-- (waffle crunch, spoon plop, sprinkles in a jar, creaking drawer for the groan).

return {
	catch = "rbxasset://sounds/electronicpingshort.wav",
	serve = "rbxasset://sounds/button.wav",
	groan = "rbxasset://sounds/snap.wav",
	topple = "rbxasset://sounds/splat.wav",
	saved = "rbxasset://sounds/swoosh.wav",

	-- every catch climbs one step of a pentatonic scale so a growing tower "sings"
	pentatonic = { 0, 2, 4, 7, 9 },
	maxSemitones = 24,
	basePlaybackSpeed = 0.8,
}
