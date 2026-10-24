# Art Bible Wobble Scoops

Stand: 23.10.2026. Die übergeordnete Art Direction steht in `docs/concept.md` unter "Art Direction und Anti-Slop" und gilt unverändert: Spielzeug-Pier zur goldenen Stunde, runde und klobige Formen (ca. 1,3-fach überzeichnet), SmoothPlastic ohne Texturen, Palette aus `src/shared/Config/Palette.luau`, Sorten unterscheiden sich auch über Silhouette und Material. Dieses Dokument hält die Entscheidungen zu einzelnen Assets fest.

## Signature-Scoop "Scoop-Buddy"

Entschieden am 23.10.2026 aus drei Konzepten:

| Konzept | Kern | Ergebnis |
|---|---|---|
| A Tropfkrone | Kugel mit dickem, welligem Tropfrand, kein Gesicht | Basis von B übernommen |
| **B Scoop-Buddy** | Form von A plus sparsames Ink-Gesicht, Ausdruck folgt dem Turm | **gewählt** |
| C Schöpfrolle | asymmetrische Kugel mit gerollter Lippe | verworfen: Asymmetrie stört das Lesen der Neigung, aufwendiger |

Bewertung:

| Kriterium | A | B | C |
|---|---|---|---|
| Silhouette | gut (Tropfrand) | gut (identisch zu A) | sehr eigenständig |
| Wiedererkennung | mittel | hoch (Gesicht, Ausdruck) | hoch |
| Lesbarkeit im Spiel (2 Studs, 15-30 Studs Abstand) | sehr gut | sehr gut, Gesicht nur aus der Nähe | Neigung schwerer lesbar |
| Animierbarkeit | Squash und Stretch | dazu Ausdruckswechsel | eingeschränkt |
| Umsetzung in Roblox | 1 MeshPart | 1 MeshPart plus Decal | 1 MeshPart, schwerer sauber |

Warum B: Der Ausdruck macht den Turm zur Figur. Wenn er ächzt, schauen 20 Kugeln gleichzeitig panisch, das ist der Clip-Moment ("der Turm schreit"). Das Gesicht ist ein Decal und ändert weder Mesh noch Stapelgeometrie, es lässt sich also jederzeit abschalten oder für LOD weglassen.

### Form

- Leicht gestauchte Kugel (Höhe ca. 0,92 der Breite), Radius im Spiel 1 Stud, Stapelradius 1,05 (siehe `Config/Launcher.luau`, `Backpack.luau`).
- Ein wulstiger Rand im unteren Drittel, darunter **7 Tropfen unterschiedlicher Länge**. Der Rand ist das Markenzeichen der Silhouette und muss auch ohne Gesicht und Farbe erkennbar sein.
- Unterhalb des Rands ist die Kugel eingezogen, damit sie in der Waffel und auf der Kugel darunter sitzt, ohne zu schweben.
- Keine Kleinteile unter ca. 0,15 Stud, sie verschwinden auf dem Handy.

### Gesicht

- Zwei Punktaugen und eine einzelne dicke, schräge Braue (Verwandtschaft zu Gregs schiefer Braue), kleiner Mund. Nur Ink `#2B2D42`.
- Das Gesicht sitzt auf der Vorderseite, leicht oberhalb der Mitte. Keine Glanzlichter, keine Wimpern, keine Wangen: Übertriebene Gesichter gelten in `concept.md` als Slop-Merkmal.
- Ausdrücke als austauschbare Decals: **ruhig** (grüner Ring), **besorgt** (gelb), **Panik** (Ächzen, rot). Weitere erst bei Bedarf.
- Im Prototyp ist das Gesicht aus kleinen Meshes nachgebaut, im Spiel wird es ein Decal.

### Material und Farbe

- Grundmaterial SmoothPlastic, in Blender als Principled BSDF mit Roughness ca. 0,45 vorbereitet. Farbe pro Sorte aus der Palette, keine Textur.
- Sorten-Unterschiede über Form und Material nach `concept.md` (Rocky Road klumpig, Mochi flach, Jelly aus Glass usw.). Der Prototyp ist Vanilla `#FFF3D6`.

### Prototyp (Stand 23.10.2026)

In `Documents\Modelle Wooble Scoops.blend`, Collection `WobbleScoops_Prototype`:

- `WS_SignatureScoop`: Empty bei (-4, 0, 0), Wurzel des Prototyps.
- `WS_Scoop_Body`: Kugel, Randwulst, Saum, 7 Tropfen und 5 Mini-Tropfen, verschmolzen über die Modifier Remesh (Voxel 0,04), Corrective Smooth und Decimate (0,055). Ergebnis ca. 1.530 Dreiecke, geschlossen (manifold), Maße 2,38 × 2,38 × 1,89. Modifier sind nicht angewendet.
- `WS_Scoop_Face`: Augen, Braue und Mund als Ink-Mesh (Platzhalter für das Decal), Ausdruck "ruhig".
- `WS_Preview_Key`, `WS_Preview_Fill`, `WS_Preview_Rim`: Vorschau-Lichter, nicht für den Export.
- Materialien `WS_Vanilla`, `WS_Ink`.

Geprüft: Mit dem Spiel-Abstand von 1,5 Studs zwischen den Kugeln (`Config/Tower.luau`, `scoopSpacing`) legt sich der Saum über die Kugel darunter, und deren Gesicht bleibt frei. Das Gesicht muss deshalb unterhalb von ca. 0,5 über der Kugelmitte bleiben. Aus ca. 22 Studs ist der Turm als Eis mit Figuren lesbar.

### Verfeinerung für Wobble und Hüpfen (Stand 23.10.2026)

Art Direction: Premium Cartoon, weich, elastisch, verspielt. Bewegung über Wobble und Hüpfen, keine Beine.

Collection `ScoopBuddy_Refinement`, das Original `WS_SignatureScoop` bleibt als Vergleich unverändert:

- `SB_Refined_Root`: Empty bei (-1,2, 0, -0,1), Standfläche auf dem Präsentationsboden.
- `SB_Refined_Body`: eine einzige Quad-Oberfläche statt Voxel-Remesh. 49 Segmente × 21 Ringe, 2.058 Dreiecke, geschlossen, Normalen außen, keine Selbstüberschneidung, keine Modifier.
- `SB_Refined_Face`: Kopie des Gesichts mit eigenen Mesh-Daten, unverändert.

Form:

- Kuppel exakt wie im Original (Ellipsoid 1,0 / 0,92), das Gesicht sitzt deshalb unverändert.
- Statt 7 unregelmäßiger Tropfen und 5 Mini-Tropfen jetzt **7 breite, runde Lappen** (Halbellipsen), Kante an Kante, links-rechts symmetrisch. Ein Lappen sitzt mittig unter dem Gesicht, damit vorne nie zwei Lappen wie Beine stehen. Rhythmus vorne lang, schräg vorne kurz, Seite lang, hinten mittel.
- Die Lappen enden auf Höhe einer flachen Standfläche, nicht darunter. Unter den Kerben ist der Sockel zurückgezogen und bildet eine weiche Schattenkerbe.
- Stauch- und Streck-Test (1,2/1,2/0,7 und 0,86/0,86/1,3): Die Form bleibt lesbar, und keine Falte bricht ein.

Vertex-Gruppen für das spätere Rig: `SB_Dome`, `SB_Rim`, `SB_Drips`, `SB_Base` (Bereiche) und `SB_Lobe_Front`, `SB_Lobe_FrontSide.L/.R`, `SB_Lobe_Side.L/.R`, `SB_Lobe_Back.L/.R` (Gewicht nimmt zum Lappenende zu, für Nachwackeln). .L ist +X, die linke Seite der Figur, die nach -Y schaut.

## Starter-Wurfkugel (Stand 23.10.2026)

Die Kugel mit Gesicht ist **keine Spielfigur** und wird **nicht gestapelt**. Der Spieler ist ein normaler R15-Character, hält die Kugel in der rechten Hand und wirft sie im Kampfmodus. Größe aus dem Code: `Config/Combat.luau`, `ballRadius = 0.6`. Kampfkamera 10,5 Studs hinter dem Spieler. Im Spiel ist die Kugel bisher ein Ball-Part aus Ice (`HeldBalls.luau`), das Modell ist noch nicht eingebunden.

Collection `ScoopBall_Throwable` (abgeleitet aus `SB_Refined_Body`, Original und Verfeinerung bleiben unverändert):

- `WSB_ThrowBall`: Empty, Ursprung = Kugelzentrum (Greif- und Drehpunkt).
- `WSB_Ball_Body`: 1,30 × 1,30 × 1,14 Studs, Kern exakt Radius 0,6 (Kollisionsradius), 1.932 Dreiecke, eine geschlossene Quad-Oberfläche, Normalen außen, keine Modifier, Skalierung 1. Material `WSB_Vanilla`.
- `WSB_Ball_Face`: eigenes Objekt mit demselben Ursprung, 4 geschlossene Teile (2 Augen, Braue, Mund), 888 Dreiecke. Material `WSB_Ink`.
- `WSB_QC_Key/Fill/Rim/Bounce`: Kontrolllichter für die Abnahme, nicht für den Export.

Form: rund aus jeder Richtung, weil die Kugel im Flug rotiert. Weicher Randwulst, darunter 7 kurze, runde Tropfen, die über die Kugelkontur hinausragen und weich ineinander übergehen. Unterseite rund, keine Standfläche. Leicht handgeformt: Rand minimal schräg, Tropfen nicht exakt gleich lang, sanfte Dellen in der Kuppel, um das Gesicht herum ausgeblendet.

Gesicht: größere, leicht ovale Augen, eine kräftige, hochgezogene Braue (selbstbewusst), Grinsen mit hochgezogenem rechtem Mundwinkel (frech). Aus 10,5 Studs lesbar.

Materialien nur mit Eigenschaften, die Roblox auch kann: `WSB_Vanilla` `#FFE7C0`, Roughness 0,42; `WSB_Ink` `#2B2D42`, Roughness 0,26. Das wärmere Creme weicht vom Palette-Token `vanilla` `#FFF3D6` ab, der im Licht fast weiß wirkt. Ob der Token angepasst wird, ist offen.

Export nach Roblox, offen:

1. UVs anlegen (beide Meshes haben noch keine).
2. Gesicht: Roblox zeigt pro MeshPart nur eine Farbe. Entweder zwei MeshParts (Körper und Gesicht, gleicher Ursprung, verschweißt) oder das Gesicht in eine Textur backen und als `SurfaceAppearance` auf einen einzigen MeshPart legen. Für eine Wurfkugel ist eine einzige MeshPart mit Textur die robustere Lösung.
3. FBX-Export und Import-Skalierung prüfen (Ziel: Kern 1,2 Studs Durchmesser).
4. Eine Kollisionskugel mit Radius 0,6 bleibt die Trefferform; das Mesh ist nur Optik.
5. `HeldBalls.luau` und der geflogene Ball müssen das Modell statt des Ball-Parts nutzen (Code, nicht Teil dieser Aufgabe).

## Blender-Konventionen

- Arbeit in der Collection `WobbleScoops_Prototype`, Objekte mit Präfix `WS_`, Materialien mit Präfix `WS_`.
- 1 Blender-Einheit = 1 Stud. Die Import-Skalierung (FBX nach Roblox) beim ersten Export prüfen und hier festhalten.
- Ursprung jeder Kugel im Kugelmittelpunkt, wie im Spiel (`TowerVisual`).
- Modifier so lange wie möglich nicht anwenden, damit die Form editierbar bleibt.
- Polybudget pro Kugel: ca. 1.500 Dreiecke, da bis zu 40 pro Turm und 10 Türme pro Server. Die verfeinerte Wobble-Form liegt bei ca. 2.060, weil runde Lappen und eine weiche Randfalte mehr Ringe brauchen. Für Türme ist eine LOD-Stufe mit ca. 800 Dreiecken nötig (gleiche Segmentzahl halbieren).

## KI-Bilder

`concept.md` schließt KI-Bilder aus. Ausnahme, vom Nutzer am 23.10.2026 freigegeben: Higgsfield-Bilder **nur als interne Referenz** in der Konzeptphase. Sie erscheinen nie im Spiel, in Thumbnails, im Icon oder auf der Spielseite.

## Offen

- Import-Skalierung und Export-Einstellungen nach Roblox.
- Ausdrucks-Decals zeichnen (ruhig, besorgt, Panik), am besten von Hand wie die Kreide-Decals.
- Varianten für die übrigen Sorten erst nach Abnahme der Vanilla-Form.
- Für den Export: Modifier anwenden (auf einer Kopie), Gesicht weglassen, UVs für das Decal anlegen.
