--!strict
-- The background music's playlist (Config/Settings music): which song comes next and how long the quiet between two
-- songs lasts. Pure: the config and the random numbers are passed in, so Sfx plays it and the Lune tests check it.

local MusicPlaylist = {}

-- The songs that can play: the playlist without its placeholders (empty ids), in order.
function MusicPlaylist.songs(config: any): { string }
	local songs = {}
	for _, id in config.music.tracks do
		if type(id) == "string" and id ~= "" then
			table.insert(songs, id)
		end
	end
	return songs
end

-- The index of the next song out of `count`, never `last` again when there is any other; `roll` is a random number
-- in [0, 1). nil without songs.
function MusicPlaylist.next(count: number, last: number?, roll: number): number?
	if count <= 0 then
		return nil
	end
	if count == 1 or not last then
		return math.clamp(1 + math.floor(roll * count), 1, count)
	end
	-- one of the others, all equally likely
	local pick = math.clamp(1 + math.floor(roll * (count - 1)), 1, count - 1)
	return if pick >= last then pick + 1 else pick
end

-- Seconds of quiet after a song: between pauseMin and pauseMax; `roll` is a random number in [0, 1).
function MusicPlaylist.pause(roll: number, config: any): number
	local m = config.music
	return m.pauseMin + (m.pauseMax - m.pauseMin) * math.clamp(roll, 0, 1)
end

return MusicPlaylist
