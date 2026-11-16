--!strict
-- Light and colour packages (since 16.11.2026), to compare before anything is changed for good. Only light, colour
-- correction, sky haze, grass and water; no model is recoloured. `preset` picks the one every client shows
-- (LookController applies it on the client at the start, so the place itself keeps "Soft"). In Studio the Workspace
-- attribute LookPreset ("Soft" or "Vivid") switches it live during a playtest.
--
-- Soft: the place's own values since the map check of 11.11.2026 (docs/look.md, Vault "Map Check 2026-11-11"): warm,
-- a little haze, low saturation. Vivid: in the direction of the reference of 16.11.2026: saturated, bright and clear,
-- no haze, strong contrast, an even bright ambient without dark corners and crisp shadows.
-- Colours as hex; grass is the hub lawn (Dekoracje.Hub.Sektor_*.Rasen), the plot ground (Plots.Plot_*.Powierzchnia)
-- and the terrain grass under the lawn; water is the terrain water and the client sea (Ocean).

return {
	preset = "Soft",

	presets = {
		Soft = {
			lighting = {
				Brightness = 2,
				ExposureCompensation = -0.15,
				Ambient = "#736964", -- 115, 105, 100
				OutdoorAmbient = "#878491", -- 135, 132, 145
				ColorShift_Top = "#FFF2DC",
				EnvironmentDiffuseScale = 1,
				EnvironmentSpecularScale = 0.3,
				ShadowSoftness = 0.25,
			},
			colorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = 0.08, TintColor = "#FFF6EC" },
			atmosphere = {
				Density = 0.18,
				Offset = 0.1,
				Haze = 1.4,
				Glare = 0.25,
				Color = "#D7EBFF",
				Decay = "#96C8FF",
			},
			bloom = { Intensity = 0.25, Size = 24, Threshold = 2 },
			sunRays = { Intensity = 0.01, Spread = 0.1 },
			grass = "#6FA046",
			water = { color = "#0069B9", transparency = 0.3 },
			ocean = "#1E7FC2", -- the client sea (Config/Map.ocean.colour)
		},

		Vivid = {
			lighting = {
				Brightness = 3,
				ExposureCompensation = 0.1,
				Ambient = "#8C8C8C", -- bright and neutral: no dark corners
				OutdoorAmbient = "#A5A5AA",
				ColorShift_Top = "#FFFAF0",
				EnvironmentDiffuseScale = 1,
				EnvironmentSpecularScale = 0.2,
				ShadowSoftness = 0.08, -- crisp
			},
			colorCorrection = { Brightness = 0.02, Contrast = 0.22, Saturation = 0.32, TintColor = "#FFFFFF" },
			-- almost no haze: only a thin fade at the horizon, so the sea's far edge does not show
			atmosphere = {
				Density = 0.06,
				Offset = 0,
				Haze = 0,
				Glare = 0,
				Color = "#C6E4FF",
				Decay = "#6AB4FF",
			},
			bloom = { Intensity = 0.15, Size = 24, Threshold = 2.4 },
			sunRays = { Intensity = 0, Spread = 0.1 },
			grass = "#4CC22A",
			water = { color = "#0080E8", transparency = 0.25 },
			ocean = "#1A8CF0",
		},
	},
}
