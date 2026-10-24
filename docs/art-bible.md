# Art Bible Wobble Scoops

Stand: 24.10.2026. Verbindlich sind `docs/design-regeln.md` und die Entscheidungen in `docs/projektstand.md`; bei Widersprüchen gelten sie vor diesem Dokument und vor `docs/concept.md`. Die Art Direction aus `docs/concept.md` ("Art Direction und Anti-Slop") gilt weiter für Welt und Turm-Kugeln: Spielzeug-Pier zur goldenen Stunde, runde und klobige Formen (ca. 1,3-fach überzeichnet), SmoothPlastic ohne Texturen, Palette aus `src/shared/Config/Palette.luau`, Sorten unterscheiden sich auch über Silhouette und Material. Ausnahme sind die Attack-Scoops (siehe unten). Dieses Dokument hält die Entscheidungen zu einzelnen Assets fest.

## Zwei Kugel-Arten

| | Turm-Kugeln | Attack-Scoops |
|---|---|---|
| Rolle | werden gefangen und gestapelt, Beute und Wert | in der Hand, werden geworfen, nicht gestapelt |
| Gesicht | **keins**, keine Emotionen | großes, austauschbares Gesicht mit Emotionen |
| Stil | Art Direction aus `concept.md`, SmoothPlastic | glänzender Premium-Cartoon, PBR mit `SurfaceAppearance` |

## Attack-Scoops: Stil (Stand 24.10.2026)

Stilreferenz ist allein das ChatGPT-Konzeptbild "Wobble Scoops Character Design" (Higgsfield-Versionen verworfen), Richtung Pixar, Slime Rancher 2, Brawl Stars. Vorgaben im Detail: `docs/projektstand.md`, Abschnitt "Modell: Attack-Scoop".

- Glänzender Premium-Cartoon: cremig, saftige Glanzlichter, satte Farben, viel Persönlichkeit. Nicht matt und nicht schlicht.
- Große glänzende Augen mit Glanzpunkt, ausdrucksstarker Mund, rosa Wangen. Ausdrücke übertrieben genug, dass man sie auf ca. 20 Studs und im Flug liest.
- Material: PBR-Texturen (Color, Roughness, Normal) über `SurfaceAppearance` auf einem MeshPart statt SmoothPlastic.
- Gesicht austauschbar (Augen und Mund getrennt, nicht ins Modell eingebacken), damit das Emotionssystem aus `design-regeln.md` funktioniert: Freude, Jubel, Wut, Angst, Überraschung, Splat.
- Sitzt in einer kleinen Waffel-Schale, die beim Wurf mitfliegt.

Die Regel aus `concept.md`, übertriebene Gesichter (Glanzlichter, Wangen) seien ein Slop-Merkmal, gilt für Attack-Scoops nicht mehr. Für KI-Bilder in Thumbnails, Icon und Spielseite gilt sie weiter (siehe "KI-Bilder").

## Attack-Scoop-Modell: externer Modeler (Stand 24.10.2026)

Das finale Attack-Scoop-Modell, Vanille mit kleiner Waffel, die mitfliegt, und 6 austauschbaren Gesichtern, kommt von einem externen Modeler und ist angefragt. Lieferumfang und technische Vorgaben: `docs/projektstand.md`, Abschnitt "Modell: Attack-Scoop".

Bis zur Lieferung bleibt die aktuelle Wurfkugel im Spiel unverändert: `BallVisual` zeichnet das Template `WSB_ThrowBall_Vanilla` aus ReplicatedStorage (Export des Blender-Prototyps `WSB_ThrowBall`, siehe unten), ohne Template die schlichte Eiskugel. Der Wechsel auf das neue Modell ist eine eigene Aufgabe nach der Lieferung (Template tauschen, Gesichter an das Emotionssystem anschließen, Waffel im Flug).

## Turm-Kugeln (Stand 24.10.2026)

Turm-Kugeln haben **kein Gesicht**. Die Entscheidung vom 23.10.2026 für den "Scoop-Buddy" (Konzept B, Turm-Kugel mit Ink-Gesicht) ist aufgehoben. Gültig bleibt die Form aus Konzept A und ihre Verfeinerung: Tropfrand bzw. runde Lappen, ohne Gesicht.

Ursprüngliche Auswahl vom 23.10.2026, zur Nachvollziehbarkeit:

| Konzept | Kern | Ergebnis |
|---|---|---|
| **A Tropfkrone** | Kugel mit dickem, welligem Tropfrand, kein Gesicht | **gültige Form** |
| B Scoop-Buddy | Form von A plus sparsames Ink-Gesicht, Ausdruck folgt dem Turm | am 23.10. gewählt, am 24.10. aufgehoben (Turm-Kugeln ohne Gesicht) |
| C Schöpfrolle | asymmetrische Kugel mit gerollter Lippe | verworfen: Asymmetrie stört das Lesen der Neigung, aufwendiger |

Bewertung:

| Kriterium | A | B | C |
|---|---|---|---|
| Silhouette | gut (Tropfrand) | gut (identisch zu A) | sehr eigenständig |
| Wiedererkennung | mittel | hoch (Gesicht, Ausdruck) | hoch |
| Lesbarkeit im Spiel (2 Studs, 15-30 Studs Abstand) | sehr gut | sehr gut, Gesicht nur aus der Nähe | Neigung schwerer lesbar |
| Animierbarkeit | Squash und Stretch | dazu Ausdruckswechsel | eingeschränkt |
| Umsetzung in Roblox | 1 MeshPart | 1 MeshPart plus Decal | 1 MeshPart, schwerer sauber |

Die Idee "der Turm schreit beim Kippen" (20 Kugeln schauen gleichzeitig panisch) ist als spätere Option unter "Offen" festgehalten.

### Form

- Leicht gestauchte Kugel (Höhe ca. 0,92 der Breite), Radius im Spiel 1 Stud, Stapelradius 1,05 (siehe `Config/Launcher.luau`, `Backpack.luau`).
- Ein wulstiger Rand im unteren Drittel, darunter **7 Tropfen unterschiedlicher Länge**. Der Rand ist das Markenzeichen der Silhouette und muss ohne Farbe erkennbar sein.
- Unterhalb des Rands ist die Kugel eingezogen, damit sie in der Waffel und auf der Kugel darunter sitzt, ohne zu schweben.
- Keine Kleinteile unter ca. 0,15 Stud, sie verschwinden auf dem Handy.

### Material und Farbe

- Grundmaterial SmoothPlastic, in Blender als Principled BSDF mit Roughness ca. 0,45 vorbereitet. Farbe pro Sorte aus der Palette, keine Textur.
- Sorten-Unterschiede über Form und Material nach `concept.md` (Rocky Road klumpig, Mochi flach, Jelly aus Glass usw.). Der Prototyp ist Vanilla `#FFF3D6`.

### Prototyp (Stand 23.10.2026)

In `Documents\Modelle Wooble Scoops.blend`, Collection `WobbleScoops_Prototype`. Prototyp, kein finales Asset:

- `WS_SignatureScoop`: Empty bei (-4, 0, 0), Wurzel des Prototyps.
- `WS_Scoop_Body`: Kugel, Randwulst, Saum, 7 Tropfen und 5 Mini-Tropfen, verschmolzen über die Modifier Remesh (Voxel 0,04), Corrective Smooth und Decimate (0,055). Ergebnis ca. 1.530 Dreiecke, geschlossen (manifold), Maße 2,38 × 2,38 × 1,89. Modifier sind nicht angewendet.
- `WS_Scoop_Face`: Augen, Braue und Mund als Ink-Mesh, Ausdruck "ruhig". Seit dem 24.10.2026 hinfällig (Turm-Kugeln ohne Gesicht), nicht exportieren.
- `WS_Preview_Key`, `WS_Preview_Fill`, `WS_Preview_Rim`: Vorschau-Lichter, nicht für den Export.
- Materialien `WS_Vanilla`, `WS_Ink`.

Geprüft: Mit dem Spiel-Abstand von 1,5 Studs zwischen den Kugeln (`Config/Tower.luau`, `scoopSpacing`) legt sich der Saum über die Kugel darunter. Aus ca. 22 Studs ist der Turm als Eis lesbar.

### Verfeinerung für Wobble und Hüpfen (Stand 23.10.2026)

Prototyp, kein finales Asset. Bewegung über Wobble und Hüpfen, keine Beine.

Collection `ScoopBuddy_Refinement`, das Original `WS_SignatureScoop` bleibt als Vergleich unverändert:

- `SB_Refined_Root`: Empty bei (-1,2, 0, -0,1), Standfläche auf dem Präsentationsboden.
- `SB_Refined_Body`: eine einzige Quad-Oberfläche statt Voxel-Remesh. 49 Segmente × 21 Ringe, 2.058 Dreiecke, geschlossen, Normalen außen, keine Selbstüberschneidung, keine Modifier.
- `SB_Refined_Face`: Kopie des Gesichts mit eigenen Mesh-Daten. Hinfällig wie `WS_Scoop_Face`.

Form:

- Kuppel exakt wie im Original (Ellipsoid 1,0 / 0,92).
- Statt 7 unregelmäßiger Tropfen und 5 Mini-Tropfen jetzt **7 breite, runde Lappen** (Halbellipsen), Kante an Kante, links-rechts symmetrisch. Ein Lappen sitzt vorne mittig, damit vorne nie zwei Lappen wie Beine stehen. Rhythmus vorne lang, schräg vorne kurz, Seite lang, hinten mittel.
- Die Lappen enden auf Höhe einer flachen Standfläche, nicht darunter. Unter den Kerben ist der Sockel zurückgezogen und bildet eine weiche Schattenkerbe.
- Stauch- und Streck-Test (1,2/1,2/0,7 und 0,86/0,86/1,3): Die Form bleibt lesbar, und keine Falte bricht ein.

Vertex-Gruppen für das spätere Rig: `SB_Dome`, `SB_Rim`, `SB_Drips`, `SB_Base` (Bereiche) und `SB_Lobe_Front`, `SB_Lobe_FrontSide.L/.R`, `SB_Lobe_Side.L/.R`, `SB_Lobe_Back.L/.R` (Gewicht nimmt zum Lappenende zu, für Nachwackeln). .L ist +X, die linke Seite der Figur, die nach -Y schaut.

## Wurfkugel-Prototyp (Stand 23.10.2026)

**Prototyp**, wird durch das Attack-Scoop-Modell des externen Modelers ersetzt (siehe oben). Bis dahin ist er die Wurfkugel im Spiel.

Die Wurfkugel ist **keine Spielfigur** und wird **nicht gestapelt**. Der Spieler ist ein normaler R15-Character, hält die Kugel in der rechten Hand und wirft sie im Kampfmodus. Größe aus dem Code: `Config/Combat.luau`, `ballRadius = 0.6`. Kampfkamera 10,5 Studs hinter dem Spieler. Im Spiel zeichnet `BallVisual` den Export als Template `WSB_ThrowBall_Vanilla` (`Config/Combat.luau`, `ballModel`), die drei Bewegungen kommen aus den Blender-Actions (`BallMotion`).

Collection `ScoopBall_Throwable` (abgeleitet aus `SB_Refined_Body`, Original und Verfeinerung bleiben unverändert):

- `WSB_ThrowBall`: Empty, Ursprung = Kugelzentrum (Greif- und Drehpunkt).
- `WSB_Ball_Body`: 1,30 × 1,30 × 1,14 Studs, Kern exakt Radius 0,6 (Kollisionsradius), 1.932 Dreiecke, eine geschlossene Quad-Oberfläche, Normalen außen, keine Modifier, Skalierung 1. Material `WSB_Vanilla`.
- `WSB_Ball_Face`: eigenes Objekt mit demselben Ursprung, 4 geschlossene Teile (2 Augen, Braue, Mund), 888 Dreiecke. Material `WSB_Ink`.
- `WSB_QC_Key/Fill/Rim/Bounce`: Kontrolllichter für die Abnahme, nicht für den Export.

Form: rund aus jeder Richtung, weil die Kugel im Flug rotiert. Weicher Randwulst, darunter 7 kurze, runde Tropfen, die über die Kugelkontur hinausragen und weich ineinander übergehen. Unterseite rund, keine Standfläche. Leicht handgeformt: Rand minimal schräg, Tropfen nicht exakt gleich lang, sanfte Dellen in der Kuppel, um das Gesicht herum ausgeblendet.

Gesicht: größere, leicht ovale Augen, eine kräftige, hochgezogene Braue (selbstbewusst), Grinsen mit hochgezogenem rechtem Mundwinkel (frech). Aus 10,5 Studs lesbar. Es entspricht noch dem alten, sparsamen Ink-Stil, nicht dem neuen Attack-Scoop-Stil.

Materialien: `WSB_Vanilla` `#FFE7C0`, Roughness 0,42; `WSB_Ink` `#2B2D42`, Roughness 0,26. Das wärmere Creme weicht vom Palette-Token `vanilla` `#FFF3D6` ab, der im Licht fast weiß wirkt. Ob der Token angepasst wird, ist offen.

Für den Prototyp gilt: Eine Kollisionskugel mit Radius 0,6 bleibt die Trefferform, das Mesh ist nur Optik. Das gilt auch für das finale Modell.

## Blender-Konventionen

- Arbeit in der Collection `WobbleScoops_Prototype`, Objekte mit Präfix `WS_`, Materialien mit Präfix `WS_`.
- 1 Blender-Einheit = 1 Stud. Die Import-Skalierung (FBX nach Roblox) beim ersten Export prüfen und hier festhalten.
- Ursprung jeder Kugel im Kugelmittelpunkt, wie im Spiel (`TowerVisual`).
- Modifier so lange wie möglich nicht anwenden, damit die Form editierbar bleibt.
- Polybudget pro Turm-Kugel: ca. 1.500 Dreiecke, da bis zu 40 pro Turm und 10 Türme pro Server. Die verfeinerte Wobble-Form liegt bei ca. 2.060, weil runde Lappen und eine weiche Randfalte mehr Ringe brauchen. Für Türme ist eine LOD-Stufe mit ca. 800 Dreiecken nötig (gleiche Segmentzahl halbieren).

## KI-Bilder

`concept.md` schließt KI-Bilder aus. Ausnahmen, vom Nutzer freigegeben: KI-Bilder **nur als interne Referenz** in der Konzeptphase (Higgsfield am 23.10.2026; seit dem 24.10.2026 ist das ChatGPT-Konzeptbild "Wobble Scoops Character Design" die einzige Stilreferenz, die Higgsfield-Versionen sind verworfen). Sie erscheinen nie im Spiel, in Thumbnails, im Icon oder auf der Spielseite.

## Offen

- Attack-Scoop-Modell vom externen Modeler: Lieferung abwarten, dann abnehmen und einbinden.
- Spätere Option "der Turm schreit beim Kippen": Turm-Kugeln bekommen nur in diesem Moment ein kurzes Panik-Gesicht oder einen anderen Panik-Effekt (Clip-Moment). Widerspricht derzeit "Turm-Kugeln ohne Gesicht" und braucht deshalb eine eigene Entscheidung.
- Import-Skalierung und Export-Einstellungen der Turm-Kugel nach Roblox.
- Varianten der Turm-Kugel für die übrigen Sorten erst nach Abnahme der Vanilla-Form.
- Für den Export der Turm-Kugel: Modifier anwenden (auf einer Kopie), Gesicht weglassen.
- Ob der Palette-Token `vanilla` an das wärmere Creme angepasst wird.
