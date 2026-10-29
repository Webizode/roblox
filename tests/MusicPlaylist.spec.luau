local harness = require("./harness")
local describe, it, expect = harness.describe, harness.it, harness.expect

local MusicPlaylist = require("../src/shared/MusicPlaylist")
local Config = require("../src/shared/Config/Settings")

describe("Music: the playlist", function()
	it("3 to 5 entries in the config; placeholders without an id are skipped", function()
		local tracks = Config.music.tracks
		expect(#tracks >= 3 and #tracks <= 5).toBe(true)
		local songs = MusicPlaylist.songs(Config)
		expect(#songs >= 1).toBe(true)
		for _, id in songs do
			expect(id ~= "").toBe(true)
		end
		local test = { music = { tracks = { "a", "", "b", "" } } }
		local list = MusicPlaylist.songs(test)
		expect(#list).toBe(2)
		expect(list[1]).toBe("a")
		expect(list[2]).toBe("b")
	end)

	it("never the same song twice in a row, and every one comes up", function()
		for _, count in { 2, 3, 5 } do
			local seen = {}
			local last = nil
			local roll = 0
			for _ = 1, 500 do
				roll = (roll + 0.6180339887) % 1
				local index = MusicPlaylist.next(count, last, roll) :: number
				expect(index >= 1 and index <= count).toBe(true)
				expect(index ~= last).toBe(true)
				seen[index] = true
				last = index
			end
			for index = 1, count do
				expect(seen[index]).toBe(true)
			end
		end
	end)

	it("a single song plays again after the pause; no songs: nothing", function()
		expect(MusicPlaylist.next(1, 1, 0.5)).toBe(1)
		expect(MusicPlaylist.next(0, nil, 0.5)).toBeNil()
	end)

	it("the quiet between two songs lies between pauseMin and pauseMax, about 60 to 120 s", function()
		expect(Config.music.pauseMin).toBe(60)
		expect(Config.music.pauseMax).toBe(120)
		expect(MusicPlaylist.pause(0, Config)).toBe(60)
		expect(MusicPlaylist.pause(0.5, Config)).toBe(90)
		expect(MusicPlaylist.pause(0.999, Config) <= 120).toBe(true)
	end)
end)
