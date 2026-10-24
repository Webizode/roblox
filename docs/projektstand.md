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

## 7. Technischer Stand (Repo, geprüft 24.10.2026)

- Repo: https://github.com/Webizode/roblox, Branch `claude/wobble-scoops-week1`, letzter Commit 23.10.2026
- ca. 10.000 Zeilen Luau, Client/Server/Shared sauber getrennt, Server-Autorität
- **113 Unit-Tests bestanden, 0 fehlgeschlagen**
- Vorhanden: Big Swirl Launcher, Fangen, Turmphysik mit Kippen, Steady-Haltung (F) mit Energie, Sprint (Shift), Dash (Q), Kampfmodus (R), Eisball-Wurf mit Ladeleiste, Munition, Nachladen, Treffer stören Turmbalance, Knockdown, Waffel-Rucksack, Servieren, Coins (nur Sitzung), Graybox-Pier, Kill-Test-Log
- Fehlt: Beute aufsammeln, Golden Glow, Emotionssystem, Sorten-Fähigkeiten, Events, Speichern (DataStore), Upgrade-Kauf, Sammelbuch, Block/Dodge
- Offene Punkte im Code: `debugCatch`, `debugThrow`, `debugDash` noch an; kleiner Exploit beim Steady-Bonus; Upgrades ohne Kaufweg
- **GitHub ist nicht der lokale Stand:** Animations-IDs, Quick/Power Dash, Hold-to-Aim und der Fix fürs Laufen außerhalb des Kampfmodus sind nicht im Repo. Lokalen Stand selbst committen und pushen

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
