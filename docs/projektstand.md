# Wobble Scoops: Projektstand und Entscheidungen

Stand: 24.10.2026 (Gespräch mit Claude). Diese Datei ist die aktuelle Hauptquelle. Sie ersetzt die ChatGPT-Zusammenfassung vom 24.10.2026, wo sie ihr widerspricht. Die verbindlichen Design-Regeln stehen zusätzlich in `docs/design-regeln.md`.

---

## 1. Was Wobble Scoops ist

Roblox-PvP-Spiel auf einem offenen Pier. Die Eismaschine **Big Swirl** schießt Eiskugeln. Spieler fangen sie und stapeln sie als **wackelnden Turm** in der Waffel auf ihrem Rücken. Zum Angreifen halten sie **lebendige Attack-Scoops** mit Gesicht, Fähigkeit und Emotionen in der Hand und **werfen** sie auf andere.

**Zwei verschiedene Kugel-Arten (nicht verwechseln):**
- **Turm-Kugeln:** werden gefangen und gestapelt, sind Beute und Wert. Kein Gesicht, keine Emotionen.
- **Attack-Scoops:** in der Hand, werden geworfen, haben Gesicht, Persönlichkeit, Emotionen und Sorten-Fähigkeit. Werden nicht gestapelt. Der Turm ist der Einsatz: Alles, was man trägt, kann einem weggeschossen werden. Sicher ist es erst nach dem **Servieren am eigenen Wagen**.

**In einem Satz:** Stapel hoch, wirf gut, bring deine Beute nach Hause, bevor dich jemand abschießt.

**Wichtige Korrektur zur ChatGPT-Version:** Es ist kein reines Wurf-/Kampfspiel mit 30–90-Sekunden-Runden. Das Kern-Verb im Code ist das Balancieren des Turms; PvP ist der Kern im Moment-zu-Moment-Spiel, der Turm ist das, worum gekämpft wird.

---

## 2. Getroffene Entscheidungen (24.10.2026)

| Thema | Entscheidung |
|---|---|
| Schwerpunkt | PvP zuerst im Spielgefühl, Sammeln als Grund zum Wiederkommen |
| Server-Modell | **Offener Server**, kein Matchmaking, keine Lobby |
| Arena-Gefühl | **Kurze Events** (ca. 3 Min.) alle paar Minuten, z. B. „Scoop Rush“, „höchster Turm gewinnt“ |
| Einsatz | Getragener Turm ist ungesichert, Servieren sichert |
| Beute | Verschüttete Kugeln anderer können eingesammelt werden (noch nicht gebaut) |
| Führende | Große Türme leuchten (Golden Glow) und werden zum Ziel |
| Fairness | 30 % (mind. 2) bleiben beim Kippen, 3 s Vorrang auf eigene Kugeln, Türme unter 5 Kugeln und Wagenbereich geschützt |
| Angriff | Einzige Angriffsaktion: Werfen. Kein Nahkampf |
| Sorten | Sidegrades mit Fähigkeiten, nie stärker. Kein Pay-to-Win |
| Scoops | Lebendig: Gesicht, Persönlichkeit, Emotionen, reagieren auf das Spiel |

---

## 3. Design-Regeln (Kurzfassung)

1. Der Turm ist dein Einsatz.
2. Wer hoch stapelt, wird gejagt.
3. Treffen fühlt sich stark an, getroffen werden fühlt sich fair an.
4. Verlieren tut weh, aber nie komplett.
5. Sorten sind anders, nicht stärker.
6. Smooth vor Features.
7. Die Scoops leben.
8. Bestehendes wird erweitert, nicht ersetzt.

---

## 4. Emotionssystem der Scoops

Ein gemeinsames System für alle Sorten (Ereignis → Emotion, Dauer, Priorität, alles in einer Config).

| Emotion | Auslöser | Wirkung |
|---|---|---|
| Freude / Jubel | Treffer, Knockdown, großer Turm serviert | nur Optik, andere sehen es |
| Wut | 2× kurz hintereinander getroffen oder Kugeln verloren | nächster Wurf ist „Wut-Wurf“ mit etwas mehr Turm-Stoß (Comeback, kein Schaden-Bonus) |
| Angst | eigener Turm ächzt oder kippt gleich | Warnsignal, Gesicht ist Teil der Anzeige |
| Überraschung | im Flug, kurz vor dem Aufprall | nur Optik |
| Splat | Aufprall | kurzes Zerquetschen, dann Effekt |
| Idle | länger nichts passiert | blinzeln, umschauen, wippen |

**Technik:**
- Gesichter als austauschbare Texturen (Augen und Mund getrennt), nicht ins Modell eingebacken
- 5–6 Ausdrücke reichen
- Squash and Stretch, Wippen, Zittern prozedural im Code, keine eigene Animation pro Sorte
- Pro Sorte nur Farbe, kleines Merkmal, Persönlichkeit, Sound
- Lesbar auf ca. 20 Studs und im Flug
- Gilt nur für die Attack-Scoops in der Hand, nicht für die Turm-Kugeln

---

## 5. Sorten-Startset

| Sorte | Fähigkeit | Persönlichkeit |
|---|---|---|
| Vanille | Allrounder, gerader Flug | freundlich, ausgeglichen |
| Erdbeere | springt einmal ab | verspielt, frech |
| Minze | verlangsamt kurz beim Treffer | cool, gelassen |
| Chili | mehr Turm-Stoß, weniger Reichweite | hitzköpfig, wird schnell wütend |

Weitere Sorten (Schoko, Blaubeere, Rainbow usw.) erst nach erfolgreichem Playtest.

---

## 6. Modell: Attack-Scoop (Vorgabe für den Modeler)

Der Attack-Scoop ist die lebendige Kugel in der Hand des Spielers, die geworfen wird. Er wird **nicht** gestapelt.

**Stil:** hochwertiger, glänzender Cartoon-Look wie im ChatGPT-Konzeptbild „Wobble Scoops Character Design“ (einzige Stilreferenz, Higgsfield-Versionen verworfen) (Richtung Pixar, Slime Rancher 2, Brawl Stars). Cremig, saftige Glanzlichter, satte Farben, viel Persönlichkeit. **Nicht** matt und nicht schlicht. So nah daran, wie Roblox es mit PBR-Materialien (Color, Roughness, Normal) hergibt.

**Muss:**
- Sitzt in einer kleinen Waffel-Schale wie im Konzeptbild (Entscheidung 24.10.2026: erlaubt, weil Attack-Scoops nicht gestapelt werden). Waffel fliegt beim Wurf mit, beim Aufprall Sahne und Waffelkrümel als VFX
- Rundlich, leicht squishy, dicke glänzende Schmelztropfen unten
- Große, glänzende Streusel
- Riesige glänzende Augen mit Glanzpunkt, ausdrucksstarker Mund, rosa Wangen
- Gesicht austauschbar (Augen und Mund getrennt), damit das Emotionssystem funktioniert
- Ausdrücke: Freude, Jubel, Wut, Angst, Überraschung, Splat
- Lesbar in der Hand und im Flug

**Technisch:**
- Roblox-kompatibel (MeshPart), optimierte Polygonzahl, PBR-Texturen
- Pivot in der Mitte, Gesicht nach vorn (LookVector)
- Größe in der Hand ca. 1,2 Studs
- Spur, Spritzer, Pfützen, Sorten-Auren sind VFX, nicht Teil des Modells

**Erste Lieferung:**
1. Vanille-Attack-Scoop mit kleiner Waffel
2. Gesichter für 6 Ausdrücke, austauschbar
3. Roblox-Datei plus Texturen
4. Vorschau aus mehreren Winkeln und einmal in Roblox Studio gerendert

Sorten (Erdbeere, Minze, Chili), Animationen und Partikel separat vereinbaren.

---

## 7. Technischer Stand (Repo, geprüft 28.10.2026)

- Repo: https://github.com/Webizode/roblox, Branch `claude/wobble-scoops-week1`, letzter Commit 28.10.2026
- ca. 14.000 Zeilen Luau, Client/Server/Shared sauber getrennt, Server-Autorität
- **193 Unit-Tests bestanden, 0 fehlgeschlagen**
- Vorhanden: Big Swirl Launcher, Fangen, Turmphysik mit Kippen, Steady-Haltung (F) mit Energie, Sprint (Shift), Dash (Q), Kampfmodus (R) mit eigener Lauf- und Idle-Animation, Eisball-Wurf mit Ladeleiste, Munition, Nachladen, Treffer stören Turmbalance, Knockdown, Beute (verschüttete Kugeln einsammeln), Waffel-Rucksack, Servieren, Kornels Insel als Map, Kill-Test-Log
- **Speichern** (seit 27.10.2026): ProfileStore mit Session-Lock. Gespeichert werden Coins, Upgrade-Stufen, servierte Kugeln pro Sorte, Kugeln gesamt, Rekord-Turm und die Einstellungen. Datenformat Version 2 mit Migration, alte Spielstände bekommen Standard-Einstellungen. Studio speichert getrennt, `/resetsave` setzt in Studio zurück
- **Einstellungsmenü** (seit 28.10.2026): Zahnrad oben links, am Gamepad Steuerkreuz hoch. Audio (Effekte, Musik), Grafik (VFX-Qualität, Leistungsmodus ohne Schatten, Bloom, Sonnenstrahlen), Kamera (Wackeln, Sichtfeld 70–110, Standard 80, Sprint-/Dash-/Ziel-Effekte), Fadenkreuz (Form, Größe, Farbe), Steuerung (Eingabegerät, Tastenübersicht im Kampf). Server prüft jeden Wert und speichert höchstens einmal pro Sekunde. Hintergrundmusik ist ein Platzhalter
- **Big Swirl** (seit 28.10.2026, Branch `feature/big-swirl`): neues Cartoon-Modell aus Blender (`assets/BigSwirl`, Skripte für Bau, Animation und Export, ca. 19.200 Dreiecke), Ø 52 Studs mit begehbarem Sockel, Treppen und Trog mit Eismischung, im Place unter `Workspace.Pier.BigSwirl`. Sechs Arme schöpfen aus dem Trog und schießen; jede Kugel kommt aus dem freien Arm, der in ihre Richtung zeigt, ein Arm wird erst nach seinem kompletten Zyklus wieder benutzt. Die Bewegung ist der in Blender animierte Zyklus (`Config/BigSwirlCycle`), jeder Client dreht damit die Bones selbst nach der Server-Uhr, ohne Animations-Assets. Die Kugel liegt ab dem Schöpfen sichtbar (1,8-fach) im Becher und schrumpft nach dem Abschuss; der Landekreis erscheint dadurch rund 2,3 s früher
- **Turm-Kugeln** (seit 29.10.2026): eigenes Modell statt der schlichten Kugel, erste Sorte Vanilla (Kuppel, Tropfrand mit 7 Lappen, hohle Unterseite zum Stapeln, Vanille-Punkte als Detailbild). Nah 448 Dreiecke, ab ca. 40 Studs die Fern-Version mit 112, getauscht vom Client. Ein Umriss-Highlight pro Turm in der Farbe der Big Swirl, rot beim Ächzen. Im Flug dreht sich die Kugel beim Steigen und kippt nach dem höchsten Punkt wie ein Federball mit der Kuppel nach unten; gefangen schwingt sie aufrecht und plumpst auf den Turm (die neue oberste Kugel fällt 0,7 Studs und staucht sich kurz). Dahinter eine kurze Spur in der Sortenfarbe, bei seltenen Sorten länger und heller, bei den seltensten mit Funken, kürzer bei niedriger VFX-Qualität und im Leistungsmodus. Nur Optik, die Flugbahn bleibt die des Servers. Werte in `Config/TowerScoops`, Logik in `ScoopFlight` (mit Tests), Modelle unter `ReplicatedStorage.TowerScoops` (Asset-Skripte und Ablauf: `assets/TowerScoops`, Art Bible). Sorten ohne Modell zeichnen weiter die schlichte Kugel
- **Sorten** (seit 29.10.2026): nur die 11 Common-Sorten (Familie Classic, Werte und Physik wie Vanilla, Gewicht je 10): Vanilla, Chocolate, Strawberry, Mint, Lemon, Bubblegum, Cookie, Pistachio, Mango, Stracciatella, Watermelon, alle mit eigenem Turm-Kugel-Modell. Feld `rarity` in `Config/Flavors` (common bis legendary, Farben in `rarityColors`). Die bisherigen seltenen Sorten (Rocky Road, Cookie Dough, Mochi, Jelly, Chili Lava, Cursed Pickle) sind am 29.10.2026 entfernt, ebenso die Rezepte, die sie brauchten (Secret Stacks Rocky Mountain und Pickle Party, Swirls Cookie Crunch, Rocky Mochi, Mint Jelly Fizz, Spicy Pickle). Es bleiben Neapolitan, Berry Swirl und Choco-Mint Twist. Die Familien heavy, sticky und wild bleiben für die neuen Sorten; die Physik-Tests nutzen dafür Test-Sorten
- **Liegengebliebene Kugeln** (seit 29.10.2026): Eine Kugel aus der Big Swirl, die niemand fängt, bleibt 3 s am Landepunkt liegen (`Config/Loot` `landedLifetime`), jeder darf sie aufheben, in der letzten Sekunde blinkt sie (`landedBlinkSeconds`), dann verpufft sie. Der Server entscheidet (`LootService.landed`, eigenes Limit `maxLanded`, verdrängt keine verschütteten Kugeln). Im Wasser ist sie sofort weg. Verschüttete Kugeln bleiben 15 s liegen (`lifetime`, seit 29.10.2026, vorher 12 s)
- **Namensschild** (seit 29.10.2026): über fliegenden und liegenden Kugeln „Name (Wert [Münze])“, Name in der Farbe der Seltenheit (`Config/Flavors` `rarityColors`), Münze wie im HUD (`Ui.coinIcon`), sichtbar bis 40 Studs (`Config/TowerScoops` `label`). Golden zeigt den Wert ×5 (`Config/Economy` `goldenMultiplier`), sobald der Launcher goldene Kugeln schickt. Nicht über Turm-Kugeln und nicht über der Wurfkugel
- **Zielwahl der Big Swirl** (seit 29.10.2026): Etwa 80 % der Kugeln landen an einem zufälligen Landepunkt in Arena und innerem Ring (bis 68 Studs von der Maschine: rosa Platz bis 62, Weg-Ring bis zum Fluss), der Rest (`nearPlayerShare` 0,2) bis 9 Studs neben einem Spieler, der in Bewegung ist. Wer sich 4 s lang nicht mehr als 2 Studs bewegt (`idleSeconds`, `idleRadius`), bekommt keine Kugeln gezielt. Die 3 Tutorial-Schüsse für neue Spieler bleiben. Nur Landepunkte, auf denen man stehen kann (wie bisher). Werte in `Config/Launcher`, Regeln in `TargetRules` (mit Tests). Vorher zielten 60 % auf einen beliebigen Spieler, auch einen stillstehenden
- **Kampfmodus-Maus** (seit 29.10.2026): Der Mauszeiger bleibt im Kampfmodus auch bei gehaltenem Rechtsklick versteckt und gesperrt; der Rechtsklick geht im Kampfmodus nicht mehr an Roblox' Kamera
- **Fadenkreuz und Perfect Timing** (seit 29.10.2026): Ein sauberer dünner Kreis, fest in der Bildschirmmitte (fest weiß, grün bei Perfect; seit 29.10.2026 keine Fadenkreuz-Einstellungen mehr, alte gespeicherte Werte werden ignoriert). Der Wurf zielt durch die Mitte; eigener Charakter, eigener Turm, Kugeln und Beute (`LocalVisuals`) stören weder das Zielen noch die Kamera. Der Kreis wird größer beim Gehen, Sprint, nach einem Dash und direkt nach dem Wurf und beim Halten etwas kleiner, nur Anzeige, keine Streuung (`AimRules`). Antippen wirft sofort (Stärke 0: 55 Studs/s, Trefferstärke ×0,6); Halten hebt die Stärke in 0,5 s auf 1 (90 Studs/s, ×1). Beim Halten pendelt ein innerer Kreis von der Mitte zum Außenkreis und zurück (`Combat.pulse`); wenn er den Außenkreis berührt (±0,06 s), wird alles grün, und Loslassen ist ein Perfect-Wurf: 110 Studs/s, gleiche Trefferstärke, eigener Sound, goldener Schweif für alle. Der Server prüft Stärke und Perfect mit seiner eigenen Haltezeit (±0,08 s). Der Wurf zielt immer genau durch die Mitte. Werte in `Config/Combat` (`perfect`, `crosshair`, `aimAssist`)
- **Treffer-Feedback** (seit 29.10.2026): rotes X am Kreis bei eigenem Treffer, rote Zahl der verlorenen Kugeln über dem Getroffenen, Feed mittig unten „YOU KNOCKED DOWN Name“ (eigener Treffer wirft um) und „YOU TOPPLED Name (+X)“ (Turm kippt höchstens 4 s nach dem eigenen Treffer, `feedback.creditSeconds`). Der Server ordnet zu (`CombatService.toppled`, Remote `HitFeedback`)
- **Knockdown-Fix** (seit 29.10.2026): Treffer zählten fast immer als Streifschuss, weil der Server als Abstand zur Körperachse den Punkt nahm, an dem der Ball in die Trefferzone eintrat (immer am Rand, ca. 2,4 von 2,8 Studs). Jetzt zählt die nächste Stelle der Flugbahn durch den Körper (`Combat.passDistance`). Dazu baut sich das Taumeln langsamer ab (`staggerDecay` 0,2 statt 0,6). Ergebnis, im Test mit 2 Spielern gemessen: zwei voll gehaltene Treffer auf die Mitte werfen um (Stärke 1,00 je Treffer), drei mittige Antipper ebenfalls beim dritten (0,60 je Treffer); ein einzelner Treffer, zwei Antipper oder seitliche Antipper nicht. Jeder Treffer wird mit `Features.debugThrow` auf dem Server protokolliert (Stärke, Abstand, Tempo, Taumeln)
- **Kamera-Empfindlichkeit** (seit 29.10.2026): im Einstellungsmenü unter Steuerung getrennt für Maus, Touch und Controller, 30–300 %, Standard 100 %, gespeichert und vom Server geprüft wie die anderen Einstellungen. Wirkt nur im Kampfmodus; die Kampfkamera dreht dafür jetzt auch auf Touch selbst (Wischen außerhalb von Schaltflächen). Außerhalb dreht Roblox' Kamera mit Roblox' eigener Einstellung
- **Zielhilfe** (seit 29.10.2026): in der Kampfkamera, Stärke nach dem gerade benutzten Gerät: Maus kaum spürbar, Controller mittel, Touch deutlich. Ist ein Gegner nah am Fadenkreuz (bis 8°, bis 120 Studs, sichtbar, nicht in seiner Schutzzone am Stand), dreht die Kamera dort langsamer und zieht sanft zu ihm hin; beides wird zum Rand hin schwächer, kein Einrasten, niemand hinter oder neben dem Fadenkreuz. Der Server prüft Treffer wie bisher. Werte in `Config/Combat` `aimAssist`, Logik in `AimRules`
- Offen (UI): Ein Designer baut das neue Hauptmenü und Einstellungsmenü. Mit seiner Datei wird das Menü neu gebaut (Design übernehmen, Script sauberer und flüssiger, alle Funktionen des alten Menüs). Bis dahin am Menü nichts umbauen
- Offen (Sorten): eigene seltenere Sorten des Nutzers (uncommon bis legendary) entwerfen, bauen und hinzufügen, mit eigener Form, Werten, Physik und Rezepten; dazu Golden. Die goldene Spur mit Glitzer ist fertig, der Launcher meldet goldene Kugeln aber erst mit `Features.goldenScoops`
- Hinweis Spielstand: Alte Spielstände können noch servierte Kugeln der entfernten Sorten enthalten (`flavorServes`). Sie bleiben gültig; ein späteres Sammelbuch muss unbekannte IDs überspringen
- Fehlt: Golden Glow, Emotionssystem, Sorten-Fähigkeiten, Events, Upgrade-Kauf (Shop), Sammelbuch, Cone Rank, Block/Dodge. Shop und Sammelbuch kommen erst nach der Big Swirl, mit einem komplett neuen Konzept; die alten Entwürfe sind verworfen (Branches am 29.10.2026 gelöscht)
- Offene Punkte im Code: `debugCatch`, `debugThrow`, `debugDash` noch an; kleiner Exploit beim Steady-Bonus; Einstellungen, die vor dem Laden des Spielstands geändert werden, gehen verloren
- Offen (Design): Seit dem Treffer-Tuning vom 25.10.2026 kippen drei schnelle volle Treffer auch den kleinsten Turm
- Offen (Design): Feuerrate der Big Swirl bleibt vorerst bei 1,5 s Grundtakt (`Config/Launcher.baseInterval`, mit mehr Spielern heute schon schneller: geteilt durch die Wurzel der Spielerzahl, höchstens alle 0,45 s). Mit der größeren Map neu an die Spielerzahl koppeln; die sechs Arme schaffen eine Kugel alle 0,5 s ohne schneller zu laufen

---

## 8. Reihenfolge

1. Lokalen Stand pushen
2. **Kill-Test** mit 2–3 Spielern gleichzeitig
3. Beute: verschüttete Kugeln anderer einsammeln
4. Golden Glow für große Türme
5. Emotionssystem mit Vanille
6. Erdbeere, Minze, Chili
7. Events
8. Speichern, Sammelbuch, Upgrades
9. Polish, UI, Monetarisierung (nur Kosmetik)

**Kill-Test bestanden, wenn:**
- Abschießen eines großen Turms sich gut anfühlt
- mind. 8 von 10 Stürzen sich fair oder selbstverschuldet anfühlen
- mind. 3 von 5 Testern freiwillig weiterspielen
- Tester das Spiel mit Verben wie „abschießen, stapeln, retten“ beschreiben

---

## 9. Team und Budget

- Budget ca. 150 € pro Monat, kleine klar abgegrenzte Aufgaben
- Vor jedem Auftrag schriftlich: Umfang, Lieferung, Zeitrahmen, Preis
- Kein Revenue Share ohne schriftliche Regeln
- **Bis zum bestandenen Kill-Test:** keine größeren Aufträge für Modelle, UI oder Animation
- Kontakte: Spooky Doggn Dog (3D, minderjährig, fragt nach Geschenkkarten: lieber nachvollziehbar über Robux/Roblox-Gruppe, klein anfangen, schriftlich festhalten), Kareem_op und Riccc (UI, später), Nick/Nik (Animation/VFX), Apex_pro45 (Generalist, Portfolio fehlt)

---

## 10. Arbeitsregeln für Claude Code

- Erst bestehende Architektur prüfen, dann gezielt ändern
- Funktionierende Systeme nicht ersetzen
- Keine automatischen Commits
- `lune run scripts/check` muss grün bleiben
- Neue Werte in die Configs, nicht hart in den Code
