--!strict
-- Saving (DataService with ProfileStore). The data format and its versions live in SaveData.

return {
	storeName = "PlayerData",
	-- Studio saves into its own store, so playtests never touch live players' saves
	studioSuffix = "_Studio",
	keyPrefix = "Player_",

	-- may reset their own save with the chat command below; only works in Studio
	admins = {
		1521940809, -- Oliwier (OlekGamer03)
		5091937796, -- Nik (FALCONEYSEE)
	},
	resetCommand = "/resetsave",

	-- shown when the save cannot be loaded; the player is kicked and nothing is written
	loadFailedMessage = "Your save could not be loaded. Please rejoin. Nothing was lost.",
	-- shown when another server took over the save (a quick server switch)
	sessionEndedMessage = "Your save was opened on another server. Please rejoin.",
}
