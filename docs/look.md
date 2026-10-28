# Look: Cartoon-Durchgang (26.10.2026)

Licht, Farbe, Himmel, Wasser und Materialien für einen hellen Cartoon-Look (Richtung Fall Guys, Splatoon, Brawl Stars). Die Map selbst ist nicht umgebaut. Alles liegt im Place, nicht in Rojo.

## Werte

| | Vorher | Nachher |
|---|---|---|
| Tageszeit (`ClockTime`) | 14,5 | 13,5 |
| `Brightness` | 3 | 2,2 |
| `Ambient` / `OutdoorAmbient` | (70, 70, 70) / (70, 70, 70) | (115, 105, 100) / (150, 140, 130) |
| `ColorShift_Top` | schwarz | (255, 242, 220) |
| `ShadowSoftness` | 0,2 | 0,5 |
| `EnvironmentSpecularScale` | 1 | 0,3 |
| ColorCorrection `CartoonColor` | – | neu: Sättigung 0,22, Kontrast 0,15, Tönung (255, 248, 238) |
| Bloom | Intensity 1, Size 24, Threshold 2 | Intensity 0,25, Size 24, Threshold 2 |
| Atmosphere | Density 0,3, Offset 0,25, grau | Density 0,1, Offset 0, Color (215, 235, 255), Decay (150, 200, 255), Haze 0,15 |
| Sky | realistisch (`6444884337` u. a.) | „Cartoon Sky“ von xor25th (Creator Store 10594688909): `6295671271` Bk, `6295671382` Dn, `6295671136` Ft, `6295670996` Lf, `6295671509` Rt, `6295671667` Up |
| Wasser | #0F96FF, Transparency 0,45, Reflectance 0,25, Wellen 0,15 / 8 | (0, 105, 185), 0,3, 0, Wellen 0,2 / 12 |
| SunRays, DepthOfField | unverändert (SunRays an, DoF aus) | unverändert |

Das Wasser wirkt viel türkiser als sein Farbwert, weil der Himmel unten hell-türkis ist und die Farbkorrektur sättigt. Deshalb der dunkle Blauton.

## Materialien

Auf SmoothPlastic umgestellt: Wood 234, Marble 100, WoodPlanks 25, Cobblestone 9, Plastic 6, Sand 3 Teile. Die Brücken (`Mosty`, Wood und WoodPlanks) bleiben bei ihrer Textur: Ohne sie werden sie zu flachen Platten, die Dielen kommen nur aus der Textur. Jedes umgestellte Teil trägt das Attribut `LookOriginalMaterial` mit seinem alten Material.

## Leistung auf Handys

Keine neuen Lichter, Partikel oder Meshes. ColorCorrection und schwacher Bloom sind sehr billig, die dünnere Atmosphere und das Wasser ohne Spiegelung eher günstiger als vorher. SmoothPlastic statt Texturen spart Speicher.

## Rückgängig machen

Direkt nach dem Durchgang: Strg+Z in Studio (ein Schritt in der Historie).

Später: `ServerStorage.LookBackup` hält alle alten Werte als Attribute. Dieses Skript in die Studio-Befehlsleiste einfügen:

```lua
local backup = game.ServerStorage.LookBackup
local L = game.Lighting
local targets = {
	Lighting = L,
	Sky = L:FindFirstChildOfClass("Sky"),
	Atmosphere = L:FindFirstChildOfClass("Atmosphere"),
	Bloom = L:FindFirstChildOfClass("BloomEffect"),
	Water = workspace.Terrain,
}
for key, value in backup:GetAttributes() do
	local prefix, prop = string.match(key, "^(%a+)_(.+)$")
	if prefix and targets[prefix] then
		targets[prefix][prop] = value
	end
end
local cc = L:FindFirstChild("CartoonColor")
if cc then
	cc:Destroy()
end
for _, part in workspace["Ice Cream Map"]:GetDescendants() do
	local original = part:GetAttribute("LookOriginalMaterial")
	if original then
		part.Material = Enum.Material[original]
		part:SetAttribute("LookOriginalMaterial", nil)
	end
end
```
