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

- Grundmaterial SmoothPlastic, Farbe pro Sorte aus der Palette (`Config/Flavors`), gesetzt als Farbe des MeshParts.
- Seit dem 29.10.2026 (vom Nutzer freigegeben) darf jede Sorte ein kleines **Detailbild** tragen, z. B. die Vanille-Punkte: eine `SurfaceAppearance` im Overlay-Modus. Das Bild ist bis auf die Details durchsichtig, darunter zeigt sich die Sortenfarbe. Bei ca. 450 Dreiecken gehen solche Details nicht als Geometrie.
- Sorten-Unterschiede über Form und Material nach `concept.md` (seltenere Sorten bekommen eigene Formen und Materialien). Die erste Sorte ist Vanilla `#F9DCA8` (seit 29.10.2026, vom Nutzer freigegeben): Der Palette-Token `vanilla` `#FFF3D6` wirkt im Licht der Insel fast weiß mit Minzstich, im Spiel verglichen mit `#FFE7C0` und `#F9DCA8`. Der Token selbst bleibt, er ist der fast weiße Ton der Eis-Effekte (Frost, Dash, Eiswölkchen).

### Turm-Kugel-Modell (Stand 29.10.2026)

Gebaut per Skript: `assets/TowerScoops/build_scoops.py` (Blender, alles parametrisch), Vorschau `preview_scoops.py` (nah, aus 30 Studs, Turm mit 10 Kugeln, Bilder in `assets/TowerScoops/renders`), Export `export_scoops.py`, Einrichtung in Studio `studio_setup.luau`. Arbeitsdatei `assets/TowerScoops/TowerScoops.blend`. Referenz: das Vanilla-Scoop-Bild des Nutzers (Kuppel, Tropfrand, hohle Unterseite).

- **Grundform für alle Sorten:** runde Kuppel (Kugel mit Radius 0,92 bis 1,0 Stud über dem Mittelpunkt), Einschnürung, Wulst mit 7 runden Lappen (einer vorne mittig, links und rechts symmetrisch, Tropfenlänge vorne lang, schräg vorne kurz, Seite lang, hinten mittel), hohle Unterseite. Eine Sorte ist ein Eintrag in `FLAVORS` (Farbe, Lappen, Kuppel, Glanz) plus optional ihre Funktion `details_<id>` für das Detailbild. Golden baut auf derselben Form auf.
- **Maße:** 2,08 × 2,06 × 1,84 Studs, Ursprung im Kugelmittelpunkt, wie `TowerShape` die Kugeln setzt. Die Unterseite sitzt mit dem Stapelabstand 1,5 über der Kuppel darunter, ohne in sie hineinzuschneiden. Die Lappen hängen über die untere Kugel.
- **Zwei Stufen:** LOD0 mit 448 Dreiecken für die Nähe, LOD1 mit 112 Dreiecken ab ca. 40 Studs Abstand zur Kamera. Der Client tauscht sie selbst (`ScoopModel`, `Config/TowerScoops` `farDistance`, mit 4 Studs Hysterese). Vergleich 308 gegen 448 Dreiecke: Mit 448 wird der Umriss der Kuppel sichtbar weicher, deshalb 448.
- **Umriss:** wie die Big Swirl in `#5A2E1A`, als **ein Highlight pro Turm** (Roblox zeigt höchstens 31 Highlights gleichzeitig). Beim Ächzen färbt es sich rot (`Palette.awning`). Fliegende Kugeln haben keinen Umriss, dafür eine Spur.
- **Im Turm** ist jede Kugel um 37° weiter gedreht als die darunter, damit die Lappen keine Streifen bilden.
- **Sorten-Details** (seit 29.10.2026): Jede Sorte muss auch ohne Farbe erkennbar sein. Die Details sind Muster im Detailbild (`details_<id>` in `build_scoops.py`, gemalt mit `blob`, `scatter`, `rim_band`), keine eigenen 3D-Teile. Einzige Ausnahme ist ein kleines Extra-Teil im selben Mesh (Zitronenscheibe, `extra_lemon_slice`), dessen Bild in einer eigenen Ecke über dem Bereich der Kugel liegt (`uv_top`). Raue oder extra glänzende Sorten bekommen zusätzlich eine RoughnessMap (`surface_roughness`).
  - Vanilla: feine Vanille-Punkte
  - Lemon (`#FFD84A`, kräftiger als zuerst, damit sie sich aus der Ferne von Vanilla abhebt): kurze Schalen-Streifen an der Seite und eine Zitronenscheibe oben (im Turm von der Kugel darüber verdeckt, die Streifen bleiben sichtbar)
  - Pistachio: große Nussstücke in zwei Grüntönen, hell und mit brauner Haut, leicht rau
  - Watermelon: schwarze Kerne, grüne Schale auf Rand und Tropfen mit heller Linie darüber
  - Chocolate: dunklerer Rand und Tropfen, extra glänzend
  - Strawberry: große rote Erdbeerstücke
  - Mint: dunkle, eckige Schoko-Splitter
  - Bubblegum: bunte Kaugummi-Kugeln mit Glanzpunkt
  - Cookie: eckige, dunkle Keksstücke und Krümel auf dunklerem Hellbraun
  - Mango: Mangowürfel mit heller Oberkante; gegen Lemon: Würfel statt Schalen-Streifen und Scheibe, Orange statt Gelb
  - Stracciatella: feine Schoko-Streifen rund um die Kugel (Vanilla hat Punkte)
- **Gleiche Form, kein Import:** Alle Sorten ohne Extra-Teil haben exakt die Grundform, Roblox legt dafür ohnehin nur ein Mesh an. `studio_setup.luau` übernimmt mit `SHAPE = "vanilla"` die Meshes von Vanilla und setzt nur Farbe und Detailbild. Importieren muss man nur eine Sorte mit eigener Form (Lemon).
- **Abstand zur Kugel darüber:** Die Unterkante der Tropfen liegt bei allen Sorten 0,86 unter dem Kugelmittelpunkt (`Config/TowerScoops` `dripDepth`). Daraus setzt das Spiel jede Kugel richtig, auch wenn oben etwas hinzukommt.

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

Materialien: `WSB_Vanilla` `#FFE7C0`, Roughness 0,42; `WSB_Ink` `#2B2D42`, Roughness 0,26. Das wärmere Creme weicht vom Palette-Token `vanilla` `#FFF3D6` ab, der im Licht fast weiß wirkt. Die Turm-Kugel Vanilla nutzt seit dem 29.10.2026 `#F9DCA8`, der Token bleibt für die Eis-Effekte (siehe oben).

Für den Prototyp gilt: Eine Kollisionskugel mit Radius 0,6 bleibt die Trefferform, das Mesh ist nur Optik. Das gilt auch für das finale Modell.

## Blender-Konventionen

- Arbeit in der Collection `WobbleScoops_Prototype`, Objekte mit Präfix `WS_`, Materialien mit Präfix `WS_`.
- 1 Blender-Einheit = 1 Stud. Die Import-Skalierung (FBX nach Roblox) beim ersten Export prüfen und hier festhalten.
- Ursprung jeder Kugel im Kugelmittelpunkt, wie im Spiel (`TowerVisual`).
- Modifier so lange wie möglich nicht anwenden, damit die Form editierbar bleibt.
- Polybudget pro Turm-Kugel (seit 29.10.2026): ca. 450 Dreiecke nah, ca. 100 fern (ab ca. 40 Studs). Die früheren Prototypen mit 1.500 bis 2.060 Dreiecken sind dafür zu schwer.
- Turm-Kugeln: Collection `TowerScoop_<sorte>`, Objekte `TS_<Sorte>_LOD0`/`_LOD1`, Materialien `TS_<sorte>`. FBX-Export mit denselben Einstellungen wie die Big Swirl (`FBX_SCALE_UNITS`, vorne -Z, oben Y), ohne Modifier (der Umriss in der Vorschau ist ein Modifier und kommt nicht mit).

## KI-Bilder

`concept.md` schließt KI-Bilder aus. Ausnahmen, vom Nutzer freigegeben: KI-Bilder **nur als interne Referenz** in der Konzeptphase (Higgsfield am 23.10.2026; seit dem 24.10.2026 ist das ChatGPT-Konzeptbild "Wobble Scoops Character Design" die einzige Stilreferenz, die Higgsfield-Versionen sind verworfen). Sie erscheinen nie im Spiel, in Thumbnails, im Icon oder auf der Spielseite.

## Offen

- Attack-Scoop-Modell vom externen Modeler: Lieferung abwarten, dann abnehmen und einbinden.
- Spätere Option "der Turm schreit beim Kippen": Turm-Kugeln bekommen nur in diesem Moment ein kurzes Panik-Gesicht oder einen anderen Panik-Effekt (Clip-Moment). Widerspricht derzeit "Turm-Kugeln ohne Gesicht" und braucht deshalb eine eigene Entscheidung.
- Import-Skalierung der Turm-Kugel nach Roblox: beim ersten Import von `vanilla_LOD0.fbx` prüfen (erwartet 2,08 × 1,84 × 2,06 Studs) und hier festhalten.
- Die übrigen 9 Sorten und Golden auf der Vanilla-Grundform (`FLAVORS` in `build_scoops.py`).
- Ob die Wurfkugel (`WSB_Vanilla` `#FFE7C0`) an das Creme der Turm-Kugel `#F9DCA8` angeglichen wird.
